import SwiftUI

struct ExternalBoardRow: View {
    let board: ExternalBoard

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 50, height: 50)

                Text("/\(board.code)/")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(board.title)
                    .font(.headline)
                    .foregroundColor(.primary)

                if let description = board.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            let hasMetrics = (board.threadCount != nil) || (board.userCount != nil) || (board.activeISPs != nil)
            if hasMetrics {
                HStack(alignment: .center, spacing: 16) {
                    if let threads = board.threadCount {
                        metricView(label: "Threads", value: threads)
                    }
                    if let users = board.userCount {
                        metricView(label: "Users", value: users)
                    }
                    if let active = board.activeISPs {
                        metricView(label: "ISPs", value: active)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func metricView(label: String, value: Int) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value.formatted(.number.grouping(.never)))
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary)
        }
    }
}
