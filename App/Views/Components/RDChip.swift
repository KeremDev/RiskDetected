import SwiftUI

struct RDChip: View {
    let level: RiskLevel
    var label: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(level.color)
                .frame(width: 6, height: 6)
            Text(label ?? level.label)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.2)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(level.bgColor)
        .foregroundStyle(level.textColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct RDRiskDot: View {
    let level: RiskLevel
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(level.color)
            .frame(width: size, height: size)
    }
}

#Preview {
    VStack(spacing: 12) {
        ForEach(RiskLevel.allCases, id: \.self) { lvl in
            HStack {
                RDChip(level: lvl)
                RDChip(level: lvl, label: "Özel etiket")
                RDRiskDot(level: lvl)
            }
        }
    }
    .padding()
    .background(Color.rdPaper)
}
