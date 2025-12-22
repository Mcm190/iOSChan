import Foundation
import Combine

final class BoardDirectory: ObservableObject {
    static let shared = BoardDirectory()

    @Published private(set) var boardsByCode: [String: Board] = [:]
    private var isLoading = false

    private init() {}

    func update(with boards: [Board]) {
        var dict: [String: Board] = [:]
        for b in boards { dict[b.board] = b }
        DispatchQueue.main.async {
            self.boardsByCode = dict
        }
    }

    func ensureLoaded() {
        if !boardsByCode.isEmpty || isLoading { return }
        isLoading = true
        FourChanAPI.shared.fetchBoards { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let boards):
                    self.update(with: boards)
                case .failure:
                    break
                }
            }
        }
    }

    func isSFW(boardID: String) -> Bool {
        if let ws = boardsByCode[boardID]?.ws_board { return ws == 1 }
        return true // default to SFW if unknown
    }
}
