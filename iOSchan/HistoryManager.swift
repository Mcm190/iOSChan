import Foundation
import Combine

struct SavedHistory: Codable, Identifiable {
    var id: String { "\(boardID)-\(threadNo)" }
    let boardID: String
    let threadNo: Int
    var title: String
    var tim: Int?
    var lastVisited: Date
    var isDead: Bool?
    // Track last known reply count and unread count for history view
    var lastReplyCount: Int?
    var unreadCount: Int
}

class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published var history: [SavedHistory] = []
    // When the user last opened the History tab
    @Published var lastViewedAt: Date? = nil
    private var pollTimer: Timer?

    private init() { load(); startPolling() }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
        bootstrapLastCounts()
    }

    private func bootstrapLastCounts() {
        for item in history {
            FourChanAPI.shared.fetchThreadDetails(board: item.boardID, threadNo: item.threadNo) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let posts):
                    let count = max(0, posts.count - 1)
                    if let idx = self.history.firstIndex(where: { $0.boardID == item.boardID && $0.threadNo == item.threadNo }) {
                        if self.history[idx].lastReplyCount == nil {
                            self.history[idx].lastReplyCount = count
                            self.save()
                        }
                    }
                case .failure:
                    break
                }
            }
        }
    }

    func checkForUpdates() {
        for item in history where item.isDead != true {
            FourChanAPI.shared.fetchThreadDetails(board: item.boardID, threadNo: item.threadNo) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let posts):
                    let count = max(0, posts.count - 1)
                    if let idx = self.history.firstIndex(where: { $0.boardID == item.boardID && $0.threadNo == item.threadNo }) {
                        let last = self.history[idx].lastReplyCount ?? count
                        if count > last {
                            self.history[idx].unreadCount += (count - last)
                        }
                        self.history[idx].lastReplyCount = count
                        self.save()
                    }
                case .failure(let error):
                    // Only mark dead on explicit 404 from API; ignore transient errors
                    if let apiErr = error as? APIError, case .notFound = apiErr {
                        if let idx = self.history.firstIndex(where: { $0.boardID == item.boardID && $0.threadNo == item.threadNo }) {
                            self.history[idx].isDead = true
                            self.save()
                        }
                    }
                }
            }
        }
    }

    func add(boardID: String, threadNo: Int, title: String, tim: Int?) {
        let normalizedTitle = title
        let now = Date()
        if let idx = history.firstIndex(where: { $0.boardID == boardID && $0.threadNo == threadNo }) {
            history[idx].title = normalizedTitle
            history[idx].tim = tim
            history[idx].lastVisited = now
            history[idx].isDead = nil
            // reset unread when revisited
            history[idx].unreadCount = 0
        } else {
            let item = SavedHistory(boardID: boardID, threadNo: threadNo, title: normalizedTitle, tim: tim, lastVisited: now, isDead: nil, lastReplyCount: nil, unreadCount: 0)
            history.insert(item, at: 0)
        }
        save()
    }

    // Update counts for a thread (called from FavoritesManager polling)
    func updateCounts(boardID: String, threadNo: Int, replyCount: Int) {
        if let idx = history.firstIndex(where: { $0.boardID == boardID && $0.threadNo == threadNo }) {
            let last = history[idx].lastReplyCount ?? replyCount
            if replyCount > last {
                history[idx].unreadCount += (replyCount - last)
            }
            history[idx].lastReplyCount = replyCount
            save()
        }
    }

    // Compute total new posts across history
    var totalUnread: Int {
        history.reduce(0) { $0 + $1.unreadCount }
    }

    // Mark history tab as viewed (clears unread counters)
    func markHistoryViewed() {
        lastViewedAt = Date()
        for i in history.indices {
            history[i].unreadCount = 0
        }
        save()
    }

    func remove(boardID: String, threadNo: Int) {
        history.removeAll { $0.boardID == boardID && $0.threadNo == threadNo }
        save()
    }

    func clear() {
        history.removeAll()
        save()
    }

    func markDead(boardID: String, threadNo: Int) {
        if let idx = history.firstIndex(where: { $0.boardID == boardID && $0.threadNo == threadNo }) {
            history[idx].isDead = true
            save()
        }
    }

    func markAlive(boardID: String, threadNo: Int) {
        if let idx = history.firstIndex(where: { $0.boardID == boardID && $0.threadNo == threadNo }) {
            history[idx].isDead = nil
            save()
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: "savedHistory")
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: "savedHistory"),
           let decoded = try? JSONDecoder().decode([SavedHistory].self, from: data) {
            history = decoded
        }
    }
}
