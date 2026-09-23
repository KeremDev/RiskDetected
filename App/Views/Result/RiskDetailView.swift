import SwiftUI
import UIKit

/// Finding detail copied from the supplied 440 × 956 HTML reference.
struct RiskDetailView: View {
    let finding: Finding
    var photoPath: String? = nil
    var localPreviewImage: UIImage? = nil
    var photoIndex: Int = 1
    var showsRegulatoryReferences: Bool = true
    var analysisTitle: String = ""
    var analysisSector: String? = nil
    var analysisID: UUID? = nil
    var analyticsItemID: String? = nil
    var analyticsSection: AnalysisResultSectionID = .riskAnalysis
    var feedbackLanguage: RDLanguage = .current
    var initialReaction: AnalysisItemReaction = .none
    var onReaction: ((AnalysisItemReaction, String?, String?) async -> Bool)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onGenerateReport: (() -> Void)? = nil
    var onShareReport: (() -> Void)? = nil

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.rdLayoutProfile) private var layoutProfile
    @State private var method: RiskMethod
    @State private var reaction: AnalysisItemReaction
    @State private var isReactionSaving = false
    @State private var pendingDislike = false
    @State private var feedbackComposerExpanded = false
    @State private var feedbackToastToken: UUID?
    @State private var showPaywall = false
    @State private var scoreExpanded = false

    private let green = Color.rdResultGreen
    private let greenDark = Color.rdResultGreenDark
    private let ink = Color.rdResultPrimaryText

    private var preferredModalColorScheme: ColorScheme {
        app.themePreference.colorScheme ?? colorScheme
    }

    init(
        finding: Finding,
        method: RiskMethod = .fineKinney,
        photoPath: String? = nil,
        localPreviewImage: UIImage? = nil,
        photoIndex: Int = 1,
        showsRegulatoryReferences: Bool = true,
        analysisTitle: String = "",
        analysisSector: String? = nil,
        analysisID: UUID? = nil,
        analyticsItemID: String? = nil,
        analyticsSection: AnalysisResultSectionID = .riskAnalysis,
        feedbackLanguage: RDLanguage = .current,
        initialReaction: AnalysisItemReaction = .none,
        onReaction: ((AnalysisItemReaction, String?, String?) async -> Bool)? = nil,
        onEdit: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onGenerateReport: (() -> Void)? = nil,
        onShareReport: (() -> Void)? = nil
    ) {
        self.finding = finding
        self.photoPath = photoPath
        self.localPreviewImage = localPreviewImage
        self.photoIndex = max(1, photoIndex)
        self.showsRegulatoryReferences = showsRegulatoryReferences
        self.analysisTitle = analysisTitle
        self.analysisSector = analysisSector
        self.analysisID = analysisID
        self.analyticsItemID = analyticsItemID
        self.analyticsSection = analyticsSection
        self.feedbackLanguage = feedbackLanguage
        self.initialReaction = initialReaction
        self.onReaction = onReaction
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onGenerateReport = onGenerateReport
        self.onShareReport = onShareReport
        _method = State(initialValue: method)
        _reaction = State(initialValue: initialReaction)
    }

    var body: some View {
        VStack(spacing: 0) {
            redesignedHeader
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    redesignedPhoto
                    redesignedTitle
                    findingSection(
                        title: finding.isScored
                            ? copy("analysis.risk.detail.v2.tehlike.aciklamasi.9083161c", "Ne gözlendi?", "What was observed?")
                            : copy("analysis.risk.detail.v2.uzman.aciklamasi.8e3abad9", "Uzman açıklaması", "Expert description"),
                        icon: "eye",
                        text: finding.description
                    )
                    redesignedMeasures
                    if !finding.rootCause.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        findingSection(
                            title: copy("analysis.risk.detail.v2.kok.neden.080d851e", "Kök neden", "Root cause"),
                            icon: "magnifyingglass",
                            text: finding.rootCause
                        )
                    }
                    if finding.isScored { redesignedScoreDisclosure }
                    if showsRegulatoryReferences { redesignedReferences }
                    membershipPromotionCard
                    redesignedFeedback
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
        }
        .background(Color.rdResultBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if onGenerateReport != nil {
                Button { onGenerateReport?() } label: {
                    Label(
                        copy("analysis.risk.detail.v2.raporu.indir.5caa46b4", "Rapor oluştur", "Create report"),
                        systemImage: "doc.badge.plus"
                    )
                    .font(referenceFont(15, .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(RDPressableButtonStyle())
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Color.rdResultBackground.opacity(0.98))
                .overlay(alignment: .top) { Divider() }
            }
        }
        .overlay(alignment: .top) {
            if feedbackToastToken != nil {
                FeedbackThanksToast(language: feedbackLanguage)
                    .padding(.horizontal, 20)
                    .padding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: feedbackToastToken)
        .overlay {
            if pendingDislike {
                DislikeFeedbackPanel(
                    language: feedbackLanguage,
                    isComposerExpanded: $feedbackComposerExpanded,
                    onClose: { pendingDislike = false },
                    onSubmit: { reason, note in
                        await submitDislike(reason: reason, note: note)
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(200)
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.88), value: pendingDislike)
        .fullScreenCover(isPresented: $showPaywall) {
            FreeAwarePaywallView(
                onClose: { showPaywall = false },
                onSubscribe: {
                    showPaywall = false
                    Task { await app.auth.refreshProfile() }
                }
            )
            .preferredColorScheme(.dark)
        }
    }

    private var redesignedHeader: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(RDTypography.font(size: 15, weight: .bold))
                    .foregroundStyle(ink)
                    .frame(width: 44, height: 44)
                    .background(Color.rdResultSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copy("analysis.risk.detail.view.pencereyi.kapat.cde23dc0", "Geri", "Back"))
            Text(copy("analysis.risk.detail.title", "Bulgu Detayı", "Finding Detail"))
                .font(referenceFont(19, .heavy))
                .foregroundStyle(ink)
            Spacer(minLength: 0)
            Menu {
                if let onEdit { Button(action: onEdit) { Label(RDLocalization.string("analysis.risk.detail.view.duzenle.82146ffa", table: .analysis, fallback: "Düzenle"), systemImage: "square.and.pencil") } }
                if let onShareReport { Button(action: onShareReport) { Label(RDLocalization.string("analysis.risk.detail.view.paylas.9fcb7d68", table: .analysis, fallback: "Paylaş"), systemImage: "square.and.arrow.up") } }
                if let onDelete { Button(role: .destructive, action: onDelete) { Label("Sil", systemImage: "trash") } }
            } label: {
                Image(systemName: "ellipsis")
                    .font(RDTypography.font(size: 15, weight: .bold))
                    .foregroundStyle(ink)
                    .frame(width: 44, height: 44)
                    .background(Color.rdResultSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel(RDLocalization.string("analysis.risk.detail.view.bulgu.islemleri.5b06133a", table: .analysis, fallback: "Bulgu işlemleri"))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
    }

    private var redesignedPhoto: some View {
        ResultDetailPhoto(image: localPreviewImage, path: photoPath, cornerRadius: 16)
            .frame(maxWidth: .infinity)
            .frame(height: localPreviewImage == nil && photoPath == nil ? 120 : 190)
            .background(Color.rdResultSubtleSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .bottomTrailing) {
                Label(RDLocalization.format("analysis.risk.detail.view.fotograf.1.cef4e007", table: .analysis, fallback: "Fotoğraf %1$@", arguments: [String(describing: photoIndex)]), systemImage: "photo")
                    .font(referenceFont(9.5, .bold))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.88))
                    .clipShape(Capsule())
                    .padding(9)
            }
            .accessibilityIdentifier("result.detail.photo_card")
    }

    private var redesignedTitle: some View {
        let band = finding.band(for: method)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle()
                    .fill(finding.isScored ? referenceRiskColor(band.level) : Color(hex: "#A66A13"))
                    .frame(width: 7, height: 7)
                Text(finding.isScored
                     ? methodRiskBandLabel(band)
                     : copy("analysis.risk.detail.v2.uzman.gorusu.81f7a08e", "Uzman görüşü", "Expert advice"))
                    .font(referenceFont(10.5, .heavy))
                    .foregroundStyle(finding.isScored ? referenceRiskColor(band.level) : Color(hex: "#A66A13"))
                Text("Bulgu #F-\(String(format: "%04d", finding.id))")
                    .font(referenceFont(9.5, .bold))
                    .foregroundStyle(Color.rdResultTertiaryText)
            }
            Text(finding.displayTitle)
                .font(referenceFont(22, .black))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            if !heroMeta.isEmpty {
                Text(heroMeta)
                    .font(referenceFont(11, .medium))
                    .foregroundStyle(Color.rdResultSecondaryText)
                    .lineLimit(2)
            }
        }
        .padding(.top, 14)
    }

    private var redesignedMeasures: some View {
        let corrective = finding.controlMeasures.filter { $0.kind != .preventive }
        let preventive = finding.controlMeasures.filter { $0.kind == .preventive }
        return VStack(spacing: 0) {
            if !corrective.isEmpty {
                findingSection(
                    title: copy("analysis.risk.detail.v2.duzeltici.onlem.12648a73", "Düzeltici önlem", "Corrective action"),
                    icon: "checkmark.seal",
                    text: corrective.map(\.text).joined(separator: "\n")
                )
            }
            if !preventive.isEmpty {
                findingSection(
                    title: copy("analysis.risk.detail.v2.onleyici.faaliyet.ad95a8ff", "Önleyici faaliyet", "Preventive action"),
                    icon: "shield",
                    text: preventive.map(\.text).joined(separator: "\n")
                )
            }
        }
    }

    private func findingSection(title: String, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.top, 16)
            Label(title, systemImage: icon)
                .font(referenceFont(12.5, .heavy))
                .foregroundStyle(ink)
            Text(text)
                .font(referenceFont(13, .regular))
                .foregroundStyle(Color.rdResultSecondaryText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var redesignedScoreDisclosure: some View {
        let band = finding.band(for: method)
        let score = finding.score(for: method)
        return VStack(alignment: .leading, spacing: 9) {
            Divider().padding(.top, 16)
            Picker(RDLocalization.string("analysis.risk.detail.view.risk.yontemi.eaa4f4ba", table: .analysis, fallback: "Risk yöntemi"), selection: $method) {
                Text("Fine-Kinney").tag(RiskMethod.fineKinney)
                Text("5×5").tag(RiskMethod.matrix5x5)
            }
            .pickerStyle(.segmented)
            Button { withAnimation(.easeOut(duration: 0.18)) { scoreExpanded.toggle() } } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(scoreText(score)) · \(methodRiskBandLabel(band))")
                            .font(referenceFont(15, .black))
                            .foregroundStyle(referenceRiskColor(band.level))
                        Text(method.fullName)
                            .font(referenceFont(9.5, .semibold))
                            .foregroundStyle(Color.rdResultSecondaryText)
                    }
                    Spacer(minLength: 0)
                    Text(RDLocalization.string("analysis.risk.detail.view.skor.nasil.olustu.8a08b396", table: .analysis, fallback: "Skor nasıl oluştu?"))
                        .font(referenceFont(10.5, .heavy))
                        .foregroundStyle(greenDark)
                    Image(systemName: scoreExpanded ? "chevron.up" : "chevron.down")
                        .font(RDTypography.font(size: 10, weight: .bold))
                }
                .padding(12)
                .background(referenceRiskColor(band.level).opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
            if scoreExpanded {
                factorRow(score: score)
                    .foregroundStyle(Color.rdResultSecondaryText)
                    .padding(.horizontal, 4)
            }
        }
        .accessibilityIdentifier("result.detail.score.disclosure")
    }

    @ViewBuilder private var redesignedReferences: some View {
        if app.currentTier.isPaid {
            findingSection(
                title: copy("analysis.risk.detail.v2.mevzuat.3eef1ac3", "Mevzuat ve ek bilgiler", "Regulatory references"),
                icon: "book",
                text: regulatoryReferenceText
            )
        } else {
            Button {
                beginPaywallEntry(at: .findingDetailRegulatoryReferences, targetTier: .plus)
                showPaywall = true
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "lock")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy("analysis.risk.detail.v2.mevzuat.3eef1ac3", "Mevzuat ve ek bilgiler", "Regulatory references"))
                            .font(referenceFont(12.5, .heavy))
                        Text(RDLocalization.string("analysis.risk.detail.view.plus.pro.ile.goruntule.0d40d1ff", table: .analysis, fallback: "Plus / Pro ile görüntüle"))
                            .font(referenceFont(10.5, .medium))
                            .foregroundStyle(Color.rdResultSecondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(ink)
                .padding(.top, 16)
            }
            .buttonStyle(.plain)
        }
    }

    private var redesignedFeedback: some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider().padding(.top, 16)
            Text(RDLocalization.string("analysis.risk.detail.view.bu.bulgu.faydali.miydi.c27c027f", table: .analysis, fallback: "Bu bulgu faydalı mıydı?"))
                .font(referenceFont(12.5, .heavy))
                .foregroundStyle(ink)
            HStack(spacing: 8) {
                feedbackButton(.like, symbol: "hand.thumbsup", label: RDLocalization.string("analysis.risk.detail.view.faydali.484e0d91", table: .analysis, fallback: "Faydalı"))
                feedbackButton(.dislike, symbol: "hand.thumbsdown", label: RDLocalization.string("analysis.risk.detail.view.faydali.degil.4b1c65d2", table: .analysis, fallback: "Faydalı değil"))
            }
        }
    }

    private func feedbackButton(_ value: AnalysisItemReaction, symbol: String, label: String) -> some View {
        let active = reaction == value
        return Button { handleReactionTap(value) } label: {
            Label(label, systemImage: active ? "\(symbol).fill" : symbol)
                .font(referenceFont(11.5, .heavy))
                .foregroundStyle(active ? greenDark : ink)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(active ? Color.rdResultGreenTint : Color.rdResultSurface)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(active ? green : Color.rdResultLine, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isReactionSaving)
    }

    private var hero: some View {
        let band = finding.band(for: method)
        return GeometryReader { proxy in
            ZStack {
                ResultDetailPhoto(image: localPreviewImage, path: photoPath, cornerRadius: 0)
                    .frame(width: proxy.size.width, height: proxy.size.height)

                LinearGradient(
                    colors: [
                        Color(hex: "#0C140E").opacity(0.62),
                        Color(hex: "#0C140E").opacity(0.12),
                        Color(hex: "#0C140E").opacity(0.20),
                        Color(hex: "#0C140E").opacity(0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: 0) {
                    HStack {
                        roundHeroButton("arrow.left") { dismiss() }
                            .accessibilityLabel(RDLocalization.string("analysis.risk.detail.view.pencereyi.kapat.cde23dc0", table: .analysis, fallback: "Pencereyi kapat"))
                            .accessibilityIdentifier("result.detail.close")
                        Spacer()
                        roundReactionButton("hand.thumbsup", active: reaction == .like) { handleReactionTap(.like) }
                            .disabled(isReactionSaving)
                            .accessibilityLabel(copy("analysis.risk.detail.v2.begen.c2cc0893", "Beğen", "Like"))
                            .accessibilityIdentifier("result.detail.like")
                        roundReactionButton("hand.thumbsdown", active: reaction == .dislike) { handleReactionTap(.dislike) }
                            .disabled(isReactionSaving)
                            .accessibilityLabel(copy("analysis.risk.detail.v2.begenme.8cc455ba", "Beğenme", "Dislike"))
                            .accessibilityIdentifier("result.detail.dislike")
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 58)

                    Spacer()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            if finding.isScored {
                                Text(methodRiskBandLabel(band))
                                    .font(referenceFont(8.5, .heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(referenceRiskColor(band.level))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                Text(copy("analysis.risk.detail.v2.uzman.gorusu.81f7a08e", "UZMAN GÖRÜŞÜ", "EXPERT ADVICE"))
                                    .font(referenceFont(8.5, .heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: "#A66A13"))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            Text("\(copy("analysis.risk.detail.v2.bulgu.e3e9e680", "BULGU", "FINDING")) #F-\(String(format: "%04d", finding.id))")
                                .font(referenceFont(9, .bold))
                                .tracking(0.3)
                                .foregroundStyle(.white.opacity(0.72))
                            Spacer()
                            if finding.isScored {
                                Text(scoreText(finding.score(for: method)))
                                    .font(referenceFont(15, .heavy))
                                    .foregroundStyle(.white)
                                Text(method == .fineKinney ? copy("analysis.risk.detail.v2.puan.371b8add", "PUAN", "POINTS") : copy("analysis.risk.detail.v2.risk.e2ab9b76", "RİSK", "RISK"))
                                    .font(referenceFont(9, .bold))
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                        }

                        Text(finding.displayTitle)
                            .font(referenceFont(13, .heavy))
                            .foregroundStyle(.white)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(heroMeta)
                            .font(referenceFont(10, .medium))
                            .foregroundStyle(.white.opacity(0.70))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .zIndex(1)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        // The HTML's 252 pt hero includes the status-bar region. SwiftUI shifts
        // ignored-safe-area content upward, so the safe-area allowance keeps
        // the visible hero at the reference height on Dynamic Island devices.
        .frame(height: layoutProfile.heightClass == .short ? 252 : 296)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("result.detail.photo_card")
        .overlay(alignment: .bottomTrailing) {
            Text(RDLocalization.format(
                "analysis.risk.detail.photo.short_label",
                table: .analysis,
                fallback: "Foto %1$@",
                arguments: [String(photoIndex)]
            ))
                .font(referenceFont(1, .regular))
                .foregroundStyle(Color.clear)
                .accessibilityLabel(RDLocalization.format("analysis.risk.detail.view.kaynak.fotograf.1.1bb24334", table: .analysis, fallback: "Kaynak fotoğraf %1$@", arguments: [String(photoIndex)]))
                .accessibilityIdentifier("result.detail.photo_index.\(photoIndex)")
        }
    }

    private var floatingActions: some View {
        HStack(spacing: 9) {
            Button { onGenerateReport?() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc")
                        .font(RDTypography.font(size: 16, weight: .semibold))
                        .foregroundStyle(greenDark)
                        .frame(width: 34, height: 34)
                        .background(Color.rdResultGreenTint)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy("analysis.risk.detail.v2.raporu.indir.5caa46b4", "Raporu İndir", "Download Report"))
                            .font(referenceFont(13.5, .heavy)).foregroundStyle(ink)
                        Text(
                            finding.isScored
                                ? copy("analysis.risk.detail.v2.bu.bulgu.standart.rapor.olarak.haz.rlan.r.9e4a8cc6", "Bu bulgu Standart Rapor olarak hazırlanır", "Creates a Standard Report for this finding")
                                : copy("analysis.risk.detail.v2.bu.gorus.standart.rapor.olarak.haz.rlan.r.6487fe4e", "Bu görüş Standart Rapor olarak hazırlanır", "Creates a Standard Report for this advice")
                        )
                            .font(referenceFont(9.5, .medium)).foregroundStyle(Color.rdResultTertiaryText)
                            .lineLimit(1).minimumScaleFactor(0.72)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(RDTypography.font(size: 12, weight: .bold)).foregroundStyle(Color.rdResultTertiaryText)
                }
                .padding(.horizontal, 13)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color.rdResultElevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: ink.opacity(0.18), radius: 8, x: 3, y: 5)
            }
            .buttonStyle(.plain)

            actionSquare("pencil", color: greenDark) { onEdit?() }
            actionSquare("trash", color: Color(hex: "#C9352B")) { onDelete?() }
            Button { onShareReport?() } label: {
                actionSquareLabel("square.and.arrow.up", color: greenDark)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copy("analysis.risk.detail.v2.raporu.paylas.b8f10f0a", "Raporu paylaş", "Share report"))
            .accessibilityIdentifier("result.detail.share_report")
        }
        .padding(.horizontal, 20)
        .offset(y: -20)
        .padding(.bottom, -20)
    }

    private var scoreBanner: some View {
        let score = finding.score(for: method)
        let band = finding.band(for: method)
        return ZStack {
            LinearGradient(
                colors: [referenceRiskColor(band.level), referenceRiskColor(band.level).opacity(0.76)],
                startPoint: .leading,
                endPoint: .trailing
            )
            Circle().fill(Color.white.opacity(0.09)).frame(width: 74, height: 74).offset(x: 155, y: -24)
            Circle().fill(Color.white.opacity(0.06)).frame(width: 56, height: 56).offset(x: 95, y: 35)

            HStack(spacing: 10) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(scoreText(score)).font(referenceFont(26, .heavy)).tracking(-1.2)
                    Text(method == .fineKinney ? copy("analysis.risk.detail.v2.puan.371b8add", "PUAN", "POINTS") : copy("analysis.risk.detail.v2.risk.e2ab9b76", "RİSK", "RISK"))
                        .font(referenceFont(8.5, .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .opacity(0.78)
                }
                Rectangle().fill(Color.white.opacity(0.28)).frame(width: 1, height: 26)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(method.fullName).font(referenceFont(10.5, .heavy))
                        Text(method.formula).font(referenceFont(9, .bold)).opacity(0.60)
                    }
                    factorRow(score: score)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
        }
        .frame(height: 66)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var expertSummaryBanner: some View {
        HStack(spacing: 11) {
            Image(systemName: "person.badge.shield.checkmark.fill")
                .font(RDTypography.font(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(copy("analysis.risk.detail.v2.uzman.gorusu.81f7a08e", "UZMAN GÖRÜŞÜ", "EXPERT ADVICE"))
                    .font(referenceFont(10.5, .heavy))
                    .tracking(0.4)
                Text(
                    finding.needsFieldVerification
                        ? copy("analysis.risk.detail.v2.saha.teyidi.ve.uzman.degerlendirmesi.gerek.03da05c6", "Saha teyidi ve uzman değerlendirmesi gerekir", "Field verification and expert review required")
                        : copy("analysis.risk.detail.v2.uzman.degerlendirmesi.c999e444", "Uzman değerlendirmesi", "Expert review")
                )
                .font(referenceFont(10.5, .medium))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 13)
        .frame(height: 66)
        .background(
            LinearGradient(
                colors: [Color(hex: "#7D561A"), Color(hex: "#A66A13")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .accessibilityIdentifier("result.detail.expert_summary")
    }

    private var hazardCard: some View {
        let band = finding.band(for: method)
        let accentColor = finding.isScored ? referenceRiskColor(band.level) : Color(hex: "#A66A13")
        return HStack(spacing: 0) {
            Rectangle().fill(accentColor).frame(width: 4)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    if finding.isScored {
                        Text(methodRiskBandLabel(band))
                            .font(referenceFont(8.5, .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(referenceRiskColor(band.level)).clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Text(copy("analysis.risk.detail.v2.uzman.gorusu.81f7a08e", "UZMAN GÖRÜŞÜ", "EXPERT ADVICE"))
                            .font(referenceFont(8.5, .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Color(hex: "#A66A13")).clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(finding.displayTitle)
                    .font(referenceFont(15, .heavy)).foregroundStyle(ink).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                HStack(spacing: 6) {
                    Text(
                        finding.isScored
                            ? copy("analysis.risk.detail.v2.tehlike.aciklamasi.9083161c", "TEHLİKE AÇIKLAMASI", "HAZARD DESCRIPTION")
                            : copy("analysis.risk.detail.v2.uzman.aciklamasi.8e3abad9", "UZMAN AÇIKLAMASI", "EXPERT DESCRIPTION")
                    )
                        .font(referenceFont(9, .heavy)).tracking(0.3).foregroundStyle(Color.rdResultTertiaryText)
                    Rectangle().fill(Color.rdResultLine).frame(height: 1)
                }
                .padding(.top, 12)
                Text(finding.description)
                    .font(referenceFont(12.5, .medium)).foregroundStyle(Color.rdResultSecondaryText)
                    .lineSpacing(5).fixedSize(horizontal: false, vertical: true).padding(.top, 7)
            }
            .padding(.leading, 11).padding(.trailing, 13).padding(.vertical, 13)
        }
        .background(Color.rdResultSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.rdResultLine, lineWidth: 1))
        .padding(.horizontal, 20).padding(.top, 18)
    }

    private var detailBlocks: some View {
        VStack(spacing: 10) {
            if !finding.rootCause.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                detailBlock(
                    icon: "magnifyingglass", title: copy("analysis.risk.detail.v2.kok.neden.080d851e", "KÖK NEDEN", "ROOT CAUSE"), tag: copy("analysis.risk.detail.v2.tespit.46928bb5", "Tespit", "Finding"),
                    lead: copy("analysis.risk.detail.v2.tehlikenin.temel.nedeni.108c3796", "Tehlikenin temel nedeni", "Underlying cause of the hazard"), text: finding.rootCause,
                    color: Color(hex: "#A66A13"), background: Color.rdResultAmberTint
                )
            }

            let corrective = finding.controlMeasures.filter { $0.kind != .preventive }
            if !corrective.isEmpty {
                detailBlock(
                    icon: "wrench.and.screwdriver", title: copy("analysis.risk.detail.v2.duzeltici.onlem.12648a73", "DÜZELTİCİ ÖNLEM", "CORRECTIVE ACTION"), tag: copy("analysis.risk.detail.v2.oncelikli.697a78d3", "Öncelikli", "Priority"),
                    lead: copy("analysis.risk.detail.v2.mevcut.tehlikenin.giderilmesi.76be5fb1", "Mevcut tehlikenin giderilmesi", "Eliminate the current hazard"), text: corrective.map(\.text).joined(separator: "\n"),
                    color: greenDark, background: Color.rdResultGreenTint
                )
            }

            membershipPromotionCard

            let preventive = finding.controlMeasures.filter { $0.kind == .preventive }
            if !preventive.isEmpty {
                detailBlock(
                    icon: "shield.checkered", title: copy("analysis.risk.detail.v2.onleyici.faaliyet.ad95a8ff", "ÖNLEYİCİ FAALİYET", "PREVENTIVE ACTION"), tag: copy("analysis.risk.detail.v2.kal.c.008b6870", "Kalıcı", "Permanent"),
                    lead: copy("analysis.risk.detail.v2.tekrar.n.engelleyecek.kontroller.f0df07c1", "Tekrarını engelleyecek kontroller", "Controls to prevent recurrence"), text: preventive.map(\.text).joined(separator: "\n"),
                    color: greenDark, background: Color.rdResultMintTint
                )
            }

            if showsRegulatoryReferences { referenceBlock }
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 26)
    }

    @ViewBuilder
    private var membershipPromotionCard: some View {
        switch app.currentTier {
        case .free:
            ResultMembershipPromotionCard(
                variant: .plusAndPro,
                title: copy("analysis.risk.detail.v2.analizini.plus.ve.pro.ile.guclendir.eebe6e13", "Analizini PLUS ve PRO ile güçlendir", "Power up your analysis with PLUS and PRO"),
                message: copy("analysis.risk.detail.v2.daha.detayl.analiz.uzman.gorusleri.ve.geli.0f8f55f6", "Daha detaylı analiz, uzman görüşleri ve gelişmiş raporlar için PLUS’a; Derin Araştırma, daha güçlü yapay zekâ ve sınırsız analiz için PRO’ya geç.", "Choose PLUS for more detailed analysis, expert advice and advanced reports; choose PRO for Deep Research, more capable AI and unlimited analyses."),
                actionTitle: copy("analysis.risk.detail.v2.planlar.incele.4fdf89b7", "Planları incele", "Explore plans")
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                beginPaywallEntry(at: .findingDetailPlusProPromotion, targetTier: .plus)
                showPaywall = true
            }
            .accessibilityHint(copy("analysis.risk.detail.v2.plus.ve.pro.abonelik.seceneklerini.acar.81aa104f", "PLUS ve PRO abonelik seçeneklerini açar", "Opens PLUS and PRO subscription options"))
            .accessibilityIdentifier("result.detail.plus_pro_promotion")

        case .plus:
            ResultMembershipPromotionCard(
                variant: .pro,
                title: copy("analysis.risk.detail.v2.analizini.pro.ile.guclendir.25dfc7da", "Analizini PRO ile güçlendir", "Power up your analysis with PRO"),
                message: copy("analysis.risk.detail.v2.analizlerinde.derin.arast.rma.ve.daha.gucl.bf1621f8", "Analizlerinde Derin Araştırma ve daha güçlü yapay zekâ modellerinden yararlan. PRO’ya geç; sınırsız analiz seni bekliyor.", "Use Deep Research and more capable AI models in your analyses. Upgrade to PRO—unlimited analyses are waiting."),
                actionTitle: copy("analysis.risk.detail.v2.pro.ya.gec.8176054d", "PRO'ya geç", "Upgrade to PRO")
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                beginPaywallEntry(at: .findingDetailProPromotion, targetTier: .pro)
                showPaywall = true
            }
            .accessibilityHint(copy("analysis.risk.detail.v2.pro.abonelik.ekran.n.acar.2ebb3f3f", "PRO abonelik ekranını açar", "Opens the PRO subscription screen"))
            .accessibilityIdentifier("result.detail.pro_promotion")

        case .pro:
            EmptyView()
        }
    }

    @ViewBuilder
    private var referenceBlock: some View {
        if app.currentTier.isPaid {
            detailBlock(
                icon: "building.columns", title: copy("analysis.risk.detail.v2.mevzuat.3eef1ac3", "MEVZUAT", "REGULATORY REFERENCES"), tag: copy("analysis.risk.detail.v2.dayanak.172f1e65", "Dayanak", "Basis"),
                lead: copy("analysis.risk.detail.v2.ilgili.yasal.dayanaklar.df4486ff", "İlgili yasal dayanaklar", "Applicable regulatory basis"),
                text: regulatoryReferenceText,
                color: Color(hex: "#4E8EB8"), background: Color.rdResultBlueTint
            )
        } else {
            Button {
                beginPaywallEntry(at: .findingDetailRegulatoryReferences, targetTier: .plus)
                showPaywall = true
            } label: {
                ZStack {
                    detailBlock(
                        icon: "building.columns", title: copy("analysis.risk.detail.v2.mevzuat.3eef1ac3", "MEVZUAT", "REGULATORY REFERENCES"), tag: copy("analysis.risk.detail.v2.dayanak.172f1e65", "Dayanak", "Basis"),
                        lead: copy("analysis.risk.detail.v2.ilgili.yasal.dayanaklar.df4486ff", "İlgili yasal dayanaklar", "Applicable regulatory basis"),
                        text: regulatoryReferenceText,
                        color: Color(hex: "#4E8EB8"), background: Color.rdResultBlueTint
                    )
                    .frame(maxWidth: .infinity, maxHeight: 154, alignment: .top)
                    .clipped()
                    .blur(radius: 6)
                    .opacity(0.74)
                    .accessibilityHidden(true)

                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: "building.columns")
                                .font(RDTypography.font(size: 15, weight: .semibold))
                            Text(copy("analysis.risk.detail.v2.mevzuat.3eef1ac3", "MEVZUAT", "REGULATORY REFERENCES"))
                                .font(referenceFont(10, .heavy))
                                .tracking(0.25)
                            Spacer()
                        }
                        .foregroundStyle(Color(hex: "#316A92"))
                        .padding(.horizontal, 12)
                        .padding(.top, 14)
                        Spacer()
                    }
                    .accessibilityHidden(true)

                    regulatoryPremiumCallout
                }
                .frame(maxWidth: .infinity, minHeight: 154, maxHeight: 154)
                .background(Color.rdResultBlueTint)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(copy("analysis.risk.detail.v2.mevzuat.referanslar.plus.ve.pro.da.bu.ozel.94661dc8", "Mevzuat referansları Plus ve Pro’da. Bu özellikler premium özelliktir.", "Regulatory references are available with Plus and Pro. These features are premium."))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("result.detail.references.premium_lock")
        }
    }

    private func beginPaywallEntry(
        at entryPoint: PaywallEntryPoint,
        targetTier: SubscriptionTier
    ) {
        PaywallEventService.shared.beginEntry(
            at: entryPoint,
            currentTier: app.currentTier,
            targetTier: targetTier,
            analysisID: analysisID,
            resultSection: analyticsSection,
            itemID: analyticsItemID ?? String(finding.id)
        )
    }

    private var regulatoryReferenceText: String {
        let references = finding.references.trimmingCharacters(in: .whitespacesAndNewlines)
        return references.isEmpty
            ? copy("analysis.risk.detail.v2.dogrulanm.s.dayanak.bulunmuyor.f65cff13", "Doğrulanmış dayanak bulunmuyor.", "No verified reference available.")
            : references
    }

    private var regulatoryPremiumCallout: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(Color(hex: "#E0A828"))
                Text("PLUS")
                    .foregroundStyle(Color(hex: "#A67C12"))
                Rectangle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: 1, height: 14)
                Image(systemName: "star.fill")
                    .foregroundStyle(green)
                Text("PRO")
                    .foregroundStyle(greenDark)
            }
            .font(referenceFont(12.5, .black))

            Text(copy("analysis.risk.detail.v2.bu.ozellikler.premium.ozelliktir.be3d321a", "Bu özellikler premium özelliktir.", "These features are premium."))
                .font(referenceFont(10.5, .semibold))
                .foregroundStyle(Color.rdResultSecondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.rdResultElevatedSurface.opacity(0.96))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "#E8762A"), Color(hex: "#E0A828"), Color(hex: "#4FAE7A"), Color(hex: "#1F8F9C")],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1.6
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .shadow(color: Color.black.opacity(0.12), radius: 7, x: 2, y: 5)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func detailBlock(icon: String, title: String, tag: String, lead: String, text: String, color: Color, background: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(RDTypography.font(size: 15, weight: .semibold)).foregroundStyle(color)
                Text(title).font(referenceFont(10, .heavy)).tracking(0.25).foregroundStyle(color)
                Text(tag).font(referenceFont(8.5, .heavy)).foregroundStyle(color)
                    .padding(.horizontal, 7).padding(.vertical, 3).background(color.opacity(0.10)).clipShape(Capsule())
                Spacer()
            }
            Text(lead).font(referenceFont(12.5, .heavy)).foregroundStyle(ink).lineSpacing(2).padding(.top, 9)
            Text(text).font(referenceFont(12, .regular)).foregroundStyle(Color.rdResultSecondaryText)
                .lineSpacing(5).fixedSize(horizontal: false, vertical: true).padding(.top, 5)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.17), lineWidth: 1))
    }

    private func factorRow(score: Double) -> some View {
        let probability = RDLanguage.current == .turkish ? "O" : "P"
        let severity = RDLanguage.current == .turkish ? "Ş" : "S"
        return HStack(spacing: 4) {
            if method == .fineKinney {
                factor(probability, finding.fk.probability); Text("×").opacity(0.5)
                factor("F", finding.fk.frequency); Text("×").opacity(0.5)
                factor(severity, finding.fk.severity); Text("=").opacity(0.5)
            } else {
                factor(probability, Double(finding.m5.probability)); Text("×").opacity(0.5)
                factor(severity, Double(finding.m5.severity)); Text("=").opacity(0.5)
            }
            Text(scoreText(score)).font(referenceFont(11.5, .heavy))
        }
        .font(referenceFont(10, .heavy))
    }

    private func factor(_ short: String, _ value: Double) -> some View {
        HStack(spacing: 3) {
            Text(short).font(referenceFont(8.5, .heavy)).opacity(0.75)
            Text(scoreText(value)).font(referenceFont(11, .heavy))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.white.opacity(0.16)).clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func roundHeroButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(RDTypography.font(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36).background(Color(hex: "#0C140E").opacity(0.45)).clipShape(Circle())
        }.buttonStyle(.plain)
    }

    private func roundReactionButton(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: active ? "\(icon).fill" : icon)
                .font(RDTypography.font(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(active ? green : Color(hex: "#0C140E").opacity(0.45)).clipShape(Circle())
        }.buttonStyle(.plain)
    }

    private func actionSquare(_ icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionSquareLabel(icon, color: color) }.buttonStyle(.plain)
    }

    private func actionSquareLabel(_ icon: String, color: Color) -> some View {
        Image(systemName: icon).font(RDTypography.font(size: 17, weight: .semibold)).foregroundStyle(color)
            .frame(width: 48, height: 56).background(Color.rdResultElevatedSurface).clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: ink.opacity(0.18), radius: 8, x: 3, y: 5)
    }

    private func handleReactionTap(_ value: AnalysisItemReaction) {
        guard !isReactionSaving else { return }

        if value == .dislike, reaction != .dislike {
            feedbackComposerExpanded = false
            pendingDislike = true
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }

        let next: AnalysisItemReaction = reaction == value ? .none : value
        Task { @MainActor in
            _ = await persistReaction(next, reason: nil, note: nil)
        }
    }

    @MainActor
    private func submitDislike(reason: String?, note: String?) async -> Bool {
        let saved = await persistReaction(.dislike, reason: reason, note: note)
        if saved { showFeedbackThanksToast() }
        return saved
    }

    @MainActor
    private func persistReaction(
        _ next: AnalysisItemReaction,
        reason: String?,
        note: String?
    ) async -> Bool {
        guard !isReactionSaving else { return false }
        let previous = reaction
        reaction = next

        guard let onReaction else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        }

        isReactionSaving = true
        let saved = await onReaction(next, reason, note)
        if !saved { reaction = previous }
        isReactionSaving = false
        UINotificationFeedbackGenerator().notificationOccurred(saved ? .success : .error)
        return saved
    }

    private func showFeedbackThanksToast() {
        let token = UUID()
        withAnimation { feedbackToastToken = token }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard feedbackToastToken == token else { return }
            withAnimation { feedbackToastToken = nil }
        }
    }

    private var heroMeta: String {
        [analysisSector?.trimmingCharacters(in: .whitespacesAndNewlines), analysisTitle.trimmingCharacters(in: .whitespacesAndNewlines)]
            .compactMap { value in guard let value, !value.isEmpty else { return nil }; return value }
            .joined(separator: " · ")
    }

    private func referenceRiskColor(_ level: RiskLevel) -> Color {
        switch level {
        case .critical: return Color(hex: "#C9352B")
        case .high: return Color(hex: "#DD6B20")
        case .medium: return Color(hex: "#C9A227")
        case .low: return green
        case .unknown: return Color(hex: "#8A8A8A")
        }
    }

    private func methodRiskBandLabel(_ band: RiskBand) -> String {
        let locale = Locale(identifier: RDLanguage.current == .turkish ? "tr_TR" : "en_US")
        return band.label.uppercased(with: locale)
    }

    private func scoreText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = RDLanguage.current.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func copy(_ key: String, _ tr: String, _ en: String) -> String {
        RDLocalization.string(key, table: .analysis, fallback: RDLanguage.current == .turkish ? tr : en)
    }
    private func referenceFont(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        RDTypography.font(size, weight)
    }
}

#Preview {
    RiskDetailView(finding: Finding.mock[0], method: .fineKinney, analysisTitle: "Şantiye Alanı", analysisSector: "İnşaat")
        .environmentObject(AppState())
}

private struct ResultDetailPhoto: View {
    let image: UIImage?
    let path: String?
    var cornerRadius: CGFloat = 16
    @State private var remoteImage: UIImage?
    @State private var loadedPath: String?

    var body: some View {
        ZStack {
            if let remoteImage {
                Image(uiImage: remoteImage).resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let image {
                Image(uiImage: image).resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AnalysisThumbnail(path: nil, cornerRadius: cornerRadius)
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: path) { await loadRemoteIfNeeded() }
    }

    private func loadRemoteIfNeeded() async {
        guard loadedPath != path else { return }
        loadedPath = path
        remoteImage = nil
        guard let path else { return }
        do {
            let data = try await AnalysisService.shared.photoData(path: path)
            if let downloaded = UIImage(data: data) { remoteImage = downloaded }
        } catch {
            remoteImage = nil
        }
    }
}
