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

    private static let installMarkerKey = "rd.install.marker.v1"
    private let supabase = SupabaseService.shared
    private var stateTask: Task<Void, Never>?
    private var deviceRegionCaptureInFlightUserIDs = Set<UUID>()
    private var deviceRegionCaptureCompletedUserIDs = Set<UUID>()
    private static let logger = Logger(subsystem: "com.riskdetected.app", category: "AuthService")

    init() {
        #if DEBUG
        if Self.isUITestMainLaunch {
            session = nil
            profile = nil
            Self.clearLocalSupabaseSessionSynchronously(using: supabase)
            return
        }
        #endif
        let isFreshInstall = Self.markInstallAndDetectFreshInstall()
        // İlk başta cache'lenmiş session'ı oku. iOS Keychain uygulama silinse bile
        // kalabildiği için fresh install'da eski Supabase session'ını kabul etmiyoruz.
        session = isFreshInstall ? nil : Self.validSession(supabase.client.auth.currentSession)
        startObservingAuthChanges(discardInitialLocalSession: isFreshInstall)
        if isFreshInstall {
            Task { await clearStaleLocalSession(reason: "fresh_install") }
        }
        // Cache'den session geldiyse profili hemen tazele
        if let session {
            Task { await ensureProfile(for: session.user) }
        }
    }

    deinit { stateTask?.cancel() }

    // MARK: - Public

    var isAuthenticated: Bool { session != nil }

    /// E-posta + şifre ile giriş.
    /// signIn'in döndürdüğü Session'dan user ID'yi alıyor — currentSession race condition yok.
    func signInWithPassword(email: String, password: String) async throws {
        lastError = nil
        try RDLegalReleaseGate.requireAuthAndPurchaseAccess()
        let signedInSession = try await supabase.auth.signIn(email: email, password: password)
        await finishSignIn(with: signedInSession)
    }

    /// E-posta adresine tek kullanımlık doğrulama kodu gönderir.
    func sendEmailOTP(email: String) async throws {
        lastError = nil
        try RDLegalReleaseGate.requireAuthAndPurchaseAccess()
        let language = RDLanguage.current
        let contentLocale: RDContentLocale = language == .english
            ? .englishInternational
            : .turkishTurkey
        try await supabase.auth.signInWithOTP(
            email: email,
            redirectTo: deepLinkURL(),
            data: [
                "app_language": .string(language.rawValue),
                "content_locale": .string(contentLocale.rawValue),
            ]
        )
    }

    /// E-posta doğrulama kodunu onaylar ve Supabase oturumu açar.
    func verifyEmailOTP(email: String, token: String) async throws {
        lastError = nil
        try RDLegalReleaseGate.requireAuthAndPurchaseAccess()
        let response = try await verifyEmailOTPWithSupportedTypes(email: email, token: token)
        if let verifiedSession = response.session {
            await finishSignIn(with: verifiedSession)
            return
        }

        if let currentSession = await currentValidSessionAfterShortWait() {
            await finishSignIn(with: currentSession)
            return
        }

        throw NSError(
            domain: "RiskDetected.AuthService",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: RDLocalization.string("auth.auth.service.dogrulama.tamamlandi.ama.oturum.olusturulamadi.l.2a5e70fd", table: .auth, fallback: "Doğrulama tamamlandı ama oturum oluşturulamadı. Lütfen yeni kod gönderip tekrar deneyin.")]
        )
    }

    /// Apple ID ile giriş — UI tarafında ASAuthorizationAppleIDCredential alındıktan sonra
    /// `idToken` ve nonce buraya iletilir.
    func signInWithApple(idToken: String, nonce: String, email: String? = nil, fullName: String? = nil) async throws {
        lastError = nil
        try RDLegalReleaseGate.requireAuthAndPurchaseAccess()
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
        try RDLegalReleaseGate.requireAuthAndPurchaseAccess()
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
        try RDLegalReleaseGate.requireAuthAndPurchaseAccess()
        let signedInSession = try await supabase.auth.signInWithOAuth(
            provider: .google,
            redirectTo: RDConfig.Auth.redirectURL
        )
        await finishSignIn(with: signedInSession)
    }

    /// Çıkış yapar.
    func signOut() async throws {
        do {
            try await supabase.auth.signOut()
        } catch {
            try? await supabase.auth.signOut(scope: .local)
            session = nil
            profile = nil
            lastError = nil
            throw error
        }
        session = nil
        profile = nil
        lastError = nil
    }

    #if DEBUG
    func resetLocalSessionForUITests() async {
        await clearStaleLocalSession(reason: "ui_test_reset")
    }
    #endif

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
                userInfo: [NSLocalizedDescriptionKey: RDLocalization.string("auth.auth.service.oturum.bulunamadi.6c4f2e88", table: .auth, fallback: "Oturum bulunamadı.")]
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
            preferredMethod: input.preferredMethod?.rawValue,
            appLanguage: (input.appLanguage ?? profile?.appLanguage)?.rawValue,
            preferredContentLocale:
                (input.preferredContentLocale ?? profile?.preferredContentLocale)?.rawValue,
            workJurisdictionCountry:
                (input.workJurisdictionCountry ?? profile?.workJurisdictionCountry)?.rawValue,
            workJurisdictionRegion:
                input.workJurisdictionRegion ?? profile?.workJurisdictionRegion,
            safetyProfileID:
                (input.safetyProfileID ?? profile?.safetyProfileID)?.rawValue,
            safetyProfileVersion:
                input.safetyProfileVersion ?? profile?.safetyProfileVersion,
            legalDocumentSetID:
                (input.legalDocumentSetID ?? profile?.legalDocumentSetID)?.rawValue
        )

        try await supabase.client
            .from("profiles")
            .upsert(payload, onConflict: "id")
            .execute()

        await fetchProfile(userID: user.id)
    }

    /// Synchronizes iOS-owned UI language and the user-owned safety profile.
    /// The two values are intentionally independent.
    func updateLocalizationPreferences(
        appLanguage: RDAppLanguage,
        safetyProfileID: RDSafetyProfileID?,
        workJurisdictionRegion: String? = nil
    ) async throws {
        guard let user = supabase.auth.currentUser else {
            throw NSError(
                domain: "RiskDetected.AuthService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: RDLocalization.string("auth.auth.service.oturum.bulunamadi.3535b0a0", table: .auth, fallback: "Oturum bulunamadı.")]
            )
        }

        struct LanguageOnlyPayload: Encodable {
            let app_language: String
            let legal_document_set: String
        }

        struct FullPayload: Encodable {
            let app_language: String
            let preferred_content_locale: String
            let work_jurisdiction_country: String
            let work_jurisdiction_region: String?
            let safety_profile_id: String
            let safety_profile_version: Int
            let legal_document_set: String
        }

        let legalSet = appLanguage == .turkish
            ? RDLegalDocumentSetID.turkeyCurrent.rawValue
            : RDLegalDocumentSetID.englishGlobalV1.rawValue

        if let safetyProfileID {
            let definition = RDSafetyProfileCatalog.profile(id: safetyProfileID)
            try await supabase.client
                .from("profiles")
                .update(
                    FullPayload(
                        app_language: appLanguage.rawValue,
                        preferred_content_locale: definition.contentLocale.rawValue,
                        work_jurisdiction_country: definition.jurisdictionCountry.rawValue,
                        work_jurisdiction_region: workJurisdictionRegion,
                        safety_profile_id: definition.id.rawValue,
                        safety_profile_version: definition.profileVersion,
                        legal_document_set: legalSet
                    )
                )
                .eq("id", value: user.id.uuidString)
                .execute()
        } else {
            try await supabase.client
                .from("profiles")
                .update(
                    LanguageOnlyPayload(
                        app_language: appLanguage.rawValue,
                        legal_document_set: legalSet
                    )
                )
                .eq("id", value: user.id.uuidString)
                .execute()
        }

        await fetchProfile(userID: user.id)
    }

    func uploadProfileLogo(_ image: UIImage) async throws -> String {
        guard let userID = supabase.currentUserID else {
            throw NSError(
                domain: "RiskDetected.AuthService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: RDLocalization.string("auth.auth.service.oturum.bulunamadi.7bbdc1d0", table: .auth, fallback: "Oturum bulunamadı.")]
            )
        }
        guard let data = image.normalizedJPEG(maxDimension: 900, compressionQuality: 0.82) else {
            throw NSError(
                domain: "RiskDetected.AuthService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: RDLocalization.string("auth.auth.service.logo.dosyasi.hazirlanamadi.dd6d4780", table: .auth, fallback: "Logo dosyası hazırlanamadı.")]
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

    func saveProfileAvatar(_ image: UIImage) async throws {
        guard let userID = supabase.currentUserID else {
            throw NSError(
                domain: "RiskDetected.AuthService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: RDLocalization.string("auth.auth.service.oturum.bulunamadi.a73b798d", table: .auth, fallback: "Oturum bulunamadı.")]
            )
        }
        guard let data = image.centeredSquareJPEG(side: 512, compressionQuality: 0.86) else {
            throw NSError(
                domain: "RiskDetected.AuthService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: RDLocalization.string("auth.auth.service.profil.fotografi.hazirlanamadi.caff0171", table: .auth, fallback: "Profil fotoğrafı hazırlanamadı.")]
            )
        }

        let path = "\(userID.uuidString.lowercased())/avatar.jpg"
        _ = try await supabase.storage
            .from(RDConfig.Bucket.avatars)
            .upload(
                path,
                data: data,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )

        try await supabase.client
            .from("profiles")
            .update(ProfileAvatarPatchPayload(avatarURL: path))
            .eq("id", value: userID.uuidString)
            .execute()

        await fetchProfile(userID: userID)
    }

    func profileAvatarImage(path: String) async throws -> UIImage? {
        let data = try await supabase.storage
            .from(RDConfig.Bucket.avatars)
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

        await recordFirstSeenDeviceRegionIfNeeded(userID: user.id)
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
            let msg = RDLocalization.format("auth.auth.service.missing.key.1.at.2.2013762e", table: .auth, fallback: "eksik anahtar'%1$@' de %2$@", arguments: [String(describing: key.stringValue), String(describing: context.codingPath.map(\.stringValue))])
            self.lastError = RDLocalization.format("auth.auth.service.profile.decode.key.1.a5da62ed", table: .auth, fallback: "Profil kod çözme (anahtar): %1$@", arguments: [String(describing: msg)])
        } catch let DecodingError.typeMismatch(type, context) {
            let msg = RDLocalization.format("auth.auth.service.type.1.mismatch.at.2.e583e0a0", table: .auth, fallback: "tip %1$@ uyumsuzluk %2$@", arguments: [String(describing: type), String(describing: context.codingPath.map(\.stringValue))])
            self.lastError = RDLocalization.format("auth.auth.service.profile.decode.type.1.fb611674", table: .auth, fallback: "Profil kod çözme (tür): %1$@", arguments: [String(describing: msg)])
        } catch let DecodingError.valueNotFound(type, context) {
            let msg = RDLocalization.format("auth.auth.service.value.1.not.found.at.2.8e8b5537", table: .auth, fallback: "değer %1$@ bulunamadı %2$@", arguments: [String(describing: type), String(describing: context.codingPath.map(\.stringValue))])
            self.lastError = RDLocalization.format("auth.auth.service.profile.decode.val.1.a6e0a1d8", table: .auth, fallback: "Profil kodu çözme (val): %1$@", arguments: [String(describing: msg)])
        } catch let DecodingError.dataCorrupted(context) {
            let msg = RDLocalization.format("auth.auth.service.data.corrupted.at.1.2.75b648bd", table: .auth, fallback: "veriler bozuk %1$@: %2$@", arguments: [String(describing: context.codingPath.map(\.stringValue)), String(describing: context.debugDescription)])
            self.lastError = RDLocalization.format("auth.auth.service.profile.decode.corrupt.1.0c05431f", table: .auth, fallback: "Profil kodu çözme (bozuk): %1$@", arguments: [String(describing: msg)])
        } catch let error as PostgrestError where Self.isMissingProfileError(error) {
            self.profile = nil
            self.lastError = nil
            return .missing
        } catch {
            self.lastError = RDLocalization.format("auth.auth.service.profile.fetch.1.3d557476", table: .auth, fallback: "Profil getirme: %1$@", arguments: [String(describing: error.localizedDescription)])
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
            if Self.isDeletedAuthUserProfileError(error) {
                await clearStaleLocalSession(reason: "profile_bootstrap_user_missing")
                return
            }

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
            self.lastError = RDLocalization.format("auth.auth.service.profile.bootstrap.1.86cceeb4", table: .auth, fallback: "Profil önyüklemesi: %1$@", arguments: [String(describing: error.localizedDescription)])
        }
    }

    private func clearStaleLocalSession(reason: String) async {
        Self.logger.warning("Clearing stale local auth session: \(reason, privacy: .public)")
        try? await supabase.auth.signOut(scope: .local)
        session = nil
        profile = nil
        lastError = nil
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

    private func recordFirstSeenDeviceRegionIfNeeded(userID: UUID) async {
        guard supabase.currentUserID == userID else { return }
        guard profile?.id == userID else { return }
        if profile?.firstSeenDeviceRegionCode != nil {
            deviceRegionCaptureCompletedUserIDs.insert(userID)
            return
        }
        guard !deviceRegionCaptureCompletedUserIDs.contains(userID) else { return }
        guard deviceRegionCaptureInFlightUserIDs.insert(userID).inserted else { return }
        defer { deviceRegionCaptureInFlightUserIDs.remove(userID) }
        guard let regionCode = Self.normalizedDeviceRegionCode(
            from: Locale.current.region?.identifier
        ) else {
            Self.logger.info("First device region capture skipped reason=invalid_or_missing_region")
            return
        }

        do {
            let recordedRegionCode: String = try await supabase.client
                .rpc(
                    "record_first_seen_device_region_v1",
                    params: FirstSeenDeviceRegionPayload(regionCode: regionCode)
                )
                .execute()
                .value
            deviceRegionCaptureCompletedUserIDs.insert(userID)
            Self.logger.info(
                "First device region recorded code=\(recordedRegionCode, privacy: .public)"
            )
        } catch {
            Self.logger.warning(
                "First device region capture failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func normalizedDeviceRegionCode(from identifier: String?) -> String? {
        guard let identifier else { return nil }
        let candidate = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard candidate.range(
            of: #"^[A-Z]{2}$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }
        return candidate
    }

    private func startObservingAuthChanges(discardInitialLocalSession: Bool = false) {
        stateTask = Task { [weak self] in
            guard let self else { return }
            var shouldDiscardInitialLocalSession = discardInitialLocalSession
            for await change in supabase.auth.authStateChanges {
                let newSession = Self.validSession(change.session)

                if shouldDiscardInitialLocalSession {
                    shouldDiscardInitialLocalSession = false
                    if newSession != nil {
                        await self.clearStaleLocalSession(reason: "fresh_install_initial_auth_event")
                        continue
                    }
                }

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

    private static func markInstallAndDetectFreshInstall() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: installMarkerKey)?.isEmpty == false {
            return false
        }
        defaults.set(UUID().uuidString, forKey: installMarkerKey)
        return true
    }

    private static func validSession(_ session: Session?) -> Session? {
        guard let session, !session.isExpired else { return nil }
        return session
    }

    private func currentValidSessionAfterShortWait() async -> Session? {
        if let session = Self.validSession(supabase.client.auth.currentSession) {
            return session
        }

        for delay in [150_000_000, 350_000_000] {
            try? await Task.sleep(nanoseconds: UInt64(delay))
            if let session = Self.validSession(supabase.client.auth.currentSession) {
                return session
            }
        }

        return nil
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
            userInfo: [NSLocalizedDescriptionKey: RDLocalization.string("auth.auth.service.e.posta.dogrulama.kodu.dogrulanamadi.f2487e20", table: .auth, fallback: "E-posta doğrulama kodu doğrulanamadı.")]
        )
    }

    private static func canRetryEmailOTPType(after error: Error) -> Bool {
        let lower = error.localizedDescription.lowercased(with: .autoupdatingCurrent)
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

    private static func isDeletedAuthUserProfileError(_ error: Error) -> Bool {
        guard let postgrestError = error as? PostgrestError else { return false }
        guard postgrestError.code == "23503" else { return false }

        let message = postgrestError.message.lowercased(with: Locale(identifier: "en_US_POSIX"))
        let detail = postgrestError.detail?.lowercased(with: Locale(identifier: "en_US_POSIX")) ?? ""
        return message.contains("profiles_id_fkey") ||
            message.contains("foreign key") ||
            detail.contains("profiles_id_fkey") ||
            detail.contains("auth.users")
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

    #if DEBUG
    private static var isUITestMainLaunch: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_MAIN")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_MAIN"] == "1"
    }

    private static func clearLocalSupabaseSessionSynchronously(using supabase: SupabaseService) {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            try? await supabase.auth.signOut(scope: .local)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 3)
    }
    #endif
}

struct ProfileUpdateInput {
    var fullName: String
    var title: String
    var certificateNumber: String
    var companyName: String
    var phone: String
    var preferredMethod: RiskMethodWire?
    var companyLogoPath: String?
    var appLanguage: RDAppLanguage? = nil
    var preferredContentLocale: RDContentLocale? = nil
    var workJurisdictionCountry: RDWorkJurisdictionCountry? = nil
    var workJurisdictionRegion: String? = nil
    var safetyProfileID: RDSafetyProfileID? = nil
    var safetyProfileVersion: Int? = nil
    var legalDocumentSetID: RDLegalDocumentSetID? = nil
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
    let appLanguage: String?
    let preferredContentLocale: String?
    let workJurisdictionCountry: String?
    let workJurisdictionRegion: String?
    let safetyProfileID: String?
    let safetyProfileVersion: Int?
    let legalDocumentSetID: String?

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
        case appLanguage = "app_language"
        case preferredContentLocale = "preferred_content_locale"
        case workJurisdictionCountry = "work_jurisdiction_country"
        case workJurisdictionRegion = "work_jurisdiction_region"
        case safetyProfileID = "safety_profile_id"
        case safetyProfileVersion = "safety_profile_version"
        case legalDocumentSetID = "legal_document_set"
    }
}

private struct ProfileAvatarPatchPayload: Encodable {
    let avatarURL: String

    enum CodingKeys: String, CodingKey {
        case avatarURL = "avatar_url"
    }
}

private struct FirstSeenDeviceRegionPayload: Encodable {
    let regionCode: String

    enum CodingKeys: String, CodingKey {
        case regionCode = "p_region_code"
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

    func centeredSquareJPEG(side: CGFloat, compressionQuality: CGFloat) -> Data? {
        let targetSize = CGSize(width: side, height: side)
        let sourceSize = size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let scale = max(side / sourceSize.width, side / sourceSize.height)
        let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let origin = CGPoint(
            x: (side - drawSize.width) / 2,
            y: (side - drawSize.height) / 2
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let normalized = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            draw(in: CGRect(origin: origin, size: drawSize))
        }
        return normalized.jpegData(compressionQuality: compressionQuality)
    }
}
