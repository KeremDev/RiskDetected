import Foundation

func assertKind(
    _ error: Error,
    _ expected: PurchaseErrorClassification.Kind,
    _ label: String
) {
    let actual = PurchaseErrorClassifier.classify(error).kind
    guard actual == expected else {
        fatalError("\(label): expected \(expected), got \(actual)")
    }
}

func revenueCatError(code: Int, codeName: String) -> NSError {
    NSError(
        domain: "RevenueCat.ErrorCode",
        code: code,
        userInfo: [
            "readable_error_code": codeName,
            "rc_code_name": codeName,
            NSLocalizedDescriptionKey: codeName,
        ]
    )
}

assertKind(
    revenueCatError(code: 10, codeName: "NETWORK_ERROR"),
    .network,
    "network code"
)

assertKind(
    revenueCatError(code: 35, codeName: "OFFLINE_CONNECTION_ERROR"),
    .network,
    "offline code"
)

assertKind(
    revenueCatError(code: 6, codeName: "PRODUCT_ALREADY_PURCHASED"),
    .existingSubscription,
    "already purchased code"
)

assertKind(
    revenueCatError(code: 1, codeName: "PURCHASE_CANCELLED"),
    .cancelled,
    "cancelled code"
)

assertKind(
    revenueCatError(code: 5, codeName: "PRODUCT_NOT_AVAILABLE_FOR_PURCHASE"),
    .productUnavailable,
    "product unavailable code"
)

assertKind(
    revenueCatError(code: 2, codeName: "STORE_PROBLEM"),
    .storeUnavailable,
    "store problem code"
)

assertKind(
    revenueCatError(code: 7, codeName: "RECEIPT_ALREADY_IN_USE"),
    .receiptConflict,
    "receipt conflict code"
)

assertKind(
    NSError(
        domain: "RiskDetected.OnboardingPurchase",
        code: 404,
        userInfo: [
            NSLocalizedDescriptionKey: "Seçilen abonelik paketi şu an hazırlanamadı.",
        ]
    ),
    .packageUnavailable,
    "package unavailable"
)

let rawNetworkLookingPurchaseMessage = PurchaseErrorClassifier.classify(
    rawMessage: "App Store connection failed while product state was unknown"
)
guard rawNetworkLookingPurchaseMessage.kind == .unknown else {
    fatalError("raw purchase fallback must not infer network from localized text")
}

let activeHigherTierMessage = PurchaseErrorClassifier.classify(
    rawMessage: "Pro aboneliğin aktif görünüyor. Plus planına geçiş ya da downgrade işlemi App Store abonelik yönetimi üzerinden yapılmalı; uygulama bunu Plus satın alma başarısı olarak işaretlemedi."
)
guard activeHigherTierMessage.kind == .backendVerification else {
    fatalError("active higher tier message must classify as backend verification")
}

print("PurchaseErrorClassifier tests passed")
