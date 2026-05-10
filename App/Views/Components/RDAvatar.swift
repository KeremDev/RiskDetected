import SwiftUI

struct RDAvatar: View {
    var initials: String = "EY"
    var size: CGFloat = 36
    var pro: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.rdGraphite, Color.rdCharcoal],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(Circle())

            Text(initials)
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .tracking(-0.3)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if pro {
                Circle()
                    .fill(Color.rdOnyx)
                    .frame(width: size * 0.5, height: size * 0.5)
                    .overlay {
                        Image(systemName: "star.fill")
                            .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "#FFD75A"))
                    }
                    .overlay(
                        Circle().stroke(.white, lineWidth: 2)
                    )
                    .offset(x: 2, y: 2)
            }
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        RDAvatar(initials: "EY", size: 36)
        RDAvatar(initials: "EY", size: 48, pro: true)
        RDAvatar(initials: "KK", size: 64, pro: true)
    }
    .padding()
    .background(Color.rdPaper)
}
