import SwiftUI

struct AnalysisResultPaywallContext: Equatable {
    let analysisID: UUID
    let section: AnalysisResultSectionID
    let funnelSessionID: UUID
    let language: RDLanguage
}

/// Uygulama içi paywall giriş noktası.
/// Claude Design paywall akışını (`PaywallDesignFlowView`) kullanır.
struct PaywallV2View: View {
    var onClose: () -> Void
    var onSubscribe: () -> Void
    var notice: String? = nil
    var resultHubContext: AnalysisResultPaywallContext? = nil

    var body: some View {
        PaywallDesignFlowView(
            source: .inApp,
            onClose: onClose,
            onSubscribe: onSubscribe,
            notice: notice,
            resultHubContext: resultHubContext
        )
    }
}

/// Kullanıcının mevcut planına göre PLUS veya PRO ekranıyla açılan paywall.
struct FreeAwarePaywallView: View {
    var onClose: () -> Void
    var onSubscribe: () -> Void
    var notice: String? = nil
    var resultHubContext: AnalysisResultPaywallContext? = nil

    var body: some View {
        PaywallDesignFlowView(
            source: .inApp,
            onClose: onClose,
            onSubscribe: onSubscribe,
            notice: notice,
            resultHubContext: resultHubContext
        )
    }
}

#Preview {
    PaywallV2View(onClose: {}, onSubscribe: {})
        .environmentObject(AppState())
}
