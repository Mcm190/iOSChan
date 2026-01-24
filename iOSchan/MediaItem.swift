import Foundation

struct MediaItem: Identifiable {
    let id: String
    let fullURL: URL
    let thumbURL: URL
    let isVideo: Bool
    let isGif: Bool

    init(board: String, tim: Int, ext: String?) {
        let fileExt = ext ?? ".jpg"
        let lower = fileExt.lowercased()
        self.isVideo = lower == ".webm" || lower == ".mp4"
        self.isGif = lower == ".gif"
        self.fullURL = URL(string: "https://i.4cdn.org/\(board)/\(tim)\(fileExt)")!
        self.thumbURL = URL(string: "https://i.4cdn.org/\(board)/\(tim)s.jpg")!
        self.id = self.fullURL.absoluteString
    }

    init(fullURL: URL, thumbURL: URL, mime: String? = nil) {
        self.fullURL = fullURL
        self.thumbURL = thumbURL
        self.id = fullURL.absoluteString

        let mimeLower = mime?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let mimeLower, !mimeLower.isEmpty {
            self.isGif = mimeLower == "image/gif"
            self.isVideo = mimeLower.hasPrefix("video/")
        } else {
            let ext = fullURL.pathExtension.lowercased()
            self.isVideo = (ext == "webm" || ext == "mp4")
            self.isGif = (ext == "gif")
        }
    }
}
