import Foundation
import Combine
import UserNotifications
import UIKit

private struct ThreadKey: Hashable { let siteID: String; let boardID: String; let threadNo: Int }

struct YouMark: Codable, Identifiable, Hashable {
    var id: String { "\(siteID)-\(boardID)-\(threadNo)-\(postNo)" }
    let siteID: String
    let boardID: String
    let threadNo: Int
    let postNo: Int
    var knownReplies: [Int] // store as array for Codable simplicity
    var unreadCount: Int

    private enum CodingKeys: String, CodingKey {
        case siteID, boardID, threadNo, postNo, knownReplies, unreadCount
    }

    init(siteID: String, boardID: String, threadNo: Int, postNo: Int, knownReplies: [Int], unreadCount: Int) {
        self.siteID = siteID
        self.boardID = boardID
        self.threadNo = threadNo
        self.postNo = postNo
        self.knownReplies = knownReplies
        self.unreadCount = unreadCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.siteID = try container.decodeIfPresent(String.self, forKey: .siteID) ?? "4chan"
        self.boardID = try container.decode(String.self, forKey: .boardID)
        self.threadNo = try container.decode(Int.self, forKey: .threadNo)
        self.postNo = try container.decode(Int.self, forKey: .postNo)
        self.knownReplies = try container.decodeIfPresent([Int].self, forKey: .knownReplies) ?? []
        self.unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(siteID, forKey: .siteID)
        try container.encode(boardID, forKey: .boardID)
        try container.encode(threadNo, forKey: .threadNo)
        try container.encode(postNo, forKey: .postNo)
        try container.encode(knownReplies, forKey: .knownReplies)
        try container.encode(unreadCount, forKey: .unreadCount)
    }
}

final class YouPostsManager: ObservableObject {
    static let shared = YouPostsManager()

    @Published private(set) var marks: [YouMark] = []
    private var timer: Timer?
    private let queue = DispatchQueue(label: "youposts.check.queue", qos: .utility)

    private init() {
        load()
        startTimer()
        updateBadge()
    }

    var totalUnread: Int { marks.reduce(0) { $0 + $1.unreadCount } }

    func marks(siteID: String = "4chan", boardID: String, threadNo: Int) -> [YouMark] {
        marks.filter { $0.siteID == siteID && $0.boardID == boardID && $0.threadNo == threadNo }
    }

    func isYouThread(siteID: String = "4chan", boardID: String, threadNo: Int) -> Bool {
        marks.contains { $0.siteID == siteID && $0.boardID == boardID && $0.threadNo == threadNo }
    }

    func unreadForThread(siteID: String = "4chan", boardID: String, threadNo: Int) -> Int {
        marks(siteID: siteID, boardID: boardID, threadNo: threadNo).reduce(0) { $0 + $1.unreadCount }
    }

    func isYou(siteID: String = "4chan", boardID: String, threadNo: Int, postNo: Int) -> Bool {
        marks.contains { $0.siteID == siteID && $0.boardID == boardID && $0.threadNo == threadNo && $0.postNo == postNo }
    }

    func markYou(siteID: String = "4chan", boardID: String, threadNo: Int, postNo: Int, threadTitle: String?, tim: Int?, knownReplies: [Int] = []) {
        if !isYou(siteID: siteID, boardID: boardID, threadNo: threadNo, postNo: postNo) {
            let unique = Array(Set(knownReplies)).sorted()
            marks.append(YouMark(siteID: siteID, boardID: boardID, threadNo: threadNo, postNo: postNo, knownReplies: unique, unreadCount: 0))
            save()
            ensureNotifications()
            if siteID == "4chan", !FavoritesManager.shared.isFavorite(boardID: boardID, threadNo: threadNo) {
                let title = threadTitle ?? "Thread \(threadNo)"
                FavoritesManager.shared.add(boardID: boardID, threadNo: threadNo, title: title, tim: tim)
            }
        }
    }

    func unmarkYou(siteID: String = "4chan", boardID: String, threadNo: Int, postNo: Int) {
        marks.removeAll { $0.siteID == siteID && $0.boardID == boardID && $0.threadNo == threadNo && $0.postNo == postNo }
        save()
        updateBadge()
    }

    func toggleYou(siteID: String = "4chan", boardID: String, threadNo: Int, postNo: Int, threadTitle: String?, tim: Int?, knownReplies: [Int] = []) {
        if isYou(siteID: siteID, boardID: boardID, threadNo: threadNo, postNo: postNo) {
            unmarkYou(siteID: siteID, boardID: boardID, threadNo: threadNo, postNo: postNo)
        } else {
            markYou(siteID: siteID, boardID: boardID, threadNo: threadNo, postNo: postNo, threadTitle: threadTitle, tim: tim, knownReplies: knownReplies)
        }
    }

    func clearUnreadForThread(siteID: String = "4chan", boardID: String, threadNo: Int) {
        var changed = false
        for i in marks.indices {
            if marks[i].siteID == siteID && marks[i].boardID == boardID && marks[i].threadNo == threadNo {
                if marks[i].unreadCount != 0 { marks[i].unreadCount = 0; changed = true }
            }
        }
        if changed { save(); updateBadge() }
    }
    
    func clearAllUnread() {
        var changed = false
        for i in marks.indices {
            if marks[i].unreadCount != 0 {
                marks[i].unreadCount = 0
                changed = true
            }
        }
        if changed {
            save()
            updateBadge()
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
    }

    func checkForUpdates() {
        checkForUpdates(completion: nil)
    }

    func checkForUpdates(completion: (() -> Void)?) {
        let marksToScan = marks.filter { $0.siteID == "4chan" }
        let grouped = Dictionary(grouping: marksToScan, by: { ThreadKey(siteID: $0.siteID, boardID: $0.boardID, threadNo: $0.threadNo) })

        guard !grouped.isEmpty else {
            completion?()
            return
        }

        let dispatchGroup = DispatchGroup()

        for (key, _) in grouped {
            dispatchGroup.enter()
            FourChanAPI.shared.fetchThreadDetails(board: key.boardID, threadNo: key.threadNo) { [weak self] result in
                defer { dispatchGroup.leave() }
                guard let self = self else { return }
                switch result {
                case .success(let posts):
                    self.process(posts: posts, boardID: key.boardID, threadNo: key.threadNo)
                case .failure:
                    break
                }
            }
        }

        dispatchGroup.notify(queue: queue) {
            completion?()
        }
    }

    private func fetchAndScan(boardID: String, threadNo: Int) {
        FourChanAPI.shared.fetchThreadDetails(board: boardID, threadNo: threadNo) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let posts):
                self.process(posts: posts, boardID: boardID, threadNo: threadNo)
            case .failure:
                break
            }
        }
    }

    private func process(posts: [Thread], boardID: String, threadNo: Int) {
        let pattern = #">>(\d+)"#
        let regex = try? NSRegularExpression(pattern: pattern)

        var quotesByPost: [Int: Set<Int>] = [:]
        for p in posts {
            guard let raw = p.com else { continue }
            let cleaned = cleanHTML(raw)
            let ns = cleaned as NSString
            let matches = regex?.matches(in: cleaned, range: NSRange(location: 0, length: ns.length)) ?? []
            var set: Set<Int> = []
            for m in matches {
                if m.numberOfRanges >= 2 {
                    let r = m.range(at: 1)
                    if r.location != NSNotFound, let target = Int(ns.substring(with: r)) {
                        set.insert(target)
                    }
                }
            }
            if !set.isEmpty { quotesByPost[p.no] = set }
        }

        DispatchQueue.main.async {
            var newTotal = 0
            var changed = false
            for i in self.marks.indices {
                guard self.marks[i].siteID == "4chan", self.marks[i].boardID == boardID && self.marks[i].threadNo == threadNo else { continue }
                let youNo = self.marks[i].postNo
                let known = Set(self.marks[i].knownReplies)
                var newlyFound: [Int] = []
                for (postNo, quoted) in quotesByPost {
                    if quoted.contains(youNo) && !known.contains(postNo) {
                        newlyFound.append(postNo)
                    }
                }
                if !newlyFound.isEmpty {
                    self.marks[i].knownReplies.append(contentsOf: newlyFound)
                    self.marks[i].unreadCount += newlyFound.count
                    newTotal += newlyFound.count
                    changed = true
                }
            }

            if changed {
                self.save()
                self.updateBadge()
                if newTotal > 0 {
                    self.notify(boardID: boardID, threadNo: threadNo, count: newTotal)
                }
            }
        }
    }

func setCustomSound(name: String?) {
    let key = "youCustomSoundName"
    if let name, !name.isEmpty {
        UserDefaults.standard.set(name, forKey: key)
    } else {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

var customSoundName: String? {
    UserDefaults.standard.string(forKey: "youCustomSoundName")
}

    private func notify(boardID: String, threadNo: Int, count: Int) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "New replies to your post in /\(boardID)/"
        content.body = "\(count) new repl\(count == 1 ? "y" : "ies") to your (You) post"
        if let name = UserDefaults.standard.string(forKey: "youCustomSoundName"), !name.isEmpty {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(name))
        } else {
            content.sound = .default
        }
        content.badge = NSNumber(value: totalUnread)
        content.userInfo = ["boardID": boardID, "threadNo": threadNo]
        let request = UNNotificationRequest(identifier: "you-replies-\(boardID)-\(threadNo)-\(UUID().uuidString)", content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    private func ensureNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
            }
            DispatchQueue.main.async {
                UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
            }
        }
    }

    private func updateBadge() {
        DispatchQueue.main.async {
            if #available(iOS 17.0, *) {
                UNUserNotificationCenter.current().setBadgeCount(self.totalUnread) { _ in }
            } else {
                UIApplication.shared.applicationIconBadgeNumber = self.totalUnread
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(marks) {
            UserDefaults.standard.set(data, forKey: "youMarks")
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: "youMarks"),
           let decoded = try? JSONDecoder().decode([YouMark].self, from: data) {
            marks = decoded
        }
    }
}

final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCenterDelegate()
    private override init() { super.init() }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let boardID = info["boardID"] as? String,
           let threadNo = info["threadNo"] as? Int {
            DeepLinkRouter.shared.open(boardID: boardID, threadNo: threadNo)
        }
        completionHandler()
    }
}
