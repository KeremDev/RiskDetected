import Foundation

/// A durable, account-owned create intent. Session is deliberately not persisted: after
/// re-login the same owner may explicitly retry, with fresh server authorization.
struct NovaPilotCompanyIntent: Codable, Equatable {
    let ownerID: UUID
    let mutationID: UUID
    let name: String
    let hazard: String
    var sector: String? = nil
    var email: String? = nil
    var employeeCount: Int? = nil
    var responsibleName: String? = nil

    static func makeProfile(ownerID: UUID, name: String, hazard: String, sector: String,
                            email: String, employeeCount: String, responsibleName: String) throws -> Self {
        var intent = try make(ownerID: ownerID, name: name, hazard: hazard)
        let normalizedSector = try make(ownerID: ownerID, name: sector, hazard: hazard).name
        guard normalizedSector.utf8.count <= 120 else { throw NovaPersonnelFailure.validation }
        intent.sector = normalizedSector
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty {
            guard email.utf8.count <= 254, email.range(of: "^[^\\s@]+@[^\\s@]+[.][^\\s@]+$", options: .regularExpression) != nil else { throw NovaPersonnelFailure.validation }
            intent.email = email
        }
        let count = employeeCount.trimmingCharacters(in: .whitespacesAndNewlines)
        if !count.isEmpty {
            guard count.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(count), (0...10_000_000).contains(number) else { throw NovaPersonnelFailure.validation }
            intent.employeeCount = number
        }
        if !responsibleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            intent.responsibleName = try make(ownerID: ownerID, name: responsibleName, hazard: hazard).name
        }
        return intent
    }

    func validate() throws {
        if let sector {
            let normalized = try Self.makeProfile(ownerID: ownerID, name: name, hazard: hazard, sector: sector,
                email: email ?? "", employeeCount: employeeCount.map(String.init) ?? "", responsibleName: responsibleName ?? "")
            guard normalized.name == name, normalized.sector == sector, normalized.email == email,
                  normalized.employeeCount == employeeCount, normalized.responsibleName == responsibleName else { throw NovaPersonnelFailure.validation }
        } else {
            // Old build's durable V1 requests must still be replayable, without fabricated fields.
            guard try Self.make(ownerID: ownerID, name: name, hazard: hazard).name == name,
                  email == nil, employeeCount == nil, responsibleName == nil else { throw NovaPersonnelFailure.validation }
        }
    }

    static func make(ownerID: UUID, name: String, hazard: String) throws -> Self {
        let name = name.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "[ \\t\\r\\n]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " "))
        guard !name.isEmpty, name.utf8.count <= 200, ["low", "medium", "high"].contains(hazard),
              !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 || $0.value == 0x200B || $0.value == 0xFEFF })
        else { throw NovaPersonnelFailure.validation }
        return .init(ownerID: ownerID, mutationID: UUID(), name: name, hazard: hazard)
    }
}

@MainActor final class NovaPilotCompanyService {
    typealias RPC = (String, [String: PersonnelRPCValue]) async throws -> Data
    private let rpc: RPC
    private let currentIdentity: () -> NovaSessionIdentity?
    private let storage: any PersonnelPendingStorage
    private static var inFlight = Set<UUID>()

    init(rpc: @escaping RPC, currentIdentity: @escaping () -> NovaSessionIdentity?, storage: any PersonnelPendingStorage) {
        self.rpc = rpc; self.currentIdentity = currentIdentity; self.storage = storage
    }

    func pending(identity: NovaSessionIdentity) throws -> NovaPilotCompanyIntent? {
        try check(identity)
        guard let data = try storage.read(account: identity.userID.uuidString.lowercased()) else { return nil }
        let intent = try JSONDecoder().decode(NovaPilotCompanyIntent.self, from: data)
        try intent.validate()
        let validated = try NovaPilotCompanyIntent.make(ownerID: intent.ownerID, name: intent.name, hazard: intent.hazard)
        guard intent.ownerID == identity.userID, validated.name == intent.name else { throw NovaPersonnelFailure.denied }
        return intent
    }

    func create(_ intent: NovaPilotCompanyIntent, identity: NovaSessionIdentity) async throws -> UUID {
        try check(identity)
        try intent.validate()
        guard intent.ownerID == identity.userID else { throw NovaPersonnelFailure.denied }
        let validated = try NovaPilotCompanyIntent.make(ownerID: intent.ownerID, name: intent.name, hazard: intent.hazard)
        guard validated.name == intent.name else { throw NovaPersonnelFailure.validation }
        guard Self.inFlight.insert(identity.userID).inserted else { throw NovaPersonnelFailure.unavailable }
        defer { Self.inFlight.remove(identity.userID) }
        if let saved = try pending(identity: identity), saved != intent { throw NovaPersonnelFailure.unavailable }
        let account = identity.userID.uuidString.lowercased()
        try storage.write(JSONEncoder().encode(intent), account: account)
        // Never fall back to companies.insert, and never generate a new mutation on retry.
        var args: [String: PersonnelRPCValue] = [
            "p_mutation": .id(intent.mutationID), "p_name": .string(intent.name), "p_hazard_class": .string(intent.hazard)
        ]
        if let sector = intent.sector {
            args["p_sector"] = .string(sector)
            args["p_email"] = intent.email.map(PersonnelRPCValue.string) ?? .null
            args["p_employee_count"] = intent.employeeCount.map { .number(Int64($0)) } ?? .null
            args["p_responsible_name"] = intent.responsibleName.map(PersonnelRPCValue.string) ?? .null
        }
        let data = try await rpc(intent.sector == nil ? "isg_pilot_company_create_v1" : "isg_pilot_company_create_v2", args)
        try check(identity)
        guard data.count <= 16384 else { throw NovaPersonnelFailure.unavailable }
        struct Receipt: Decodable {
            struct Row: Decodable { let id: UUID; let user_id: UUID; let name: String; let hazard_class: String; let is_archived: Bool }
            let schema_version: Int; let company: Row; let replayed: Bool
        }
        let receipt = try JSONDecoder().decode(Receipt.self, from: data)
        guard receipt.schema_version == (intent.sector == nil ? 1 : 2), receipt.company.user_id == identity.userID,
              !receipt.company.is_archived, !receipt.company.name.isEmpty,
              ["low", "medium", "high"].contains(receipt.company.hazard_class) else { throw NovaPersonnelFailure.unavailable }
        // A replay returns the current row, whose name may have changed since creation.
        try storage.remove(account: account)
        return receipt.company.id
    }

    private func check(_ identity: NovaSessionIdentity) throws {
        try Task.checkCancellation()
        guard currentIdentity() == identity else { throw NovaPersonnelFailure.denied }
    }
}
