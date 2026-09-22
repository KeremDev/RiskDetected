import Foundation
import CryptoKit

indirect enum IsgWorkspaceRPCValue: Encodable, Equatable {
    case string(String), number(Int), bool(Bool), array([IsgWorkspaceRPCValue])
    case object([String: IsgWorkspaceRPCValue]), null
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
    static func id(_ value: UUID?) -> Self { value.map { .string($0.uuidString.lowercased()) } ?? .null }
}

/// Keeps one mutation key for one unchanged command. If the server commits but
/// the response is lost, tapping Save again replays the receipt instead of
/// creating a second record. Editing any command field starts a new attempt.
struct IsgWorkspaceMutationAttempt {
    private var signature: String?
    private var mutationID = UUID()

    mutating func id(namespace: String, payload: [String: IsgWorkspaceRPCValue]) -> UUID {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = (try? encoder.encode(IsgWorkspaceRPCValue.object(payload))) ?? Data()
        return id(namespace: namespace, components: [Self.digest(encoded)])
    }

    mutating func id(namespace: String, components: [String]) -> UUID {
        let value = ([namespace] + components).map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        if signature != value { signature = value; mutationID = UUID() }
        return mutationID
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum IsgWorkspaceAPIFailure: Error, Equatable { case staleSession, invalidResponse, invalidRequest }

struct IsgWorkspaceCompany: Equatable {
    let id: UUID
    let name: String
    let hazardClass: String
    let status: String
    let version: Int64
    let sector: String?
    let email: String?
    let declaredEmployeeCount: Int?
    let address: String?
    let responsibleName: String?
    let responsiblePhone: String?
    let responsibleEmail: String?
    let profileVersion: Int64?

    init(id: UUID, name: String, hazardClass: String, status: String, version: Int64,
         sector: String? = nil, email: String? = nil, declaredEmployeeCount: Int? = nil,
         address: String? = nil, responsibleName: String? = nil, responsiblePhone: String? = nil,
         responsibleEmail: String? = nil, profileVersion: Int64? = nil) {
        self.id = id; self.name = name; self.hazardClass = hazardClass; self.status = status; self.version = version
        self.sector = sector; self.email = email; self.declaredEmployeeCount = declaredEmployeeCount
        self.address = address; self.responsibleName = responsibleName; self.responsiblePhone = responsiblePhone
        self.responsibleEmail = responsibleEmail; self.profileVersion = profileVersion
    }

    func applying(_ profile: IsgWorkspaceCompanyProfile) -> Self {
        .init(id: id, name: name, hazardClass: hazardClass, status: status, version: version,
              sector: profile.sector, email: profile.email, declaredEmployeeCount: profile.declaredEmployeeCount,
              address: profile.address, responsibleName: profile.responsibleName,
              responsiblePhone: profile.responsiblePhone, responsibleEmail: profile.responsibleEmail,
              profileVersion: profile.version)
    }
}

struct IsgWorkspaceCompanyProfile: Equatable {
    let sector: String
    let email: String?
    let declaredEmployeeCount: Int?
    let address: String?
    let responsibleName: String?
    let responsiblePhone: String?
    let responsibleEmail: String?
    let version: Int64
}

struct IsgWorkspaceCompanyDraft: Equatable {
    var name: String
    var hazardClass: String
    var sector: String
    var email: String
    var employeeCount: Int?
    var address: String
    var responsibleName: String
    var responsiblePhone: String
    var responsibleEmail: String
}

struct IsgWorkspaceMember: Equatable {
    let id: UUID
    let userID: UUID?
    let role: String
    let status: String
    let isPracticingExpert: Bool
    let permissionRevision: Int64
    let version: Int64
    let activeCompanyCount: Int64
}
struct IsgWorkspaceMemberPage: Equatable { let rows: [IsgWorkspaceMember]; let next: UUID? }

struct IsgWorkspaceCompanyAssignment: Identifiable, Equatable {
    enum PeriodState { case current, future, ended }
    let id: UUID
    let companyID: UUID
    let membershipID: UUID
    let userID: UUID
    let assignmentRole: String
    let membershipRole: String
    let membershipStatus: String
    let startsAt: String
    let endsAt: String?
    let version: Int64

    func periodState(at now: Date = Date()) -> PeriodState {
        let formatter = ISO8601DateFormatter()
        func date(_ value: String) -> Date? {
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions.insert(.withFractionalSeconds)
            return formatter.date(from: value)
        }
        guard let start = date(startsAt) else { return .ended }
        // A cancelled future assignment is retained as an empty interval.
        if let end = endsAt.flatMap(date), end <= start || end <= now { return .ended }
        return start > now ? .future : .current
    }
}

struct IsgWorkspaceCompanyAssignmentPage: Equatable {
    let rows: [IsgWorkspaceCompanyAssignment]
    let next: UUID?
}

struct IsgWorkspaceInvitation: Equatable {
    let id: UUID
    let email: String
    let role: String
    let status: String
    let expiresAt: String
    let version: Int64
}
struct IsgWorkspaceInvitationPage: Equatable { let rows: [IsgWorkspaceInvitation]; let next: UUID? }

struct IsgWorkspaceInvitationToken: Equatable {
    let invitationID: UUID
    let role: String
    let status: String
    let expiresAt: String
    let token: String
}

struct IsgPersonnelMetrics: Equatable {
    struct Counts: Equatable { let active: Int64; let archived: Int64 }
    struct AssignmentCounts: Equatable { let current: Int64; let historical: Int64 }
    let workspaceID: UUID
    let companyID: UUID?
    let workplaces: Counts
    let departments: Counts
    let employees: Counts
    let jobRoles: Counts
    let contractors: Counts
    let assignments: AssignmentCounts
}

struct IsgWorkspaceDashboard: Equatable {
    struct Pair: Equatable { let first: Int64?; let second: Int64? }
    let workspaceID: UUID; let companyID: UUID?
    let companies: Pair; let experts: Int64?; let nonconformities: Pair
    let visits: Pair; let training: Pair; let deadlines: Pair
}

struct IsgWorkspaceSearchRow: Decodable, Equatable {
    let kind: String; let id: UUID; let title: String; let subtitle: String?
    enum CodingKeys: String, CodingKey { case kind,id,title,subtitle }
}
struct IsgWorkspaceSearchPage: Equatable {
    let rows: [IsgWorkspaceSearchRow]; let nextKind: String?; let nextID: UUID?
}

struct IsgWorkspaceAnalysisItem: Decodable, Equatable {
    let id: UUID; let kind: String?; let title: String
    let ordinal: Int?; let displayOrder: Int?
    let body: String?; let description: String?; let recommendation: String?
    let recommendedAction: String?; let referencesText: String?
    let sourceKey: String?; let itemClass: String?; let category: String?; let responsible: String?
    let isScored: Bool?; let fkProbability: Double?; let fkFrequency: Double?; let fkSeverity: Double?
    let fkScore: Double?; let fkBand: String?; let m5Probability: Int?; let m5Severity: Int?
    let m5Score: Int?; let m5Band: String?; let sourcePhotoIndices: [Int]?
    let audience: String?; let durationMinutes: Int?; let catalogCode: String?
    let sourceFindingKeys: [String]?; let version: Int64?
    enum CodingKeys: String, CodingKey {
        case id,kind,title,ordinal,body,description,recommendation
        case displayOrder = "display_order"
        case recommendedAction = "recommended_action", referencesText = "references_text"
        case sourceKey = "source_key", itemClass = "item_class", category, responsible, audience, version
        case isScored = "is_scored", fkProbability = "fk_probability", fkFrequency = "fk_frequency"
        case fkSeverity = "fk_severity", fkScore = "fk_score", fkBand = "fk_band"
        case m5Probability = "m5_probability", m5Severity = "m5_severity", m5Score = "m5_score", m5Band = "m5_band"
        case sourcePhotoIndices = "source_photo_indices", durationMinutes = "duration_minutes"
        case catalogCode = "catalog_code", sourceFindingKeys = "source_finding_keys"
    }
}
struct IsgWorkspaceAnalysisResult: Equatable {
    let analysisID: UUID; let title: String; let primaryMethod: String; let createdAt: String
    let riskFindings: [IsgWorkspaceAnalysisItem]
    let expertItems: [IsgWorkspaceAnalysisItem]
    let trainingItems: [IsgWorkspaceAnalysisItem]
}
struct IsgWorkspaceAnalysisSummary: Identifiable, Equatable {
    let id: UUID; let title: String; let kind: String; let primaryMethod: String
    let createdAt: String; let findingCount: Int; let highestBand: String?
}
struct IsgWorkspaceAnalysisPage: Equatable {
    let rows: [IsgWorkspaceAnalysisSummary]; let offset: Int; let hasMore: Bool
}
struct IsgWorkspacePhotoAnalysisJob: Identifiable, Equatable {
    let id: UUID
    let workspaceID: UUID
    let companyID: UUID
    let status: String
    let outputAssetID: UUID?
    let errorCode: String?
    let version: Int64?
    let analysisID: UUID?
}
struct IsgWorkspaceFilingResult: Equatable {
    let nonconformityID: UUID; let created: Bool; let successMessageKey: String
}
struct IsgWorkspaceExportResult: Equatable {
    let id: UUID; let status: String; let outputAssetID: UUID?
}
struct IsgWorkspaceChange: Decodable, Equatable {
    let sequence: Int64; let eventType: String; let aggregateType: String
    let aggregateID: UUID; let aggregateVersion: Int64
    enum CodingKeys: String, CodingKey {
        case sequence, eventType = "event_type", aggregateType = "aggregate_type"
        case aggregateID = "aggregate_id", aggregateVersion = "aggregate_version"
    }
}
struct IsgWorkspaceChangePage: Equatable { let rows: [IsgWorkspaceChange]; let next: Int64 }

enum IsgWorkspaceDomain: String, CaseIterable, Equatable {
    case personnel, training, risk, nonconformity, checklist
    case emergencyPlan, drill, appointment, ppe, equipment
    case katip, annualPlan, board, workPermit, visit, files
}

struct IsgWorkspaceDomainRecord: Identifiable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String?
    let status: String?
    let version: Int64?
    let facts: [(String, String)]
    let checklistItems: [IsgWorkspaceChecklistItem]
    let trainingParticipants: [IsgWorkspaceTrainingParticipant]
    let boardDecisions: [IsgWorkspaceBoardDecision]
    let riskVersions: [IsgWorkspaceRiskVersion]
    let equipmentInspections: [IsgWorkspaceEquipmentInspection]
    let assetID: UUID?
    let fileExtension: String?
    let originalFilename: String?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.subtitle == rhs.subtitle &&
        lhs.status == rhs.status && lhs.version == rhs.version &&
        lhs.assetID == rhs.assetID && lhs.fileExtension == rhs.fileExtension &&
        lhs.originalFilename == rhs.originalFilename &&
        lhs.checklistItems == rhs.checklistItems &&
        lhs.trainingParticipants == rhs.trainingParticipants &&
        lhs.boardDecisions == rhs.boardDecisions &&
        lhs.riskVersions == rhs.riskVersions &&
        lhs.equipmentInspections == rhs.equipmentInspections &&
        lhs.facts.elementsEqual(rhs.facts) { $0.0 == $1.0 && $0.1 == $1.1 }
    }
}

struct IsgWorkspaceRiskVersion: Identifiable, Equatable {
    var id: Int { number }
    let number: Int
    let kind: String
    let assessmentOn: String
    let revisionOn: String?
    let scopeSummary: String?
    let reason: String?
    let state: String
    let validUntil: String?
    let periodYears: Int?
    let periodSource: String?
    let periodNeedsReview: Bool
    let sourceDrift: Bool
    let editRevision: Int
    let cancellationNote: String?
}

struct IsgWorkspaceEquipmentInspection: Identifiable, Equatable {
    let id: UUID
    let performedOn: String
    let result: String
    let nextDueOn: String?
    let periodMonths: Int?
    let dueSource: String?
    let inspector: String?
    let externalRef: String?
    let note: String?
    let assetID: UUID?
    let version: Int64
    let katipDeclared: Bool
    let katipNote: String?
}

struct IsgWorkspaceBoardDecision: Identifiable, Equatable {
    let id: UUID
    let number: Int
    let text: String
    let responsibleContact: String?
    let dueOn: String?
    let state: String
    let version: Int64
}

struct IsgWorkspaceTrainingParticipant: Identifiable, Equatable {
    let id: UUID
    let name: String
    let attended: Bool
}

struct IsgWorkspaceChecklistItem: Identifiable, Equatable {
    var id: String { code }
    let code: String
    let prompt: String
    let allowsNotApplicable: Bool
    let result: String?
    let note: String?
    let nonconformityID: UUID?
}

struct IsgWorkspaceChecklistTemplate: Identifiable, Equatable {
    var id: String { "\(code):\(version)" }
    let code: String
    let version: Int
    let title: String
    let itemCount: Int
}

struct IsgWorkspaceDomainMetric: Identifiable, Equatable {
    let id: String
    let value: Int64
}

struct IsgWorkspaceDomainSnapshot: Equatable {
    let domain: IsgWorkspaceDomain
    let companyID: UUID
    let rows: [IsgWorkspaceDomainRecord]
    let metrics: [IsgWorkspaceDomainMetric]
}

struct IsgWorkspaceEquipmentCatalog: Equatable {
    struct Suggestion: Identifiable, Equatable {
        var id: String { code }
        let code: String
        let ordinal: Int
        let defaultPeriodMonths: Int?
        let defaultBasisNote: String?
    }
    struct Rule: Identifiable, Equatable {
        var id: String { equipmentType }
        let equipmentType: String
        let periodMonths: Int
        let periodSource: String
        let needsReview: Bool
        let exceptionNote: String?
        let version: Int64
    }
    let suggestions: [Suggestion]
    let rules: [Rule]

    func period(for code: String) -> Int? {
        rules.first(where: { $0.equipmentType == code })?.periodMonths
            ?? suggestions.first(where: { $0.code == code })?.defaultPeriodMonths
    }
}

struct IsgWorkspaceMutationResult: Equatable {
    let domain: IsgWorkspaceDomain
    let companyID: UUID
    /// Returned by commands that create an aggregate. Keeping this optional
    /// lets compact product flows (for example: create a meeting, then mark it
    /// held and add its decisions) remain on the tenant-scoped API boundary.
    let recordID: UUID?
    let version: Int64?
}

struct IsgWorkspaceFileUploadResult: Equatable {
    let entryID: UUID
    let assetID: UUID
    let companyID: UUID
    let byteSize: Int64
}

struct IsgWorkspaceFileDownload: Equatable {
    let filename: String
    let data: Data
}

enum IsgWorkspaceDirectoryKind: String, Equatable { case workplace, department }

struct IsgWorkspaceDirectoryEntry: Identifiable, Equatable {
    let id: UUID
    let kind: IsgWorkspaceDirectoryKind
    let code: String
    let name: String
    let workplaceID: UUID?
    let hazardClass: String?
    let isArchived: Bool
    let version: Int64
}

struct IsgWorkspaceEmployeeEntry: Identifiable, Equatable {
    let id: UUID
    let code: String
    let name: String
    let departmentID: UUID?
    let hiredOn: String?
    let endsBefore: String?
    let isArchived: Bool
    let version: Int64
}

enum IsgWorkspacePersonnelAdvancedKind: String, CaseIterable, Equatable {
    case jobRoles = "job_roles", contractors, engagements, assignments
}

enum IsgWorkspaceTrainingAdvancedKind: String, CaseIterable, Equatable {
    case curricula, annualPlans = "annual_plans", annualItems = "annual_items", attempts, certificates
}

struct IsgWorkspaceAdvancedTopic: Identifiable, Equatable {
    let id: UUID
    let position: Int
    let title: String
    let description: String
    let durationMinutes: Int
}

struct IsgWorkspaceAdvancedRecord: Identifiable, Equatable {
    let id: UUID
    let kind: String
    let title: String
    let subtitle: String?
    let status: String?
    let version: Int64
    let fields: [String: String]
    let topics: [IsgWorkspaceAdvancedTopic]

    func uuid(_ key: String) -> UUID? { fields[key].flatMap(UUID.init(uuidString:)) }
    func text(_ key: String) -> String? { fields[key] }
    func flag(_ key: String) -> Bool { fields[key] == "true" }
}

/// RPC transport for the dark OSGB rollout. It never falls back to a personal
/// endpoint and validates the current session/workspace again after every await.
@MainActor final class IsgWorkspaceAPI {
    typealias RPC = (String, [String: IsgWorkspaceRPCValue]) async throws -> Data
    typealias Upload = (String, String, Data, String) async throws -> Void
    typealias FileWorker = (String) async throws -> Data
    private let rpc: RPC
    private let upload: Upload
    private let finalizeUpload: FileWorker
    private let download: FileWorker
    private let currentIdentity: () -> NovaSessionIdentity?
    private let isCurrentWorkspace: (NovaWorkspaceSelection) -> Bool

    init(rpc: @escaping RPC, currentIdentity: @escaping () -> NovaSessionIdentity?,
         isCurrentWorkspace: @escaping (NovaWorkspaceSelection) -> Bool,
         currentEpoch: @escaping () -> UUID?,
         upload: @escaping Upload = { _, _, _, _ in throw IsgWorkspaceAPIFailure.invalidRequest },
         finalizeUpload: @escaping FileWorker = { _ in throw IsgWorkspaceAPIFailure.invalidRequest },
         download: @escaping FileWorker = { _ in throw IsgWorkspaceAPIFailure.invalidRequest }) {
        self.rpc = { function, arguments in
            try Task.checkCancellation()
            guard let identity = currentIdentity() else { throw IsgWorkspaceAPIFailure.staleSession }
            guard let epoch = currentEpoch() else { throw IsgWorkspaceAPIFailure.staleSession }
            let data = try await rpc(function, arguments)
            try Task.checkCancellation()
            guard currentIdentity() == identity, currentEpoch() == epoch else {
                throw IsgWorkspaceAPIFailure.staleSession
            }
            return data
        }
        self.upload = upload
        self.finalizeUpload = finalizeUpload
        self.download = download
        self.currentIdentity = currentIdentity
        self.isCurrentWorkspace = isCurrentWorkspace
    }

    func list(identity: NovaSessionIdentity) async throws -> [IsgWorkspaceContext] {
        try require(identity)
        let data = try await rpc("isg_workspace_list_v1", [:])
        try require(identity)
        guard data.count <= 262_144 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let response = try JSONDecoder().decode(WorkspaceList.self, from: data)
        guard response.schemaVersion == 1, response.userID == identity.userID,
              Set(response.workspaces.map(\.workspaceID)).count == response.workspaces.count,
              response.workspaces.allSatisfy({ $0.canRead && $0.membership.userID == identity.userID }) else { throw IsgWorkspaceAPIFailure.invalidResponse }
        return response.workspaces
    }

    func context(identity: NovaSessionIdentity, workspaceID: UUID) async throws -> IsgWorkspaceContext {
        try require(identity)
        let data = try await rpc("isg_workspace_context_v1", ["p_workspace": .id(workspaceID)])
        try require(identity)
        guard data.count <= 32_768 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let context = try JSONDecoder().decode(IsgWorkspaceContext.self, from: data)
        guard context.workspaceID == workspaceID, context.membership.userID == identity.userID, context.canRead else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        return context
    }

    func createWorkspace(identity: NovaSessionIdentity, mutationID: UUID,
                         name: String, timezone: String) async throws -> IsgWorkspaceContext {
        try require(identity)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTimezone = timezone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.utf8.count <= 200,
              !cleanTimezone.isEmpty, cleanTimezone.utf8.count <= 80 else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        let data = try await rpc("isg_osgb_workspace_create_v1", [
            "p_mutation": .id(mutationID), "p_name": .string(cleanName),
            "p_timezone": .string(cleanTimezone)
        ])
        try require(identity)
        guard data.count <= 32_768 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let context = try JSONDecoder().decode(IsgWorkspaceContext.self, from: data)
        guard context.membership.userID == identity.userID, context.kind == "osgb", context.canRead else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        return context
    }

    func acceptInvitation(identity: NovaSessionIdentity, mutationID: UUID,
                          token: String) async throws -> IsgWorkspaceContext {
        try require(identity)
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard clean.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        let data = try await rpc("isg_workspace_invitation_accept_v1", [
            "p_mutation": .id(mutationID), "p_token": .string(clean)
        ])
        try require(identity)
        guard data.count <= 32_768 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let context = try JSONDecoder().decode(IsgWorkspaceContext.self, from: data)
        guard context.membership.userID == identity.userID, context.kind == "osgb", context.canRead else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        return context
    }

    func members(selection: NovaWorkspaceSelection, status: String = "all",
                 after: UUID? = nil, limit: Int = 100) async throws -> IsgWorkspaceMemberPage {
        try require(selection)
        guard ["all", "active", "suspended", "ended"].contains(status), (1...100).contains(limit) else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        let data = try await rpc("isg_workspace_member_list_v1", [
            "p_workspace": .id(selection.workspaceID), "p_status": .string(status),
            "p_after": .id(after), "p_limit": .number(limit)
        ])
        try require(selection)
        guard data.count <= 262_144 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let page = try JSONDecoder().decode(MemberPageDTO.self, from: data)
        guard page.schemaVersion == 1, page.workspaceID == selection.workspaceID,
              page.rows.count <= limit else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let rows = try page.rows.map { try $0.value() }
        let ids = rows.map { $0.id.uuidString.lowercased() }
        guard Set(ids).count == ids.count, ids == ids.sorted(),
              after == nil || ids.allSatisfy({ $0 > after!.uuidString.lowercased() }),
              page.next == nil || page.next == rows.last?.id else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        return .init(rows: rows, next: page.next)
    }

    func invitations(selection: NovaWorkspaceSelection, status: String = "all",
                     after: UUID? = nil, limit: Int = 100) async throws -> IsgWorkspaceInvitationPage {
        try require(selection)
        guard ["all", "pending", "accepted", "revoked", "expired"].contains(status),
              (1...100).contains(limit) else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let data = try await rpc("isg_workspace_invitation_list_v1", [
            "p_workspace": .id(selection.workspaceID), "p_status": .string(status),
            "p_after": .id(after), "p_limit": .number(limit)
        ])
        try require(selection)
        guard data.count <= 262_144 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let page = try JSONDecoder().decode(InvitationPageDTO.self, from: data)
        guard page.schemaVersion == 1, page.workspaceID == selection.workspaceID,
              page.rows.count <= limit else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let rows = try page.rows.map { try $0.value() }
        let ids = rows.map { $0.id.uuidString.lowercased() }
        guard Set(ids).count == ids.count, ids == ids.sorted(),
              after == nil || ids.allSatisfy({ $0 > after!.uuidString.lowercased() }),
              page.next == nil || page.next == rows.last?.id else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        return .init(rows: rows, next: page.next)
    }

    func invite(selection: NovaWorkspaceSelection, mutationID: UUID, email: String,
                role: String, expiresAt: String) async throws -> IsgWorkspaceInvitationToken {
        try require(selection)
        let clean = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard clean.range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", options: .regularExpression) != nil,
              ["admin", "expert"].contains(role), !expiresAt.isEmpty else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        let data = try await rpc("isg_workspace_invite_v1", [
            "p_mutation": .id(mutationID), "p_workspace": .id(selection.workspaceID),
            "p_email": .string(clean), "p_role": .string(role), "p_expires_at": .string(expiresAt)
        ])
        try require(selection)
        return try decodeInvitationToken(data, selection: selection, expectedInvitationID: nil)
    }

    func resendInvitation(selection: NovaWorkspaceSelection, mutationID: UUID,
                          invitationID: UUID, expectedVersion: Int64,
                          expiresAt: String) async throws -> IsgWorkspaceInvitationToken {
        try require(selection)
        guard expectedVersion >= 0, !expiresAt.isEmpty else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let data = try await rpc("isg_workspace_invitation_resend_v1", [
            "p_mutation": .id(mutationID), "p_workspace": .id(selection.workspaceID),
            "p_invitation": .id(invitationID), "p_expected": .number(Int(expectedVersion)),
            "p_expires_at": .string(expiresAt)
        ])
        try require(selection)
        return try decodeInvitationToken(data, selection: selection, expectedInvitationID: invitationID)
    }

    func revokeInvitation(selection: NovaWorkspaceSelection, mutationID: UUID,
                          invitationID: UUID, expectedVersion: Int64) async throws {
        try require(selection)
        guard expectedVersion >= 0 else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let data = try await rpc("isg_workspace_invitation_mutate_v1", [
            "p_mutation": .id(mutationID), "p_workspace": .id(selection.workspaceID),
            "p_invitation": .id(invitationID), "p_expected_version": .number(Int(expectedVersion)),
            "p_action": .string("revoke")
        ])
        try require(selection)
        guard data.count <= 32_768 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let response = try JSONDecoder().decode(InvitationMutationDTO.self, from: data)
        guard response.schemaVersion == 1, response.workspaceID == selection.workspaceID,
              response.invitationID == invitationID, response.status == "revoked",
              response.version > expectedVersion else { throw IsgWorkspaceAPIFailure.invalidResponse }
    }

    func mutateMember(selection: NovaWorkspaceSelection, mutationID: UUID,
                      membershipID: UUID, expectedVersion: Int64, action: String,
                      value: String? = nil, reason: String? = nil) async throws -> IsgWorkspaceMember {
        try require(selection)
        guard expectedVersion >= 0,
              ["suspend", "reactivate", "end", "change_role", "set_practicing", "transfer_owner"].contains(action),
              reason.map({ $0.utf8.count <= 500 }) ?? true else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let data = try await rpc("isg_workspace_member_mutate_v1", [
            "p_mutation": .id(mutationID), "p_workspace": .id(selection.workspaceID),
            "p_membership": .id(membershipID), "p_expected_version": .number(Int(expectedVersion)),
            "p_action": .string(action), "p_value": value.map(IsgWorkspaceRPCValue.string) ?? .null,
            "p_reason": reason.map(IsgWorkspaceRPCValue.string) ?? .null
        ])
        try require(selection)
        guard data.count <= 32_768 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let response = try JSONDecoder().decode(MemberMutationDTO.self, from: data)
        guard response.schemaVersion == 1, response.workspaceID == selection.workspaceID,
              response.membership.membershipID == membershipID else { throw IsgWorkspaceAPIFailure.invalidResponse }
        return try response.membership.value()
    }

    func companies(selection: NovaWorkspaceSelection, after: UUID? = nil, limit: Int = 50) async throws -> [IsgWorkspaceCompany] {
        try require(selection)
        guard (1...100).contains(limit) else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let data = try await rpc("isg_workspace_company_list_v1", [
            "p_workspace": .id(selection.workspaceID), "p_after": .id(after), "p_limit": .number(limit)
        ])
        try require(selection)
        guard data.count <= 262_144 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let response = try JSONDecoder().decode(CompanyPage.self, from: data)
        guard response.schemaVersion == 1, response.workspaceID == selection.workspaceID,
              response.rows.count <= limit else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let companies = try response.rows.map { try $0.value() }
        let ids = companies.map { $0.id.uuidString.lowercased() }
        guard Set(ids).count == ids.count, ids == ids.sorted(),
              after == nil || ids.allSatisfy({ $0 > after!.uuidString.lowercased() }),
              response.next == nil || response.next == companies.last?.id else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        return companies
    }

    func assignments(selection: NovaWorkspaceSelection, companyID: UUID, status: String = "all",
                     after: UUID? = nil, limit: Int = 100) async throws
        -> IsgWorkspaceCompanyAssignmentPage {
        try require(selection)
        guard ["all", "current", "ended", "future"].contains(status), (1...100).contains(limit) else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        let data = try await rpc("isg_workspace_assignment_list_v1", [
            "p_workspace": .id(selection.workspaceID), "p_company": .id(companyID),
            "p_status": .string(status), "p_after": .id(after), "p_limit": .number(limit)
        ])
        try require(selection)
        guard data.count <= 262_144 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let response = try JSONDecoder().decode(AssignmentPageDTO.self, from: data)
        guard response.schemaVersion == 1, response.workspaceID == selection.workspaceID,
              response.companyID == companyID, response.rows.count <= limit else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        let rows = try response.rows.map {
            try $0.value(workspaceID: selection.workspaceID, companyID: companyID)
        }
        let ids = rows.map { $0.id.uuidString.lowercased() }
        guard Set(ids).count == ids.count, ids == ids.sorted(),
              after == nil || ids.allSatisfy({ $0 > after!.uuidString.lowercased() }),
              response.next == nil || response.next == rows.last?.id else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        return .init(rows: rows, next: response.next)
    }

    func mutateAssignment(selection: NovaWorkspaceSelection, mutationID: UUID, companyID: UUID,
                          action: String, assignmentID: UUID?, membershipID: UUID?,
                          expectedVersion: Int64, role: String?, startsAt: String?,
                          endsAt: String?, reason: String) async throws -> IsgWorkspaceCompanyAssignment {
        try require(selection, operate: true)
        let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["create", "end"].contains(action), expectedVersion >= 0,
              !cleanReason.isEmpty, cleanReason.utf8.count <= 500,
              (action == "create" && assignmentID == nil && membershipID != nil && expectedVersion == 0 &&
                ["primary", "support"].contains(role ?? "") && Self.validInstant(startsAt) &&
                (endsAt == nil || Self.validInstant(endsAt))) ||
              (action == "end" && assignmentID != nil && membershipID == nil && endsAt != nil &&
                Self.validInstant(endsAt)) else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let data = try await rpc("isg_workspace_assignment_mutate_v1", [
            "p_mutation": .id(mutationID), "p_workspace": .id(selection.workspaceID),
            "p_company": .id(companyID), "p_assignment": .id(assignmentID),
            "p_membership": .id(membershipID), "p_expected": .number(Int(expectedVersion)),
            "p_action": .string(action), "p_role": role.map(IsgWorkspaceRPCValue.string) ?? .null,
            "p_starts_at": startsAt.map(IsgWorkspaceRPCValue.string) ?? .null,
            "p_ends_at": endsAt.map(IsgWorkspaceRPCValue.string) ?? .null,
            "p_reason": .string(cleanReason)
        ])
        try require(selection, operate: true)
        guard data.count <= 32_768 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let result = try JSONDecoder().decode(AssignmentDTO.self, from: data)
            .value(workspaceID: selection.workspaceID, companyID: companyID)
        guard (action == "create" && result.membershipID == membershipID &&
                 result.assignmentRole == role && result.version == 0) ||
              (action == "end" && result.id == assignmentID && result.endsAt != nil &&
                 expectedVersion < Int64.max && result.version == expectedVersion + 1) else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        return result
    }

    func createCompany(selection: NovaWorkspaceSelection, mutationID: UUID, profileMutationID: UUID,
                       draft: IsgWorkspaceCompanyDraft) async throws -> IsgWorkspaceCompany {
        try require(selection, operate: true)
        let clean = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.utf8.count <= 200,
              ["low", "medium", "high"].contains(draft.hazardClass) else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        let data = try await rpc("isg_workspace_company_create_v1", [
            "p_mutation": .id(mutationID), "p_workspace": .id(selection.workspaceID),
            "p_name": .string(clean), "p_hazard": .string(draft.hazardClass)
        ])
        try require(selection, operate: true)
        let company = try decodeCompanyMutation(data, selection: selection, expectedCompanyID: nil)
        let profile = try await mutateCompanyProfile(selection: selection, mutationID: profileMutationID,
            companyID: company.id, expectedVersion: 0, draft: draft)
        return company.applying(profile)
    }

    func updateCompany(selection: NovaWorkspaceSelection, mutationID: UUID, profileMutationID: UUID,
                       companyID: UUID, expectedVersion: Int64, expectedProfileVersion: Int64,
                       draft: IsgWorkspaceCompanyDraft) async throws -> IsgWorkspaceCompany {
        try require(selection, operate: true)
        let clean = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expectedVersion >= 0, !clean.isEmpty, clean.utf8.count <= 200,
              ["low", "medium", "high"].contains(draft.hazardClass) else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        let data = try await rpc("isg_workspace_company_update_v1", [
            "p_mutation": .id(mutationID), "p_workspace": .id(selection.workspaceID),
            "p_company": .id(companyID), "p_expected": .number(Int(expectedVersion)),
            "p_name": .string(clean), "p_hazard": .string(draft.hazardClass)
        ])
        try require(selection, operate: true)
        let company = try decodeCompanyMutation(data, selection: selection, expectedCompanyID: companyID)
        let profile = try await mutateCompanyProfile(selection: selection, mutationID: profileMutationID,
            companyID: company.id, expectedVersion: expectedProfileVersion, draft: draft)
        return company.applying(profile)
    }

    private func mutateCompanyProfile(selection: NovaWorkspaceSelection, mutationID: UUID,
                                      companyID: UUID, expectedVersion: Int64,
                                      draft: IsgWorkspaceCompanyDraft) async throws -> IsgWorkspaceCompanyProfile {
        try require(selection, operate: true)
        let sector = draft.sector.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = draft.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = draft.address.trimmingCharacters(in: .whitespacesAndNewlines)
        let responsibleName = draft.responsibleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let responsiblePhone = draft.responsiblePhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let responsibleEmail = draft.responsibleEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let responsibleValues = [responsibleName, responsiblePhone, responsibleEmail]
        guard expectedVersion >= 0, !sector.isEmpty, sector.utf8.count <= 160,
              email.utf8.count <= 320, address.utf8.count <= 1_000,
              responsibleName.utf8.count <= 160, responsiblePhone.utf8.count <= 80,
              responsibleEmail.utf8.count <= 320,
              responsibleValues.allSatisfy({ $0.isEmpty }) || responsibleValues.allSatisfy({ !$0.isEmpty }) else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        let data = try await rpc("isg_workspace_company_profile_mutate_v1", [
            "p_mutation": .id(mutationID), "p_workspace": .id(selection.workspaceID),
            "p_company": .id(companyID), "p_expected": .number(Int(expectedVersion)),
            "p_sector": .string(sector), "p_email": email.isEmpty ? .null : .string(email),
            "p_employee_count": draft.employeeCount.map(IsgWorkspaceRPCValue.number) ?? .null,
            "p_address": address.isEmpty ? .null : .string(address),
            "p_responsible_name": responsibleName.isEmpty ? .null : .string(responsibleName),
            "p_responsible_phone": responsiblePhone.isEmpty ? .null : .string(responsiblePhone),
            "p_responsible_email": responsibleEmail.isEmpty ? .null : .string(responsibleEmail)
        ])
        try require(selection, operate: true)
        guard data.count <= 32_768 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let response = try JSONDecoder().decode(CompanyProfileDTO.self, from: data)
        guard response.schemaVersion == 1, response.workspaceID == selection.workspaceID,
              response.companyID == companyID else { throw IsgWorkspaceAPIFailure.invalidResponse }
        return try response.value()
    }

    func archiveCompany(selection: NovaWorkspaceSelection, mutationID: UUID,
                        companyID: UUID, expectedVersion: Int64, reason: String) async throws {
        try require(selection, operate: true)
        let clean = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expectedVersion >= 0, !clean.isEmpty, clean.utf8.count <= 500 else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        let data = try await rpc("isg_workspace_company_archive_v1", [
            "p_mutation": .id(mutationID), "p_workspace": .id(selection.workspaceID),
            "p_company": .id(companyID), "p_expected": .number(Int(expectedVersion)),
            "p_reason": .string(clean)
        ])
        try require(selection, operate: true)
        guard data.count <= 32_768 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let response = try JSONDecoder().decode(CompanyArchiveDTO.self, from: data)
        guard response.schemaVersion == 1, response.workspaceID == selection.workspaceID,
              response.companyID == companyID, response.status == "archived",
              response.version > expectedVersion, response.dataDeleted == false else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
    }

    func personnelMetrics(selection: NovaWorkspaceSelection, companyID: UUID?) async throws -> IsgPersonnelMetrics {
        try require(selection)
        let data = try await rpc("isg_workspace_personnel_metrics_v1", [
            "p_workspace": .id(selection.workspaceID), "p_company": .id(companyID)
        ])
        try require(selection)
        guard data.count <= 32_768 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let response = try JSONDecoder().decode(PersonnelMetricsDTO.self, from: data)
        return try response.value(workspaceID: selection.workspaceID, companyID: companyID)
    }

    func dashboard(selection: NovaWorkspaceSelection, companyID: UUID?) async throws -> IsgWorkspaceDashboard {
        try require(selection)
        let data = try await rpc("isg_workspace_dashboard_v1", [
            "p_workspace": .id(selection.workspaceID), "p_company": .id(companyID)
        ])
        try require(selection)
        guard data.count <= 65_536 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let dto = try JSONDecoder().decode(DashboardDTO.self, from: data)
        return try dto.value(workspaceID: selection.workspaceID, companyID: companyID)
    }

    func search(selection: NovaWorkspaceSelection, companyID: UUID, query: String,
                afterKind: String? = nil, afterID: UUID? = nil, limit: Int = 30) async throws -> IsgWorkspaceSearchPage {
        try require(selection)
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...120).contains(clean.utf8.count), (1...100).contains(limit),
              (afterKind == nil) == (afterID == nil) else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let data = try await rpc("isg_workspace_search_v1", ["p_workspace": .id(selection.workspaceID),
            "p_company": .id(companyID), "p_query": .string(clean),
            "p_after_kind": afterKind.map(IsgWorkspaceRPCValue.string) ?? .null,
            "p_after_id": .id(afterID), "p_limit": .number(limit)])
        try require(selection)
        guard data.count <= 262_144 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let dto = try JSONDecoder().decode(SearchDTO.self, from: data)
        return try dto.value(workspaceID: selection.workspaceID, companyID: companyID, limit: limit)
    }

    func analyses(selection: NovaWorkspaceSelection, companyID: UUID, offset: Int = 0,
                  limit: Int = 30) async throws -> IsgWorkspaceAnalysisPage {
        try require(selection)
        guard (0...100_000).contains(offset), (1...100).contains(limit) else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        let data = try await rpc("isg_workspace_analysis_list_v1", ["p_workspace": .id(selection.workspaceID),
            "p_company": .id(companyID), "p_offset": .number(offset), "p_limit": .number(limit)])
        try require(selection)
        guard data.count <= 262_144 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let dto = try JSONDecoder().decode(AnalysisListDTO.self, from: data)
        return try dto.value(workspaceID: selection.workspaceID, companyID: companyID,
                             expectedOffset: offset, limit: limit)
    }

    func analysis(selection: NovaWorkspaceSelection, companyID: UUID, analysisID: UUID) async throws -> IsgWorkspaceAnalysisResult {
        try require(selection)
        let data = try await rpc("isg_workspace_analysis_read_v1", ["p_workspace": .id(selection.workspaceID),
            "p_company": .id(companyID), "p_analysis": .id(analysisID)])
        try require(selection)
        guard data.count <= 524_288 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let dto = try JSONDecoder().decode(AnalysisDTO.self, from: data)
        return try dto.value(workspaceID: selection.workspaceID, companyID: companyID, analysisID: analysisID)
    }

    func submitPhotoAnalysis(selection: NovaWorkspaceSelection, mutationID: UUID,
                             companyID: UUID, assetID: UUID) async throws -> IsgWorkspacePhotoAnalysisJob {
        try require(selection, operate: true)
        let data = try await rpc("isg_workspace_photo_analysis_submit_v1", [
            "p_workspace": .id(selection.workspaceID), "p_company": .id(companyID),
            "p_idempotency": .id(mutationID), "p_source_asset": .id(assetID)
        ])
        try require(selection, operate: true)
        guard data.count <= 32_768 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let dto = try JSONDecoder().decode(PhotoAnalysisSubmitDTO.self, from: data)
        return try dto.value(workspaceID: selection.workspaceID, companyID: companyID)
    }

    func photoAnalysisJob(selection: NovaWorkspaceSelection, companyID: UUID,
                          jobID: UUID) async throws -> IsgWorkspacePhotoAnalysisJob {
        try require(selection)
        let data = try await rpc("isg_workspace_photo_analysis_get_v1", [
            "p_workspace": .id(selection.workspaceID), "p_job": .id(jobID)
        ])
        try require(selection)
        guard data.count <= 32_768 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let dto = try JSONDecoder().decode(PhotoAnalysisJobDTO.self, from: data)
        return try dto.value(workspaceID: selection.workspaceID, companyID: companyID, jobID: jobID)
    }

    func fileAnalysisItem(selection: NovaWorkspaceSelection, mutationID: UUID, companyID: UUID,
                          workplaceID: UUID, sourceScope: String, analysisID: UUID,
                          itemKind: String, itemID: UUID, severity: String?, openedOn: String,
                          dueOn: String?) async throws -> IsgWorkspaceFilingResult {
        try require(selection, operate: true)
        guard ["workspace", "personal"].contains(sourceScope), ["finding", "expert_item"].contains(itemKind),
              severity == nil || ["low", "medium", "high", "critical"].contains(severity!),
              ISO8601Day.isValid(openedOn), dueOn == nil || ISO8601Day.isValid(dueOn!) else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        let data = try await rpc("isg_workspace_analysis_file_v1", ["p_mutation": .id(mutationID),
            "p_workspace": .id(selection.workspaceID), "p_company": .id(companyID),
            "p_workplace": .id(workplaceID), "p_source_scope": .string(sourceScope),
            "p_analysis": .id(analysisID), "p_item_kind": .string(itemKind), "p_item": .id(itemID),
            "p_severity": severity.map(IsgWorkspaceRPCValue.string) ?? .null,
            "p_opened_on": .string(openedOn), "p_due_on": dueOn.map(IsgWorkspaceRPCValue.string) ?? .null])
        try require(selection, operate: true)
        guard data.count <= 65_536 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let dto = try JSONDecoder().decode(FilingDTO.self, from: data)
        guard dto.schemaVersion == 1, dto.workspaceID == selection.workspaceID, dto.companyID == companyID,
              dto.commitState == "committed_and_visible",
              ["analysis_finding_filed", "analysis_finding_already_filed"].contains(dto.successMessageKey) else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        return .init(nonconformityID: dto.nonconformityID, created: dto.created, successMessageKey: dto.successMessageKey)
    }

    func createExport(selection: NovaWorkspaceSelection, mutationID: UUID, companyID: UUID,
                      analysisID: UUID, format: String, findingIDs: [UUID], expertItemIDs: [UUID],
                      trainingItemIDs: [UUID]) async throws -> IsgWorkspaceExportResult {
        try require(selection, operate: true)
        guard ["pdf", "xlsx"].contains(format) else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let selectionValue: IsgWorkspaceRPCValue = .object([
            "finding_ids": .array(findingIDs.map { .id($0) }),
            "expert_item_ids": .array(expertItemIDs.map { .id($0) }),
            "training_item_ids": .array(trainingItemIDs.map { .id($0) })])
        let data = try await rpc("isg_workspace_export_create_v1", ["p_mutation": .id(mutationID),
            "p_workspace": .id(selection.workspaceID), "p_company": .id(companyID),
            "p_analysis": .id(analysisID), "p_format": .string(format), "p_selection": selectionValue])
        try require(selection, operate: true)
        return try decodeExport(data, selection: selection, companyID: companyID)
    }

    func export(selection: NovaWorkspaceSelection, companyID: UUID, jobID: UUID) async throws -> IsgWorkspaceExportResult {
        try require(selection)
        let data = try await rpc("isg_workspace_export_get_v1", ["p_workspace": .id(selection.workspaceID),
            "p_company": .id(companyID), "p_job": .id(jobID)])
        try require(selection)
        let result = try decodeExport(data, selection: selection, companyID: companyID)
        guard result.id == jobID else { throw IsgWorkspaceAPIFailure.invalidResponse }
        return result
    }

    func changes(selection: NovaWorkspaceSelection, companyID: UUID?, after: Int64 = 0,
                 limit: Int = 100) async throws -> IsgWorkspaceChangePage {
        try require(selection)
        guard after >= 0, (1...200).contains(limit) else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        let data = try await rpc("isg_workspace_change_read_v1", ["p_workspace": .id(selection.workspaceID),
            "p_company": .id(companyID), "p_after": .number(Int(after)), "p_limit": .number(limit)])
        try require(selection)
        guard data.count <= 262_144 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let dto = try JSONDecoder().decode(ChangeDTO.self, from: data)
        guard dto.schemaVersion == 1, dto.workspaceID == selection.workspaceID, dto.companyID == companyID,
              dto.rows.count <= limit, dto.next >= after, dto.rows.allSatisfy({ $0.sequence > after && $0.sequence <= dto.next }) else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        return .init(rows: dto.rows, next: dto.next)
    }

    /// Reads one D1-D7 operational domain without crossing into the legacy
    /// personal endpoints. The server remains the authority for assignment,
    /// feature and record visibility; this adapter additionally pins the
    /// response envelope to the active workspace and company.
    func domain(selection: NovaWorkspaceSelection, companyID: UUID,
                domain: IsgWorkspaceDomain, limit: Int = 100) async throws -> IsgWorkspaceDomainSnapshot {
        try require(selection)
        guard (1...100).contains(limit) else { throw IsgWorkspaceAPIFailure.invalidRequest }
        var after: UUID?
        var rows: [IsgWorkspaceDomainRecord] = []
        var seen = Set<UUID>()
        for pageIndex in 0..<100 {
            let request = domainReadRequest(selection: selection, companyID: companyID,
                                            domain: domain, after: after, limit: limit)
            let data = try await rpc(request.function, request.arguments)
            try require(selection)
            guard data.count <= 1_048_576 else { throw IsgWorkspaceAPIFailure.invalidResponse }
            let page = try decodeDomainPage(data, workspaceID: selection.workspaceID,
                                            companyID: companyID, domain: domain, limit: limit)
            guard page.rows.allSatisfy({ seen.insert($0.id).inserted }) else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
            rows.append(contentsOf: page.rows)
            guard let next = page.next else { break }
            guard next != after, page.rows.last?.id == next, pageIndex < 99 else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
            after = next
        }
        let metricsData: Data?
        if let metrics = domainMetricRequest(selection: selection, companyID: companyID, domain: domain) {
            metricsData = try await rpc(metrics.function, metrics.arguments)
        } else {
            metricsData = nil
        }
        try require(selection)
        guard (metricsData?.count ?? 0) <= 262_144 else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        let metrics = try metricsData.map {
            try decodeDomainMetrics($0, workspaceID: selection.workspaceID, companyID: companyID)
        } ?? []
        return .init(domain: domain, companyID: companyID, rows: rows, metrics: metrics)
    }

    /// Fetches the authoritative detail shape for a selected list row. Some
    /// domains intentionally omit heavy history arrays from their board read.
    func domainDetail(selection: NovaWorkspaceSelection, companyID: UUID,
                      domain: IsgWorkspaceDomain, id: UUID) async throws -> IsgWorkspaceDomainRecord {
        try require(selection)
        var request = domainReadRequest(selection: selection, companyID: companyID,
                                        domain: domain, after: nil, limit: 1)
        request.arguments["p_id"] = .id(id)
        request.arguments["p_after"] = .null
        request.arguments["p_limit"] = .number(1)
        if domain == .equipment { request.arguments["p_kind"] = .string("detail") }
        let data = try await rpc(request.function, request.arguments)
        try require(selection)
        guard data.count <= 1_048_576 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let page = try decodeDomainPage(data, workspaceID: selection.workspaceID,
                                        companyID: companyID, domain: domain, limit: 1)
        guard page.next == nil, page.rows.count == 1, page.rows[0].id == id else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        return page.rows[0]
    }

    func checklistTemplates(selection: NovaWorkspaceSelection, companyID: UUID) async throws
        -> [IsgWorkspaceChecklistTemplate] {
        try require(selection)
        let data = try await rpc("isg_workspace_checklist_read_v1", [
            "p_workspace": .id(selection.workspaceID), "p_company": .id(companyID),
            "p_id": .null, "p_after": .null, "p_limit": .number(1)
        ])
        try require(selection)
        guard data.count <= 262_144 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let response = try JSONDecoder().decode(ChecklistTemplateEnvelope.self, from: data)
        guard response.schemaVersion == 1, response.workspaceID == selection.workspaceID,
              response.companyID == companyID, response.templates.count <= 500,
              Set(response.templates.map(\.id)).count == response.templates.count,
              response.templates.allSatisfy({ !$0.code.isEmpty && !$0.title.isEmpty &&
                  (1...1000).contains($0.version) && (1...500).contains($0.itemCount) }) else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        return response.templates.map {
            .init(code: $0.code, version: $0.version, title: $0.title, itemCount: $0.itemCount)
        }
    }

    func equipmentCatalog(selection: NovaWorkspaceSelection, companyID: UUID) async throws
        -> IsgWorkspaceEquipmentCatalog {
        try require(selection)
        let data = try await rpc("isg_workspace_equipment_read_v1", [
            "p_workspace": .id(selection.workspaceID), "p_company": .id(companyID),
            "p_kind": .string("catalog"), "p_id": .null, "p_query": .string(""),
            "p_state": .null, "p_type": .null, "p_after": .null, "p_limit": .number(100)
        ])
        try require(selection)
        guard data.count <= 262_144,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["schema_version"] as? NSNumber)?.intValue == 1,
              root["workspace_id"] as? String == selection.workspaceID.uuidString.lowercased(),
              root["company_id"] as? String == companyID.uuidString.lowercased(),
              let rawSuggestions = root["suggestions"] as? [[String: Any]],
              let rawRules = root["rules"] as? [[String: Any]],
              rawSuggestions.count <= 100, rawRules.count <= 100 else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        let suggestions: [IsgWorkspaceEquipmentCatalog.Suggestion] = try rawSuggestions.map { row in
            guard let code = row["code"] as? String, !code.isEmpty,
                  let ordinal = (row["ordinal"] as? NSNumber)?.intValue,
                  ordinal > 0 else { throw IsgWorkspaceAPIFailure.invalidResponse }
            let months = (row["default_period_months"] as? NSNumber)?.intValue
            let note = row["default_basis_note"] as? String
            return .init(code: code, ordinal: ordinal, defaultPeriodMonths: months, defaultBasisNote: note)
        }.sorted { $0.ordinal < $1.ordinal }
        let rules: [IsgWorkspaceEquipmentCatalog.Rule] = try rawRules.map { row in
            guard let type = row["equipment_type"] as? String, !type.isEmpty,
                  let months = (row["period_months"] as? NSNumber)?.intValue,
                  let source = row["period_source"] as? String,
                  let needsReview = row["needs_review"] as? Bool,
                  let version = (row["version"] as? NSNumber)?.int64Value,
                  (1...240).contains(months) else { throw IsgWorkspaceAPIFailure.invalidResponse }
            return .init(equipmentType: type, periodMonths: months, periodSource: source,
                         needsReview: needsReview, exceptionNote: row["exception_note"] as? String,
                         version: version)
        }
        guard Set(suggestions.map(\.code)).count == suggestions.count,
              Set(rules.map(\.equipmentType)).count == rules.count else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        return .init(suggestions: suggestions, rules: rules)
    }

    func initializePersonnel(selection: NovaWorkspaceSelection, companyID: UUID) async throws {
        try require(selection, operate: true)
        let data = try await rpc("isg_workspace_personnel_initialize_v1", [
            "p_workspace": .id(selection.workspaceID), "p_company": .id(companyID)
        ])
        try require(selection, operate: true)
        guard data.count <= 32_768,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              try validScope(root, workspaceID: selection.workspaceID, companyID: companyID),
              root["workplace_id"] as? String != nil else { throw IsgWorkspaceAPIFailure.invalidResponse }
    }

    func directory(selection: NovaWorkspaceSelection, companyID: UUID,
                   kind: IsgWorkspaceDirectoryKind, includeArchived: Bool = false) async throws
        -> [IsgWorkspaceDirectoryEntry] {
        try require(selection)
        var rows: [IsgWorkspaceDirectoryEntry] = []
        var cursor: UUID?
        var pageCount = 0
        repeat {
            pageCount += 1
            guard pageCount <= 100 else { throw IsgWorkspaceAPIFailure.invalidResponse }
            let data = try await rpc("isg_workspace_personnel_read_v1", [
                "p_workspace": .id(selection.workspaceID), "p_company": .id(companyID),
                "p_kind": .string(kind == .workplace ? "workplaces" : "departments"),
                "p_query": .string(""), "p_archived": .bool(includeArchived),
                "p_after": .id(cursor), "p_id": .null, "p_limit": .number(100)
            ])
            try require(selection)
            guard data.count <= 262_144 else { throw IsgWorkspaceAPIFailure.invalidResponse }
            let response = try JSONDecoder().decode(DirectoryPageDTO.self, from: data)
            guard response.schemaVersion == 1, response.workspaceID == selection.workspaceID,
                  response.companyID == companyID, response.rows.count <= 100 else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
            let page = try response.rows.map { try $0.value(kind: kind) }
            try validatePersonnelPage(page.map(\.id), after: cursor, next: response.next)
            rows.append(contentsOf: page)
            cursor = response.next
        } while cursor != nil
        return rows
    }

    func employees(selection: NovaWorkspaceSelection, companyID: UUID,
                   includeArchived: Bool = false) async throws -> [IsgWorkspaceEmployeeEntry] {
        try require(selection)
        var rows: [IsgWorkspaceEmployeeEntry] = []
        var cursor: UUID?
        var pageCount = 0
        repeat {
            pageCount += 1
            guard pageCount <= 100 else { throw IsgWorkspaceAPIFailure.invalidResponse }
            let data = try await rpc("isg_workspace_personnel_read_v1", [
                "p_workspace": .id(selection.workspaceID), "p_company": .id(companyID),
                "p_kind": .string("employees"), "p_query": .string(""),
                "p_archived": .bool(includeArchived), "p_after": .id(cursor), "p_id": .null,
                "p_limit": .number(100)
            ])
            try require(selection)
            guard data.count <= 262_144 else { throw IsgWorkspaceAPIFailure.invalidResponse }
            let response = try JSONDecoder().decode(EmployeePageDTO.self, from: data)
            guard response.schemaVersion == 1, response.workspaceID == selection.workspaceID,
                  response.companyID == companyID, response.rows.count <= 100 else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
            let page = try response.rows.map { try $0.value() }
            try validatePersonnelPage(page.map(\.id), after: cursor, next: response.next)
            rows.append(contentsOf: page)
            cursor = response.next
        } while cursor != nil
        return rows
    }

    func personnelAdvanced(selection: NovaWorkspaceSelection, companyID: UUID,
                           kind: IsgWorkspacePersonnelAdvancedKind) async throws
        -> [IsgWorkspaceAdvancedRecord] {
        try await advancedRows(selection: selection, companyID: companyID,
            function: "isg_workspace_personnel_advanced_read_v1", kind: kind.rawValue)
    }

    func trainingAdvanced(selection: NovaWorkspaceSelection, companyID: UUID,
                          kind: IsgWorkspaceTrainingAdvancedKind) async throws
        -> [IsgWorkspaceAdvancedRecord] {
        try await advancedRows(selection: selection, companyID: companyID,
            function: "isg_workspace_training_advanced_read_v1", kind: kind.rawValue)
    }

    func mutatePersonnelAdvanced(selection: NovaWorkspaceSelection, mutationID: UUID,
                                 companyID: UUID, payload: [String: IsgWorkspaceRPCValue]) async throws {
        try await mutateAdvanced(selection: selection, mutationID: mutationID, companyID: companyID,
            function: "isg_workspace_personnel_advanced_mutate_v1", payload: payload)
    }

    func mutateTrainingAdvanced(selection: NovaWorkspaceSelection, mutationID: UUID,
                                companyID: UUID, payload: [String: IsgWorkspaceRPCValue]) async throws {
        try await mutateAdvanced(selection: selection, mutationID: mutationID, companyID: companyID,
            function: "isg_workspace_training_advanced_mutate_v1", payload: payload)
    }

    func mutateDirectory(selection: NovaWorkspaceSelection, mutationID: UUID, companyID: UUID,
                         kind: IsgWorkspaceDirectoryKind, action: String,
                         entryID: UUID?, expectedVersion: Int64, workplaceID: UUID?,
                         code: String?, name: String?) async throws {
        try require(selection, operate: true)
        guard ["create", "edit", "archive"].contains(action), expectedVersion >= 0,
              (action == "create") == (entryID == nil),
              action == "archive" || validDirectoryText(code, name) else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        let data = try await rpc("isg_workspace_directory_mutate_v1", [
            "p_mutation": .id(mutationID), "p_workspace": .id(selection.workspaceID),
            "p_company": .id(companyID), "p_entity": .string(kind.rawValue),
            "p_action": .string(action), "p_id": .id(entryID),
            "p_expected": .number(Int(expectedVersion)), "p_workplace": .id(workplaceID),
            "p_code": code.map(IsgWorkspaceRPCValue.string) ?? .null,
            "p_name": name.map(IsgWorkspaceRPCValue.string) ?? .null
        ])
        try require(selection, operate: true)
        try validateMutationEnvelope(data, selection: selection, companyID: companyID,
                                     expectedAction: action)
    }

    func mutateEmployee(selection: NovaWorkspaceSelection, mutationID: UUID, companyID: UUID,
                        action: String, employeeID: UUID?, expectedVersion: Int64,
                        code: String?, name: String?, departmentID: UUID?,
                        hiredOn: String?, endsBefore: String?) async throws -> IsgWorkspaceEmployeeEntry? {
        try require(selection, operate: true)
        guard ["create", "edit", "archive"].contains(action), expectedVersion >= 0,
              (action == "create") == (employeeID == nil),
              action == "archive" || validDirectoryText(code, name),
              hiredOn.map(ISO8601Day.isValid) ?? true, endsBefore.map(ISO8601Day.isValid) ?? true,
              hiredOn == nil || endsBefore == nil || hiredOn! < endsBefore! else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        let data = try await rpc("isg_workspace_employee_mutate_v1", [
            "p_mutation": .id(mutationID), "p_workspace": .id(selection.workspaceID),
            "p_company": .id(companyID), "p_action": .string(action),
            "p_employee": .id(employeeID), "p_expected": .number(Int(expectedVersion)),
            "p_code": code.map(IsgWorkspaceRPCValue.string) ?? .null,
            "p_name": name.map(IsgWorkspaceRPCValue.string) ?? .null,
            "p_department": .id(departmentID),
            "p_hired_on": hiredOn.map(IsgWorkspaceRPCValue.string) ?? .null,
            "p_ends_before": endsBefore.map(IsgWorkspaceRPCValue.string) ?? .null
        ])
        try require(selection, operate: true)
        guard data.count <= 32_768,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              try validScope(root, workspaceID: selection.workspaceID, companyID: companyID),
              root["action"] == nil || root["action"] as? String == action else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        guard action != "archive" else { return nil }
        return try EmployeeDTO(json: root).value()
    }

    /// Reviewed D2-D6 commands share one transport boundary. Domain-specific
    /// fields are built by the form, but workspace/company scope is pinned and
    /// checked again after the network call.
    func mutateDomain(selection: NovaWorkspaceSelection, mutationID: UUID, companyID: UUID,
                      domain: IsgWorkspaceDomain,
                      payload: [String: IsgWorkspaceRPCValue]) async throws -> IsgWorkspaceMutationResult {
        try require(selection, operate: true)
        guard !payload.isEmpty, let function = mutationFunction(domain),
              case .string(let action)? = payload["action"], !action.isEmpty,
              (try? JSONEncoder().encode(IsgWorkspaceRPCValue.object(payload)).count).map({ $0 <= 65_536 }) == true else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        let data = try await rpc(function, [
            "p_mutation": .id(mutationID), "p_workspace": .id(selection.workspaceID),
            "p_company": .id(companyID), "p_payload": .object(payload)
        ])
        try require(selection, operate: true)
        guard data.count <= 262_144,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              try validScope(root, workspaceID: selection.workspaceID, companyID: companyID) else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        let record = (root["row"] as? [String: Any]) ?? root
        let idKeys = ["id", "meeting_id", "plan_id", "appointment_id", "assessment_id",
                      "training_id", "nonconformity_id", "run_id", "drill_id", "handover_id",
                      "equipment_id", "contract_id", "permit_id", "visit_id", "entry_id"]
        let recordID = idKeys.compactMap { record[$0] as? String }.compactMap(UUID.init(uuidString:)).first
        let version = (record["version"] as? NSNumber)?.int64Value
        return .init(domain: domain, companyID: companyID, recordID: recordID, version: version)
    }

    /// Opens a server-scoped upload intent, writes only to its exact private
    /// object path, then asks the byte-inspection worker to finalize the asset.
    /// A file entry is created only after the worker has accepted those bytes.
    func uploadFile(selection: NovaWorkspaceSelection, mutationID: UUID, companyID: UUID,
                    title: String, filename: String, category: String,
                    data: Data) async throws -> IsgWorkspaceFileUploadResult {
        try require(selection, operate: true)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileExtension = URL(fileURLWithPath: cleanFilename).pathExtension.lowercased()
        let allowedExtensions = Set(["pdf", "doc", "docx", "xls", "xlsx", "csv",
                                     "jpg", "jpeg", "png", "webp", "avif", "heic", "heif"])
        let allowedCategories = Set(["company_logo", "risk_assessment", "emergency_plan",
                                     "training_material", "inspection_report", "measurement_report",
                                     "accident_record", "board_document", "handover_form",
                                     "personnel_document", "contract", "permit_form", "visit_evidence",
                                     "notebook_archive", "other"])
        guard !cleanTitle.isEmpty, cleanTitle.utf8.count <= 320,
              !cleanFilename.isEmpty, cleanFilename.utf8.count <= 400,
              allowedExtensions.contains(fileExtension), allowedCategories.contains(category),
              (1...52_428_800).contains(data.count) else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        let receiptData = try await rpc("isg_workspace_file_create_receipt_v1", [
            "p_workspace": .id(selection.workspaceID), "p_company": .id(companyID),
            "p_mutation": .id(mutationID)
        ])
        try require(selection, operate: true)
        guard receiptData.count <= 16_384 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let receipt = try JSONDecoder().decode(FileCreateReceiptDTO.self, from: receiptData)
        guard receipt.schemaVersion == 1, receipt.workspaceID == selection.workspaceID,
              receipt.companyID == companyID else { throw IsgWorkspaceAPIFailure.invalidResponse }
        if receipt.found {
            guard let entryID = receipt.entryID, let assetID = receipt.assetID,
                  receipt.byteSize == Int64(data.count) else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
            return .init(entryID: entryID, assetID: assetID,
                         companyID: companyID, byteSize: Int64(data.count))
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let expiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(600))
        let uploadAttemptID = UUID()
        let openedData = try await rpc("isg_workspace_upload_open_v1", [
            "p_workspace": .id(selection.workspaceID), "p_company": .id(companyID),
            "p_idempotency": .id(uploadAttemptID), "p_request_hash": .string("\\x" + digest),
            "p_purpose": .string("workspace_file"),
            "p_media_type": .string(Self.mediaType(for: fileExtension)),
            "p_extension": .string(fileExtension), "p_expected_bytes": .number(data.count),
            "p_expires_at": .string(expiresAt)
        ])
        try require(selection, operate: true)
        guard openedData.count <= 32_768 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let opened = try JSONDecoder().decode(FileUploadOpenDTO.self, from: openedData)
        guard opened.schemaVersion == 1, opened.workspaceID == selection.workspaceID,
              opened.status == "open", opened.bucket == "isg-workspace-private",
              opened.objectPath.hasPrefix(selection.workspaceID.uuidString.lowercased() + "/"),
              opened.credentialReturned, !opened.replayed,
              let token = opened.uploadToken,
              token.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }

        try await upload(opened.bucket, opened.objectPath, data, Self.mediaType(for: fileExtension))
        try require(selection, operate: true)
        let finalizedData = try await finalizeUpload(token)
        try require(selection, operate: true)
        guard finalizedData.count <= 32_768 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let finalized = try JSONDecoder().decode(FileUploadFinalizedDTO.self, from: finalizedData)
        guard finalized.schemaVersion == 1, finalized.workspaceID == selection.workspaceID,
              finalized.byteSize == Int64(data.count) else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let assetID = finalized.assetID

        let entry = try await mutateDomain(selection: selection, mutationID: mutationID, companyID: companyID,
                                           domain: .files, payload: [
            "action": .string("create"), "asset_id": .id(assetID),
            "category": .string(category), "visibility": .string("company_team"),
            "title": .string(cleanTitle), "original_filename": .string(cleanFilename),
            "note": .string(""), "tags": .array([])
        ])
        guard let entryID = entry.recordID else { throw IsgWorkspaceAPIFailure.invalidResponse }
        return .init(entryID: entryID, assetID: assetID,
                     companyID: companyID, byteSize: Int64(data.count))
    }

    func downloadFile(selection: NovaWorkspaceSelection, companyID: UUID,
                      row: IsgWorkspaceDomainRecord) async throws -> IsgWorkspaceFileDownload {
        try require(selection)
        guard let assetID = row.assetID, let filename = row.originalFilename,
              !filename.isEmpty else { throw IsgWorkspaceAPIFailure.invalidRequest }
        return try await downloadAsset(selection: selection, assetID: assetID, filename: filename)
    }

    func downloadAsset(selection: NovaWorkspaceSelection, assetID: UUID,
                       filename: String) async throws -> IsgWorkspaceFileDownload {
        try require(selection)
        let expiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(120))
        let openedData = try await rpc("isg_workspace_download_open_v1", [
            "p_workspace": .id(selection.workspaceID), "p_asset": .id(assetID),
            "p_purpose": .string("workspace_file_preview"), "p_expires_at": .string(expiresAt)
        ])
        try require(selection)
        guard openedData.count <= 32_768 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let opened = try JSONDecoder().decode(FileDownloadOpenDTO.self, from: openedData)
        guard opened.schemaVersion == 1, opened.workspaceID == selection.workspaceID,
              opened.downloadToken.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        let bytes = try await download(opened.downloadToken)
        try require(selection)
        guard !bytes.isEmpty, bytes.count <= 52_428_800 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        return .init(filename: filename, data: bytes)
    }

    private static func mediaType(for fileExtension: String) -> String {
        switch fileExtension {
        case "pdf": return "application/pdf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "csv": return "text/csv"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        case "heic", "heif": return "image/heic"
        default: return "application/octet-stream"
        }
    }

    private func validDirectoryText(_ code: String?, _ name: String?) -> Bool {
        guard let code = code?.trimmingCharacters(in: .whitespacesAndNewlines),
              let name = name?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !code.isEmpty && code.utf8.count <= 80 && !name.isEmpty && name.utf8.count <= 200
    }

    private func advancedRows(selection: NovaWorkspaceSelection, companyID: UUID,
                              function: String, kind: String) async throws -> [IsgWorkspaceAdvancedRecord] {
        try require(selection)
        var rows: [IsgWorkspaceAdvancedRecord] = []
        var cursor: UUID?
        var seen = Set<UUID>()
        for pageIndex in 0..<100 {
            let data = try await rpc(function, [
                "p_workspace": .id(selection.workspaceID), "p_company": .id(companyID),
                "p_kind": .string(kind), "p_after": .id(cursor), "p_limit": .number(100)
            ])
            try require(selection)
            guard data.count <= 524_288,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  try validScope(root, workspaceID: selection.workspaceID, companyID: companyID),
                  root["kind"] as? String == kind,
                  let rawRows = root["rows"] as? [[String: Any]], rawRows.count <= 100 else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
            let page = try rawRows.map { try advancedRecord($0) }
            guard page.allSatisfy({ seen.insert($0.id).inserted }) else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
            let next: UUID?
            if root["next"] == nil || root["next"] is NSNull { next = nil }
            else if let raw = root["next"] as? String, let id = UUID(uuidString: raw) { next = id }
            else { throw IsgWorkspaceAPIFailure.invalidResponse }
            guard next == nil || (page.count == 100 && page.last?.id == next && next != cursor && pageIndex < 99) else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
            rows.append(contentsOf: page)
            cursor = next
            if next == nil { break }
        }
        return rows
    }

    private func mutateAdvanced(selection: NovaWorkspaceSelection, mutationID: UUID, companyID: UUID,
                                function: String, payload: [String: IsgWorkspaceRPCValue]) async throws {
        try require(selection, operate: true)
        guard case .string(let action)? = payload["action"], !action.isEmpty,
              (try? JSONEncoder().encode(IsgWorkspaceRPCValue.object(payload)).count).map({ $0 <= 65_536 }) == true else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        let data = try await rpc(function, ["p_mutation": .id(mutationID),
            "p_workspace": .id(selection.workspaceID), "p_company": .id(companyID),
            "p_payload": .object(payload)])
        try require(selection, operate: true)
        guard data.count <= 65_536,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              try validScope(root, workspaceID: selection.workspaceID, companyID: companyID),
              root["action"] as? String == action, root["entity_id"] as? String != nil,
              ((root["version"] as? NSNumber)?.int64Value ?? -1) >= 0 else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
    }

    private func advancedRecord(_ row: [String: Any]) throws -> IsgWorkspaceAdvancedRecord {
        guard let idText = row["id"] as? String, let id = UUID(uuidString: idText),
              let kind = row["kind"] as? String, !kind.isEmpty else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        var fields: [String: String] = [:]
        for (key, value) in row {
            if let text = value as? String { fields[key] = text }
            else if let number = value as? NSNumber {
                fields[key] = CFGetTypeID(number) == CFBooleanGetTypeID() ?
                    (number.boolValue ? "true" : "false") : number.stringValue
            }
        }
        let title = fields["title"] ?? fields["name"] ?? fields["employee_name"] ??
            fields["training_title"] ?? fields["certificate_no"] ?? kind
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        let subtitle = fields["code"] ?? fields["contractor_name"] ?? fields["workplace_name"] ??
            fields["employer_name"] ?? fields["employee_name"]
        let status = fields["state"] ?? fields["verification_state"] ??
            (fields["is_current"] == "true" ? "active" : nil)
        let version = (row["version"] as? NSNumber)?.int64Value ?? 0
        guard version >= 0 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let topics: [IsgWorkspaceAdvancedTopic]
        if let values = row["topics"] as? [[String: Any]] {
            guard values.count <= 999 else { throw IsgWorkspaceAPIFailure.invalidResponse }
            topics = try values.map { value in
                guard let rawID = value["id"] as? String, let topicID = UUID(uuidString: rawID),
                      let position = (value["position"] as? NSNumber)?.intValue, (1...999).contains(position),
                      let topicTitle = value["title"] as? String, !topicTitle.isEmpty,
                      let description = value["description"] as? String,
                      let minutes = (value["duration_minutes"] as? NSNumber)?.intValue,
                      (1...100_000).contains(minutes) else {
                    throw IsgWorkspaceAPIFailure.invalidResponse
                }
                return .init(id: topicID, position: position, title: topicTitle,
                             description: description, durationMinutes: minutes)
            }
            guard Set(topics.map(\.id)).count == topics.count,
                  Set(topics.map(\.position)).count == topics.count else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
        } else { topics = [] }
        return .init(id: id, kind: kind, title: title, subtitle: subtitle,
                     status: status, version: version, fields: fields, topics: topics)
    }

    private static func validInstant(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        let formatter = ISO8601DateFormatter()
        if formatter.date(from: value) != nil { return true }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value) != nil
    }

    private func validScope(_ root: [String: Any], workspaceID: UUID, companyID: UUID) throws -> Bool {
        (root["schema_version"] as? NSNumber)?.intValue == 1 &&
        root["workspace_id"] as? String == workspaceID.uuidString.lowercased() &&
        root["company_id"] as? String == companyID.uuidString.lowercased()
    }

    private func validateMutationEnvelope(_ data: Data, selection: NovaWorkspaceSelection,
                                          companyID: UUID, expectedAction: String) throws {
        guard data.count <= 32_768,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              try validScope(root, workspaceID: selection.workspaceID, companyID: companyID),
              root["action"] as? String == expectedAction,
              root["entity_id"] as? String != nil else { throw IsgWorkspaceAPIFailure.invalidResponse }
    }

    private func domainReadRequest(selection: NovaWorkspaceSelection, companyID: UUID,
                                   domain: IsgWorkspaceDomain, after: UUID?, limit: Int)
        -> (function: String, arguments: [String: IsgWorkspaceRPCValue]) {
        let scope: [String: IsgWorkspaceRPCValue] = [
            "p_workspace": .id(selection.workspaceID), "p_company": .id(companyID)
        ]
        switch domain {
        case .personnel:
            return ("isg_workspace_personnel_read_v1", scope.merging([
                "p_kind": .string("employees"), "p_query": .string(""), "p_archived": .bool(false),
                "p_after": after.map(IsgWorkspaceRPCValue.id) ?? .null, "p_id": .null, "p_limit": .number(limit)
            ]) { _, new in new })
        case .training:
            return ("isg_workspace_training_read_v1", scope.merging([
                "p_id": .null, "p_after": after.map(IsgWorkspaceRPCValue.id) ?? .null, "p_limit": .number(limit)
            ]) { _, new in new })
        case .risk:
            return ("isg_workspace_risk_read_v1", scope.merging([
                "p_id": .null, "p_after": after.map(IsgWorkspaceRPCValue.id) ?? .null, "p_limit": .number(limit)
            ]) { _, new in new })
        case .nonconformity:
            return ("isg_workspace_nonconformity_read_v1", scope.merging([
                "p_id": .null, "p_state": .null, "p_after": after.map(IsgWorkspaceRPCValue.id) ?? .null,
                "p_limit": .number(limit)
            ]) { _, new in new })
        case .checklist:
            return ("isg_workspace_checklist_read_v1", scope.merging([
                "p_id": .null, "p_after": after.map(IsgWorkspaceRPCValue.id) ?? .null, "p_limit": .number(limit)
            ]) { _, new in new })
        case .emergencyPlan, .drill, .appointment, .ppe:
            let kind: String
            switch domain {
            case .emergencyPlan: kind = "plans"
            case .drill: kind = "drills"
            case .appointment: kind = "appointments"
            default: kind = "ppe"
            }
            return ("isg_workspace_safety_read_v1", scope.merging([
                "p_kind": .string(kind), "p_id": .null,
                "p_after": after.map(IsgWorkspaceRPCValue.id) ?? .null, "p_limit": .number(limit)
            ]) { _, new in new })
        case .equipment:
            return ("isg_workspace_equipment_read_v1", scope.merging([
                "p_kind": .string("inventory"), "p_id": .null, "p_query": .string(""),
                "p_state": .null, "p_type": .null, "p_after": after.map(IsgWorkspaceRPCValue.id) ?? .null,
                "p_limit": .number(limit)
            ]) { _, new in new })
        case .katip, .annualPlan, .board, .workPermit, .visit:
            let kind: String
            switch domain {
            case .katip: kind = "katip_contract"
            case .annualPlan: kind = "annual_plan"
            case .board: kind = "board"
            case .workPermit: kind = "work_permit"
            default: kind = "site_visit"
            }
            return ("isg_workspace_operations_read_v1", scope.merging([
                "p_kind": .string(kind), "p_id": .null,
                "p_after": after.map(IsgWorkspaceRPCValue.id) ?? .null, "p_limit": .number(limit)
            ]) { _, new in new })
        case .files:
            return ("isg_workspace_file_read_v1", scope.merging([
                "p_id": .null, "p_query": .string(""), "p_category": .null,
                "p_include_archived": .bool(false),
                "p_after": after.map(IsgWorkspaceRPCValue.id) ?? .null, "p_limit": .number(limit)
            ]) { _, new in new })
        }
    }

    private func domainMetricRequest(selection: NovaWorkspaceSelection, companyID: UUID,
                                     domain: IsgWorkspaceDomain)
        -> (function: String, arguments: [String: IsgWorkspaceRPCValue])? {
        let arguments: [String: IsgWorkspaceRPCValue] = [
            "p_workspace": .id(selection.workspaceID), "p_company": .id(companyID)
        ]
        switch domain {
        case .personnel: return ("isg_workspace_personnel_metrics_v1", arguments)
        case .training: return ("isg_workspace_training_metrics_v1", arguments)
        case .risk, .nonconformity, .checklist:
            return ("isg_workspace_assurance_metrics_v1", arguments)
        case .emergencyPlan, .drill, .appointment, .ppe:
            return ("isg_workspace_safety_metrics_v1", arguments)
        case .equipment: return ("isg_workspace_equipment_metrics_v1", arguments)
        case .katip, .annualPlan, .board, .workPermit, .visit:
            return ("isg_workspace_operations_metrics_v1", arguments)
        case .files: return nil
        }
    }

    private func mutationFunction(_ domain: IsgWorkspaceDomain) -> String? {
        switch domain {
        case .training: return "isg_workspace_training_mutate_v1"
        case .risk: return "isg_workspace_risk_mutate_v1"
        case .nonconformity: return "isg_workspace_nonconformity_mutate_v1"
        case .checklist: return "isg_workspace_checklist_mutate_v1"
        case .emergencyPlan, .drill, .appointment, .ppe: return "isg_workspace_safety_mutate_v1"
        case .equipment: return "isg_workspace_equipment_mutate_v1"
        case .katip, .annualPlan, .board, .workPermit, .visit:
            return "isg_workspace_operations_mutate_v1"
        case .files: return "isg_workspace_file_mutate_v1"
        case .personnel: return nil
        }
    }

    private func decodeDomainPage(_ data: Data, workspaceID: UUID, companyID: UUID,
                                  domain: IsgWorkspaceDomain, limit: Int) throws
        -> (rows: [IsgWorkspaceDomainRecord], next: UUID?) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["schema_version"] as? NSNumber)?.intValue == 1,
              root["workspace_id"] as? String == workspaceID.uuidString.lowercased(),
              root["company_id"] as? String == companyID.uuidString.lowercased() else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        let rawRows: [[String: Any]]
        if let values = root["rows"] as? [[String: Any]] { rawRows = values }
        else if let row = root["row"] as? [String: Any] { rawRows = [row] }
        else { rawRows = [] }
        guard rawRows.count <= limit else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let rows = try rawRows.map { try domainRecord($0, domain: domain) }
        let next: UUID?
        if root["next"] is NSNull || root["next"] == nil { next = nil }
        else if let raw = root["next"] as? String, let value = UUID(uuidString: raw) { next = value }
        else { throw IsgWorkspaceAPIFailure.invalidResponse }
        guard Set(rows.map(\.id)).count == rows.count,
              next == nil || (rows.count == limit && rows.last?.id == next) else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        return (rows, next)
    }

    private func decodeDomainMetrics(_ data: Data, workspaceID: UUID, companyID: UUID) throws
        -> [IsgWorkspaceDomainMetric] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["schema_version"] as? NSNumber)?.intValue == 1,
              root["workspace_id"] as? String == workspaceID.uuidString.lowercased(),
              root["company_id"] as? String == companyID.uuidString.lowercased(),
              (root["measured"] as? Bool) == true else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        var values: [IsgWorkspaceDomainMetric] = []
        flattenMetrics(root, prefix: "", into: &values)
        return Array(values.prefix(12))
    }

    private func flattenMetrics(_ value: [String: Any], prefix: String,
                                into result: inout [IsgWorkspaceDomainMetric]) {
        let ignored = Set(["schema_version", "workspace_id", "company_id", "measured"])
        for key in value.keys.sorted() where !ignored.contains(key) {
            let path = prefix.isEmpty ? key : prefix + "." + key
            if let nested = value[key] as? [String: Any] { flattenMetrics(nested, prefix: path, into: &result) }
            else if let number = value[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.int64Value >= 0 {
                result.append(.init(id: path, value: number.int64Value))
            }
        }
    }

    private func domainRecord(_ row: [String: Any], domain: IsgWorkspaceDomain) throws
        -> IsgWorkspaceDomainRecord {
        let idKeys = ["employee_id", "training_id", "assessment_id", "nonconformity_id", "run_id",
                      "plan_id", "drill_id", "appointment_id", "handover_id", "equipment_id",
                      "contract_id", "meeting_id", "permit_id", "visit_id", "entry_id", "id"]
        guard let idText = idKeys.compactMap({ row[$0] as? String }).first,
              let id = UUID(uuidString: idText) else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let titleKeys: [String]
        switch domain {
        case .personnel: titleKeys = ["name", "full_name", "code"]
        case .training: titleKeys = ["title", "trainer"]
        case .risk: titleKeys = ["scope", "assessment_id"]
        case .nonconformity: titleKeys = ["title"]
        case .checklist: titleKeys = ["template_code"]
        case .emergencyPlan: titleKeys = ["scope"]
        case .drill: titleKeys = ["observation", "planned_on"]
        case .appointment: titleKeys = ["kind", "starts_on"]
        case .ppe: titleKeys = ["item"]
        case .equipment: titleKeys = ["equipment_type_label", "equipment_type", "serial_tag"]
        case .katip: titleKeys = ["counterparty", "scope"]
        case .annualPlan: titleKeys = ["plan_year"]
        case .board: titleKeys = ["planned_on", "applicability"]
        case .workPermit: titleKeys = ["job_description", "template_code"]
        case .visit: titleKeys = ["visited_on", "location_note"]
        case .files: titleKeys = ["title", "original_filename"]
        }
        let title = domainTitle(row, domain: domain) ??
            titleKeys.compactMap { display(row[$0]) }.first ?? id.uuidString
        let riskVersions = domain == .risk ? row["versions"] as? [[String: Any]] : nil
        let latestRiskVersion = riskVersions?.first
        let status: String?
        if domain == .risk {
            if riskVersions?.contains(where: { display($0["state"]) == "draft" }) == true { status = "draft" }
            else if ((row["current_version"] as? NSNumber)?.intValue ?? 0) > 0 { status = "final" }
            else { status = display(latestRiskVersion?["state"]) }
        } else {
            status = ["state", "status"].compactMap { display(row[$0]) }.first
        }
        let subtitle = ["code", "serial_tag", "trainer", "location", "location_note", "expert_contact",
                        "opened_on", "prepared_on", "planned_on", "visited_on", "starts_on", "original_filename"]
            .compactMap { display(row[$0]) }.first
        let version = (row["version"] as? NSNumber)?.int64Value
        let hidden = Set(idKeys + titleKeys + ["state", "status", "version", "workspace_id", "company_id",
                                              "created_by_user_id", "updated_by_user_id", "created_at", "updated_at",
                                              "participants", "versions", "items", "asset", "team", "actions",
                                              "attendance", "agenda", "decisions"])
        var facts = row.keys.sorted().compactMap { key -> (String, String)? in
            guard !hidden.contains(key), let value = display(row[key]) else { return nil }
            return (key, value)
        }
        if domain == .equipment {
            for key in ["serial_tag", "equipment_type_label", "equipment_type"] {
                if let value = display(row[key]), !facts.contains(where: { $0.0 == key }) {
                    facts.insert((key, value), at: 0)
                }
            }
        }
        if domain == .emergencyPlan, let team = row["team"] as? [[String: Any]] {
            facts.append(("team_size", String(team.count)))
            let names = team.compactMap { $0["full_name"] as? String }
            if !names.isEmpty { facts.append(("team_members", names.joined(separator: ", "))) }
        }
        if domain == .board {
            if let agenda = row["agenda"] as? [String] {
                facts.append(("agenda_count", String(agenda.count)))
                if let first = agenda.first, !first.isEmpty { facts.append(("agenda_summary", first)) }
            }
            if let attendance = row["attendance"] as? [[String: Any]] {
                facts.append(("attendance_count", String(attendance.count)))
            }
            if let decisions = row["decisions"] as? [[String: Any]] {
                facts.append(("decision_count", String(decisions.count)))
                let open = decisions.filter { ($0["state"] as? String) == "open" }.count
                facts.append(("open_decision_count", String(open)))
            }
        }
        if let draft = riskVersions?.first(where: { display($0["state"]) == "draft" }) {
            if let value = display(draft["version"]) { facts.append(("draft_version", value)) }
            if let value = display(draft["kind"]) { facts.append(("draft_kind", value)) }
        }
        if domain == .training, let snapshot = row["curriculum_snapshot"] as? [String: Any] {
            if let value = display(snapshot["title"]) { facts.append(("curriculum_title", value)) }
            if let value = display(snapshot["revision"]) { facts.append(("curriculum_revision", value)) }
            if let value = display(snapshot["assessment_required"]) {
                facts.append(("assessment_required", value))
            }
        }
        let checklistItems: [IsgWorkspaceChecklistItem]
        if domain == .checklist, let rawItems = row["items"] as? [[String: Any]] {
            checklistItems = try rawItems.map { item in
                guard let code = item["item_code"] as? String, !code.isEmpty,
                      let prompt = item["prompt"] as? String, !prompt.isEmpty,
                      let allows = item["allows_not_applicable"] as? Bool else {
                    throw IsgWorkspaceAPIFailure.invalidResponse
                }
                let result = item["result"] as? String
                guard result == nil || ["conform", "nonconform", "not_applicable"].contains(result!) else {
                    throw IsgWorkspaceAPIFailure.invalidResponse
                }
                let nonconformityID = (item["nonconformity_id"] as? String).flatMap(UUID.init(uuidString:))
                if item["nonconformity_id"] != nil && nonconformityID == nil {
                    throw IsgWorkspaceAPIFailure.invalidResponse
                }
                return .init(code: code, prompt: prompt, allowsNotApplicable: allows,
                             result: result, note: item["note"] as? String,
                             nonconformityID: nonconformityID)
            }
            guard checklistItems.count <= 500,
                  Set(checklistItems.map(\.code)).count == checklistItems.count else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
        } else { checklistItems = [] }
        let trainingParticipants: [IsgWorkspaceTrainingParticipant]
        if domain == .training, let rawParticipants = row["participants"] as? [[String: Any]] {
            trainingParticipants = try rawParticipants.map { participant in
                guard let rawID = participant["employee_id"] as? String,
                      let employeeID = UUID(uuidString: rawID),
                      let name = participant["name"] as? String, !name.isEmpty,
                      let attended = participant["attended"] as? Bool else {
                    throw IsgWorkspaceAPIFailure.invalidResponse
                }
                return .init(id: employeeID, name: name, attended: attended)
            }
            guard trainingParticipants.count <= 500,
                  Set(trainingParticipants.map(\.id)).count == trainingParticipants.count else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
        } else { trainingParticipants = [] }
        let boardDecisions: [IsgWorkspaceBoardDecision]
        if domain == .board, let rawDecisions = row["decisions"] as? [[String: Any]] {
            boardDecisions = try rawDecisions.map { decision in
                guard let rawID = decision["decision_id"] as? String,
                      let id = UUID(uuidString: rawID),
                      let number = (decision["decision_no"] as? NSNumber)?.intValue,
                      let text = decision["decision_text"] as? String, !text.isEmpty,
                      let state = decision["state"] as? String,
                      ["open", "done", "cancelled"].contains(state),
                      let version = (decision["version"] as? NSNumber)?.int64Value else {
                    throw IsgWorkspaceAPIFailure.invalidResponse
                }
                return .init(id: id, number: number, text: text,
                             responsibleContact: decision["responsible_contact"] as? String,
                             dueOn: decision["due_on"] as? String, state: state, version: version)
            }
            guard boardDecisions.count <= 500, Set(boardDecisions.map(\.id)).count == boardDecisions.count else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
        } else { boardDecisions = [] }
        let parsedRiskVersions: [IsgWorkspaceRiskVersion]
        if domain == .risk, let values = riskVersions {
            guard values.count <= 500 else { throw IsgWorkspaceAPIFailure.invalidResponse }
            parsedRiskVersions = try values.map { value in
                guard let number = (value["version"] as? NSNumber)?.intValue, number > 0,
                      let kind = value["kind"] as? String,
                      ["full", "partial", "metadata", "rescan"].contains(kind),
                      let assessmentOn = value["assessment_on"] as? String, !assessmentOn.isEmpty,
                      let state = value["state"] as? String,
                      ["draft", "final", "superseded", "cancelled"].contains(state) else {
                    throw IsgWorkspaceAPIFailure.invalidResponse
                }
                let scopeSummary: String?
                if let scope = value["scope"] as? [String: Any] {
                    scopeSummary = display(scope["summary"])
                } else if let scope = value["scope"] as? [String] {
                    scopeSummary = scope.isEmpty ? nil : scope.joined(separator: ", ")
                } else if value["scope"] == nil || value["scope"] is NSNull {
                    scopeSummary = nil
                } else {
                    throw IsgWorkspaceAPIFailure.invalidResponse
                }
                return .init(number: number, kind: kind, assessmentOn: assessmentOn,
                             revisionOn: value["revision_on"] as? String,
                             scopeSummary: scopeSummary, reason: value["reason"] as? String,
                             state: state, validUntil: value["valid_until"] as? String,
                             periodYears: (value["period_years"] as? NSNumber)?.intValue,
                             periodSource: value["period_source"] as? String,
                             periodNeedsReview: (value["period_needs_review"] as? Bool) ?? false,
                             sourceDrift: (value["source_drift"] as? Bool) ?? false,
                             editRevision: (value["edit_revision"] as? NSNumber)?.intValue ?? 0,
                             cancellationNote: value["cancellation_note"] as? String)
            }
            guard Set(parsedRiskVersions.map(\.number)).count == parsedRiskVersions.count else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
        } else { parsedRiskVersions = [] }
        let equipmentInspections: [IsgWorkspaceEquipmentInspection]
        if domain == .equipment, let values = row["inspections"] as? [[String: Any]] {
            guard values.count <= 500 else { throw IsgWorkspaceAPIFailure.invalidResponse }
            equipmentInspections = try values.map { value in
                guard let idText = value["inspection_id"] as? String,
                      let inspectionID = UUID(uuidString: idText),
                      let performedOn = value["performed_on"] as? String, !performedOn.isEmpty,
                      let result = value["result"] as? String,
                      ["pass", "conditional", "fail"].contains(result),
                      let version = (value["version"] as? NSNumber)?.int64Value, version >= 0 else {
                    throw IsgWorkspaceAPIFailure.invalidResponse
                }
                let assetID: UUID?
                if value["workspace_asset_id"] == nil || value["workspace_asset_id"] is NSNull {
                    assetID = nil
                } else if let raw = value["workspace_asset_id"] as? String,
                          let parsed = UUID(uuidString: raw) { assetID = parsed }
                else { throw IsgWorkspaceAPIFailure.invalidResponse }
                return .init(id: inspectionID, performedOn: performedOn, result: result,
                             nextDueOn: value["next_due_on"] as? String,
                             periodMonths: (value["period_months"] as? NSNumber)?.intValue,
                             dueSource: value["due_source"] as? String,
                             inspector: value["inspector"] as? String,
                             externalRef: value["external_ref"] as? String,
                             note: value["note"] as? String, assetID: assetID, version: version,
                             katipDeclared: (value["katip_assignment_declared"] as? Bool) ?? false,
                             katipNote: value["katip_declared_note"] as? String)
            }
            guard Set(equipmentInspections.map(\.id)).count == equipmentInspections.count else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
        } else { equipmentInspections = [] }
        let asset = row["asset"] as? [String: Any]
        let assetID = (asset?["id"] as? String).flatMap(UUID.init(uuidString:))
        let fileExtension = asset?["extension"] as? String
        return .init(id: id, title: title, subtitle: subtitle, status: status,
                     version: version, facts: Array(facts.prefix(14)), checklistItems: checklistItems,
                     trainingParticipants: trainingParticipants, boardDecisions: boardDecisions,
                     riskVersions: parsedRiskVersions, equipmentInspections: equipmentInspections,
                     assetID: assetID,
                     fileExtension: fileExtension, originalFilename: row["original_filename"] as? String)
    }

    private func domainTitle(_ row: [String: Any], domain: IsgWorkspaceDomain) -> String? {
        guard domain == .risk,
              let versions = row["versions"] as? [[String: Any]],
              let scope = versions.first?["scope"] as? [String: Any],
              let summary = scope["summary"] as? String else { return nil }
        let clean = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    private func display(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let text = value as? String { return text.isEmpty ? nil : text }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "Evet" : "Hayır" }
            return number.stringValue
        }
        if let list = value as? [Any] { return list.isEmpty ? nil : String(list.count) }
        return nil
    }

    private func require(_ identity: NovaSessionIdentity) throws {
        guard currentIdentity() == identity else { throw IsgWorkspaceAPIFailure.staleSession }
    }
    private func require(_ selection: NovaWorkspaceSelection, operate: Bool = false) throws {
        guard selection.isStructurallyValid, selection.canRead, (!operate || selection.canOperate), isCurrentWorkspace(selection) else {
            throw IsgWorkspaceAPIFailure.staleSession
        }
    }

    private func decodeExport(_ data: Data, selection: NovaWorkspaceSelection, companyID: UUID) throws -> IsgWorkspaceExportResult {
        guard data.count <= 65_536 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let dto = try JSONDecoder().decode(ExportEnvelope.self, from: data)
        guard dto.schemaVersion == 1, dto.workspaceID == selection.workspaceID,
              dto.companyID == companyID,
              ["queued", "running", "succeeded", "failed", "cancelled"].contains(dto.row.status),
              (dto.row.status == "succeeded") == (dto.row.outputAssetID != nil) else { throw IsgWorkspaceAPIFailure.invalidResponse }
        return .init(id: dto.row.id, status: dto.row.status, outputAssetID: dto.row.outputAssetID)
    }

    private func decodeCompanyMutation(_ data: Data, selection: NovaWorkspaceSelection,
                                       expectedCompanyID: UUID?) throws -> IsgWorkspaceCompany {
        guard data.count <= 32_768 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let dto = try JSONDecoder().decode(CompanyMutationDTO.self, from: data)
        guard dto.schemaVersion == 1, dto.workspaceID == selection.workspaceID,
              expectedCompanyID == nil || dto.companyID == expectedCompanyID else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        return try dto.value()
    }

    private func decodeInvitationToken(_ data: Data, selection: NovaWorkspaceSelection,
                                       expectedInvitationID: UUID?) throws -> IsgWorkspaceInvitationToken {
        guard data.count <= 32_768 else { throw IsgWorkspaceAPIFailure.invalidResponse }
        let response = try JSONDecoder().decode(InvitationTokenDTO.self, from: data)
        guard response.schemaVersion == 1, response.workspaceID == selection.workspaceID,
              expectedInvitationID == nil || response.invitationID == expectedInvitationID,
              response.status == "pending", ["admin", "expert"].contains(response.role),
              (response.tokenPersisted == false || response.tokenReturned == true),
              response.token.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw IsgWorkspaceAPIFailure.invalidResponse
        }
        return .init(invitationID: response.invitationID, role: response.role,
                     status: response.status, expiresAt: response.expiresAt, token: response.token)
    }

    private struct WorkspaceList: Decodable {
        let schemaVersion: Int; let userID: UUID; let workspaces: [IsgWorkspaceContext]
        enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", userID = "user_id", workspaces }
    }
    private func validatePersonnelPage(_ ids: [UUID], after: UUID?, next: UUID?) throws {
        let ordered = ids.map { $0.uuidString.lowercased() }
        guard Set(ids).count == ids.count, ordered == ordered.sorted(),
              after == nil || ordered.allSatisfy({ $0 > after!.uuidString.lowercased() }),
              next == nil || next == ids.last else { throw IsgWorkspaceAPIFailure.invalidResponse }
    }

    private struct DirectoryPageDTO: Decodable {
        let next: UUID?
        let schemaVersion: Int; let workspaceID: UUID; let companyID: UUID; let rows: [DirectoryDTO]
        enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", workspaceID = "workspace_id", companyID = "company_id", rows, next }
    }
    private struct ChecklistTemplateEnvelope: Decodable {
        let schemaVersion: Int; let workspaceID: UUID; let companyID: UUID
        let templates: [ChecklistTemplateDTO]
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", workspaceID = "workspace_id"
            case companyID = "company_id", templates
        }
    }
    private struct ChecklistTemplateDTO: Decodable {
        let code: String; let version: Int; let title: String; let itemCount: Int
        var id: String { "\(code):\(version)" }
        enum CodingKeys: String, CodingKey {
            case code, version, title, itemCount = "item_count"
        }
    }
    private struct DirectoryDTO: Decodable {
        let workplaceID: UUID?; let departmentID: UUID?; let code: String; let name: String
        let parentWorkplaceID: UUID?; let hazardClass: String?; let isArchived: Bool; let version: Int64
        enum CodingKeys: String, CodingKey {
            case workplaceID = "workplace_id", departmentID = "department_id", code, name
            case parentWorkplaceID = "parent_workplace_id", hazardClass = "hazard_class"
            case isArchived = "is_archived", version
        }
        func value(kind: IsgWorkspaceDirectoryKind) throws -> IsgWorkspaceDirectoryEntry {
            let id = kind == .workplace ? workplaceID : departmentID
            guard let id, !code.isEmpty, !name.isEmpty, version >= 0 else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
            return .init(id: id, kind: kind, code: code, name: name,
                         workplaceID: kind == .department ? workplaceID : nil,
                         hazardClass: hazardClass, isArchived: isArchived, version: version)
        }
    }
    private struct EmployeePageDTO: Decodable {
        let next: UUID?
        let schemaVersion: Int; let workspaceID: UUID; let companyID: UUID; let rows: [EmployeeDTO]
        enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", workspaceID = "workspace_id", companyID = "company_id", rows, next }
    }
    private struct EmployeeDTO: Decodable {
        let employeeID: UUID; let code: String; let name: String; let departmentID: UUID?
        let hiredOn: String?; let endsBefore: String?; let isArchived: Bool; let version: Int64
        enum CodingKeys: String, CodingKey {
            case employeeID = "employee_id", code, name, departmentID = "department_id"
            case hiredOn = "hired_on", endsBefore = "employment_ends_before"
            case isArchived = "is_archived", version
        }
        init(json: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: json)
            self = try JSONDecoder().decode(Self.self, from: data)
        }
        func value() throws -> IsgWorkspaceEmployeeEntry {
            guard !code.isEmpty, !name.isEmpty, version >= 0,
                  hiredOn.map(ISO8601Day.isValid) ?? true,
                  endsBefore.map(ISO8601Day.isValid) ?? true else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
            return .init(id: employeeID, code: code, name: name, departmentID: departmentID,
                         hiredOn: hiredOn, endsBefore: endsBefore,
                         isArchived: isArchived, version: version)
        }
    }
    private struct MemberPageDTO: Decodable {
        let schemaVersion: Int; let workspaceID: UUID; let rows: [MemberDTO]; let next: UUID?
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", workspaceID = "workspace_id", rows, next
        }
    }
    private struct MemberDTO: Decodable {
        let membershipID: UUID; let userID: UUID; let role: String; let status: String
        let isPracticingExpert: Bool; let permissionRevision: Int64; let version: Int64
        let activeCompanyCount: Int64?
        enum CodingKeys: String, CodingKey {
            case membershipID = "membership_id", userID = "user_id", role, status
            case isPracticingExpert = "is_practicing_expert", permissionRevision = "permission_revision"
            case version, activeCompanyCount = "active_company_count"
        }
        func value() throws -> IsgWorkspaceMember {
            guard ["owner", "admin", "expert"].contains(role),
                  ["active", "suspended", "ended"].contains(status),
                  !isPracticingExpert || (role == "expert" && status == "active"),
                  permissionRevision >= 0, version >= 0, (activeCompanyCount ?? 0) >= 0 else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
            return .init(id: membershipID, userID: userID, role: role, status: status,
                         isPracticingExpert: isPracticingExpert, permissionRevision: permissionRevision,
                         version: version, activeCompanyCount: activeCompanyCount ?? 0)
        }
    }
    private struct MemberMutationDTO: Decodable {
        let schemaVersion: Int; let workspaceID: UUID; let membership: MemberDTO
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", workspaceID = "workspace_id", membership
        }
    }
    private struct InvitationPageDTO: Decodable {
        let schemaVersion: Int; let workspaceID: UUID; let rows: [InvitationDTO]; let next: UUID?
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", workspaceID = "workspace_id", rows, next
        }
    }
    private struct InvitationDTO: Decodable {
        let invitationID: UUID; let email: String; let role: String; let status: String
        let expiresAt: String; let version: Int64
        enum CodingKeys: String, CodingKey {
            case invitationID = "invitation_id", email, role, status
            case expiresAt = "expires_at", version
        }
        func value() throws -> IsgWorkspaceInvitation {
            guard email.contains("@"), ["admin", "expert"].contains(role),
                  ["pending", "accepted", "revoked", "expired"].contains(status),
                  !expiresAt.isEmpty, version >= 0 else { throw IsgWorkspaceAPIFailure.invalidResponse }
            return .init(id: invitationID, email: email, role: role, status: status,
                         expiresAt: expiresAt, version: version)
        }
    }
    private struct InvitationTokenDTO: Decodable {
        let schemaVersion: Int; let workspaceID: UUID; let invitationID: UUID
        let role: String; let status: String; let expiresAt: String; let token: String
        let tokenPersisted: Bool?; let tokenReturned: Bool?
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", workspaceID = "workspace_id"
            case invitationID = "invitation_id", role, status, expiresAt = "expires_at"
            case token = "invitation_token", tokenPersisted = "token_persisted", tokenReturned = "token_returned"
        }
    }
    private struct InvitationMutationDTO: Decodable {
        let schemaVersion: Int; let workspaceID: UUID; let invitationID: UUID
        let status: String; let version: Int64
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", workspaceID = "workspace_id"
            case invitationID = "invitation_id", status, version
        }
    }
    private struct CompanyPage: Decodable {
        let schemaVersion: Int; let workspaceID: UUID; let rows: [CompanyDTO]; let next: UUID?
        enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", workspaceID = "workspace_id", rows, next }
    }
    private struct AssignmentPageDTO: Decodable {
        let schemaVersion: Int; let workspaceID: UUID; let companyID: UUID
        let rows: [AssignmentDTO]; let next: UUID?
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", workspaceID = "workspace_id"
            case companyID = "company_id", rows, next
        }
    }
    private struct AssignmentDTO: Decodable {
        let assignmentID: UUID; let workspaceID: UUID; let companyID: UUID
        let membershipID: UUID; let userID: UUID; let assignmentRole: String
        let membershipRole: String?; let membershipStatus: String?
        let startsAt: String; let endsAt: String?; let version: Int64
        enum CodingKeys: String, CodingKey {
            case assignmentID = "assignment_id", workspaceID = "workspace_id", companyID = "company_id"
            case membershipID = "membership_id", userID = "user_id", assignmentRole = "assignment_role"
            case membershipRole = "membership_role", membershipStatus = "membership_status"
            case startsAt = "starts_at", endsAt = "ends_at", version
        }
        @MainActor func value(workspaceID expectedWorkspace: UUID,
                              companyID expectedCompany: UUID) throws -> IsgWorkspaceCompanyAssignment {
            guard workspaceID == expectedWorkspace, companyID == expectedCompany,
                  ["primary", "support"].contains(assignmentRole),
                  version >= 0, IsgWorkspaceAPI.validInstant(startsAt),
                  endsAt.map(IsgWorkspaceAPI.validInstant) ?? true else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
            return .init(id: assignmentID, companyID: companyID, membershipID: membershipID,
                userID: userID, assignmentRole: assignmentRole,
                membershipRole: membershipRole ?? "expert", membershipStatus: membershipStatus ?? "unknown",
                startsAt: startsAt, endsAt: endsAt, version: version)
        }
    }
    private struct CompanyDTO: Decodable {
        let companyID: UUID; let name: String; let hazardClass: String; let status: String; let version: Int64
        let sector: String?; let email: String?; let declaredEmployeeCount: Int?; let address: String?
        let responsibleName: String?; let responsiblePhone: String?; let responsibleEmail: String?
        let profileVersion: Int64?
        enum CodingKeys: String, CodingKey {
            case companyID = "company_id", name, hazardClass = "hazard_class", status, version, sector, email, address
            case declaredEmployeeCount = "declared_employee_count", responsibleName = "responsible_name"
            case responsiblePhone = "responsible_phone", responsibleEmail = "responsible_email"
            case profileVersion = "profile_version"
        }
        func value() throws -> IsgWorkspaceCompany {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 200,
                  ["low", "medium", "high"].contains(hazardClass), status == "active",
                  (0...9_007_199_254_740_991).contains(version) else { throw IsgWorkspaceAPIFailure.invalidResponse }
            return .init(id: companyID, name: name, hazardClass: hazardClass, status: status, version: version,
                sector: sector, email: email, declaredEmployeeCount: declaredEmployeeCount, address: address,
                responsibleName: responsibleName, responsiblePhone: responsiblePhone,
                responsibleEmail: responsibleEmail, profileVersion: profileVersion)
        }
    }
    private struct CompanyMutationDTO: Decodable {
        let schemaVersion: Int; let workspaceID: UUID; let companyID: UUID
        let name: String; let hazardClass: String; let status: String; let version: Int64
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", workspaceID = "workspace_id", companyID = "company_id"
            case name, hazardClass = "hazard_class", status, version
        }
        func value() throws -> IsgWorkspaceCompany {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 200,
                  ["low", "medium", "high"].contains(hazardClass), status == "active",
                  (0...9_007_199_254_740_991).contains(version) else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
            return .init(id: companyID, name: name, hazardClass: hazardClass, status: status, version: version)
        }
    }
    private struct CompanyArchiveDTO: Decodable {
        let schemaVersion: Int; let workspaceID: UUID; let companyID: UUID
        let status: String; let version: Int64; let dataDeleted: Bool
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", workspaceID = "workspace_id", companyID = "company_id"
            case status, version, dataDeleted = "data_deleted"
        }
    }
    private struct CompanyProfileDTO: Decodable {
        let schemaVersion: Int; let workspaceID: UUID; let companyID: UUID
        let sector: String; let email: String?; let declaredEmployeeCount: Int?; let address: String?
        let responsibleName: String?; let responsiblePhone: String?; let responsibleEmail: String?
        let profileVersion: Int64
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", workspaceID = "workspace_id", companyID = "company_id"
            case sector, email, address, declaredEmployeeCount = "declared_employee_count"
            case responsibleName = "responsible_name", responsiblePhone = "responsible_phone"
            case responsibleEmail = "responsible_email", profileVersion = "profile_version"
        }
        func value() throws -> IsgWorkspaceCompanyProfile {
            let responsible = [responsibleName, responsiblePhone, responsibleEmail]
            guard !sector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  sector.utf8.count <= 160, profileVersion >= 0,
                  responsible.allSatisfy({ $0 == nil }) || responsible.allSatisfy({ $0 != nil }) else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
            return .init(sector: sector, email: email, declaredEmployeeCount: declaredEmployeeCount,
                         address: address, responsibleName: responsibleName,
                         responsiblePhone: responsiblePhone, responsibleEmail: responsibleEmail,
                         version: profileVersion)
        }
    }
    private struct PersonnelMetricsDTO: Decodable {
        struct Counts: Decodable { let active: Int64; let archived: Int64 }
        struct AssignmentCounts: Decodable { let current: Int64; let historical: Int64 }
        let schemaVersion: Int; let workspaceID: UUID; let companyID: UUID?; let measured: Bool
        let workplaces: Counts; let departments: Counts; let employees: Counts
        let jobRoles: Counts?; let contractors: Counts?; let assignments: AssignmentCounts?
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", workspaceID = "workspace_id", companyID = "company_id"
            case measured, workplaces, departments, employees, contractors, assignments
            case jobRoles = "job_roles"
        }
        func value(workspaceID expectedWorkspace: UUID, companyID expectedCompany: UUID?) throws -> IsgPersonnelMetrics {
            let all = [workplaces, departments, employees] + [jobRoles, contractors].compactMap { $0 }
            guard schemaVersion == 1, workspaceID == expectedWorkspace, companyID == expectedCompany, measured,
                  all.allSatisfy({ $0.active >= 0 && $0.archived >= 0 }) else { throw IsgWorkspaceAPIFailure.invalidResponse }
            return .init(workspaceID: workspaceID, companyID: companyID,
                workplaces: .init(active: workplaces.active, archived: workplaces.archived),
                departments: .init(active: departments.active, archived: departments.archived),
                employees: .init(active: employees.active, archived: employees.archived),
                jobRoles: .init(active: jobRoles?.active ?? 0, archived: jobRoles?.archived ?? 0),
                contractors: .init(active: contractors?.active ?? 0, archived: contractors?.archived ?? 0),
                assignments: .init(current: assignments?.current ?? 0, historical: assignments?.historical ?? 0))
        }
    }

    private struct DashboardDTO: Decodable {
        struct Companies: Decodable { let total: Int64; let unassigned: Int64? }
        struct Experts: Decodable { let active: Int64? }
        struct Nonconformities: Decodable { let open: Int64; let overdue: Int64 }
        struct Visits: Decodable { let total: Int64; let last30Days: Int64; enum CodingKeys: String,CodingKey { case total; case last30Days = "last_30_days" } }
        struct Training: Decodable { let planned: Int64; let completed: Int64 }
        struct Deadlines: Decodable { let equipmentDueSoon: Int64; let riskDueSoon: Int64; enum CodingKeys: String,CodingKey { case equipmentDueSoon = "equipment_due_soon", riskDueSoon = "risk_due_soon" } }
        let schemaVersion: Int; let workspaceID: UUID; let companyID: UUID?; let measured: Bool
        let companies: Companies; let experts: Experts; let nonconformities: Nonconformities
        let visits: Visits; let training: Training; let deadlines: Deadlines
        enum CodingKeys: String,CodingKey { case schemaVersion = "schema_version", workspaceID = "workspace_id", companyID = "company_id", measured,companies,experts,nonconformities,visits,training,deadlines }
        func value(workspaceID expected: UUID, companyID expectedCompany: UUID?) throws -> IsgWorkspaceDashboard {
            let values = [companies.total, nonconformities.open, nonconformities.overdue, visits.total,
                          visits.last30Days, training.planned, training.completed, deadlines.equipmentDueSoon, deadlines.riskDueSoon]
            guard schemaVersion == 1, workspaceID == expected, companyID == expectedCompany, measured,
                  values.allSatisfy({ $0 >= 0 }), companies.unassigned.map({ $0 >= 0 }) ?? true,
                  experts.active.map({ $0 >= 0 }) ?? true else { throw IsgWorkspaceAPIFailure.invalidResponse }
            return .init(workspaceID: workspaceID, companyID: companyID,
                companies: .init(first: companies.total, second: companies.unassigned), experts: experts.active,
                nonconformities: .init(first: nonconformities.open, second: nonconformities.overdue),
                visits: .init(first: visits.total, second: visits.last30Days),
                training: .init(first: training.planned, second: training.completed),
                deadlines: .init(first: deadlines.equipmentDueSoon, second: deadlines.riskDueSoon))
        }
    }
    private struct SearchDTO: Decodable {
        struct Cursor: Decodable { let kind: String; let id: UUID }
        let schemaVersion: Int; let workspaceID: UUID; let companyID: UUID; let rows: [IsgWorkspaceSearchRow]
        let returned: Int; let next: Cursor?
        enum CodingKeys: String,CodingKey { case schemaVersion = "schema_version", workspaceID = "workspace_id", companyID = "company_id", rows,returned,next }
        func value(workspaceID expected: UUID, companyID expectedCompany: UUID, limit: Int) throws -> IsgWorkspaceSearchPage {
            let allowed = ["company","employee","nonconformity","equipment","training","file"]
            guard schemaVersion == 1, workspaceID == expected, companyID == expectedCompany,
                  returned == rows.count, rows.count <= limit, rows.allSatisfy({ allowed.contains($0.kind) && !$0.title.isEmpty }) else {
                throw IsgWorkspaceAPIFailure.invalidResponse }
            return .init(rows: rows, nextKind: next?.kind, nextID: next?.id)
        }
    }
    private struct AnalysisDTO: Decodable {
        struct Header: Decodable {
            let id: UUID; let title: String; let primaryMethod: String; let createdAt: String
            enum CodingKeys: String,CodingKey { case id,title; case primaryMethod = "primary_method", createdAt = "created_at" }
        }
        struct Counts: Decodable { let risk: Int; let expert: Int; let training: Int }
        let schemaVersion: Int; let workspaceID: UUID; let companyID: UUID; let analysis: Header
        let riskFindings: [IsgWorkspaceAnalysisItem]; let expertItems: [IsgWorkspaceAnalysisItem]
        let trainingItems: [IsgWorkspaceAnalysisItem]; let counts: Counts
        enum CodingKeys: String,CodingKey { case schemaVersion = "schema_version", workspaceID = "workspace_id", companyID = "company_id", analysis; case riskFindings = "risk_findings", expertItems = "expert_items", trainingItems = "training_items", counts }
        func value(workspaceID expected: UUID, companyID expectedCompany: UUID, analysisID: UUID) throws -> IsgWorkspaceAnalysisResult {
            guard schemaVersion == 1, workspaceID == expected, companyID == expectedCompany, analysis.id == analysisID,
                  ["fine_kinney","matrix_5x5"].contains(analysis.primaryMethod), counts.risk == riskFindings.count,
                  counts.expert == expertItems.count, counts.training == trainingItems.count else { throw IsgWorkspaceAPIFailure.invalidResponse }
            return .init(analysisID: analysis.id,title: analysis.title,primaryMethod: analysis.primaryMethod,
                createdAt: analysis.createdAt,
                riskFindings: riskFindings,expertItems: expertItems,trainingItems: trainingItems)
        }
    }
    private struct AnalysisListDTO: Decodable {
        struct Row: Decodable {
            let id: UUID; let title: String; let kind: String; let status: String
            let primaryMethod: String; let createdAt: String; let version: Int64
            let findingCount: Int; let highestBand: String?
            enum CodingKeys: String, CodingKey {
                case id,title,kind,status,version
                case primaryMethod = "primary_method", createdAt = "created_at"
                case findingCount = "finding_count", highestBand = "highest_band"
            }
        }
        let schemaVersion: Int; let workspaceID: UUID; let companyID: UUID
        let offset: Int; let returned: Int; let hasMore: Bool; let rows: [Row]
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", workspaceID = "workspace_id", companyID = "company_id"
            case offset, returned, hasMore = "has_more", rows
        }
        func value(workspaceID expected: UUID, companyID expectedCompany: UUID,
                   expectedOffset: Int, limit: Int) throws -> IsgWorkspaceAnalysisPage {
            let kinds = ["photo", "document", "record_set"]
            let methods = ["fine_kinney", "matrix_5x5"]
            let bands = ["critical", "high", "medium", "low"]
            guard schemaVersion == 1, workspaceID == expected, companyID == expectedCompany,
                  offset == expectedOffset, returned == rows.count, rows.count <= limit,
                  rows.allSatisfy({ !$0.title.isEmpty && kinds.contains($0.kind) && $0.status == "ready" &&
                      methods.contains($0.primaryMethod) && $0.version > 0 && $0.findingCount >= 0 &&
                      ($0.highestBand == nil || bands.contains($0.highestBand!)) }),
                  Set(rows.map(\.id)).count == rows.count else { throw IsgWorkspaceAPIFailure.invalidResponse }
            return .init(rows: rows.map { .init(id: $0.id, title: $0.title, kind: $0.kind,
                primaryMethod: $0.primaryMethod, createdAt: $0.createdAt,
                findingCount: $0.findingCount, highestBand: $0.highestBand) },
                offset: offset, hasMore: hasMore)
        }
    }
    private struct PhotoAnalysisSubmitDTO: Decodable {
        let schemaVersion: Int
        let jobID: UUID
        let workspaceID: UUID
        let companyID: UUID
        let sourceAssetID: UUID
        let status: String
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", jobID = "job_id", workspaceID = "workspace_id"
            case companyID = "company_id", sourceAssetID = "source_asset_id", status
        }
        func value(workspaceID expectedWorkspace: UUID,
                   companyID expectedCompany: UUID) throws -> IsgWorkspacePhotoAnalysisJob {
            guard schemaVersion == 1, workspaceID == expectedWorkspace, companyID == expectedCompany,
                  ["queued", "running", "succeeded", "failed", "cancelled", "reconcile"].contains(status) else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
            return .init(id: jobID, workspaceID: workspaceID, companyID: companyID, status: status,
                         outputAssetID: nil, errorCode: nil, version: nil, analysisID: nil)
        }
    }
    private struct PhotoAnalysisJobDTO: Decodable {
        let schemaVersion: Int
        let jobID: UUID
        let workspaceID: UUID
        let companyID: UUID
        let feature: String
        let status: String
        let sourceKind: String
        let outputAssetID: UUID?
        let errorCode: String?
        let version: Int64
        let analysisID: UUID?
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", jobID = "job_id", workspaceID = "workspace_id"
            case companyID = "company_id", feature, status, sourceKind = "source_kind"
            case outputAssetID = "output_asset_id", errorCode = "error_code", version
            case analysisID = "analysis_id"
        }
        func value(workspaceID expectedWorkspace: UUID, companyID expectedCompany: UUID,
                   jobID expectedJob: UUID) throws -> IsgWorkspacePhotoAnalysisJob {
            let statuses = ["queued", "running", "succeeded", "failed", "cancelled", "reconcile"]
            guard schemaVersion == 1, workspaceID == expectedWorkspace, companyID == expectedCompany,
                  jobID == expectedJob, feature == "photo_analysis", sourceKind == "photo",
                  statuses.contains(status), version >= 0,
                  status != "succeeded" || (outputAssetID != nil && analysisID != nil),
                  !["failed", "reconcile"].contains(status) || errorCode != nil else {
                throw IsgWorkspaceAPIFailure.invalidResponse
            }
            return .init(id: jobID, workspaceID: workspaceID, companyID: companyID, status: status,
                         outputAssetID: outputAssetID, errorCode: errorCode,
                         version: version, analysisID: analysisID)
        }
    }
    private struct FilingDTO: Decodable {
        let schemaVersion: Int; let workspaceID: UUID; let companyID: UUID; let nonconformityID: UUID
        let created: Bool; let commitState: String; let successMessageKey: String
        enum CodingKeys: String,CodingKey { case schemaVersion = "schema_version", workspaceID = "workspace_id", companyID = "company_id", nonconformityID = "nonconformity_id", created; case commitState = "commit_state", successMessageKey = "success_message_key" }
    }
    private struct ExportEnvelope: Decodable {
        struct Row: Decodable { let id: UUID; let status: String; let outputAssetID: UUID?; enum CodingKeys: String,CodingKey { case id,status; case outputAssetID = "output_asset_id" } }
        let schemaVersion: Int; let workspaceID: UUID?; let companyID: UUID?; let row: Row
        enum CodingKeys: String,CodingKey { case schemaVersion = "schema_version", workspaceID = "workspace_id", companyID = "company_id", row }
    }
    private struct FileUploadOpenDTO: Decodable {
        let schemaVersion: Int; let intentID: UUID; let workspaceID: UUID
        let status: String; let bucket: String; let objectPath: String
        let uploadToken: String?; let credentialReturned: Bool; let replayed: Bool
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", intentID = "intent_id", workspaceID = "workspace_id"
            case status, bucket, objectPath = "object_path", uploadToken = "upload_token"
            case credentialReturned = "credential_returned", replayed
        }
    }
    private struct FileCreateReceiptDTO: Decodable {
        let schemaVersion: Int; let workspaceID: UUID; let companyID: UUID
        let found: Bool; let entryID: UUID?; let assetID: UUID?; let byteSize: Int64?
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", workspaceID = "workspace_id", companyID = "company_id"
            case found, entryID = "entry_id", assetID = "asset_id", byteSize = "byte_size"
        }
    }
    private struct FileUploadFinalizedDTO: Decodable {
        let schemaVersion: Int; let assetID: UUID; let workspaceID: UUID; let byteSize: Int64
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", assetID = "asset_id", workspaceID = "workspace_id"
            case byteSize = "byte_size"
        }
    }
    private struct FileDownloadOpenDTO: Decodable {
        let schemaVersion: Int; let downloadID: UUID; let workspaceID: UUID
        let expiresAt: String; let downloadToken: String
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", downloadID = "download_id", workspaceID = "workspace_id"
            case expiresAt = "expires_at", downloadToken = "download_token"
        }
    }
    private struct ChangeDTO: Decodable {
        let schemaVersion: Int; let workspaceID: UUID; let companyID: UUID?; let rows: [IsgWorkspaceChange]; let next: Int64
        enum CodingKeys: String,CodingKey { case schemaVersion = "schema_version", workspaceID = "workspace_id", companyID = "company_id", rows,next }
    }
    private enum ISO8601Day {
        static func isValid(_ value: String) -> Bool {
            guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
            let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .iso8601)
            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
            return formatter.date(from: value) != nil
        }
    }
}
