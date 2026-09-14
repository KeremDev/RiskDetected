import Foundation
import Supabase

extension NovaChecklistService {
    static func live() -> NovaChecklistService {
        let client = SupabaseService.shared.client
        return NovaChecklistService(rpc: { function, args in
            do { return try await client.rpc(function, params: args).execute().data }
            catch let error as PostgrestError {
                guard error.code == "P0001" || error.code == "28000" else { throw NovaChecklistFailure.unavailable }
                switch error.message {
                case "AUTH_REQUIRED", "ACCESS_DENIED": throw NovaChecklistFailure.denied
                case "PAID_PLAN_REQUIRED": throw NovaChecklistFailure.planRequired
                case "FEATURE_UNAVAILABLE": throw NovaChecklistFailure.moduleUnavailable
                case "RUN_SUBMITTED": throw NovaChecklistFailure.runSubmitted
                case "RUN_INCOMPLETE": throw NovaChecklistFailure.runIncomplete
                case "TEMPLATE_PUBLISHED": throw NovaChecklistFailure.templatePublished
                case "IDEMPOTENCY_CONFLICT": throw NovaChecklistFailure.conflict
                case "VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED": throw NovaChecklistFailure.validation
                default: throw NovaChecklistFailure.unavailable
                }
            } catch {
                throw NovaChecklistFailure.unavailable
            }
        }, isSession: { identity in
            guard let session = client.auth.currentSession, session.user.id == identity.userID else { return false }
            return NovaPersonnelService.sessionID(session.accessToken) == identity.sessionID
        })
    }
}
