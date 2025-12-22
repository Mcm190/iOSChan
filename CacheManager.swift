import Foundation

struct CacheManager {
    static func clearCaches() throws {
        // 1) URLCache
        URLCache.shared.removeAllCachedResponses()

        // 2) Temporary directory
        let tmp = FileManager.default.temporaryDirectory
        if let tempContents = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for url in tempContents {
                try? FileManager.default.removeItem(at: url)
            }
        }

        // 3) Downloaded images folders we created in Documents: (BOARD-THREAD-DATE)
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let contents = try FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.isDirectoryKey])
            for url in contents {
                let name = url.lastPathComponent
                // Our download folders are created like: (BOARD-THREAD-DATE)
                if name.hasPrefix("(") && name.hasSuffix(")") {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }
}
