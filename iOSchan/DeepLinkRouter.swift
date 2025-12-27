//  DeepLinkRouter.swift
//  iOSchan
//
//  Simple router to navigate to a thread from notifications.

import SwiftUI
import Combine

final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    @Published var target: ThreadTarget? = nil
    private init() {}

    struct ThreadTarget: Identifiable, Equatable {
        let boardID: String
        let threadNo: Int
        var id: String { "\(boardID)-\(threadNo)" }
    }

    func open(boardID: String, threadNo: Int) {
        DispatchQueue.main.async {
            self.target = ThreadTarget(boardID: boardID, threadNo: threadNo)
        }
    }
}

