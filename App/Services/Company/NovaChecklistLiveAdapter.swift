import Foundation
import Supabase

extension NovaChecklistService {
    static func live() -> NovaChecklistService {
        let client = SupabaseService.shared.client
        let ticket = NovaExpertTransport.shared.capture()
        return NovaChecklistService(rpc: { function, args in
            do { return try await NovaExpertTransport.shared.execute(function, params: args, ticket: ticket) }
            catch let error as PostgrestError {
                guard error.code == "P0001" || error.code == "28000" else { throw NovaChecklistFailure.unavailable }
                switch error.message {
                case "AUTH_REQUIRED", "ACCESS_DENIED": throw NovaChecklistFailure.denied
                case "PAID_PLAN_REQUIRED": throw NovaChecklistFailure.planRequired
                case "FEATURE_UNAVAILABLE": throw NovaChecklistFailure.moduleUnavailable
                case "RUN_SUBMITTED": throw NovaChecklistFailure.runSubmitted
                case "RUN_INCOMPLETE": throw NovaChecklistFailure.runIncomplete
                case "TEMPLATE_PUBLISHED": throw NovaChecklistFailure.templatePublished
                case "IDEMPOTENCY_CONFLICT", "CHECKLIST_CONFLICT": throw NovaChecklistFailure.conflict
                case "DUPLICATE_CHECKLIST_ITEM": throw NovaChecklistFailure.duplicateItem
                case "COMPANY_REQUIRED_FOR_NONCONFORMITY": throw NovaChecklistFailure.companyRequired
                case "EXPLANATION_REQUIRED": throw NovaChecklistFailure.explanationRequired
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
