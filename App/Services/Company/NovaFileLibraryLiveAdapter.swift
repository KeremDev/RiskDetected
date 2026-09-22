import Foundation
import Supabase

extension NovaFileLibraryService {
    static func live() -> NovaFileLibraryService {
        let client = SupabaseService.shared.client
        let ticket = NovaExpertTransport.shared.capture()
        return NovaFileLibraryService(rpc: { function, args in
            do { return try await NovaExpertTransport.shared.execute(function, params: args, ticket: ticket) }
            catch let error as PostgrestError {
                guard error.code == "P0001" || error.code == "28000" else { throw NovaFileFailure.unavailable }
                switch error.message {
                case "AUTH_REQUIRED", "ACCESS_DENIED": throw NovaFileFailure.denied
                case "PAID_PLAN_REQUIRED": throw NovaFileFailure.planRequired
                // The server refused the format before an upload was opened, so
                // the screen can say which file it was rather than failing vaguely.
                case "UNSUPPORTED_FORMAT": throw NovaFileFailure.unsupportedFormat
                case "SIZE_LIMIT": throw NovaFileFailure.tooLarge
                case "UPLOAD_NOT_CANCELLABLE": throw NovaFileFailure.notCancellable
                case "VERSION_CONFLICT": throw NovaFileFailure.versionConflict
                case "IDEMPOTENCY_CONFLICT": throw NovaFileFailure.conflict
                case "VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED": throw NovaFileFailure.validation
                default: throw NovaFileFailure.unavailable
                }
            }
        }, upload: { bucket, path, data, fileExtension in
            try NovaExpertTransport.shared.validate(ticket)
            do {
                // upsert stays off: the quarantine bucket has no update policy,
                // so bytes that were already checked can never be swapped.
                _ = try await client.storage.from(bucket).upload(
                    path, data: data,
                    options: FileOptions(contentType: contentType(fileExtension), upsert: false))
                try NovaExpertTransport.shared.validate(ticket)
            } catch {
                throw NovaFileFailure.uploadFailed
            }
        }, inspect: { entryID in
            try NovaExpertTransport.shared.validate(ticket)
            struct Request: Encodable { let entry_id: String; let workspace_id: String? }
            struct Answer: Decodable { let state: String? }
            do {
                let _: Answer = try await client.functions.invoke(
                    "isg-file-inspect",
                    options: FunctionInvokeOptions(body: Request(entry_id: entryID.uuidString.lowercased(),
                        workspace_id: ticket?.access.workspaceID?.uuidString.lowercased())))
                try NovaExpertTransport.shared.validate(ticket)
            } catch {
                // The upload keeps whatever state it really reached. Nothing here
                // may report the file as cleared because the call did not land.
                throw NovaFileFailure.inspectionUnavailable
            }
        }, download: { bucket, path in
            try NovaExpertTransport.shared.validate(ticket)
            do {
                let data = try await client.storage.from(bucket).download(path: path)
                try NovaExpertTransport.shared.validate(ticket)
                return data
            }
            catch { throw NovaFileFailure.unavailable }
        }, isSession: { identity in
            guard (try? NovaExpertTransport.shared.validate(ticket)) != nil else { return false }
            guard let session = client.auth.currentSession, session.user.id == identity.userID else { return false }
            return NovaPersonnelService.sessionID(session.accessToken) == identity.sessionID
        })
    }

    /// Only a hint for the transfer. The real type is decided from the bytes by
    /// the inspector, and a wrong hint cannot get a file accepted.
    private static func contentType(_ fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "csv": return "text/csv"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        case "heic", "heif": return "image/heic"
        default: return "application/octet-stream"
        }
    }
}
