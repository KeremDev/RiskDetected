import SwiftUI
import UIKit

struct AnalyzingView: View {
    /// Parent'tan binding — dismiss için daha güvenilir (iOS 26 fullScreenCover).
    @Binding var isPresented: Bool
    /// nil = preview / mock modu; set edilirse gerçek analiz çalıştırılır.
    var asyncWork: (() async throws -> AnalysisResultBundle)? = nil
    var previewImage: UIImage? = nil
    var onComplete: (AnalysisResultBundle?) -> Void = { _ in }
    var onError: (String) -> Void = { _ in }

    private let steps: [String] = [
        "Görüntü kalitesi okunuyor",
        "Risk sinyalleri tanımlanıyor",
        "KKD ve çevresel kontroller",
        "Bulgular yapılandırılıyor",
    ]

    @State private var currentStep: Int = 0
    @State private var scanY: CGFloat = -1
    @State private var animTask: Task<Void, Never>?
    @State private var workTask: Task<Void, Never>?
    @State private var workDone = false
    @State private var workResult: AnalysisResultBundle? = nil
    @State private var animDone = false

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
        .onAppear {
            // animTask nil kontrolü: iOS 26'da fullScreenCover animation sırasında
            // onDisappear/onAppear döngüsü oluşuyor. didStart bayrağı yerine
            // task varlığını kontrol et — daha güvenilir.
            guard animTask == nil else { return }
            startAnimation()
            startWork()
        }
    }

    // MARK: - Scan card

    private var scanCard: some View {
        ZStack {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 240, height: 240)
                    .clipped()
                    .overlay(Color.black.opacity(0.14))
            } else {
                RDPlaceholderPhoto(label: "Analiz ediliyor", cornerRadius: 22)
            }

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

    // MARK: - Animasyon (minimum görünüm süresi)

    private func startAnimation() {
        animTask?.cancel()
        currentStep = 0
        animDone = false
        animTask = Task.detached { @MainActor [self] in
            for i in 1...steps.count {
                try? await Task.sleep(nanoseconds: 700_000_000)
                if Task.isCancelled { return }
                self.currentStep = min(i, steps.count - 1)
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }
            self.animDone = true
            self.finishIfReady()
        }
    }

    // MARK: - Gerçek iş

    private func startWork() {
        guard let work = asyncWork else {
            // Mock mod: iş yok, sadece animasyon.
            workDone = true
            return
        }
        workTask = Task { @MainActor in
            do {
                let result = try await work()
                if Task.isCancelled { return }
                workResult = result
                workDone = true
                finishIfReady()
            } catch {
                if Task.isCancelled { return }
                workDone = true
                animTask?.cancel()
                let msg = error.localizedDescription
                isPresented = false
                onError(msg)
            }
        }
    }

    /// Hem animasyon hem iş bitince onComplete'i tetikle.
    private func finishIfReady() {
        guard animDone && workDone else { return }
        let result = workResult
        isPresented = false
        onComplete(result)
    }
}

#Preview {
    AnalyzingView(isPresented: .constant(true))
}
