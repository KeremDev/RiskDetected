import Foundation

enum CompanyHazardClass: String, Codable, CaseIterable, Identifiable, Equatable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return RDLocalization.string("localizable.company.az.tehlikeli.5a7188a4", table: .localizable, fallback: "Az Tehlikeli")
        case .medium: return RDLocalization.string("localizable.company.tehlikeli.a8563876", table: .localizable, fallback: "Tehlikeli")
        case .high: return RDLocalization.string("localizable.company.cok.tehlikeli.66f7a10e", table: .localizable, fallback: "Çok Tehlikeli")
        }
    }

    var shortTitle: String {
        switch self {
        case .low: return RDLocalization.string("localizable.company.az.563adf3d", table: .localizable, fallback: "Az")
        case .medium: return RDLocalization.string("localizable.company.tehlikeli.533167db", table: .localizable, fallback: "Tehlikeli")
        case .high: return RDLocalization.string("localizable.company.cok.tehlikeli.b663cc01", table: .localizable, fallback: "Çok Tehlikeli")
        }
    }
}

struct Company: Codable, Identifiable, Equatable {
    let id: UUID
    let userID: UUID
    let name: String
    let hazardClass: CompanyHazardClass
    let logoPath: String?
    let address: String?
    let contactPerson: String?
    let department: String?
    let defaultResponsible: String?
    let defaultDueDays: Int?
    let isArchived: Bool
    let createdAt: String?
    let updatedAt: String?

    var listSubtitle: String {
        [
            RDLanguage.current == .turkish ? hazardClass.title : nil,
            department?.nonEmpty,
        ]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var reportInfoText: String {
        [
            RDLanguage.current == .turkish ? hazardClass.title : nil,
            department.map { "Birim: \($0)" },
            contactPerson.map { RDLocalization.format("localizable.company.ilgili.1.2f721c63", table: .localizable, fallback: "İlgili: %1$@", arguments: [String(describing: $0)]) },
            defaultResponsible.map { "Sorumlu: \($0)" },
            defaultDueDays.map { RDLocalization.format("localizable.company.termin.1.gun.1d4912c1", table: .localizable, fallback: "Termin: %1$@ gün", arguments: [String(describing: $0)]) },
            address.map { "Adres: \($0)" }
        ]
        .compactMap { $0?.nonEmpty }
        .joined(separator: " · ")
    }

    var defaultDueText: String? {
        defaultDueDays.map { RDLocalization.format("localizable.company.1.gun.886f2f8c", table: .localizable, fallback: "%1$@ gün", arguments: [String(describing: $0)]) }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case hazardClass = "hazard_class"
        case logoPath = "logo_path"
        case address
        case contactPerson = "contact_person"
        case department
        case defaultResponsible = "default_responsible"
        case defaultDueDays = "default_due_days"
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
    var address: String = ""
    var contactPerson: String = ""
    var department: String = ""
    var defaultResponsible: String = ""
    var defaultDueDaysText: String = ""

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var defaultDueDays: Int? {
        let trimmed = defaultDueDaysText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    var isValid: Bool {
        let dueText = defaultDueDaysText.trimmingCharacters(in: .whitespacesAndNewlines)
        let dueIsValid = dueText.isEmpty || (defaultDueDays.map { (1...365).contains($0) } ?? false)
        return !trimmedName.isEmpty && dueIsValid
    }
}

struct CompanySnapshot: Codable, Equatable {
    let id: UUID
    let name: String
    let hazardClass: CompanyHazardClass
    let logoPath: String?
    let address: String?
    let contactPerson: String?
    let department: String?
    let defaultResponsible: String?
    let defaultDueDays: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case hazardClass = "hazard_class"
        case logoPath = "logo_path"
        case address
        case contactPerson = "contact_person"
        case department
        case defaultResponsible = "default_responsible"
        case defaultDueDays = "default_due_days"
    }

    init(company: Company) {
        self.id = company.id
        self.name = company.name
        self.hazardClass = company.hazardClass
        self.logoPath = company.logoPath
        self.address = company.address
        self.contactPerson = company.contactPerson
        self.department = company.department
        self.defaultResponsible = company.defaultResponsible
        self.defaultDueDays = company.defaultDueDays
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
