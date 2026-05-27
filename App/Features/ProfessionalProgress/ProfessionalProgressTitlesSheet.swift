import SwiftUI

struct ProfessionalProgressTitlesSheet: View {
    let summary: ProfessionalProgressSummary

    @Environment(\.dismiss) private var dismiss
    @State private var showRankGuide = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 0) {
                progressHeader
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                rankGuideButton
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                titleSection("Temel Rütbeler", titles: Array(ProfessionalProgressTitle.allCases.prefix(3)))
                sectionDivider
                titleSection("Uzmanlık Rütbeleri", titles: Array(ProfessionalProgressTitle.allCases.dropFirst(3).prefix(3)))
                sectionDivider
                titleSection("Ustalık", titles: Array(ProfessionalProgressTitle.allCases.suffix(1)))
                Spacer(minLength: 0)
            }
            .background(Color.rdWhite)
        }
        .background(Color.rdWhite)
        .sheet(isPresented: $showRankGuide) {
            ProfessionalProgressRankGuideSheet(summary: summary)
                .presentationDetents([.height(560), .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack {
            RDModalCloseButton {
                dismiss()
            }
            .frame(width: 42, height: 42)

            Spacer()

            Text("Mesleki Ünvanlar")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdBlack)

            Spacer()

            Color.clear
                .frame(width: 42, height: 42)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.rdWhite)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.rdLine)
                .frame(height: 1)
        }
    }

    private var progressHeader: some View {
        ProfessionalProgressHomeCard(
            summary: summary,
            accessibilityIdentifier: "professionalProgress.titles.progress.card",
            displayStyle: .showcase
        )
    }

    private var rankGuideButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showRankGuide = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdPlanPlusDark)

                Text("Nasıl rütbe alırım?")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)

                Spacer()

                Image(systemName: "chevron.up.circle.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdSlate.opacity(0.65))
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Color.rdFog.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityLabel("Nasıl rütbe alırım")
    }

    private func titleSection(_ title: String, titles: [ProfessionalProgressTitle]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .padding(.horizontal, 24)

            LazyVGrid(columns: columns, alignment: .center, spacing: 12) {
                ForEach(titles) { professionalTitle in
                    rankTile(professionalTitle)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 12)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.rdFog)
            .frame(height: 6)
    }

    private func rankTile(_ title: ProfessionalProgressTitle) -> some View {
        let earned = summary.profile.totalMDP >= title.threshold
        let current = title == summary.currentTitle
        let style = RankVisualStyle(title: title)

        return VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                rankIcon(style: style, earned: earned, current: current)

                if current {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdPlanPlus)
                        .background(Circle().fill(Color.rdWhite).frame(width: 20, height: 20))
                        .offset(x: 3, y: -2)
                } else if !earned {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(Color.rdWhite)
                        .frame(width: 20, height: 20)
                        .background(Color.rdSlate.opacity(0.80))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.rdWhite, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }

            VStack(spacing: 1) {
                Text(title.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(earned ? Color.rdBlack : Color.rdSlate)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.70)

                Text("\(formattedNumber(title.threshold)) MDP")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(earned ? Color.rdSlate : Color.rdSlate.opacity(0.70))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(title.label), \(earned ? "kazanıldı" : "henüz kazanılmadı")")
    }

    private func rankIcon(style: RankVisualStyle, earned: Bool, current: Bool) -> some View {
        ZStack {
            Circle()
                .fill(earned ? style.background : lockedIconBackground)
                .frame(width: 58, height: 58)
                .shadow(color: earned ? style.shadow : Color.rdSlate.opacity(0.12), radius: earned ? 12 : 7, x: 0, y: 5)

            Circle()
                .stroke(earned ? Color.rdWhite : Color.rdLine, lineWidth: 4)
                .frame(width: 58, height: 58)

            Circle()
                .stroke(current ? Color.rdPlanPlus.opacity(0.95) : Color.clear, lineWidth: 3)
                .frame(width: 66, height: 66)

            Image(systemName: style.symbol)
                .font(.system(size: 23, weight: .black, design: .rounded))
                .foregroundStyle(earned ? style.foreground : Color.rdSlate.opacity(0.45))
                .symbolRenderingMode(.hierarchical)

            if earned {
                Image(systemName: "sparkle")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .offset(x: 17, y: -17)
            }
        }
        .frame(width: 70, height: 70)
    }

    private var lockedIconBackground: LinearGradient {
        LinearGradient(
            colors: [Color.rdFog, Color(hex: "#E5E9EC")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func formattedNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private struct RankVisualStyle {
    let symbol: String
    let background: LinearGradient
    let foreground: Color
    let shadow: Color

    init(title: ProfessionalProgressTitle) {
        switch title {
        case .candidate:
            symbol = "person.crop.circle.badge.checkmark"
            foreground = Color(hex: "#087C5B")
            shadow = Color(hex: "#00B894").opacity(0.26)
            background = Self.gradient("#DDFCF0", "#48CFAE")
        case .fieldObserver:
            symbol = "binoculars.fill"
            foreground = Color(hex: "#9A5B00")
            shadow = Color(hex: "#C57A12").opacity(0.26)
            background = Self.gradient("#FFF2D4", "#D59A45")
        case .riskHunter:
            symbol = "scope"
            foreground = Color(hex: "#8F421D")
            shadow = Color(hex: "#A15C38").opacity(0.28)
            background = Self.gradient("#FFE1D0", "#B66A45")
        case .hazardAnalyst:
            symbol = "exclamationmark.triangle.fill"
            foreground = Color(hex: "#8F2B13")
            shadow = Color(hex: "#E85D35").opacity(0.28)
            background = Self.gradient("#FFE1D6", "#F97345")
        case .seniorRiskSpecialist:
            symbol = "shield.checkered"
            foreground = Color(hex: "#4F6F98")
            shadow = Color(hex: "#8EA0B8").opacity(0.30)
            background = Self.gradient("#E8F1FF", "#93A9C8")
        case .safetyStrategist:
            symbol = "flag.checkered"
            foreground = Color.rdPlanPlusDark
            shadow = Color.rdPlanPlus.opacity(0.32)
            background = Self.gradient("#FFF3BF", "#F0A400")
        case .masterHSESpecialist:
            symbol = "crown.fill"
            foreground = Color(hex: "#102A43")
            shadow = Color(hex: "#102A43").opacity(0.24)
            background = Self.gradient("#DDEBFF", "#476B97")
        }
    }

    private static func gradient(_ top: String, _ bottom: String) -> LinearGradient {
        LinearGradient(
            colors: [Color(hex: top), Color(hex: bottom)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct ProfessionalProgressRankGuideSheet: View {
    let summary: ProfessionalProgressSummary

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    statusCard
                    actionHintCard
                    rulesCard
                    guardrailCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 26)
            }
            .background(Color.rdPaper)
            .navigationTitle("Rütbe Puanlama")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    RDModalCloseButton {
                        dismiss()
                    }
                }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Color.rdPlanPlusDark)
                    .frame(width: 44, height: 44)
                    .background(Color.rdPlanPlus.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.currentTitle.label)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(nextTitleStatusText)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                statPill(value: formattedNumber(summary.profile.totalMDP), label: "Toplam MDP")
                statPill(value: formattedNumber(summary.nextTitleRemaining), label: "Kalan MDP")
            }
        }
        .padding(16)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: RDRadius.lg)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
    }

    private var actionHintCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.up.forward.circle.fill")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreenDark)
                .frame(width: 38, height: 38)
                .background(Color.rdGreenSoft)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Sana en yakın adım")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                Text(actionHintText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.rdGreenSoft.opacity(0.62), Color.rdWhite],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: RDRadius.lg)
                .stroke(Color.rdGreen.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
    }

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MDP nasıl kazanılır?")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdBlack)

            VStack(spacing: 9) {
                scoreRow(icon: "doc.text.fill", title: "Rapor oluştur", points: "+60 MDP", detail: "Her yeni rapor bir kez puan verir.")
                scoreRow(icon: "tablecells.fill", title: "Risk analizi PDF/XLSX", points: "+90 MDP", detail: "Standart rapor puanına eklenir.")
                scoreRow(icon: "shield.lefthalf.filled", title: "Yüksek/kritik riskli analiz", points: "+120 MDP", detail: "Tehlikeyi görünür kıldığında kazanılır.")
                scoreRow(icon: "magnifyingglass.circle.fill", title: "Detaylı analiz", points: "+70 MDP", detail: "Standart dışı detaylı analizlerde işler.")
                scoreRow(icon: "square.grid.3x2.fill", title: "İlk yetkinlik alanı", points: "+20 MDP", detail: "Her alan için yalnızca ilk kez verilir.")
                scoreRow(icon: "calendar.badge.checkmark", title: "Haftanın ilk raporu", points: "+25 MDP", detail: "Haftada bir kez takip disiplini bonusu.")
            }
        }
        .padding(16)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: RDRadius.lg)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
    }

    private var guardrailCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                Text("Puanlar gerçek iş çıktısından gelir.")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
            }

            Text("Uygulamaya giriş yapmak puan vermez. Aynı analiz veya rapor tekrar işlense bile yeniden MDP yazılmaz. Aynı saha çalışmasından gelen analiz ve raporlar adil ilerleme için sınırlı hesaplanır.")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.rdFog.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
    }

    private func scoreRow(icon: String, title: String, points: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .frame(width: 30, height: 30)
                .background(Color.rdFog)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Text(detail)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(points)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdPlanPlusDark)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(Color.rdPlanPlus.opacity(0.14))
                .clipShape(Capsule())
        }
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .rdMono(size: 17, weight: .bold)
                .foregroundStyle(Color.rdBlack)
            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.rdFog.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var nextTitleStatusText: String {
        guard let nextTitle = summary.nextTitle else {
            return "En üst rütbedesin. Birikimin profilinde korunur."
        }
        return "\(nextTitle.label) için \(formattedNumber(summary.nextTitleRemaining)) MDP kaldı."
    }

    private var actionHintText: String {
        if summary.weeklyTracking.reportsCount == 0, summary.weeklyTracking.analysesCount > 0 {
            return "\(summary.weeklyTracking.analysesCount) analiz tamamlandı. Birini rapora dönüştürerek +60 MDP kazanabilirsin."
        }
        if summary.weeklyTracking.reportsCount == 0 {
            return "Bu hafta ilk raporunu oluşturursan +60 MDP ve +25 haftalık bonus kazanırsın."
        }
        if summary.profile.highFindings + summary.profile.criticalFindings == 0 {
            return "Yüksek veya kritik riskleri doğru sınıflandırmak +120 MDP katkı sağlar."
        }
        return "Yeni raporlar ve farklı yetkinlik alanları rütbe ilerlemeni hızlandırır."
    }

    private func formattedNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
