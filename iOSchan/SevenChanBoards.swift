import Foundation

/// Static catalog of 7chan boards used when the site directory selects the "7chan" site.
/// This provides a fallback so we don't need to fetch the index from the network.
struct SevenChanBoards {
    /// Full list of known 7chan boards based on user's provided codes.
    static let all: [ExternalBoard] = [
        // SFW clusters
        ExternalBoard(code: "i", title: "/i/"),
        ExternalBoard(code: "b", title: "/b/"),
        ExternalBoard(code: "fl", title: "/fl/"),
        ExternalBoard(code: "gfx", title: "/gfx/"),
        ExternalBoard(code: "?", title: "/?/"),
        ExternalBoard(code: "a", title: "/a/"),
        ExternalBoard(code: "grim", title: "/grim/"),
        ExternalBoard(code: "hi", title: "/hi/"),
        ExternalBoard(code: "me", title: "/me/"),
        ExternalBoard(code: "rx", title: "/rx/"),
        ExternalBoard(code: "vg", title: "/vg/"),
        ExternalBoard(code: "weed", title: "/weed/"),
        ExternalBoard(code: "wp", title: "/wp/"),
        ExternalBoard(code: "x", title: "/x/"),

        ExternalBoard(code: "aisfw", title: "/aisfw/"),
        ExternalBoard(code: "co", title: "/co/"),
        ExternalBoard(code: "diy", title: "/diy/"),
        ExternalBoard(code: "eh", title: "/eh/"),
        ExternalBoard(code: "fit", title: "/fit/"),
        ExternalBoard(code: "halp", title: "/halp/"),
        ExternalBoard(code: "jew", title: "/jew/"),
        ExternalBoard(code: "lit", title: "/lit/"),
        ExternalBoard(code: "phi", title: "/phi/"),
        ExternalBoard(code: "pr", title: "/pr/"),
        ExternalBoard(code: "rnb", title: "/rnb/"),
        ExternalBoard(code: "sci", title: "/sci/"),
        ExternalBoard(code: "tg", title: "/tg/"),
        ExternalBoard(code: "w", title: "/w/"),

        // NSFW clusters
        ExternalBoard(code: "ai", title: "/ai/"),
        ExternalBoard(code: "cake", title: "/cake/"),
        ExternalBoard(code: "cd", title: "/cd/"),
        ExternalBoard(code: "d", title: "/d/"),
        ExternalBoard(code: "di", title: "/di/"),
        ExternalBoard(code: "elit", title: "/elit/"),
        ExternalBoard(code: "fur", title: "/fur/"),
        ExternalBoard(code: "gif", title: "/gif/"),
        ExternalBoard(code: "h", title: "/h/"),
        ExternalBoard(code: "men", title: "/men/"),
        ExternalBoard(code: "pco", title: "/pco/"),
        ExternalBoard(code: "s", title: "/s/"),
        ExternalBoard(code: "sh", title: "/sh/"),
        ExternalBoard(code: "ss", title: "/ss/"),
        ExternalBoard(code: "unf", title: "/unf/")
    ]

    static func enrichBoardTitles(site: SiteDirectory.Site, boards: [ExternalBoard], completion: @escaping ([ExternalBoard]) -> Void) {
        SevenChanBoardsAPI.enrichBoardTitles(site: site, boards: boards, completion: completion)
    }
}

private enum SevenChanBoardsAPI {
    private static let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    private static let userDefaultsKey = "SevenChanBoardTitles.v1"

    static func enrichBoardTitles(site: SiteDirectory.Site, boards: [ExternalBoard], completion: @escaping ([ExternalBoard]) -> Void) {
        let cached = loadCache()
        var updated = boards.map { board -> ExternalBoard in
            if let title = cached[board.code], !title.isEmpty, board.title.hasPrefix("/") {
                return ExternalBoard(code: board.code, title: title, description: board.description, activeISPs: board.activeISPs, userCount: board.userCount, threadCount: board.threadCount)
            }
            return board
        }

        let missing: [String] = updated.filter { $0.title.hasPrefix("/") }.map { $0.code }
        guard !missing.isEmpty else {
            completion(updated)
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var newTitles: [String: String] = [:]

        for code in missing {
            group.enter()
            fetchBoardTitle(site: site, boardCode: code) { title in
                if let title, !title.isEmpty {
                    lock.lock()
                    newTitles[code] = title
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if !newTitles.isEmpty {
                var merged = cached
                for (k, v) in newTitles { merged[k] = v }
                saveCache(merged)
            }

            updated = updated.map { board in
                guard board.title.hasPrefix("/") else { return board }
                if let title = newTitles[board.code] ?? cached[board.code], !title.isEmpty {
                    return ExternalBoard(code: board.code, title: title, description: board.description, activeISPs: board.activeISPs, userCount: board.userCount, threadCount: board.threadCount)
                }
                return board
            }
            completion(updated)
        }
    }

    private static func fetchBoardTitle(site: SiteDirectory.Site, boardCode: String, completion: @escaping (String?) -> Void) {
        var url = site.baseURL
        if url.absoluteString.hasSuffix("/") == false { url.appendPathComponent("") }
        url.appendPathComponent("\(boardCode)/")

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.httpShouldHandleCookies = true
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            let fields = HTTPCookie.requestHeaderFields(with: cookies)
            for (k, v) in fields { request.setValue(v, forHTTPHeaderField: k) }
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil { completion(nil); return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                completion(nil)
                return
            }
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                completion(nil)
                return
            }
            completion(parseBoardTitleFromHTML(html, boardCode: boardCode))
        }.resume()
    }

    private static func parseBoardTitleFromHTML(_ html: String, boardCode: String) -> String? {
        let ns = html as NSString
        let boardEsc = NSRegularExpression.escapedPattern(for: boardCode)
        let pattern = #"<title>\s*/\#(boardEsc)/\s*-\s*(.*?)</title>"#
            .replacingOccurrences(of: "#(boardEsc)", with: boardEsc)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let m = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2
        else { return nil }
        let raw = ns.substring(with: m.range(at: 1))
        return decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        result = result
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        return result
    }

    private static func loadCache() -> [String: String] {
        guard let obj = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: String] else { return [:] }
        return obj
    }

    private static func saveCache(_ dict: [String: String]) {
        UserDefaults.standard.set(dict, forKey: userDefaultsKey)
    }
}

