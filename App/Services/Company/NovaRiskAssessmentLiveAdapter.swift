import Foundation
import Supabase

extension NovaRiskAssessmentService {
    static func live() -> NovaRiskAssessmentService {
        let client = SupabaseService.shared.client
        return NovaRiskAssessmentService(rpc: { function, args in
            do { return try await client.rpc(function, params: args).execute().data }
            catch let error as PostgrestError {
                guard error.code == "P0001" || error.code == "28000" else { throw NovaRiskFailure.unavailable }
                switch error.message {
                case "AUTH_REQUIRED", "ACCESS_DENIED": throw NovaRiskFailure.denied
                case "PAID_PLAN_REQUIRED": throw NovaRiskFailure.planRequired
                case "FEATURE_UNAVAILABLE": throw NovaRiskFailure.moduleUnavailable
                case "ASSESSMENT_DATE_IN_FUTURE": throw NovaRiskFailure.dateInFuture
                case "ASSESSMENT_DATE_IMMUTABLE": throw NovaRiskFailure.dateImmutable
                case "DRAFT_ALREADY_OPEN": throw NovaRiskFailure.draftOpen
                case "VERSION_FINALIZED": throw NovaRiskFailure.versionFinalized
                case "RULE_NEEDS_REVIEW": throw NovaRiskFailure.ruleNeedsReview
                case "VERSION_CONFLICT", "IDEMPOTENCY_CONFLICT": throw NovaRiskFailure.conflict
                case "VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED": throw NovaRiskFailure.validation
                default: throw NovaRiskFailure.unavailable
                }
            } catch {
                throw NovaRiskFailure.unavailable
            }
        }, isSession: { identity in
            guard let session = client.auth.currentSession, session.user.id == identity.userID else { return false }
            return NovaPersonnelService.sessionID(session.accessToken) == identity.sessionID
        })
    }
}
