import FirebaseAuth
import Foundation

final class FirebasePhoneAuthService {
    static let shared = FirebasePhoneAuthService()

    private init() {}

    var isConfigured: Bool {
        FirebaseBootstrap.isConfigured
    }

    func sendCode(phone: String) async throws -> String {
        guard isConfigured else { throw FirebasePhoneAuthError.notConfigured }

        return try await withCheckedThrowingContinuation { continuation in
            PhoneAuthProvider.provider().verifyPhoneNumber(phone, uiDelegate: nil) { verificationID, error in
                if let error {
                    continuation.resume(throwing: FirebasePhoneAuthError.provider(error))
                    return
                }

                guard let verificationID else {
                    continuation.resume(throwing: FirebasePhoneAuthError.missingVerificationID)
                    return
                }

                continuation.resume(returning: verificationID)
            }
        }
    }

    func verifyCode(verificationID: String, code: String) async throws -> String {
        guard isConfigured else { throw FirebasePhoneAuthError.notConfigured }

        let credential = PhoneAuthProvider.provider()
            .credential(withVerificationID: verificationID, verificationCode: code)

        let user = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<User, Error>) in
            Auth.auth().signIn(with: credential) { result, error in
                if let error {
                    continuation.resume(throwing: FirebasePhoneAuthError.provider(error))
                    return
                }

                guard let user = result?.user else {
                    continuation.resume(throwing: FirebasePhoneAuthError.missingUser)
                    return
                }

                continuation.resume(returning: user)
            }
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            user.getIDToken { token, error in
                if let error {
                    continuation.resume(throwing: FirebasePhoneAuthError.provider(error))
                    return
                }

                guard let token else {
                    continuation.resume(throwing: FirebasePhoneAuthError.missingIDToken)
                    return
                }

                continuation.resume(returning: token)
            }
        }
    }
}

enum FirebasePhoneAuthError: LocalizedError {
    case notConfigured
    case missingVerificationID
    case missingUser
    case missingIDToken
    case bridgeNotEnabled
    case provider(code: Int, message: String)

    static func provider(_ error: Error) -> FirebasePhoneAuthError {
        let nsError = error as NSError
        let details = [
            nsError.localizedDescription,
            nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
            nsError.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        return .provider(code: nsError.code, message: details)
    }

    var shouldFallbackToSupabaseOTP: Bool {
        switch self {
        case .notConfigured:
            return true
        case let .provider(_, message):
            let lower = message.lowercased(with: Locale(identifier: "tr_TR"))
            return lower.contains("configuration_not_found") ||
                lower.contains("billing_not_enabled") ||
                lower.contains("operation is not allowed") ||
                lower.contains("operation-not-allowed") ||
                lower.contains("not enabled") ||
                lower.contains("disabled")
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Firebase telefon doğrulaması için GoogleService-Info.plist bulunamadı."
        case .missingVerificationID:
            return "Firebase doğrulama oturumu başlatılamadı."
        case .missingUser:
            return "Firebase telefon kullanıcısı doğrulanamadı."
        case .missingIDToken:
            return "Firebase doğrulama tokenı alınamadı."
        case .bridgeNotEnabled:
            return "Firebase telefon doğrulaması hazır, ancak Supabase kullanıcı eşleme köprüsü henüz aktif değil."
        case let .provider(code, message):
            let lower = message.lowercased(with: Locale(identifier: "tr_TR"))
            if lower.contains("operation is not allowed") ||
                lower.contains("operation-not-allowed") ||
                lower.contains("not enabled") ||
                lower.contains("disabled")
            {
                return "Firebase telefon girişi henüz aktif değil. Firebase Console > Authentication > Sign-in method bölümünden Phone provider açılmalı. Firebase kodu: \(code)"
            }
            if lower.contains("app is not authorized") ||
                lower.contains("app-not-authorized") ||
                lower.contains("bundle") ||
                lower.contains("api key")
            {
                return "Firebase iOS uygulama ayarı bu bundle için yetkili görünmüyor. Bundle ID ve GoogleService-Info.plist kontrol edilmeli. Firebase kodu: \(code)"
            }
            if lower.contains("quota") ||
                lower.contains("too many") ||
                lower.contains("too-many-requests")
            {
                return "Firebase SMS kotası veya deneme sınırı dolmuş görünüyor. Biraz bekleyip tekrar dene ya da Firebase test numarası kullan. Firebase kodu: \(code)"
            }
            if lower.contains("invalid phone") ||
                lower.contains("invalid-phone-number")
            {
                return "Telefon numarası Firebase tarafından geçerli kabul edilmedi. Numarayı başında 0 olmadan, 10 haneli olarak gir. Firebase kodu: \(code)"
            }
            if lower.contains("captcha") ||
                lower.contains("recaptcha") ||
                lower.contains("url scheme")
            {
                return "Firebase güvenlik doğrulaması tamamlanamadı. reCAPTCHA/URL scheme ayarı kontrol edilmeli. Firebase kodu: \(code)"
            }
            return "Firebase telefon doğrulaması tamamlanamadı. Firebase kodu: \(code). Detay: \(message)"
        }
    }
}
