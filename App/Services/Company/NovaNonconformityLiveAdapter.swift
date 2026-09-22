import Foundation
import Supabase

extension NovaNonconformityService {
    static func live(currentScope: @escaping () -> NovaPersonnelScope?) -> NovaNonconformityService {
        makeLive { scope in
            guard currentScope() == scope else { return false }
            return novaCurrentSessionIdentity() == .init(userID: scope.ownerID, sessionID: scope.sessionID)
        }
    }

    /// The analysis result has its own company picker. Its write must not race
    /// the Firmalar tab's global selection; the RPC verifies the company again.
    static func live(identity: NovaSessionIdentity) -> NovaNonconformityService {
        makeLive { scope in
            scope.ownerID == identity.userID && scope.sessionID == identity.sessionID
                && novaCurrentSessionIdentity() == identity
        }
    }

    private static func makeLive(isCurrent: @escaping (NovaPersonnelScope) -> Bool) -> NovaNonconformityService {
        let ticket = NovaExpertTransport.shared.capture()
        return NovaNonconformityService(rpc: { function, args in
            do { return try await NovaExpertTransport.shared.execute(function, params: args, ticket: ticket) }
            catch let error as PostgrestError {
                guard error.code == "P0001" || error.code == "28000" else { throw NovaNonconformityFailure.unavailable }
                switch error.message {
                case "AUTH_REQUIRED", "ACCESS_DENIED", "PAID_PLAN_REQUIRED": throw NovaNonconformityFailure.denied
                // An unreadable legacy band is its own answer: the screen has to
                // ask the expert instead of showing a generic failure.
                case "SEVERITY_UNKNOWN": throw NovaNonconformityFailure.severityUnknown
                case "PAYLOAD_NOT_ALLOWED": throw NovaNonconformityFailure.payloadRejected
                // A half-filled scoring method is its own answer: the screen has
                // to point at the missing input, not show a generic failure.
                case "RISK_INPUT_INCOMPLETE": throw NovaNonconformityFailure.riskInputIncomplete
                case "VALIDATION_ERROR", "SOURCE_REFERENCE_REQUIRED": throw NovaNonconformityFailure.validation
                case "VERSION_CONFLICT", "IDEMPOTENCY_CONFLICT", "STATE_TRANSITION_INVALID": throw NovaNonconformityFailure.conflict
                default: throw NovaNonconformityFailure.unavailable
                }
            }
        }, isCurrent: isCurrent)
    }
}
