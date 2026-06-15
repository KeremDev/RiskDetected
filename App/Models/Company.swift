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
    let address: String?
    let contactPerson: String?
    let department: String?
    let defaultResponsible: String?
    let defaultDueDays: Int?
    let isArchived: Bool
    let createdAt: String?
    let updatedAt: String?

    var listSubtitle: String {
        [hazardClass.title, department?.nonEmpty]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var reportInfoText: String {
        [
            hazardClass.title,
            department.map { "Birim: \($0)" },
            contactPerson.map { "İlgili: \($0)" },
            defaultResponsible.map { "Sorumlu: \($0)" },
            defaultDueDays.map { "Termin: \($0) gün" },
            address.map { "Adres: \($0)" }
        ]
        .compactMap { $0?.nonEmpty }
        .joined(separator: " · ")
    }

    var defaultDueText: String? {
        defaultDueDays.map { "\($0) gün" }
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
