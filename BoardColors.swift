import SwiftUI

public enum BoardColors {
    public struct Theme {
        public let background: Color
        public let surface: Color
        public let card: Color
        public let text: Color
        public let accent: Color
        public let highlight: Color

        fileprivate init(background: Color, surface: Color, card: Color, text: Color, accent: Color, highlight: Color) {
            self.background = background
            self.surface = surface
            self.card = card
            self.text = text
            self.accent = accent
            self.highlight = highlight
        }
    }

    static func theme(for board: Board) -> Theme {
        let isSFW = (board.ws_board ?? 1) == 1
        return theme(isSFW: isSFW)
    }

    public static func theme(for boardID: String, isSFW: Bool? = nil) -> Theme {
        let safe = isSFW ?? BoardDirectory.shared.isSFW(boardID: boardID)
        return theme(isSFW: safe)
    }

    private static func theme(isSFW: Bool) -> Theme {
        isSFW ? blue : red
    }

    private static let blue = Theme(
        background: Color(red: 238.0 / 255.0, green: 242.0 / 255.0, blue: 255.0 / 255.0),
        surface: Color(red: 214.0 / 255.0, green: 218.0 / 255.0, blue: 240.0 / 255.0),
        card: Color(red: 183.0 / 255.0, green: 197.0 / 255.0, blue: 217.0 / 255.0),
        text: Color(red: 15.0 / 255.0, green: 12.0 / 255.0, blue: 93.0 / 255.0),
        accent: Color(red: 17.0 / 255.0, green: 119.0 / 255.0, blue: 67.0 / 255.0),
        highlight: Color(red: 17.0 / 255.0, green: 119.0 / 255.0, blue: 67.0 / 255.0)
    )

    private static let red = Theme(
        background: Color(red: 254.0 / 255.0, green: 255.0 / 255.0, blue: 238.0 / 255.0),
        surface: Color(red: 237.0 / 255.0, green: 224.0 / 255.0, blue: 214.0 / 255.0),
        card: Color(red: 237.0 / 255.0, green: 224.0 / 255.0, blue: 214.0 / 255.0),
        text: Color(red: 106.0 / 255.0, green: 0.0 / 255.0, blue: 5.0 / 255.0),
        accent: Color(red: 25.0 / 255.0, green: 0.0 / 255.0, blue: 128.0 / 255.0),
        highlight: Color(red: 122.0 / 255.0, green: 152.0 / 255.0, blue: 58.0 / 255.0)
    )
}
