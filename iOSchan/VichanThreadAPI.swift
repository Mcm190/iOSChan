import Foundation

struct ExternalFile: Codable, Hashable, Sendable {
    let path: String
    let thumb: String
    let mime: String?
    let size: Int?
    let width: Int?
    let height: Int?
    let originalName: String?
}

struct ExternalAttachment: Codable, Hashable, Sendable {
    let mediaKey: String
    let ext: String?
    let fpath: Int?
}

struct ExternalPost: Identifiable, Codable {
    var id: Int { no }
    let no: Int
    let sub: String?
    let com: String?
    let name: String?
    let time: Int
    let tim: Int?
    let ext: String?
    let filename: String?
    let fsize: Int?
    let fpath: Int?
    let mediaKey: String?
    let attachments: [ExternalAttachment]?
    let files: [ExternalFile]?
}

enum VichanThreadAPI {
    private static let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

    private static func normalizeBoardCode(_ boardCode: String) -> String {
        boardCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func fetchThread(site: SiteDirectory.Site, boardCode: String, threadNo: Int, completion: @escaping (Result<[ExternalPost], Error>) -> Void) {
        let boardCode = normalizeBoardCode(boardCode)
        guard !boardCode.isEmpty else {
            completion(.success([]))
            return
        }

        var root = site.apiBaseURL
        if root.absoluteString.hasSuffix("/") == false { root.appendPathComponent("") }

        let candidates: [URL] = [
            root.appendingPathComponent("\(boardCode)/res/\(threadNo).json"),
            root.appendingPathComponent("api/\(boardCode)/thread/\(threadNo).json")
        ]

        attemptFetch(from: candidates, index: 0) { result in
            switch result {
            case .success(let posts) where !posts.isEmpty && hasUsefulSevenChanThreadContent(posts):
                completion(.success(posts))
            default:
                if site.id == "7chan" {
#if DEBUG
                    if case .success(let posts) = result, !posts.isEmpty {
                        print("[VichanThreadAPI] 7chan JSON thread returned \(posts.count) posts but no content; falling back to HTML")
                    }
#endif
                    fetchSevenChanThreadHTML(site: site, boardCode: boardCode, threadNo: threadNo, completion: completion)
                } else {
                    completion(result)
                }
            }
        }
    }

    private static func hasUsefulSevenChanThreadContent(_ posts: [ExternalPost]) -> Bool {
        for p in posts {
            let sub = (p.sub ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !sub.isEmpty { return true }
            let com = (p.com ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !com.isEmpty { return true }
            if let files = p.files, !files.isEmpty { return true }
            if let atts = p.attachments, !atts.isEmpty { return true }
            if let key = p.mediaKey, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            if p.tim != nil, let ext = p.ext, !ext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        }
        return false
    }

    private static func attemptFetch(from candidates: [URL], index: Int, completion: @escaping (Result<[ExternalPost], Error>) -> Void) {
        guard index < candidates.count else {
            completion(.failure(NSError(domain: "VichanThreadAPI", code: -3, userInfo: [NSLocalizedDescriptionKey: "All thread endpoints failed"])) )
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

            if let posts = parseThreadJSON(data) {
#if DEBUG
                print("[VichanThreadAPI] Loaded \(posts.count) posts from \(url.absoluteString)")
#endif
                completion(.success(posts))
            } else {
                attemptFetch(from: candidates, index: index + 1, completion: completion)
            }
        }.resume()
    }

    private static func parseThreadJSON(_ data: Data) -> [ExternalPost]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }

        // Vichan/Taimaba shape: { posts: [ { no, time, ... } ] }
        if let top = json as? [String: Any],
           let arr = top["posts"] as? [[String: Any]],
           arr.first?["no"] != nil
        {
            return arr.compactMap { dict in
                guard let no = dict["no"] as? Int else { return nil }
                guard let time = dict["time"] as? Int else { return nil }
                let sub = dict["sub"] as? String
                let com = dict["com"] as? String
                let name = dict["name"] as? String
                let timInt = dict["tim"] as? Int
                let filename = dict["filename"] as? String

                // Some vichan derivatives rely on the posted filename instead of a numeric `tim` ID.
                let timStr = (dict["tim"] as? String) ?? (timInt != nil ? String(timInt!) : nil) ?? filename

                let extRaw = dict["ext"] as? String
                let ext = extRaw?.replacingOccurrences(of: ".", with: "").lowercased()
                let fsize = dict["fsize"] as? Int
                let fpath = (dict["fpath"] as? Int) ?? ((dict["fpath"] as? String).flatMap { Int($0) })

                let attachments = parseVichanAttachments(dict)
                return ExternalPost(
                    no: no,
                    sub: sub,
                    com: com,
                    name: name,
                    time: time,
                    tim: timInt,
                    ext: ext,
                    filename: filename,
                    fsize: fsize,
                    fpath: fpath,
                    mediaKey: timStr,
                    attachments: attachments,
                    files: nil
                )
            }
        }

        // Lynxchan thread shape: OP post object with nested "posts": [ ... ]
        if let top = json as? [String: Any],
           top["threadId"] != nil || top["postId"] != nil || top["creation"] != nil || top["message"] != nil
        {
            var out: [ExternalPost] = []
            if let op = parseLynxchanPost(top) {
                out.append(op)
            }
            if let replies = top["posts"] as? [[String: Any]] {
                out.append(contentsOf: replies.compactMap { parseLynxchanPost($0) })
            }
            return out.isEmpty ? nil : out
        }

        return nil
    }

    private static func parseLynxchanPost(_ dict: [String: Any]) -> ExternalPost? {
        let threadId = (dict["threadId"] as? Int) ?? (dict["threadId"] as? Int64).map(Int.init)
        let postId = (dict["postId"] as? Int) ?? (dict["postId"] as? Int64).map(Int.init)
        guard let no = threadId ?? postId else { return nil }

        let name = dict["name"] as? String
        let com = (dict["message"] as? String) ?? (dict["markdown"] as? String)
        let creation = dict["creation"] as? String
        let time = parseISO8601ToUnixSeconds(creation) ?? 0

        let files = (dict["files"] as? [[String: Any]])?.compactMap(parseLynxchanFile)

        return ExternalPost(
            no: no,
            sub: dict["subject"] as? String,
            com: com,
            name: name,
            time: time,
            tim: nil,
            ext: nil,
            filename: nil,
            fsize: nil,
            fpath: nil,
            mediaKey: nil,
            attachments: nil,
            files: files
        )
    }

    private static func parseVichanAttachments(_ dict: [String: Any]) -> [ExternalAttachment]? {
        var out: [ExternalAttachment] = []

        let arrays: [[String: Any]] =
            (dict["extra_files"] as? [[String: Any]])
            ?? (dict["extraFiles"] as? [[String: Any]])
            ?? (dict["extraFilesArray"] as? [[String: Any]])
            ?? []

        for f in arrays {
            guard let mediaKey = parseMediaKey(f) else { continue }
            let ext = (f["ext"] as? String) ?? (f["ext"] as? NSString as String?)
            let fpath = (f["fpath"] as? Int) ?? ((f["fpath"] as? String).flatMap { Int($0) })
            out.append(ExternalAttachment(mediaKey: mediaKey, ext: ext, fpath: fpath))
        }

        return out.isEmpty ? nil : out
    }

    private static func parseMediaKey(_ dict: [String: Any]) -> String? {
        if let s = dict["tim"] as? String, !s.isEmpty { return s }
        if let i = dict["tim"] as? Int { return String(i) }
        if let i64 = dict["tim"] as? Int64 { return String(i64) }
        if let s = dict["mediaKey"] as? String, !s.isEmpty { return s }
        if let s = dict["filename"] as? String, !s.isEmpty { return s }
        return nil
    }

    static func parseLynxchanFile(_ dict: [String: Any]) -> ExternalFile? {
        guard let path = dict["path"] as? String, let thumb = dict["thumb"] as? String else { return nil }
        let mime = dict["mime"] as? String
        let size = (dict["size"] as? Int) ?? (dict["size"] as? Int64).map(Int.init)
        let width = dict["width"] as? Int
        let height = dict["height"] as? Int
        let originalName = dict["originalName"] as? String
        return ExternalFile(path: path, thumb: thumb, mime: mime, size: size, width: width, height: height, originalName: originalName)
    }

    private static func parseISO8601ToUnixSeconds(_ iso: String?) -> Int? {
        guard let iso, !iso.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            return Int(date.timeIntervalSince1970)
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: iso) {
            return Int(date.timeIntervalSince1970)
        }
        return nil
    }

    private static func fetchSevenChanThreadHTML(site: SiteDirectory.Site, boardCode: String, threadNo: Int, completion: @escaping (Result<[ExternalPost], Error>) -> Void) {
        var url = site.baseURL
        if url.absoluteString.hasSuffix("/") == false { url.appendPathComponent("") }
        url.appendPathComponent("\(boardCode)/res/\(threadNo).html")

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpShouldHandleCookies = true
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(.failure(NSError(domain: "VichanThreadAPI", code: code, userInfo: [NSLocalizedDescriptionKey: "7chan thread HTML failed"])) )
                return
            }
            guard let html = decodeHTMLString7Chan(data) else {
                completion(.failure(NSError(domain: "VichanThreadAPI", code: -7, userInfo: [NSLocalizedDescriptionKey: "7chan thread decode failed"])) )
                return
            }
            if isSevenChanCloudflareChallenge(html) {
                completion(.failure(NSError(domain: "VichanThreadAPI", code: -4, userInfo: [NSLocalizedDescriptionKey: "Cloudflare challenge is blocking 7chan threads. Tap Fix access to clear it."])) )
                return
            }
            let posts = parseSevenChanThreadHTML(html, board: boardCode)
            completion(.success(posts))
        }.resume()
    }

    private static func parseSevenChanThreadHTML(_ html: String, board: String) -> [ExternalPost] {
        let ns = html as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        // Post start markers in Kusaba/7chan markup:
        // - OP wrapper: <div class="op" id="p677">
        // - Reply wrapper: id="reply_21642">
        let postStartPattern = #"id=['\"](?:p|reply_)(\d+)['\"]"#
        let postStartRegex = try? NSRegularExpression(pattern: postStartPattern, options: [.caseInsensitive])

        // Name, subject, message (per-post chunk)
        let namePattern = #"<span[^>]*class=['\"][^'\"]*(?:postername|name)[^'\"]*['\"][^>]*>(.*?)</span>"#
        let subjectPattern = #"<span[^>]*class=['\"][^'\"]*subject[^'\"]*['\"][^>]*>(.*?)</span>"#
        let messagePattern = #"<p[^>]*class=['\"][^'\"]*(?:message|postMessage)[^'\"]*['\"][^>]*>(.*?)</p>"#

        let nameRegex = try? NSRegularExpression(pattern: namePattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let subjectRegex = try? NSRegularExpression(pattern: subjectPattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let messageRegex = try? NSRegularExpression(pattern: messagePattern, options: [.caseInsensitive, .dotMatchesLineSeparators])

        // Files: href=".../<board>/src/<tim>.<ext>" and thumb img src="...<tim>s.<ext>" (saved pages may rewrite paths)
        let fileHrefPattern = #"/\#(board)/src/(\d+)\.(\w+)"#
            .replacingOccurrences(of: "#(board)", with: NSRegularExpression.escapedPattern(for: board))
        let thumbImgBeforeSrcPattern = #"<img[^>]*class=['\"][^'\"]*thumb[^'\"]*['\"][^>]*src=['\"][^'\"]*(\d+)s\.(jpg|jpeg|png|gif|webp)"#
        let thumbImgAfterSrcPattern = #"<img[^>]*src=['\"][^'\"]*(\d+)s\.(jpg|jpeg|png|gif|webp)[^'\"]*['\"][^>]*class=['\"][^'\"]*thumb[^'\"]*['\"]"#
        let fileHrefRegex = try? NSRegularExpression(pattern: fileHrefPattern, options: [.caseInsensitive])
        let thumbImgBeforeSrcRegex = try? NSRegularExpression(pattern: thumbImgBeforeSrcPattern, options: [.caseInsensitive])
        let thumbImgAfterSrcRegex = try? NSRegularExpression(pattern: thumbImgAfterSrcPattern, options: [.caseInsensitive])

        var results: [ExternalPost] = []
        var seen: Set<Int> = []

        let matches = postStartRegex?.matches(in: html, options: [], range: fullRange) ?? []
        for (index, m) in matches.enumerated() {
            guard m.numberOfRanges >= 2 else { continue }
            let noStr = ns.substring(with: m.range(at: 1))
            guard let no = Int(noStr), seen.insert(no).inserted else { continue }

            let start = m.range.location
            let end: Int = {
                if matches.indices.contains(index + 1) {
                    return matches[index + 1].range.location
                }
                return ns.length
            }()
            let window = NSRange(location: start, length: max(0, end - start))

            var name: String? = nil
            if let nm = nameRegex?.firstMatch(in: html, options: [], range: window), nm.numberOfRanges >= 2 {
                name = cleanHTML7Chan(ns.substring(with: nm.range(at: 1)))
            }

            var subject: String? = nil
            if let sm = subjectRegex?.firstMatch(in: html, options: [], range: window), sm.numberOfRanges >= 2 {
                subject = cleanHTML7Chan(ns.substring(with: sm.range(at: 1)))
            }

            var message: String? = nil
            if let mm = messageRegex?.firstMatch(in: html, options: [], range: window), mm.numberOfRanges >= 2 {
                message = ns.substring(with: mm.range(at: 1))
            }

            // Extract first file if present
            var files: [ExternalFile]? = nil
            var fileTim: String? = nil
            var fileExt: String? = nil
            if let fm = fileHrefRegex?.firstMatch(in: html, options: [], range: window), fm.numberOfRanges >= 3 {
                fileTim = ns.substring(with: fm.range(at: 1))
                fileExt = ns.substring(with: fm.range(at: 2)).lowercased()
            }

            var thumbTim: String? = nil
            var thumbExt: String? = nil
            if let tm = thumbImgBeforeSrcRegex?.firstMatch(in: html, options: [], range: window), tm.numberOfRanges >= 3 {
                thumbTim = ns.substring(with: tm.range(at: 1))
                thumbExt = ns.substring(with: tm.range(at: 2)).lowercased()
            } else if let tm = thumbImgAfterSrcRegex?.firstMatch(in: html, options: [], range: window), tm.numberOfRanges >= 3 {
                thumbTim = ns.substring(with: tm.range(at: 1))
                thumbExt = ns.substring(with: tm.range(at: 2)).lowercased()
            }

            if let tim = (fileTim ?? thumbTim) {
                let extNoDot = (fileExt ?? thumbExt ?? "jpg").trimmingCharacters(in: .whitespacesAndNewlines)
                let thumbExtNoDot: String = {
                    let candidate = (thumbExt ?? extNoDot).lowercased()
                    switch candidate {
                    case "jpeg", "jpg", "png", "gif", "webp":
                        return candidate
                    default:
                        return "jpg"
                    }
                }()

                let full = "/\(board)/src/\(tim).\(extNoDot)"
                let thumb = "/\(board)/thumb/\(tim)s.\(thumbExtNoDot)"
                files = [ExternalFile(path: full, thumb: thumb, mime: nil, size: nil, width: nil, height: nil, originalName: nil)]
            }

            // Time: try to extract from title/datetime attributes or fallback 0
            let time = 0

            let post = ExternalPost(
                no: no,
                sub: subject,
                com: message,
                name: name,
                time: time,
                tim: nil,
                ext: nil,
                filename: nil,
                fsize: nil,
                fpath: nil,
                mediaKey: nil,
                attachments: nil,
                files: files
            )
            results.append(post)
        }

        return results
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
