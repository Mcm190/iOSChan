import Foundation
import Combine

struct SavedHistory: Codable, Identifiable {
    var id: String { "\(siteID)-\(boardID)-\(threadNo)" }
    let siteID: String
    let boardID: String
    let threadNo: Int
    var title: String
    var tim: Int?
    var lastVisited: Date
    var isDead: Bool?
    // Track last known reply count and unread count for history view
    var lastReplyCount: Int?
    var unreadCount: Int

    private enum CodingKeys: String, CodingKey {
        case siteID, boardID, threadNo, title, tim, lastVisited, isDead, lastReplyCount, unreadCount
    }

    init(
        siteID: String,
        boardID: String,
        threadNo: Int,
        title: String,
        tim: Int?,
        lastVisited: Date,
        isDead: Bool?,
        lastReplyCount: Int?,
        unreadCount: Int
    ) {
        self.siteID = siteID
        self.boardID = boardID
        self.threadNo = threadNo
        self.title = title
        self.tim = tim
        self.lastVisited = lastVisited
        self.isDead = isDead
        self.lastReplyCount = lastReplyCount
        self.unreadCount = unreadCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.siteID = try container.decodeIfPresent(String.self, forKey: .siteID) ?? "4chan"
        self.boardID = try container.decode(String.self, forKey: .boardID)
        self.threadNo = try container.decode(Int.self, forKey: .threadNo)
        self.title = try container.decode(String.self, forKey: .title)
        self.tim = try container.decodeIfPresent(Int.self, forKey: .tim)
        self.lastVisited = try container.decodeIfPresent(Date.self, forKey: .lastVisited) ?? Date()
        self.isDead = try container.decodeIfPresent(Bool.self, forKey: .isDead)
        self.lastReplyCount = try container.decodeIfPresent(Int.self, forKey: .lastReplyCount)
        self.unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(siteID, forKey: .siteID)
        try container.encode(boardID, forKey: .boardID)
        try container.encode(threadNo, forKey: .threadNo)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(tim, forKey: .tim)
        try container.encode(lastVisited, forKey: .lastVisited)
        try container.encodeIfPresent(isDead, forKey: .isDead)
        try container.encodeIfPresent(lastReplyCount, forKey: .lastReplyCount)
        try container.encode(unreadCount, forKey: .unreadCount)
    }
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
            if item.siteID == "4chan" {
                FourChanAPI.shared.fetchThreadDetails(board: item.boardID, threadNo: item.threadNo) { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .success(let posts):
                        let count = max(0, posts.count - 1)
                        if let idx = self.history.firstIndex(where: { $0.siteID == item.siteID && $0.boardID == item.boardID && $0.threadNo == item.threadNo }) {
                            if self.history[idx].lastReplyCount == nil {
                                self.history[idx].lastReplyCount = count
                                self.save()
                            }
                        }
                    case .failure:
                        break
                    }
                }
            } else if let site = SiteDirectory.shared.all.first(where: { $0.id == item.siteID }) {
                VichanThreadAPI.fetchThread(site: site, boardCode: item.boardID, threadNo: item.threadNo) { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .success(let posts):
                        let count = max(0, posts.count - 1)
                        if let idx = self.history.firstIndex(where: { $0.siteID == item.siteID && $0.boardID == item.boardID && $0.threadNo == item.threadNo }) {
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
    }

    func checkForUpdates() {
        for item in history where item.isDead != true {
            if item.siteID == "4chan" {
                FourChanAPI.shared.fetchThreadDetails(board: item.boardID, threadNo: item.threadNo) { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .success(let posts):
                        let count = max(0, posts.count - 1)
                        if let idx = self.history.firstIndex(where: { $0.siteID == item.siteID && $0.boardID == item.boardID && $0.threadNo == item.threadNo }) {
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
                            if let idx = self.history.firstIndex(where: { $0.siteID == item.siteID && $0.boardID == item.boardID && $0.threadNo == item.threadNo }) {
                                self.history[idx].isDead = true
                                self.save()
                            }
                        }
                    }
                }
            } else if let site = SiteDirectory.shared.all.first(where: { $0.id == item.siteID }) {
                VichanThreadAPI.fetchThread(site: site, boardCode: item.boardID, threadNo: item.threadNo) { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .success(let posts):
                        let count = max(0, posts.count - 1)
                        if let idx = self.history.firstIndex(where: { $0.siteID == item.siteID && $0.boardID == item.boardID && $0.threadNo == item.threadNo }) {
                            let last = self.history[idx].lastReplyCount ?? count
                            if count > last {
                                self.history[idx].unreadCount += (count - last)
                            }
                            self.history[idx].lastReplyCount = count
                            self.save()
                        }
                    case .failure:
                        break
                    }
                }
            }
        }
    }

    func add(siteID: String = "4chan", boardID: String, threadNo: Int, title: String, tim: Int?, replyCount: Int? = nil) {
        let normalizedTitle = title
        let now = Date()
        if let idx = history.firstIndex(where: { $0.siteID == siteID && $0.boardID == boardID && $0.threadNo == threadNo }) {
            history[idx].title = normalizedTitle
            history[idx].tim = tim
            history[idx].lastVisited = now
            history[idx].isDead = nil
            // reset unread when revisited
            history[idx].unreadCount = 0
            if let replyCount {
                history[idx].lastReplyCount = replyCount
            }
        } else {
            let item = SavedHistory(siteID: siteID, boardID: boardID, threadNo: threadNo, title: normalizedTitle, tim: tim, lastVisited: now, isDead: nil, lastReplyCount: replyCount, unreadCount: 0)
            history.insert(item, at: 0)
        }
        save()
    }

    // Update counts for a thread (called from FavoritesManager polling)
    func updateCounts(siteID: String = "4chan", boardID: String, threadNo: Int, replyCount: Int) {
        if let idx = history.firstIndex(where: { $0.siteID == siteID && $0.boardID == boardID && $0.threadNo == threadNo }) {
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
        remove(siteID: "4chan", boardID: boardID, threadNo: threadNo)
    }

    func remove(siteID: String = "4chan", boardID: String, threadNo: Int) {
        history.removeAll { $0.siteID == siteID && $0.boardID == boardID && $0.threadNo == threadNo }
        save()
    }

    func clear() {
        history.removeAll()
        save()
    }

    func markDead(siteID: String = "4chan", boardID: String, threadNo: Int) {
        if let idx = history.firstIndex(where: { $0.siteID == siteID && $0.boardID == boardID && $0.threadNo == threadNo }) {
            history[idx].isDead = true
            save()
        }
    }

    func markAlive(siteID: String = "4chan", boardID: String, threadNo: Int) {
        if let idx = history.firstIndex(where: { $0.siteID == siteID && $0.boardID == boardID && $0.threadNo == threadNo }) {
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
