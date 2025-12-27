import SwiftUI

struct HistoryView: View {
    @ObservedObject private var historyManager = HistoryManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var showNewPostsBanner: Bool = false
    @State private var newPostsCount: Int = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 8) {
                if showNewPostsBanner && newPostsCount > 0 {
                    Text("\(newPostsCount) new posts since last viewed")
                        .font(.subheadline.weight(.semibold))
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }

                List {
                    if historyManager.history.isEmpty {
                        Text("No history yet. Open a thread to record it.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(historyManager.history) { item in
                            NavigationLink(destination: ThreadDetailView(boardID: item.boardID, threadNo: item.threadNo, isArchived: false)) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading) {
                                        Text(item.title)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Text("/\(item.boardID)/ • No. \(item.threadNo)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if item.unreadCount > 0 {
                                        Text("\(item.unreadCount)")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundColor(.red)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 4)
                                            .background(Color.red.opacity(0.12))
                                            .clipShape(Capsule())
                                    }

                                    if item.isDead == true {
                                        Text("404")
                                            .font(.caption2.bold())
                                            .padding(6)
                                            .background(Color.red.opacity(0.12))
                                            .foregroundColor(.red)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .listRowBackground((BoardDirectory.shared.isSFW(boardID: item.boardID) ? Color.chanSFW : Color.chanNSFW).opacity(0.20))
                        }
                        .onDelete { idx in
                            idx.forEach { i in
                                let item = historyManager.history[i]
                                historyManager.remove(boardID: item.boardID, threadNo: item.threadNo)
                            }
                        }
                    }
                }
                .refreshable {
                    historyManager.checkForUpdates()
                }
                .listStyle(.plain)
                .onAppear { BoardDirectory.shared.ensureLoaded() }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") { historyManager.clear() }
                }
            }
            .onAppear {
                let total = historyManager.totalUnread
                if total > 0 {
                    newPostsCount = total
                    showNewPostsBanner = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation { showNewPostsBanner = false }
                    }
                }
            }
        }
        .environment(\.dynamicTypeSize, settings.dynamicType)
    }
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
    }
}
