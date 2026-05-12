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
        if session?.user.id != nil {
            Task { await ensureProfile(for: supabase.client.auth.currentSession?.user) }
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
        await finishSignIn(with: signedInSession)
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
            await finishSignIn(with: verifiedSession)
        }
    }

    /// Apple ID ile giriş — UI tarafında ASAuthorizationAppleIDCredential alındıktan sonra
    /// `idToken` ve nonce buraya iletilir.
    func signInWithApple(idToken: String, nonce: String, email: String? = nil, fullName: String? = nil) async throws {
        lastError = nil
        let signedInSession = try await supabase.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        await finishSignIn(with: signedInSession, emailFallback: email, fullNameFallback: fullName)
    }

    /// Google ile giriş — Google Sign-In SDK'sından alınan idToken ile.
    func signInWithGoogle(
        idToken: String,
        accessToken: String? = nil,
        nonce: String? = nil,
        emailFallback: String? = nil,
        fullNameFallback: String? = nil
    ) async throws {
        lastError = nil
        let signedInSession = try await supabase.auth.signInWithIdToken(
            credentials: .init(provider: .google, idToken: idToken, accessToken: accessToken, nonce: nonce)
        )
        await finishSignIn(
            with: signedInSession,
            emailFallback: emailFallback,
            fullNameFallback: fullNameFallback
        )
    }

    /// Google OAuth web flow — GoogleSignIn SDK olmadan Supabase PKCE/OAuth akışını kullanır.
    func signInWithGoogleOAuth() async throws {
        lastError = nil
        let signedInSession = try await supabase.auth.signInWithOAuth(
            provider: .google,
            redirectTo: RDConfig.Auth.redirectURL
        )
        await finishSignIn(with: signedInSession)
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
        let result = await fetchProfile(userID: userID)
        if case .missing = result {
            await ensureProfile(for: supabase.client.auth.currentSession?.user)
        }
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
    private func finishSignIn(with signedInSession: Session, emailFallback: String? = nil, fullNameFallback: String? = nil) async {
        self.session = signedInSession
        await ensureProfile(
            for: signedInSession.user,
            emailFallback: emailFallback,
            fullNameFallback: fullNameFallback
        )
    }

    private func ensureProfile(for user: User?, emailFallback: String? = nil, fullNameFallback: String? = nil) async {
        guard let user else { return }

        switch await fetchProfile(userID: user.id) {
        case .found(let profile):
            await backfillProviderIdentityIfNeeded(
                for: user,
                profile: profile,
                emailFallback: emailFallback,
                fullNameFallback: fullNameFallback
            )
        case .failed:
            return
        case .missing:
            await createDefaultProfile(
                for: user,
                emailFallback: emailFallback,
                fullNameFallback: fullNameFallback
            )
        }
    }

    @discardableResult
    private func fetchProfile(userID: UUID) async -> ProfileFetchResult {
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
            return .found(row)
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
        } catch let error as PostgrestError where Self.isMissingProfileError(error) {
            self.profile = nil
            self.lastError = nil
            return .missing
        } catch {
            self.lastError = "Profile fetch: \(error.localizedDescription)"
        }
        return .failed
    }

    private func createDefaultProfile(for user: User, emailFallback: String? = nil, fullNameFallback: String? = nil) async {
        let resolvedFullName = Self.providerFullName(for: user, fallback: fullNameFallback)
        let payload = ProfileBootstrapPayload(
            id: user.id.uuidString,
            email: Self.providerEmail(for: user, fallback: emailFallback),
            fullName: resolvedFullName,
            initials: resolvedFullName.flatMap(Self.initials(for:)),
            tier: SubscriptionTier.free.rawValue
        )

        do {
            try await supabase.client
                .from("profiles")
                .insert(payload)
                .execute()
            await fetchProfile(userID: user.id)
        } catch {
            // If a profile appeared between fetch and insert, read it again instead of surfacing a false failure.
            if case .found(let profile) = await fetchProfile(userID: user.id) {
                await backfillProviderIdentityIfNeeded(
                    for: user,
                    profile: profile,
                    emailFallback: emailFallback,
                    fullNameFallback: fullNameFallback
                )
                return
            }
            self.lastError = "Profile bootstrap: \(error.localizedDescription)"
        }
    }

    private func backfillProviderIdentityIfNeeded(
        for user: User,
        profile: UserProfile,
        emailFallback: String? = nil,
        fullNameFallback: String? = nil
    ) async {
        let resolvedEmail = Self.providerEmail(for: user, fallback: emailFallback)
        let resolvedFullName = Self.providerFullName(for: user, fallback: fullNameFallback)

        let shouldUpdateEmail = profile.email?.nilIfBlank == nil && resolvedEmail != nil
        let shouldUpdateName = resolvedFullName.map {
            Self.shouldBackfillFullName(profile.fullName, email: resolvedEmail, providerFullName: $0)
        } ?? false

        guard shouldUpdateEmail || shouldUpdateName else { return }

        let payload = ProfileIdentityPatchPayload(
            email: shouldUpdateEmail ? resolvedEmail : profile.email,
            fullName: shouldUpdateName ? resolvedFullName : profile.fullName,
            initials: shouldUpdateName ? resolvedFullName.flatMap(Self.initials(for:)) : profile.initials
        )

        do {
            try await supabase.client
                .from("profiles")
                .update(payload)
                .eq("id", value: user.id.uuidString)
                .execute()
            await fetchProfile(userID: user.id)
        } catch {
            Self.logger.warning("Profile provider identity backfill failed: \(error.localizedDescription, privacy: .public)")
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

                if newSession?.user.id != nil {
                    await self.ensureProfile(for: newSession?.user)
                } else {
                    await MainActor.run { self.profile = nil }
                }
            }
        }
    }

    private func deepLinkURL() -> URL {
        RDConfig.Auth.redirectURL
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

    private static func isMissingProfileError(_ error: PostgrestError) -> Bool {
        if error.code == "PGRST116" { return true }
        let lower = error.message.lowercased(with: Locale(identifier: "en_US_POSIX"))
        return lower.contains("0 rows") || lower.contains("no rows")
    }

    private static func providerEmail(for user: User, fallback: String?) -> String? {
        user.email?.nilIfBlank ?? fallback?.nilIfBlank ?? metadataString("email", in: user.userMetadata)
    }

    private static func providerFullName(for user: User, fallback: String?) -> String? {
        if let fallback = fallback?.nilIfBlank { return fallback }

        let metadata = user.userMetadata
        if let fullName = metadataString("full_name", in: metadata) { return fullName }
        if let name = metadataString("name", in: metadata) { return name }
        if let displayName = metadataString("display_name", in: metadata) { return displayName }

        let givenName = metadataString("given_name", in: metadata)
        let familyName = metadataString("family_name", in: metadata)
        let combined = [givenName, familyName]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: " ")
            .nilIfBlank
        return combined
    }

    private static func metadataString(_ key: String, in metadata: [String: AnyJSON]) -> String? {
        metadata[key]?.stringValue?.nilIfBlank
    }

    private static func shouldBackfillFullName(
        _ currentFullName: String?,
        email: String?,
        providerFullName: String
    ) -> Bool {
        guard providerFullName.nilIfBlank != nil else { return false }
        guard let current = currentFullName?.nilIfBlank else { return true }

        let currentNormalized = current.lowercased(with: Locale(identifier: "en_US_POSIX"))
        let emailLocalPart = email?
            .split(separator: "@", maxSplits: 1)
            .first
            .map(String.init)?
            .lowercased(with: Locale(identifier: "en_US_POSIX"))

        return emailLocalPart == currentNormalized
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

private enum ProfileFetchResult {
    case found(UserProfile)
    case missing
    case failed
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

private struct ProfileBootstrapPayload: Encodable {
    let id: String
    let email: String?
    let fullName: String?
    let initials: String?
    let tier: String

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
        case initials
        case tier
    }
}

private struct ProfileIdentityPatchPayload: Encodable {
    let email: String?
    let fullName: String?
    let initials: String?

    enum CodingKeys: String, CodingKey {
        case email
        case fullName = "full_name"
        case initials
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
