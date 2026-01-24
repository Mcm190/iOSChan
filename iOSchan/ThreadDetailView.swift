import SwiftUI
import Foundation
import Photos
import UIKit

struct ThreadDetailView: View {
    let boardID: String
    let threadNo: Int
    // Indicates whether this thread was opened from an archived listing
    let isArchived: Bool
    let isSFWOverride: Bool?

    @State private var posts: [Thread] = []
    @State private var selectedImageIndex: Int? = nil
    @State private var mediaItems: [MediaItem] = []
    @State private var showGallery: Bool = false
    @ObservedObject var favoritesManager = FavoritesManager.shared
    @ObservedObject var historyManager = HistoryManager.shared
    // Search
    @State private var searchText: String = ""
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isSearchVisible: Bool = false

    // Open in Safari (thread page for replying / posting)
    @State private var showSafariThread = false
    @State private var showReplyComposer = false

    // Quote copy toast
    @State private var showQuoteCopiedToast = false
    @State private var quoteCopiedText = ""
    // Download Manager States
    @State private var isDownloadingAll = false
    @State private var downloadStatusMessage = ""
    @State private var showDownloadAlert = false
    @State private var downloadProgressCurrent: Int = 0
    @State private var downloadProgressTotal: Int = 0
    @State private var highlightedPostNo: Int? = nil
    @State private var repliesIndex: [Int: [Int]] = [:]
    @State private var firstNewPostNo: Int? = nil
    @State private var listProxy: ScrollViewProxy? = nil
    @Environment(\.openURL) private var openURL
    @ObservedObject private var settings = AppSettings.shared

    private var threadURL: URL {
        URL(string: "https://boards.4chan.org/\(boardID)/thread/\(threadNo)")!
    }
    
    private var boardTheme: BoardColors.Theme { BoardColors.theme(for: boardID, isSFW: isSFWOverride) }

    var body: some View {
        ZStack {
            // Main list
            ScrollViewReader { proxy in
                List {
                    ForEach(filteredPosts, id: \.no) { post in
                        if post.no == firstNewPostNo {
                            NewPostsDividerRow(accent: boardTheme.accent)
                                .listRowInsets(EdgeInsets())
                        }

                        // Break complex expressions into locals to help the compiler
                        let postReplies = repliesIndex[post.no] ?? []
                        let isHighlighted = (highlightedPostNo == post.no)
                        let isOP = post.no == (posts.first?.no ?? post.no)

                        PostRowView(
                            boardID: boardID,
                            threadNo: threadNo,
                            post: post,
                            replies: postReplies,
                            resolvePost: { no in posts.first(where: { $0.no == no }) },
                                imageTapped: { url in
                                    rebuildMediaList()
                                    if let idx = mediaItems.firstIndex(where: { $0.fullURL == url }) {
                                        selectedImageIndex = idx
                                    }
                                },
                            highlighted: isHighlighted,
                            copyQuote: { copyQuote($0) },
                            attributedComment: { attributedComment(from: $0) },
                            isOP: isOP
                            , isArchived: isArchived
                            , threadTitle: inferredThreadTitle
                            , opTim: opTim
                            , theme: boardTheme
                        )
                        .id(post.no)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowBackground(boardTheme.surface)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
            .navigationTitle("Thread \(threadNo.formatted(.number.grouping(.never)))")
                .onAppear { loadPosts() }
            .onChange(of: posts.count) { _ in
                buildRepliesIndex()
                rebuildMediaList()
            }

            // Image Browser
            .sheet(isPresented: Binding(get: { selectedImageIndex != nil }, set: { if !$0 { selectedImageIndex = nil } })) {
                if let idx = selectedImageIndex {
                    ImageBrowser(media: mediaItems, currentIndex: idx, isPresented: Binding(get: { selectedImageIndex != nil }, set: { if !$0 { selectedImageIndex = nil } }), onBack: {
                        // Close browser and re-open gallery
                        selectedImageIndex = nil
                        showGallery = true
                    })
                } else {
                    EmptyView()
                }
            }

            .sheet(isPresented: $showGallery) {
                GalleryView(mediaItems: mediaItems, onSelect: { idx in
                    selectedImageIndex = idx
                    showGallery = false
                })
            }

            // Toolbar Actions: collapsed into ellipsis menu
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            isSearchVisible.toggle()
                            if isSearchVisible {
                                isSearchFieldFocused = true
                            }
                        }) {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                        Button(action: { showGallery = true }) {
                            Label("Gallery", systemImage: "photo.on.rectangle.angled")
                        }
                        if firstNewPostNo != nil {
                            Button(action: jumpToNewPosts) {
                                Label("Jump to New Posts", systemImage: "arrow.down.to.line")
                            }
                        }
                        Button(action: loadPosts) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        if !isArchived {
                            Button(action: { showReplyComposer = true }) {
                                Label("Reply", systemImage: "arrowshape.turn.up.left.fill")
                            }
                        }
                        Button(action: { showSafariThread = true }) {
                            Label("Open in Safari", systemImage: "safari")
                        }
                        Button(action: downloadAllImagesToFiles) {
                            Label("Download All", systemImage: "arrow.down.circle.fill")
                        }
                        Button(action: toggleFavorite) {
                            Label(favoritesManager.isFavorite(boardID: boardID, threadNo: threadNo) ? "Unfavorite" : "Favorite", systemImage: favoritesManager.isFavorite(boardID: boardID, threadNo: threadNo) ? "star.fill" : "star")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .padding(6)
                    }
                }
            }

            // Download progress overlay
            if isDownloadingAll {
                Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                VStack(spacing: 12) {
                    Text("Downloading images")
                        .font(.headline)
                    ProgressView(value: Double(downloadProgressCurrent), total: Double(downloadProgressTotal))
                        .progressViewStyle(.linear)
                    Text("Image \(downloadProgressCurrent) of \(downloadProgressTotal)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(20)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 10)
            }
        }
        .background(boardTheme.background)
        .toolbarBackground(boardTheme.surface.opacity(0.6), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        // Open thread in Safari (for replying / posting)
        .sheet(isPresented: $showSafariThread) {
            SafariView(url: threadURL)
        }
        .sheet(isPresented: $showReplyComposer, onDismiss: { loadPosts() }) {
            PostComposerNative(boardID: boardID, threadNo: threadNo, threadTitle: inferredThreadTitle, opTim: opTim)
        }
        // Quote copied toast overlay
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

        // Alerts
        .alert("Download Complete", isPresented: $showDownloadAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(downloadStatusMessage)
        }
    }

    // MARK: - Helpers

    private var inferredThreadTitle: String? {
        guard let first = posts.first else { return nil }
        let subject = (first.sub ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !subject.isEmpty { return cleanHTML(subject) }
        let comment = cleanHTML(first.com ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return comment.isEmpty ? nil : comment
    }

    private var opTim: Int? { posts.first?.tim }

    func copyQuote(_ postNo: Int) {
        let quote = ">>\(postNo)"
        UIPasteboard.general.string = quote
        quoteCopiedText = quote
        showQuoteCopiedToast = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            showQuoteCopiedToast = false
        }
    }

    func formatFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    func loadPosts() {
        FourChanAPI.shared.fetchThreadDetails(board: boardID, threadNo: threadNo) { result in
            switch result {
            case .success(let fetchedPosts):
                DispatchQueue.main.async {
                    let replyCount = max(0, fetchedPosts.count - 1)
                    let historyLast = historyManager.history.first(where: { $0.siteID == "4chan" && $0.boardID == boardID && $0.threadNo == threadNo })?.lastReplyCount
                    let favLast = favoritesManager.favorites.first(where: { $0.siteID == "4chan" && $0.boardID == boardID && $0.threadNo == threadNo })?.lastReplyCount
                    let lastSeen = [historyLast, favLast].compactMap { $0 }.max() ?? replyCount
                    if replyCount > lastSeen, fetchedPosts.indices.contains(lastSeen + 1) {
                        firstNewPostNo = fetchedPosts[lastSeen + 1].no
                    } else {
                        firstNewPostNo = nil
                    }

                    self.posts = fetchedPosts
                    self.buildRepliesIndex()

                    // ✅ NEW: clear unread + update lastReplyCount when viewing the thread
                    FavoritesManager.shared.markSeen(
                        boardID: boardID,
                        threadNo: threadNo,
                        replyCount: replyCount
                    )

                    // Clear (You) unread counters for this thread when viewing it.
                    YouPostsManager.shared.clearUnreadForThread(boardID: boardID, threadNo: threadNo)

                    // Record to history (use OP title or first comment)
                    let firstPost = fetchedPosts.first
                    let title = firstPost?.sub ?? cleanHTML(firstPost?.com ?? "Thread \(threadNo)")
                    HistoryManager.shared.add(boardID: boardID, threadNo: threadNo, title: title, tim: firstPost?.tim, replyCount: replyCount)

                    // Rebuild media list for gallery/browser
                    rebuildMediaList()
                }

            case .failure(let error):
                DispatchQueue.main.async {
                    // Only mark dead when API explicitly reports 404
                    if let apiErr = error as? APIError, case .notFound = apiErr {
                        FavoritesManager.shared.markDead(boardID: boardID, threadNo: threadNo)
                        HistoryManager.shared.markDead(boardID: boardID, threadNo: threadNo)
                    }
                }
                print("Error: \(error)")
            }
        }
    }


    func cleanHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // Build media item list for the current posts (includes images and videos)
    func rebuildMediaList() {
        mediaItems = posts.compactMap { post in
            guard let tim = post.tim else { return nil }
            let fileExt = post.ext ?? ".jpg"
            let fullURL = URL(string: "https://i.4cdn.org/\(boardID)/\(tim)\(fileExt)")
            let thumbURL = URL(string: "https://i.4cdn.org/\(boardID)/\(tim)s.jpg")
            if let fullURL, let thumbURL {
                return MediaItem(fullURL: fullURL, thumbURL: thumbURL)
            }
            return nil
        }
    }

    func attributedComment(from raw: String) -> AttributedString {
        let cleaned = cleanHTML(raw)
        var result = AttributedString()

        let linkPattern = #">>(\d+)"#
        let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: [])
        let urlDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

        let lines = cleaned.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            // Greentext: line starts with '>' but not '>>'
            let isGreentext = line.hasPrefix(">") && !line.hasPrefix(">>")

            let nsLine = line as NSString
            let matches = linkRegex?.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)) ?? []
            var currentLocation = 0

            for match in matches {
                let range = match.range
                // Append text before the match
                if range.location > currentLocation {
                    let beforeRange = NSRange(location: currentLocation, length: range.location - currentLocation)
                    let beforeText = nsLine.substring(with: beforeRange)
                    result.append(linkifyPlainText(beforeText, detector: urlDetector, defaultColor: isGreentext ? .green : nil))
                }

                // Append the link segment (>>12345)
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

            // Append the tail after the last match
            if currentLocation < nsLine.length {
                let tailRange = NSRange(location: currentLocation, length: nsLine.length - currentLocation)
                let tailText = nsLine.substring(with: tailRange)
                result.append(linkifyPlainText(tailText, detector: urlDetector, defaultColor: isGreentext ? .green : nil))
            }

            // Re-insert newline separators (except after last line)
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

    private func jumpToNewPosts() {
        guard let target = firstNewPostNo else { return }
        withAnimation { listProxy?.scrollTo(target, anchor: .top) }
    }

    func buildRepliesIndex() {
        // Build a reverse index: targetPostNo -> [replyingPostNos]
        var temp: [Int: Set<Int>] = [:]
        let pattern = #">>(\d+)"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])

        for post in posts {
            guard let raw = post.com else { continue }
            let cleaned = cleanHTML(raw)
            let ns = cleaned as NSString
            let matches = regex?.matches(in: cleaned, options: [], range: NSRange(location: 0, length: ns.length)) ?? []
            for match in matches {
                if match.numberOfRanges >= 2 {
                    let r = match.range(at: 1)
                    if r.location != NSNotFound, let target = Int(ns.substring(with: r)) {
                        temp[target, default: []].insert(post.no)
                    }
                }
            }
        }

        var finalized: [Int: [Int]] = [:]
        for (k, set) in temp {
            finalized[k] = Array(set).sorted()
        }

        self.repliesIndex = finalized
    }

    func toggleFavorite() {
        if favoritesManager.isFavorite(boardID: boardID, threadNo: threadNo) {
            favoritesManager.remove(boardID: boardID, threadNo: threadNo)
        } else {
            let firstPost = posts.first
            let title = firstPost?.sub ?? cleanHTML(firstPost?.com ?? "Thread \(threadNo)")
            let tim = firstPost?.tim
            favoritesManager.add(boardID: boardID, threadNo: threadNo, title: title, tim: tim)
        }
    }

    // Filter posts by `searchText` (case-insensitive)
    var filteredPosts: [Thread] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return posts }
        return posts.filter { post in
            if let sub = post.sub, cleanHTML(sub).lowercased().contains(query) { return true }
            if let com = post.com, cleanHTML(com).lowercased().contains(query) { return true }
            return false
        }
    }

    // MARK: - Download Logic

    func downloadAllImagesToFiles() {
        isDownloadingAll = true
        downloadStatusMessage = "Starting..."

        Task {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "ddMMyyyy"
            let dateString = dateFormatter.string(from: Date())
            let folderName = "(\(boardID.uppercased())-\(threadNo.formatted(.number.grouping(.never)))-\(dateString))"

            do {
                guard let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    throw NSError(domain: "App", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find Documents directory"])
                }

                let destinationFolderUrl = documentsUrl.appendingPathComponent(folderName)

                if !FileManager.default.fileExists(atPath: destinationFolderUrl.path) {
                    try FileManager.default.createDirectory(at: destinationFolderUrl, withIntermediateDirectories: true)
                }

                let imagePosts = posts.filter { $0.tim != nil }
                let totalCount = imagePosts.count
                await MainActor.run {
                    downloadProgressCurrent = 0
                    downloadProgressTotal = totalCount
                    downloadStatusMessage = "Downloading image 0 of \(totalCount)"
                }
                var currentCount = 0

                for post in imagePosts {
                    if let tim = post.tim, let ext = post.ext {
                        currentCount += 1

                        await MainActor.run {
                            downloadProgressCurrent = currentCount
                            downloadProgressTotal = totalCount
                            downloadStatusMessage = "Downloading image \(currentCount) of \(totalCount)"
                        }

                        let fullURLStr = "https://i.4cdn.org/\(boardID)/\(tim)\(ext)"
                        if let fileURL = URL(string: fullURLStr) {
                            let destinationFileUrl = destinationFolderUrl.appendingPathComponent("\(tim)\(ext)")

                            if !FileManager.default.fileExists(atPath: destinationFileUrl.path) {
                                do {
                                    let (data, _) = try await URLSession.shared.data(from: fileURL)
                                    try data.write(to: destinationFileUrl)
                                } catch {
                                    print("Failed: \(fullURLStr)")
                                }
                            }
                        }
                    }
                }

                await MainActor.run {
                    isDownloadingAll = false
                    downloadProgressCurrent = downloadProgressTotal
                    downloadStatusMessage = "Download Complete!\nSaved to Files."
                    showDownloadAlert = true
                }

            } catch {
                await MainActor.run {
                    isDownloadingAll = false
                    downloadProgressCurrent = 0
                    downloadStatusMessage = "Error: \(error.localizedDescription)"
                    showDownloadAlert = true
                }
            }
        }
    }

    func saveImageToPhotoLibrary(from url: URL?) {
        guard let url = url else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                }
            } catch {
                print("Failed to save to photos: \(error)")
            }
        }
    }
}

struct PostRowView: View {
    let boardID: String
    let threadNo: Int
    let post: Thread
    let replies: [Int]
    let resolvePost: (Int) -> Thread?
    let imageTapped: (URL) -> Void
    let highlighted: Bool
    let copyQuote: (Int) -> Void
    let attributedComment: (String) -> AttributedString
    let isOP: Bool
    let isArchived: Bool
    let threadTitle: String?
    let opTim: Int?
    let theme: BoardColors.Theme
    @Environment(\.openURL) private var openURL
    @State private var showRepliesPopover = false
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var youPostsManager = YouPostsManager.shared

    var body: some View {
        let highlightColor: Color? = highlighted
            ? Color.yellow.opacity(0.15)
            : ((settings.highlightOP && isOP) ? theme.highlight.opacity(0.12) : nil)

        HStack(alignment: .top, spacing: 10) {
            if let tim = post.tim {
                let fileExt = post.ext ?? ".jpg"
                let thumbURL = URL(string: "https://i.4cdn.org/\(boardID)/\(tim)s.jpg")
                let fullURL = URL(string: "https://i.4cdn.org/\(boardID)/\(tim)\(fileExt)")

                if let url = thumbURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.gray.opacity(0.3)
                        }
                    }
                    .frame(width: CGFloat(60) * settings.thumbnailScale, height: CGFloat(60) * settings.thumbnailScale)
                    .cornerRadius(6)
                    .clipped()
                    .onTapGesture {
                        if let fu = fullURL { imageTapped(fu) }
                    }
                    .contextMenu {
                        if fileExt != ".webm" && fileExt != ".mp4" {
                            Button {
                                saveImageToPhotoLibrary(from: fullURL)
                            } label: {
                                Label("Save Image", systemImage: "photo")
                            }
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if fileExt == ".webm" || fileExt == ".mp4" {
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
            }

            VStack(alignment: .leading, spacing: 4 * settings.density.spacingMultiplier) {
                // Subject at the very top of the post content
                if let subject = post.sub?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty {
                    Text(cleanHTML(subject))
                        .font(.headline.weight(.bold))
                        .foregroundColor(theme.text)
                        .lineLimit(2)
                }

                // Metadata row (name, No., time, replies)
                HStack(alignment: .firstTextBaseline, spacing: 8 * settings.density.spacingMultiplier) {
                    Text(post.name ?? "Anonymous")
                        .font(.caption)
                        .bold()
                        .foregroundColor(theme.accent)

                    Text("No. \(post.no.formatted(.number.grouping(.never)))")
                        .font(.caption)
                        .foregroundColor(theme.text.opacity(0.7))
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button { copyQuote(post.no) } label: {
                                Label("Copy Quote", systemImage: "doc.on.doc")
                            }
                            Button {
                                youPostsManager.toggleYou(
                                    boardID: boardID,
                                    threadNo: threadNo,
                                    postNo: post.no,
                                    threadTitle: threadTitle,
                                    tim: opTim,
                                    knownReplies: replies
                                )
                            } label: {
                                let isYou = youPostsManager.isYou(boardID: boardID, threadNo: threadNo, postNo: post.no)
                                Label(isYou ? "Unmark (You)" : "Mark (You)", systemImage: isYou ? "person.fill.badge.minus" : "person.fill.badge.plus")
                            }
                        }

                    if youPostsManager.isYou(boardID: boardID, threadNo: threadNo, postNo: post.no) {
                        Text("(You)")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(theme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(theme.accent.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    if settings.showIDs, let pid = post.posterID {
                        Text("ID: \(pid)")
                            .font(.caption2)
                            .foregroundColor(theme.text.opacity(0.65))
                    }
                    if settings.showFlags, let cc = post.country {
                        Text(flagEmoji(for: cc))
                            .font(.caption)
                    }

                    Spacer()

                    HStack(spacing: 8 * settings.density.spacingMultiplier) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text(Date(timeIntervalSince1970: TimeInterval(post.time)), style: .relative)
                        }

                        if settings.showReplyCounts && !replies.isEmpty {
                            Button { showRepliesPopover = true } label: {
                                let count = replies.count
                                Text("\(count) repl\(count == 1 ? "y" : "ies")")
                                    .foregroundColor(theme.accent)
                            }
                            .buttonStyle(.borderless)
                            .popover(isPresented: $showRepliesPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Replies to No. \(post.no.formatted(.number.grouping(.never)))")
                                        .font(.caption.bold())
                                        .foregroundColor(theme.text.opacity(0.7))
                                    Divider()
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 12) {
                                            ForEach(replies, id: \.self) { replyNo in
                                                Button {
                                                    showRepliesPopover = false
                                                    if let url = URL(string: "quote://\(replyNo)") { _ = openURL(url) }
                                                } label: {
                                                    if let rp = resolvePost(replyNo) {
                                                        HStack(alignment: .top, spacing: 10) {
                                                            if let tim = rp.tim {
                                                                let fileExt = rp.ext ?? ".jpg"
                                                                let thumbURL = URL(string: "https://i.4cdn.org/\(boardID)/\(tim)s.jpg")
                                                                if let url = thumbURL {
                                                                    AsyncImage(url: url) { phase in
                                                                        if let image = phase.image {
                                                                            image.resizable().scaledToFill()
                                                                        } else {
                                                                            Color.gray.opacity(0.3)
                                                                        }
                                                                    }
                                                                    .frame(width: CGFloat(60) * settings.thumbnailScale, height: CGFloat(60) * settings.thumbnailScale)
                                                                    .cornerRadius(6)
                                                                    .clipped()
                                                                    .overlay(alignment: .bottomTrailing) {
                                                                        if fileExt == ".webm" || fileExt == ".mp4" {
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
                                                            }

                                                            VStack(alignment: .leading, spacing: 6) {
                                                                Text(">>\(replyNo.formatted(.number.grouping(.never)))")
                                                                    .font(.caption.bold())
                                                                    .foregroundColor(theme.accent)

                                                                if let subject = rp.sub?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty {
                                                                    Text(cleanHTML(subject))
                                                                        .font(.headline.weight(.bold))
                                                                        .foregroundColor(theme.text)
                                                                }

                                                                HStack(alignment: .firstTextBaseline, spacing: 8 * settings.density.spacingMultiplier) {
                                                                    Text(rp.name ?? "Anonymous")
                                                                        .font(.caption)
                                                                        .bold()
                                                                        .foregroundColor(theme.accent)

                                                                    Text("No. \(rp.no.formatted(.number.grouping(.never)))")
                                                                        .font(.caption)
                                                                        .foregroundColor(theme.text.opacity(0.7))

                                                                    Spacer()

                                                                    HStack(spacing: 4) {
                                                                        Image(systemName: "clock")
                                                                        Text(Date(timeIntervalSince1970: TimeInterval(rp.time)), style: .relative)
                                                                    }
                                                                    .font(.caption)
                                                                    .foregroundColor(theme.text.opacity(0.65))
                                                                }

                                                                if let filename = rp.filename, let fsize = rp.fsize, let ext = rp.ext {
                                                                    Text("\(filename)\(ext) • \(formatFileSize(fsize))")
                                                                        .font(.system(size: 10))
                                                                        .foregroundColor(theme.text.opacity(0.65))
                                                                        .lineLimit(1)
                                                                        .allowsHitTesting(false)
                                                                }

                                                                if let com = rp.com {
                                                                    Text(attributedComment(com))
                                                                        .font(.body)
                                                                        .fixedSize(horizontal: false, vertical: true)
                                                                }
                                                            }
                                                        }
                                                        .padding(.vertical, 8)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                    } else {
                                                        VStack(alignment: .leading, spacing: 4) {
                                                            Text(">>\(replyNo.formatted(.number.grouping(.never)))")
                                                                .font(.caption.bold())
                                                                .foregroundColor(theme.accent)
                                                            Text("Post unavailable")
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                        }
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                        .padding(.vertical, 8)
                                                    }
                                                }
                                                .buttonStyle(.plain)

                                                Divider()
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .frame(maxHeight: .infinity)
                                }
                                .padding(12)
                                .frame(maxWidth: 420, alignment: .leading)
                                .frame(maxHeight: .infinity, alignment: .topLeading)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundColor(theme.text.opacity(0.65))
                }

                if let filename = post.filename, let fsize = post.fsize, let ext = post.ext {
                    Text("\(filename)\(ext) • \(formatFileSize(fsize))")
                        .font(.system(size: 10))
                        .foregroundColor(theme.text.opacity(0.65))
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }

                if let comment = post.com {
                    Text(attributedComment(comment))
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isArchived {
                    Text("Archived")
                        .font(.caption2)
                        .foregroundColor(theme.text.opacity(0.65))
                        .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 6 * settings.density.spacingMultiplier)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlightColor ?? Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                youPostsManager.toggleYou(
                    boardID: boardID,
                    threadNo: threadNo,
                    postNo: post.no,
                    threadTitle: threadTitle,
                    tim: opTim,
                    knownReplies: replies
                )
            } label: {
                let isYou = youPostsManager.isYou(boardID: boardID, threadNo: threadNo, postNo: post.no)
                Label(isYou ? "Unmark (You)" : "Mark (You)", systemImage: isYou ? "person.fill.badge.minus" : "person.fill.badge.plus")
            }
        }
    }

    // Local helper for saving images
    private func saveImageToPhotoLibrary(from url: URL?) {
        guard let url = url else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                }
            } catch {
                print("Failed to save to photos: \(error)")
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

private struct ThreadSubjectHeader: View {
    let title: String
    let theme: BoardColors.Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subject")
                .font(.caption2.weight(.semibold))
                .foregroundColor(theme.text.opacity(0.6))
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundColor(theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .cornerRadius(12)
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .listRowBackground(Color.clear)
    }
}

private struct NewPostsDividerRow: View {
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(accent).frame(height: 1)
            Text("New Posts")
                .font(.caption2.weight(.semibold))
                .foregroundColor(accent)
            Rectangle().fill(accent).frame(height: 1)
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
    }
}

private func flagEmoji(for countryCode: String) -> String {
    let base: UInt32 = 127397
    var s = ""
    for v in countryCode.uppercased().unicodeScalars {
        if let scalar = UnicodeScalar(base + v.value) {
            s.unicodeScalars.append(scalar)
        }
    }
    return s
}

