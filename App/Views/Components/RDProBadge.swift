import SwiftUI

struct RDProBadge: View {
    var small: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.system(size: small ? 9 : 11, weight: .bold, design: .rounded))
            Text("PRO")
                .font(.system(size: small ? 9 : 10, weight: .heavy, design: .rounded))
                .tracking(0.6)
        }
        .padding(.horizontal, small ? 6 : 8)
        .frame(height: small ? 18 : 22)
        .background(Color.rdGreen)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: small ? .clear : Color.rdGreen.opacity(0.3), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    VStack(spacing: 12) {
        RDProBadge()
        RDProBadge(small: true)
    }
    .padding()
    .background(Color.rdPaper)
}
