import Foundation

enum MediaCacheManager {
    static func prefetchThread(boardID: String, threadNo: Int) {
        FourChanAPI.shared.fetchThreadDetails(board: boardID, threadNo: threadNo) { result in
            switch result {
            case .success(let posts):
                let mediaPosts = posts.filter { $0.tim != nil && $0.ext != nil }
                for post in mediaPosts {
                    guard let tim = post.tim, let ext = post.ext else { continue }
                    if let url = URL(string: "https://i.4cdn.org/\(boardID)/\(tim)\(ext)") {
                        prefetch(url: url)
                    }
                }
            case .failure:
                break
            }
        }
    }

    private static func prefetch(url: URL) {
        // Download and store to URLCache; also write to Documents for offline browsing
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else { return }
            // Put into URLCache if possible
            if let response = response {
                let cachedResponse = CachedURLResponse(response: response, data: data)
                URLCache.shared.storeCachedResponse(cachedResponse, for: request)
            }
            // Also write to a dedicated cache folder for offline access
            do {
                let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let cacheFolder = documentsUrl.appendingPathComponent("MediaCache", isDirectory: true)
                if !FileManager.default.fileExists(atPath: cacheFolder.path) {
                    try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
                }
                let filename = url.lastPathComponent
                let destination = cacheFolder.appendingPathComponent(filename)
                if !FileManager.default.fileExists(atPath: destination.path) {
                    try data.write(to: destination)
                }
            } catch {
                // Ignore write errors
            }
        }.resume()
    }
}
