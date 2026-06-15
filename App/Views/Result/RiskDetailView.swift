import SwiftUI
import UIKit

struct RiskDetailView: View {
    let finding: Finding
    var photoPath: String? = nil
    var localPreviewImage: UIImage? = nil
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var method: RiskMethod
    @State private var showPaywall = false
    private var preferredModalColorScheme: ColorScheme {
        app.themePreference.colorScheme ?? colorScheme
    }

    init(
        finding: Finding,
        method: RiskMethod = .fineKinney,
        photoPath: String? = nil,
        localPreviewImage: UIImage? = nil
    ) {
        self.finding = finding
        self.photoPath = photoPath
        self.localPreviewImage = localPreviewImage
        _method = State(initialValue: method)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    photoScoreCard
                    comparisonCard

                    section("Tehlike açıklaması", body: finding.description)
                    controlMeasuresSection
                    rootCauseSection
                    referenceSection

                    Color.clear.frame(height: 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .frame(width: 38, height: 38)
                    .background(Color.rdWhite.opacity(0.96))
                    .clipShape(Circle())
                    .shadow(color: Color.rdOnyx.opacity(0.14), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(RDPressableButtonStyle())
            .padding(.top, 10)
            .padding(.trailing, 18)
            .accessibilityLabel("Pencereyi kapat")
        }
        .background(Color.rdPaper)
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

    // MARK: - Header

    private var header: some View {
        let band = finding.band(for: method)
        return VStack(alignment: .leading, spacing: 8) {
            Text(finding.category.uppercased())
                .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(Color.rdSlate)

            Text(finding.displayTitle)
                .font(.system(size: RDFontScale.size(22), weight: .bold, design: .rounded))
                .tracking(-0.4)
                .foregroundStyle(Color.rdBlack)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                RDChip(level: band.level, label: band.label)
                Text("AI güveni %\(Int(finding.confidence * 100))")
                    .rdMono(size: 11, weight: .semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(Color.rdGreenDark)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.top, 4)
        }
    }

    private var photoScoreCard: some View {
        ZStack(alignment: .bottom) {
            ResultDetailPhoto(image: localPreviewImage, path: photoPath)
                .frame(height: 210)

            methodologyOverlay
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
    }

    // MARK: - Methodology

    private var methodologyOverlay: some View {
        let band = finding.band(for: method)
        let score = finding.score(for: method)

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(scoreDisplay(score))
                        .font(.system(size: RDFontScale.size(26), weight: .heavy, design: .monospaced))
                        .foregroundStyle(band.color)
                        .tracking(-0.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Text(band.action)
                    .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                    .foregroundStyle(band.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 4) {
                Text(method.fullName.uppercased())
                    .font(.system(size: RDFontScale.size(9), weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(Color.rdBlack.opacity(0.72))
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                Text("R = \(finding.formula(for: method))")
                    .rdMono(size: 10.5, weight: .semibold)
                    .foregroundStyle(Color.rdBlack.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .allowsTightening(true)
            }
            .frame(maxWidth: 190, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.50))
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .opacity(0.82)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.16), radius: 14, x: 0, y: 8)
    }

    private func scoreDisplay(_ score: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: Int(score))) ?? "\(Int(score))"
    }

    private var comparisonCard: some View {
        RDCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Yöntem karşılaştırması".uppercased())
                    .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(Color.rdSlate)

                HStack(spacing: 10) {
                    methodBox(
                        title: "Fine-Kinney",
                        formula: "O × F × Ş",
                        score: Int(finding.fkScore),
                        band: finding.fkBand,
                        active: method == .fineKinney,
                        targetMethod: .fineKinney
                    )
                    methodBox(
                        title: "5×5 L-Tipi",
                        formula: "O × Ş",
                        score: finding.m5Score,
                        band: finding.m5Band,
                        active: method == .matrix5x5,
                        targetMethod: .matrix5x5
                    )
                }
            }
        }
    }

    private func methodBox(title: String, formula: String, score: Int, band: RiskBand, active: Bool, targetMethod: RiskMethod) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                method = targetMethod
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                        .foregroundStyle(active ? Color.rdBlack : Color.rdSlate)
                    Text("R = \(formula)")
                        .rdMono(size: 10)
                        .foregroundStyle(Color.rdSlate)

                    Text(scoreDisplay(Double(score)))
                        .font(.system(size: RDFontScale.size(23), weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(band.color)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text(band.label)
                        .font(.system(size: RDFontScale.size(11), weight: .semibold, design: .rounded))
                        .foregroundStyle(band.color)
                }
                .padding(10)
                .frame(maxWidth: .infinity)

                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: RDFontScale.size(16), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdGreen)
                        .background(Circle().fill(Color.rdWhite))
                        .offset(x: -8, y: 8)
                }
            }
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(active ? Color.rdSelected : Color.rdLine, lineWidth: active ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    private var controlMeasuresSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Önlem / Kontrol tedbirleri".uppercased())
                .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(Color.rdSlate)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(finding.controlMeasures.indices, id: \.self) { index in
                    let measure = finding.controlMeasures[index]
                    (
                        Text("\(measure.displayTitle): ")
                            .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded)) +
                        Text(measure.text)
                            .font(.system(size: RDFontScale.size(14), design: .rounded))
                    )
                    .foregroundStyle(Color.rdGraphite)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rdGreenSoft)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Section

    private func section(_ title: String, body: String,
                         accent: Color = .rdFog, accentText: Color = .rdGraphite,
                         icon: String = "info.circle") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(Color.rdSlate)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                    .foregroundStyle(accentText)
                    .padding(.top, 1)
                Text(body)
                    .font(.system(size: RDFontScale.size(14), design: .rounded))
                    .foregroundStyle(accentText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var referenceSection: some View {
        if app.currentTier.isPaid {
            section("Mevzuat referansları", body: finding.references.isEmpty ? "Kontrol edilmeli" : finding.references,
                    accent: Color.rdFog, accentText: Color.rdGraphite,
                    icon: "books.vertical")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Mevzuat referansları".uppercased())
                        .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(Color.rdSlate)
                    RDTierBadge(tier: .plus, small: true)
                }

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showPaywall = true
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: RDFontScale.size(15), weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mevzuat Referansları Plus'ta Açıktır")
                                .font(.system(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                                .foregroundStyle(Color.rdBlack)
                            Text("İlgili kanun, yönetmelik ve standart karşılıklarını görmek için Plus veya Pro'ya geç.")
                                .font(.system(size: RDFontScale.size(11), design: .rounded))
                                .foregroundStyle(Color.rdSlate)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 8)

                        RDTierBadge(tier: .plus, small: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var rootCauseSection: some View {
        if app.currentTier.isPaid, !finding.rootCause.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            section("Kök neden", body: finding.rootCause,
                    accent: Color.rdPlanPlusSoft, accentText: Color.rdPlanPlusDark,
                    icon: "point.3.connected.trianglepath.dotted")
        }
    }
}

#Preview {
    RiskDetailView(finding: Finding.mock[0], method: .fineKinney)
        .environmentObject(AppState())
}

private struct ResultDetailPhoto: View {
    let image: UIImage?
    let path: String?
    @State private var remoteImage: UIImage?
    @State private var loadedPath: String?

    var body: some View {
        ZStack {
            if let remoteImage {
                Image(uiImage: remoteImage)
                    .resizable()
                    .scaledToFill()
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                AnalysisThumbnail(path: nil, cornerRadius: 16)
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task(id: path) {
            await loadRemoteIfNeeded()
        }
    }

    private func loadRemoteIfNeeded() async {
        guard let path, loadedPath != path else { return }
        loadedPath = path
        do {
            let data = try await AnalysisService.shared.photoData(path: path)
            if let downloaded = UIImage(data: data) {
                remoteImage = downloaded
            }
        } catch {
            remoteImage = nil
        }
    }
}
