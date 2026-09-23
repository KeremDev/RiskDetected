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
            .accessibilityLabel(RDLocalization.string("localizable.referral.rewards.view.kapat.f440065a", table: .localizable, fallback: "Kapat"))

            VStack(alignment: .leading, spacing: 2) {
                Text(RDLocalization.string("localizable.referral.rewards.view.arkadasini.davet.et.dfddcfd0", table: .localizable, fallback: "Arkadaşını davet et"))
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(Color.rdInk)
                Text(RDLocalization.string("localizable.referral.rewards.view.birlikte.plus.kazanin.0ad4e4eb", table: .localizable, fallback: "Birlikte Plus kazanın"))
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
                    Text(RDLocalization.format("localizable.referral.rewards.view.ikiniz.de.1.gun.plus.kazanin.4cda5cf0", table: .localizable, fallback: "İkiniz de %1$@ gün Plus kazanın", arguments: [String(describing: value.campaign.rewardDays)]))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.rdInk)
                    Text(RDLocalization.format("localizable.referral.rewards.view.arkadasin.kodunu.kabul.edip.1.gun.icinde.iki.far.ffba5873", table: .localizable, fallback: "Arkadaşın kodunu kabul edip %1$@ gün içinde, iki farklı günde gerçek bir işlem yaptığında ödülleriniz hazır olur.", arguments: [String(describing: value.campaign.qualificationWindowDays)]))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.rdCharcoal)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                stepPill("1", RDLocalization.string("localizable.referral.rewards.view.kodu.paylas.1d53f29d", table: .localizable, fallback: "Kodu paylaş"))
                Image(systemName: "chevron.right").foregroundStyle(Color.rdSlate)
                stepPill("2", RDLocalization.string("localizable.referral.rewards.view.2.gun.kullan.09722221", table: .localizable, fallback: "2 gün kullan"))
                Image(systemName: "chevron.right").foregroundStyle(Color.rdSlate)
                stepPill("3", RDLocalization.string("localizable.referral.rewards.view.odulu.ac.fa11f045", table: .localizable, fallback: "Ödülü aç"))
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
            Text(RDLocalization.string("localizable.referral.rewards.view.davet.kodun.a02ea628", table: .localizable, fallback: "Davet kodun"))
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
                    message = ReferralMessage(title: RDLocalization.string("localizable.referral.rewards.view.kod.kopyalandi.1d603165", table: .localizable, fallback: "Kod kopyalandı"), detail: RDLocalization.string("localizable.referral.rewards.view.davet.kodunu.istedigin.yerde.paylasabilirsin.85831c64", table: .localizable, fallback: "Davet kodunu istediğin yerde paylaşabilirsin."))
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
                Label(RDLocalization.string("localizable.referral.rewards.view.davet.baglantisini.paylas.5d971796", table: .localizable, fallback: "Davet bağlantısını paylaş"), systemImage: "square.and.arrow.up")
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
            metric(RDLocalization.string("localizable.referral.rewards.view.gonderilen.383f0546", table: .localizable, fallback: "Gönderilen"), value.counts.invited, "paperplane")
            metric("Tamamlayan", value.counts.qualified, "checkmark.circle")
            metric(RDLocalization.string("localizable.referral.rewards.view.odul.cbb24d10", table: .localizable, fallback: "Ödül"), value.counts.rewarded, "gift")
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
                sectionTitle(RDLocalization.string("localizable.referral.rewards.view.odullerin.a24ed38f", table: .localizable, fallback: "Ödüllerin"))
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
                Button(RDLocalization.string("localizable.referral.rewards.view.baslat.4655a757", table: .localizable, fallback: "Başlat")) {
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
            sectionTitle(RDLocalization.string("localizable.referral.rewards.view.bir.davet.kodun.mu.var.9cc6307c", table: .localizable, fallback: "Bir davet kodun mu var?"))
            Text(RDLocalization.string("localizable.referral.rewards.view.kodu.bir.kez.kabul.edebilirsin.kendi.kodun.kulla.a958ad09", table: .localizable, fallback: "Kodu bir kez kabul edebilirsin. Kendi kodun kullanılamaz."))
                .font(.system(size: 14))
                .foregroundStyle(Color.rdSlate)
            HStack(spacing: 10) {
                TextField(RDLocalization.string("localizable.referral.rewards.view.davet.kodu.7dcced4a", table: .localizable, fallback: "Davet kodu"), text: $claimCode)
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
                            Text(RDLocalization.format("localizable.referral.rewards.view.kabul.1.85a1d392", table: .localizable, fallback: "Kabul: %1$@", arguments: [String(describing: formatted(invite.claimedAt))]))
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
                    Label(RDLocalization.string("localizable.referral.rewards.view.nasil.calisir.7f5f24d1", table: .localizable, fallback: "Nasıl çalışır?"), systemImage: "info.circle")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.rdInk)
                    Spacer()
                    Image(systemName: termsExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Color.rdSlate)
                }
            }
            .buttonStyle(.plain)
            if termsExpanded {
                Text(RDLocalization.format("localizable.referral.rewards.view.davet.edilen.kisi.kodu.kabul.ettikten.sonra.1.gu.2a6be115", table: .localizable, fallback: "Davet edilen kişi kodu kabul ettikten sonra %1$@ gün içinde iki farklı günde personel, işyeri, departman, eğitim, risk değerlendirmesi, rapor veya tamamlanmış kontrol listesi işlemi yapmalıdır. Görüntüleme ve başarısız işlemler sayılmaz. Ödül mağaza aboneliği değildir; otomatik yenilenmez ve kotayı sıfırlamaz.", arguments: [String(describing: value.campaign.qualificationWindowDays)]))
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
            Text(RDLocalization.string("localizable.referral.rewards.view.davet.programi.hazirlaniyor.26b2461b", table: .localizable, fallback: "Davet programı hazırlanıyor"))
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
            Text(RDLocalization.string("localizable.referral.rewards.view.davet.bilgileri.alinamadi.8e6c5d74", table: .localizable, fallback: "Davet bilgileri alınamadı"))
                .font(.system(size: 18, weight: .bold))
            Button(RDLocalization.string("localizable.referral.rewards.view.tekrar.dene.a47c6a17", table: .localizable, fallback: "Tekrar dene")) { Task { await load() } }
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
            message = ReferralMessage(title: RDLocalization.string("localizable.referral.rewards.view.davet.programi.acilamadi.7bfb8b3b", table: .localizable, fallback: "Davet programı açılamadı"), detail: ReferralRewardsService.userMessage(for: error))
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
                title: result.replayed ? RDLocalization.string("localizable.referral.rewards.view.davet.zaten.bagli.51287f09", table: .localizable, fallback: "Davet zaten bağlı") : RDLocalization.string("localizable.referral.rewards.view.davet.kabul.edildi.69a1afed", table: .localizable, fallback: "Davet kabul edildi"),
                detail: RDLocalization.format("localizable.referral.rewards.view.1.farkli.gunde.gercek.bir.islem.yaptiginda.iki.t.f55cedd9", table: .localizable, fallback: "%1$@ farklı günde gerçek bir işlem yaptığında iki tarafın da ödülü hazır olacak.", arguments: [String(describing: result.qualificationDays ?? 2)])
            )
        } catch {
            message = ReferralMessage(title: RDLocalization.string("localizable.referral.rewards.view.kod.kullanilamadi.45305d7b", table: .localizable, fallback: "Kod kullanılamadı"), detail: ReferralRewardsService.userMessage(for: error))
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
                message = ReferralMessage(title: RDLocalization.string("localizable.referral.rewards.view.plus.odulun.basladi.75d8c45d", table: .localizable, fallback: "Plus ödülün başladı"), detail: RDLocalization.string("localizable.referral.rewards.view.7.gunluk.plus.erisimin.otomatik.yenileme.olmadan.7571bfa6", table: .localizable, fallback: "7 günlük Plus erişimin otomatik yenileme olmadan etkinleştirildi."))
            } else if result.reason == "PAID_ACCESS_ACTIVE" {
                message = ReferralMessage(title: RDLocalization.string("localizable.referral.rewards.view.odulun.guvende.4790c052", table: .localizable, fallback: "Ödülün güvende"), detail: RDLocalization.string("localizable.referral.rewards.view.aktif.ucretli.planin.varken.sureyi.baslatmiyoruz.befc94bc", table: .localizable, fallback: "Aktif ücretli planın varken süreyi başlatmıyoruz. Planın sona erdiğinde bu ekrandan kullanabilirsin."))
            } else if result.reason == "GIFT_ALREADY_ACTIVE" {
                message = ReferralMessage(title: RDLocalization.string("localizable.referral.rewards.view.aktif.bir.odulun.var.d05525ca", table: .localizable, fallback: "Aktif bir ödülün var"), detail: RDLocalization.string("localizable.referral.rewards.view.mevcut.hediye.suren.bittikten.sonra.siradaki.odu.dca2166b", table: .localizable, fallback: "Mevcut hediye süren bittikten sonra sıradaki ödülü başlatabilirsin."))
            }
        } catch {
            message = ReferralMessage(title: RDLocalization.string("localizable.referral.rewards.view.odul.baslatilamadi.2a212afb", table: .localizable, fallback: "Ödül başlatılamadı"), detail: ReferralRewardsService.userMessage(for: error))
        }
    }

    private func rewardTitle(_ reward: ReferralDashboard.Reward) -> String {
        switch reward.state {
        case "active": return RDLocalization.string("localizable.referral.rewards.view.plus.odulun.aktif.48d9b4d7", table: .localizable, fallback: "Plus ödülün aktif")
        case "expired": return RDLocalization.string("localizable.referral.rewards.view.plus.odulu.kullanildi.4edff412", table: .localizable, fallback: "Plus ödülü kullanıldı")
        default: return RDLocalization.string("localizable.referral.rewards.view.7.gunluk.plus.hazir.b21f5f3d", table: .localizable, fallback: "7 günlük Plus hazır")
        }
    }

    private func rewardDetail(_ reward: ReferralDashboard.Reward) -> String {
        if let expires = reward.expiresAt, reward.state == "active" {
            return RDLocalization.format("localizable.referral.rewards.view.1.tarihine.kadar.32918982", table: .localizable, fallback: "%1$@ tarihine kadar", arguments: [String(describing: formatted(expires))])
        }
        return reward.state == "expired" ? RDLocalization.string("localizable.referral.rewards.view.bu.odulun.suresi.tamamlandi.5282931a", table: .localizable, fallback: "Bu ödülün süresi tamamlandı") : RDLocalization.string("localizable.referral.rewards.view.hazir.oldugunda.sureyi.sen.baslat.9e8e7a8c", table: .localizable, fallback: "Hazır olduğunda süreyi sen başlat")
    }

    private func acceptedInviteText(_ invite: ReferralDashboard.Invite) -> String {
        switch invite.state {
        case "rewarded": return RDLocalization.string("localizable.referral.rewards.view.kosullari.tamamladin.odulun.hazir.45d7a0e5", table: .localizable, fallback: "Koşulları tamamladın; ödülün hazır.")
        case "qualified": return RDLocalization.string("localizable.referral.rewards.view.islemlerin.dogrulandi.odul.hazirlaniyor.3fba58fa", table: .localizable, fallback: "İşlemlerin doğrulandı; ödül hazırlanıyor.")
        default:
            return RDLocalization.format("localizable.referral.rewards.view.ilerleme.1.2.farkli.gun.ce754ede", table: .localizable, fallback: "İlerleme: %1$@/%2$@ farklı gün", arguments: [String(describing: invite.distinctDays ?? 0), String(describing: invite.requiredDays ?? 2)])
        }
    }

    private func statusTitle(_ state: String) -> String {
        switch state {
        case "rewarded": return RDLocalization.string("localizable.referral.rewards.view.odul.kazanildi.6890253c", table: .localizable, fallback: "Ödül kazanıldı")
        case "qualified": return RDLocalization.string("localizable.referral.rewards.view.kosul.tamamlandi.2e5811b4", table: .localizable, fallback: "Koşul tamamlandı")
        case "rejected", "expired": return RDLocalization.string("localizable.referral.rewards.view.davet.tamamlanmadi.a02c8209", table: .localizable, fallback: "Davet tamamlanmadı")
        default: return RDLocalization.string("localizable.referral.rewards.view.kodu.kabul.etti.f4903e56", table: .localizable, fallback: "Kodu kabul etti")
        }
    }

    private func statusBadge(_ state: String) -> String {
        switch state {
        case "rewarded": return RDLocalization.string("localizable.referral.rewards.view.kazanildi.0b3d242d", table: .localizable, fallback: "Kazanıldı")
        case "qualified": return RDLocalization.string("localizable.referral.rewards.view.tamamlandi.e605b999", table: .localizable, fallback: "Tamamlandı")
        case "rejected", "expired": return RDLocalization.string("localizable.referral.rewards.view.kapandi.b7c3fa64", table: .localizable, fallback: "Kapandı")
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
