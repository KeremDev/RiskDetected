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
    @State private var openingRecentID: UUID? = nil
    @State private var quotaUsage: DailyQuotaUsage? = nil
    @State private var showPaywall = false

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

                    RDButton(
                        title: "Taramayı Başlat",
                        style: .detect,
                        icon: "sparkles",
                        backgroundOverride: .rdBlack,
                        foregroundOverride: .rdGreen,
                        shadowOverride: Color.rdBlack.opacity(0.14)
                    ) {
                        startAnalysisFlow()
                    }
                    .frame(height: 56)
                    .padding(.top, 14)

                    recentSection
                        .padding(.top, 28)
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
            await loadQuotaUsage()
        }
        .onChange(of: app.auth.session?.user.id) { _ in
            Task {
                await loadRecentItems()
                await loadQuotaUsage()
            }
        }
        .onChange(of: app.isPro) { _ in
            Task { await loadQuotaUsage() }
        }
        .confirmationDialog("Saha fotoğrafı", isPresented: $showSourceDialog, titleVisibility: .visible) {
            Button("Kamera ile çek") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showCameraPicker = true
                } else {
                    // Simülatörde kamera yok — galeriye düş
                    showGalleryPicker = true
                }
            }
            Button("Galeriden seç") { showGalleryPicker = true }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Fotoğrafı nereden almak istersin?")
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
                onUpgradeRequested: { showPaywall = true }
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
                        await loadQuotaUsage()
                    }
                }
            )
            .environmentObject(app)
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(
                onClose: { showPaywall = false },
                onSubscribe: {
                    showPaywall = false
                    Task { await app.auth.refreshProfile() }
                }
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
                            .font(.system(size: 14, weight: .semibold))
                        Text(m.label)
                            .font(.system(size: 14, weight: .semibold))
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
                showPaywall = true
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
                                    .font(.system(size: 12, weight: .bold))
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
                                    .font(.system(size: 12, weight: .semibold))
                                Text("İşaretlemeyi düzenle")
                                    .font(.system(size: 12, weight: .semibold))
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
                            // Kamera ikonu — katmanlı gölge ile boyut
                            ZStack {
                                // Dış glow halkası
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color.rdGreen.opacity(0.12))
                                    .frame(width: 68, height: 68)
                                    .blur(radius: 6)
                                    .offset(y: 3)

                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.rdGreenSoft, Color.rdGreen.opacity(0.22)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 56, height: 56)
                                    .shadow(color: Color.rdGreen.opacity(0.3), radius: 8, x: 0, y: 4)

                                Image(systemName: "camera.fill")
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(Color.rdGreenDark)
                            }
                            .frame(width: 68, height: 68)

                            Text("Saha fotoğrafı yükle")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.rdBlack)
                            Text("Kamerayla çek veya galeriden seç")
                                .font(.system(size: 13))
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
                            // Kart zemini — üstten alta hafif gradient
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.rdWhite, Color.rdGreen.opacity(0.04)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                            // Dashed border — marka siyahıyla daha net bir çerçeve.
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(
                                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                                )
                                .foregroundStyle(Color.rdBlack)
                        }
                    )
                    // Çift katman gölge: ambient + directional
                    .shadow(color: Color.black.opacity(0.04), radius: 1, x: 0, y: 1)
                    .shadow(color: Color.black.opacity(0.07), radius: 14, x: 0, y: 6)
                    // Alt yeşil glow
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.rdGreen.opacity(0.08))
                            .frame(height: 60)
                            .blur(radius: 12)
                            .offset(y: 10)
                            .allowsHitTesting(false)
                    }
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
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.rdCritical)
                }
                .frame(width: 82, height: 82)

                Text("Günlük free limit doldu")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.rdBlack)
                Text("Yeni fotoğraf analizi için yarın tekrar dene veya PRO ile sınırsız taramaya geç.")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.rdSlate)
                    .frame(maxWidth: 280)

                HStack(spacing: 5) {
                    Text("PRO'ya geç")
                        .font(.system(size: 12, weight: .heavy))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
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
                    showPaywall = true
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
                                Text("Saha gözlemini yaz veya prosedür metnini yapıştır...")
                                Text("Örn: \"Yüksekte çalışma alanında korkuluk eksik, işçi paraşüt tipi emniyet kemeri kullanmıyor.\"")
                                    .padding(.top, 4)
                            }
                            .font(.system(size: 15))
                            .foregroundStyle(Color.rdSlate)
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                            .allowsHitTesting(false)
                        }
                        TextEditor(text: $text)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.rdBlack)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(minHeight: 160)
                            .onChange(of: text) { new in
                                if new.count > 2000 {
                                    text = String(new.prefix(2000))
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
                        Text("Maks. 2000 karakter")
                            .font(.system(size: 12))
                        Spacer()
                        Text("\(text.count)/2000")
                            .rdMono(size: 12, weight: .medium)
                    }
                    .foregroundStyle(Color.rdSlate)
                    .padding(.horizontal, 2)
                }
            }
        }
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
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color.rdCritical)
            }

            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.rdBlack)

            Text(subtitle)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.rdSlate)
                .frame(maxWidth: 290)

            HStack(spacing: 5) {
                Text("PRO'ya geç")
                    .font(.system(size: 12, weight: .heavy))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
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
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.rdSlate)
                Spacer()
                Button("Tümü") { /* navigate to history */ }
                    .font(.system(size: 13, weight: .semibold))
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

    private var emptyRecentCard: some View {
        RDCard {
            HStack(spacing: 12) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.rdGreenDark)
                    .frame(width: 42, height: 42)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Henüz tamamlanmış analiz yok")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.rdBlack)
                    Text("İlk tarama tamamlandığında burada listelenecek.")
                        .font(.system(size: 12))
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
            showPaywall = true
            return
        }
        if mode == .photo && selectedImage == nil {
            showSourceDialog = true
            return
        }
        if mode == .text && text.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 {
            // Minimum içerik yok — kullanıcı text alanına odaklanacak (keyboard zaten açık)
            return
        }
        showCanvasSheet = true
    }

    /// AnnotateView'daki "İşaretli alanları analiz et" sonrası ana sayfada
    /// bekletmeden doğrudan analiz odağı seçimine geçer.
    private func continueFromAnnotatedPhoto() {
        guard mode == .photo, selectedImage != nil else { return }
        if !app.isPro, quotaUsage?.isExhausted == true {
            showPaywall = true
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
            showPaywall = true
            Task { await loadQuotaUsage() }
        } else {
            analysisError = normalized.fullText
        }
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

                    AnalysisThumbnail(path: item.photoPath, cornerRadius: innerPhotoSize / 2)
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
                            .font(.system(size: 8.5, weight: .black))
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
