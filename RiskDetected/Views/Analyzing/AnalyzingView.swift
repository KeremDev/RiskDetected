import SwiftUI

struct AnalyzingView: View {
    var onComplete: () -> Void

    private let steps: [String] = [
        "Görüntü kalitesi okunuyor",
        "Risk sinyalleri tanımlanıyor",
        "KKD ve çevresel kontroller",
        "Bulgular yapılandırılıyor",
    ]

    @State private var currentStep: Int = 0
    @State private var scanY: CGFloat = -1
    @State private var task: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.rdPaper.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                scanCard
                    .padding(.bottom, 24)

                Text("Analiz devam ediyor")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Color.rdBlack)
                    .padding(.bottom, 24)

                stepsList

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
        }
        .onAppear { startTimers() }
        .onDisappear { task?.cancel() }
    }

    // MARK: - Scan card

    private var scanCard: some View {
        ZStack {
            RDPlaceholderPhoto(label: "Analiz ediliyor", cornerRadius: 22)

            // Scan beam
            GeometryReader { geo in
                let h = geo.size.height
                LinearGradient(
                    colors: [.clear, Color.rdGreen.opacity(0.55), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 60)
                .offset(y: scanY * h)
                .onAppear {
                    withAnimation(
                        .linear(duration: 1.6).repeatForever(autoreverses: false)
                    ) {
                        scanY = 1
                    }
                }
            }

            // Inner glow border
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.rdGreen.opacity(0.7), lineWidth: 2)
                .shadow(color: Color.rdGreen.opacity(0.3), radius: 12)
        }
        .frame(width: 240, height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 18)
    }

    // MARK: - Steps

    private var stepsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, label in
                HStack(spacing: 10) {
                    stepDot(index: index)
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.rdInk)
                }
                .opacity(index <= currentStep ? 1.0 : 0.35)
                .animation(.easeInOut(duration: 0.24), value: currentStep)
            }
        }
        .frame(maxWidth: 320)
    }

    @ViewBuilder
    private func stepDot(index: Int) -> some View {
        ZStack {
            Circle()
                .fill(index < currentStep ? Color.rdGreen : Color.rdFog)
                .overlay(
                    Circle().stroke(index == currentStep ? Color.rdBlack : .clear, lineWidth: 2)
                )

            if index < currentStep {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            } else if index == currentStep {
                Circle()
                    .fill(Color.rdBlack)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 22, height: 22)
    }

    // MARK: - Step ilerletici

    private func startTimers() {
        task?.cancel()
        currentStep = 0
        task = Task { @MainActor in
            for i in 1...steps.count {
                try? await Task.sleep(nanoseconds: 700_000_000)
                if Task.isCancelled { return }
                currentStep = min(i, steps.count - 1)
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }
            onComplete()
        }
    }
}

#Preview {
    AnalyzingView(onComplete: {})
}
