import SwiftUI

struct GlobalSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var isSearching = false
    @State private var progressText: String = ""
    @State private var results: [SearchResult] = []
    @State private var searchArchived: Bool = false
    @State private var boards: [Board] = []
    @State private var selectedBoards: Set<String> = []

    actor _SearchAccumulator {
        var items: [SearchResult] = []
        func append(contentsOf new: [SearchResult]) {
            items.append(contentsOf: new)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Field
                HStack {
                    TextField("Search across all boards", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                    if isSearching {
                        ProgressView()
                            .padding(.leading, 6)
                    }
                }
                .padding()

                if !boards.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(boards, id: \.board) { b in
                                let isOn = selectedBoards.contains(b.board)
                                Button(action: {
                                    if isOn { selectedBoards.remove(b.board) } else { selectedBoards.insert(b.board) }
                                }) {
                                    Text("/\(b.board)/")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(isOn ? Color.blue.opacity(0.15) : Color(UIColor.secondarySystemBackground))
                                        .foregroundColor(isOn ? .blue : .primary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }
                HStack {
                    Picker("", selection: $searchArchived) {
                        Text("Live").tag(false)
                        Text("Archived").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                .padding(.horizontal)
                .padding(.bottom, 6)

                if !progressText.isEmpty {
                    Text(progressText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 6)
                }

                List(results) { r in
                    NavigationLink(destination: ThreadDetailView(boardID: r.boardID, threadNo: r.threadNo, isArchived: false)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.subject ?? r.snippet)
                                .font(.headline)
                                .lineLimit(2)
                            Text("/\(r.boardID)/ • No. \(r.threadNo)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let sub = r.subject { Text(r.snippet).font(.caption).foregroundColor(.secondary).lineLimit(2) }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Global Search")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Search") { Task { await performSearch() } }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                }
            }
            .onAppear { loadBoards() }
        }
    }

    private func loadBoards() {
        FourChanAPI.shared.fetchBoards { result in
            switch result {
            case .success(let fetchedBoards):
                DispatchQueue.main.async {
                    self.boards = fetchedBoards
                    // default to all boards selected
                    self.selectedBoards = Set(fetchedBoards.map { $0.board })
                }
            case .failure(let error):
                print("Failed to load boards: \(error)")
            }
        }
    }

    private func performSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        await MainActor.run {
            isSearching = true
            results = []
            progressText = searchArchived ? "Fetching archives..." : "Fetching catalogs..."
        }

        let boardsToSearch = Array(selectedBoards)
        var tempResults: [SearchResult] = []
        let accumulator = _SearchAccumulator()

        await withTaskGroup(of: Void.self) { group in
            for b in boardsToSearch {
                group.addTask {
                    do {
                        let threads = try await (searchArchived ? fetchArchivedOPs(boardID: b) : fetchCatalog(boardID: b))
                        let filtered = threads.filter { t in
                            let sub = t.sub.map(cleanHTML) ?? ""
                            let com = t.com.map(cleanHTML) ?? ""
                            return sub.localizedCaseInsensitiveContains(q) || com.localizedCaseInsensitiveContains(q)
                        }
                        let mapped = filtered.map { SearchResult(boardID: b, threadNo: $0.no, subject: $0.sub.map(cleanHTML), snippet: ($0.com.map(cleanHTML) ?? "").prefix(160).description) }
                        await accumulator.append(contentsOf: mapped)
                        await MainActor.run { progressText = "Searched /\(b)/ (\(filtered.count) matches)" }
                    } catch {
                        await MainActor.run { progressText = "Failed /\(b)/" }
                    }
                }
            }
        }
        let final = await accumulator.items
        await MainActor.run {
            results = final.sorted(by: { lhs, rhs in
                if lhs.boardID == rhs.boardID { return lhs.threadNo > rhs.threadNo }
                return lhs.boardID < rhs.boardID
            })
            isSearching = false
            if results.isEmpty { progressText = "No matches found." } else { progressText = "Found \(results.count) matches." }
        }
    }

    private func fetchCatalog(boardID: String) async throws -> [Thread] {
        return try await withCheckedThrowingContinuation { cont in
            FourChanAPI.shared.fetchThreads(boardID: boardID) { result in
                switch result {
                case .success(let threads): cont.resume(returning: threads)
                case .failure(let error): cont.resume(throwing: error)
                }
            }
        }
    }

    private func fetchArchivedOPs(boardID: String) async throws -> [Thread] {
        return try await withCheckedThrowingContinuation { cont in
            FourChanAPI.shared.fetchArchivedThreads(boardID: boardID) { result in
                switch result {
                case .success(let threads): cont.resume(returning: threads)
                case .failure(let error): cont.resume(throwing: error)
                }
            }
        }
    }
}

struct SearchResult: Identifiable {
    var id: String { "\(boardID)-\(threadNo)" }
    let boardID: String
    let threadNo: Int
    let subject: String?
    let snippet: String
}
