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
        pinnedSession = URLSession(
            configuration: .default,
            delegate: serverTrustPinningDelegate,
            delegateQueue: nil
        )

        client = SupabaseClient(
            supabaseURL: RDConfig.supabaseURL,
            supabaseKey: RDConfig.supabasePublishableKey,
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: RDConfig.Auth.redirectURL,
                    flowType: .implicit,
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
        return url.path == expected.path
    }
}
