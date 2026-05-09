import SwiftUI

struct RDUpgradeCTA: View {
    var isPro: Bool
    var action: () -> Void

    var body: some View {
        Button {
            if !isPro {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(isPro ? "PRO" : "PRO")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(colors: [Color.rdGreen, Color.rdGreenDark],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.rdGreen.opacity(0.18), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .shadow(color: Color.rdGreen.opacity(0.24), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityLabel(isPro ? "Pro aktif" : "Pro'ya geç")
    }
}

struct RDHeaderAccountCTA: View {
    @EnvironmentObject private var app: AppState
    var onUpgrade: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if !app.isPro {
                RDUpgradeCTA(isPro: false, action: onUpgrade)
            }
            RDAvatar(
                initials: app.profile?.displayInitials ?? "—",
                size: 36,
                pro: app.isPro
            )
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        RDUpgradeCTA(isPro: false) {}
        RDUpgradeCTA(isPro: true) {}
    }
    .padding()
    .background(Color.rdPaper)
}
