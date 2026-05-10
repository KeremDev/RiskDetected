import SwiftUI
import UIKit

struct RiskDetailView: View {
    let finding: Finding
    var method: RiskMethod = .fineKinney
    var photoPath: String? = nil
    var localPreviewImage: UIImage? = nil
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                photoScoreCard
                comparisonCard

                section("Tehlike açıklaması", body: finding.description)
                section("Önerilen önlem", body: finding.action,
                        accent: Color.rdGreenSoft, accentText: Color.rdGreenDark,
                        icon: "shield.lefthalf.filled")
                referenceSection

                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.rdPaper)
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(
                onClose: { showPaywall = false },
                onSubscribe: {
                    showPaywall = false
                    Task { await app.auth.refreshProfile() }
                }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        let band = finding.band(for: method)
        return VStack(alignment: .leading, spacing: 8) {
            Text(finding.category.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(Color.rdSlate)

            Text(finding.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
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

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 7) {
                    Text("\(Int(score))")
                        .font(.system(size: 28, weight: .heavy, design: .monospaced))
                        .foregroundStyle(band.color)
                        .tracking(-0.6)
                    Text("R = \(finding.formula(for: method))")
                        .rdMono(size: 10.5, weight: .semibold)
                        .foregroundStyle(Color.rdBlack.opacity(0.78))
                        .lineLimit(1)
                }

                Text(band.action)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(band.color)
            }
            Spacer(minLength: 6)
            Text(method.fullName.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(Color.rdBlack.opacity(0.72))
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
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

    private var comparisonCard: some View {
        RDCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Yöntem karşılaştırması".uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(Color.rdSlate)

                HStack(spacing: 10) {
                    methodBox(
                        title: "Fine-Kinney",
                        formula: "O × F × Ş",
                        score: Int(finding.fkScore),
                        band: finding.fkBand,
                        active: method == .fineKinney
                    )
                    methodBox(
                        title: "5×5 L-Tipi",
                        formula: "O × Ş",
                        score: finding.m5Score,
                        band: finding.m5Band,
                        active: method == .matrix5x5
                    )
                }
            }
        }
    }

    private func methodBox(title: String, formula: String, score: Int, band: RiskBand, active: Bool) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(active ? Color.rdBlack : Color.rdSlate)
            Text("R = \(formula)")
                .rdMono(size: 10)
                .foregroundStyle(Color.rdSlate)

            Text("\(score)")
                .font(.system(size: 24, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(band.color)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(band.label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(band.color)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(active ? Color.rdSelected : Color.rdLine, lineWidth: active ? 1.5 : 1)
        )
    }

    // MARK: - Section

    private func section(_ title: String, body: String,
                         accent: Color = .rdFog, accentText: Color = .rdGraphite,
                         icon: String = "info.circle") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(Color.rdSlate)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentText)
                    .padding(.top, 1)
                Text(body)
                    .font(.system(size: 14, design: .rounded))
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
        if app.isPro {
            section("Standart referansları", body: finding.references,
                    accent: Color.rdFog, accentText: Color.rdGraphite,
                    icon: "books.vertical")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Standart referansları".uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(Color.rdSlate)
                    RDProBadge(small: true)
                }

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showPaywall = true
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Standart referansları PRO'da açıktır")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.rdBlack)
                            Text("Mevzuat, standart ve kaynak bağlantılarını görmek için yükselt.")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(Color.rdSlate)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 8)

                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                            Text("PRO")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(Color(hex: "#8A5A00"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(hex: "#FFF3C4"))
                        .clipShape(Capsule())
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
