import Foundation

/// `GET /support/canned-responses`.
struct CannedResponse: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let tags: [String]
    let createdAt: Date?
}

struct CannedResponseBody: Encodable {
    var title: String?
    var body: String?
    var tags: [String]?
}

/// `GET /support/kb-articles`. Keyed by `slug` for detail/patch; no delete route.
struct KbArticle: Decodable, Identifiable, Equatable {
    let id: String
    let slug: String
    let title: String
    let body: String
    let category: String?
    let isPublished: Bool
    let views: Int
    let createdAt: Date?
    let updatedAt: Date?
}

struct CreateKbArticleBody: Encodable {
    let slug: String
    let title: String
    let body: String
    var category: String?
    var isPublished: Bool?
}

struct UpdateKbArticleBody: Encodable {
    var slug: String?
    var title: String?
    var body: String?
    var category: String?
    var isPublished: Bool?
}

/// `GET /support/categories`. No timestamps on this model.
struct TicketCategory: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let slug: String
    let slaFirstResponseMin: Int
    let slaResolutionMin: Int
}

struct CreateCategoryBody: Encodable {
    let name: String
    let slug: String
    var slaFirstResponseMin: Int?
    var slaResolutionMin: Int?
}

struct UpdateCategoryBody: Encodable {
    var name: String?
    var slug: String?
    var slaFirstResponseMin: Int?
    var slaResolutionMin: Int?
}
