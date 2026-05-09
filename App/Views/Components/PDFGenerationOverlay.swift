import SwiftUI

@MainActor
final class PDFGenerationProgressController: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var progress: Double = 0

    private var progressTask: Task<Void, Never>?

    func start() {
        progressTask?.cancel()
        progress = 0.07
        isActive = true

        progressTask = Task { @MainActor in
            let waypoints: [Double] = [0.12, 0.18, 0.23, 0.31, 0.38, 0.46, 0.54, 0.61, 0.68, 0.71, 0.76, 0.81, 0.86, 0.90]
            for point in waypoints {
                try? await Task.sleep(nanoseconds: 420_000_000)
                guard !Task.isCancelled else { return }
                advance(to: point)
            }

            while !Task.isCancelled && progress < 0.94 {
                try? await Task.sleep(nanoseconds: 850_000_000)
                guard !Task.isCancelled else { return }
                advance(to: min(progress + 0.01, 0.94))
            }
        }
    }

    func advance(to value: Double) {
        guard isActive else { return }
        let nextValue = max(progress, min(max(value, 0), 0.98))
        withAnimation(.easeInOut(duration: 0.28)) {
            progress = nextValue
        }
    }

    func complete() async {
        progressTask?.cancel()
        progressTask = nil
        withAnimation(.easeInOut(duration: 0.24)) {
            progress = 0.98
        }
        try? await Task.sleep(nanoseconds: 220_000_000)
        withAnimation(.easeInOut(duration: 0.22)) {
            progress = 1
        }
        try? await Task.sleep(nanoseconds: 260_000_000)
        reset()
    }

    func stop() {
        reset()
    }

    func cancel() {
        reset()
    }

    private func reset() {
        progressTask?.cancel()
        progressTask = nil
        isActive = false
        progress = 0
    }
}

struct PDFGenerationOverlay: View {
    let progress: Double

    @State private var pulse = false
    @State private var orbit = false

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var percentText: String {
        "\(Int((clampedProgress * 100).rounded()))%"
    }

    private var statusText: String {
        switch clampedProgress {
        case ..<0.25:
            return "Rapor verileri hazırlanıyor"
        case ..<0.55:
            return "Görsel ve risk tabloları işleniyor"
        case ..<0.85:
            return "PDF sayfaları oluşturuluyor"
        case ..<1:
            return "Rapor arşive kaydediliyor"
        default:
            return "PDF hazır"
        }
    }

    var body: some View {
        ZStack {
            Color.rdBlack.opacity(0.22)
                .ignoresSafeArea()

            VStack(spacing: 26) {
                aiMark

                VStack(spacing: 8) {
                    Text("PDF hazırlanıyor")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .tracking(-0.4)
                        .foregroundStyle(Color.rdBlack)

                    Text(statusText)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    HStack {
                        Text("İlerleme")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                            .textCase(.uppercase)
                            .tracking(1.2)

                        Spacer()

                        Text(percentText)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.rdGreen)
                            .monospacedDigit()
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.rdFog)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.rdGreen, .rdGreenDark],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(10, geo.size.width * clampedProgress))
                                .shadow(color: Color.rdGreen.opacity(0.28), radius: 10, x: 0, y: 4)
                        }
                    }
                    .frame(height: 12)
                }

                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("RiskDetected raporu oluşturulurken uygulamayı açık tut.")
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 30)
            .frame(maxWidth: 330)
            .background(.ultraThinMaterial)
            .background(Color.rdWhite.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.rdWhite.opacity(0.68), lineWidth: 1)
            )
            .shadow(color: Color.rdBlack.opacity(0.16), radius: 34, x: 0, y: 18)
            .padding(.horizontal, 28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PDF hazırlanıyor")
        .accessibilityValue("\(percentText), \(statusText)")
        .accessibilityHint("Rapor oluşturulurken uygulamayı açık tut.")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                orbit = true
            }
        }
    }

    private var aiMark: some View {
        ZStack {
            Circle()
                .fill(Color.rdGreenSoft)
                .frame(width: 132, height: 132)
                .scaleEffect(pulse ? 1.05 : 0.95)

            Circle()
                .stroke(Color.rdGreen.opacity(0.18), lineWidth: 18)
                .frame(width: 104, height: 104)

            Circle()
                .trim(from: 0.05, to: 0.78)
                .stroke(
                    AngularGradient(
                        colors: [.rdGreen, .rdGreenDark, .rdGreen.opacity(0.1), .rdGreen],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 104, height: 104)
                .rotationEffect(.degrees(orbit ? 360 : 0))

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdBlack)

            Image(systemName: "sparkle")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreen)
                .offset(x: 44, y: -42)
                .opacity(pulse ? 1 : 0.45)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    PDFGenerationOverlay(progress: 0.62)
}
