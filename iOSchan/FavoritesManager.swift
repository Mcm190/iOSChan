//
//  FavoritesManager.swift
//  iOSchan
//
//  Created by MCM on 20/12/2025.
//

import Foundation
import SwiftUI
import Combine

// 1. The data model for a saved thread
struct SavedThread: Codable, Identifiable {
    var id: String { "\(siteID)-\(boardID)-\(threadNo)" } // Unique ID (e.g. "4chan-g-123456")
    let siteID: String
    let boardID: String
    let threadNo: Int
    let title: String
    let tim: Int? // For the thumbnail
    let mediaKey: String?
    let ext: String?
    let fpath: Int?
    var isDead: Bool? // Optional flag to indicate 404 (dead) thread
    var lastReplyCount: Int? // Last known total replies (posts.count - 1)
    var unreadCount: Int // New replies since last seen, defaults to 0 with Codable

    private enum CodingKeys: String, CodingKey {
        case siteID, boardID, threadNo, title, tim, mediaKey, ext, fpath, isDead, lastReplyCount, unreadCount
    }

    init(
        siteID: String,
        boardID: String,
        threadNo: Int,
        title: String,
        tim: Int?,
        mediaKey: String?,
        ext: String?,
        fpath: Int?,
        isDead: Bool?,
        lastReplyCount: Int?,
        unreadCount: Int
    ) {
        self.siteID = siteID
        self.boardID = boardID
        self.threadNo = threadNo
        self.title = title
        self.tim = tim
        self.mediaKey = mediaKey
        self.ext = ext
        self.fpath = fpath
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
        self.mediaKey = try container.decodeIfPresent(String.self, forKey: .mediaKey) ?? tim.map(String.init)
        self.ext = try container.decodeIfPresent(String.self, forKey: .ext)
        self.fpath = try container.decodeIfPresent(Int.self, forKey: .fpath)
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
        try container.encodeIfPresent(mediaKey, forKey: .mediaKey)
        try container.encodeIfPresent(ext, forKey: .ext)
        try container.encodeIfPresent(fpath, forKey: .fpath)
        try container.encodeIfPresent(isDead, forKey: .isDead)
        try container.encodeIfPresent(lastReplyCount, forKey: .lastReplyCount)
        try container.encode(unreadCount, forKey: .unreadCount)
    }
}

// 2a. The data model for a saved board
struct SavedBoard: Codable, Identifiable {
    var id: String { board }
    let board: String
    let title: String
}

// 2. The Manager Class
class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager() // Singleton
    
    @Published var favorites: [SavedThread] = []
    @Published var savedBoards: [SavedBoard] = []
    
    var totalUnreadCount: Int { favorites.reduce(0) { $0 + $1.unreadCount } }
    
    private var pollTimer: Timer?
    
    init() {
        load()
        startPolling()
    }
    
    // Save a thread
    func add(boardID: String, threadNo: Int, title: String, tim: Int?) {
        let mediaKey = tim.map(String.init)
        let newFavorite = SavedThread(siteID: "4chan", boardID: boardID, threadNo: threadNo, title: title, tim: tim, mediaKey: mediaKey, ext: nil, fpath: nil, isDead: nil, lastReplyCount: nil, unreadCount: 0)
        if !favorites.contains(where: { $0.id == newFavorite.id }) {
            favorites.append(newFavorite)
            save()
            MediaCacheManager.prefetchThread(boardID: boardID, threadNo: threadNo)
        }
    }

    func add(siteID: String, boardID: String, threadNo: Int, title: String, mediaKey: String?, ext: String?, fpath: Int?) {
        let newFavorite = SavedThread(siteID: siteID, boardID: boardID, threadNo: threadNo, title: title, tim: nil, mediaKey: mediaKey, ext: ext, fpath: fpath, isDead: nil, lastReplyCount: nil, unreadCount: 0)
        if !favorites.contains(where: { $0.id == newFavorite.id }) {
            favorites.append(newFavorite)
            save()
        }
    }

    // Save / remove a board from favorites
    func addBoard(_ board: Board) {
        let sb = SavedBoard(board: board.board, title: board.title)
        if !savedBoards.contains(where: { $0.id == sb.id }) {
            savedBoards.append(sb)
            saveBoards()
        }
    }

    func removeBoard(boardCode: String) {
        savedBoards.removeAll { $0.board == boardCode }
        saveBoards()
    }

    func isBoardFavorite(_ boardCode: String) -> Bool {
        savedBoards.contains { $0.board == boardCode }
    }
    
    // Remove a thread
    func remove(siteID: String = "4chan", boardID: String, threadNo: Int) {
        favorites.removeAll { $0.siteID == siteID && $0.boardID == boardID && $0.threadNo == threadNo }
        save()
    }
    
    // Check if it's already favorited
    func isFavorite(siteID: String = "4chan", boardID: String, threadNo: Int) -> Bool {
        return favorites.contains { $0.siteID == siteID && $0.boardID == boardID && $0.threadNo == threadNo }
    }
    
    // Internal save/load logic
    private func save() {
        if let encoded = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(encoded, forKey: "savedThreads")
        }
    }
    private func saveBoards() {
        if let encoded = try? JSONEncoder().encode(savedBoards) {
            UserDefaults.standard.set(encoded, forKey: "savedBoards")
        }
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: "savedThreads"),
           let decoded = try? JSONDecoder().decode([SavedThread].self, from: data) {
            favorites = decoded
        }

        if let dataB = UserDefaults.standard.data(forKey: "savedBoards"),
           let decodedB = try? JSONDecoder().decode([SavedBoard].self, from: dataB) {
            savedBoards = decodedB
        }
    }
    
    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
        // Bootstrap counts on launch without generating unread
        bootstrapLastCounts()
    }

    private func bootstrapLastCounts() {
        for fav in favorites where fav.siteID == "4chan" {
            FourChanAPI.shared.fetchThreadDetails(board: fav.boardID, threadNo: fav.threadNo) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let posts):
                    let count = max(0, posts.count - 1)
                    if let idx = self.favorites.firstIndex(where: { $0.boardID == fav.boardID && $0.threadNo == fav.threadNo }) {
                        if self.favorites[idx].lastReplyCount == nil {
                            self.favorites[idx].lastReplyCount = count
                            self.save()
                        }
                    }
                case .failure:
                    // Ignore bootstrap failures
                    break
                }
            }
        }
    }

    func checkForUpdates() {
        for fav in favorites where fav.siteID == "4chan" && fav.isDead != true {
            FourChanAPI.shared.fetchThreadDetails(board: fav.boardID, threadNo: fav.threadNo) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let posts):
                    let count = max(0, posts.count - 1)
                    if let idx = self.favorites.firstIndex(where: { $0.boardID == fav.boardID && $0.threadNo == fav.threadNo }) {
                        let last = self.favorites[idx].lastReplyCount ?? count
                        if count > last {
                            self.favorites[idx].unreadCount += (count - last)
                        }
                        self.favorites[idx].lastReplyCount = count
                        self.save()
                        // Also update history unread counts if this thread exists in history
                        HistoryManager.shared.updateCounts(boardID: fav.boardID, threadNo: fav.threadNo, replyCount: count)
                    }
                case .failure(let error):
                    // Only mark dead on explicit 404 from the API; ignore transient/network errors
                    if let apiErr = error as? APIError {
                        if case .notFound = apiErr {
                            self.markDead(boardID: fav.boardID, threadNo: fav.threadNo)
                            HistoryManager.shared.markDead(boardID: fav.boardID, threadNo: fav.threadNo)
                        }
                    }
                }
            }
        }

        // Also refresh (You) reply counts on the same cadence as favorites polling.
        YouPostsManager.shared.checkForUpdates()
    }

    func markSeen(boardID: String, threadNo: Int, replyCount: Int) {
        if let idx = favorites.firstIndex(where: { $0.siteID == "4chan" && $0.boardID == boardID && $0.threadNo == threadNo }) {
            favorites[idx].lastReplyCount = replyCount
            favorites[idx].unreadCount = 0
            save()
        }
    }
    
    func markDead(boardID: String, threadNo: Int) {
        if let idx = favorites.firstIndex(where: { $0.siteID == "4chan" && $0.boardID == boardID && $0.threadNo == threadNo }) {
            favorites[idx].isDead = true
            save()
        }
    }
    
    func clearAll() {
        favorites.removeAll()
        save()
    }
    
    func resetDeadMarkers() {
        for i in favorites.indices {
            favorites[i].isDead = nil
        }
        save()
    }
}
