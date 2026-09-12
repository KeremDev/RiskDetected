import Foundation

/// Auth-layer new-password UX validation only; never apply to legacy sign-in.
/// Release gate: GoTrue 2.195.0 counts minimum bytes, not Unicode characters.
/// The server Unicode-minimum policy must be resolved before signup UI activation.
struct IsgPasswordRules: Equatable, Codable {
    let minimumCharacters: Bool
    let uppercase: Bool
    let lowercase: Bool
    let digit: Bool
    let maximumBytes: Bool
    var valid: Bool { minimumCharacters && uppercase && lowercase && digit && maximumBytes }

    init(_ password: String) {
        let scalars = password.unicodeScalars.map(\.value)
        minimumCharacters = scalars.count >= 8
        uppercase = scalars.contains { (65...90).contains($0) }
        lowercase = scalars.contains { (97...122).contains($0) }
        digit = scalars.contains { (48...57).contains($0) }
        maximumBytes = password.utf8.count <= 72
    }
}

enum IsgPasswordAuthError: String, Error {
    case invalidEmail = "password_email_invalid"
    case invalidPassword = "password_policy_invalid"
    case signedIn = "password_signup_requires_signed_out"
    case confirmationRequired = "password_confirmation_required"
    case signupFailed = "password_signup_failed"
    case recoveryFailed = "password_recovery_failed"
}
