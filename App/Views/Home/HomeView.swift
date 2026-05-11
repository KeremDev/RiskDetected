import SwiftUI

// MARK: - AnalysisJob

/// iOS 26 SwiftUI bug workaround: fullScreenCover(isPresented:) captures stale @State
/// value when two state vars are set in same sync frame. Using fullScreenCover(item:)
/// guarantees the closure captures the live item at presentation time.
struct AnalysisJob: Identifiable {
    let id = UUID()
    let previewImage: UIImage?
    let work: (@escaping @MainActor (AnalysisProgressUpdate) -> Void) async throws -> AnalysisResultBundle
}

private struct PaywallPresentation: Identifiable {
    let id = UUID()
    let notice: String?
}

private let maxTextInputCharacters = AnalysisService.maxTextInputCharacters

struct HomeView: View {
    @EnvironmentObject var app: AppState

    @State private var mode: HomeMode = .photo
    @State private var text: String = ""
    @State private var selectedCanvases: Set<AnalysisCanvas> = [.general]
    @State private var analysisPrompt: String = ""
    @State private var showCanvasSheet = false
    @State private var showAnnotate = false
    @State private var showResult = false

    // Foto akışı state
    @State private var showSourceDialog = false
    @State private var showCameraPicker = false
    @State private var showGalleryPicker = false
    @State private var selectedImage: UIImage? = nil

    // Analiz state
    @State private var analysisResult: AnalysisResultBundle? = nil
    @State private var analysisError: String? = nil
    @State private var pendingJob: AnalysisJob? = nil
    @State private var recentItems: [RecentAnalysis] = []
    @State private var recentReports: [ReportRow] = []
    @State private var openingRecentID: UUID? = nil
    @State private var openingReportID: UUID? = nil
    @State private var quotaUsage: DailyQuotaUsage? = nil
    @State private var paywallPresentation: PaywallPresentation? = nil
    @State private var reportPreviewItem: ShareItem?

    enum HomeMode: String, CaseIterable {
        case photo, text
        var label: String { self == .photo ? "Fotoğraf" : "Metin" }
        var icon: String { self == .photo ? "camera.fill" : "text.alignleft" }
    }

    var body: some View {
        VStack(spacing: 0) {
            HomeHeader()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    modeSegment
                        .padding(.bottom, 14)

                    if mode == .photo {
                        photoUploadCard
                    } else {
                        textInputArea
                    }

                    if !app.isPro {
                        freeQuotaHint
                            .padding(.top, 10)
                    }

                    RDButton(
                        title: "Taramayı Başlat",
                        style: .detect,
                        icon: "sparkles",
                        backgroundOverride: .rdCTA,
                        foregroundOverride: .white,
                        shadowOverride: Color.rdGreen.opacity(0.18)
                    ) {
                        startAnalysisFlow()
                    }
                    .frame(height: 56)
                    .padding(.top, 14)

                    recentSection
                        .padding(.top, 28)

                    generatedReportsSection
                        .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 110) // tab bar clearance
                .background(Color.rdWhite)
            }
            .background(Color.rdWhite)
        }
        .background(Color.rdWhite.ignoresSafeArea())
        .task {
            await loadRecentItems()
            await loadRecentReports()
            await loadQuotaUsage()
        }
        .onAppear {
            handlePendingQuickScanOnAppear()
        }
        .onChange(of: app.auth.session?.user.id) { _ in
            Task {
                await loadRecentItems()
                await loadRecentReports()
                await loadQuotaUsage()
            }
        }
        .onChange(of: app.isPro) { _ in
            Task { await loadQuotaUsage() }
        }
        .onChange(of: app.quickScanRequestID) { _ in
            handleQuickScanRequest()
        }
        .sheet(isPresented: $showSourceDialog) {
            PhotoSourceSheet(
                onCamera: {
                    showSourceDialog = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            showCameraPicker = true
                        } else {
                            showGalleryPicker = true
                        }
                    }
                },
                onGallery: {
                    showSourceDialog = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        showGalleryPicker = true
                    }
                },
                onClose: { showSourceDialog = false }
            )
            .presentationDetents([.height(330)])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showCanvasSheet) {
            CanvasSheet(
                selected: $selectedCanvases,
                userPrompt: $analysisPrompt,
                isUserPro: app.isPro,
                onConfirm: {
                    showCanvasSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        runAnalysis()
                    }
                },
                onUpgradeRequested: {
                    showCanvasSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showPlainPaywall()
                    }
                }
            )
            .presentationDetents([.fraction(0.72), .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraPicker { image in
                showCameraPicker = false
                if let image {
                    selectedImage = image
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showAnnotate = true
                    }
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showGalleryPicker) {
            GalleryPicker { image in
                showGalleryPicker = false
                if let image {
                    selectedImage = image
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showAnnotate = true
                    }
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showAnnotate) {
            AnnotateView(
                initialImage: selectedImage,
                onCancel: { showAnnotate = false },
                onAnalyze: { annotated in
                    selectedImage = annotated
                    showAnnotate = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        continueFromAnnotatedPhoto()
                    }
                }
            )
        }
        .fullScreenCover(item: $pendingJob) { job in
            AnalyzingView(
                isPresented: Binding(
                    get: { pendingJob != nil },
                    set: { if !$0 { pendingJob = nil } }
                ),
                asyncWork: job.work,
                previewImage: job.previewImage,
                onComplete: { result in
                    analysisResult = result
                    pendingJob = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showResult = true
                    }
                },
                onError: { msg in
                    handleAnalysisError(msg)
                    pendingJob = nil
                }
            )
        }
        .sheet(item: $reportPreviewItem) { item in
            DocumentPreview(url: item.url)
        }
        .fullScreenCover(isPresented: $showResult) {
            ResultView(
                bundle: analysisResult,
                localPreviewImage: selectedImage,
                onClose: {
                    showResult = false
                    selectedImage = nil
                    analysisResult = nil
                    Task {
                        await loadRecentItems()
                        await loadRecentReports()
                        await loadQuotaUsage()
                    }
                }
            )
            .environmentObject(app)
        }
        .fullScreenCover(item: $paywallPresentation) { presentation in
            PaywallView(
                onClose: {
                    paywallPresentation = nil
                },
                onSubscribe: {
                    paywallPresentation = nil
                    Task { await app.auth.refreshProfile() }
                },
                notice: presentation.notice
            )
        }
        .alert("Analiz Hatası", isPresented: .init(
            get: { analysisError != nil },
            set: { if !$0 { analysisError = nil } }
        )) {
            Button("Tamam") { analysisError = nil }
        } message: {
            Text(analysisError ?? "")
        }
    }

    // MARK: - Subviews

    private var modeSegment: some View {
        HStack(spacing: 0) {
            ForEach(HomeMode.allCases, id: \.self) { m in
                let active = mode == m
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { mode = m }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: m.icon)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text(m.label)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundStyle(active ? Color.rdBlack : Color.rdSlate)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(active ? Color.rdWhite : Color.clear)
                            .shadow(color: active ? Color.black.opacity(0.08) : .clear,
                                    radius: 3, x: 0, y: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.rdFog)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.rdLine, lineWidth: 1)
                )
        )
    }

    private var photoUploadCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isFreeQuotaExhausted {
                showQuotaPaywall()
                return
            }
            if selectedImage != nil {
                // Mevcut foto varsa direkt çizim ekranına dön
                showAnnotate = true
            } else {
                showSourceDialog = true
            }
        } label: {
            ZStack {
                if let img = selectedImage {
                    // Seçilmiş foto preview
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                selectedImage = nil
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color.black.opacity(0.55))
                                    .clipShape(Circle())
                            }
                            .padding(10)
                        }
                        .overlay(alignment: .bottomLeading) {
                            HStack(spacing: 6) {
                                Image(systemName: "pencil.tip.crop.circle")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                Text("İşaretlemeyi düzenle")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.92))
                            .clipShape(Capsule())
                            .padding(10)
                        }
                } else if isFreeQuotaExhausted {
                    lockedPhotoUploadContent
                } else {
                    ZStack {
                        // İçerik
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color.rdWhite)
                                    .frame(width: 56, height: 56)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18)
                                            .stroke(Color.rdLine, lineWidth: 1)
                                    )

                                Image(systemName: "camera.fill")
                                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.rdGreenDark)
                            }
                            .frame(width: 68, height: 68)

                            Text("Saha fotoğrafı yükle")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.rdBlack)
                            Text("Kamerayla çek veya galeriden seç")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(Color.rdSlate)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        VStack {
                            Spacer()
                            Text("JPG · PNG · HEIC")
                                .rdMono(size: 11, weight: .medium)
                                .foregroundStyle(Color.rdSlate.opacity(0.7))
                                .padding(.bottom, 14)
                        }
                    }
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.rdWhite)

                            // Dashed border — marka siyahıyla daha net bir çerçeve.
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(
                                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                                )
                                .foregroundStyle(Color.rdBlack)
                        }
                    )
                }
            }
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    private var lockedPhotoUploadContent: some View {
        ZStack {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.rdCritical.opacity(0.10))
                        .frame(width: 74, height: 74)
                        .shadow(color: Color.rdCritical.opacity(0.18), radius: 16, x: 0, y: 8)

                    Circle()
                        .stroke(Color.rdCritical, lineWidth: 6)
                        .frame(width: 56, height: 56)

                    Image(systemName: "lock.fill")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdCritical)
                }
                .frame(width: 82, height: 82)

                Text("Günlük free limit doldu")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Text("Yeni fotoğraf analizi için yarın tekrar dene veya PRO ile sınırsız taramaya geç.")
                    .font(.system(size: 13, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.rdSlate)
                    .frame(maxWidth: 280)

                HStack(spacing: 5) {
                    Text("PRO'ya geç")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color.rdCritical)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [Color.rdWhite, Color.rdCriticalBg.opacity(0.68)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.7, dash: [6, 4])
                        )
                        .foregroundStyle(Color.rdCritical.opacity(0.38))
                )
        )
        .shadow(color: Color.rdCritical.opacity(0.10), radius: 16, x: 0, y: 8)
    }

    private var textInputArea: some View {
        Group {
            if isFreeQuotaExhausted {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showQuotaPaywall()
                } label: {
                    lockedInputContent(
                        title: "Günlük free limit doldu",
                        subtitle: "Yeni metin analizi için yarın tekrar dene veya PRO ile sınırsız taramaya geç.",
                        icon: "text.badge.xmark"
                    )
                }
                .buttonStyle(RDPressableButtonStyle())
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Saha gözlemini kısa yaz...")
                                Text("Örn: \"Korkuluk eksik, işçi emniyet kemeri kullanmıyor.\"")
                                    .padding(.top, 4)
                            }
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                            .allowsHitTesting(false)
                        }
                        TextEditor(text: $text)
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(Color.rdBlack)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(minHeight: 160)
                            .onChange(of: text) { new in
                                if new.count > maxTextInputCharacters {
                                    text = String(new.prefix(maxTextInputCharacters))
                                }
                            }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.rdWhite)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.rdLine, lineWidth: 1)
                            )
                    )

                    HStack {
                        Text("Maks. \(maxTextInputCharacters) karakter")
                            .font(.system(size: 12, design: .rounded))
                        Spacer()
                        Text("\(text.count)/\(maxTextInputCharacters)")
                            .rdMono(size: 12, weight: .medium)
                    }
                    .foregroundStyle(Color.rdSlate)
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private var freeQuotaHint: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showPlainPaywall()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isFreeQuotaExhausted ? Color.rdCritical : Color.rdOnyx)
                    Text(freeQuotaCompactText)
                        .rdMono(size: 11, weight: .bold)
                        .foregroundStyle(Color.white)
                }
                .frame(width: 42, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Günlük deneme hakkı")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text("Günde 2 analiz. Pro ile sınırsız hak ve daha detaylı bulgular.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 28, height: 28)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityLabel("Free kullanım bilgisi. Günde 2 analiz. Pro ile sınırsız hak ve detaylı bulgular.")
    }

    private var freeQuotaCompactText: String {
        guard let quotaUsage else { return "2/2" }
        return "\(quotaUsage.remaining)/\(quotaUsage.limit)"
    }

    private func lockedInputContent(title: String, subtitle: String, icon: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.rdCritical.opacity(0.10))
                    .frame(width: 68, height: 68)
                    .shadow(color: Color.rdCritical.opacity(0.18), radius: 16, x: 0, y: 8)

                Circle()
                    .stroke(Color.rdCritical, lineWidth: 5)
                    .frame(width: 52, height: 52)

                Image(systemName: icon)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdCritical)
            }

            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdBlack)

            Text(subtitle)
                .font(.system(size: 13, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.rdSlate)
                .frame(maxWidth: 290)

            HStack(spacing: 5) {
                Text("PRO'ya geç")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color.rdCritical)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [Color.rdWhite, Color.rdCriticalBg.opacity(0.68)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                        .foregroundStyle(Color.rdCritical.opacity(0.38))
                )
        )
        .shadow(color: Color.rdCritical.opacity(0.08), radius: 14, x: 0, y: 6)
    }

    private var recentSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Son uygunsuzluklar")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.rdSlate)
                Spacer()
                Button("Tümü") { /* navigate to history */ }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
            }

            if recentItems.isEmpty {
                emptyRecentCard
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(recentItems) { item in
                            RecentAnalysisCard(
                                item: item,
                                isLoading: openingRecentID == item.id
                            ) {
                                openRecentAnalysis(item)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, -20)
                .background(Color.rdWhite)
            }
        }
        .background(Color.rdWhite)
    }

    private var generatedReportsSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Oluşturulan Raporlar")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.rdSlate)
                Spacer()
                Button("Tümü") {
                    app.activeTab = .reports
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
            }

            if recentReports.isEmpty {
                emptyReportsCard
            } else {
                VStack(spacing: 8) {
                    ForEach(recentReports.prefix(5)) { report in
                        HomeReportRow(
                            report: report,
                            isLoading: openingReportID == report.id
                        ) {
                            openReport(report)
                        }
                    }
                }
            }
        }
        .background(Color.rdWhite)
    }

    private var emptyReportsCard: some View {
        RDCard {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .frame(width: 42, height: 42)
                    .background(Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Henüz rapor oluşturulmadı")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text("PDF veya Excel çıktıları burada görünecek.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var emptyRecentCard: some View {
        RDCard {
            HStack(spacing: 12) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdGreenDark)
                    .frame(width: 42, height: 42)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Henüz tamamlanmış analiz yok")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text("İlk tarama tamamlandığında burada listelenecek.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Helpers

    private var isFreeQuotaExhausted: Bool {
        !app.isPro && quotaUsage?.isExhausted == true
    }

    /// "Taramayı Başlat" → foto yoksa picker; varsa canvas sheet.
    private func startAnalysisFlow() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if !app.isPro, quotaUsage?.isExhausted == true {
            showQuotaPaywall()
            return
        }
        if mode == .photo && selectedImage == nil {
            showSourceDialog = true
            return
        }
        if mode == .text && text.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 {
            analysisError = AppErrorMessage.make(
                AnalysisService.AnalysisError.invalidInput("Analiz için en az 10 karakterlik bir açıklama yazmalısın."),
                context: "Eksik metin",
                fallbackTitle: "Eksik metin"
            ).fullText
            return
        }
        showCanvasSheet = true
    }

    private func handleQuickScanRequest() {
        mode = .photo
        if !app.isPro, quotaUsage?.isExhausted == true {
            showQuotaPaywall()
            app.quickScanSource = .chooser
            return
        }
        let source = app.quickScanSource
        app.quickScanSource = .chooser
        switch source {
        case .camera:
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                showCameraPicker = true
            } else {
                showGalleryPicker = true
            }
            return
        case .gallery:
            showGalleryPicker = true
            return
        case .chooser:
            break
        }
        if selectedImage == nil {
            showSourceDialog = true
        } else {
            showCanvasSheet = true
        }
    }

    private func handlePendingQuickScanOnAppear() {
        guard app.quickScanSource != .chooser else { return }
        DispatchQueue.main.async {
            handleQuickScanRequest()
        }
    }

    /// AnnotateView'daki "İşaretli alanları analiz et" sonrası ana sayfada
    /// bekletmeden doğrudan analiz odağı seçimine geçer.
    private func continueFromAnnotatedPhoto() {
        guard mode == .photo, selectedImage != nil else { return }
        if !app.isPro, quotaUsage?.isExhausted == true {
            showQuotaPaywall()
            return
        }
        showCanvasSheet = true
    }

    /// Canvas seçimi onaylandıktan sonra çağrılır.
    /// async closure oluştur → AnalyzingView'a ilet → o çalıştırır.
    private func runAnalysis() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // AuthService.session authStateChanges'ten geliyor — currentSession'dan daha güvenilir.
        guard let userID = app.auth.session?.user.id else {
            analysisError = AppErrorMessage.make(AnalysisService.AnalysisError.notAuthenticated).fullText
            return
        }
        let canvases = Array(selectedCanvases)
        let capturedImage = selectedImage
        let capturedText = text
        let capturedPrompt = analysisPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .photo:
            guard let img = capturedImage else {
                return
            }
            pendingJob = AnalysisJob(previewImage: img) {
                progress in
                try await AnalysisService.shared.runPhotoAnalysis(
                    userID: userID,
                    images: [img],
                    canvases: canvases,
                    userPrompt: capturedPrompt,
                    onProgress: progress
                )
            }
        case .text:
            let trimmed = capturedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return
            }
            pendingJob = AnalysisJob(previewImage: nil) {
                progress in
                try await AnalysisService.shared.runTextAnalysis(
                    userID: userID,
                    text: trimmed,
                    canvases: canvases,
                    userPrompt: capturedPrompt,
                    onProgress: progress
                )
            }
        }
    }

    private func handleAnalysisError(_ msg: String) {
        let normalized = AppErrorMessage.make(rawMessage: msg, context: "Analiz tamamlanamadı", fallbackTitle: "Analiz tamamlanamadı")
        if normalized.category == .quotaExceeded {
            analysisError = nil
            showQuotaPaywall(supportID: normalized.supportID)
            Task { await loadQuotaUsage() }
        } else {
            analysisError = normalized.fullText
        }
    }

    private func quotaPaywallNotice(supportID: String = AppErrorMessage.newSupportID()) -> String {
        "Bugünkü ücretsiz analiz hakkın doldu. Yarın tekrar deneyebilir veya Pro ile devam edebilirsin. Destek kodu: \(supportID)"
    }

    private func showQuotaPaywall(supportID: String = AppErrorMessage.newSupportID()) {
        paywallPresentation = PaywallPresentation(notice: quotaPaywallNotice(supportID: supportID))
    }

    private func showPlainPaywall() {
        paywallPresentation = PaywallPresentation(notice: nil)
    }

    private func loadRecentItems() async {
        guard app.auth.session != nil else { return }
        do {
            let rows = try await AnalysisService.shared.listRecent(limit: 8)
            let paths = try await AnalysisService.shared.firstPhotoPaths(analysisIDs: rows.map(\.id))
            recentItems = rows.map { row in
                RecentAnalysis(row: row, photoPath: paths[row.id])
            }
        } catch {
            recentItems = []
        }
    }

    private func loadRecentReports() async {
        guard app.auth.session != nil else {
            recentReports = []
            return
        }
        do {
            recentReports = try await AnalysisService.shared.listReports(limit: 5)
        } catch {
            recentReports = []
        }
    }

    private func loadQuotaUsage() async {
        guard app.auth.session != nil, !app.isPro else {
            quotaUsage = nil
            return
        }
        do {
            quotaUsage = try await AnalysisService.shared.dailyQuotaUsage()
        } catch {
            quotaUsage = nil
        }
    }

    private func openRecentAnalysis(_ item: RecentAnalysis) {
        guard openingRecentID == nil else { return }
        openingRecentID = item.id
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            do {
                let result = try await AnalysisService.shared.result(analysisID: item.id)
                analysisResult = result
                showResult = true
            } catch {
                analysisError = AppErrorMessage.make(error, context: "Analiz açılamadı", fallbackTitle: "Analiz açılamadı").fullText
            }
            openingRecentID = nil
        }
    }

    private func openReport(_ report: ReportRow) {
        guard openingReportID == nil else { return }
        openingReportID = report.id
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let requestID = UUID().uuidString
        let supportID = AppErrorMessage.newSupportID()

        Task {
            do {
                let url = try await AnalysisService.shared.reportFileURL(
                    for: report,
                    requestID: requestID,
                    supportID: supportID
                )
                reportPreviewItem = ShareItem(url: url)
            } catch {
                analysisError = AppErrorMessage.make(
                    error,
                    context: "Rapor açılamadı",
                    fallbackTitle: "Rapor açılamadı"
                ).fullText
            }
            openingReportID = nil
        }
    }
}

// MARK: - HomeHeader

private struct HomeHeader: View {
    @EnvironmentObject var app: AppState
    @State private var showPaywall = false

    var body: some View {
        HStack {
            RDLogo(size: 18)
            Spacer()
            RDHeaderAccountCTA {
                showPaywall = true
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .zIndex(100)
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(onClose: { showPaywall = false },
                        onSubscribe: {
                            showPaywall = false
                            Task { await app.auth.refreshProfile() }
                        })
        }
    }
}

// MARK: - RecentAnalysisCard

struct RecentAnalysisCard: View {
    let item: RecentAnalysis
    var isLoading: Bool = false
    let action: () -> Void

    private let ringSize: CGFloat = 94
    private let innerPhotoSize: CGFloat = 78

    private var primaryLevel: RiskLevel {
        item.findings.first?.level ?? .unknown
    }

    private var primaryLabel: String {
        item.findings.first?.title ?? primaryLevel.label
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    Color.rdCritical.opacity(0.72),
                                    Color.rdHigh.opacity(0.58),
                                    Color.rdMedium.opacity(0.52),
                                    Color.rdCritical.opacity(0.62),
                                    Color(red: 0.93, green: 0.12, blue: 0.38).opacity(0.66),
                                    Color.rdCritical.opacity(0.72)
                                ],
                                center: .center
                            ),
                            lineWidth: 3.5
                        )
                        .frame(width: ringSize, height: ringSize)

                    Circle()
                        .fill(Color.rdWhite)
                        .frame(width: ringSize - 9, height: ringSize - 9)

                    AnalysisThumbnail(
                        path: item.photoPath,
                        isTextAnalysis: item.isTextAnalysis,
                        cornerRadius: innerPhotoSize / 2
                    )
                        .frame(width: innerPhotoSize, height: innerPhotoSize)
                        .clipShape(Circle())
                }
                .frame(width: ringSize, height: ringSize)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.rdBlack)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .offset(x: 2, y: 2)
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8.5, weight: .black, design: .rounded))
                        Text("\(item.count)")
                            .rdMono(size: 10, weight: .black)
                    }
                    .foregroundStyle(Color.rdBlack)
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(.ultraThinMaterial.opacity(0.96))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.rdWhite.opacity(0.74), lineWidth: 1))
                    .offset(x: 3, y: 3)
                }
            }
            .frame(width: ringSize + 8, height: ringSize + 8)
        }
        .buttonStyle(RDPressableButtonStyle())
    }

}

// MARK: - HomeReportRow

private struct HomeReportRow: View {
    let report: ReportRow
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(kindStyle.text)
                    .frame(width: 38, height: 38)
                    .background(kindStyle.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 5) {
                    Text(reportTitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(kindLabel)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(kindStyle.text)
                            .padding(.horizontal, 8)
                            .frame(height: 23)
                            .background(kindStyle.background)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        Text(dateText)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }
            }
            .padding(12)
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    private var iconName: String {
        if isExcel { return "tablecells.fill" }
        return isRiskAnalysis ? "tablecells" : "doc.richtext"
    }

    private var isExcel: Bool {
        report.format == "xlsx" || report.mimeType == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    }

    private var isRiskAnalysis: Bool {
        report.kind == PDFReportKind.riskAnalysis.rawValue
    }

    private var kindLabel: String {
        if isExcel { return "Excel tablo" }
        return isRiskAnalysis ? "Risk analizi" : "Standart rapor"
    }

    private var kindStyle: (text: Color, background: Color) {
        if isExcel {
            return (Color(hex: "#2563EB"), Color(hex: "#EAF1FF"))
        }
        if isRiskAnalysis {
            return (Color.rdGreen, Color.rdGreenSoft)
        }
        return (Color(hex: "#6D5DF6"), Color(hex: "#EFEDFF"))
    }

    private var reportTitle: String {
        guard let separatorRange = report.title.range(of: " · ", options: .backwards) else {
            return report.title
        }
        return String(report.title[..<separatorRange.lowerBound])
    }

    private var dateText: String {
        guard let date = report.createdAt.flatMap(Self.parseDate) else { return "Tarih yok" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM HH:mm"
        return formatter.string(from: date)
    }

    private static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }
}

struct PhotoSourceSheet: View {
    let onCamera: () -> Void
    let onGallery: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 48, height: 48)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Saha fotoğrafı")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text("Fotoğrafı nereden almak istiyorsun?")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                        .frame(width: 38, height: 38)
                        .background(Color.rdCloud)
                        .clipShape(Circle())
                }
                .buttonStyle(RDPressableButtonStyle())
                .accessibilityLabel("Kapat")
            }

            VStack(spacing: 10) {
                sourceButton(
                    title: "Kamera ile çek",
                    subtitle: "Sahada anında fotoğraf al",
                    icon: "camera.fill",
                    action: onCamera
                )
                sourceButton(
                    title: "Galeriden seç",
                    subtitle: "Var olan saha görselini kullan",
                    icon: "photo.on.rectangle.angled",
                    action: onGallery
                )
            }

            Text("Fotoğraf seçildikten sonra istersen riskli alanları işaretleyebilirsin.")
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.rdPaper)
    }

    private func sourceButton(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .frame(width: 44, height: 44)
                    .background(Color.rdWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13)
                            .stroke(Color.rdLine, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

// MARK: - FlowLayout

/// Basit bir flow layout — chip dizisi için satır taşması yapar.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var width: CGFloat = 0
        var height: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth + size.width > maxWidth, lineWidth > 0 {
                width = max(width, lineWidth - spacing)
                height += lineHeight + lineSpacing
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        width = max(width, lineWidth - spacing)
        height += lineHeight
        return CGSize(width: max(0, width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
}
