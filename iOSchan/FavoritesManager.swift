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
    var id: String { "\(boardID)-\(threadNo)" } // Unique ID (e.g. "g-123456")
    let boardID: String
    let threadNo: Int
    let title: String
    let tim: Int? // For the thumbnail
    var isDead: Bool? // Optional flag to indicate 404 (dead) thread
    var lastReplyCount: Int? // Last known total replies (posts.count - 1)
    var unreadCount: Int // New replies since last seen, defaults to 0 with Codable
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
        let newFavorite = SavedThread(boardID: boardID, threadNo: threadNo, title: title, tim: tim, isDead: nil, lastReplyCount: nil, unreadCount: 0)
        if !favorites.contains(where: { $0.id == newFavorite.id }) {
            favorites.append(newFavorite)
            save()
            MediaCacheManager.prefetchThread(boardID: boardID, threadNo: threadNo)
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
    func remove(boardID: String, threadNo: Int) {
        favorites.removeAll { $0.boardID == boardID && $0.threadNo == threadNo }
        save()
    }
    
    // Check if it's already favorited
    func isFavorite(boardID: String, threadNo: Int) -> Bool {
        return favorites.contains { $0.boardID == boardID && $0.threadNo == threadNo }
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
        for fav in favorites {
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
        for fav in favorites where fav.isDead != true {
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
    }

    func markSeen(boardID: String, threadNo: Int, replyCount: Int) {
        if let idx = favorites.firstIndex(where: { $0.boardID == boardID && $0.threadNo == threadNo }) {
            favorites[idx].lastReplyCount = replyCount
            favorites[idx].unreadCount = 0
            save()
        }
    }
    
    func markDead(boardID: String, threadNo: Int) {
        if let idx = favorites.firstIndex(where: { $0.boardID == boardID && $0.threadNo == threadNo }) {
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

