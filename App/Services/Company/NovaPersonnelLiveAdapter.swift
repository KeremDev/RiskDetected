import Foundation
import Supabase

extension NovaPersonnelService {
    static func live(currentScope: @escaping () -> NovaPersonnelScope?) -> NovaPersonnelService {
        let client = SupabaseService.shared.client
        let ticket = NovaExpertTransport.shared.capture()
        return NovaPersonnelService(rpc: { function, args in
            do { return try await NovaExpertTransport.shared.execute(function, params: args, ticket: ticket) }
            catch let error as PostgrestError {
                // Unknown outcomes (including disabled rollout) retain the original journal.
                guard error.code == "P0001" || error.code == "28000" else { throw NovaPersonnelFailure.unavailable }
                switch error.message {
                case "AUTH_REQUIRED", "ACCESS_DENIED", "PAID_PLAN_REQUIRED": throw NovaPersonnelFailure.denied
                case "VALIDATION_ERROR", "DEPARTMENT_SCOPE_INVALID", "ASSIGNMENT_CHANGE_REQUIRED", "EMPLOYMENT_INTERVAL_INVALID": throw NovaPersonnelFailure.validation
                case "VERSION_CONFLICT": throw NovaPersonnelFailure.conflict
                case "DEPARTMENT_SELECTION_REQUIRED": throw NovaPersonnelFailure.selectionRequired
                default: throw NovaPersonnelFailure.unavailable
                }
            }
        }, isCurrent: { scope in
            guard currentScope() == scope, let session = client.auth.currentSession, session.user.id == scope.ownerID else { return false }
            return Self.sessionID(session.accessToken) == scope.sessionID
        }, storage: KeychainPersonnelPendingStorage())
    }
}
