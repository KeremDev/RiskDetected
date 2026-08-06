import Foundation
import NaturalLanguage
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
    let appLanguage: RDAppLanguage
    let contentLocale: RDContentLocale
}

struct SupportRequestResult: Decodable {
    let ok: Bool?
    let supportID: String?
    let deliveryStatus: String?
    let acknowledgement: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case supportID = "support_id"
        case deliveryStatus = "delivery_status"
        case acknowledgement
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
            let appLanguage: String
            let contentLocale: String
            let userMessageLanguage: String
            let preferredResponseLanguage: String

            enum CodingKeys: String, CodingKey {
                case subject
                case message
                case attachments
                case appLanguage = "app_language"
                case contentLocale = "content_locale"
                case userMessageLanguage = "user_message_language"
                case preferredResponseLanguage = "preferred_response_language"
            }
        }

        let body = Body(
            subject: input.subject,
            message: input.message,
            attachments: input.attachments.map(\.payload),
            appLanguage: input.appLanguage.rawValue,
            contentLocale: input.contentLocale.rawValue,
            userMessageLanguage: Self.detectedMessageLanguage(
                "\(input.subject)\n\(input.message)"
            ),
            preferredResponseLanguage: input.appLanguage.rawValue
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

    private static func detectedMessageLanguage(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        switch recognizer.dominantLanguage {
        case .turkish:
            return RDAppLanguage.turkish.rawValue
        case .english:
            return RDAppLanguage.english.rawValue
        default:
            return "und"
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
            let supportSuffix = decoded.supportID.map { RDLocalization.format("localizable.support.service.destek.kodu.1.39ec082a", table: .localizable, fallback: "\nDestek kodu: %1$@", arguments: [String(describing: $0)]) } ?? ""
            return ((decoded.message ?? RDLocalization.string("localizable.support.service.destek.talebi.gonderilemedi.06e0a169", table: .localizable, fallback: "Destek talebi gönderilemedi.")) + supportSuffix, decoded.supportID)
        }
        return (RDLocalization.string("localizable.support.service.destek.talebi.gonderilemedi.6b41a926", table: .localizable, fallback: "Destek talebi gönderilemedi."), nil)
    }
}
