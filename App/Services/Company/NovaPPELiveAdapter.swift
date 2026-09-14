import Foundation
import Supabase

extension NovaPPEService {
    static func live() -> NovaPPEService {
        let client = SupabaseService.shared.client
        return NovaPPEService(rpc: { function, args in
            do { return try await client.rpc(function, params: args).execute().data }
            catch let error as PostgrestError {
                guard error.code == "P0001" || error.code == "28000" else { throw NovaPPEFailure.unavailable }
                switch error.message {
                case "AUTH_REQUIRED", "ACCESS_DENIED": throw NovaPPEFailure.denied
                case "PAID_PLAN_REQUIRED": throw NovaPPEFailure.planRequired
                // Two switches guard this module, and they fail differently.
                case "FEATURE_UNAVAILABLE": throw NovaPPEFailure.featureUnavailable
                case "MODULE_UNAVAILABLE": throw NovaPPEFailure.moduleUnavailable
                case "HANDED_IN_THE_FUTURE": throw NovaPPEFailure.handedInFuture
                case "RETURNED_IN_THE_FUTURE": throw NovaPPEFailure.returnedInFuture
                case "RETURN_BEFORE_HANDOVER": throw NovaPPEFailure.returnBeforeHandover
                case "RETURN_EXCEEDS_HANDOVER": throw NovaPPEFailure.returnExceedsHandover
                case "IDEMPOTENCY_CONFLICT": throw NovaPPEFailure.conflict
                case "VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED": throw NovaPPEFailure.validation
                default: throw NovaPPEFailure.unavailable
                }
            } catch {
                throw NovaPPEFailure.unavailable
            }
        }, isSession: { identity in
            guard let session = client.auth.currentSession, session.user.id == identity.userID else { return false }
            return NovaPersonnelService.sessionID(session.accessToken) == identity.sessionID
        })
    }
}
