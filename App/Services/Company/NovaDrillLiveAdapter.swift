import Foundation
import Supabase

extension NovaDrillService {
    static func live() -> NovaDrillService {
        let client = SupabaseService.shared.client
        let ticket = NovaExpertTransport.shared.capture()
        return NovaDrillService(rpc: { function, args in
            do { return try await NovaExpertTransport.shared.execute(function, params: args, ticket: ticket) }
            catch let error as PostgrestError {
                guard error.code == "P0001" || error.code == "28000" else { throw NovaDrillFailure.unavailable }
                switch error.message {
                case "AUTH_REQUIRED", "ACCESS_DENIED": throw NovaDrillFailure.denied
                case "PAID_PLAN_REQUIRED": throw NovaDrillFailure.planRequired
                // Two switches guard this module, and they fail differently.
                case "FEATURE_UNAVAILABLE": throw NovaDrillFailure.featureUnavailable
                case "MODULE_UNAVAILABLE": throw NovaDrillFailure.moduleUnavailable
                case "PERFORMED_IN_THE_FUTURE": throw NovaDrillFailure.performedInFuture
                case "PARTICIPANT_OUT_OF_SCOPE": throw NovaDrillFailure.participantOutOfScope
                case "DRILL_PERFORMED": throw NovaDrillFailure.alreadyPerformed
                case "IDEMPOTENCY_CONFLICT": throw NovaDrillFailure.conflict
                case "VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED": throw NovaDrillFailure.validation
                default: throw NovaDrillFailure.unavailable
                }
            } catch {
                throw NovaDrillFailure.unavailable
            }
        }, isSession: { identity in
            guard let session = client.auth.currentSession, session.user.id == identity.userID else { return false }
            return NovaPersonnelService.sessionID(session.accessToken) == identity.sessionID
        })
    }
}
