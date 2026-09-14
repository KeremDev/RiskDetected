import Foundation
import Supabase

extension NovaDocumentTrackingService {
    static func live(currentScope: @escaping () -> NovaPersonnelScope?) -> NovaDocumentTrackingService {
        let client = SupabaseService.shared.client
        return NovaDocumentTrackingService(rpc: { function, args in
            do { return try await client.rpc(function, params: args).execute().data }
            catch let error as PostgrestError {
                guard error.code == "P0001" || error.code == "28000" else { throw NovaDocumentFailure.unavailable }
                switch error.message {
                case "AUTH_REQUIRED", "ACCESS_DENIED": throw NovaDocumentFailure.denied
                case "PAID_PLAN_REQUIRED": throw NovaDocumentFailure.planRequired
                // An archived obligation is its own answer: the screen has to
                // say why the copy was refused, not show a generic failure.
                case "OBLIGATION_ARCHIVED": throw NovaDocumentFailure.archived
                case "VERSION_CONFLICT": throw NovaDocumentFailure.versionConflict
                case "IDEMPOTENCY_CONFLICT": throw NovaDocumentFailure.conflict
                case "VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED": throw NovaDocumentFailure.validation
                default: throw NovaDocumentFailure.unavailable
                }
            }
        }, isCurrent: { scope in
            guard currentScope() == scope, let session = client.auth.currentSession, session.user.id == scope.ownerID else { return false }
            return NovaPersonnelService.sessionID(session.accessToken) == scope.sessionID
        })
    }
}
