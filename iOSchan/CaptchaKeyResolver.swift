import Foundation

enum CaptchaKeyResolverError: Error {
    case network(Error)
}

struct CaptchaKeyResolver {
    
    // 4chan's public hCaptcha Site Key.
    // This rarely changes.
    
    static let hardcodedSiteKey = "33f96e6a-387c-4706-9513-55f671f25a39"

    static func fetchSiteKey(boardID: String, threadNo: Int?) async throws -> (String, URL) {
        // We simulate a network delay slightly so the UI doesn't feel glitchy,
        // but we return the known key immediately.
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s optional delay
        
        // Always return the hardcoded key.
        // The BaseURL is important for cookies/referer checks.
        let baseURL = URL(string: "https://boards.4chan.org/\(boardID)/")!
        
        return (hardcodedSiteKey, baseURL)
    }
}
