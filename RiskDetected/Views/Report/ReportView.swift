import SwiftUI

struct ReportView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Raporlar")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Color.rdBlack)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    ReportPreview()
                    actionButtons
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
        }
        .background(Color.rdCloud)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            RDButton(title: "İndir", style: .secondary, icon: "arrow.down.to.line", height: 52) {}
                .frame(maxWidth: .infinity)
            RDButton(title: "Paylaş", style: .primary, icon: "square.and.arrow.up", height: 52) {}
                .frame(maxWidth: .infinity)
        }
    }
}

private struct ReportPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                RDLogo(size: 12)
                Spacer()
                Text("02.05.2026 · #2841")
                    .rdMono(size: 10)
                    .foregroundStyle(Color.rdSlate)
            }
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.rdBlack)
                    .frame(height: 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("İş Güvenliği Risk Analizi")
                    .font(.system(size: 18, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.rdBlack)
                Text("3. Kat şantiye girişi · KKD Bazlı analiz")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.rdSlate)
            }

            // Counts grid
            HStack(spacing: 6) {
                miniBadge(value: "1", label: "KRİTİK", bg: .rdCriticalBg, fg: .rdCriticalText)
                miniBadge(value: "1", label: "YÜKSEK", bg: .rdHighBg, fg: .rdHighText)
                miniBadge(value: "2", label: "ORTA", bg: .rdMediumBg, fg: .rdMediumText)
            }

            VStack(spacing: 0) {
                tableHeader
                ForEach(Array(Finding.mock.prefix(4).enumerated()), id: \.element.id) { idx, f in
                    tableRow(idx: idx + 1, finding: f)
                    if idx < 3 {
                        Divider().background(Color.rdLine)
                    }
                }
            }
            .padding(.top, 6)

            Text("Sayfa 1 / 4 · İSG Uzmanı: Erdem Yılmaz · A-12384")
                .rdMono(size: 10)
                .foregroundStyle(Color.rdSlate)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.rdFog)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.top, 10)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rdWhite)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.10), radius: 28, x: 0, y: 12)
    }

    private func miniBadge(value: String, label: String, bg: Color, fg: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .rdMono(size: 16, weight: .bold)
                .foregroundStyle(fg)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(fg)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var tableHeader: some View {
        HStack(spacing: 6) {
            Text("#").frame(width: 20, alignment: .leading)
            Text("RİSK").frame(maxWidth: .infinity, alignment: .leading)
            Text("SEV").frame(width: 60, alignment: .leading)
            Text("GÜVEN").frame(width: 50, alignment: .leading)
        }
        .font(.system(size: 9, weight: .bold))
        .tracking(0.7)
        .foregroundStyle(Color.rdSlate)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.rdLine).frame(height: 1)
        }
    }

    private func tableRow(idx: Int, finding: Finding) -> some View {
        HStack(spacing: 6) {
            Text("\(idx)")
                .rdMono(size: 11, weight: .semibold)
                .frame(width: 20, alignment: .leading)
            Text(finding.title)
                .font(.system(size: 11))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                RDChip(level: finding.fkBand.level)
            }
            .frame(width: 60, alignment: .leading)
            Text("\(Int(finding.confidence * 100))%")
                .rdMono(size: 10)
                .frame(width: 50, alignment: .leading)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    ReportView()
}
