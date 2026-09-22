import SwiftUI
import UIKit

struct ReferralRewardsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var colorScheme

    let onClose: () -> Void

    @State private var dashboard: ReferralDashboard?
    @State private var claimCode: String
    @State private var loading = true
    @State private var working = false
    @State private var message: ReferralMessage?
    @State private var sharePayload: ReferralSharePayload?
    @State private var termsExpanded = false

    private let service = ReferralRewardsService.shared

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        _claimCode = State(initialValue: ReferralDeepLinkStore.shared.pendingCode ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if loading {
                        loadingCard
                    } else if let dashboard {
                        hero(dashboard)
                        codeCard(dashboard)
                        metrics(dashboard)
                        rewardsSection(dashboard)
                        claimCard(dashboard)
                        inviteProgress(dashboard)
                        termsCard(dashboard)
                    } else {
                        errorCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
        .background(Color.rdPaper.ignoresSafeArea())
        .task { await load() }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: [payload.message])
                .presentationDetents([.medium, .large])
        }
        .alert(item: $message) { item in
            Alert(title: Text(item.title), message: Text(item.detail), dismissButton: .default(Text("Tamam")))
        }
        .accessibilityIdentifier("referral.root")
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Color.rdInk)
                    .frame(width: 48, height: 48)
                    .background(Color.rdWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kapat")

            VStack(alignment: .leading, spacing: 2) {
                Text("Arkadaşını davet et")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(Color.rdInk)
                Text("Birlikte Plus kazanın")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.rdSlate)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.rdPaper)
    }

    private func hero(_ value: ReferralDashboard) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(Color.rdPlanPlusDark)
                    .frame(width: 48, height: 48)
                    .background(Color.rdPlanPlusSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 6) {
                    Text("İkiniz de \(value.campaign.rewardDays) gün Plus kazanın")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.rdInk)
                    Text("Arkadaşın kodunu kabul edip \(value.campaign.qualificationWindowDays) gün içinde, iki farklı günde gerçek bir işlem yaptığında ödülleriniz hazır olur.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.rdCharcoal)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                stepPill("1", "Kodu paylaş")
                Image(systemName: "chevron.right").foregroundStyle(Color.rdSlate)
                stepPill("2", "2 gün kullan")
                Image(systemName: "chevron.right").foregroundStyle(Color.rdSlate)
                stepPill("3", "Ödülü aç")
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.rdPlanPlusSoft, Color.rdWhite],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.rdPlanPlus.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private func stepPill(_ number: String, _ title: String) -> some View {
        VStack(spacing: 5) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 24, height: 24)
                .background(Color.rdInk)
                .clipShape(Circle())
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.rdCharcoal)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    private func codeCard(_ value: ReferralDashboard) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Davet kodun")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.rdSlate)
            HStack {
                Text(value.referralCode)
                    .font(.system(size: 29, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(Color.rdInk)
                    .accessibilityIdentifier("referral.code")
                Spacer()
                Button {
                    UIPasteboard.general.string = value.referralCode
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    Task { await service.track("code_copied") }
                    message = ReferralMessage(title: "Kod kopyalandı", detail: "Davet kodunu istediğin yerde paylaşabilirsin.")
                } label: {
                    Label("Kopyala", systemImage: "doc.on.doc")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.rdInk)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(Color.rdFog)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Button {
                sharePayload = ReferralSharePayload(message: value.shareMessage)
                UISelectionFeedbackGenerator().selectionChanged()
                Task { await service.track("share_started") }
            } label: {
                Label("Davet bağlantısını paylaş", systemImage: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.rdGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("referral.share")
        }
        .cardSurface()
    }

    private func metrics(_ value: ReferralDashboard) -> some View {
        HStack(spacing: 10) {
            metric("Gönderilen", value.counts.invited, "paperplane")
            metric("Tamamlayan", value.counts.qualified, "checkmark.circle")
            metric("Ödül", value.counts.rewarded, "gift")
        }
    }

    private func metric(_ title: String, _ value: Int, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.rdGreenDark)
            Text("\(value)")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.rdInk)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.rdSlate)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.rdWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func rewardsSection(_ value: ReferralDashboard) -> some View {
        if !value.rewards.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Ödüllerin")
                ForEach(value.rewards) { reward in
                    rewardCard(reward)
                }
            }
        }
    }

    private func rewardCard(_ reward: ReferralDashboard.Reward) -> some View {
        HStack(spacing: 13) {
            Image(systemName: reward.state == "active" ? "sparkles" : "gift.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.rdPlanPlusDark)
                .frame(width: 44, height: 44)
                .background(Color.rdPlanPlusSoft)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(rewardTitle(reward))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.rdInk)
                Text(rewardDetail(reward))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.rdSlate)
            }
            Spacer()
            if reward.state == "earned" || reward.state == "available" {
                Button("Başlat") {
                    Task { await activate(reward) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.rdGreen)
                .disabled(working)
                .accessibilityIdentifier("referral.reward.activate")
            }
        }
        .cardSurface()
    }

    private func claimCard(_ value: ReferralDashboard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Bir davet kodun mu var?")
            Text("Kodu bir kez kabul edebilirsin. Kendi kodun kullanılamaz.")
                .font(.system(size: 14))
                .foregroundStyle(Color.rdSlate)
            HStack(spacing: 10) {
                TextField("Davet kodu", text: $claimCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .onChange(of: claimCode) { newValue in
                        let filtered = newValue.uppercased().filter { $0.isLetter || $0.isNumber }
                        if filtered != newValue || filtered.count > 12 {
                            claimCode = String(filtered.prefix(12))
                        }
                    }
                Button("Kullan") {
                    Task { await claim() }
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(canClaim ? Color.rdInk : Color.rdSlate.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .disabled(!canClaim || working)
                .accessibilityIdentifier("referral.claim")
            }

            if let accepted = value.acceptedInvites.first {
                HStack(spacing: 9) {
                    Image(systemName: accepted.state == "rewarded" ? "checkmark.seal.fill" : "clock.fill")
                        .foregroundStyle(accepted.state == "rewarded" ? Color.rdGreen : Color.rdPlanPlus)
                    Text(acceptedInviteText(accepted))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.rdCharcoal)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.rdFog)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .cardSurface()
    }

    @ViewBuilder
    private func inviteProgress(_ value: ReferralDashboard) -> some View {
        if !value.sentInvites.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Davetlerin")
                ForEach(value.sentInvites) { invite in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(statusColor(invite.state))
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(statusTitle(invite.state))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.rdInk)
                            Text("Kabul: \(formatted(invite.claimedAt))")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.rdSlate)
                        }
                        Spacer()
                        Text(statusBadge(invite.state))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(statusColor(invite.state))
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(statusColor(invite.state).opacity(0.10))
                            .clipShape(Capsule())
                    }
                    .cardSurface()
                }
            }
        }
    }

    private func termsCard(_ value: ReferralDashboard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { termsExpanded.toggle() }
            } label: {
                HStack {
                    Label("Nasıl çalışır?", systemImage: "info.circle")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.rdInk)
                    Spacer()
                    Image(systemName: termsExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Color.rdSlate)
                }
            }
            .buttonStyle(.plain)
            if termsExpanded {
                Text("Davet edilen kişi kodu kabul ettikten sonra \(value.campaign.qualificationWindowDays) gün içinde iki farklı günde personel, işyeri, departman, eğitim, risk değerlendirmesi, rapor veya tamamlanmış kontrol listesi işlemi yapmalıdır. Görüntüleme ve başarısız işlemler sayılmaz. Ödül mağaza aboneliği değildir; otomatik yenilenmez ve kotayı sıfırlamaz.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.rdSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardSurface()
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Color.rdGreen)
            Text("Davet programı hazırlanıyor")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.rdSlate)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .cardSurface()
    }

    private var errorCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30))
                .foregroundStyle(Color.rdHigh)
            Text("Davet bilgileri alınamadı")
                .font(.system(size: 18, weight: .bold))
            Button("Tekrar dene") { Task { await load() } }
                .buttonStyle(.borderedProminent)
                .tint(Color.rdGreen)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .cardSurface()
    }

    private var canClaim: Bool {
        claimCode.range(of: "^[A-Z0-9]{6,12}$", options: .regularExpression) != nil
    }

    private func sectionTitle(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(Color.rdInk)
    }

    @MainActor
    private func load() async {
        loading = dashboard == nil
        do {
            dashboard = try await service.dashboard()
            await service.track("screen_viewed")
        } catch {
            message = ReferralMessage(title: "Davet programı açılamadı", detail: ReferralRewardsService.userMessage(for: error))
        }
        loading = false
    }

    @MainActor
    private func claim() async {
        guard canClaim, !working else { return }
        working = true
        defer { working = false }
        do {
            let result = try await service.claim(code: claimCode)
            ReferralDeepLinkStore.shared.clear()
            dashboard = try await service.dashboard()
            message = ReferralMessage(
                title: result.replayed ? "Davet zaten bağlı" : "Davet kabul edildi",
                detail: "\(result.qualificationDays ?? 2) farklı günde gerçek bir işlem yaptığında iki tarafın da ödülü hazır olacak."
            )
        } catch {
            message = ReferralMessage(title: "Kod kullanılamadı", detail: ReferralRewardsService.userMessage(for: error))
        }
    }

    @MainActor
    private func activate(_ reward: ReferralDashboard.Reward) async {
        guard !working else { return }
        working = true
        defer { working = false }
        await service.track("reward_activation_started")
        do {
            let result = try await service.activate(instanceID: reward.instanceID)
            if result.activated {
                await app.refreshPlanState()
                dashboard = try await service.dashboard()
                message = ReferralMessage(title: "Plus ödülün başladı", detail: "7 günlük Plus erişimin otomatik yenileme olmadan etkinleştirildi.")
            } else if result.reason == "PAID_ACCESS_ACTIVE" {
                message = ReferralMessage(title: "Ödülün güvende", detail: "Aktif ücretli planın varken süreyi başlatmıyoruz. Planın sona erdiğinde bu ekrandan kullanabilirsin.")
            } else if result.reason == "GIFT_ALREADY_ACTIVE" {
                message = ReferralMessage(title: "Aktif bir ödülün var", detail: "Mevcut hediye süren bittikten sonra sıradaki ödülü başlatabilirsin.")
            }
        } catch {
            message = ReferralMessage(title: "Ödül başlatılamadı", detail: ReferralRewardsService.userMessage(for: error))
        }
    }

    private func rewardTitle(_ reward: ReferralDashboard.Reward) -> String {
        switch reward.state {
        case "active": return "Plus ödülün aktif"
        case "expired": return "Plus ödülü kullanıldı"
        default: return "7 günlük Plus hazır"
        }
    }

    private func rewardDetail(_ reward: ReferralDashboard.Reward) -> String {
        if let expires = reward.expiresAt, reward.state == "active" {
            return "\(formatted(expires)) tarihine kadar"
        }
        return reward.state == "expired" ? "Bu ödülün süresi tamamlandı" : "Hazır olduğunda süreyi sen başlat"
    }

    private func acceptedInviteText(_ invite: ReferralDashboard.Invite) -> String {
        switch invite.state {
        case "rewarded": return "Koşulları tamamladın; ödülün hazır."
        case "qualified": return "İşlemlerin doğrulandı; ödül hazırlanıyor."
        default:
            return "İlerleme: \(invite.distinctDays ?? 0)/\(invite.requiredDays ?? 2) farklı gün"
        }
    }

    private func statusTitle(_ state: String) -> String {
        switch state {
        case "rewarded": return "Ödül kazanıldı"
        case "qualified": return "Koşul tamamlandı"
        case "rejected", "expired": return "Davet tamamlanmadı"
        default: return "Kodu kabul etti"
        }
    }

    private func statusBadge(_ state: String) -> String {
        switch state {
        case "rewarded": return "Kazanıldı"
        case "qualified": return "Tamamlandı"
        case "rejected", "expired": return "Kapandı"
        default: return "Bekliyor"
        }
    }

    private func statusColor(_ state: String) -> Color {
        switch state {
        case "rewarded", "qualified": return .rdGreen
        case "rejected", "expired": return .rdCritical
        default: return .rdPlanPlus
        }
    }

    private func formatted(_ value: String) -> String {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let date = withFractional.date(from: value) ?? plain.date(from: value) else {
            return value
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
}

private struct ReferralMessage: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

private struct ReferralSharePayload: Identifiable {
    let id = UUID()
    let message: String
}

private extension View {
    func cardSurface() -> some View {
        self
            .padding(16)
            .background(Color.rdWhite)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.rdLine, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
