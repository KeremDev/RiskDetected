import Foundation
import Supabase

/// Tek noktadan erişilen Supabase istemcisi (Auth + DB + Storage + Functions).
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient
    private let serverTrustPinningDelegate: ServerTrustPinningDelegate
    private let pinnedSession: URLSession

    private init() {
        serverTrustPinningDelegate = ServerTrustPinningDelegate()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = true

        pinnedSession = URLSession(
            configuration: configuration,
            delegate: serverTrustPinningDelegate,
            delegateQueue: nil
        )

        client = SupabaseClient(
            supabaseURL: RDConfig.supabaseURL,
            supabaseKey: RDConfig.supabasePublishableKey,
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: RDConfig.Auth.redirectURL,
                    flowType: .pkce,
                    emitLocalSessionAsInitialSession: true
                ),
                global: .init(session: pinnedSession)
            )
        )
    }

    // Convenience erişim
    var auth: AuthClient { client.auth }
    var storage: SupabaseStorageClient { client.storage }
    var functions: FunctionsClient { client.functions }

    /// Aktif kullanıcı id (yoksa nil).
    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    func handleAuthURL(_ url: URL) {
        guard Self.isExpectedAuthCallback(url) else { return }
        client.auth.handle(url)
    }

    private static func isExpectedAuthCallback(_ url: URL) -> Bool {
        let expected = RDConfig.Auth.redirectURL
        guard url.scheme == expected.scheme else { return false }
        guard url.host == expected.host else { return false }
        guard url.path == expected.path else { return false }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryNames = Set(components?.queryItems?.map(\.name) ?? [])
        let fragment = components?.fragment?.lowercased() ?? ""
        guard !fragment.contains("access_token=") else { return false }
        guard !fragment.contains("refresh_token=") else { return false }
        return queryNames.contains("code") || queryNames.contains("error") ||
            queryNames.contains("error_description") || queryNames.contains("error_code")
    }
}
