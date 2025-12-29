import SwiftUI
import Photos
import UIKit

struct ThreadDetailView: View {
    let boardID: String
    let threadNo: Int
    // Indicates whether this thread was opened from an archived listing
    let isArchived: Bool

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
    @State private var showNativeComposer = false
    @State private var composerInitialComment: String? = nil

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
    @Environment(\.openURL) private var openURL
    @ObservedObject private var settings = AppSettings.shared

    @State private var lastReadPostNo: Int? = nil
    @State private var showJumpToBottomToast = false
    @State private var scrollToPostNo: Int? = nil
    @State private var visiblePostNos: Set<Int> = []
    @State private var lastMaxSeenPostNo: Int? = nil
    @State private var hasVisitedBefore: Bool = false

    private var threadURL: URL {
        URL(string: "https://boards.4chan.org/\(boardID)/thread/\(threadNo)")!
    }

    private var isSFWBoard: Bool { BoardDirectory.shared.isSFW(boardID: boardID) }
    private var threadTint: Color { isSFWBoard ? .chanSFW : .chanNSFW }

    var body: some View {
        ZStack {
            // Main list
            ScrollViewReader { proxy in
                List(filteredPosts, id: \.no) { post in
                    if isFirstNewPost(post.no) {
                        NewPostsDivider()
                            .listRowInsets(EdgeInsets())
                    }

                    let postReplies = repliesIndex[post.no] ?? []
                    let isHighlighted = (highlightedPostNo == post.no)
                    let isOP = post.no == (posts.first?.no ?? post.no)
                    let opPost = posts.first
                    let threadTitle = opPost?.sub ?? cleanHTML(opPost?.com ?? "Thread \(threadNo)")

                    PostRowView(
                        boardID: boardID,
                        threadNo: threadNo,
                        threadTitle: threadTitle,
                        threadTim: opPost?.tim,
                        post: post,
                        replies: postReplies,
                        postLookup: { no in posts.first(where: { $0.no == no }) },
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
                    )
                    .id(post.no)
                    .listRowBackground(threadTint.opacity(0.20))
                    .onAppear { visiblePostNos.insert(post.no) }
                    .onDisappear { visiblePostNos.remove(post.no) }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: isSearchVisible ? .always : .automatic), prompt: "Search posts")
                .focused($isSearchFieldFocused)
                .scrollContentBackground(.hidden)
                .background(threadTint.opacity(0.12))
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
                    } else if url.scheme == "reply",
                              let host = url.host,
                              let targetNo = Int(host) {
                        composerInitialComment = ">>\(targetNo)\n"
                        showNativeComposer = true
                        return .handled
                    }
                    return .systemAction
                })
                .onAppear {
                    hasVisitedBefore = HistoryManager.shared.history.contains(where: { $0.boardID == boardID && $0.threadNo == threadNo })
                    loadPosts()
                    if let savedTop = ThreadReadState.shared.lastTopPostNo(boardID: boardID, threadNo: threadNo) {
                        lastReadPostNo = savedTop
                    }
                    lastMaxSeenPostNo = ThreadReadState.shared.lastMaxPostNo(boardID: boardID, threadNo: threadNo)
                }
                .onChange(of: posts.count) { _ in
                    buildRepliesIndex()
                    rebuildMediaList()
                    YouPostsManager.shared.clearUnreadForThread(boardID: boardID, threadNo: threadNo)
                    if hasVisitedBefore, let target = lastReadPostNo, posts.contains(where: { $0.no == target }) {
                        DispatchQueue.main.async {
                            withAnimation { proxy.scrollTo(target, anchor: .top) }
                        }
                    }
                }
                .onChange(of: scrollToPostNo) { target in
                    if let target = target {
                        withAnimation { proxy.scrollTo(target, anchor: .bottom) }
                        scrollToPostNo = nil
                    }
                }

            }
            .navigationTitle("Thread \(threadNo.formatted(.number.grouping(.never)))")

            .sheet(isPresented: Binding(get: { selectedImageIndex != nil }, set: { if !$0 { selectedImageIndex = nil } })) {
                if let idx = selectedImageIndex {
                    ImageBrowser(media: mediaItems, currentIndex: idx, isPresented: Binding(get: { selectedImageIndex != nil }, set: { if !$0 { selectedImageIndex = nil } }), onBack: {
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
                        Button(action: loadPosts) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        Button(action: { showNativeComposer = true }) {
                            Label("Reply", systemImage: "arrowshape.turn.up.left.fill")
                        }
                        Button(action: downloadAllImagesToFiles) {
                            Label("Download All", systemImage: "arrow.down.circle.fill")
                        }
                        Button(action: toggleFavorite) {
                            Label(favoritesManager.isFavorite(boardID: boardID, threadNo: threadNo) ? "Unfavorite" : "Favorite", systemImage: favoritesManager.isFavorite(boardID: boardID, threadNo: threadNo) ? "star.fill" : "star")
                        }
                        Button(action: {
                            if let last = posts.last?.no {
                                scrollToPostNo = last
                                showJumpToBottomToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { showJumpToBottomToast = false }
                            }
                        }) {
                            Label("Jump to Bottom", systemImage: "arrow.down.to.line")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .padding(6)
                    }
                }
            }

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
        .background(threadTint.opacity(0.12))
        .sheet(isPresented: $showSafariThread) {
            SafariView(url: threadURL)
        }
        .sheet(isPresented: $showNativeComposer) {
            PostComposerNative(boardID: boardID, threadNo: threadNo, initialComment: composerInitialComment)
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
        .overlay(alignment: .top) {
            if showJumpToBottomToast {
                Text("Jumped to bottom")
                    .font(.caption.bold())
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 44)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showQuoteCopiedToast)
        .animation(.easeInOut(duration: 0.2), value: showJumpToBottomToast)
        .environment(\.dynamicTypeSize, settings.adjustedDynamicType)
        .alert("Download Complete", isPresented: $showDownloadAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(downloadStatusMessage)
        }
        .onDisappear {
            if let top = topVisiblePostNo() {
                ThreadReadState.shared.setLastTopPostNo(boardID: boardID, threadNo: threadNo, postNo: top)
            }
            if let latest = posts.last?.no {
                ThreadReadState.shared.setLastMaxPostNo(boardID: boardID, threadNo: threadNo, postNo: latest)
            }
        }
    }


    private func isFirstNewPost(_ postNo: Int) -> Bool {
        guard let last = lastMaxSeenPostNo else { return false }
        guard let idx = posts.firstIndex(where: { $0.no == postNo }),
              let lastIdx = posts.firstIndex(where: { $0.no == last }) else { return false }
        return idx == lastIdx + 1
    }

    private func topVisiblePostNo() -> Int? {
        guard !visiblePostNos.isEmpty else { return nil }
        var bestNo: Int?
        var bestIdx: Int?
        for no in visiblePostNos {
            if let idx = posts.firstIndex(where: { $0.no == no }) {
                if bestIdx == nil || idx < bestIdx! {
                    bestIdx = idx
                    bestNo = no
                }
            }
        }
        return bestNo
    }

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
                    self.posts = fetchedPosts
                    self.buildRepliesIndex()

                    let replyCount = max(0, fetchedPosts.count - 1)
                    FavoritesManager.shared.markSeen(
                        boardID: boardID,
                        threadNo: threadNo,
                        replyCount: replyCount
                    )

                    HistoryManager.shared.add(boardID: boardID, threadNo: threadNo, title: fetchedPosts.first?.sub ?? cleanHTML(fetchedPosts.first?.com ?? "Thread \(threadNo)"), tim: fetchedPosts.first?.tim)
                    HistoryManager.shared.markSeen(boardID: boardID, threadNo: threadNo, replyCount: replyCount)

                    rebuildMediaList()
                    YouPostsManager.shared.clearUnreadForThread(boardID: boardID, threadNo: threadNo)

                    self.lastReadPostNo = ThreadReadState.shared.lastTopPostNo(boardID: boardID, threadNo: threadNo)
                    self.lastMaxSeenPostNo = ThreadReadState.shared.lastMaxPostNo(boardID: boardID, threadNo: threadNo)
                }

            case .failure(let error):
                DispatchQueue.main.async {
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

    func rebuildMediaList() {
        mediaItems = posts.compactMap { post in
            if let tim = post.tim {
                return MediaItem(board: boardID, tim: tim, ext: post.ext)
            }
            return nil
        }
    }

    func attributedComment(from raw: String) -> AttributedString {
        let cleaned = cleanHTML(raw)
        var result = AttributedString()

        let quotePattern = #">>(\d+)"#
        let quoteRegex = try? NSRegularExpression(pattern: quotePattern, options: [])
        let urlRegex = try? NSRegularExpression(pattern: #"https?:\/\/[^\s]+"#, options: [])

        let lines = cleaned.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            let isGreentext = line.hasPrefix(">") && !line.hasPrefix(">>")

            let nsLine = line as NSString
            let length = nsLine.length

            var events: [(range: NSRange, kind: String, payload: String?)] = []

            if let qrx = quoteRegex {
                let matches = qrx.matches(in: line, options: [], range: NSRange(location: 0, length: length))
                for m in matches where m.numberOfRanges >= 2 {
                    let full = m.range
                    let numRange = m.range(at: 1)
                    let numStr = nsLine.substring(with: numRange)
                    events.append((full, "quote", numStr))
                }
            }

            if let urx = urlRegex {
                let matches = urx.matches(in: line, options: [], range: NSRange(location: 0, length: length))
                for m in matches {
                    let full = m.range
                    let urlStr = nsLine.substring(with: full)
                    events.append((full, "url", urlStr))
                }
            }

            events.sort { $0.range.location < $1.range.location }

            var currentLocation = 0
            for ev in events {
                let r = ev.range
                if r.location > currentLocation {
                    let beforeRange = NSRange(location: currentLocation, length: r.location - currentLocation)
                    var before = AttributedString(nsLine.substring(with: beforeRange))
                    if isGreentext { before.foregroundColor = .green }
                    result.append(before)
                }

                let segmentStr = nsLine.substring(with: r)
                var segment = AttributedString(segmentStr)
                switch ev.kind {
                case "quote":
                    if let target = ev.payload, let u = URL(string: "quote://\(target)") { segment.link = u }
                case "url":
                    if let s = ev.payload, let u = URL(string: s) { segment.link = u }
                default:
                    break
                }
                if isGreentext { segment.foregroundColor = .green }
                result.append(segment)

                currentLocation = r.location + r.length
            }

            if currentLocation < length {
                let tailRange = NSRange(location: currentLocation, length: length - currentLocation)
                var tail = AttributedString(nsLine.substring(with: tailRange))
                if isGreentext { tail.foregroundColor = .green }
                result.append(tail)
            }

            if index < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }

        return result
    }

    func buildRepliesIndex() {
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

    var filteredPosts: [Thread] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return posts }
        return posts.filter { post in
            if let sub = post.sub, cleanHTML(sub).lowercased().contains(query) { return true }
            if let com = post.com, cleanHTML(com).lowercased().contains(query) { return true }
            return false
        }
    }


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
    let threadTitle: String?
    let threadTim: Int?
    let post: Thread
    let replies: [Int]
    let postLookup: (Int) -> Thread?
    let imageTapped: (URL) -> Void
    let highlighted: Bool
    let copyQuote: (Int) -> Void
    let attributedComment: (String) -> AttributedString
    let isOP: Bool
    let isArchived: Bool
    @Environment(\.openURL) private var openURL
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var youManager = YouPostsManager.shared
    @State private var showRepliesPopover = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let tim = post.tim {
                let fileExt = post.ext ?? ".jpg"
                let thumbURL = URL(string: "https://i.4cdn.org/\(boardID)/\(tim)s.jpg")
                let fullURL  = URL(string: "https://i.4cdn.org/\(boardID)/\(tim)\(fileExt)")

                if let url = thumbURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.gray.opacity(0.3)
                        }
                    }
                    .frame(width: CGFloat(60) * settings.thumbnailScale, height: CGFloat(60) * settings.thumbnailScale)
                    .cornerRadius(4)
                    .clipped()
                    .onTapGesture {
                        if let fu = fullURL { imageTapped(fu) }
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
                HStack(alignment: .firstTextBaseline, spacing: 8 * settings.density.spacingMultiplier) {
                    Text(post.name ?? "Anonymous")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.red)

                    Text("No. \(post.no.formatted(.number.grouping(.never)))")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .onTapGesture { copyQuote(post.no) }
                    if youManager.isYou(boardID: boardID, threadNo: threadNo, postNo: post.no) {
                        Text("(You)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.blue)
                    }

                    if settings.showIDs, let pid = post.posterID {
                        Text("ID: \(pid)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if settings.showFlags, let cc = post.country {
                        // 4chan uses 2-letter country codes; display as regional flag emoji when possible
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
                                                if let replyPost = postLookup(replyNo) {
                                                    ReplyPreviewRow(
                                                        boardID: boardID,
                                                        post: replyPost,
                                                        attributedComment: attributedComment,
                                                        onTap: {
                                                            showRepliesPopover = false
                                                            if let url = URL(string: "quote://\(replyNo)") { _ = openURL(url) }
                                                        }
                                                    )
                                                } else {
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
                                        .padding(.vertical, 4)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                if let sub = post.sub {
                    Text(sub)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let filename = post.filename, let fsize = post.fsize, let ext = post.ext {
                    Text("\(filename)\(ext) • \(formatFileSize(fsize))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }

                if let comment = post.com {
                    Text(attributedComment(comment))
                        .font(.body)
                        .textSelection(.enabled)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isArchived {
                    Text("Archived")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .contextMenu {
            let isMarked = youManager.isYou(boardID: boardID, threadNo: threadNo, postNo: post.no)
            Button(isMarked ? "Unmark (You)" : "Mark as (You)") {
                youManager.toggleYou(boardID: boardID, threadNo: threadNo, postNo: post.no, threadTitle: threadTitle, tim: threadTim)
            }
        }
        .padding(.vertical, 4 * settings.density.spacingMultiplier)
        .background(isArchived ? Color(UIColor.systemGray5).opacity(0.06) : Color.clear)
        .background(highlighted ? Color.yellow.opacity(0.15) : Color.clear)
        .background(settings.highlightOP && isOP ? Color.blue.opacity(0.06) : Color.clear)
    }

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

    private func plainText(from raw: String?) -> String {
        guard let raw = raw else { return "" }
        let attr = attributedComment(raw)
        return String(attr.characters)
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

struct ReplyPreviewRow: View {
    let boardID: String
    let post: Thread
    let attributedComment: (String) -> AttributedString
    let onTap: () -> Void
    @ObservedObject private var settings = AppSettings.shared
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                if let tim = post.tim {
                    let thumbURL = URL(string: "https://i.4cdn.org/\(boardID)/\(tim)s.jpg")
                    AsyncImage(url: thumbURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.gray.opacity(0.3)
                        }
                    }
                    .frame(width: CGFloat(44) * settings.thumbnailScale, height: CGFloat(44) * settings.thumbnailScale)
                    .cornerRadius(4)
                    .clipped()
                }
                VStack(alignment: .leading, spacing: 4 * settings.density.spacingMultiplier) {
                    HStack(spacing: 6) {
                        Text("No. \(post.no.formatted(.number.grouping(.never)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(Date(timeIntervalSince1970: TimeInterval(post.time)), style: .relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let sub = post.sub {
                        Text(sub)
                            .font(.caption.bold())
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.primary)
                    }
                    if let com = post.com {
                        Text(attributedComment(com))
                            .font(.caption)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct NewPostsDivider: View {
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color.red).frame(height: 2)
            Text("New posts")
                .font(.caption.bold())
                .foregroundColor(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.12))
                .clipShape(Capsule())
                .padding(.leading, 12)
        }
    }
}

final class ThreadReadState {
    static let shared = ThreadReadState()
    private let defaults = UserDefaults.standard
    private let keyPrefix = "lastReadPost_" // key format: lastReadPost_/board/thread
    private let keyTopPrefix = "lastTopPost_"
    private let keyMaxPrefix = "lastMaxPost_"
    private init() {}
    private func key(boardID: String, threadNo: Int) -> String {
        return "\(keyPrefix)\(boardID)/\(threadNo)"
    }
    private func topKey(boardID: String, threadNo: Int) -> String {
        return "\(keyTopPrefix)\(boardID)/\(threadNo)"
    }
    private func maxKey(boardID: String, threadNo: Int) -> String {
        return "\(keyMaxPrefix)\(boardID)/\(threadNo)"
    }

    func lastReadPostNo(boardID: String, threadNo: Int) -> Int? {
        let k = key(boardID: boardID, threadNo: threadNo)
        let v = defaults.integer(forKey: k)
        return v == 0 ? nil : v
    }

    func setLastReadPostNo(boardID: String, threadNo: Int, postNo: Int) {
        let k = key(boardID: boardID, threadNo: threadNo)
        defaults.set(postNo, forKey: k)
    }

    func lastTopPostNo(boardID: String, threadNo: Int) -> Int? {
        let k = topKey(boardID: boardID, threadNo: threadNo)
        let v = defaults.integer(forKey: k)
        return v == 0 ? nil : v
    }
    func setLastTopPostNo(boardID: String, threadNo: Int, postNo: Int) {
        let k = topKey(boardID: boardID, threadNo: threadNo)
        defaults.set(postNo, forKey: k)
    }

    func lastMaxPostNo(boardID: String, threadNo: Int) -> Int? {
        let k = maxKey(boardID: boardID, threadNo: threadNo)
        let v = defaults.integer(forKey: k)
        return v == 0 ? nil : v
    }

    func setLastMaxPostNo(boardID: String, threadNo: Int, postNo: Int) {
        let k = maxKey(boardID: boardID, threadNo: threadNo)
        defaults.set(postNo, forKey: k)
    }
}

