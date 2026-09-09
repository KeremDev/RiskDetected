import SwiftUI

struct ProfessionalProgressTitlesSheet: View {
    let summary: ProfessionalProgressSummary

    @Environment(\.dismiss) private var dismiss
    @State private var showRankGuide = false

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private let rankIconCircleSize: CGFloat = 50
    private let rankIconOuterRingSize: CGFloat = 58
    private let rankIconFrameSize: CGFloat = 62

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

                titleSection(RDLocalization.string("professionalprogress.professional.progress.titles.sheet.temel.rutbeler.ae685d59", table: .professionalProgress, fallback: "Temel Rütbeler"), titles: Array(ProfessionalProgressTitle.allCases.prefix(3)))
                sectionDivider
                titleSection(RDLocalization.string("professionalprogress.professional.progress.titles.sheet.uzmanlik.rutbeleri.adc7d11a", table: .professionalProgress, fallback: "Uzmanlık Rütbeleri"), titles: Array(ProfessionalProgressTitle.allCases.dropFirst(3).prefix(3)))
                sectionDivider
                titleSection(RDLocalization.string("professionalprogress.professional.progress.titles.sheet.ustalik.0d958d48", table: .professionalProgress, fallback: "Ustalık"), titles: Array(ProfessionalProgressTitle.allCases.suffix(1)))
                Spacer(minLength: 0)
            }
            .background(Color.rdWhite)
        }
        .background(Color.rdWhite)
        .sheet(isPresented: $showRankGuide) {
            ProfessionalProgressRankGuideSheet(summary: summary)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack {
            RDModalCloseButton {
                dismiss()
            }
            .scaleEffect(0.86)
            .frame(width: 34, height: 34)

            Spacer()

            Text(RDLocalization.string("professionalprogress.professional.progress.titles.sheet.mesleki.unvanlar.20cd00f4", table: .professionalProgress, fallback: "Mesleki Ünvanlar"))
                .font(RDTypography.font(size: RDFontScale.size(16), weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer()

            Color.clear
                .frame(width: 34, height: 34)
        }
        .padding(.horizontal, 18)
        .padding(.top, 24)
        .padding(.bottom, 8)
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
                    .font(RDTypography.font(size: RDFontScale.size(16), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdPlanPlusDark)

                Text(RDLocalization.string("professionalprogress.professional.progress.titles.sheet.nasil.rutbe.alirim.ba68ce6d", table: .professionalProgress, fallback: "Nasıl rütbe alırım?"))
                    .font(RDTypography.font(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)

                Spacer()

                Image(systemName: "chevron.up.circle.fill")
                    .font(RDTypography.font(size: RDFontScale.size(16), weight: .bold, design: .rounded))
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
        .accessibilityLabel(RDLocalization.string("professionalprogress.professional.progress.titles.sheet.nasil.rutbe.alirim.9a8647bb", table: .professionalProgress, fallback: "Nasıl rütbe alırım"))
    }

    private func titleSection(_ title: String, titles: [ProfessionalProgressTitle]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(RDTypography.font(size: RDFontScale.size(16), weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .padding(.horizontal, 24)

            LazyVGrid(columns: columns, alignment: .center, spacing: 12) {
                ForEach(titles) { professionalTitle in
                    rankTile(professionalTitle)
                }
            }
            .padding(.horizontal, 20)
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
                        .font(RDTypography.font(size: RDFontScale.size(14), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdPlanPlus)
                        .background(Circle().fill(Color.rdWhite).frame(width: 18, height: 18))
                        .offset(x: 2, y: -2)
                } else if !earned {
                    Image(systemName: "lock.fill")
                        .font(RDTypography.font(size: RDFontScale.size(8), weight: .black, design: .rounded))
                        .foregroundStyle(Color.rdWhite)
                        .frame(width: 18, height: 18)
                        .background(Color.rdSlate.opacity(0.80))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.rdWhite, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }

            VStack(spacing: 1) {
                Text(title.label)
                    .font(RDTypography.font(size: RDFontScale.size(11), weight: .semibold, design: .rounded))
                    .foregroundStyle(earned ? Color.rdBlack : Color.rdSlate)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.70)

                Text(RDLocalization.format("professionalprogress.professional.progress.titles.sheet.1.mdp.0657733e", table: .professionalProgress, fallback: "%1$@ MDP", arguments: [String(describing: formattedNumber(title.threshold))]))
                    .font(RDTypography.font(size: RDFontScale.size(9), weight: .semibold, design: .rounded))
                    .foregroundStyle(earned ? Color.rdSlate : Color.rdSlate.opacity(0.70))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(
            RDLocalization.format(
                "progress.accessibility.title_status",
                table: .professionalProgress,
                fallback: "%1$@, %2$@",
                arguments: [
                    title.label,
                    earned
                        ? RDLocalization.string(
                            "progress.accessibility.earned",
                            table: .professionalProgress,
                            fallback: "kazanıldı"
                        )
                        : RDLocalization.string(
                            "progress.accessibility.not_earned",
                            table: .professionalProgress,
                            fallback: "henüz kazanılmadı"
                        ),
                ]
            )
        )
    }

    private func rankIcon(style: RankVisualStyle, earned: Bool, current: Bool) -> some View {
        ZStack {
            Circle()
                .fill(earned ? style.background : lockedIconBackground)
                .frame(width: rankIconCircleSize, height: rankIconCircleSize)
                .shadow(color: earned ? style.shadow : Color.rdSlate.opacity(0.12), radius: earned ? 12 : 7, x: 0, y: 5)

            Circle()
                .stroke(earned ? Color.rdWhite : Color.rdLine, lineWidth: 4)
                .frame(width: rankIconCircleSize, height: rankIconCircleSize)

            Circle()
                .stroke(current ? Color.rdPlanPlus.opacity(0.95) : Color.clear, lineWidth: 3)
                .frame(width: rankIconOuterRingSize, height: rankIconOuterRingSize)

            Image(systemName: style.symbol)
                .font(RDTypography.font(size: RDFontScale.size(19), weight: .black, design: .rounded))
                .foregroundStyle(earned ? style.foreground : Color.rdSlate.opacity(0.45))
                .symbolRenderingMode(.hierarchical)

            if earned {
                Image(systemName: "sparkle")
                    .font(RDTypography.font(size: RDFontScale.size(7), weight: .black, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .offset(x: 14, y: -14)
            }
        }
        .frame(width: rankIconFrameSize, height: rankIconFrameSize)
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
            .navigationTitle(RDLocalization.string("professionalprogress.professional.progress.titles.sheet.rutbe.puanlama.7bbebefb", table: .professionalProgress, fallback: "Rütbe Puanlama"))
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
                    .font(RDTypography.font(size: RDFontScale.size(22), weight: .black, design: .rounded))
                    .foregroundStyle(Color.rdPlanPlusDark)
                    .frame(width: 44, height: 44)
                    .background(Color.rdPlanPlus.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.currentTitle.label)
                        .font(RDTypography.font(size: RDFontScale.size(20), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(nextTitleStatusText)
                        .font(RDTypography.font(size: RDFontScale.size(12.5), weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                statPill(value: formattedNumber(summary.profile.totalMDP), label: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.toplam.mdp.f0ea764d", table: .professionalProgress, fallback: "Toplam MDP"))
                statPill(value: formattedNumber(summary.nextTitleRemaining), label: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.kalan.mdp.f71caff4", table: .professionalProgress, fallback: "Kalan MDP"))
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
                .font(RDTypography.font(size: RDFontScale.size(20), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreenDark)
                .frame(width: 38, height: 38)
                .background(Color.rdGreenSoft)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(RDLocalization.string("professionalprogress.professional.progress.titles.sheet.sana.en.yakin.adim.996c4c7d", table: .professionalProgress, fallback: "Sana en yakın adım"))
                    .font(RDTypography.font(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                Text(actionHintText)
                    .font(RDTypography.font(size: RDFontScale.size(15), weight: .bold, design: .rounded))
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
            Text(RDLocalization.string("professionalprogress.professional.progress.titles.sheet.mdp.nasil.kazanilir.6d3aeefc", table: .professionalProgress, fallback: "MDP nasıl kazanılır?"))
                .font(RDTypography.font(size: RDFontScale.size(17), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdBlack)

            VStack(spacing: 9) {
                scoreRow(icon: "doc.text.fill", title: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.rapor.olustur.5f96ad63", table: .professionalProgress, fallback: "Rapor oluştur"), points: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.60.mdp.1f989881", table: .professionalProgress, fallback: "+60 MDP"), detail: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.her.yeni.rapor.bir.kez.puan.verir.e2c8fe15", table: .professionalProgress, fallback: "Her yeni rapor bir kez puan verir."))
                scoreRow(icon: "tablecells.fill", title: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.risk.analizi.pdf.xlsx.910caae2", table: .professionalProgress, fallback: "Risk analizi PDF/XLSX"), points: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.90.mdp.96c72589", table: .professionalProgress, fallback: "+90 MDP"), detail: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.standart.rapor.puanina.eklenir.2fbe2c93", table: .professionalProgress, fallback: "Standart rapor puanına eklenir."))
                scoreRow(icon: "shield.lefthalf.filled", title: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.yuksek.kritik.riskli.analiz.c31153a6", table: .professionalProgress, fallback: "Yüksek/kritik riskli analiz"), points: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.120.mdp.7316b2eb", table: .professionalProgress, fallback: "+120 MDP"), detail: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.tehlikeyi.gorunur.kildiginda.kazanilir.8c66d951", table: .professionalProgress, fallback: "Tehlikeyi görünür kıldığında kazanılır."))
                scoreRow(icon: "magnifyingglass.circle.fill", title: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.detayli.analiz.7a12c895", table: .professionalProgress, fallback: "Detaylı analiz"), points: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.70.mdp.6acf724a", table: .professionalProgress, fallback: "+70 MDP"), detail: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.standart.disi.detayli.analizlerde.isler.2aa4f581", table: .professionalProgress, fallback: "Standart dışı detaylı analizlerde işler."))
                scoreRow(icon: "square.grid.3x2.fill", title: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.ilk.yetkinlik.alani.42920cb0", table: .professionalProgress, fallback: "İlk yetkinlik alanı"), points: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.20.mdp.aa9eb553", table: .professionalProgress, fallback: "+20 MDP"), detail: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.her.alan.icin.yalnizca.ilk.kez.verilir.c2b98db3", table: .professionalProgress, fallback: "Her alan için yalnızca ilk kez verilir."))
                scoreRow(icon: "calendar.badge.checkmark", title: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.haftanin.ilk.raporu.dce7285a", table: .professionalProgress, fallback: "Haftanın ilk raporu"), points: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.25.mdp.c7974c89", table: .professionalProgress, fallback: "+25 MDP"), detail: RDLocalization.string("professionalprogress.professional.progress.titles.sheet.haftada.bir.kez.takip.disiplini.bonusu.e4efaa1c", table: .professionalProgress, fallback: "Haftada bir kez takip disiplini bonusu."))
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
                    .font(RDTypography.font(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                Text(RDLocalization.string("professionalprogress.professional.progress.titles.sheet.puanlar.gercek.is.ciktisindan.gelir.f2b509b4", table: .professionalProgress, fallback: "Puanlar gerçek iş çıktısından gelir."))
                    .font(RDTypography.font(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
            }

            Text(RDLocalization.string("professionalprogress.professional.progress.titles.sheet.uygulamaya.giris.yapmak.puan.vermez.ayni.analiz..3eefe37a", table: .professionalProgress, fallback: "Uygulamaya giriş yapmak puan vermez. Aynı analiz veya rapor tekrar işlense bile yeniden MDP yazılmaz. Aynı saha çalışmasından gelen analiz ve raporlar adil ilerleme için sınırlı hesaplanır."))
                .font(RDTypography.font(size: RDFontScale.size(12.5), weight: .medium, design: .rounded))
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
                .font(RDTypography.font(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .frame(width: 30, height: 30)
                .background(Color.rdFog)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RDTypography.font(size: RDFontScale.size(13.5), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Text(detail)
                    .font(RDTypography.font(size: RDFontScale.size(11.5), weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(points)
                .font(RDTypography.font(size: RDFontScale.size(12.5), weight: .bold, design: .rounded))
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
                .font(RDTypography.font(size: RDFontScale.size(10.5), weight: .semibold, design: .rounded))
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
            return RDLocalization.string("professionalprogress.professional.progress.titles.sheet.en.ust.rutbedesin.birikimin.profilinde.korunur.32f9a051", table: .professionalProgress, fallback: "En üst rütbedesin. Birikimin profilinde korunur.")
        }
        return RDLocalization.format("professionalprogress.professional.progress.titles.sheet.1.icin.2.mdp.kaldi.7f112857", table: .professionalProgress, fallback: "%1$@ için %2$@ MDP kaldı.", arguments: [String(describing: nextTitle.label), String(describing: formattedNumber(summary.nextTitleRemaining))])
    }

    private var actionHintText: String {
        if summary.weeklyTracking.reportsCount == 0, summary.weeklyTracking.analysesCount > 0 {
            return RDLocalization.format("professionalprogress.professional.progress.titles.sheet.1.analiz.tamamlandi.birini.rapora.donusturerek.6.8619c6e0", table: .professionalProgress, fallback: "%1$@ analiz tamamlandı. Birini rapora dönüştürerek +60 MDP kazanabilirsin.", arguments: [String(describing: summary.weeklyTracking.analysesCount)])
        }
        if summary.weeklyTracking.reportsCount == 0 {
            return RDLocalization.string("professionalprogress.professional.progress.titles.sheet.bu.hafta.ilk.raporunu.olusturursan.60.mdp.ve.25..d8302300", table: .professionalProgress, fallback: "Bu hafta ilk raporunu oluşturursan +60 MDP ve +25 haftalık bonus kazanırsın.")
        }
        if summary.profile.highFindings + summary.profile.criticalFindings == 0 {
            return RDLocalization.string("professionalprogress.professional.progress.titles.sheet.yuksek.veya.kritik.riskleri.dogru.siniflandirmak.9485e6fa", table: .professionalProgress, fallback: "Yüksek veya kritik riskleri doğru sınıflandırmak +120 MDP katkı sağlar.")
        }
        return RDLocalization.string("professionalprogress.professional.progress.titles.sheet.yeni.raporlar.ve.farkli.yetkinlik.alanlari.rutbe.5c547b24", table: .professionalProgress, fallback: "Yeni raporlar ve farklı yetkinlik alanları rütbe ilerlemeni hızlandırır.")
    }

    private func formattedNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
