import Foundation
import Supabase

struct WelcomeEmailResult: Decodable {
    let ok: Bool?
    let deliveryStatus: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case deliveryStatus = "delivery_status"
    }
}

final class WelcomeEmailService {
    static let shared = WelcomeEmailService()

    private let supabase = SupabaseService.shared

    private init() {}

    func sendIfNeeded() async throws -> WelcomeEmailResult {
        struct Body: Encodable {}

        return try await supabase.functions.invoke(
            RDConfig.sendWelcomeEmailFunctionName,
            options: FunctionInvokeOptions(body: Body())
        )
    }
}
