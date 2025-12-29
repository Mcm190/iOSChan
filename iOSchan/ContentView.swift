import SwiftUI

struct ContentView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @ObservedObject private var youManager = YouPostsManager.shared
    @ObservedObject private var historyManager = HistoryManager.shared
    @ObservedObject private var deepLink = DeepLinkRouter.shared
    
    var body: some View {
        TabView {
            BoardListView()
                .tabItem { Label("Boards", systemImage: "list.bullet") }

            FavoritesView()
                .tabItem { Label("Favorites", systemImage: "star.fill") }
                .badge(favoritesManager.totalUnreadCount)

            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
                .badge(historyManager.totalUnread + youManager.totalUnread)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .preferredColorScheme(settings.preferredColorScheme)
        .sheet(item: $deepLink.target) { target in
            ThreadDetailView(boardID: target.boardID, threadNo: target.threadNo, isArchived: false)
        }
    }
}

struct BoardListView: View {
    @State private var boards: [Board] = []
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @State private var showGlobalSearch = false

    var body: some View {
        NavigationView {
            List {
                if !favoritesManager.savedBoards.isEmpty {
                    Section("Favorites") {
                        ForEach(favoritesManager.savedBoards) { favBoard in
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
                    }
                }

                Section("All Boards") {
                    ForEach(boards.filter { !favoritesManager.isBoardFavorite($0.board) }, id: \.board) { board in
                        NavigationLink(destination: ThreadView(board: board)) {
                            BoardRow(board: board, isFavorite: favoritesManager.isBoardFavorite(board.board)) {
                                if favoritesManager.isBoardFavorite(board.board) {
                                    favoritesManager.removeBoard(boardCode: board.board)
                                } else {
                                    // Add to saved boards and also ensure local `boards` state contains this board
                                    favoritesManager.addBoard(board)
                                    if !boards.contains(where: { $0.board == board.board }) {
                                        boards.append(board)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("4chan Boards")
            .listStyle(.plain)
            .environment(\.dynamicTypeSize, settings.dynamicType)
            .onAppear {
                if boards.isEmpty {
                    fetchData()
                    UserDefaults.standard.set(true, forKey: "hasLoadedBoardsOnce")
                }
                BoardDirectory.shared.ensureLoaded()
            }
            .refreshable { fetchData() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: { showGlobalSearch = true }) {
                            Image(systemName: "magnifyingglass.circle")
                        }
                        Button(action: fetchData) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showGlobalSearch) {
            GlobalSearchView()
        }
    }

    func fetchData() {
        FourChanAPI.shared.fetchBoards { result in
            switch result {
            case .success(let fetchedBoards):
                DispatchQueue.main.async {
                    BoardDirectory.shared.update(with: fetchedBoards)
                    self.boards = fetchedBoards
                }
            case .failure(let error):
                print("Error fetching boards: \(error)")
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
    @State private var showNativeComposer = false
    private var boardURL: URL {
        URL(string: "https://boards.4chan.org/\(board.board)/")!
    }

    let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var isSFWBoard: Bool { BoardDirectory.shared.isSFW(boardID: board.board) }
    private var threadTint: Color { isSFWBoard ? .chanSFW : .chanNSFW }

    var body: some View {
        Group {
            if isGridView {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(filteredThreads, id: \.no) { thread in
                            ThreadGridCell(
                                board: board,
                                thread: thread,
                                selectedImageURL: $selectedImageURL,
                                isArchived: showArchived
                            )
                        }
                    }
                    .padding(10)
                }
                .refreshable { loadThreads() }
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: isSearchVisible ? .always : .automatic), prompt: "Search threads")
                .focused($isSearchFieldFocused)
                .environment(\.dynamicTypeSize, settings.dynamicType)
                .scrollContentBackground(.hidden)
                .background(threadTint.opacity(0.12))
            } else {
                List(filteredThreads, id: \.no) { thread in
                    ThreadListRow(
                        board: board,
                        thread: thread,
                        selectedImageURL: $selectedImageURL,
                        isArchived: showArchived
                    )
                    .listRowBackground(threadTint.opacity(0.20))
                }
                .listStyle(.plain)
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: isSearchVisible ? .always : .automatic), prompt: "Search threads")
                .focused($isSearchFieldFocused)
                .refreshable { loadThreads() }
                .environment(\.dynamicTypeSize, settings.dynamicType)
                .scrollContentBackground(.hidden)
                .background(threadTint.opacity(0.12))
            }
        }
        .navigationTitle("/\(board.board)/")
        .onAppear {
            let key = "hasLoaded_\(board.board)"
            // Always load if this instance has no data yet (first navigation)
            if threads.isEmpty {
                loadThreads()
            }
            // Preserve the original one-time marker for analytics/first-time behavior
            if UserDefaults.standard.object(forKey: key) == nil {
                UserDefaults.standard.set(true, forKey: key)
            }
        }
        .fullScreenCover(item: $selectedImageURL) { url in
            FullScreenImageView(imageURL: url)
        }

        .sheet(isPresented: $showSafariBoard) {
            SafariView(url: boardURL)
        }
        .sheet(isPresented: $showNativeComposer) {
            PostComposerNative(boardID: board.board, threadNo: nil)
        }

        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Picker("", selection: $showArchived) {
                    Text("Live").tag(false)
                    Text("Archived").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 200)
                .onChange(of: showArchived) { _ in loadThreads() }
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
                        Button(action: { showNativeComposer = true }) { Label("New Thread", systemImage: "square.and.pencil") }
                    }

                    Button(action: { isGridView.toggle() }) { Label(isGridView ? "List View" : "Grid View", systemImage: isGridView ? "list.bullet" : "square.grid.2x2") }
                } label: {
                    Image(systemName: "ellipsis")
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
                                showSafariBoard = true
                                showToolbarMenuPopover = false
                            }) {
                                Label("New Thread", systemImage: "square.and.pencil")
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let tim = thread.tim {
                ThumbnailView(board: board.board, tim: tim, ext: thread.ext, selectedImageURL: $selectedImageURL)
                    .frame(width: CGFloat(80) * settings.thumbnailScale, height: CGFloat(80) * settings.thumbnailScale)
            }

            NavigationLink(destination: ThreadDetailView(boardID: board.board, threadNo: thread.no, isArchived: isArchived)) {
                VStack(alignment: .leading, spacing: 5 * settings.density.spacingMultiplier) {
                    if let subject = thread.sub {
                        Text(cleanHTML(subject))
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let comment = thread.com {
                        Text(cleanHTML(comment))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(4)
                    }
                    HStack {
                        Text("No. \(thread.no.formatted(.number.grouping(.never)))")
                        Spacer()
                        if settings.showReplyCounts, let replies = thread.replies {
                            Text("R: \(replies)")
                        }
                        if settings.showImageCounts, let images = thread.images {
                            Text("I: \(images)")
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .padding(.top, 4)
                    if isArchived {
                        Text("Archived")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .padding(.vertical, 4 * settings.density.spacingMultiplier)
        .background(
            (isArchived ? Color(UIColor.systemGray5).opacity(0.06) : Color.clear)
                .blendMode(.normal)
        )
    }
}

struct ThreadGridCell: View {
    let board: Board
    let thread: Thread
    @Binding var selectedImageURL: URL?
    let isArchived: Bool
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let tim = thread.tim {
                ThumbnailView(board: board.board, tim: tim, ext: thread.ext, selectedImageURL: $selectedImageURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: CGFloat(150) * settings.thumbnailScale)
                    .clipped()
            }

                NavigationLink(destination: ThreadDetailView(boardID: board.board, threadNo: thread.no, isArchived: isArchived)) {
                VStack(alignment: .leading, spacing: 4 * settings.density.spacingMultiplier) {
                    if let subject = thread.sub {
                        Text(cleanHTML(subject))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let comment = thread.com {
                        Text(cleanHTML(comment))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                    HStack {
                        if settings.showReplyCounts { Text("R: \(thread.replies ?? 0)") }
                        Spacer()
                        if settings.showImageCounts { Text("I: \(thread.images ?? 0)") }
                    }
                    .font(.caption2)
                    .foregroundColor(.gray)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.systemBackground))
            }
        }
        .background(
            (isArchived ? Color(UIColor.systemGray5).opacity(0.06) : Color(UIColor.secondarySystemBackground).opacity(0.85))
        )
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        .overlay(alignment: .topLeading) {
            if isArchived {
                Text("Archived")
                    .font(.caption2)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(UIColor.systemBackground).opacity(0.7))
                    .cornerRadius(8)
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
                            Color.gray.opacity(0.3)
                        }
                    }
                } else {
                    Color.gray.opacity(0.3)
                }

                if fileExt == ".webm" || fileExt == ".mp4" {
                    Image(systemName: "video.fill")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        .padding(4)
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

    var body: some View {
        NavigationView {
            List {
                if favoritesManager.favorites.isEmpty {
                    Text("No favorites yet. Go star some threads!")
                        .foregroundColor(.gray)
                } else {
                    ForEach(favoritesManager.favorites) { fav in
                        NavigationLink(destination: ThreadDetailView(boardID: fav.boardID, threadNo: fav.threadNo, isArchived: false)) {
                            HStack {
                                if let tim = fav.tim {
                                    let url = URL(string: "https://i.4cdn.org/\(fav.boardID)/\(tim)s.jpg")
                                    AsyncImage(url: url) { phase in
                                        if let image = phase.image {
                                            image.resizable().scaledToFill()
                                        } else {
                                            Color.gray.opacity(0.3)
                                        }
                                    }
                                    .frame(width: 50, height: 50)
                                    .cornerRadius(4)
                                    .clipped()
                                }

                                VStack(alignment: .leading) {
                                    Text(fav.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                }
                                
                                if fav.unreadCount > 0 {
                                    Text("\(fav.unreadCount)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .background(Color.red.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                                
                                if fav.isDead == true {
                                    Text("404")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red.opacity(0.15))
                                        .foregroundColor(.red)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .listRowBackground((BoardDirectory.shared.isSFW(boardID: fav.boardID) ? Color.chanSFW : Color.chanNSFW).opacity(0.20))
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { index in
                            let fav = favoritesManager.favorites[index]
                            favoritesManager.remove(boardID: fav.boardID, threadNo: fav.threadNo)
                        }
                    }
                }
            }
            .navigationTitle("Favorites")
            .refreshable {
                favoritesManager.checkForUpdates()
            }
            .onAppear { BoardDirectory.shared.ensureLoaded() }
        }
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

