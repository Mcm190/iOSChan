import Foundation

struct PostPayload {
    let boardID: String
    let threadNo: Int?
    var name: String?
    var subject: String?
    var email: String?
    var comment: String
    var imageData: Data?
    var imageFilename: String?
    var captchaToken: String?
    var captchaId: String?
}

enum PostError: Error, LocalizedError {
    case missingCaptcha
    case invalidResponse
    case serverMessage(String)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .missingCaptcha: return "CAPTCHA is required."
        case .invalidResponse: return "Invalid server response."
        case .serverMessage(let msg): return msg
        case .network(let err): return err.localizedDescription
        }
    }
}

final class PostingManager {
    static let shared = PostingManager()

    private init() {}

    func submit(_ payload: PostPayload) async throws {
        guard let token = payload.captchaToken, !token.isEmpty else { throw PostError.missingCaptcha }

        let url = URL(string: "https://sys.4chan.org/\(payload.boardID)/post")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = try await buildMultipartBody(boundary: boundary, payload: payload, token: token)
        request.httpBody = body

        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        if let cookie = CookieBridge.shared.cookieHeader(for: "4chan.org") {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let referer: String
        if let resto = payload.threadNo {
            referer = "https://boards.4chan.org/\(payload.boardID)/thread/\(resto)/post"
        } else {
            referer = "https://boards.4chan.org/\(payload.boardID)/post"
        }
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("https://boards.4chan.org", forHTTPHeaderField: "Origin")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw PostError.invalidResponse }

            if (200..<400).contains(http.statusCode) {
                if let html = String(data: data, encoding: .utf8) {
                    if html.localizedCaseInsensitiveContains("error") || html.localizedCaseInsensitiveContains("ban") {
                        throw PostError.serverMessage("Server responded with an error. Please verify your post and CAPTCHA.")
                    }
                }
                return
            } else {
                let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw PostError.serverMessage(msg)
            }
        } catch {
            throw PostError.network(error)
        }
    }

    private func buildMultipartBody(boundary: String, payload: PostPayload, token: String) async throws -> Data {
        var data = Data()

        func appendField(_ name: String, _ value: String) {
            data.appendString("--\(boundary)\r\n")
            data.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            data.appendString("\(value)\r\n")
        }

        func appendFileField(name: String, filename: String, mimeType: String, fileData: Data) {
            data.appendString("--\(boundary)\r\n")
            data.appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
            data.appendString("Content-Type: \(mimeType)\r\n\r\n")
            data.append(fileData)
            data.appendString("\r\n")
        }

        appendField("mode", "regist")
        if let resto = payload.threadNo { appendField("resto", String(resto)) }
        appendField("com", payload.comment)

        if let name = payload.name, !name.isEmpty { appendField("name", name) }
        if let subject = payload.subject, !subject.isEmpty { appendField("sub", subject) }
        if let email = payload.email, !email.isEmpty { appendField("email", email) }

        appendField("h-captcha-response", token)
        if let cid = payload.captchaId, !cid.isEmpty {
            appendField("captcha_id", cid)
        }

        if let imgData = payload.imageData, !imgData.isEmpty {
            let filename = payload.imageFilename ?? "file.jpg"
            let mime = mimeType(for: filename)
            appendFileField(name: "upfile", filename: filename, mimeType: mime, fileData: imgData)
        }

        data.appendString("--\(boundary)--\r\n")
        return data
    }

    private func mimeType(for filename: String) -> String {
        let lower = filename.lowercased()
        if lower.hasSuffix(".png") { return "image/png" }
        if lower.hasSuffix(".gif") { return "image/gif" }
        if lower.hasSuffix(".webp") { return "image/webp" }
        if lower.hasSuffix(".jpeg") || lower.hasSuffix(".jpg") { return "image/jpeg" }
        if lower.hasSuffix(".webm") { return "video/webm" }
        if lower.hasSuffix(".mp4") { return "video/mp4" }
        return "application/octet-stream"
    }
}

private extension Data {
    mutating func appendString(_ s: String) {
        if let d = s.data(using: .utf8) { append(d) }
    }
}
