import Foundation
import Supabase

extension NovaKatipService {
    static func live() -> NovaKatipService {
        let client = SupabaseService.shared.client
        return NovaKatipService(rpc: { function, args in
            do { return try await client.rpc(function, params: args).execute().data }
            catch let error as PostgrestError {
                guard error.code == "P0001" || error.code == "28000" else { throw NovaKatipFailure.unavailable }
                switch error.message {
                case "AUTH_REQUIRED", "ACCESS_DENIED": throw NovaKatipFailure.denied
                case "PAID_PLAN_REQUIRED": throw NovaKatipFailure.planRequired
                // Two switches guard this module, and they fail differently.
                case "FEATURE_UNAVAILABLE": throw NovaKatipFailure.featureUnavailable
                case "MODULE_UNAVAILABLE": throw NovaKatipFailure.moduleUnavailable
                case "ENDS_BEFORE_START": throw NovaKatipFailure.endsBeforeStart
                case "CONTRACT_ARCHIVED": throw NovaKatipFailure.archived
                case "IDEMPOTENCY_CONFLICT": throw NovaKatipFailure.conflict
                case "VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED", "VERSION_CONFLICT", "DOCUMENT_NOT_READY": throw NovaKatipFailure.validation
                default: throw NovaKatipFailure.unavailable
                }
            } catch {
                throw NovaKatipFailure.unavailable
            }
        }, isSession: { identity in
            guard let session = client.auth.currentSession, session.user.id == identity.userID else { return false }
            return NovaPersonnelService.sessionID(session.accessToken) == identity.sessionID
        })
    }
}
