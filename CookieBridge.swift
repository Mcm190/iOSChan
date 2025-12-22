import Foundation

final class CookieBridge {
    static let shared = CookieBridge()
    private init() {}

    private var cookies: [HTTPCookie] = []

    func update(with newCookies: [HTTPCookie]) {
        // Merge by name+domain+path
        var dict: [String: HTTPCookie] = [:]
        for c in cookies { dict[key(for: c)] = c }
        for c in newCookies { dict[key(for: c)] = c }
        cookies = Array(dict.values)
    }

    private func key(for c: HTTPCookie) -> String { "\(c.name)|\(c.domain)|\(c.path)" }

    func cookieHeader(for domainContains: String) -> String? {
        let filtered = cookies.filter { $0.domain.contains(domainContains) }
        guard !filtered.isEmpty else { return nil }
        let parts = filtered.map { "\($0.name)=\($0.value)" }
        return parts.joined(separator: "; ")
    }
}
