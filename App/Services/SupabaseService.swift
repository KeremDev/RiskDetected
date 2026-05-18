import Foundation
import Supabase

/// Tek noktadan erişilen Supabase istemcisi (Auth + DB + Storage + Functions).
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: RDConfig.supabaseURL,
            supabaseKey: RDConfig.supabasePublishableKey,
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: RDConfig.Auth.redirectURL,
                    emitLocalSessionAsInitialSession: true
                )
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
        client.auth.handle(url)
    }
}
