import SwiftUI
import Foundation
import WebKit
import UIKit

enum ExternalHTTPDefaults {
    static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    static let acceptLanguage = "en-US,en;q=0.9"
    static let acceptImages = "image/avif,image/webp,image/apng,image/*,*/*;q=0.8"
}

enum ExternalHTTP {
    static let kun8MediaHosts: [String] = [
        "nerv.8kun.top"
    ]

    static func candidateURLs(for url: URL) -> [URL] {
        guard let host = url.host, kun8MediaHosts.contains(host) else { return [url] }

        var result: [URL] = [url]
        for altHost in kun8MediaHosts where altHost != host {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { continue }
            components.host = altHost
            if let altURL = components.url { result.append(altURL) }
        }
        return result
    }

    static func request(url: URL, accept: String? = nil) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpShouldHandleCookies = true

        request.setValue(ExternalHTTPDefaults.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(ExternalHTTPDefaults.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }

        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            let fields = HTTPCookie.requestHeaderFields(with: cookies)
            for (k, v) in fields { request.setValue(v, forHTTPHeaderField: k) }
        }

        return request
    }
}

struct HeaderAsyncImage<Content: View>: View {
    let url: URL?
    let userAgent: String
    let acceptLanguage: String
    let accept: String?
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    init(
        url: URL?,
        userAgent: String = ExternalHTTPDefaults.userAgent,
        acceptLanguage: String = ExternalHTTPDefaults.acceptLanguage,
        accept: String? = ExternalHTTPDefaults.acceptImages,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.userAgent = userAgent
        self.acceptLanguage = acceptLanguage
        self.accept = accept
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            await MainActor.run { phase = .empty }
            return
        }

        await MainActor.run { phase = .empty }

        var lastError: Error?
        for candidateURL in ExternalHTTP.candidateURLs(for: url) {
            if Task.isCancelled { return }
            do {
                var request = ExternalHTTP.request(url: candidateURL, accept: accept)
                request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
                guard let uiImage = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }

                try Task.checkCancellation()
                await MainActor.run { phase = .success(Image(uiImage: uiImage)) }
                return
            } catch {
                lastError = error
                continue
            }
        }

        if Task.isCancelled { return }
        await MainActor.run { phase = .failure(lastError ?? URLError(.unknown)) }
    }
}

// URL builder for external media rules used by this file
enum ExternalMediaURLBuilder {
    static func normalizeExt(_ ext: String?) -> String {
        let raw = (ext ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix(".") { return String(raw.dropFirst()).lowercased() }
        return raw.lowercased()
    }

    static func mediaItems(site: SiteDirectory.Site, board: String, post: ExternalPost) -> [MediaItem] {
        if let files = post.files, !files.isEmpty {
            return files.compactMap { file in
                guard let full = url(site: site, pathOrURLString: file.path),
                      let thumb = url(site: site, pathOrURLString: file.thumb)
                else { return nil }
                return MediaItem(fullURL: full, thumbURL: thumb, mime: file.mime)
            }
        }

        var candidates: [(mediaKey: String, ext: String?, fpath: Int?)] = []

        if let key = post.mediaKey ?? post.tim.map({ String($0) }) {
            candidates.append((mediaKey: key, ext: post.ext, fpath: post.fpath))
        }

        if let attachments = post.attachments, !attachments.isEmpty {
            for a in attachments {
                candidates.append((mediaKey: a.mediaKey, ext: a.ext, fpath: a.fpath))
            }
        }

        var out: [MediaItem] = []
        out.reserveCapacity(candidates.count)

        for c in candidates {
            let extNoDot = normalizeExt(c.ext)
            if extNoDot.isEmpty { continue }
            if let full = vichanFullURL(site: site, board: board, tim: c.mediaKey, extNoDot: extNoDot, fpath: c.fpath),
               let thumb = vichanThumbURL(site: site, board: board, tim: c.mediaKey, extNoDot: extNoDot, fpath: c.fpath, spoiler: false).thumbnail
            {
                out.append(MediaItem(fullURL: full, thumbURL: thumb))
            }
        }

        if out.isEmpty { return [] }
        var seen: Set<String> = []
        var unique: [MediaItem] = []
        unique.reserveCapacity(out.count)
        for item in out {
            if seen.insert(item.fullURL.absoluteString).inserted {
                unique.append(item)
            }
        }
        return unique
    }

    static func mediaItem(site: SiteDirectory.Site, board: String, thread: ExternalThread) -> MediaItem? {
        if let files = thread.files, let first = files.first {
            guard let full = url(site: site, pathOrURLString: first.path),
                  let thumb = url(site: site, pathOrURLString: first.thumb)
            else { return nil }
            return MediaItem(fullURL: full, thumbURL: thumb, mime: first.mime)
        }

        guard let key = thread.mediaKey ?? thread.tim.map({ String($0) }) else { return nil }
        let extNoDot = normalizeExt(thread.ext)
        if extNoDot.isEmpty { return nil }
        let fpath = thread.fpath
        guard let full = vichanFullURL(site: site, board: board, tim: key, extNoDot: extNoDot, fpath: fpath),
              let thumb = vichanThumbURL(site: site, board: board, tim: key, extNoDot: extNoDot, fpath: fpath, spoiler: false).thumbnail
        else { return nil }
        return MediaItem(fullURL: full, thumbURL: thumb)
    }

    static func thumbnailURL(site: SiteDirectory.Site, board: String, thread: ExternalThread, preferSpoiler: Bool) -> URL? {
        if site.id == "8kun" {
            let fpath = thread.fpath
            let key = thread.mediaKey ?? thread.tim.map({ String($0) })
            guard let tim = key else { return nil }
            let extNoDot = normalizeExt(thread.ext)
            let pair = kun8ThumbURL(board: board, tim: tim, extNoDot: extNoDot, fpath: fpath, spoiler: preferSpoiler)
            return preferSpoiler ? pair.spoilerThumbnail : pair.thumbnail
        }

        return mediaItem(site: site, board: board, thread: thread)?.thumbURL
    }

    static func thumbnailURL(site: SiteDirectory.Site, board: String, post: ExternalPost, preferSpoiler: Bool) -> URL? {
        if let files = post.files, let first = files.first {
            return url(site: site, pathOrURLString: first.thumb)
        }

        var key = post.mediaKey ?? post.tim.map({ String($0) })
        var ext = post.ext
        var fpath = post.fpath

        if (key == nil || normalizeExt(ext).isEmpty), let first = post.attachments?.first {
            key = first.mediaKey
            ext = first.ext
            fpath = first.fpath
        }

        guard let tim = key else { return nil }
        let extNoDot = normalizeExt(ext)
        if extNoDot.isEmpty { return nil }

        if site.id == "8kun" {
            let pair = kun8ThumbURL(board: board, tim: tim, extNoDot: extNoDot, fpath: fpath, spoiler: preferSpoiler)
            return preferSpoiler ? pair.spoilerThumbnail : pair.thumbnail
        }

        return vichanThumbURL(site: site, board: board, tim: tim, extNoDot: extNoDot, fpath: fpath, spoiler: false).thumbnail
    }

    static func fullURL(site: SiteDirectory.Site, board: String, post: ExternalPost) -> URL? {
        if let files = post.files, let first = files.first {
            return url(site: site, pathOrURLString: first.path)
        }

        var key = post.mediaKey ?? post.tim.map({ String($0) })
        var ext = post.ext
        var fpath = post.fpath

        if (key == nil || normalizeExt(ext).isEmpty), let first = post.attachments?.first {
            key = first.mediaKey
            ext = first.ext
            fpath = first.fpath
        }

        guard let key else { return nil }
        let extNoDot = normalizeExt(ext)
        if extNoDot.isEmpty { return nil }
        return vichanFullURL(site: site, board: board, tim: key, extNoDot: extNoDot, fpath: fpath)
    }

    // MARK: - Site-specific URL rules

    private static func url(site: SiteDirectory.Site, pathOrURLString: String) -> URL? {
        if let absolute = URL(string: pathOrURLString), absolute.scheme != nil {
            return absolute
        }
        return URL(string: pathOrURLString, relativeTo: site.baseURL)
    }

    private static func vichanFullURL(site: SiteDirectory.Site, board: String, tim: String, extNoDot: String, fpath: Int?) -> URL? {
        if site.id == "8kun" {
            return kun8FullURL(board: board, tim: tim, extNoDot: extNoDot, fpath: fpath)
        }
        if site.id == "7chan" {
            return URL(string: "https://7chan.org/\(board)/src/\(tim).\(extNoDot)")
        }
        return URL(string: "\(site.baseURL.absoluteString)\(board)/src/\(tim).\(extNoDot)")
    }

    private static func vichanThumbURL(site: SiteDirectory.Site, board: String, tim: String, extNoDot: String, fpath: Int?, spoiler: Bool) -> (thumbnail: URL?, spoilerThumbnail: URL?) {
        if site.id == "8kun" {
            return kun8ThumbURL(board: board, tim: tim, extNoDot: extNoDot, fpath: fpath, spoiler: spoiler)
        }
        if site.id == "7chan" {
            let thumbExt: String
            switch extNoDot.lowercased() {
            case "jpeg", "jpg", "png", "gif", "webp":
                thumbExt = extNoDot.lowercased()
            default:
                thumbExt = "jpg"
            }
            return (URL(string: "https://7chan.org/\(board)/thumb/\(tim)s.\(thumbExt)"), nil)
        }
        return (URL(string: "\(site.baseURL.absoluteString)\(board)/thumb/\(tim)s.jpg"), nil)
    }

    private static func kun8FullURL(board: String, tim: String, extNoDot: String, fpath: Int?) -> URL? {
        let f = fpath ?? 1
        if f == 1 {
            return URL(string: "https://nerv.8kun.top/file_store/\(tim).\(extNoDot)")
        } else {
            return URL(string: "https://nerv.8kun.top/\(board)/src/\(tim).\(extNoDot)")
        }
    }

    private static func kun8ThumbURL(board: String, tim: String, extNoDot: String, fpath: Int?, spoiler: Bool) -> (thumbnail: URL?, spoilerThumbnail: URL?) {
        let spoilerURL = URL(string: "https://nerv.8kun.top/static/assets/\(board)/spoiler.png")
        if spoiler { return (spoilerURL, spoilerURL) }
        let thumbExt: String
        switch extNoDot.lowercased() {
        case "jpeg", "jpg", "png", "gif": thumbExt = extNoDot.lowercased()
        default: thumbExt = "jpg"
        }
        let f = fpath ?? 1
        if f == 1 {
            return (URL(string: "https://nerv.8kun.top/file_store/thumb/\(tim).\(thumbExt)"), spoilerURL)
        } else {
            return (URL(string: "https://nerv.8kun.top/\(board)/thumb/\(tim).\(thumbExt)"), spoilerURL)
        }
    }
}

struct ExternalThreadListView: View {
    let site: SiteDirectory.Site
    let boardCode: String
    let boardTitle: String

    @State private var threads: [ExternalThread] = []
    @State private var loadErrorMessage: String? = nil
    @State private var blockedURL: URL? = nil
    @State private var isGridView: Bool = false
    // Search threads
    @State private var searchText: String = ""
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isSearchVisible: Bool = false
    @ObservedObject private var settings = AppSettings.shared

    private var threadTint: Color { .chanNSFW }
    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var filteredThreads: [ExternalThread] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return threads }
        return threads.filter { thread in
            if String(thread.no).contains(query) { return true }
            if let sub = thread.sub, cleanHTML(sub).lowercased().contains(query) { return true }
            if let com = thread.com, cleanHTML(com).lowercased().contains(query) { return true }
            return false
        }
    }

    var body: some View {
        Group {
            if isGridView {
                gridBody
            } else {
                listBody
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: isSearchVisible ? .always : .automatic), prompt: "Search threads")
        .focused($isSearchFieldFocused)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(site.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("/\(boardCode)/")
                        .font(.headline)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isGridView.toggle()
                } label: {
                    Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        isSearchVisible.toggle()
                        if isSearchVisible {
                            isSearchFieldFocused = true
                        } else {
                            searchText = ""
                            isSearchFieldFocused = false
                        }
                    }) {
                        Label("Search", systemImage: "magnifyingglass")
                    }

                    Button(action: loadCatalog) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .onAppear { loadCatalog() }
        .sheet(item: $blockedURL) { url in
            CloudflareClearanceInlineView(url: url) {
                blockedURL = nil
                loadCatalog()
            }
        }
    }

    @ViewBuilder
    private var listBody: some View {
        List {
            if let message = loadErrorMessage, threads.isEmpty {
                Section {
                    loadErrorMessageCard(for: message)
                }
            }

            ForEach(filteredThreads, id: \.no) { thread in
                NavigationLink(destination: ExternalThreadDetailView(site: site, boardCode: boardCode, threadNo: thread.no)) {
                    ExternalThreadRow(site: site, board: boardCode, thread: thread)
                }
                .listRowBackground(threadTint.opacity(0.20))
            }
        }
        .listStyle(.plain)
        .environment(\.dynamicTypeSize, settings.adjustedDynamicType)
        .scrollContentBackground(.hidden)
        .background(threadTint.opacity(0.12))
        .refreshable { loadCatalog() }
    }

    private var gridBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let message = loadErrorMessage, threads.isEmpty {
                    loadErrorMessageCard(for: message)
                        .padding(.horizontal, 4)
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(10)
                }

                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(filteredThreads, id: \.no) { thread in
                        ExternalThreadGridCell(site: site, board: boardCode, thread: thread)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(10)
        }
        .background(threadTint.opacity(0.12))
        .environment(\.dynamicTypeSize, settings.adjustedDynamicType)
        .refreshable { loadCatalog() }
    }

    @ViewBuilder
    private func loadErrorMessageCard(for message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button("Retry") { loadCatalog() }
                Button("Fix access") {
                    blockedURL = site.baseURL
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func loadCatalog() {
        self.threads = []
        self.loadErrorMessage = nil
        VichanCatalogAPI.fetchCatalog(site: site, boardCode: boardCode) { result in
            switch result {
            case .success(let fetched):
                DispatchQueue.main.async { self.threads = fetched }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.threads = []
                    self.loadErrorMessage = "Failed to load catalog: \(error.localizedDescription)"
                    if site.id == "7chan",
                       let nsError = error as NSError?,
                       nsError.domain == "VichanCatalogAPI",
                       nsError.code == -4
                    {
                        blockedURL = catalogHTMLURL()
                    }
                }
                print("Failed to load external catalog: \(error)")
            }
        }
    }

    private func catalogHTMLURL() -> URL {
        var url = site.baseURL
        if url.absoluteString.hasSuffix("/") == false { url.appendPathComponent("") }
        url.appendPathComponent("\(boardCode)/catalog.html")
        return url
    }
}

private func externalThreadThumbnailURL(site: SiteDirectory.Site, board: String, thread: ExternalThread, preferSpoiler: Bool = false) -> URL? {
    ExternalMediaURLBuilder.thumbnailURL(site: site, board: board, thread: thread, preferSpoiler: preferSpoiler)
}

private struct ExternalThreadGridCell: View {
    let site: SiteDirectory.Site
    let board: String
    let thread: ExternalThread

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var youPostsManager = YouPostsManager.shared

    private var thumbURL: URL? {
        externalThreadThumbnailURL(site: site, board: board, thread: thread)
    }

    private var thumbnailHeight: CGFloat {
        let base = CGFloat(150) * settings.thumbnailScale
        return min(max(base, 120), 220)
    }

    private var hasYou: Bool {
        youPostsManager.isYouThread(siteID: site.id, boardID: board, threadNo: thread.no)
    }

    private var youUnread: Int {
        hasYou ? youPostsManager.unreadForThread(siteID: site.id, boardID: board, threadNo: thread.no) : 0
    }

    var body: some View {
        NavigationLink(destination: ExternalThreadDetailView(site: site, boardCode: board, threadNo: thread.no)) {
            VStack(alignment: .leading, spacing: 0) {
                if let url = thumbURL {
                    HeaderAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        default:
                            Color.gray.opacity(0.3)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: thumbnailHeight, maxHeight: thumbnailHeight)
                    .clipped()
                } else {
                    Color.gray.opacity(0.3)
                        .frame(height: thumbnailHeight)
                }

                VStack(alignment: .leading, spacing: 4 * settings.density.spacingMultiplier) {
                    HStack {
                        Text("No. \(thread.no.formatted(.number.grouping(.never)))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        if hasYou {
                            Text(youUnread > 0 ? "You \(youUnread)" : "You")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.10))
                                .clipShape(Capsule())
                        }
                    }

                    if let subject = thread.sub {
                        Text(cleanHTML(subject))
                            .font(.headline)
                            .lineLimit(2)
                            .foregroundColor(.primary)
                    }
                    if let comment = thread.com {
                        Text(cleanHTML(comment))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }

                    HStack {
                        if settings.showReplyCounts, let replies = thread.replies {
                            Text("R: \(replies)")
                        }
                        Spacer()
                        if settings.showImageCounts, let images = thread.images {
                            Text("I: \(images)")
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(.gray)
                }
                .padding(8)
                .background(Color(UIColor.systemBackground))
            }
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

struct ExternalThreadRow: View {
    @State private var blockedURL: URL? = nil
    @State private var reloadToken: UUID? = nil
    @State private var useSpoilerThumb: Bool = false

    let site: SiteDirectory.Site
    let board: String
    let thread: ExternalThread
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var youPostsManager = YouPostsManager.shared

    private func thumbnailURL() -> URL? {
        externalThreadThumbnailURL(site: site, board: board, thread: thread, preferSpoiler: useSpoilerThumb)
    }

    private func urlWithReloadToken(_ url: URL) -> URL {
        guard let token = reloadToken?.uuidString, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: "r", value: token))
        comps.queryItems = items
        return comps.url ?? url
    }

    var body: some View {
        let hasYou = youPostsManager.isYouThread(siteID: site.id, boardID: board, threadNo: thread.no)
        let youUnread = hasYou ? youPostsManager.unreadForThread(siteID: site.id, boardID: board, threadNo: thread.no) : 0

        HStack(alignment: .top, spacing: 10 * settings.density.spacingMultiplier) {
            if let url = thumbnailURL() {
                HeaderAsyncImage(url: urlWithReloadToken(url)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error != nil {
                        ZStack {
                            Color.gray.opacity(0.3)
                            VStack(spacing: 6) {
                                if site.id == "8kun" {
                                    Button("Try spoiler thumb") {
                                        if !useSpoilerThumb { useSpoilerThumb = true; reloadToken = UUID() }
                                    }
                                }
                                Button("Fix access") {
                                    let host = url.host ?? site.baseURL.host ?? "localhost"
                                    blockedURL = URL(string: "https://\(host)/")
                                }
                                .font(.caption)
                            }
                            .padding(4)
                        }
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(width: CGFloat(80) * settings.thumbnailScale, height: CGFloat(80) * settings.thumbnailScale)
                .cornerRadius(4)
                .clipped()
                .overlay(alignment: Alignment.bottomTrailing) {
                    let ext = (thread.ext ?? "").replacingOccurrences(of: ".", with: "").lowercased()
                    let isVideo = (ext == "webm" || ext == "mp4") || (thread.files?.first?.mime?.lowercased().hasPrefix("video/") == true)
                    if isVideo {
                        Image(systemName: "video.fill")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                            .padding(2)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 5 * settings.density.spacingMultiplier) {
                if let subject = thread.sub, !subject.isEmpty {
                    Text(cleanHTML(subject))
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let comment = thread.com, !comment.isEmpty {
                    Text(cleanHTML(comment))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                }
                HStack {
                    Text("No. \(thread.no.formatted(.number.grouping(.never)))")
                    if hasYou {
                        Text(youUnread > 0 ? "You \(youUnread)" : "You")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.10))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    if let replies = thread.replies { Text("R: \(replies)") }
                    if let images = thread.images { Text("I: \(images)") }
                }
                .font(.caption2)
                    .foregroundColor(.gray)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4 * settings.density.spacingMultiplier)
        .background(Color(UIColor.secondarySystemBackground).opacity(0.85))
        .sheet(item: $blockedURL) { url in
            CloudflareClearanceInlineView(url: url) {
                blockedURL = nil
                reloadToken = UUID()
            }
        }
    }
}

struct ExternalThreadWebDetail: View {
    let site: SiteDirectory.Site
    let boardCode: String
    let threadNo: Int

    var body: some View {
        SiteBoardsWebView(site: SiteDirectory.Site(id: site.id, displayName: site.displayName, baseURL: site.baseURL.appendingPathComponent("\(boardCode)/res/\(threadNo).html"), kind: site.kind))
            .navigationTitle("No. \(threadNo.formatted(.number.grouping(.never)))")
    }
}

struct ExternalThreadDetailView: View {
    let site: SiteDirectory.Site
    let boardCode: String
    let threadNo: Int
    @State private var posts: [ExternalPost] = []
    @State private var mediaItems: [MediaItem] = []
    @State private var selectedImageIndex: Int? = nil
    @State private var showGallery: Bool = false
    @State private var loadErrorMessage: String? = nil
    @State private var blockedURL: URL? = nil
    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @ObservedObject private var youPostsManager = YouPostsManager.shared
    @ObservedObject private var historyManager = HistoryManager.shared
    @State private var showQuoteCopiedToast = false
    @State private var quoteCopiedText = ""
    @State private var highlightedPostNo: Int? = nil
    @State private var repliesIndex: [Int: [Int]] = [:]
    @State private var firstNewPostNo: Int? = nil
    // Search posts
    @State private var searchText: String = ""
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isSearchVisible: Bool = false
    // Jump to bottom/top
    @State private var listProxy: ScrollViewProxy? = nil
    private var threadTint: Color { .chanNSFW }
    @ObservedObject private var settings = AppSettings.shared

    private var isFavorite: Bool {
        favoritesManager.isFavorite(siteID: site.id, boardID: boardCode, threadNo: threadNo)
    }

    private var filteredPosts: [ExternalPost] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return posts }
        return posts.filter { post in
            if String(post.no).contains(query) { return true }
            if let sub = post.sub, cleanHTML(sub).lowercased().contains(query) { return true }
            if let com = post.com, cleanHTML(com).lowercased().contains(query) { return true }
            if let name = post.name, name.lowercased().contains(query) { return true }
            return false
        }
    }

    var body: some View {
        let threadTitle = inferredTitle()
        ZStack {
            ScrollViewReader { proxy in
                List {
                    if let message = loadErrorMessage {
                        Section {
                            threadLoadErrorCard(message: message)
                        }
                    }
                    ForEach(filteredPosts, id: \.no) { post in
                        if post.no == firstNewPostNo {
                            NewPostsDividerRow()
                                .listRowInsets(EdgeInsets())
                        }

                        let postReplies = repliesIndex[post.no] ?? []
                        let isHighlighted = (highlightedPostNo == post.no)
                        let isOP = post.no == (posts.first?.no ?? post.no)

                        ExternalPostRow(
                            site: site,
                            boardID: boardCode,
                            threadNo: threadNo,
                            post: post,
                            replies: postReplies,
                            imageTapped: { url in
                                rebuildMediaList()
                                if let idx = mediaItems.firstIndex(where: { $0.fullURL == url }) {
                                    selectedImageIndex = idx
                                }
                            },
                            highlighted: isHighlighted,
                            copyQuote: { copyQuote($0) },
                            attributedComment: { attributedComment(from: $0) },
                            isOP: isOP,
                            threadTitle: threadTitle
                        )
                        .id(post.no)
                        .listRowBackground(threadTint.opacity(0.20))
                    }
                }
                .onAppear { listProxy = proxy }
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: isSearchVisible ? .always : .automatic), prompt: "Search posts")
                .focused($isSearchFieldFocused)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "quote",
                       let host = url.host,
                       let targetNo = Int(host) {
                        withAnimation {
                            proxy.scrollTo(targetNo, anchor: .top)
                            highlightedPostNo = targetNo
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if highlightedPostNo == targetNo {
                                highlightedPostNo = nil
                            }
                        }
                        return .handled
                    }
                    return .systemAction
                })
            }
        }
        .background(threadTint.opacity(0.12))
        .navigationTitle("Thread \(threadNo.formatted(.number.grouping(.never)))")
        .onAppear { loadThread() }
        .onChange(of: posts.count) { _ in
            buildRepliesIndex()
            rebuildMediaList()
        }
        .sheet(isPresented: Binding(get: { selectedImageIndex != nil }, set: { if !$0 { selectedImageIndex = nil } })) {
            if let idx = selectedImageIndex {
                ImageBrowser(media: mediaItems, currentIndex: idx, isPresented: Binding(get: { selectedImageIndex != nil }, set: { if !$0 { selectedImageIndex = nil } }), onBack: nil)
            } else { EmptyView() }
        }
        .sheet(isPresented: $showGallery) {
            GalleryView(mediaItems: mediaItems, onSelect: { idx in
                selectedImageIndex = idx
                showGallery = false
            })
        }
        .sheet(item: $blockedURL) { url in
            CloudflareClearanceInlineView(url: url) {
                blockedURL = nil
                loadErrorMessage = nil
                loadThread()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundColor(isFavorite ? .yellow : .gray)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        isSearchVisible.toggle()
                        if isSearchVisible {
                            isSearchFieldFocused = true
                        } else {
                            searchText = ""
                            isSearchFieldFocused = false
                        }
                    }) {
                        Label("Search", systemImage: "magnifyingglass")
                    }

                    Button(action: { showGallery = true }) {
                        Label("Gallery", systemImage: "photo.on.rectangle.angled")
                    }

                    Button(action: loadThread) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    if firstNewPostNo != nil {
                        Button(action: jumpToNewPosts) {
                            Label("Jump to New Posts", systemImage: "arrow.down.to.line")
                        }
                    }

                    Button(action: jumpToBottom) {
                        Label("Jump to Bottom", systemImage: "arrow.down.to.line")
                    }
                    Button(action: jumpToTop) {
                        Label("Jump to Top", systemImage: "arrow.up.to.line")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                        .padding(6)
                }
            }
        }
        .overlay(alignment: .top) {
            if showQuoteCopiedToast {
                Text("Copied \(quoteCopiedText)")
                    .font(.caption.bold())
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showQuoteCopiedToast)
        .environment(\.dynamicTypeSize, settings.adjustedDynamicType)
    }

    private func copyQuote(_ postNo: Int) {
        let quote = ">>\(postNo)"
        UIPasteboard.general.string = quote
        quoteCopiedText = quote
        showQuoteCopiedToast = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            showQuoteCopiedToast = false
        }
    }

    private func attributedComment(from raw: String) -> AttributedString {
        let cleaned = cleanHTML(raw)
        var result = AttributedString()

        let linkPattern = #">>(\d+)"#
        let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: [])
        let urlDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

        let lines = cleaned.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            let isGreentext = line.hasPrefix(">") && !line.hasPrefix(">>")

            let nsLine = line as NSString
            let matches = linkRegex?.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)) ?? []
            var currentLocation = 0

            for match in matches {
                let range = match.range
                if range.location > currentLocation {
                    let beforeRange = NSRange(location: currentLocation, length: range.location - currentLocation)
                    let beforeText = nsLine.substring(with: beforeRange)
                    result.append(linkifyPlainText(beforeText, detector: urlDetector, defaultColor: isGreentext ? .green : nil))
                }

                if match.numberOfRanges >= 2 {
                    let numberRange = match.range(at: 1)
                    let numberStr = nsLine.substring(with: numberRange)
                    var linkPart = AttributedString(nsLine.substring(with: range))
                    linkPart.link = URL(string: "quote://\(numberStr)")
                    linkPart.foregroundColor = .blue
                    result.append(linkPart)
                } else {
                    let partText = nsLine.substring(with: range)
                    result.append(linkifyPlainText(partText, detector: urlDetector, defaultColor: isGreentext ? .green : nil))
                }

                currentLocation = range.location + range.length
            }

            if currentLocation < nsLine.length {
                let tailRange = NSRange(location: currentLocation, length: nsLine.length - currentLocation)
                let tailText = nsLine.substring(with: tailRange)
                result.append(linkifyPlainText(tailText, detector: urlDetector, defaultColor: isGreentext ? .green : nil))
            }

            if index < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }

        return result
    }

    private func linkifyPlainText(_ text: String, detector: NSDataDetector?, defaultColor: Color?) -> AttributedString {
        guard let detector else {
            var out = AttributedString(text)
            if let defaultColor { out.foregroundColor = defaultColor }
            return out
        }

        let ns = text as NSString
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else {
            var out = AttributedString(text)
            if let defaultColor { out.foregroundColor = defaultColor }
            return out
        }

        var result = AttributedString()
        var currentLocation = 0

        for m in matches {
            guard let url = m.url else { continue }
            let range = m.range
            if range.location > currentLocation {
                let beforeRange = NSRange(location: currentLocation, length: range.location - currentLocation)
                var before = AttributedString(ns.substring(with: beforeRange))
                if let defaultColor { before.foregroundColor = defaultColor }
                result.append(before)
            }

            var linkPart = AttributedString(ns.substring(with: range))
            linkPart.link = url
            linkPart.foregroundColor = .blue
            result.append(linkPart)

            currentLocation = range.location + range.length
        }

        if currentLocation < ns.length {
            let tailRange = NSRange(location: currentLocation, length: ns.length - currentLocation)
            var tail = AttributedString(ns.substring(with: tailRange))
            if let defaultColor { tail.foregroundColor = defaultColor }
            result.append(tail)
        }

        return result
    }

    private func loadThread() {
        loadErrorMessage = nil
        VichanThreadAPI.fetchThread(site: site, boardCode: boardCode, threadNo: threadNo) { result in
            switch result {
            case .success(let fetched):
                DispatchQueue.main.async {
                    loadErrorMessage = nil
                    let replyCount = max(0, fetched.count - 1)
                    let historyLast = historyManager.history.first(where: { $0.siteID == site.id && $0.boardID == boardCode && $0.threadNo == threadNo })?.lastReplyCount
                    let favLast = favoritesManager.favorites.first(where: { $0.siteID == site.id && $0.boardID == boardCode && $0.threadNo == threadNo })?.lastReplyCount
                    let lastSeen = [historyLast, favLast].compactMap { $0 }.max() ?? replyCount
                    if replyCount > lastSeen, fetched.indices.contains(lastSeen + 1) {
                        firstNewPostNo = fetched[lastSeen + 1].no
                    } else {
                        firstNewPostNo = nil
                    }

                    self.posts = fetched
                    self.buildRepliesIndex()
                    self.rebuildMediaList()

                    YouPostsManager.shared.clearUnreadForThread(siteID: site.id, boardID: boardCode, threadNo: threadNo)
                    HistoryManager.shared.add(siteID: site.id, boardID: boardCode, threadNo: threadNo, title: inferredTitle(), tim: nil, replyCount: replyCount)
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    print("Failed to load external thread: \(error)")
                    self.posts = []
                    self.mediaItems = []
                    self.loadErrorMessage = "Failed to load thread: \(error.localizedDescription)"
                    self.repliesIndex = [:]
                    self.firstNewPostNo = nil
                    if site.id == "7chan",
                       let nsError = error as NSError?,
                       nsError.domain == "VichanThreadAPI",
                       nsError.code == -4 {
                        blockedURL = threadHTMLURL()
                    }
                }
            }
        }
    }

    private func threadHTMLURL() -> URL {
        var url = site.baseURL
        if url.absoluteString.hasSuffix("/") == false { url.appendPathComponent("") }
        url.appendPathComponent("\(boardCode)/res/\(threadNo).html")
        return url
    }

    @ViewBuilder
    private func threadLoadErrorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                Button("Retry") { loadThread() }
                if site.id == "7chan" {
                    Button("Fix access") {
                        blockedURL = threadHTMLURL()
                    }
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func rebuildMediaList() {
        mediaItems = posts.flatMap { ExternalMediaURLBuilder.mediaItems(site: site, board: boardCode, post: $0) }
    }

    private func buildRepliesIndex() {
        let pattern = #">>(\d+)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        var out: [Int: Set<Int>] = [:]

        for post in posts {
            guard let raw = post.com else { continue }
            let cleaned = cleanHTML(raw)
            let ns = cleaned as NSString
            let matches = regex?.matches(in: cleaned, options: [], range: NSRange(location: 0, length: ns.length)) ?? []
            for m in matches {
                if m.numberOfRanges >= 2 {
                    let r = m.range(at: 1)
                    if r.location != NSNotFound, let target = Int(ns.substring(with: r)) {
                        out[target, default: []].insert(post.no)
                    }
                }
            }
        }

        repliesIndex = out.mapValues { Array($0).sorted() }
    }

    private func jumpToNewPosts() {
        guard let target = firstNewPostNo else { return }
        withAnimation { listProxy?.scrollTo(target, anchor: .top) }
    }

    private func jumpToBottom() {
        guard let last = posts.last?.no else { return }
        withAnimation { listProxy?.scrollTo(last, anchor: .bottom) }
    }

    private func jumpToTop() {
        guard let first = posts.first?.no else { return }
        withAnimation { listProxy?.scrollTo(first, anchor: .top) }
    }

    private func toggleFavorite() {
        if isFavorite {
            favoritesManager.remove(siteID: site.id, boardID: boardCode, threadNo: threadNo)
            return
        }

        let title = inferredTitle()
        let preview = inferredPreview()
        favoritesManager.add(
            siteID: site.id,
            boardID: boardCode,
            threadNo: threadNo,
            title: title,
            mediaKey: preview?.mediaKey,
            ext: preview?.ext,
            fpath: preview?.fpath
        )
    }

    private func inferredTitle() -> String {
        let op = posts.first
        let subject = (op?.sub ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !subject.isEmpty { return subject }

        let comment = cleanHTML(op?.com ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !comment.isEmpty { return comment }

        return "Thread \(threadNo)"
    }

    private struct Preview {
        let mediaKey: String
        let ext: String
        let fpath: Int?
    }

    private func inferredPreview() -> Preview? {
        for post in posts {
            if let key = post.mediaKey?.trimmingCharacters(in: .whitespacesAndNewlines),
               let ext = post.ext?.trimmingCharacters(in: .whitespacesAndNewlines),
               !key.isEmpty, !ext.isEmpty
            {
                return Preview(mediaKey: key, ext: ext, fpath: post.fpath)
            }
            if let att = post.attachments?.first,
               !att.mediaKey.isEmpty,
               let ext = att.ext?.trimmingCharacters(in: .whitespacesAndNewlines),
               !ext.isEmpty
            {
                return Preview(mediaKey: att.mediaKey, ext: ext, fpath: att.fpath)
            }
        }
        return nil
    }
}

struct ExternalPostRow: View {
    @State private var blockedURL: URL? = nil
    @State private var reloadToken: UUID? = nil
    @State private var useSpoilerThumb: Bool = false

    let site: SiteDirectory.Site
    let boardID: String
    let threadNo: Int
    let post: ExternalPost
    let replies: [Int]
    let imageTapped: (URL) -> Void
    let highlighted: Bool
    let copyQuote: (Int) -> Void
    let attributedComment: (String) -> AttributedString
    let isOP: Bool
    let threadTitle: String?

    @Environment(\.openURL) private var openURL
    @State private var showRepliesPopover = false
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var youPostsManager = YouPostsManager.shared

    private func urlWithReloadToken(_ url: URL) -> URL {
        guard let token = reloadToken?.uuidString, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: "r", value: token))
        comps.queryItems = items
        return comps.url ?? url
    }

    @ViewBuilder
    private func thumbView(item: MediaItem) -> some View {
        let resolvedThumb: URL? = {
            if useSpoilerThumb, site.id == "8kun" {
                return URL(string: "https://nerv.8kun.top/static/assets/\(boardID)/spoiler.png")
            }
            return item.thumbURL
        }()

        if let thumbURL = resolvedThumb {
            HeaderAsyncImage(url: urlWithReloadToken(thumbURL)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else if phase.error != nil {
                    ZStack {
                        Color.gray.opacity(0.3)
                        VStack(spacing: 6) {
                            if site.id == "8kun" {
                                Button("Try spoiler thumb") {
                                    if !useSpoilerThumb { useSpoilerThumb = true; reloadToken = UUID() }
                                }
                            }
                            Button("Fix access") {
                                let host = thumbURL.host ?? site.baseURL.host ?? "localhost"
                                blockedURL = URL(string: "https://\(host)/")
                            }
                            .font(.caption)
                        }
                        .padding(4)
                    }
                } else {
                    Color.gray.opacity(0.3)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if item.isVideo {
                    Image(systemName: "video.fill")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        .padding(2)
                }
            }
            .onTapGesture { imageTapped(item.fullURL) }
        } else {
            Color.gray.opacity(0.3)
        }
    }

    var body: some View {
        let media = ExternalMediaURLBuilder.mediaItems(site: site, board: boardID, post: post)
        let thumbSize = CGFloat(60) * settings.thumbnailScale

        HStack(alignment: .top, spacing: 10 * settings.density.spacingMultiplier) {
            if !media.isEmpty {
                if media.count == 1, let first = media.first {
                    thumbView(item: first)
                        .frame(width: thumbSize, height: thumbSize)
                        .cornerRadius(4)
                        .clipped()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6 * settings.density.spacingMultiplier) {
                            ForEach(media) { item in
                                thumbView(item: item)
                                    .frame(width: thumbSize, height: thumbSize)
                                    .cornerRadius(4)
                                    .clipped()
                            }
                        }
                    }
                    .frame(height: thumbSize)
                }
            }
            VStack(alignment: .leading, spacing: 4 * settings.density.spacingMultiplier) {
                HStack(spacing: 8 * settings.density.spacingMultiplier) {
                    Text(post.name ?? "Anonymous")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.red)
                    Text("No. \(post.no.formatted(.number.grouping(.never)))")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .contentShape(Rectangle())
                        .onTapGesture { copyQuote(post.no) }
                        .onLongPressGesture(minimumDuration: 0.35) {
                            youPostsManager.toggleYou(
                                siteID: site.id,
                                boardID: boardID,
                                threadNo: threadNo,
                                postNo: post.no,
                                threadTitle: threadTitle,
                                tim: nil,
                                knownReplies: replies
                            )
                        }
                        .contextMenu {
                            Button { copyQuote(post.no) } label: {
                                Label("Copy Quote", systemImage: "doc.on.doc")
                            }
                            Button {
                                youPostsManager.toggleYou(
                                    siteID: site.id,
                                    boardID: boardID,
                                    threadNo: threadNo,
                                    postNo: post.no,
                                    threadTitle: threadTitle,
                                    tim: nil,
                                    knownReplies: replies
                                )
                            } label: {
                                let isYou = youPostsManager.isYou(siteID: site.id, boardID: boardID, threadNo: threadNo, postNo: post.no)
                                Label(isYou ? "Unmark (You)" : "Mark (You)", systemImage: isYou ? "person.fill.badge.minus" : "person.fill.badge.plus")
                            }
                        }

                    if youPostsManager.isYou(siteID: site.id, boardID: boardID, threadNo: threadNo, postNo: post.no) {
                        Text("(You)")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.blue)
                    }

                    Spacer()

                    HStack(spacing: 8 * settings.density.spacingMultiplier) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text(Date(timeIntervalSince1970: TimeInterval(post.time)), style: .relative)
                        }

                        if !replies.isEmpty {
                            Button { showRepliesPopover = true } label: {
                                let count = replies.count
                                Text("\(count) repl\(count == 1 ? "y" : "ies")")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.borderless)
                            .popover(isPresented: $showRepliesPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Replies to No. \(post.no.formatted(.number.grouping(.never)))")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    Divider()
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 8) {
                                            ForEach(replies, id: \.self) { replyNo in
                                                Button {
                                                    showRepliesPopover = false
                                                    if let url = URL(string: "quote://\(replyNo)") { _ = openURL(url) }
                                                } label: {
                                                    Text(">>\(replyNo.formatted(.number.grouping(.never)))")
                                                        .font(.body)
                                                        .foregroundColor(.blue)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                    .frame(maxHeight: 240)
                                }
                                .padding(12)
                                .frame(maxWidth: 260, alignment: .leading)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                if let subject = post.sub, !subject.isEmpty {
                    Text(cleanHTML(subject))
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let filename = post.filename, let fsize = post.fsize, let ext = post.ext {
                    Text("\(filename)\(ext) • \(formatFileSize(fsize))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }

                if let com = post.com {
                    Text(attributedComment(com))
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
        .background(highlighted ? Color.yellow.opacity(0.15) : Color.clear)
        .background(settings.highlightOP && isOP ? Color.blue.opacity(0.06) : Color.clear)
        .sheet(item: $blockedURL) { url in
            CloudflareClearanceInlineView(url: url) {
                blockedURL = nil
                reloadToken = UUID()
            }
        }
    }

    private func formatFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

private struct NewPostsDividerRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.red).frame(height: 1)
            Text("New Posts")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.red)
            Rectangle().fill(Color.red).frame(height: 1)
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
    }
}

// Minimal inline Cloudflare clearance WebView for this screen
struct CloudflareClearanceInlineView: UIViewRepresentable {
    let url: URL
    let onCleared: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onCleared: onCleared) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: config)
        web.customUserAgent = ExternalHTTPDefaults.userAgent
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: url))
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCleared: () -> Void
        init(onCleared: @escaping () -> Void) { self.onCleared = onCleared }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let host = webView.url?.host ?? ""
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let relevant = cookies.filter { cookie in
                    let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    return !host.isEmpty && host.hasSuffix(domain)
                }

                relevant.forEach { HTTPCookieStorage.shared.setCookie($0) }
                CookieBridge.shared.update(with: relevant)

                let hasClearance = relevant.contains { $0.name.lowercased() == "cf_clearance" }
                let hasLynxchanBypass = relevant.contains { cookie in
                    let n = cookie.name.lowercased()
                    return n == "captchaid" || n == "bypass" || n == "extracookie"
                }
                if hasClearance || hasLynxchanBypass { self.onCleared() }
            }
        }
    }
}
