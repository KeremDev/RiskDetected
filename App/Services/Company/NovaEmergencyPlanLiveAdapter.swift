import Foundation
import Supabase

extension NovaEmergencyPlanService {
    static func live() -> NovaEmergencyPlanService {
        let client = SupabaseService.shared.client
        let ticket = NovaExpertTransport.shared.capture()
        return NovaEmergencyPlanService(rpc: { function, args in
            do { return try await NovaExpertTransport.shared.execute(function, params: args, ticket: ticket) }
            catch let error as PostgrestError {
                guard error.code == "P0001" || error.code == "28000" else { throw NovaEmergencyFailure.unavailable }
                switch error.message {
                case "AUTH_REQUIRED", "ACCESS_DENIED": throw NovaEmergencyFailure.denied
                case "PAID_PLAN_REQUIRED": throw NovaEmergencyFailure.planRequired
                // Two switches guard this module, and they fail differently:
                // the phase is closed, or this module alone is.
                case "FEATURE_UNAVAILABLE": throw NovaEmergencyFailure.featureUnavailable
                case "MODULE_UNAVAILABLE": throw NovaEmergencyFailure.moduleUnavailable
                case "PREPARED_IN_THE_FUTURE": throw NovaEmergencyFailure.preparedInFuture
                case "TEAM_ROLE_UNKNOWN": throw NovaEmergencyFailure.roleUnknown
                case "IDEMPOTENCY_CONFLICT": throw NovaEmergencyFailure.conflict
                case "VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED": throw NovaEmergencyFailure.validation
                default: throw NovaEmergencyFailure.unavailable
                }
            } catch {
                throw NovaEmergencyFailure.unavailable
            }
        }, isSession: { identity in
            guard let session = client.auth.currentSession, session.user.id == identity.userID else { return false }
            return NovaPersonnelService.sessionID(session.accessToken) == identity.sessionID
        })
    }
}
