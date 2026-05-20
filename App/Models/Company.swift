import Foundation

enum CompanyHazardClass: String, Codable, CaseIterable, Identifiable, Equatable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Az Tehlikeli"
        case .medium: return "Tehlikeli"
        case .high: return "Çok Tehlikeli"
        }
    }

    var shortTitle: String {
        switch self {
        case .low: return "Az"
        case .medium: return "Tehlikeli"
        case .high: return "Çok Tehlikeli"
        }
    }
}

struct Company: Codable, Identifiable, Equatable {
    let id: UUID
    let userID: UUID
    let name: String
    let hazardClass: CompanyHazardClass
    let logoPath: String?
    let isArchived: Bool
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case hazardClass = "hazard_class"
        case logoPath = "logo_path"
        case isArchived = "is_archived"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CompanyDraft: Equatable {
    var id: UUID?
    var name: String = ""
    var hazardClass: CompanyHazardClass = .medium
    var logoPath: String?

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !trimmedName.isEmpty
    }
}

struct CompanySnapshot: Codable, Equatable {
    let id: UUID
    let name: String
    let hazardClass: CompanyHazardClass
    let logoPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case hazardClass = "hazard_class"
        case logoPath = "logo_path"
    }

    init(company: Company) {
        self.id = company.id
        self.name = company.name
        self.hazardClass = company.hazardClass
        self.logoPath = company.logoPath
    }
}
