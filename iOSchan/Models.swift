import Foundation

// MARK: - Board Models

// Added 'Sendable' to tell Swift this is safe to pass between threads
struct BoardListResponse: Codable, Sendable {
    let boards: [Board]
}

struct Board: Codable, Identifiable, Sendable {
    let board: String
    let title: String
    let meta_description: String?
    let ws_board: Int?
    
    var id: String { board }
}

// MARK: - Thread Models

struct CatalogPage: Codable, Sendable {
    let page: Int
    let threads: [Thread]
}

struct Thread: Codable, Identifiable, Sendable {
    let no: Int
    let time: Int
    let sub: String?
    let com: String?
    let name: String?
    let posterID: String?
    let country: String?
    let country_name: String?
    let tim: Int?
    let ext: String?
    let replies: Int?
    let images: Int?
    let filename: String?
    let fsize: Int?

    private enum CodingKeys: String, CodingKey {
        case no, time, sub, com, name
        case posterID = "id"
        case country
        case country_name
        case tim, ext, replies, images, filename, fsize
    }
    
    var id: Int { no }
}

struct ThreadDetailResponse: Codable, Sendable {
    let posts: [Thread]
}
