import Foundation

struct PurchaseErrorClassification: Equatable {
    enum Kind: Equatable {
        case cancelled
        case network
        case existingSubscription
        case receiptConflict
        case storeUnavailable
        case productUnavailable
        case purchaseNotAllowed
        case configuration
        case backendVerification
        case packageUnavailable
        case operationInProgress
        case paymentPending
        case unknown
    }

    let kind: Kind
    let rawMessage: String
    let code: Int?
    let codeName: String?
    let domain: String

    var debugSummary: String {
        [
            "kind=\(kind)",
            "domain=\(domain)",
            "code=\(code.map(String.init) ?? "nil")",
            "codeName=\(codeName ?? "nil")",
        ].joined(separator: " ")
    }
}

enum PurchaseErrorClassifier {
    static func classify(_ error: Error) -> PurchaseErrorClassification {
        if error is CancellationError {
            return PurchaseErrorClassification(
                kind: .cancelled,
                rawMessage: "",
                code: nil,
                codeName: nil,
                domain: "CancellationError"
            )
        }

        return classify(nsError: error as NSError, visited: [])
    }

    static func classify(rawMessage: String) -> PurchaseErrorClassification {
        let raw = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased(with: .autoupdatingCurrent)
        let kind: PurchaseErrorClassification.Kind

        if lower.contains("bu öğeye abonesiniz") ||
            lower.contains("bu ogeye abonesiniz") ||
            lower.contains("already subscribed") ||
            lower.contains("currently subscribed") ||
            lower.contains("already purchased") ||
            lower.contains("aktif bir riskdetected aboneliği") ||
            lower.contains("aktif bir riskdetected aboneligi") ||
            lower.contains("item already") ||
            lower.contains("product already")
        {
            kind = .existingSubscription
        } else if lower.contains("revenuecat_owner_mismatch") ||
            lower.contains("revenuecat_purchase_predates_account") ||
            lower.contains("revenuecat_transfer_conflict") ||
            lower.contains("receipt_already_in_use") ||
            lower.contains("receipt in use") ||
            lower.contains("belongs to other user") ||
            lower.contains("farklı bir riskdetected hesab") ||
            lower.contains("farkli bir riskdetected hesab") ||
            lower.contains("başka bir hesap") ||
            lower.contains("baska bir hesap")
        {
            kind = .receiptConflict
        } else if lower.contains("revenuecat_tier_mismatch") ||
            lower.contains("seçilen plan") && lower.contains("doğrulanan plan") ||
            lower.contains("secilen plan") && lower.contains("dogrulanan plan") ||
            lower.contains("backend tarafında doğrulanamadı") ||
            lower.contains("backend tarafinda dogrulanamadi") ||
            lower.contains("satın alma başarısı olarak işaretlemedi") ||
            lower.contains("satin alma basarisi olarak isaretlemedi")
        {
            kind = .backendVerification
        } else if lower.contains("abonelik paketi") && (
            lower.contains("bulunamadı") ||
                lower.contains("bulunamadi") ||
                lower.contains("hazırlanamadı") ||
                lower.contains("hazirlanamadi")
        ) {
            kind = .packageUnavailable
        } else {
            kind = .unknown
        }

        return PurchaseErrorClassification(
            kind: kind,
            rawMessage: raw,
            code: nil,
            codeName: nil,
            domain: "raw"
        )
    }

    private static func classify(nsError: NSError, visited: Set<String>) -> PurchaseErrorClassification {
        let visitKey = "\(nsError.domain):\(nsError.code)"
        if !visited.contains(visitKey), let nested = nestedRevenueCatError(in: nsError) {
            var nextVisited = visited
            nextVisited.insert(visitKey)
            let nestedClassification = classify(nsError: nested as NSError, visited: nextVisited)
            if nestedClassification.kind != .unknown {
                return nestedClassification
            }
        }

        let codeName = revenueCatCodeName(in: nsError)
        let kind = kind(forCodeName: codeName)
            ?? kind(forRevenueCatCode: nsError.code, domain: nsError.domain, codeName: codeName)
            ?? kind(forAppError: nsError)
            ?? classify(rawMessage: nsError.localizedDescription).kind

        return PurchaseErrorClassification(
            kind: kind,
            rawMessage: nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            code: nsError.code,
            codeName: codeName,
            domain: nsError.domain
        )
    }

    private static func nestedRevenueCatError(in error: NSError) -> Error? {
        if let root = error.userInfo["rc_root_error"] as? Error {
            return root
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
            return underlying
        }
        return nil
    }

    private static func revenueCatCodeName(in error: NSError) -> String? {
        let keys = ["readable_error_code", "rc_code_name"]
        for key in keys {
            if let value = error.userInfo[key] as? String, !value.isEmpty {
                return value.uppercased()
            }
        }
        return nil
    }

    private static func kind(forCodeName codeName: String?) -> PurchaseErrorClassification.Kind? {
        guard let codeName else { return nil }
        switch codeName {
        case "PURCHASE_CANCELLED":
            return .cancelled
        case "NETWORK_ERROR", "OFFLINE_CONNECTION_ERROR":
            return .network
        case "PRODUCT_ALREADY_PURCHASED":
            return .existingSubscription
        case "RECEIPT_ALREADY_IN_USE",
             "RECEIPT_IN_USE_BY_OTHER_SUBSCRIBER",
             "PURCHASE_BELONGS_TO_OTHER_USER":
            return .receiptConflict
        case "STORE_PROBLEM",
             "PRODUCT_REQUEST_TIMED_OUT",
             "API_ENDPOINT_BLOCKED",
             "UNKNOWN_BACKEND_ERROR",
             "UNEXPECTED_BACKEND_RESPONSE_ERROR":
            return .storeUnavailable
        case "PRODUCT_NOT_AVAILABLE_FOR_PURCHASE":
            return .productUnavailable
        case "PURCHASE_NOT_ALLOWED",
             "INSUFFICIENT_PERMISSIONS":
            return .purchaseNotAllowed
        case "INVALID_CREDENTIALS",
             "CONFIGURATION_ERROR",
             "INVALID_APP_USER_ID",
             "INVALID_APPLE_SUBSCRIPTION_KEY_ERROR":
            return .configuration
        case "INVALID_RECEIPT",
             "MISSING_RECEIPT_FILE",
             "SIGNATURE_VERIFICATION_FAILED":
            return .backendVerification
        case "OPERATION_ALREADY_IN_PROGRESS_FOR_PRODUCT_ERROR":
            return .operationInProgress
        case "PAYMENT_PENDING":
            return .paymentPending
        default:
            return nil
        }
    }

    private static func kind(
        forRevenueCatCode code: Int,
        domain: String,
        codeName: String?
    ) -> PurchaseErrorClassification.Kind? {
        guard codeName != nil || domain.localizedCaseInsensitiveContains("RevenueCat") else {
            return nil
        }

        switch code {
        case 1:
            return .cancelled
        case 2, 12, 16, 32, 33:
            return .storeUnavailable
        case 3, 19:
            return .purchaseNotAllowed
        case 5:
            return .productUnavailable
        case 6:
            return .existingSubscription
        case 7, 13, 40:
            return .receiptConflict
        case 8, 9, 37:
            return .backendVerification
        case 10, 35:
            return .network
        case 11, 14, 17, 23:
            return .configuration
        case 15:
            return .operationInProgress
        case 20:
            return .paymentPending
        default:
            return nil
        }
    }

    private static func kind(forAppError error: NSError) -> PurchaseErrorClassification.Kind? {
        if error.domain == "RiskDetected.OnboardingPurchase", error.code == 404 {
            return .packageUnavailable
        }

        guard error.domain == "RiskDetected.Subscription" else { return nil }
        if error.code == 404 {
            return .packageUnavailable
        }
        if error.code == 409 {
            return .backendVerification
        }
        if error.code == 401 {
            return .configuration
        }
        return nil
    }
}
