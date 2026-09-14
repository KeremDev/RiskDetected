import Foundation
import Supabase

extension NovaEquipmentCheckService {
    static func live() -> NovaEquipmentCheckService {
        let client = SupabaseService.shared.client
        return NovaEquipmentCheckService(rpc: { function, args in
            do { return try await client.rpc(function, params: args).execute().data }
            catch let error as PostgrestError {
                guard error.code == "P0001" || error.code == "28000" else { throw NovaEquipmentFailure.unavailable }
                switch error.message {
                case "AUTH_REQUIRED", "ACCESS_DENIED": throw NovaEquipmentFailure.denied
                case "PAID_PLAN_REQUIRED": throw NovaEquipmentFailure.planRequired
                // Two switches guard this module, and they fail differently:
                // the phase is closed, or this module alone is.
                case "FEATURE_UNAVAILABLE", "MODULE_UNAVAILABLE": throw NovaEquipmentFailure.moduleUnavailable
                case "PERFORMED_IN_THE_FUTURE": throw NovaEquipmentFailure.futureReport
                case "DUE_BEFORE_REPORT": throw NovaEquipmentFailure.dueBeforeReport
                case "DUE_ON_A_FAILED_CHECK": throw NovaEquipmentFailure.dueOnFailedCheck
                case "IDEMPOTENCY_CONFLICT": throw NovaEquipmentFailure.conflict
                case "VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED": throw NovaEquipmentFailure.validation
                default: throw NovaEquipmentFailure.unavailable
                }
            } catch {
                // A serial that is already on file is refused by a unique index
                // rather than by a named error, so the message is what says so.
                if String(describing: error).contains("equipment_items_company_id_serial_tag_key") {
                    throw NovaEquipmentFailure.duplicateSerial
                }
                throw NovaEquipmentFailure.unavailable
            }
        }, isSession: { identity in
            guard let session = client.auth.currentSession, session.user.id == identity.userID else { return false }
            return NovaPersonnelService.sessionID(session.accessToken) == identity.sessionID
        })
    }
}
