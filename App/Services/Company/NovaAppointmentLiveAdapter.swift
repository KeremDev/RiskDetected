import Foundation
import Supabase

extension NovaAppointmentService {
    static func live() -> NovaAppointmentService {
        let client = SupabaseService.shared.client
        let ticket = NovaExpertTransport.shared.capture()
        return NovaAppointmentService(rpc: { function, args in
            do { return try await NovaExpertTransport.shared.execute(function, params: args, ticket: ticket) }
            catch let error as PostgrestError {
                guard error.code == "P0001" || error.code == "28000" else { throw NovaAppointmentFailure.unavailable }
                switch error.message {
                case "AUTH_REQUIRED", "ACCESS_DENIED": throw NovaAppointmentFailure.denied
                case "PAID_PLAN_REQUIRED": throw NovaAppointmentFailure.planRequired
                // Two switches guard this module, and they fail differently.
                case "FEATURE_UNAVAILABLE": throw NovaAppointmentFailure.featureUnavailable
                case "MODULE_UNAVAILABLE": throw NovaAppointmentFailure.moduleUnavailable
                case "APPOINTMENT_OVERLAP": throw NovaAppointmentFailure.overlap
                case "BASIS_REQUIRED": throw NovaAppointmentFailure.basisRequired
                case "IDEMPOTENCY_CONFLICT": throw NovaAppointmentFailure.conflict
                case "VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED": throw NovaAppointmentFailure.validation
                default: throw NovaAppointmentFailure.unavailable
                }
            } catch {
                throw NovaAppointmentFailure.unavailable
            }
        }, isSession: { identity in
            guard let session = client.auth.currentSession, session.user.id == identity.userID else { return false }
            return NovaPersonnelService.sessionID(session.accessToken) == identity.sessionID
        })
    }
}
