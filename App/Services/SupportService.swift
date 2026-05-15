import Foundation
import Supabase

struct SupportAttachmentPayload: Encodable, Equatable {
    let filename: String
    let mimeType: String
    let data: String
    let sizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case filename
        case mimeType = "mime_type"
        case data
        case sizeBytes = "size_bytes"
    }
}

struct SupportAttachmentDraft: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    let mimeType: String
    let data: Data

    var sizeBytes: Int { data.count }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    var payload: SupportAttachmentPayload {
        SupportAttachmentPayload(
            filename: filename,
            mimeType: mimeType,
            data: data.base64EncodedString(),
            sizeBytes: data.count
        )
    }
}

struct SupportRequestInput {
    let subject: String
    let message: String
    let attachments: [SupportAttachmentDraft]
}

struct SupportRequestResult: Decodable {
    let ok: Bool?
    let supportID: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case supportID = "support_id"
    }
}

final class SupportService {
    static let shared = SupportService()

    private let supabase = SupabaseService.shared

    private init() {}

    func send(_ input: SupportRequestInput) async throws -> SupportRequestResult {
        struct Body: Encodable {
            let subject: String
            let message: String
            let attachments: [SupportAttachmentPayload]
        }

        let body = Body(
            subject: input.subject,
            message: input.message,
            attachments: input.attachments.map(\.payload)
        )

        do {
            return try await supabase.functions.invoke(
                RDConfig.supportContactFunctionName,
                options: FunctionInvokeOptions(body: body)
            )
        } catch let FunctionsError.httpError(_, data) {
            let payload = Self.functionErrorPayload(from: data)
            throw NSError(
                domain: "RiskDetected.SupportService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: payload.message]
            )
        }
    }

    private static func functionErrorPayload(from data: Data) -> (message: String, supportID: String?) {
        struct ErrorBody: Decodable {
            let message: String?
            let supportID: String?

            enum CodingKeys: String, CodingKey {
                case message
                case supportID = "support_id"
            }
        }

        if let decoded = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            let supportSuffix = decoded.supportID.map { "\nDestek kodu: \($0)" } ?? ""
            return ((decoded.message ?? "Destek talebi gönderilemedi.") + supportSuffix, decoded.supportID)
        }
        return ("Destek talebi gönderilemedi.", nil)
    }
}
