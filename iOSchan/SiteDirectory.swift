import Foundation
import Combine

final class SiteDirectory: ObservableObject {
    static let shared = SiteDirectory()

    enum Kind {
        case fourChan
        case external
    }

    struct Site: Identifiable, Equatable {
        let id: String
        let displayName: String
        let baseURL: URL
        let kind: Kind

        init(id: String, displayName: String, baseURL: URL, kind: Kind) {
            self.id = id
            self.displayName = displayName
            self.baseURL = baseURL
            self.kind = kind
        }
    }

    @Published var current: Site

    let all: [Site]

    private init() {
        let fourChan = Site(id: "4chan", displayName: "4chan", baseURL: URL(string: "https://boards.4chan.org/")!, kind: .fourChan)
        // Kuroba uses endchan.net for Lynxchan-based Endchan.
        let endchan = Site(id: "endchan", displayName: "Endchan", baseURL: URL(string: "https://endchan.net/")!, kind: .external)
        let kohlchan = Site(id: "kohlchan", displayName: "Kohlchan", baseURL: URL(string: "https://kohlchan.net/")!, kind: .external)
        let eightKun = Site(id: "8kun", displayName: "8kun", baseURL: URL(string: "https://8kun.top/")!, kind: .external)
        let sevenChan = Site(id: "7chan", displayName: "7chan", baseURL: URL(string: "https://7chan.org/")!, kind: .external)

        self.all = [fourChan, endchan, kohlchan, eightKun, sevenChan]

        if let savedID = UserDefaults.standard.string(forKey: "currentSiteID"),
           let saved = all.first(where: { $0.id == savedID }) {
            self.current = saved
        } else {
            self.current = fourChan
        }
    }

    func switchTo(_ site: Site) {
        guard site != current else { return }
        current = site
        UserDefaults.standard.set(site.id, forKey: "currentSiteID")
    }
}


extension SiteDirectory.Site {
    /// Base URL used for JSON APIs (boards/catalog/thread).
    var apiBaseURL: URL {
        baseURL
    }
}
