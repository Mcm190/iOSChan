import SwiftUI

extension ThreadDetailView {
    init(boardID: String, threadNo: Int, isArchived: Bool) {
        self.init(boardID: boardID, threadNo: threadNo, isArchived: isArchived, isSFWOverride: nil)
    }
}
