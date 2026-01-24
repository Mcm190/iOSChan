import Foundation

struct ExternalThread: Identifiable, Codable {
    var id: Int { no }
    let no: Int
    let sub: String?
    let com: String?
    let tim: Int?
    let ext: String?
    let replies: Int?
    let images: Int?
    let fpath: Int?
    let mediaKey: String?
    let files: [ExternalFile]?
}

enum VichanCatalogAPI {
    private static let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    private static let sevenChanMaxBoardPagesToFetch = 15

    private static func normalizeBoardCode(_ boardCode: String) -> String {
        boardCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func makeLynxchanCatalogURL(root: URL, board: String, page: Int?) -> URL? {
        var base = root
        if base.absoluteString.hasSuffix("/") == false { base.appendPathComponent("") }
        var url = base.appendingPathComponent("\(board)/catalog")
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var items: [URLQueryItem] = [URLQueryItem(name: "json", value: "1")]
        if let page { items.append(URLQueryItem(name: "page", value: String(page))) }
        comps.queryItems = items
        return comps.url
    }

    static func fetchCatalog(site: SiteDirectory.Site, boardCode: String, completion: @escaping (Result<[ExternalThread], Error>) -> Void) {
        let boardCode = normalizeBoardCode(boardCode)
        guard !boardCode.isEmpty else {
            completion(.success([]))
            return
        }

        if site.id == "7chan" {
            // Try JSON endpoints first; if empty or fail, fallback to HTML catalog parsing
            var root = site.apiBaseURL
            if root.absoluteString.hasSuffix("/") == false { root.appendPathComponent("") }
            var candidates: [URL] = [
                root.appendingPathComponent("\(boardCode)/catalog.json"),
                root.appendingPathComponent("api/\(boardCode)/catalog.json"),
                root.appendingPathComponent("\(boardCode)/threads.json"),
                root.appendingPathComponent("\(boardCode)/1.json"),
                root.appendingPathComponent("\(boardCode)/0.json")
            ]
            if let lynx = makeLynxchanCatalogURL(root: root, board: boardCode, page: nil) { candidates.append(lynx) }
            let apiRoot = root.appendingPathComponent("api/")
            if let apiLynx = makeLynxchanCatalogURL(root: apiRoot, board: boardCode, page: nil) { candidates.append(apiLynx) }
            attemptFetch(from: candidates, index: 0) { result in
                switch result {
                case .success(let threads) where !threads.isEmpty && hasUsefulSevenChanCatalogContent(threads):
                    completion(.success(threads))
                default:
#if DEBUG
                    if case .success(let threads) = result, !threads.isEmpty {
                        print("[VichanCatalogAPI] 7chan JSON catalog returned \(threads.count) threads but no subject/thumb; falling back to HTML")
                    }
#endif
                    fetchSevenChanCatalogHTML(site: site, board: boardCode, completion: completion)
                }
            }
            return
        }

        var root = site.apiBaseURL
        if root.absoluteString.hasSuffix("/") == false { root.appendPathComponent("") }

        var candidates: [URL] = [
            root.appendingPathComponent("\(boardCode)/catalog.json"),
            root.appendingPathComponent("api/\(boardCode)/catalog.json"),
            root.appendingPathComponent("\(boardCode)/threads.json"), // some vichan variants
            root.appendingPathComponent("\(boardCode)/1.json"), // Lynxchan first page (common)
            root.appendingPathComponent("\(boardCode)/0.json") // Lynxchan first page (some installs)
        ]

        if let lynxchanURL = makeLynxchanCatalogURL(root: root, board: boardCode, page: nil) {
            candidates.append(lynxchanURL)
        }

        let apiRoot = root.appendingPathComponent("api/")
        if let apiLynxchanURL = makeLynxchanCatalogURL(root: apiRoot, board: boardCode, page: nil) {
            candidates.append(apiLynxchanURL)
        }

        attemptFetch(from: candidates, index: 0, completion: completion)
    }

    private static func hasUsefulSevenChanCatalogContent(_ threads: [ExternalThread]) -> Bool {
        for t in threads {
            let sub = (t.sub ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !sub.isEmpty { return true }
            let com = (t.com ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !com.isEmpty { return true }
            if let files = t.files, !files.isEmpty { return true }
            if let key = t.mediaKey, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let ext = t.ext, !ext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            if t.tim != nil, let ext = t.ext, !ext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        }
        return false
    }

    private static func attemptFetch(from candidates: [URL], index: Int, completion: @escaping (Result<[ExternalThread], Error>) -> Void) {
        guard index < candidates.count else {
            completion(.failure(NSError(domain: "VichanCatalogAPI", code: -3, userInfo: [NSLocalizedDescriptionKey: "All catalog endpoints failed"])) )
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
            if let _ = error { attemptFetch(from: candidates, index: index + 1, completion: completion); return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data = data else {
                attemptFetch(from: candidates, index: index + 1, completion: completion); return
            }

            if let threads = parseCatalogJSON(data) {
#if DEBUG
                print("[VichanCatalogAPI] Loaded \(threads.count) threads from \(url.absoluteString)")
#endif
                completion(.success(threads))
            } else {
                attemptFetch(from: candidates, index: index + 1, completion: completion)
            }
        }.resume()
    }

    private static func parseCatalogJSON(_ data: Data) -> [ExternalThread]? {
        // Lynxchan shape: { pageCount, threads: [ { threadId, message, subject, files, omittedPosts, omittedFiles, posts }, ... ] }
        if let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let threads = top["threads"] as? [[String: Any]],
           let first = threads.first,
           (first["threadId"] != nil || first["postId"] != nil)
        {
            return threads.compactMap(parseLynxchanCatalogThread)
        }

        // Lynxchan alt shape: [ { threadId, message, subject, thumb }, ... ]
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let first = arr.first, first["threadId"] != nil
        {
            return arr.compactMap(parseLynxchanCatalogThreadListItem)
        }

        // Inserted branch: flat array of thread dictionaries with no/threadId/postId keys
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], let first = arr.first, (first["no"] != nil) || (first["threadId"] != nil) || (first["postId"] != nil) {
            var result: [ExternalThread] = []
            for t in arr {
                let no = (t["no"] as? Int) ?? (t["no"] as? Int64).map(Int.init) ?? (t["no"] as? String).flatMap { Int($0) } ?? (t["threadId"] as? Int) ?? (t["postId"] as? Int)
                guard let no else { continue }
                let sub = (t["sub"] as? String) ?? (t["subject"] as? String)
                let com = (t["com"] as? String) ?? (t["message"] as? String)
                let timInt = (t["tim"] as? Int) ?? (t["tim"] as? Int64).map(Int.init) ?? (t["tim"] as? String).flatMap { Int($0) }
                let filename = t["filename"] as? String
                let timStr = (t["tim"] as? String) ?? timInt.map(String.init) ?? filename
                let ext = (t["ext"] as? String) ?? ((t["ext"] as? NSString).map { $0 as String })
                let replies = (t["replies"] as? Int) ?? (t["omittedPosts"] as? Int)
                let images = (t["images"] as? Int) ?? (t["omittedFiles"] as? Int)
                let fpath = (t["fpath"] as? Int) ?? ((t["fpath"] as? String).flatMap { Int($0) })
                result.append(ExternalThread(no: no, sub: sub, com: com, tim: timInt, ext: ext, replies: replies, images: images, fpath: fpath, mediaKey: timStr, files: nil))
            }
            if !result.isEmpty { return result }
        }

        // Flat array of threads with keys like no/threadId/postId
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let first = arr.first, ["no", "threadId", "postId"].contains(where: { first[$0] != nil })
        {
            var result: [ExternalThread] = []
            for t in arr {
                if let no = (t["no"] as? Int) ?? (t["threadId"] as? Int) ?? (t["postId"] as? Int) {
                    let sub = t["sub"] as? String ?? t["subject"] as? String
                    let com = t["com"] as? String ?? t["message"] as? String
                    let timInt = t["tim"] as? Int
                    let filename = t["filename"] as? String
                    let timStr = (t["tim"] as? String) ?? (timInt != nil ? String(timInt!) : nil) ?? filename
                    let ext = (t["ext"] as? String) ?? ((t["ext"] as? NSString).map { $0 as String })
                    let replies = t["replies"] as? Int ?? t["omittedPosts"] as? Int
                    let images = t["images"] as? Int ?? t["omittedFiles"] as? Int
                    let fpath = (t["fpath"] as? Int) ?? ((t["fpath"] as? String).flatMap { Int($0) })
                    result.append(ExternalThread(no: no, sub: sub, com: com, tim: timInt, ext: ext, replies: replies, images: images, fpath: fpath, mediaKey: timStr, files: nil))
                }
            }
            if !result.isEmpty { return result }
        }

        // Common shape: [ { page: 1, threads: [ { no, sub, com, tim, ext, replies, images }, ... ] }, ... ]
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            var result: [ExternalThread] = []
            for page in arr {
                if let threads = page["threads"] as? [[String: Any]] {
                    for t in threads {
                        if let no = (t["no"] as? Int) ?? (t["no"] as? Int64).map(Int.init) ?? (t["no"] as? String).flatMap({ Int($0) }) {
                            let sub = t["sub"] as? String
                            let com = t["com"] as? String
                            let timInt = (t["tim"] as? Int) ?? (t["tim"] as? Int64).map(Int.init) ?? (t["tim"] as? String).flatMap { Int($0) }
                            let filename = t["filename"] as? String
                            let timStr = (t["tim"] as? String) ?? timInt.map(String.init) ?? filename
                            let ext = (t["ext"] as? String) ?? ((t["ext"] as? NSString).map { $0 as String })
                            let replies = t["replies"] as? Int
                            let images = t["images"] as? Int
                            let fpath = (t["fpath"] as? Int) ?? ((t["fpath"] as? String).flatMap { Int($0) })
                            result.append(ExternalThread(no: no, sub: sub, com: com, tim: timInt, ext: ext, replies: replies, images: images, fpath: fpath, mediaKey: timStr, files: nil))
                        }
                    }
                } else if let no = (page["no"] as? Int) ?? (page["no"] as? Int64).map(Int.init) ?? (page["no"] as? String).flatMap({ Int($0) }) { // some variants just flatten threads
                    let sub = page["sub"] as? String
                    let com = page["com"] as? String
                    let timInt = (page["tim"] as? Int) ?? (page["tim"] as? Int64).map(Int.init) ?? (page["tim"] as? String).flatMap { Int($0) }
                    let filename = page["filename"] as? String
                    let timStr = (page["tim"] as? String) ?? timInt.map(String.init) ?? filename
                    let ext = (page["ext"] as? String) ?? ((page["ext"] as? NSString).map { $0 as String })
                    let replies = page["replies"] as? Int
                    let images = page["images"] as? Int
                    let fpath = (page["fpath"] as? Int) ?? ((page["fpath"] as? String).flatMap { Int($0) })
                    return [ExternalThread(no: no, sub: sub, com: com, tim: timInt, ext: ext, replies: replies, images: images, fpath: fpath, mediaKey: timStr, files: nil)]
                }
            }
            return result
        }
        return nil
    }

    private static func parseLynxchanCatalogThread(_ dict: [String: Any]) -> ExternalThread? {
        let threadId = (dict["threadId"] as? Int) ?? (dict["threadId"] as? Int64).map(Int.init)
        let postId = (dict["postId"] as? Int) ?? (dict["postId"] as? Int64).map(Int.init)
        guard let no = threadId ?? postId else { return nil }

        let sub = dict["subject"] as? String
        let com = (dict["message"] as? String) ?? (dict["markdown"] as? String)

        let files = (dict["files"] as? [[String: Any]])?.compactMap(VichanThreadAPI.parseLynxchanFile)
        var ext: String? = nil
        if let firstFile = files?.first {
            let noDot = (firstFile.path as NSString).pathExtension
            if !noDot.isEmpty {
                ext = "." + noDot.lowercased()
            }
        }

        let omittedPosts = (dict["omittedPosts"] as? Int) ?? (dict["ommitedPosts"] as? Int) ?? 0
        let visibleReplies = (dict["posts"] as? [[String: Any]])?.count ?? 0
        let replies = omittedPosts + visibleReplies

        let omittedFiles = dict["omittedFiles"] as? Int
        let opFileCount = files?.count ?? 0
        let images = omittedFiles.map { $0 + opFileCount } ?? (opFileCount > 0 ? opFileCount : nil)

        return ExternalThread(no: no, sub: sub, com: com, tim: nil, ext: ext, replies: replies, images: images, fpath: nil, mediaKey: nil, files: files)
    }

    private static func parseLynxchanCatalogThreadListItem(_ dict: [String: Any]) -> ExternalThread? {
        let threadId = (dict["threadId"] as? Int) ?? (dict["threadId"] as? Int64).map(Int.init)
        guard let no = threadId else { return nil }

        let sub = dict["subject"] as? String
        let com = dict["message"] as? String
        let thumb = dict["thumb"] as? String

        let files = thumb.map { thumb in
            let full = deriveLynxchanFullPath(fromThumb: thumb) ?? thumb
            return [ExternalFile(path: full, thumb: thumb, mime: nil, size: nil, width: nil, height: nil, originalName: nil)]
        }
        var ext: String? = nil
        if let firstFile = files?.first {
            let noDot = (firstFile.thumb as NSString).pathExtension
            if !noDot.isEmpty {
                ext = "." + noDot.lowercased()
            }
        }

        return ExternalThread(no: no, sub: sub, com: com, tim: nil, ext: ext, replies: nil, images: nil, fpath: nil, mediaKey: nil, files: files)
    }

    private static func deriveLynxchanFullPath(fromThumb thumb: String) -> String? {
        let ns = thumb as NSString
        let dir = ns.deletingLastPathComponent
        let filename = ns.lastPathComponent

        if filename.hasPrefix("t_") {
            let fullName = String(filename.dropFirst(2))
            return (dir as NSString).appendingPathComponent(fullName)
        }

        return nil
    }

    private static func fetchSevenChanCatalogHTML(site: SiteDirectory.Site, board: String, completion: @escaping (Result<[ExternalThread], Error>) -> Void) {
        fetchSevenChanCatalogLikeHTML(site: site, board: board, preferCatalog: true, completion: completion)
    }

    private static func fetchSevenChanCatalogLikeHTML(site: SiteDirectory.Site, board: String, preferCatalog: Bool, completion: @escaping (Result<[ExternalThread], Error>) -> Void) {
        enum Kind { case catalog, index }

        func makeURL(_ kind: Kind) -> URL {
            var url = site.baseURL
            if url.absoluteString.hasSuffix("/") == false { url.appendPathComponent("") }
            switch kind {
            case .catalog:
                url.appendPathComponent("\(board)/catalog.html")
            case .index:
                url.appendPathComponent("\(board)/")
            }
            return url
        }

        let primary: Kind = preferCatalog ? .catalog : .index
        let fallback: Kind = preferCatalog ? .index : .catalog

        func fetch(_ kind: Kind, fallbackTo other: Kind?) {
            let url = makeURL(kind)
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.httpShouldHandleCookies = true
            request.setValue(ua, forHTTPHeaderField: "User-Agent")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    if let other { fetch(other, fallbackTo: nil); return }
                    completion(.failure(error))
                    return
                }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                    if let other { fetch(other, fallbackTo: nil); return }
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    completion(.failure(NSError(domain: "VichanCatalogAPI", code: code, userInfo: [NSLocalizedDescriptionKey: "7chan catalog HTML failed"])) )
                    return
                }
                guard let html = decodeHTMLString7Chan(data) else {
                    if let other { fetch(other, fallbackTo: nil); return }
                    completion(.failure(NSError(domain: "VichanCatalogAPI", code: -7, userInfo: [NSLocalizedDescriptionKey: "7chan catalog decode failed"])) )
                    return
                }
                if isSevenChanCloudflareChallenge(html) {
                    completion(.failure(NSError(domain: "VichanCatalogAPI", code: -4, userInfo: [NSLocalizedDescriptionKey: "Cloudflare challenge is blocking 7chan catalog. Tap Fix access to clear it."])) )
                    return
                }

                let threads = parseSevenChanCatalogHTML(html, board: board)
#if DEBUG
                let useful = hasUsefulSevenChanCatalogContent(threads)
                print("[VichanCatalogAPI] 7chan \(kind) HTML parsed \(threads.count) threads (useful=\(useful)) from \(url.absoluteString)")
#endif
                if kind == .index, !threads.isEmpty {
                    let maxPage = sevenChanMaxPageFromIndexHTML(html, board: board)
#if DEBUG
                    print("[VichanCatalogAPI] 7chan index maxPage=\(maxPage)")
#endif
                    if maxPage > 1 {
                        fetchSevenChanIndexPages(site: site, board: board, maxPage: maxPage, initial: threads) { merged in
                            completion(.success(merged))
                        }
                        return
                    }
                }

                if (threads.isEmpty || !hasUsefulSevenChanCatalogContent(threads)), let other {
                    fetch(other, fallbackTo: nil)
                    return
                }
                completion(.success(threads))
            }.resume()
        }

        fetch(primary, fallbackTo: fallback)
    }

    private static func sevenChanMaxPageFromIndexHTML(_ html: String, board: String) -> Int {
        let ns = html as NSString
        let range = NSRange(location: 0, length: ns.length)
        let boardEsc = NSRegularExpression.escapedPattern(for: board)

        // Absolute: /<board>/<n>.html
        let absPattern = #"/\#(boardEsc)/(\d+)\.html"#
            .replacingOccurrences(of: "#(boardEsc)", with: boardEsc)
        // Relative: <n>.html
        let relPattern = #"href=['\"](\d+)\.html['\"]"#
        // Query: ?page=<n>
        let queryPattern = #"[?&]page=(\d+)"#

        let regexes = [
            try? NSRegularExpression(pattern: absPattern, options: [.caseInsensitive]),
            try? NSRegularExpression(pattern: relPattern, options: [.caseInsensitive]),
            try? NSRegularExpression(pattern: queryPattern, options: [.caseInsensitive])
        ].compactMap { $0 }

        var maxPage = 1
        for r in regexes {
            for m in r.matches(in: html, options: [], range: range) {
                guard m.numberOfRanges >= 2 else { continue }
                let s = ns.substring(with: m.range(at: 1))
                if let n = Int(s), n > maxPage { maxPage = n }
            }
        }

        return min(maxPage, sevenChanMaxBoardPagesToFetch)
    }

    private static func fetchSevenChanIndexPages(site: SiteDirectory.Site, board: String, maxPage: Int, initial: [ExternalThread], completion: @escaping ([ExternalThread]) -> Void) {
        guard maxPage > 1 else { completion(initial); return }

        var byNo: [Int: ExternalThread] = [:]
        var ordered: [ExternalThread] = []
        ordered.reserveCapacity(initial.count + 50)

        func merge(_ threads: [ExternalThread]) {
            for t in threads {
                if let existing = byNo[t.no] {
                    let merged = mergeThread(existing: existing, incoming: t)
                    byNo[t.no] = merged
                    if let idx = ordered.firstIndex(where: { $0.no == t.no }) { ordered[idx] = merged }
                } else {
                    byNo[t.no] = t
                    ordered.append(t)
                }
            }
        }

        merge(initial)

        func makeURL(page: Int) -> URL {
            var url = site.baseURL
            if url.absoluteString.hasSuffix("/") == false { url.appendPathComponent("") }
            url.appendPathComponent("\(board)/\(page).html")
            return url
        }

        func fetchPage(_ page: Int) {
            guard page <= maxPage else {
                completion(ordered)
                return
            }

            let url = makeURL(page: page)
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.httpShouldHandleCookies = true
            request.setValue(ua, forHTTPHeaderField: "User-Agent")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

            URLSession.shared.dataTask(with: request) { data, response, error in
                defer { fetchPage(page + 1) }
                if error != nil { return }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else { return }
                guard let html = decodeHTMLString7Chan(data) else { return }
                if isSevenChanCloudflareChallenge(html) { return }

                let threads = parseSevenChanCatalogHTML(html, board: board)
#if DEBUG
                print("[VichanCatalogAPI] 7chan index page \(page) parsed \(threads.count) threads")
#endif
                merge(threads)
            }.resume()
        }

        fetchPage(2)
    }

    private static func mergeThread(existing: ExternalThread, incoming: ExternalThread) -> ExternalThread {
        let sub = (existing.sub?.isEmpty == false) ? existing.sub : incoming.sub
        let com = (existing.com?.isEmpty == false) ? existing.com : incoming.com
        let files = (existing.files?.isEmpty == false) ? existing.files : incoming.files
        let tim = existing.tim ?? incoming.tim
        let ext = (existing.ext?.isEmpty == false) ? existing.ext : incoming.ext
        let replies = existing.replies ?? incoming.replies
        let images = existing.images ?? incoming.images
        let fpath = existing.fpath ?? incoming.fpath
        let mediaKey = (existing.mediaKey?.isEmpty == false) ? existing.mediaKey : incoming.mediaKey
        return ExternalThread(no: existing.no, sub: sub, com: com, tim: tim, ext: ext, replies: replies, images: images, fpath: fpath, mediaKey: mediaKey, files: files)
    }

    private static func parseSevenChanCatalogHTML(_ html: String, board: String) -> [ExternalThread] {
        if let parsed = parseSevenChanIndexThreadsByContainer(html, board: board), !parsed.isEmpty {
            return parsed
        }

        // Fallback: old approach for unknown layouts (less reliable, may mix data).
        let ns = html as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let boardEsc = NSRegularExpression.escapedPattern(for: board)

        let absLinkPattern = #"href=['\"][^'\"]*/\#(boardEsc)/res/(\d+)\.html"#
            .replacingOccurrences(of: "#(boardEsc)", with: boardEsc)
        let relLinkPattern = #"href=['\"]res/(\d+)\.html"#
        let absLinkRegex = try? NSRegularExpression(pattern: absLinkPattern, options: [.caseInsensitive])
        let relLinkRegex = try? NSRegularExpression(pattern: relLinkPattern, options: [.caseInsensitive])

        let subjectRegex = try? NSRegularExpression(pattern: #"<span[^>]*class=['\"][^'\"]*subject[^'\"]*['\"][^>]*>(.*?)</span>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let messageRegex = try? NSRegularExpression(pattern: #"<p[^>]*class=['\"][^'\"]*message[^'\"]*['\"][^>]*>(.*?)</p>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])

        // OP file link and thumb patterns.
        let fileRegex = try? NSRegularExpression(pattern: #"/\#(boardEsc)/src/(\d+)\.(\w+)"#.replacingOccurrences(of: "#(boardEsc)", with: boardEsc), options: [.caseInsensitive])
        let thumbRegex = try? NSRegularExpression(pattern: #"(?:/thumb/|/)\s*(\d+)s\.(jpg|jpeg|png|gif|webp)"#, options: [.caseInsensitive])

        var linkMatches: [NSTextCheckingResult] = []
        linkMatches.append(contentsOf: absLinkRegex?.matches(in: html, options: [], range: fullRange) ?? [])
        linkMatches.append(contentsOf: relLinkRegex?.matches(in: html, options: [], range: fullRange) ?? [])

        var results: [ExternalThread] = []
        var seen: Set<Int> = []

        for m in linkMatches {
            let noStr: String
            if m.numberOfRanges >= 3 {
                noStr = ns.substring(with: m.range(at: 2))
            } else if m.numberOfRanges >= 2 {
                noStr = ns.substring(with: m.range(at: 1))
            } else { continue }
            guard let no = Int(noStr), seen.insert(no).inserted else { continue }

            let start = m.range.location
            let end = min(ns.length, m.range.location + 8000)
            let window = NSRange(location: start, length: max(0, end - start))

            let subject: String? = {
                guard let regex = subjectRegex,
                      let match = regex.firstMatch(in: html, options: [], range: window),
                      match.numberOfRanges >= 2 else { return nil }
                return cleanHTML7Chan(ns.substring(with: match.range(at: 1)))
            }()

            var message: String? = nil
            if let mm = messageRegex?.firstMatch(in: html, options: [], range: window), mm.numberOfRanges >= 2 {
                message = stripSevenChanAbbrev(ns.substring(with: mm.range(at: 1)))
            }

            var timStr: String? = nil
            var fileExt: String? = nil
            if let fm = fileRegex?.firstMatch(in: html, options: [], range: window), fm.numberOfRanges >= 3 {
                timStr = ns.substring(with: fm.range(at: 1))
                fileExt = ns.substring(with: fm.range(at: 2)).lowercased()
            }

            var thumbExt: String? = nil
            if let timStr, let tm = thumbRegex?.firstMatch(in: html, options: [], range: window), tm.numberOfRanges >= 3 {
                let t = ns.substring(with: tm.range(at: 1))
                if t == timStr {
                    thumbExt = ns.substring(with: tm.range(at: 2)).lowercased()
                }
            }

            let files: [ExternalFile]? = timStr.map { tim in
                let ext = (fileExt ?? "jpg").trimmingCharacters(in: .whitespacesAndNewlines)
                let thumbExtNoDot = (thumbExt ?? ext).trimmingCharacters(in: .whitespacesAndNewlines)
                return [ExternalFile(path: "/\(board)/src/\(tim).\(ext)", thumb: "/\(board)/thumb/\(tim)s.\(thumbExtNoDot)", mime: nil, size: nil, width: nil, height: nil, originalName: nil)]
            }
            let extFromFiles: String? = {
                guard let first = files?.first else { return nil }
                let ext = (first.path as NSString).pathExtension
                let trimmed = ext.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : ".\(trimmed)"
            }()

            results.append(ExternalThread(no: no, sub: subject, com: message, tim: nil, ext: extFromFiles, replies: nil, images: nil, fpath: nil, mediaKey: timStr, files: files))
        }

        return results
    }

    private static func parseSevenChanIndexThreadsByContainer(_ html: String, board: String) -> [ExternalThread]? {
        let ns = html as NSString
        let range = NSRange(location: 0, length: ns.length)
        let boardEsc = NSRegularExpression.escapedPattern(for: board)

        // Thread containers (seen variants):
        // - <div class="thread" id="thread_677_x">
        // - <div class="thread" id="thread_677">
        let threadStartStrictPattern = #"<div[^>]*class=['\"][^'\"]*thread[^'\"]*['\"][^>]*id=['\"]thread_(\d+)_\#(boardEsc)['\"]"#
            .replacingOccurrences(of: "#(boardEsc)", with: boardEsc)
        let threadStartLoosePattern = #"<div[^>]*class=['\"][^'\"]*thread[^'\"]*['\"][^>]*id=['\"]thread_(\d+)(?:_[a-z0-9]+)?['\"]"#
        let threadStartStrictRegex = try? NSRegularExpression(pattern: threadStartStrictPattern, options: [.caseInsensitive])
        let threadStartLooseRegex = try? NSRegularExpression(pattern: threadStartLoosePattern, options: [.caseInsensitive])

        guard let subjectRegex = try? NSRegularExpression(pattern: #"<span[^>]*class=['\"][^'\"]*subject[^'\"]*['\"][^>]*>(.*?)</span>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let messageRegex = try? NSRegularExpression(pattern: #"<p[^>]*class=['\"][^'\"]*(?:message|postMessage)[^'\"]*['\"][^>]*>(.*?)</p>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let fileRegex = try? NSRegularExpression(pattern: #"/\#(boardEsc)/src/(\d+)\.(\w+)"#.replacingOccurrences(of: "#(boardEsc)", with: boardEsc), options: [.caseInsensitive])
        else { return nil }

        let matches: [NSTextCheckingResult] = {
            let strictMatches = threadStartStrictRegex?.matches(in: html, options: [], range: range) ?? []
            if !strictMatches.isEmpty { return strictMatches }
            return threadStartLooseRegex?.matches(in: html, options: [], range: range) ?? []
        }()
        guard !matches.isEmpty else { return nil }

        func opRange(in threadChunk: NSString, threadNo: Int) -> NSRange {
            let full = NSRange(location: 0, length: threadChunk.length)
            let opPattern = #"id=['\"]p#(no)['\"]"#
                .replacingOccurrences(of: "#(no)", with: String(threadNo))
            guard let opRegex = try? NSRegularExpression(pattern: opPattern, options: [.caseInsensitive]),
                  let op = opRegex.firstMatch(in: threadChunk as String, options: [], range: full)
            else { return full }

            let start = op.range.location
            let afterOp = NSRange(location: start, length: threadChunk.length - start)
            if let replyRegex = try? NSRegularExpression(pattern: #"id=['\"]reply_(\d+)['\"]"#, options: [.caseInsensitive]),
               let reply = replyRegex.firstMatch(in: threadChunk as String, options: [], range: afterOp)
            {
                return NSRange(location: start, length: max(0, reply.range.location - start))
            }
            return NSRange(location: start, length: max(0, threadChunk.length - start))
        }

        var out: [ExternalThread] = []
        out.reserveCapacity(matches.count)

        for (i, m) in matches.enumerated() {
            guard m.numberOfRanges >= 2 else { continue }
            let noStr = ns.substring(with: m.range(at: 1))
            guard let threadNo = Int(noStr) else { continue }

            let start = m.range.location
            let end = (i + 1 < matches.count) ? matches[i + 1].range.location : ns.length
            let threadRange = NSRange(location: start, length: max(0, end - start))
            let threadHTML = ns.substring(with: threadRange)
            let threadNS = threadHTML as NSString

            let op = opRange(in: threadNS, threadNo: threadNo)

            let subject: String? = {
                guard let sm = subjectRegex.firstMatch(in: threadHTML, options: [], range: op),
                      sm.numberOfRanges >= 2 else { return nil }
                return cleanHTML7Chan(threadNS.substring(with: sm.range(at: 1)))
            }()

            var message: String? = nil
            if let mm = messageRegex.firstMatch(in: threadHTML, options: [], range: op), mm.numberOfRanges >= 2 {
                message = stripSevenChanAbbrev(threadNS.substring(with: mm.range(at: 1)))
            }

            var timStr: String? = nil
            var fileExt: String? = nil
            if let fm = fileRegex.firstMatch(in: threadHTML, options: [], range: op), fm.numberOfRanges >= 3 {
                timStr = threadNS.substring(with: fm.range(at: 1))
                fileExt = threadNS.substring(with: fm.range(at: 2)).lowercased()
            }

            var thumbExt: String? = nil
            if let timStr {
                let thumbPattern = #"(?:/thumb/|_files/|/)(?:t_)?#(timStr)s\.(jpg|jpeg|png|gif|webp)"#
                    .replacingOccurrences(of: "#(timStr)", with: NSRegularExpression.escapedPattern(for: timStr))
                if let thumbRegex = try? NSRegularExpression(pattern: thumbPattern, options: [.caseInsensitive]),
                   let tm = thumbRegex.firstMatch(in: threadHTML, options: [], range: op),
                   tm.numberOfRanges >= 2
                {
                    thumbExt = threadNS.substring(with: tm.range(at: 1)).lowercased()
                }
            }

            let files: [ExternalFile]? = timStr.map { tim in
                let ext = (fileExt ?? "jpg").trimmingCharacters(in: .whitespacesAndNewlines)
                let thumbExtNoDot = (thumbExt ?? (["jpg", "jpeg", "png", "gif", "webp"].contains(ext.lowercased()) ? ext : "jpg"))
                let thumb = "/\(board)/thumb/\(tim)s.\(thumbExtNoDot)"
                let full = "/\(board)/src/\(tim).\(ext)"
                return [ExternalFile(path: full, thumb: thumb, mime: nil, size: nil, width: nil, height: nil, originalName: nil)]
            }
            let extFromFiles: String? = {
                guard let first = files?.first else { return nil }
                let ext = (first.path as NSString).pathExtension
                let trimmed = ext.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : ".\(trimmed)"
            }()

            out.append(ExternalThread(
                no: threadNo,
                sub: subject,
                com: message,
                tim: nil,
                ext: extFromFiles,
                replies: nil,
                images: nil,
                fpath: nil,
                mediaKey: timStr,
                files: files
            ))
        }

        return out
    }

    private static func stripSevenChanAbbrev(_ htmlFragment: String) -> String {
        // Remove "Message too long" block inside teasers.
        return htmlFragment.replacingOccurrences(of: #"<span[^>]*class=['\"][^'\"]*abbrev[^'\"]*['\"][^>]*>.*?</span>"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    private static func decodeHTMLString7Chan(_ data: Data) -> String? {
        let encodings: [String.Encoding] = [.utf8, .isoLatin1, .windowsCP1251]
        for enc in encodings {
            if let s = String(data: data, encoding: enc) { return s }
        }
        return nil
    }

    private static func cleanHTML7Chan(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    private static func isSevenChanCloudflareChallenge(_ html: String) -> Bool {
        let lower = html.lowercased()
        if lower.contains("just a moment") && lower.contains("_cf_chl_opt") { return true }
        if lower.contains("challenge-error-text") { return true }
        if lower.contains("enable javascript and cookies") { return true }
        return false
    }
}

