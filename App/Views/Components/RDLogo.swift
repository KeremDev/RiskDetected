import SwiftUI

/// Brand logosunu Assets.xcassets içindeki "RDLogo" görselinden render eder.
/// `size` parametresi "Risk" wordmark'ının yaklaşık cap-height'ı kadardır;
/// böylece eski API (font size mantığı) çağrılarıyla görsel olarak uyumlu kalır.
struct RDLogo: View {
    @Environment(\.colorScheme) private var colorScheme

    var size: CGFloat = 18
    var mono: Bool = false
    /// Koyu / fotoğraf arka plan üstünde: template + beyaz render
    var onDark: Bool = false

    private static let aspectRatio: CGFloat = 2101.0 / 748.0
    private static let capHeightRatio: CGFloat = 0.44

    private var imageHeight: CGFloat { size / Self.capHeightRatio }
    private var imageWidth: CGFloat { imageHeight * Self.aspectRatio }
    private var rendersOnDark: Bool { onDark || colorScheme == .dark }

    var body: some View {
        Image("RDLogo")
            .resizable()
            .renderingMode(rendersOnDark ? .template : (mono ? .template : .original))
            .interpolation(.high)
            .scaledToFit()
            .frame(width: imageWidth, height: imageHeight)
            .foregroundStyle(rendersOnDark ? Color.white : Color.rdBlack)
            .accessibilityLabel("RiskDetected")
    }
}

#Preview {
    VStack(spacing: 24) {
        RDLogo(size: 14)
        RDLogo(size: 18)
        RDLogo(size: 24)
        RDLogo(size: 30)
    }
    .padding()
    .background(Color.rdPaper)
}
