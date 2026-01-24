import SwiftUI

struct ContentView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var favoritesManager = FavoritesManager.shared

    var body: some View {
        TabView {
            BoardListView()
                .tabItem { Label("Boards", systemImage: "list.bullet") }

            FavoritesView()
                .tabItem { Label("Favorites", systemImage: "star.fill") }
                .badge(favoritesManager.totalUnreadCount)

            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .preferredColorScheme(settings.preferredColorScheme)
    }
}

struct BoardListView: View {
    private enum EightKunBoardSearchScope: Hashable {
        case code
        case description
    }

    private enum EightKunBoardSort: Hashable {
        case activity
        case code
    }

    private enum EndchanBoardSort: Hashable {
        case users
        case code
    }

    @State private var boards: [Board] = []
    @State private var externalBoards: [ExternalBoard] = []
    @State private var isLoading: Bool = false
    @State private var loadErrorMessage: String? = nil
    @State private var boardSearchText: String = ""
    @State private var eightKunSearchScope: EightKunBoardSearchScope = .code
    @State private var eightKunSort: EightKunBoardSort = .activity
    @State private var endchanSort: EndchanBoardSort = .code
    @State private var showSites: Bool = false
    @State private var showCloudflareSheet: Bool = false
    @State private var blockedURL: URL? = nil

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @ObservedObject private var siteDirectory = SiteDirectory.shared

    private var normalizedBoardQuery: String {
        boardSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func codeMatches(_ code: String) -> Bool {
        let q = normalizedBoardQuery
        guard !q.isEmpty else { return true }

        let normalizedCode = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()

        if normalizedCode.contains(q) { return true }
        if "/\(normalizedCode)/".contains(q) { return true }
        return false
    }

    private func descriptionMatches(title: String, description: String?) -> Bool {
        let q = normalizedBoardQuery
        guard !q.isEmpty else { return true }
        if title.lowercased().contains(q) { return true }
        if let description, description.lowercased().contains(q) { return true }
        return false
    }

    private func boardMatches(code: String, title: String, description: String? = nil) -> Bool {
        let q = normalizedBoardQuery
        guard !q.isEmpty else { return true }

        let normalizedCode = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()

        if normalizedCode.contains(q) { return true }
        if "/\(normalizedCode)/".contains(q) { return true }
        if title.lowercased().contains(q) { return true }
        if let description, description.lowercased().contains(q) { return true }
        return false
    }

    private var filteredSavedBoards: [SavedBoard] {
        let q = normalizedBoardQuery
        guard !q.isEmpty else { return favoritesManager.savedBoards }
        return favoritesManager.savedBoards.filter { boardMatches(code: $0.board, title: $0.title) }
    }

    private var filteredFourChanBoards: [Board] {
        let base = boards.filter { !favoritesManager.isBoardFavorite($0.board) }
        let q = normalizedBoardQuery
        guard !q.isEmpty else { return base }
        return base.filter { boardMatches(code: $0.board, title: $0.title, description: $0.meta_description) }
    }

    private var filteredExternalBoards: [ExternalBoard] {
        let q = normalizedBoardQuery
        var base = externalBoards

        if !q.isEmpty {
            if siteDirectory.current.id == "8kun" {
                switch eightKunSearchScope {
                case .code:
                    base = base.filter { codeMatches($0.code) }
                case .description:
                    base = base.filter { descriptionMatches(title: $0.title, description: $0.description) }
                }
            } else {
                base = base.filter { boardMatches(code: $0.code, title: $0.title, description: $0.description) }
            }
        }

        if siteDirectory.current.id == "8kun" {
            switch eightKunSort {
            case .activity:
                return base.sorted { lhs, rhs in
                    let li = lhs.activeISPs
                    let ri = rhs.activeISPs
                    switch (li, ri) {
                    case let (l?, r?):
                        if l != r { return l > r }
                    case (nil, _?):
                        return false
                    case (_?, nil):
                        return true
                    case (nil, nil):
                        break
                    }
                    return lhs.code < rhs.code
                }
            case .code:
                return base.sorted(by: { $0.code < $1.code })
            }
        }

        if siteDirectory.current.id == "endchan" {
            switch endchanSort {
            case .users:
                return base.sorted { lhs, rhs in
                    let li = lhs.userCount ?? 0
                    let ri = rhs.userCount ?? 0
                    if li != ri { return li > ri }
                    return lhs.code < rhs.code
                }
            case .code:
                return base.sorted(by: { $0.code < $1.code })
            }
        }

        return base
    }

    var body: some View {
        NavigationView {
            List {
                if siteDirectory.current.kind == .fourChan {
                    if !filteredSavedBoards.isEmpty {
                        Section {
                            ForEach(filteredSavedBoards) { favBoard in
                                if let boardObj = boards.first(where: { $0.board == favBoard.board }) {
                                    NavigationLink(destination: ThreadView(board: boardObj)) {
                                        BoardRow(board: boardObj, isFavorite: true) {
                                            favoritesManager.removeBoard(boardCode: boardObj.board)
                                        }
                                    }
                                } else {
                                    NavigationLink(destination: EmptyView()) {
                                        HStack {
                                            Text("/\(favBoard.board)/")
                                                .font(.system(.body, design: .monospaced))
                                            Text(favBoard.title)
                                            Spacer()
                                            Button(action: { favoritesManager.removeBoard(boardCode: favBoard.board) }) {
                                                Image(systemName: "star.fill")
                                                    .foregroundColor(.yellow)
                                            }
                                            .buttonStyle(.borderless)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("Favorites")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                                .textCase(nil)
                        }
                    }

                    Section {
                        ForEach(filteredFourChanBoards, id: \.board) { board in
                            NavigationLink(destination: ThreadView(board: board)) {
                                BoardRow(board: board, isFavorite: favoritesManager.isBoardFavorite(board.board)) {
                                    if favoritesManager.isBoardFavorite(board.board) {
                                        favoritesManager.removeBoard(boardCode: board.board)
                                    } else {
                                        favoritesManager.addBoard(board)
                                        if !boards.contains(where: { $0.board == board.board }) {
                                            boards.append(board)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("All Boards")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(nil)
                    }
                } else {
                    if let loadErrorMessage {
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(loadErrorMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                HStack(spacing: 16) {
                                    Button("Retry") { fetchData() }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    Button("Fix access") {
                                        blockedURL = siteDirectory.current.baseURL
                                        showCloudflareSheet = true
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }

                    if siteDirectory.current.id == "8kun",
                       !externalBoards.isEmpty,
                       externalBoards.allSatisfy({ $0.activeISPs == nil }) {
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Active ISP counts are unavailable until 8kun's index page can be loaded.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Button("Fix access") {
                                    blockedURL = siteDirectory.current.baseURL
                                    showCloudflareSheet = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 8)
                        }
                    }

                    Section {
                        if isLoading && externalBoards.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(1.2)
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        } else {
                            ForEach(filteredExternalBoards) { board in
                                NavigationLink(destination: ExternalThreadListView(site: siteDirectory.current, boardCode: board.code, boardTitle: board.title)) {
                                    ExternalBoardRow(board: board)
                                }
                            }
                        }
                    } header: {
                        Text("All Boards")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(nil)
                    }
                }
            }
            .navigationTitle("\(siteDirectory.current.displayName)")
            .listStyle(.insetGrouped)
            .environment(\.dynamicTypeSize, settings.dynamicType)
            .searchable(text: $boardSearchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search boards")
            .conditionalSearchScopes(siteDirectory.current.id == "8kun", selection: $eightKunSearchScope) {
                Text("Code").tag(EightKunBoardSearchScope.code)
                Text("Description").tag(EightKunBoardSearchScope.description)
            }
            .onAppear {
                switch siteDirectory.current.kind {
                case .fourChan:
                    if boards.isEmpty { fetchData() }
                case .external:
                    if externalBoards.isEmpty { fetchData() }
                }
            }
            .onChange(of: siteDirectory.current) { _ in
                boardSearchText = ""
                eightKunSearchScope = .code
                eightKunSort = .activity
                endchanSort = .code
                fetchData()
            }
            .refreshable { fetchData() }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSites = true
                    } label: {
                        Image(systemName: "globe")
                            .font(.system(size: 16, weight: .medium))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if siteDirectory.current.id == "8kun" {
                        Menu {
                            Picker("Sort", selection: $eightKunSort) {
                                Text("Activity").tag(EightKunBoardSort.activity)
                                Text("A–Z").tag(EightKunBoardSort.code)
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 14, weight: .medium))
                        }
                    } else if siteDirectory.current.id == "endchan" {
                        Menu {
                            Picker("Sort", selection: $endchanSort) {
                                Text("Users").tag(EndchanBoardSort.users)
                                Text("A–Z").tag(EndchanBoardSort.code)
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button(action: fetchData) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                }
            }
            .sheet(isPresented: $showSites) {
                SitesView()
            }
            .sheet(item: $blockedURL) { url in
                CloudflareClearanceInlineView(url: url) {
                    blockedURL = nil
                    showCloudflareSheet = false
                    fetchData()
                }
            }
        }
    }

    func fetchData() {
        let site = siteDirectory.current
        loadErrorMessage = nil
        isLoading = true

        switch site.kind {
        case .fourChan:
            externalBoards = []
            FourChanAPI.shared.fetchBoards { result in
                DispatchQueue.main.async {
                    guard site == self.siteDirectory.current else { return }
                    self.isLoading = false
                    switch result {
                    case .success(let fetchedBoards):
                        self.boards = fetchedBoards
                    case .failure(let error):
                        self.loadErrorMessage = "Failed to load boards: \(error.localizedDescription)"
                        print("Error fetching boards: \(error)")
                    }
                }
            }

        case .external:
            boards = []
            externalBoards = []
            if site.id == "7chan" {
                guard site == self.siteDirectory.current else {
                    self.isLoading = false
                    return
                }
                externalBoards = SevenChanBoards.all
                isLoading = false
                SevenChanBoards.enrichBoardTitles(site: site, boards: externalBoards) { enriched in
                    guard site == self.siteDirectory.current else { return }
                    self.externalBoards = enriched
                }
                return
            }
            VichanBoardsAPI.fetchBoards(site: site) { result in
                DispatchQueue.main.async {
                    guard site == self.siteDirectory.current else { return }
                    self.isLoading = false
                switch result {
                case .success(let fetchedBoards):
                        if site.id == "8kun" {
                            self.externalBoards = fetchedBoards
                        } else {
                            self.externalBoards = fetchedBoards.sorted(by: { $0.code < $1.code })
                        }
                case .failure(let error):
                    self.externalBoards = []
                    self.loadErrorMessage = "Failed to load boards: \(error.localizedDescription)"
                    print("Error fetching external boards: \(error)")
                    }
                }
            }
        }
    }
}

struct ThreadView: View {
    let board: Board

    @State private var threads: [Thread] = []
    @State private var selectedImageURL: URL?
    @ObservedObject private var settings = AppSettings.shared

    @State private var isGridView = false
    @State private var showArchived = false
    @State private var showToolbarMenuPopover = false
    @State private var searchText: String = ""
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isSearchVisible: Bool = false

    @State private var showSafariBoard = false
    private var boardURL: URL {
        URL(string: "https://boards.4chan.org/\(board.board)/")!
    }
    @State private var showNewThreadComposer = false

    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var boardTheme: BoardColors.Theme { BoardColors.theme(for: board) }

    var body: some View {
        Group {
            if isGridView {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredThreads, id: \.no) { thread in
                            ThreadGridCell(
                                board: board,
                                thread: thread,
                                selectedImageURL: $selectedImageURL,
                                isArchived: showArchived
                            )
                        }
                    }
                    .padding(12)
                }
                .refreshable { loadThreads() }
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: isSearchVisible ? .always : .automatic), prompt: "Search threads")
                .focused($isSearchFieldFocused)
                .environment(\.dynamicTypeSize, settings.dynamicType)
                .background(boardTheme.background)
            } else {
                List(filteredThreads, id: \.no) { thread in
                    ThreadListRow(
                        board: board,
                        thread: thread,
                        selectedImageURL: $selectedImageURL,
                        isArchived: showArchived
                    )
                    .listRowBackground(boardTheme.surface)
                }
                .listStyle(.plain)
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: isSearchVisible ? .always : .automatic), prompt: "Search threads")
                .focused($isSearchFieldFocused)
                .refreshable { loadThreads() }
                .environment(\.dynamicTypeSize, settings.dynamicType)
                .scrollContentBackground(.hidden)
                .background(boardTheme.background)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadThreads() }
        .fullScreenCover(item: $selectedImageURL) { url in
            FullScreenImageView(imageURL: url)
        }

        .sheet(isPresented: $showSafariBoard) {
            SafariView(url: boardURL)
        }

        .sheet(isPresented: $showNewThreadComposer, onDismiss: { loadThreads() }) {
            PostComposerNative(boardID: board.board, threadNo: nil)
        }

        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("4chan")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("/\(board.board)/")
                        .font(.headline)
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Picker("", selection: $showArchived) {
                    Text("Live").tag(false)
                    Text("Archived").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 140)
                .onChange(of: showArchived) { _ in loadThreads() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { isGridView.toggle() }) {
                    Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 15, weight: .medium))
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                #if os(iOS)
                Menu {
                    Button(action: {
                        isSearchVisible.toggle()
                        if isSearchVisible { isSearchFieldFocused = true } else { searchText = ""; isSearchFieldFocused = false }
                    }) { Label("Search", systemImage: "magnifyingglass") }

                    Button(action: { loadThreads() }) { Label("Refresh", systemImage: "arrow.clockwise") }

                    if !showArchived {
                        Button(action: { showNewThreadComposer = true }) { Label("New Thread", systemImage: "square.and.pencil") }
                    }

                    Button(action: { isGridView.toggle() }) { Label(isGridView ? "List View" : "Grid View", systemImage: isGridView ? "list.bullet" : "square.grid.2x2") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .medium))
                }
                #else
                Button(action: { showToolbarMenuPopover.toggle() }) { Image(systemName: "ellipsis") }
                .popover(isPresented: $showToolbarMenuPopover, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: {
                            isSearchVisible.toggle()
                            if isSearchVisible {
                                isSearchFieldFocused = true
                            } else {
                                searchText = ""
                                isSearchFieldFocused = false
                            }
                            showToolbarMenuPopover = false
                        }) {
                            Label("Search", systemImage: "magnifyingglass")
                        }

                        Button(action: {
                            loadThreads()
                            showToolbarMenuPopover = false
                        }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }

                        if !showArchived {
                            Button(action: {
                                showNewThreadComposer = true
                                showToolbarMenuPopover = false
                            }) {
                                Label("New Thread", systemImage: "square.and.pencil")
                            }
                            Button(action: {
                                showSafariBoard = true
                                showToolbarMenuPopover = false
                            }) {
                                Label("Open Board in Safari", systemImage: "safari")
                            }
                        }

                        Button(action: {
                            isGridView.toggle()
                            showToolbarMenuPopover = false
                        }) {
                            Label(isGridView ? "List View" : "Grid View", systemImage: isGridView ? "list.bullet" : "square.grid.2x2")
                        }
                    }
                    .padding(12)
                    .frame(minWidth: 180)
                }
                #endif
            }
        }
        .toolbarBackground(boardTheme.surface.opacity(0.6), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    func loadThreads() {
        if showArchived {
            FourChanAPI.shared.fetchArchivedThreads(boardID: board.board) { result in
                switch result {
                case .success(let fetchedThreads):
                    DispatchQueue.main.async { self.threads = fetchedThreads }
                case .failure(let error):
                    print("Error loading archived threads: \(error)")
                }
            }
        } else {
            FourChanAPI.shared.fetchThreads(boardID: board.board) { result in
                switch result {
                case .success(let fetchedThreads):
                    DispatchQueue.main.async { self.threads = fetchedThreads }
                case .failure(let error):
                    print("Error loading threads: \(error)")
                }
            }
        }
    }

    var filteredThreads: [Thread] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return threads }
        return threads.filter { thread in
            if let sub = thread.sub, cleanHTML(sub).lowercased().contains(query) { return true }
            if let com = thread.com, cleanHTML(com).lowercased().contains(query) { return true }
            return false
        }
    }
}

struct ThreadListRow: View {
    let board: Board
    let thread: Thread
    @Binding var selectedImageURL: URL?
    let isArchived: Bool
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var youPostsManager = YouPostsManager.shared

    var body: some View {
        let theme = BoardColors.theme(for: board)
        let hasYou = youPostsManager.isYouThread(boardID: board.board, threadNo: thread.no)
        let youUnread = hasYou ? youPostsManager.unreadForThread(boardID: board.board, threadNo: thread.no) : 0

        HStack(alignment: .top, spacing: 12) {
            if let tim = thread.tim {
                ThumbnailView(board: board.board, tim: tim, ext: thread.ext, selectedImageURL: $selectedImageURL)
                    .frame(width: CGFloat(80) * settings.thumbnailScale, height: CGFloat(80) * settings.thumbnailScale)
                    .cornerRadius(8)
            }

            NavigationLink(destination: ThreadDetailView(boardID: board.board, threadNo: thread.no, isArchived: isArchived, isSFWOverride: (board.ws_board ?? 1) == 1)) {
                VStack(alignment: .leading, spacing: 6 * settings.density.spacingMultiplier) {
                    if let subject = thread.sub {
                        Text(cleanHTML(subject))
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .foregroundColor(theme.text)
                    }
                    if let comment = thread.com {
                        Text(cleanHTML(comment))
                            .font(.system(size: 13))
                            .foregroundColor(theme.text.opacity(0.7))
                            .lineLimit(4)
                    }
                    HStack(spacing: 8) {
                        Text("No. \(thread.no.formatted(.number.grouping(.never)))")
                            .font(.system(size: 11))
                            .foregroundColor(theme.text.opacity(0.5))
                        if hasYou {
                            Text(youUnread > 0 ? "You \(youUnread)" : "You")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(theme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(theme.accent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        Spacer()
                        if settings.showReplyCounts, let replies = thread.replies {
                            Text("R: \(replies)")
                                .font(.system(size: 11))
                                .foregroundColor(theme.text.opacity(0.5))
                        }
                        if settings.showImageCounts, let images = thread.images {
                            Text("I: \(images)")
                                .font(.system(size: 11))
                                .foregroundColor(theme.text.opacity(0.5))
                        }
                    }
                    if isArchived {
                        Text("Archived")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .padding(.vertical, 6 * settings.density.spacingMultiplier)
        .background(isArchived ? Color(UIColor.systemGray5).opacity(0.06) : Color.clear)
    }
}

struct ThreadGridCell: View {
    let board: Board
    let thread: Thread
    @Binding var selectedImageURL: URL?
    let isArchived: Bool
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var youPostsManager = YouPostsManager.shared

    var body: some View {
        let theme = BoardColors.theme(for: board)
        let hasYou = youPostsManager.isYouThread(boardID: board.board, threadNo: thread.no)
        let youUnread = hasYou ? youPostsManager.unreadForThread(boardID: board.board, threadNo: thread.no) : 0

        VStack(alignment: .leading, spacing: 0) {
            if let tim = thread.tim {
                ThumbnailView(board: board.board, tim: tim, ext: thread.ext, selectedImageURL: $selectedImageURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: CGFloat(150) * settings.thumbnailScale)
                    .clipped()
            }

            NavigationLink(destination: ThreadDetailView(boardID: board.board, threadNo: thread.no, isArchived: isArchived, isSFWOverride: (board.ws_board ?? 1) == 1)) {
                VStack(alignment: .leading, spacing: 5 * settings.density.spacingMultiplier) {
                    if let subject = thread.sub {
                        Text(cleanHTML(subject))
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(2)
                            .foregroundColor(theme.text)
                    }
                    if let comment = thread.com {
                        Text(cleanHTML(comment))
                            .font(.system(size: 12))
                            .foregroundColor(theme.text.opacity(0.7))
                            .lineLimit(3)
                    }
                    HStack {
                        if settings.showReplyCounts { Text("R: \(thread.replies ?? 0)").font(.system(size: 10)) }
                        Spacer()
                        if settings.showImageCounts { Text("I: \(thread.images ?? 0)").font(.system(size: 10)) }
                    }
                    .foregroundColor(theme.text.opacity(0.5))

                    if hasYou {
                        Text(youUnread > 0 ? "You \(youUnread)" : "You")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(theme.accent)
                            .padding(.top, 2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(theme.accent.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.card)
            }
        }
        .background(isArchived ? Color(UIColor.systemGray5).opacity(0.06) : theme.surface)
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
        .overlay(alignment: .topLeading) {
            if isArchived {
                Text("Archived")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(6)
                    .padding(8)
            }
        }
    }
}

struct ThumbnailView: View {
    let board: String
    let tim: Int
    let ext: String?
    @Binding var selectedImageURL: URL?

    var body: some View {
        let fileExt = ext ?? ".jpg"
        let thumbURL = URL(string: "https://i.4cdn.org/\(board)/\(tim)s.jpg")
        let fullURL  = URL(string: "https://i.4cdn.org/\(board)/\(tim)\(fileExt)")

        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                if let url = thumbURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        default:
                            Color.gray.opacity(0.2)
                        }
                    }
                } else {
                    Color.gray.opacity(0.2)
                }

                if fileExt == ".webm" || fileExt == ".mp4" {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { selectedImageURL = fullURL }
    }
}

struct FavoritesView: View {
    @ObservedObject var favoritesManager = FavoritesManager.shared
    @ObservedObject private var siteDirectory = SiteDirectory.shared
    @ObservedObject private var youPostsManager = YouPostsManager.shared

    var body: some View {
        NavigationView {
            List {
                if favoritesManager.favorites.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "star")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No favorites yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Star threads to save them here")
                            .font(.subheadline)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(favoritesManager.favorites) { fav in
                        let site = siteDirectory.all.first(where: { $0.id == fav.siteID })
                        let hasYou = (fav.siteID == "4chan") && youPostsManager.isYouThread(boardID: fav.boardID, threadNo: fav.threadNo)
                        let youUnread = hasYou ? youPostsManager.unreadForThread(boardID: fav.boardID, threadNo: fav.threadNo) : 0
                        NavigationLink(destination: favoriteDestination(for: fav, site: site)) {
                            HStack(spacing: 12) {
                                favoriteThumb(for: fav, site: site)
                                    .frame(width: 50, height: 50)
                                    .cornerRadius(6)
                                    .clipped()

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(fav.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .lineLimit(1)
                                    Text("\(site?.displayName ?? fav.siteID) • /\(fav.boardID)/ • \(fav.threadNo.formatted(.number.grouping(.never)))")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                HStack(spacing: 6) {
                                    if hasYou {
                                        Text(youUnread > 0 ? "You \(youUnread)" : "You")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.accentColor)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 4)
                                            .background(Color.accentColor.opacity(0.10))
                                            .clipShape(Capsule())
                                    }

                                    if fav.unreadCount > 0 {
                                        Text("\(fav.unreadCount)")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.red)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 4)
                                            .background(Color.red.opacity(0.10))
                                            .clipShape(Capsule())
                                    }

                                    if fav.isDead == true {
                                        Text("404")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.red.opacity(0.12))
                                            .foregroundColor(.red)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { index in
                            let fav = favoritesManager.favorites[index]
                            favoritesManager.remove(siteID: fav.siteID, boardID: fav.boardID, threadNo: fav.threadNo)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Favorites")
            .refreshable {
                favoritesManager.checkForUpdates()
            }
        }
    }

    @ViewBuilder
    private func favoriteThumb(for fav: SavedThread, site: SiteDirectory.Site?) -> some View {
        if fav.siteID == "4chan" {
            if let tim = fav.tim, let url = URL(string: "https://i.4cdn.org/\(fav.boardID)/\(tim)s.jpg") {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.gray.opacity(0.2)
                    }
                }
            } else {
                Color.gray.opacity(0.2)
            }
        } else if let site, let mediaKey = fav.mediaKey, let ext = fav.ext {
            let thread = ExternalThread(
                no: fav.threadNo,
                sub: nil,
                com: nil,
                tim: nil,
                ext: ext,
                replies: nil,
                images: nil,
                fpath: fav.fpath,
                mediaKey: mediaKey,
                files: nil
            )
            let thumbURL = ExternalMediaURLBuilder.thumbnailURL(site: site, board: fav.boardID, thread: thread, preferSpoiler: false)
            HeaderAsyncImage(url: thumbURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
        } else {
            Color.gray.opacity(0.2)
        }
    }

    private func favoriteDestination(for fav: SavedThread, site: SiteDirectory.Site?) -> AnyView {
        if fav.siteID == "4chan" {
            return AnyView(ThreadDetailView(boardID: fav.boardID, threadNo: fav.threadNo, isArchived: false))
        }
        if let site {
            return AnyView(ExternalThreadDetailView(site: site, boardCode: fav.boardID, threadNo: fav.threadNo))
        }
        return AnyView(EmptyView())
    }
}

func cleanHTML(_ text: String) -> String {
    return text.replacingOccurrences(of: "<br>", with: "\n")
        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&#039;", with: "'")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&amp;", with: "&")
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}

private extension View {
    @ViewBuilder
    func conditionalSearchScopes<S: Hashable, Content: View>(
        _ condition: Bool,
        selection: Binding<S>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if condition {
            if #available(iOS 16.0, *) {
                self.searchScopes(selection) { content() }
            } else {
                self
            }
        } else { self }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
