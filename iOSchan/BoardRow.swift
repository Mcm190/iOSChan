//
//  BoardRow.swift
//  iOSchan
//
//  Created by MCM on 20/12/2025.
//

import SwiftUI

struct BoardRow: View {
    let board: Board
    let isFavorite: Bool
    let toggleFavorite: () -> Void

    private var isSFW: Bool { (board.ws_board ?? 1) == 1 }
    private var rowTint: Color { isSFW ? .chanSFW : .chanNSFW }

    var body: some View {
        HStack(spacing: 12) {
            // 1. Circle with /board/ style
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 50, height: 50)

                // Added "/" around the board name
                Text("/\(board.board)/")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(board.title)
                    .font(.headline)
                    .foregroundColor(.primary)

                // 2. Cleaned Description (Fixed the Optional Error here)
                Text(cleanHTML(board.meta_description ?? ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundColor(isFavorite ? .yellow : .gray)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(rowTint.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // Helper to clean the description text
    func cleanHTML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
    }
}
