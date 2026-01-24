import Foundation

struct ExternalBoard: Codable, Identifiable {
    var id: String { code }
    let code: String
    let title: String
    let description: String?
    let activeISPs: Int?
    let userCount: Int?
    let threadCount: Int?

    init(
        code: String,
        title: String,
        description: String? = nil,
        activeISPs: Int? = nil,
        userCount: Int? = nil,
        threadCount: Int? = nil
    ) {
        self.code = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.title = title
        self.description = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.activeISPs = activeISPs
        self.userCount = userCount
        self.threadCount = threadCount
    }
}

enum VichanBoardsAPI {
    private static let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    private static let kunIndexMinimumBoardCount = 200

    static func fetchBoards(site: SiteDirectory.Site, completion: @escaping (Result<[ExternalBoard], Error>) -> Void) {
        var root = site.apiBaseURL
        if root.absoluteString.hasSuffix("/") == false { root.appendPathComponent("") }

        let lynxchanBoardsURL = makeLynxchanBoardsURL(root: root, page: nil)
        let lynxchanBoardsListURL = makeLynxchanBoardsListURL(root: root, page: nil)

        // Try common candidates in order
        var candidates: [URL] = [
            root.appendingPathComponent("boards.json"),
            root.appendingPathComponent("api/boards.json")
        ]
        if let lynxchanBoardsURL {
            candidates.append(lynxchanBoardsURL)
        }
        if let lynxchanBoardsListURL {
            candidates.append(lynxchanBoardsListURL)
        }

        // 8kun: the index table is ordered (by activity) and includes Active ISPs and tags,
        // but depending on how the site serves it, it may not include every board.
        // Parse the index first, and if it looks incomplete, merge with JSON endpoints.
        if site.id == "8kun" {
            // Prefer the board directory search endpoint (it supports pagination without JS and includes activity metrics).
            fetchKunBoardsFromBoardSearch(site: site) { result in
                switch result {
                case .success(let boards):
                    completion(.success(boards))
                case .failure:
                    // Fallback to legacy index+JSON approach.
                    fetchKunBoardsFromIndex(site: site) { indexResult in
                        switch indexResult {
                        case .success(let indexBoards):
#if DEBUG
                            print("[VichanBoardsAPI] 8kun index parsed \(indexBoards.count) boards")
#endif
                            if indexBoards.count >= kunIndexMinimumBoardCount {
                                completion(.success(indexBoards))
                                return
                            }

                            completion(.success(indexBoards))

                            attemptFetch(site: site, candidates: candidates, index: 0) { apiResult in
                                switch apiResult {
                                case .success(let apiBoards):
#if DEBUG
                                    print("[VichanBoardsAPI] 8kun JSON loaded \(apiBoards.count) boards; merging")
#endif
                                    completion(.success(mergeKunBoards(indexBoards: indexBoards, apiBoards: apiBoards)))
                                case .failure:
                                    break
                                }
                            }
                        case .failure:
                            attemptFetch(site: site, candidates: candidates, index: 0, completion: completion)
                        }
                    }
                }
            }
            return
        }

        attemptFetch(site: site, candidates: candidates, index: 0, completion: completion)
    }

    private static func fetchKunBoardsFromIndex(site: SiteDirectory.Site, completion: @escaping (Result<[ExternalBoard], Error>) -> Void) {
        let url = site.baseURL.appendingPathComponent("index.html")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpShouldHandleCookies = true
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            let fields = HTTPCookie.requestHeaderFields(with: cookies)
            for (k, v) in fields { request.setValue(v, forHTTPHeaderField: k) }
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(.failure(NSError(domain: "VichanBoardsAPI", code: code, userInfo: [NSLocalizedDescriptionKey: "8kun index.html failed"])))
                return
            }
            let html =
                String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? String(decoding: data, as: UTF8.self)
            guard let boards = parseKunIndexBoards(html), !boards.isEmpty else {
                completion(.failure(NSError(domain: "VichanBoardsAPI", code: -5, userInfo: [NSLocalizedDescriptionKey: "Failed to parse 8kun board table"])))
                return
            }
            completion(.success(boards))
        }.resume()
    }

    private static func fetchKunBoardsFromBoardSearch(site: SiteDirectory.Site, completion: @escaping (Result<[ExternalBoard], Error>) -> Void) {
        // main.js uses sys_full_dns = "//sys.8kun.top" when host is 8kun.top; board-search.php lives there.
        let base = URL(string: "https://sys.8kun.top/")!

        struct Page {
            let boards: [ExternalBoard]
            let nextOffset: Int?
        }

        func decodeResponse(_ data: Data) -> Page? {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let boardsDict = json["boards"] as? [String: Any] ?? [:]
            let order = json["order"] as? [String] ?? []
            let omitted = (json["omitted"] as? Int) ?? ((json["omitted"] as? String).flatMap(Int.init)) ?? 0
            let search = json["search"] as? [String: Any] ?? [:]
            let pageOffset = (search["page"] as? Int) ?? ((search["page"] as? String).flatMap(Int.init)) ?? 0

            var out: [ExternalBoard] = []
            out.reserveCapacity(order.count)

            for uri in order {
                let row = boardsDict[uri] as? [String: Any] ?? [:]
                let code = (row["uri"] as? String) ?? uri
                let title = (row["title"] as? String) ?? code
                let active = (row["active"] as? Int) ?? ((row["active"] as? String).flatMap(Int.init))

                let tagsArr = row["tags"] as? [String]
                let tags = tagsArr?.joined(separator: " ")

                out.append(ExternalBoard(code: code, title: title, description: tags, activeISPs: active))
            }

            let pageCount = out.count
            let remaining = max(0, omitted - pageOffset)
            let nextOffset: Int? = (remaining > 0 && pageCount > 0) ? (pageOffset + pageCount) : nil
            return Page(boards: out, nextOffset: nextOffset)
        }

        func fetch(offset: Int, accumulated: [ExternalBoard]) {
            var comps = URLComponents(url: base.appendingPathComponent("board-search.php"), resolvingAgainstBaseURL: false)!
            comps.queryItems = [
                URLQueryItem(name: "page", value: String(offset)),
                // "sfw" checkbox in main.js: checked => sfw=1; unchecked => sfw=0 (include NSFW boards).
                URLQueryItem(name: "sfw", value: "0")
            ]
            let url = comps.url!

            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.httpShouldHandleCookies = true
            request.setValue(ua, forHTTPHeaderField: "User-Agent")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

            if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
                let fields = HTTPCookie.requestHeaderFields(with: cookies)
                for (k, v) in fields { request.setValue(v, forHTTPHeaderField: k) }
            }

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    completion(.failure(error))
                    return
                }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    completion(.failure(NSError(domain: "VichanBoardsAPI", code: code, userInfo: [NSLocalizedDescriptionKey: "8kun board-search failed"])))
                    return
                }

                guard let page = decodeResponse(data) else {
                    completion(.failure(NSError(domain: "VichanBoardsAPI", code: -6, userInfo: [NSLocalizedDescriptionKey: "8kun board-search decode failed"])))
                    return
                }

                let merged = accumulated + page.boards

                if let next = page.nextOffset {
                    fetch(offset: next, accumulated: merged)
                } else {
#if DEBUG
                    print("[VichanBoardsAPI] 8kun board-search loaded \(merged.count) boards")
#endif
                    completion(.success(merged))
                }
            }.resume()
        }

        fetch(offset: 0, accumulated: [])
    }

    private static func parseKunIndexBoards(_ html: String) -> [ExternalBoard]? {
        // The 8kun index table contains rows like:
        // Board | Title | PPH | Active ISPs | Tags | Total posts
        // This parser avoids brittle full-row regexes by extracting <td> cells per <tr>.
        guard
            let rowRegex = try? NSRegularExpression(
                pattern: #"<tr[^>]*>(.*?)</tr>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ),
            let cellRegex = try? NSRegularExpression(
                pattern: #"<td[^>]*>(.*?)</td>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ),
            let headerCellRegex = try? NSRegularExpression(
                pattern: #"<th[^>]*>(.*?)</th>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ),
            let hrefRegex = try? NSRegularExpression(
                pattern: #"href\s*=\s*['"]\/([^\/'"]+)\/"#,
                options: [.caseInsensitive]
            )
        else { return nil }

        let nsHTML = html as NSString
        let rowMatches = rowRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        if rowMatches.isEmpty { return nil }

        // Determine column positions from the header row, if present.
        var boardIndex = 0
        var titleIndex = 1
        var activeIndex = 3
        var tagsIndex = 4
        var startRowAt = 0

        for (idx, rowMatch) in rowMatches.enumerated() {
            guard rowMatch.numberOfRanges >= 2 else { continue }
            let rowHTML = nsHTML.substring(with: rowMatch.range(at: 1))
            if rowHTML.range(of: "<th", options: .caseInsensitive) == nil { continue }

            let rowNSString = rowHTML as NSString
            let thMatches = headerCellRegex.matches(in: rowHTML, range: NSRange(location: 0, length: rowNSString.length))
            guard !thMatches.isEmpty else { continue }

            let labels = thMatches.map {
                cleanHTML(rowNSString.substring(with: $0.range(at: 1)))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }

            // Use the first header row that clearly matches the board table.
            if labels.contains(where: { $0.contains("active") && $0.contains("isp") }) {
                for (i, label) in labels.enumerated() {
                    if label.contains("board") { boardIndex = i }
                    if label.contains("title") { titleIndex = i }
                    if label.contains("active") && label.contains("isp") { activeIndex = i }
                    if label.contains("tag") { tagsIndex = i }
                }
                startRowAt = idx + 1
                break
            }
        }

        var seen: Set<String> = []
        var out: [ExternalBoard] = []

        for (rowIdx, rowMatch) in rowMatches.enumerated() {
            if rowIdx < startRowAt { continue }
            guard rowMatch.numberOfRanges >= 2 else { continue }
            let rowHTML = nsHTML.substring(with: rowMatch.range(at: 1))
            if rowHTML.range(of: "<td", options: .caseInsensitive) == nil { continue }

            let rowNSString = rowHTML as NSString
            let cellMatches = cellRegex.matches(in: rowHTML, range: NSRange(location: 0, length: rowNSString.length))
            guard cellMatches.count >= 4 else { continue }

            let cells = cellMatches.map { rowNSString.substring(with: $0.range(at: 1)) }

            // 1) Board code (first cell)
            let codeRaw: String = {
                let idx = min(max(boardIndex, 0), cells.count - 1)
                let cell = cells[idx]
                let nsCell = cell as NSString
                let matches = hrefRegex.matches(in: cell, range: NSRange(location: 0, length: nsCell.length))
                if let first = matches.first, first.numberOfRanges >= 2 {
                    return nsCell.substring(with: first.range(at: 1))
                }
                // Fallback to cleaned text like "/pol/"
                return cleanHTML(cell)
            }()
            let code = codeRaw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !code.isEmpty else { continue }
            guard seen.insert(code).inserted else { continue }

            // 2) Title
            let titleCell = (cells.indices.contains(titleIndex) ? cells[titleIndex] : (cells.count >= 2 ? cells[1] : ""))
            let titleText = cleanHTML(titleCell).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = titleText.isEmpty ? code : titleText

            // 3) Active ISPs
            let activeISPs: Int? = {
                if cells.indices.contains(activeIndex) {
                    let activeText = cleanHTML(cells[activeIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let activeDigits = String(activeText.filter(\.isNumber))
                    if !activeDigits.isEmpty { return Int(activeDigits) }
                }

                // Fallback: Active ISPs tends to be the 2nd numeric column after Board/Title.
                var numeric: [Int] = []
                numeric.reserveCapacity(3)
                for (i, c) in cells.enumerated() where i != boardIndex && i != titleIndex {
                    let t = cleanHTML(c).trimmingCharacters(in: .whitespacesAndNewlines)
                    let d = String(t.filter(\.isNumber))
                    if let v = Int(d), !d.isEmpty { numeric.append(v) }
                }
                if numeric.count >= 2 { return numeric[1] }
                return nil
            }()

            // 4) Tags/description (if present)
            var tags: String? = nil
            if cells.indices.contains(tagsIndex) {
                let t = cleanHTML(cells[tagsIndex])
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { tags = t }
            }

            out.append(ExternalBoard(code: code, title: title, description: tags, activeISPs: activeISPs))
        }

        return out.isEmpty ? nil : out
    }

    private static func mergeKunBoards(indexBoards: [ExternalBoard], apiBoards: [ExternalBoard]) -> [ExternalBoard] {
        var apiByCode: [String: ExternalBoard] = [:]
        apiByCode.reserveCapacity(apiBoards.count)
        for b in apiBoards { apiByCode[b.code] = b }

        var seen: Set<String> = []
        seen.reserveCapacity(indexBoards.count)

        var out: [ExternalBoard] = []
        out.reserveCapacity(indexBoards.count + apiBoards.count)

        for b in indexBoards {
            let api = apiByCode[b.code]
            let title = (b.title.isEmpty || b.title == b.code) ? (api?.title ?? b.title) : b.title
            let desc = b.description ?? api?.description
            out.append(ExternalBoard(code: b.code, title: title, description: desc, activeISPs: b.activeISPs))
            seen.insert(b.code)
        }

        let extras = apiBoards
            .filter { !seen.contains($0.code) }
            .sorted(by: { $0.code < $1.code })
        out.append(contentsOf: extras)
        return out
    }

    private static func attemptFetch(site: SiteDirectory.Site, candidates: [URL], index: Int, completion: @escaping (Result<[ExternalBoard], Error>) -> Void) {
        guard index < candidates.count else {
            completion(.failure(NSError(domain: "VichanBoardsAPI", code: -3, userInfo: [NSLocalizedDescriptionKey: "All endpoints failed"])) )
            return
        }
        let url = candidates[index]
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpShouldHandleCookies = true
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            let fields = HTTPCookie.requestHeaderFields(with: cookies)
            for (k, v) in fields { request.setValue(v, forHTTPHeaderField: k) }
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                // Try next candidate
                attemptFetch(site: site, candidates: candidates, index: index + 1, completion: completion)
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data = data else {
                attemptFetch(site: site, candidates: candidates, index: index + 1, completion: completion)
                return
            }

            // Detect Lynxchan boards JSON if last path component is either "boards.js" or "boards"
            if (url.lastPathComponent == "boards.js" || url.lastPathComponent == "boards"),
               let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Some Lynxchan installs wrap under { status, data: { ... } }
                let container: [String: Any]
                if let dataObj = raw["data"] as? [String: Any] {
                    container = dataObj
                } else {
                    container = raw
                }

                if let _ = container["boards"] as? [[String: Any]] {
                    guard let parsed = parseLynxchanBoardsJSON(data) else {
                        attemptFetch(site: site, candidates: candidates, index: index + 1, completion: completion)
                        return
                    }
#if DEBUG
                    print("[VichanBoardsAPI] Loaded \(parsed.boards.count) boards (pageCount=\(parsed.pageCount)) from \(url.absoluteString)")
#endif
                    if parsed.pageCount > 1 {
                        // Determine if this is from boards.js or boards list url:
                        let preferList = url.lastPathComponent == "boards"
                        fetchRemainingLynxchanBoards(root: site.apiBaseURL, pageCount: parsed.pageCount, initial: parsed.boards, preferList: preferList, completion: completion)
                    } else {
                        completion(.success(parsed.boards))
                    }
                    return
                }
            }

            if site.id == "endchan", let parsed = parseEndchanBoardsHTML(data) {
                completion(.success(parsed))
                return
            }

            if let boards = parseBoardsJSON(data) {
#if DEBUG
                print("[VichanBoardsAPI] Loaded \(boards.count) boards from \(url.absoluteString)")
#endif
                completion(.success(boards))
            } else {
                // Try next candidate
                attemptFetch(site: site, candidates: candidates, index: index + 1, completion: completion)
            }
        }.resume()
    }

    private struct LynxchanBoardsParseResult {
        let boards: [ExternalBoard]
        let pageCount: Int
    }

    private static func makeLynxchanBoardsURL(root: URL, page: Int?) -> URL? {
        var url = root
        if url.absoluteString.hasSuffix("/") == false { url.appendPathComponent("") }
        url.appendPathComponent("boards.js")

        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let resolvedPage = page ?? 1
        var items: [URLQueryItem] = [
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page", value: String(resolvedPage))
        ]
        comps.queryItems = items
        return comps.url
    }

    private static func makeLynxchanBoardsListURL(root: URL, page: Int?) -> URL? {
        var url = root
        if url.absoluteString.hasSuffix("/") == false { url.appendPathComponent("") }
        url.appendPathComponent("boards")

        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let resolvedPage = page ?? 1
        var items: [URLQueryItem] = [
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page", value: String(resolvedPage))
        ]
        comps.queryItems = items
        return comps.url
    }

    private static func fetchRemainingLynxchanBoards(root: URL, pageCount: Int, initial: [ExternalBoard], preferList: Bool, completion: @escaping (Result<[ExternalBoard], Error>) -> Void) {
        var base = root
        if base.absoluteString.hasSuffix("/") == false { base.appendPathComponent("") }

        let group = DispatchGroup()
        let lock = NSLock()
        var allBoards: [ExternalBoard] = initial
        var lastError: Error?

        if pageCount >= 2 {
            for page in 2...pageCount {
                let url: URL?
                if preferList {
                    url = makeLynxchanBoardsListURL(root: base, page: page)
                } else {
                    url = makeLynxchanBoardsURL(root: base, page: page)
                }
                guard let url else { continue }
                group.enter()

                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
                request.httpShouldHandleCookies = true
                request.setValue(ua, forHTTPHeaderField: "User-Agent")
                request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
                request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

                if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
                    let fields = HTTPCookie.requestHeaderFields(with: cookies)
                    for (k, v) in fields { request.setValue(v, forHTTPHeaderField: k) }
                }

                URLSession.shared.dataTask(with: request) { data, response, error in
                    defer { group.leave() }
                    if let error {
                        lastError = error
                        return
                    }
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                        lastError = NSError(domain: "VichanBoardsAPI", code: code, userInfo: [NSLocalizedDescriptionKey: "boards.js page \(page) failed"])
                        return
                    }
                    guard let parsed = parseLynxchanBoardsJSON(data) else { return }
                    lock.lock()
                    allBoards.append(contentsOf: parsed.boards)
                    lock.unlock()
                }.resume()
            }
        }

        group.notify(queue: .global()) {
            let unique = Dictionary(grouping: allBoards, by: { $0.code })
                .compactMap { $0.value.first }
                .sorted(by: { $0.code < $1.code })

#if DEBUG
            print("[VichanBoardsAPI] Loaded \(unique.count) total boards across \(pageCount) boards.js pages")
#endif
            if unique.isEmpty, let lastError {
                completion(.failure(lastError))
            } else {
                completion(.success(unique))
            }
        }
    }

    private static func parseLynxchanBoardsJSON(_ data: Data) -> LynxchanBoardsParseResult? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // Some Lynxchan installs wrap under { status, data: { ... } }
        let container: [String: Any]
        if let dataObj = raw["data"] as? [String: Any] {
            container = dataObj
        } else {
            container = raw
        }

        let pageCount = (container["pageCount"] as? Int) ?? 1
        guard let arr = container["boards"] as? [[String: Any]] else { return nil }

        let boards = arr.compactMap { dict -> ExternalBoard? in
            guard let code = dict["boardUri"] as? String else { return nil }
            let title = (dict["boardName"] as? String) ?? code
            let description = dict["boardDescription"] as? String
            let users = parseUserCount(from: dict)
            let threads = parseThreadCount(from: dict)
            return ExternalBoard(code: code, title: title, description: description, userCount: users, threadCount: threads)
        }

        guard !boards.isEmpty else { return nil }
        return LynxchanBoardsParseResult(boards: boards, pageCount: pageCount)
    }

    private static func parseBoardsJSON(_ data: Data) -> [ExternalBoard]? {
        // 1) { "boards": [ ... ] }
        if let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let arr = top["boards"] as? [[String: Any]] {
            return arr.compactMap { dict in
                let code = (dict["board"] as? String) ?? (dict["uri"] as? String)
                let title = (dict["title"] as? String) ?? (dict["title_long"] as? String) ?? code
                let description = (dict["meta_description"] as? String) ?? (dict["description"] as? String)
                if let code = code, let title = title {
                    let users = parseUserCount(from: dict)
                    let threads = parseThreadCount(from: dict)
                    return ExternalBoard(code: code, title: title, description: description, userCount: users, threadCount: threads)
                }
                return nil
            }
        }
        // 2) [ ... ]
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return arr.compactMap { dict in
                let code = (dict["board"] as? String) ?? (dict["uri"] as? String)
                let title = (dict["title"] as? String) ?? (dict["title_long"] as? String) ?? code
                let description = (dict["meta_description"] as? String) ?? (dict["description"] as? String)
                if let code = code, let title = title {
                    let users = parseUserCount(from: dict)
                    let threads = parseThreadCount(from: dict)
                    return ExternalBoard(code: code, title: title, description: description, userCount: users, threadCount: threads)
                }
                return nil
            }
        }
        // 3) Typed fallback
        struct RawBoard: Codable {
            let board: String?
            let uri: String?
            let title: String?
            let title_long: String?
            let meta_description: String?
            let description: String?
        }
        if let arr = try? JSONDecoder().decode([RawBoard].self, from: data) {
            return arr.compactMap { rb in
                let code = rb.board ?? rb.uri
                let title = rb.title ?? rb.title_long ?? code
                let description = rb.meta_description ?? rb.description
                if let code = code, let title = title {
                    return ExternalBoard(code: code, title: title, description: description)
                }
                return nil
            }
        }
        return nil
    }

    private static func parseUserCount(from dict: [String: Any]) -> Int? {
        let keys = ["boardUsers", "users", "currentUsers", "boardActive", "visitors"]
        for key in keys {
            if let value = extractIntValue(dict[key]) {
                return value
            }
        }
        return nil
    }

    private static func parseThreadCount(from dict: [String: Any]) -> Int? {
        let keys = ["boardThreads", "threads", "threadCount", "thread_count", "thread_total", "thread", "topics"]
        for key in keys {
            if let value = extractIntValue(dict[key]) {
                return value
            }
        }
        return nil
    }

    private static func parseEndchanBoardsHTML(_ data: Data) -> [ExternalBoard]? {
        guard let html = decodeHTMLString(from: data) else { return nil }
        guard html.lowercased().contains("div#boardswrapper") || html.lowercased().contains("divboards") else { return nil }

        let pattern = #"<div[^>]*class=['\"][^'\"]*boardsCell[^'\"]*['\"][^>]*>(.*?)</div>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return nil }
        let nsHTML = html as NSString

        var headerIndices: [String: Int] = [:]
        var boards: [ExternalBoard] = []

        for match in regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length)) {
            let rowRange = match.range(at: 0)
            guard let range = Range(rowRange, in: html) else { continue }
            let rowHTML = String(html[range])

            if rowHTML.lowercased().contains("boardscellheader") {
                headerIndices = parseEndchanHeaderIndices(rowHTML)
                continue
            }

            let columns = parseEndchanRowColumns(rowHTML)
            guard !columns.isEmpty else { continue }

            let code = parseEndchanBoardCode(from: rowHTML) ?? parseEndchanBoardCode(from: columns[1] ?? columns[0] ?? "")
            guard let boardCode = code else { continue }

            let title = parseEndchanBoardTitle(from: columns[1], fallback: boardCode)
            let description = columns[2] ?? columns[1]

            let userCol = headerIndices["users"] ?? 5
            let threadCol = headerIndices["threads"]

            let users = columnValue(columns[userCol]) ?? extractIntValueFromHTML(rowHTML, keys: ["data-user", "data-users", "data-boardusers"])
            let threads = (threadCol != nil ? columnValue(columns[threadCol!]) : nil) ?? extractIntValueFromHTML(rowHTML, keys: ["data-thread", "data-threads", "data-threadcount"])

            boards.append(ExternalBoard(
                code: boardCode,
                title: title,
                description: description,
                userCount: users,
                threadCount: threads
            ))
        }

        guard !boards.isEmpty else { return nil }
        return boards
    }

    private static func parseEndchanHeaderIndices(_ html: String) -> [String: Int] {
        var result: [String: Int] = [:]
        let columns = parseEndchanRowColumns(html)
        for (idx, text) in columns {
            let lower = text.lowercased()
            if result["users"] == nil, lower.contains("user") {
                result["users"] = idx
            }
            if result["threads"] == nil, lower.contains("thread") {
                result["threads"] = idx
            }
        }
        if result["users"] == nil {
            result["users"] = 5
        }
        return result
    }

    private static func parseEndchanRowColumns(_ html: String) -> [Int: String] {
        let pattern = #"<span[^>]*class=['\"][^'\"]*col(\d+)[^'\"]*['\"][^>]*>(.*?)</span>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [:] }
        let nsHTML = html as NSString
        var out: [Int: String] = [:]

        for match in regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length)) {
            guard match.numberOfRanges >= 3,
                  let idxRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html),
                  let idx = Int(html[idxRange]) else { continue }
            out[idx] = cleanHTML(String(html[textRange]))
        }

        return out
    }

    private static func parseEndchanBoardCode(from html: String) -> String? {
        let pattern = #"href=['"]/?([^/'"\s]+)/"# 
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let ns = html as NSString
            if let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges >= 2,
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let fallbackPattern = #"/([^/\s]+?)/"#
        if let regex = try? NSRegularExpression(pattern: fallbackPattern, options: .caseInsensitive) {
            let ns = html as NSString
            if let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges >= 2,
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range])
            }
        }
        return nil
    }

    private static func parseEndchanBoardTitle(from column: String?, fallback: String) -> String {
        guard var text = column?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return fallback }
        let separators = [" - ", " — ", " – ", " -", "- ", "—", "–"]
        for sep in separators {
            if let range = text.range(of: sep) {
                let after = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !after.isEmpty {
                    text = after
                    break
                }
            }
        }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "☆✶"))
    }

    private static func columnValue(_ text: String?) -> Int? {
        guard let text = text else { return nil }
        let digits = text.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
        guard !digits.isEmpty else { return nil }
        return Int(String(String.UnicodeScalarView(digits)))
    }

    private static func extractIntValueFromHTML(_ html: String, keys: [String]) -> Int? {
        for key in keys {
            let literalKey = NSRegularExpression.escapedPattern(for: key)
            let pattern = #"(?i)\b\#(literalKey)\s*=\s*['"]?(\d+)"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let ns = html as NSString
                if let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: ns.length)),
                   match.numberOfRanges >= 3,
                   let range = Range(match.range(at: 2), in: html) {
                    return Int(String(html[range]))
                }
            }
        }
        return nil
    }

    private static func cleanHTML(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    private static func decodeHTMLString(from data: Data) -> String? {
        let encodings: [String.Encoding] = [.utf8, .isoLatin1, .windowsCP1251]
        for encoding in encodings {
            if let decoded = String(data: data, encoding: encoding) {
                return decoded
            }
        }
        return nil
    }

    private static func extractIntValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let str = value as? String, let num = Int(str) {
            return num
        }
        if let num = value as? NSNumber {
            return num.intValue
        }
        return nil
    }
}
