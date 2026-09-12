import Foundation

/// Additive transport only; no legacy API or UI behavior is changed.
struct IsgMutationOutcome: Decodable {
    let schemaVersion: Int
    let operationID: String
    let requestID: String
    let supportID: String
    let outcome: String
    let code: String?
    let version: Int64?
    let currentVersion: Int64?
    let projection: String?
    let retryAfterSeconds: Int?
    private static let statusCodes = ["AUTH_REQUIRED":401,"COMPANY_ACCESS_DENIED":403,"CAPABILITY_DISABLED":403,
        "CROSS_COMPANY_REFERENCE":403,"VERSION_CONFLICT":409,"VALIDATION_FAILED":422,"RULE_REVIEW_REQUIRED":409,
        "DOCUMENT_NOT_READY":409,"QUOTA_EXCEEDED":409,"IDEMPOTENCY_CONFLICT":409,"SCAN_PENDING":423,"UNSUPPORTED_FORMAT":415]
    var httpStatus: Int { outcome == "committed" ? 200 : outcome == "pending" ? 202 : outcome == "indeterminate" ? 503 : Self.statusCodes[code!]! }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        func text(_ name: String) throws -> String { try c.decode(String.self, forKey: Key(name)) }
        var fields: Set<String> = ["schema_version","operation_id","request_id","support_id","outcome"]
        schemaVersion = try c.decode(Int.self, forKey: Key("schema_version"))
        operationID = try text("operation_id"); requestID = try text("request_id"); supportID = try text("support_id"); outcome = try text("outcome")
        let uuid = "^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
        guard schemaVersion == 1, operationID.utf8.count == 36, requestID.utf8.count == 36,
              operationID.range(of: uuid, options: .regularExpression) != nil,
              requestID.range(of: uuid, options: .regularExpression) != nil,
              supportID.utf8.count == 16, supportID.range(of: "^ISG-[A-F0-9]{12}$", options: .regularExpression) != nil else { throw Invalid.outcome }
        switch outcome {
        case "committed":
            let v = try c.decode(Int64.self, forKey: Key("version")); let p = try text("projection")
            guard (0...9007199254740991).contains(v), ["ready","pending","failed"].contains(p) else { throw Invalid.outcome }
            version = v; projection = p; code = nil; currentVersion = nil; retryAfterSeconds = nil
            fields.formUnion(["version","projection"])
        case "pending", "indeterminate":
            let value = try text("code"); let delay = try c.decode(Int.self, forKey: Key("retry_after_seconds"))
            guard value == (outcome == "pending" ? "JOB_PENDING" : "RETRYABLE_FAILURE"), (1...300).contains(delay) else { throw Invalid.outcome }
            code = value; retryAfterSeconds = delay; version = nil; projection = nil; currentVersion = nil
            fields.formUnion(["code","retry_after_seconds"])
        case "rejected":
            let value = try text("code"); guard Self.statusCodes[value] != nil else { throw Invalid.outcome }
            code = value; version = nil; projection = nil; retryAfterSeconds = nil; fields.insert("code")
            if value == "VERSION_CONFLICT" {
                let v = try c.decode(Int64.self, forKey: Key("current_version"))
                guard (0...9007199254740991).contains(v) else { throw Invalid.outcome }
                currentVersion = v; fields.insert("current_version")
            } else { currentVersion = nil }
        default: throw Invalid.outcome
        }
        guard Set(c.allKeys.map(\.stringValue)) == fields else { throw Invalid.outcome }
    }
    static func parse(status: Int, data: Data) -> IsgMutationOutcome? {
        guard let value = try? JSONDecoder().decode(Self.self, from: data), value.httpStatus == status else { return nil }
        return value
    }
    private enum Invalid: Error { case outcome }
    private struct Key: CodingKey {
        let stringValue: String; var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

enum IsgMutationPhase: String, CaseIterable { case prepared, submitting, reconciling, committed, blocked, detached }
enum IsgMutationEvent: String, CaseIterable { case submit, transport_loss, committed, pending, indeterminate, rejected, account_changed }
struct IsgMutationTransition {
    let phase: IsgMutationPhase; let effect: String
    /// sameContext must include operation ID and the current auth-session epoch.
    static func next(_ phase: IsgMutationPhase, _ event: IsgMutationEvent, sameContext: Bool) -> Self {
        guard sameContext, phase != .detached else { return Self(phase: phase, effect: "none") }
        if event == .account_changed { return Self(phase: .detached, effect: "detach") }
        if phase == .prepared, event == .submit { return Self(phase: .submitting, effect: "submit_same_key") }
        guard phase == .submitting || phase == .reconciling else { return Self(phase: phase, effect: "none") }
        if event == .committed { return Self(phase: .committed, effect: "show_committed") }
        if event == .rejected { return Self(phase: .blocked, effect: "show_blocked") }
        if [.transport_loss,.pending,.indeterminate].contains(event) { return Self(phase: .reconciling, effect: "reconcile_same_operation") }
        return Self(phase: phase, effect: "none")
    }
}
