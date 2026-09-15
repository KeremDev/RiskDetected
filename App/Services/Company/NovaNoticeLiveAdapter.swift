import Foundation
import Supabase

extension NovaNoticeService {
    static func live() -> NovaNoticeService {
        let client = SupabaseService.shared.client
        return NovaNoticeService(rpc: { function, args in
            do { return try await client.rpc(function, params: args).execute().data }
            catch let error as PostgrestError {
                guard error.code == "P0001" || error.code == "28000" else { throw NovaNoticeFailure.unavailable }
                switch error.message {
                case "AUTH_REQUIRED", "ACCESS_DENIED": throw NovaNoticeFailure.denied
                case "FEATURE_UNAVAILABLE": throw NovaNoticeFailure.featureUnavailable
                // The situation moved on while the panel was open.
                case "NOTICE_NOT_FOUND": throw NovaNoticeFailure.notFound
                case "VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED": throw NovaNoticeFailure.validation
                default: throw NovaNoticeFailure.unavailable
                }
            } catch {
                throw NovaNoticeFailure.unavailable
            }
        }, isSession: { identity in
            guard let session = client.auth.currentSession, session.user.id == identity.userID else { return false }
            return NovaPersonnelService.sessionID(session.accessToken) == identity.sessionID
        })
    }
}
