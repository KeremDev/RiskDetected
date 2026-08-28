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
    var initialReaction: AnalysisItemReaction = .none
    var onReaction: ((AnalysisItemReaction) -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onGenerateReport: (() -> Void)? = nil

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var method: RiskMethod
    @State private var reaction: AnalysisItemReaction
    @State private var showPaywall = false

    private let green = Color(hex: "#35774A")
    private let greenDark = Color(hex: "#2E6B41")
    private let ink = Color(hex: "#1A1A1A")

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
        initialReaction: AnalysisItemReaction = .none,
        onReaction: ((AnalysisItemReaction) -> Void)? = nil,
        onEdit: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onGenerateReport: (() -> Void)? = nil
    ) {
        self.finding = finding
        self.photoPath = photoPath
        self.localPreviewImage = localPreviewImage
        self.photoIndex = max(1, photoIndex)
        self.showsRegulatoryReferences = showsRegulatoryReferences
        self.analysisTitle = analysisTitle
        self.analysisSector = analysisSector
        self.initialReaction = initialReaction
        self.onReaction = onReaction
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onGenerateReport = onGenerateReport
        _method = State(initialValue: method)
        _reaction = State(initialValue: initialReaction)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    hero
                    floatingActions
                    scoreBanner
                    hazardCard
                    detailBlocks
                }
            }
            .background(Color.white)

            Capsule()
                .fill(ink)
                .frame(width: 145, height: 5)
                .padding(.vertical, 11)
                .background(Color.white)
        }
        .background(Color.white.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showPaywall) {
            FreeAwarePaywallView(
                onClose: { showPaywall = false },
                onSubscribe: {
                    showPaywall = false
                    Task { await app.auth.refreshProfile() }
                }
            )
            .preferredColorScheme(preferredModalColorScheme)
        }
    }

    private var hero: some View {
        let band = finding.band(for: method)
        return ZStack {
            ResultDetailPhoto(image: localPreviewImage, path: photoPath, cornerRadius: 0)
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
                    roundReactionButton("hand.thumbsup", active: reaction == .like) { toggleReaction(.like) }
                    roundReactionButton("hand.thumbsdown", active: reaction == .dislike) { toggleReaction(.dislike) }
                }
                .padding(.horizontal, 14)
                .padding(.top, 58)

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(methodRiskBandLabel(band))
                            .font(referenceFont(8.5, .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(referenceRiskColor(band.level))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text("BULGU #F-\(String(format: "%04d", finding.id))")
                            .font(referenceFont(9, .bold))
                            .tracking(0.3)
                            .foregroundStyle(.white.opacity(0.72))
                        Spacer()
                        Text(scoreText(finding.score(for: method)))
                            .font(referenceFont(15, .heavy))
                            .foregroundStyle(.white)
                        Text(method == .fineKinney ? "PUAN" : "RİSK")
                            .font(referenceFont(9, .bold))
                            .foregroundStyle(.white.opacity(0.72))
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
        }
        // The HTML's 252 pt hero includes the status-bar region. SwiftUI shifts
        // ignored-safe-area content upward, so the safe-area allowance keeps
        // the visible hero at the reference height on Dynamic Island devices.
        .frame(height: 296)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("result.detail.photo_card")
        .overlay(alignment: .bottomTrailing) {
            Text("Foto \(photoIndex)")
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
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(greenDark)
                        .frame(width: 34, height: 34)
                        .background(Color(hex: "#EAF6EE"))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy("Rapor Oluştur", "Create Report"))
                            .font(referenceFont(13.5, .heavy)).foregroundStyle(ink)
                        Text(copy("Bu tehlikeye ait rapor oluşturulur", "Creates a report for this hazard"))
                            .font(referenceFont(9.5, .medium)).foregroundStyle(Color(hex: "#9A9A9A"))
                            .lineLimit(1).minimumScaleFactor(0.72)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: "#C4C4C4"))
                }
                .padding(.horizontal, 13)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: ink.opacity(0.18), radius: 8, x: 3, y: 5)
            }
            .buttonStyle(.plain)

            actionSquare("pencil", color: greenDark) { onEdit?() }
            actionSquare("trash", color: Color(hex: "#C9352B")) { onDelete?() }
            ShareLink(item: "\(finding.displayTitle)\n\n\(finding.description)") {
                actionSquareLabel("square.and.arrow.up", color: greenDark)
            }
            .buttonStyle(.plain)
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
                    Text(method == .fineKinney ? "PUAN" : "RİSK").font(referenceFont(8.5, .heavy)).opacity(0.78)
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

    private var hazardCard: some View {
        let band = finding.band(for: method)
        return HStack(spacing: 0) {
            Rectangle().fill(referenceRiskColor(band.level)).frame(width: 4)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(methodRiskBandLabel(band))
                        .font(referenceFont(8.5, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(referenceRiskColor(band.level)).clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(copy("BULGU BAŞLIĞI", "FINDING TITLE"))
                        .font(referenceFont(9, .heavy)).tracking(0.3).foregroundStyle(Color(hex: "#A0A0A0"))
                }
                Text(finding.displayTitle)
                    .font(referenceFont(15, .heavy)).foregroundStyle(ink).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                HStack(spacing: 6) {
                    Text(copy("TEHLİKE AÇIKLAMASI", "HAZARD DESCRIPTION"))
                        .font(referenceFont(9, .heavy)).tracking(0.3).foregroundStyle(Color(hex: "#A0A0A0"))
                    Rectangle().fill(Color(hex: "#ECECEC")).frame(height: 1)
                }
                .padding(.top, 12)
                Text(finding.description)
                    .font(referenceFont(12.5, .medium)).foregroundStyle(Color(hex: "#4D4D4D"))
                    .lineSpacing(5).fixedSize(horizontal: false, vertical: true).padding(.top, 7)
            }
            .padding(.leading, 11).padding(.trailing, 13).padding(.vertical, 13)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#E6E6E6"), lineWidth: 1))
        .padding(.horizontal, 20).padding(.top, 18)
    }

    private var detailBlocks: some View {
        VStack(spacing: 10) {
            if !finding.rootCause.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                detailBlock(
                    icon: "magnifyingglass", title: copy("KÖK NEDEN", "ROOT CAUSE"), tag: copy("Tespit", "Finding"),
                    lead: copy("Tehlikenin temel nedeni", "Underlying cause of the hazard"), text: finding.rootCause,
                    color: Color(hex: "#A66A13"), background: Color(hex: "#FFF8E8")
                )
            }

            let corrective = finding.controlMeasures.filter { $0.kind != .preventive }
            if !corrective.isEmpty {
                detailBlock(
                    icon: "wrench.and.screwdriver", title: copy("DÜZELTİCİ ÖNLEM", "CORRECTIVE ACTION"), tag: copy("Öncelikli", "Priority"),
                    lead: copy("Mevcut tehlikenin giderilmesi", "Eliminate the current hazard"), text: corrective.map(\.text).joined(separator: "\n"),
                    color: greenDark, background: Color(hex: "#EDF8F0")
                )
            }

            let preventive = finding.controlMeasures.filter { $0.kind == .preventive }
            if !preventive.isEmpty {
                detailBlock(
                    icon: "shield.checkered", title: copy("ÖNLEYİCİ FAALİYET", "PREVENTIVE ACTION"), tag: copy("Kalıcı", "Permanent"),
                    lead: copy("Tekrarını engelleyecek kontroller", "Controls to prevent recurrence"), text: preventive.map(\.text).joined(separator: "\n"),
                    color: Color(hex: "#2F6C55"), background: Color(hex: "#EFF8F4")
                )
            }

            if showsRegulatoryReferences { referenceBlock }
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 26)
    }

    @ViewBuilder
    private var referenceBlock: some View {
        if app.currentTier.isPaid {
            detailBlock(
                icon: "building.columns", title: copy("MEVZUAT", "REGULATORY REFERENCES"), tag: copy("Dayanak", "Basis"),
                lead: copy("İlgili yasal dayanaklar", "Applicable regulatory basis"),
                text: finding.references.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? copy("Doğrulanmış dayanak bulunmuyor.", "No verified reference available.") : finding.references,
                color: Color(hex: "#316A92"), background: Color(hex: "#EFF6FB")
            )
        } else {
            Button { showPaywall = true } label: {
                detailBlock(
                    icon: "lock.fill", title: copy("MEVZUAT", "REGULATORY REFERENCES"), tag: "PLUS",
                    lead: copy("Mevzuat referansları Plus ve Pro’da", "References are available with Plus and Pro"),
                    text: copy("İlgili doğrulanmış mevzuat dayanaklarını görmek için planını yükselt.", "Upgrade to view applicable verified references."),
                    color: Color(hex: "#316A92"), background: Color(hex: "#EFF6FB")
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func detailBlock(icon: String, title: String, tag: String, lead: String, text: String, color: Color, background: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
                Text(title).font(referenceFont(10, .heavy)).tracking(0.25).foregroundStyle(color)
                Text(tag).font(referenceFont(8.5, .heavy)).foregroundStyle(color)
                    .padding(.horizontal, 7).padding(.vertical, 3).background(color.opacity(0.10)).clipShape(Capsule())
                Spacer()
            }
            Text(lead).font(referenceFont(12.5, .heavy)).foregroundStyle(ink).lineSpacing(2).padding(.top, 9)
            Text(text).font(referenceFont(12, .regular)).foregroundStyle(Color(hex: "#575757"))
                .lineSpacing(5).fixedSize(horizontal: false, vertical: true).padding(.top, 5)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.17), lineWidth: 1))
    }

    private func factorRow(score: Double) -> some View {
        HStack(spacing: 4) {
            if method == .fineKinney {
                factor("O", finding.fk.probability); Text("×").opacity(0.5)
                factor("F", finding.fk.frequency); Text("×").opacity(0.5)
                factor("Ş", finding.fk.severity); Text("=").opacity(0.5)
            } else {
                factor("O", Double(finding.m5.probability)); Text("×").opacity(0.5)
                factor("Ş", Double(finding.m5.severity)); Text("=").opacity(0.5)
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
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36).background(Color(hex: "#0C140E").opacity(0.45)).clipShape(Circle())
        }.buttonStyle(.plain)
    }

    private func roundReactionButton(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: active ? "\(icon).fill" : icon)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(active ? green : Color(hex: "#0C140E").opacity(0.45)).clipShape(Circle())
        }.buttonStyle(.plain)
    }

    private func actionSquare(_ icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionSquareLabel(icon, color: color) }.buttonStyle(.plain)
    }

    private func actionSquareLabel(_ icon: String, color: Color) -> some View {
        Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(color)
            .frame(width: 48, height: 56).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: ink.opacity(0.18), radius: 8, x: 3, y: 5)
    }

    private func toggleReaction(_ value: AnalysisItemReaction) {
        let next: AnalysisItemReaction = reaction == value ? .none : value
        reaction = next
        onReaction?(next)
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
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func copy(_ tr: String, _ en: String) -> String { RDLanguage.current == .turkish ? tr : en }
    private func referenceFont(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        ResultTypography.font(size, weight)
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
