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
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(isPro ? .white : Color(hex: "#F5B700"))
                Text(isPro ? "PRO" : "PRO")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.7)
                    .foregroundStyle(isPro ? .white : Color(hex: "#3A2A00"))
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        isPro
                        ? LinearGradient(colors: [Color.rdGreen, Color.rdGreenDark],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color(hex: "#FFF7D6"), Color(hex: "#FFE08A")],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isPro ? Color.clear : Color(hex: "#F6C343").opacity(0.85), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .shadow(color: (isPro ? Color.rdGreen : Color(hex: "#F5B700")).opacity(0.24),
                    radius: 8, x: 0, y: 3)
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
            RDUpgradeCTA(isPro: app.isPro, action: onUpgrade)
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
