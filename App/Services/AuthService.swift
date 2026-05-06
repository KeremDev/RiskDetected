import Foundation
import Supabase

/// Auth orkestrasyonu — Apple, Google, Phone OTP, sign-out.
@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var profile: UserProfile?
    @Published var isLoading: Bool = false
    @Published var lastError: String?

    private let supabase = SupabaseService.shared
    private var stateTask: Task<Void, Never>?

    init() {
        // İlk başta cache'lenmiş session'ı oku
        session = supabase.client.auth.currentSession
        startObservingAuthChanges()
        // Cache'den session geldiyse profili hemen tazele
        if let cachedUserID = session?.user.id {
            Task { await fetchProfile(userID: cachedUserID) }
        }
    }

    deinit { stateTask?.cancel() }

    // MARK: - Public

    var isAuthenticated: Bool { session != nil }

    /// E-posta + şifre ile giriş (demo / dev).
    /// signIn'in döndürdüğü Session'dan user ID'yi alıyor — currentSession race condition yok.
    func signInWithPassword(email: String, password: String) async throws {
        lastError = nil
        let signedInSession = try await supabase.auth.signIn(email: email, password: password)
        self.session = signedInSession

        // Profili response'taki user ID ile direkt fetch et
        await fetchProfile(userID: signedInSession.user.id)
    }

    /// E-posta adresine sihirli link gönderir (passwordless).
    func sendMagicLink(email: String) async throws {
        try await supabase.auth.signInWithOTP(email: email,
                                              redirectTo: deepLinkURL())
    }

    /// Telefon numarasına SMS OTP gönderir (E.164 formatında: +905...).
    func sendPhoneOTP(phone: String) async throws {
        try await supabase.auth.signInWithOTP(phone: phone)
    }

    /// SMS OTP doğrulaması.
    func verifyPhoneOTP(phone: String, token: String) async throws {
        try await supabase.auth.verifyOTP(phone: phone, token: token, type: .sms)
    }

    /// Apple ID ile giriş — UI tarafında ASAuthorizationAppleIDCredential alındıktan sonra
    /// `idToken` ve nonce buraya iletilir.
    func signInWithApple(idToken: String, nonce: String) async throws {
        try await supabase.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
    }

    /// Google ile giriş — Google Sign-In SDK'sından alınan idToken ile.
    func signInWithGoogle(idToken: String, nonce: String? = nil) async throws {
        try await supabase.auth.signInWithIdToken(
            credentials: .init(provider: .google, idToken: idToken, nonce: nonce)
        )
    }

    /// Çıkış yapar.
    func signOut() async throws {
        try await supabase.auth.signOut()
    }

    /// Aktif kullanıcının profilini yeniler (currentUserID üzerinden — observer fallback).
    func refreshProfile() async {
        guard let userID = supabase.currentUserID else {
            self.profile = nil
            return
        }
        await fetchProfile(userID: userID)
    }

    // MARK: - Private

    /// Profile fetch'in tek kaynağı. Hatayı `lastError`'a yazıyor ki UI gösterebilsin.
    private func fetchProfile(userID: UUID) async {
        do {
            let row: UserProfile = try await supabase.client
                .from("profiles")
                .select()
                .eq("id", value: userID.uuidString)
                .single()
                .execute()
                .value

            self.profile = row
            self.lastError = nil
        } catch let DecodingError.keyNotFound(key, context) {
            let msg = "missing key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue))"
            self.lastError = "Profile decode (key): \(msg)"
        } catch let DecodingError.typeMismatch(type, context) {
            let msg = "type \(type) mismatch at \(context.codingPath.map(\.stringValue))"
            self.lastError = "Profile decode (type): \(msg)"
        } catch let DecodingError.valueNotFound(type, context) {
            let msg = "value \(type) not found at \(context.codingPath.map(\.stringValue))"
            self.lastError = "Profile decode (val): \(msg)"
        } catch let DecodingError.dataCorrupted(context) {
            let msg = "data corrupted at \(context.codingPath.map(\.stringValue)): \(context.debugDescription)"
            self.lastError = "Profile decode (corrupt): \(msg)"
        } catch {
            self.lastError = "Profile fetch: \(error.localizedDescription)"
        }
    }

    private func startObservingAuthChanges() {
        stateTask = Task { [weak self] in
            guard let self else { return }
            for await change in supabase.auth.authStateChanges {
                let newSession = change.session

                await MainActor.run {
                    self.session = newSession
                }

                if let userID = newSession?.user.id {
                    await self.fetchProfile(userID: userID)
                } else {
                    await MainActor.run { self.profile = nil }
                }
            }
        }
    }

    private func deepLinkURL() -> URL {
        URL(string: "io.supabase.riskdetected://login-callback")!
    }
}
