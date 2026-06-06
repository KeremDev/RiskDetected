import SwiftUI
import UIKit

enum AnalysisWaitingPresentationMode {
    case photo
    case text
}

struct AnalyzingView: View {
    /// Parent'tan binding — dismiss için daha güvenilir (iOS 26 fullScreenCover).
    @Binding var isPresented: Bool
    /// nil = preview / mock modu; set edilirse gerçek analiz çalıştırılır.
    var asyncWork: ((@escaping @MainActor (AnalysisProgressUpdate) -> Void) async throws -> AnalysisResultBundle)? = nil
    var previewImage: UIImage? = nil
    var presentationMode: AnalysisWaitingPresentationMode = .photo
    var onComplete: (AnalysisResultBundle?) -> Void = { _ in }
    var onError: (String) -> Void = { _ in }

    @State private var currentStep: Int = 0
    @State private var animTask: Task<Void, Never>?
    @State private var workTask: Task<Void, Never>?
    @State private var workDone = false
    @State private var workResult: AnalysisResultBundle? = nil
    @State private var animDone = false
    @State private var progressUpdate: AnalysisProgressUpdate?
    @State private var signalPulse = false

    var body: some View {
        ZStack {
            Color.rdPaper.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                scanCard
                    .padding(.bottom, 22)

                VStack(spacing: 6) {
                    Text("Analiz devam ediyor")
                        .font(.system(size: RDFontScale.size(22), weight: .bold, design: .rounded))
                        .tracking(-0.4)
                        .foregroundStyle(Color.rdBlack)
                    Text(heroSubtitle)
                        .font(.system(size: RDFontScale.size(12.5), weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(.bottom, progressUpdate == nil ? 18 : 12)

                if let progressUpdate, progressUpdate != .queued {
                    progressStatus(progressUpdate)
                        .padding(.bottom, 18)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

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
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                signalPulse = true
            }
        }
    }

    // MARK: - Scan card

    private var scanCard: some View {
        ZStack {
            ZStack {
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 246, height: 246)
                        .clipped()
                        .overlay(Color.black.opacity(0.16))
                } else {
                    RDPlaceholderPhoto(label: "Analiz ediliyor", cornerRadius: 24)
                }

                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    GeometryReader { geo in
                        let h = geo.size.height
                        let cycle = timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1.55) / 1.55
                        let y = CGFloat(cycle) * (h + 96) - 80

                        LinearGradient(
                            colors: [.clear, Color.rdGreen.opacity(0.62), Color.rdGreen.opacity(0.22), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 64)
                        .offset(y: y)
                    }
                }

                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.rdGreen.opacity(0.75), lineWidth: 2)
                    .shadow(color: Color.rdGreen.opacity(0.32), radius: 14)
            }
            .frame(width: 246, height: 246)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 18)

            aiSignal(icon: "shield.lefthalf.filled", label: "KKD", alignment: .topLeading)
                .offset(x: -18, y: -12)
            aiSignal(icon: "waveform.path.ecg", label: "Risk", alignment: .topTrailing)
                .offset(x: 18, y: 26)
            aiSignal(icon: "checklist.checked", label: "Kontrol", alignment: .bottomLeading)
                .offset(x: -16, y: 16)
        }
        .frame(width: 296, height: 286)
    }

    private func aiSignal(icon: String, label: String, alignment: Alignment) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: RDFontScale.size(10), weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: RDFontScale.size(10), weight: .bold, design: .rounded))
        }
        .foregroundStyle(Color.rdGreenDark)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.ultraThinMaterial)
        .overlay(
            Capsule()
                .stroke(Color.rdGreen.opacity(0.26), lineWidth: 1)
        )
        .clipShape(Capsule())
        .shadow(color: Color.rdGreen.opacity(signalPulse ? 0.26 : 0.08), radius: signalPulse ? 14 : 6, x: 0, y: 5)
        .scaleEffect(signalPulse ? 1.03 : 0.98)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    // MARK: - Steps

    private var heroSubtitle: String {
        switch presentationMode {
        case .photo:
            return "AI, görüntüyü iş güvenliği odaklarıyla katman katman tarıyor."
        case .text:
            return "AI, metni iş güvenliği odaklarıyla katman katman tarıyor."
        }
    }

    private var steps: [String] {
        switch presentationMode {
        case .photo:
            return [
                "Görüntü kalitesi okunuyor",
                "Risk sinyalleri tanımlanıyor",
                "KKD ve çevresel kontroller",
                "Bulgular yapılandırılıyor",
            ]
        case .text:
            return [
                "Kullanıcı metni okunuyor",
                "Risk sinyalleri tanımlanıyor",
                "KKD ve saha kontrolleri",
                "Bulgular yapılandırılıyor",
            ]
        }
    }

    private var stepsList: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, label in
                let isActive = index == currentStep
                let isReached = animDone || index <= currentStep
                HStack(spacing: 10) {
                    stepDot(index: index)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.system(size: RDFontScale.size(13.5), weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)
                        Text(stepSubtitle(index))
                            .font(.system(size: RDFontScale.size(10.5), weight: .medium, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 54)
                .background(isReached ? Color.rdWhite : Color.rdFog.opacity(0.62))
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(isActive ? Color.rdGreen.opacity(0.42) : Color.rdLine.opacity(0.75), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .shadow(color: isActive ? Color.rdGreen.opacity(0.10) : Color.clear, radius: 12, x: 0, y: 7)
                .opacity(isReached ? 1.0 : 0.52)
                .scaleEffect(isActive ? 1.015 : 1)
                .animation(.spring(response: 0.34, dampingFraction: 0.84), value: currentStep)
            }
        }
        .frame(maxWidth: 320)
    }

    private func stepSubtitle(_ index: Int) -> String {
        switch presentationMode {
        case .photo:
            switch index {
            case 0: return "Netlik ve görüntü okunabilirliği kontrol ediliyor"
            case 1: return "Tehlike ipuçları ve uygunsuzluk alanları ayrıştırılıyor"
            case 2: return "KKD, çevre ve saha düzeni birlikte değerlendiriliyor"
            default: return "Bulgular, risk seviyesi ve aksiyonlar hazırlanıyor"
            }
        case .text:
            switch index {
            case 0: return "Metin kalitesi ve saha bağlamı kontrol ediliyor"
            case 1: return "Tehlike ifadeleri ve uygunsuzluk alanları ayrıştırılıyor"
            case 2: return "KKD, çevre ve çalışma düzeni birlikte değerlendiriliyor"
            default: return "Bulgular, risk seviyesi ve aksiyonlar hazırlanıyor"
            }
        }
    }

    private func progressStatus(_ update: AnalysisProgressUpdate) -> some View {
        HStack(spacing: 10) {
            Image(systemName: update.icon)
                .font(.system(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreen)

            VStack(alignment: .leading, spacing: 2) {
                Text(update.title)
                    .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Text(update.message)
                    .font(.system(size: RDFontScale.size(11), weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.rdGreenSoft.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.rdGreen.opacity(0.16), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func stepDot(index: Int) -> some View {
        ZStack {
            Circle()
                .fill(index < currentStep ? Color.rdGreen : Color.rdFog)
                .overlay(
                    Circle().stroke(index == currentStep ? Color.rdSelected : .clear, lineWidth: 2)
                )

            if index < currentStep {
                Image(systemName: "checkmark")
                    .font(.system(size: RDFontScale.size(10), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else if animDone && index != currentStep {
                Image(systemName: "checkmark")
                    .font(.system(size: RDFontScale.size(10), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else if index == currentStep {
                Circle()
                    .fill(Color.rdSelected)
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
            var index = 0
            var didCompleteMinimumCycle = false
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 700_000_000)
                if Task.isCancelled { return }
                index = (index + 1) % steps.count
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    self.currentStep = index
                }
                if index == steps.count - 1, !didCompleteMinimumCycle {
                    didCompleteMinimumCycle = true
                    self.animDone = true
                    self.finishIfReady()
                }
                if didCompleteMinimumCycle, self.workDone {
                    return
                }
            }
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
                let result = try await work { update in
                    withAnimation(.easeInOut(duration: 0.22)) {
                        progressUpdate = update
                    }
                }
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

#Preview("Text Analysis") {
    AnalyzingView(isPresented: .constant(true), presentationMode: .text)
}
