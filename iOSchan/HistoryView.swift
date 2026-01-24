import SwiftUI

struct HistoryView: View {
    @ObservedObject private var historyManager = HistoryManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var youPostsManager = YouPostsManager.shared
    @ObservedObject private var siteDirectory = SiteDirectory.shared
    @State private var showNewPostsBanner: Bool = false
    @State private var newPostsCount: Int = 0

    @ViewBuilder
    private func destination(for item: SavedHistory, site: SiteDirectory.Site?) -> some View {
        if item.siteID == "4chan" {
            ThreadDetailView(boardID: item.boardID, threadNo: item.threadNo, isArchived: false)
        } else if let site {
            ExternalThreadDetailView(site: site, boardCode: item.boardID, threadNo: item.threadNo)
        } else {
            EmptyView()
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if showNewPostsBanner && newPostsCount > 0 {
                    HStack {
                        Image(systemName: "bell.badge.fill")
                            .foregroundColor(.accentColor)
                        Text("\(newPostsCount) new posts since last viewed")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.08))
                }

                List {
                    if historyManager.history.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "clock")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("No history yet")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Threads you visit will appear here")
                                .font(.subheadline)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(historyManager.history) { item in
                            let site = siteDirectory.all.first(where: { $0.id == item.siteID })
                            let siteName = site?.displayName ?? item.siteID
                            let hasYou = youPostsManager.isYouThread(siteID: item.siteID, boardID: item.boardID, threadNo: item.threadNo)
                            let youUnread = hasYou ? youPostsManager.unreadForThread(siteID: item.siteID, boardID: item.boardID, threadNo: item.threadNo) : 0

                            NavigationLink(destination: destination(for: item, site: site)) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .lineLimit(1)
                                        Text("\(siteName) • /\(item.boardID)/ • No. \(item.threadNo.formatted(.number.grouping(.never)))")
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
                                        if item.unreadCount > 0 {
                                            Text("\(item.unreadCount)")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(.red)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 4)
                                                .background(Color.red.opacity(0.10))
                                                .clipShape(Capsule())
                                        }

                                        if item.isDead == true {
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
                        .onDelete { idx in
                            idx.forEach { i in
                                let item = historyManager.history[i]
                                historyManager.remove(siteID: item.siteID, boardID: item.boardID, threadNo: item.threadNo)
                            }
                        }
                    }
                }
                .refreshable {
                    historyManager.checkForUpdates()
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !historyManager.history.isEmpty {
                        Button("Clear") { historyManager.clear() }
                            .font(.system(size: 15, weight: .medium))
                    }
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
