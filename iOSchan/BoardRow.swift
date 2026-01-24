import SwiftUI

struct BoardRow: View {
    let board: Board
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    private var theme: BoardColors.Theme { BoardColors.theme(for: board) }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(theme.card)
                    .frame(width: 48, height: 48)
                    .shadow(color: theme.text.opacity(0.08), radius: 2, x: 0, y: 1)

                Text("/\(board.board)/")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(theme.text)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(board.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.text)

                Text(cleanHTML(board.meta_description ?? ""))
                    .font(.system(size: 13))
                    .foregroundColor(theme.text.opacity(0.6))
                    .lineLimit(2)
            }

            Spacer()

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isFavorite ? .yellow : theme.text.opacity(0.3))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 8)
    }

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
