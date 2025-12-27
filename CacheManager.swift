import Foundation

struct CacheManager {
    static func clearCaches() throws {
        URLCache.shared.removeAllCachedResponses()

        let tmp = FileManager.default.temporaryDirectory
        if let tempContents = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for url in tempContents {
                try? FileManager.default.removeItem(at: url)
            }
        }

        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let contents = try FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.isDirectoryKey])
            for url in contents {
                let name = url.lastPathComponent
                if name.hasPrefix("(") && name.hasSuffix(")") {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }
}
