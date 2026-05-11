import Foundation
import Supabase
import OSLog
import UIKit

/// Auth orkestrasyonu — Apple, Google, Email OTP, sign-out.
@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var profile: UserProfile?
    @Published var isLoading: Bool = false
    @Published var lastError: String?

    private let supabase = SupabaseService.shared
    private var stateTask: Task<Void, Never>?
    private static let logger = Logger(subsystem: "com.riskdetected.app", category: "AuthService")

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

    /// E-posta adresine tek kullanımlık doğrulama kodu gönderir.
    func sendEmailOTP(email: String) async throws {
        lastError = nil
        try await supabase.auth.signInWithOTP(email: email, redirectTo: deepLinkURL())
    }

    /// E-posta doğrulama kodunu onaylar ve Supabase oturumu açar.
    func verifyEmailOTP(email: String, token: String) async throws {
        lastError = nil
        let response = try await verifyEmailOTPWithSupportedTypes(email: email, token: token)
        if let verifiedSession = response.session {
            self.session = verifiedSession
            await fetchProfile(userID: verifiedSession.user.id)
        }
    }

    /// Telefon numarasına SMS OTP gönderir (E.164 formatında: +905...).
    func sendPhoneOTP(phone: String) async throws {
        lastError = nil
        try await supabase.auth.signInWithOTP(phone: phone)
    }

    /// SMS OTP doğrulaması.
    func verifyPhoneOTP(phone: String, token: String) async throws {
        lastError = nil
        let response = try await supabase.auth.verifyOTP(phone: phone, token: token, type: .sms)
        if let verifiedSession = response.session {
            self.session = verifiedSession
            await fetchProfile(userID: verifiedSession.user.id)
        }
    }

    /// Firebase Phone Auth doğrulaması tamamlandıktan sonra Firebase ID tokenını
    /// backend bridge'e gönderir ve dönen Supabase bridge hesabıyla oturum açar.
    func signInWithFirebasePhoneIDToken(_ idToken: String) async throws {
        struct Body: Encodable {
            let id_token: String
        }

        struct BridgeResponse: Decodable {
            let email: String
            let password: String
            let userID: UUID
            let phone: String

            enum CodingKeys: String, CodingKey {
                case email
                case password
                case userID = "user_id"
                case phone
            }
        }

        lastError = nil
        let response: BridgeResponse = try await supabase.functions.invoke(
            RDConfig.firebasePhoneBridgeFunctionName,
            options: FunctionInvokeOptions(body: Body(id_token: idToken))
        )

        let signedInSession = try await supabase.auth.signIn(
            email: response.email,
            password: response.password
        )
        self.session = signedInSession
        await fetchProfile(userID: response.userID)
    }

    /// Apple ID ile giriş — UI tarafında ASAuthorizationAppleIDCredential alındıktan sonra
    /// `idToken` ve nonce buraya iletilir.
    func signInWithApple(idToken: String, nonce: String) async throws {
        lastError = nil
        let signedInSession = try await supabase.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        self.session = signedInSession
        await fetchProfile(userID: signedInSession.user.id)
    }

    /// Google ile giriş — Google Sign-In SDK'sından alınan idToken ile.
    func signInWithGoogle(idToken: String, nonce: String? = nil) async throws {
        lastError = nil
        let signedInSession = try await supabase.auth.signInWithIdToken(
            credentials: .init(provider: .google, idToken: idToken, nonce: nonce)
        )
        self.session = signedInSession
        await fetchProfile(userID: signedInSession.user.id)
    }

    /// Google OAuth web flow — GoogleSignIn SDK olmadan Supabase PKCE/OAuth akışını kullanır.
    func signInWithGoogleOAuth() async throws {
        lastError = nil
        let signedInSession = try await supabase.auth.signInWithOAuth(
            provider: .google,
            redirectTo: deepLinkURL()
        )
        self.session = signedInSession
        await fetchProfile(userID: signedInSession.user.id)
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

    func updateProfile(_ input: ProfileUpdateInput) async throws {
        guard let user = supabase.auth.currentUser else {
            throw NSError(
                domain: "RiskDetected.AuthService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Oturum bulunamadı."]
            )
        }

        let payload = ProfileUpdatePayload(
            id: user.id.uuidString,
            email: user.email,
            fullName: input.fullName.nilIfBlank,
            initials: Self.initials(for: input.fullName),
            title: input.title.nilIfBlank,
            certificateNumber: input.certificateNumber.nilIfBlank,
            companyName: input.companyName.nilIfBlank,
            companyLogoURL: input.companyLogoPath,
            phone: input.phone.nilIfBlank,
            preferredMethod: input.preferredMethod?.rawValue
        )

        try await supabase.client
            .from("profiles")
            .upsert(payload, onConflict: "id")
            .execute()

        await fetchProfile(userID: user.id)
    }

    func uploadProfileLogo(_ image: UIImage) async throws -> String {
        guard let userID = supabase.currentUserID else {
            throw NSError(
                domain: "RiskDetected.AuthService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Oturum bulunamadı."]
            )
        }
        guard let data = image.normalizedJPEG(maxDimension: 900, compressionQuality: 0.82) else {
            throw NSError(
                domain: "RiskDetected.AuthService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Logo dosyası hazırlanamadı."]
            )
        }

        let path = "\(userID.uuidString.lowercased())/profile-logo.jpg"
        _ = try await supabase.storage
            .from(RDConfig.Bucket.logos)
            .upload(
                path,
                data: data,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )
        return path
    }

    func profileLogoImage(path: String) async throws -> UIImage? {
        let data = try await supabase.storage
            .from(RDConfig.Bucket.logos)
            .download(path: path)
        return UIImage(data: data)
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

    private func verifyEmailOTPWithSupportedTypes(email: String, token: String) async throws -> AuthResponse {
        let types: [EmailOTPType] = [.email, .magiclink, .signup]
        var lastError: Error?

        for (index, type) in types.enumerated() {
            do {
                return try await supabase.auth.verifyOTP(email: email, token: token, type: type)
            } catch {
                lastError = error
                guard index < types.count - 1, Self.canRetryEmailOTPType(after: error) else {
                    break
                }
            }
        }

        throw lastError ?? NSError(
            domain: "RiskDetected.AuthService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "E-posta doğrulama kodu doğrulanamadı."]
        )
    }

    private static func canRetryEmailOTPType(after error: Error) -> Bool {
        let lower = error.localizedDescription.lowercased(with: Locale(identifier: "tr_TR"))
        if lower.contains("rate") ||
            lower.contains("too many") ||
            lower.contains("429") ||
            lower.contains("over_email_send_rate_limit")
        {
            return false
        }
        return true
    }

    static func logAuthError(_ message: AppErrorMessage, operation: String, email: String? = nil) {
        logger.error("Auth error support=\(message.supportID, privacy: .public) operation=\(operation, privacy: .public) category=\(message.category.rawValue, privacy: .public) email=\(email ?? "-", privacy: .private(mask: .hash)) message=\(message.message, privacy: .public)")
    }

    private static func initials(for name: String) -> String? {
        let parts = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? nil : initials
    }
}

struct ProfileUpdateInput {
    var fullName: String
    var title: String
    var certificateNumber: String
    var companyName: String
    var phone: String
    var preferredMethod: RiskMethodWire?
    var companyLogoPath: String?
}

private struct ProfileUpdatePayload: Encodable {
    let id: String
    let email: String?
    let fullName: String?
    let initials: String?
    let title: String?
    let certificateNumber: String?
    let companyName: String?
    let companyLogoURL: String?
    let phone: String?
    let preferredMethod: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
        case initials
        case title
        case certificateNumber = "certificate_number"
        case companyName = "company_name"
        case companyLogoURL = "company_logo_url"
        case phone
        case preferredMethod = "preferred_method"
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension UIImage {
    func normalizedJPEG(maxDimension: CGFloat, compressionQuality: CGFloat) -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let normalized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return normalized.jpegData(compressionQuality: compressionQuality)
    }
}
