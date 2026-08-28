import SwiftUI

// MARK: - AnalysisJob

/// iOS 26 SwiftUI bug workaround: fullScreenCover(isPresented:) captures stale @State
/// value when two state vars are set in same sync frame. Using fullScreenCover(item:)
/// guarantees the closure captures the live item at presentation time.
struct AnalysisJob: Identifiable {
    let id = UUID()
    let previewImage: UIImage?
    let presentationMode: AnalysisWaitingPresentationMode
    let photoCount: Int
    let work: (@escaping @MainActor (AnalysisProgressUpdate) -> Void) async throws -> AnalysisResultBundle
}

private struct PaywallPresentation: Identifiable {
    let id = UUID()
}

private enum PhotoTrayDismissDestination {
    case camera
    case gallery
    case annotation(UUID)
    case preAnalysis
    case paywall
}

private struct PendingPhotoImport {
    let images: [UIImage]
    let shouldAnnotate: Bool
    let returnToPhotoTrayAfterAnnotate: Bool
}

#if DEBUG
private struct GalleryPickerDismissFixtureView: View {
    let onPick: () -> Void
    @State private var didPick = false

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .onAppear {
                guard !didPick else { return }
                didPick = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    onPick()
                }
            }
    }
}
#endif

private struct AnalysisPhotoDraft: Identifiable {
    let id: UUID
    var image: UIImage

    init(id: UUID = UUID(), image: UIImage) {
        self.id = id
        self.image = image
    }
}

private let freeQuotaCachePrefix = "rd.home.freeQuota"
private let analysisSectorSheetHeight: CGFloat = 600

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedCanvases: Set<AnalysisCanvas> = [.general]
    @State private var showCanvasSheet = false
    @State private var showSectorSheet = false
    @State private var selectedAnalysisSector: AnalysisSectorID?
    @State private var showAnnotate = false
    @State private var pendingAnnotateRequestID: UUID?
    @State private var showResult = false

    // Foto akışı state
    @State private var showSourceDialog = false
    @State private var showCameraPicker = false
    @State private var showGalleryPicker = false
    @State private var selectedPhotos: [AnalysisPhotoDraft] = []
    @State private var annotatingPhotoID: UUID?
    @State private var queuedAnnotatePhotoIDs: [UUID] = []
    @State private var returnToPhotoTrayAfterAnnotation = false
    @State private var pendingPhotoTrayDismissDestination: PhotoTrayDismissDestination?
    @State private var pendingPhotoImport: PendingPhotoImport?
    @State private var continueAfterAnnotationDismiss = false

    // Analiz state
    @State private var analysisResult: AnalysisResultBundle? = nil
    @State private var analysisError: String? = nil
    @State private var analysisErrorTitle: String = RDLocalization.string("analysis.home.view.analiz.hatasi.5a62e64f", table: .analysis, fallback: "Analiz Hatası")
    @State private var pendingJob: AnalysisJob? = nil
    @State private var recentItems: [RecentAnalysis] = []
    @State private var recentReports: [ReportRow] = []
    @State private var openingRecentID: UUID? = nil
    @State private var resumingInFlightID: UUID? = nil
    @State private var openingReportID: UUID? = nil
    @State private var didOpenUITestResult = false
    @State private var didOpenUITestAnalyzing = false
    @State private var didOpenE2ERealAnalysis = false
    @State private var quotaUsage: DailyQuotaUsage? = nil
    @State private var professionalProgressSummary: ProfessionalProgressSummary? = nil
    @State private var showProfessionalTitlesSheet = false
    @State private var paywallPresentation: PaywallPresentation? = nil
    @State private var restoreCanvasSheetAfterPaywall = false
    @State private var reportPreviewItem: ShareItem?

    var body: some View {
        VStack(spacing: 0) {
            HomeHeader()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if RDConfig.Features.professionalProgressEnabled,
                       RDProfessionalProgressLocalizationReview.isAvailable,
                       let professionalProgressSummary {
                        ProfessionalProgressWeeklyTrackingCard(
                            summary: professionalProgressSummary,
                            displayStyle: .compact
                        )
                        .padding(.bottom, 12)
                    }

                    photoUploadCard

                    if !app.currentTier.isPaid {
                        freeQuotaHint
                            .padding(.top, 10)
                    }

                    RDButton(
                        title: RDLocalization.string("analysis.home.view.taramayi.baslat.59df4910", table: .analysis, fallback: "Taramayı Başlat"),
                        style: .detect,
                        icon: "sparkles",
                        backgroundOverride: scanButtonBackground,
                        shadowOverride: scanButtonShadow
                    ) {
                        startAnalysisFlow()
                    }
                    .accessibilityIdentifier("home.start_scan")
                    .frame(height: 56)
                    .rdCardShadow(colorScheme: colorScheme, radius: 3, x: 8, y: 10)
                    .padding(.top, 14)

                    if RDConfig.Features.professionalProgressEnabled,
                       RDProfessionalProgressLocalizationReview.isAvailable,
                       let professionalProgressSummary {
                        ProfessionalProgressHomeCard(
                            summary: professionalProgressSummary,
                            onTap: { showProfessionalTitlesSheet = true }
                        )
                        .padding(.top, 18)
                    }

                    recentSection
                        .padding(.top, 28)

                    generatedReportsSection
                        .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, RDTabBar.contentClearance)
                .keyboardAdaptivePadding(extra: 16)
                .background(Color.rdWhite)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.rdWhite)
        }
        .background(Color.rdWhite.ignoresSafeArea())
        .task {
            await loadRecentItems()
            await loadRecentReports()
            await loadQuotaUsage()
            await loadProfessionalProgress()
        }
        .onAppear {
            closeFreeQuotaEntryPointsIfNeeded()
            preparePhotoTrayFixtureIfNeeded()
            handlePendingQuickScanOnAppear()
            openUITestResultIfNeeded()
            openAnalyzingFixtureIfNeeded()
            openRealE2EAnalysisIfNeeded()
            openPendingAnalysisResultIfNeeded()
            resumeInFlightAnalysisIfNeeded()
            Task {
                await loadRecentItems()
                await loadRecentReports()
                await loadProfessionalProgress()
            }
        }
        .onChange(of: app.auth.session?.user.id) { _ in
            Task {
                await loadRecentItems()
                await loadRecentReports()
                await loadQuotaUsage()
                await loadProfessionalProgress()
            }
            resumeInFlightAnalysisIfNeeded()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            openPendingAnalysisResultIfNeeded()
            resumeInFlightAnalysisIfNeeded()
        }
        .onChange(of: app.pendingAnalysisResultID) { _ in
            openPendingAnalysisResultIfNeeded()
        }
        .onChange(of: app.currentTier) { _ in
            normalizeSelectedCanvasesForTier()
            closeFreeQuotaEntryPointsIfNeeded()
            Task { await loadQuotaUsage() }
        }
        .onChange(of: maxSelectablePhotos) { _ in
            preparePhotoTrayFixtureIfNeeded()
        }
        .onChange(of: quotaUsage) { _ in
            closeFreeQuotaEntryPointsIfNeeded()
        }
        .onChange(of: app.quickScanRequestID) { _ in
            handleQuickScanRequest()
        }
        .sheet(isPresented: $showSourceDialog, onDismiss: presentPendingPhotoTrayDestinationIfNeeded) {
            PhotoMediaTraySheet(
                photos: selectedPhotos,
                maxPhotoCount: maxSelectablePhotos,
                visibleSlotCount: visiblePhotoSlotCount,
                canAddMore: selectedPhotos.count < maxSelectablePhotos,
                onCamera: openCameraFromPhotoTray,
                onGallery: openGalleryFromPhotoTray,
                onAnnotate: { id in
                    startAnnotatingPhoto(id, returnToPhotoTray: true)
                },
                onRemove: removePhoto,
                onMove: movePhoto,
                onLockedSlot: {
                    pendingPhotoTrayDismissDestination = .paywall
                    showSourceDialog = false
                },
                onStartAnalysis: {
                    pendingPhotoTrayDismissDestination = .preAnalysis
                    showSourceDialog = false
                },
                onClose: { showSourceDialog = false }
            )
            .presentationDetents([
                .height(PhotoMediaTraySheet.detentHeight(
                    photosCount: selectedPhotos.count,
                    maxPhotoCount: maxSelectablePhotos,
                    visibleSlotCount: visiblePhotoSlotCount
                ))
            ])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(isPresented: $showCanvasSheet) {
            CanvasSheet(
                selected: $selectedCanvases,
                userTier: app.currentTier,
                legislationCanvasEnabled: app.legislationCanvasEnabled,
                onConfirm: {
                    showCanvasSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        continueAfterCanvasSelection()
                    }
                },
                onUpgradeRequested: {
                    showCanvasSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showPlainPaywall(restoreCanvasAfterDismiss: true)
                    }
                }
            )
            .presentationDetents([.height(360), .large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(isPresented: $showSectorSheet) {
            AnalysisSectorPickerView(
                items: sectorPickerItems,
                selected: $selectedAnalysisSector,
                onContinue: {
                    showSectorSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        continueAfterSectorSelection()
                    }
                }
            )
            .presentationDetents([.height(analysisSectorSheetHeight)])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(preferredModalColorScheme)
        }
        .fullScreenCover(
            isPresented: $showCameraPicker,
            onDismiss: consumePendingPhotoImportAfterPickerDismissal
        ) {
            CameraPicker { image in
                if let image {
                    pendingPhotoImport = PendingPhotoImport(
                        images: [image],
                        shouldAnnotate: true,
                        returnToPhotoTrayAfterAnnotate: true
                    )
                }
                showCameraPicker = false
            }
            .ignoresSafeArea()
            .preferredColorScheme(preferredModalColorScheme)
            .onDisappear {
                showCameraPicker = false
            }
        }
        .fullScreenCover(
            isPresented: $showGalleryPicker,
            onDismiss: consumePendingPhotoImportAfterPickerDismissal
        ) {
            #if DEBUG
            if Self.isUITestSimulatedGalleryImport {
                GalleryPickerDismissFixtureView {
                    stageGalleryPhotoImport([
                        Self.uiTestPhotoFixture(seed: 21),
                        Self.uiTestPhotoFixture(seed: 22),
                        Self.uiTestPhotoFixture(seed: 23),
                    ])
                }
            } else {
                galleryPickerContent
            }
            #else
            galleryPickerContent
            #endif
        }
        .fullScreenCover(
            isPresented: annotatePresentationBinding,
            onDismiss: continueAfterAnnotationPresentationDismissal
        ) {
            AnnotateView(
                initialImage: annotatingPhoto?.image,
                primaryActionTitle: annotatePrimaryActionTitle,
                primaryActionIcon: annotatePrimaryActionIcon,
                onCancel: {
                    dismissAnnotationAndContinue()
                },
                onAnalyze: { annotated in
                    updateAnnotatedPhoto(with: annotated)
                    dismissAnnotationAndContinue()
                }
            )
            .preferredColorScheme(preferredModalColorScheme)
        }
        .fullScreenCover(item: $pendingJob) { job in
            AnalyzingView(
                isPresented: Binding(
                    get: { pendingJob != nil },
                    set: { if !$0 { pendingJob = nil } }
                ),
                asyncWork: job.work,
                previewImage: job.previewImage,
                presentationMode: job.presentationMode,
                photoCount: job.photoCount,
                onComplete: { result in
                    analysisResult = result
                    resumingInFlightID = nil
                    if !app.currentTier.isPaid {
                        markFreeQuotaExhaustedLocally()
                    }
                    pendingJob = nil
                    Task {
                        await loadProfessionalProgress()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showResult = true
                    }
                },
                onError: { msg in
                    resumingInFlightID = nil
                    pendingJob = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        handleAnalysisError(msg)
                    }
                }
            )
            .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(item: $reportPreviewItem) { item in
            DocumentPreview(url: item.url)
                .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(isPresented: $showProfessionalTitlesSheet) {
            if RDProfessionalProgressLocalizationReview.isAvailable,
               let professionalProgressSummary {
                ProfessionalProgressTitlesSheet(summary: professionalProgressSummary)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .preferredColorScheme(preferredModalColorScheme)
            }
        }
        .fullScreenCover(isPresented: $showResult) {
            ResultView(
                bundle: analysisResult,
                localPreviewImage: primarySelectedImage,
                localPreviewImages: selectedImages,
                onClose: {
                    showResult = false
                    resetAnalysisDraft()
                    analysisResult = nil
                    Task {
                        await loadRecentItems()
                        await loadRecentReports()
                        await loadQuotaUsage()
                        await loadProfessionalProgress()
                    }
                }
            )
            .environmentObject(app)
            .preferredColorScheme(preferredModalColorScheme)
        }
        .fullScreenCover(item: $paywallPresentation, onDismiss: {
            restoreCanvasSheetAfterPaywallIfNeeded()
        }) { presentation in
            FreeAwarePaywallView(
                onClose: {
                    paywallPresentation = nil
                },
                onSubscribe: {
                    handlePaywallSubscription()
                },
                notice: nil
            )
            .preferredColorScheme(preferredModalColorScheme)
        }
        .alert(analysisErrorTitle, isPresented: .init(
            get: { analysisError != nil },
            set: {
                if !$0 {
                    analysisError = nil
                    analysisErrorTitle = RDLocalization.string("analysis.home.view.analiz.hatasi.a9fd1811", table: .analysis, fallback: "Analiz Hatası")
                }
            }
        )) {
            Button(RDLocalization.string("analysis.home.view.tamam.b16fe160", table: .analysis, fallback: "Tamam")) {
                analysisError = nil
                analysisErrorTitle = RDLocalization.string("analysis.home.view.analiz.hatasi.fb111abd", table: .analysis, fallback: "Analiz Hatası")
            }
        } message: {
            Text(analysisError ?? "")
        }
    }

    // MARK: - Subviews

    private var preferredModalColorScheme: ColorScheme {
        app.themePreference.colorScheme ?? colorScheme
    }

    private var galleryPickerContent: some View {
        MultiGalleryPicker(selectionLimit: remainingPhotoSlots) { images in
            stageGalleryPhotoImport(images)
        }
        .ignoresSafeArea()
        .preferredColorScheme(preferredModalColorScheme)
        .onDisappear {
            showGalleryPicker = false
        }
    }

    private var scanButtonBackground: Color {
        preferredModalColorScheme == .dark ? .rdGreen : .rdOnyx
    }

    private var scanButtonShadow: Color {
        if preferredModalColorScheme == .dark {
            return Color.rdGreen.opacity(0.28)
        }
        return Color.rdOnyx.opacity(0.18)
    }

    private var selectedImages: [UIImage] {
        selectedPhotos.map(\.image)
    }

    private var primarySelectedImage: UIImage? {
        selectedPhotos.first?.image
    }

    private var annotatingPhoto: AnalysisPhotoDraft? {
        guard let annotatingPhotoID else { return nil }
        return selectedPhotos.first { $0.id == annotatingPhotoID }
    }

    private var maxSelectablePhotos: Int {
        return app.planCapabilities.safeMaxPhotosPerAnalysis
    }

    private var visiblePhotoSlotCount: Int {
        return app.planCapabilities.safeVisiblePhotoSlotsInUI
    }

    private var remainingPhotoSlots: Int {
        max(maxSelectablePhotos - selectedPhotos.count, 1)
    }

    private var annotatePresentationBinding: Binding<Bool> {
        Binding(
            get: {
                showAnnotate && annotatingPhoto != nil
            },
            set: { newValue in
                if !newValue {
                    pendingAnnotateRequestID = nil
                    annotatingPhotoID = nil
                    continueAfterAnnotationDismiss = true
                    showAnnotate = false
                }
            }
        )
    }

    private var annotatePrimaryActionTitle: String {
        returnToPhotoTrayAfterAnnotation ? RDLocalization.string("analysis.home.view.isaretlemeyi.kaydet.aa26b5c5", table: .analysis, fallback: "İşaretlemeyi kaydet") : RDLocalization.string("analysis.home.view.isaretli.alanlari.analiz.et.20a08616", table: .analysis, fallback: "İşaretli alanları analiz et")
    }

    private var annotatePrimaryActionIcon: String {
        returnToPhotoTrayAfterAnnotation ? "checkmark" : "sparkles"
    }

    private var photoUploadCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(RDLocalization.string("analysis.home.view.saha.fotograflari.b396eb02", table: .analysis, fallback: "Saha fotoğrafları"), systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: RDFontScale.size(15), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Spacer(minLength: 0)
                Text("\(selectedPhotos.count)/\(maxSelectablePhotos)")
                    .rdMono(size: 12, weight: .semibold)
                    .foregroundStyle(Color.rdSlate)
            }

            if isFreeQuotaExhausted && selectedPhotos.isEmpty {
                Button {
                    showQuotaPaywall()
                } label: {
                    lockedPhotoUploadContent
                }
                .buttonStyle(RDPressableButtonStyle())
            } else {
                Button {
                    openPhotoUploadCard()
                } label: {
                    if selectedPhotos.isEmpty {
                        emptyPhotoUploadDropZone
                    } else {
                        selectedPhotoUploadSummaryRow
                    }
                }
                .buttonStyle(RDPressableButtonStyle())
                .accessibilityIdentifier("home.photo_tray.open")

                if !selectedPhotos.isEmpty {
                    photoUploadPreviewStrip
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.rdWhite)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.rdLine, lineWidth: 1)
                )
        )
        .homeCardDepth(colorScheme: colorScheme, radius: 18, y: 8)
    }

    private var emptyPhotoUploadDropZone: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.rdWhite)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                            .foregroundStyle(Color.rdSlate.opacity(0.45))
                    )

                Image(systemName: "plus")
                    .font(.system(size: RDFontScale.size(32), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdGreenDark)
            }
            .frame(width: 82, height: 82)

            VStack(spacing: 5) {
                Text(RDLocalization.string("analysis.home.view.saha.fotografi.yukle.fc090c81", table: .analysis, fallback: "Saha fotoğrafı yükle"))
                    .font(.system(size: RDFontScale.size(17), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Text(RDLocalization.string("analysis.home.view.jpg.png.heic.48da947b", table: .analysis, fallback: "JPG · PNG · HEIC"))
                    .rdMono(size: 11, weight: .medium)
                    .foregroundStyle(Color.rdSlate.opacity(0.78))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 178)
        .background(Color.clear)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var selectedPhotoUploadSummaryRow: some View {
        HStack(spacing: 12) {
            photoUploadSummaryIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(
                    RDLocalization.plural(
                        "analysis.count.photos_added",
                        table: .analysis,
                        value: selectedPhotos.count,
                        fallbackOne: "%lld fotoğraf eklendi",
                        fallbackOther: "%lld fotoğraf eklendi"
                    )
                )
                    .font(.system(size: RDFontScale.size(16), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Text(RDLocalization.string("analysis.home.view.fotograflari.duzenle.7c862adf", table: .analysis, fallback: "Fotoğrafları düzenle"))
                    .rdMono(size: 11, weight: .medium)
                    .foregroundStyle(Color.rdSlate.opacity(0.78))
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.up")
                .font(.system(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .frame(width: 34, height: 34)
                .background(Color.rdFog)
                .clipShape(Circle())
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(Color.rdFog)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var photoUploadSummaryIcon: some View {
        ZStack {
            if let image = selectedPhotos.first?.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.72), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.rdWhite)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.4, dash: [6, 4]))
                            .foregroundStyle(Color.rdSlate.opacity(0.45))
                    )
                Image(systemName: "plus")
                    .font(.system(size: RDFontScale.size(22), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdGreenDark)
            }
        }
        .frame(width: 54, height: 54)
    }

    private var photoUploadPreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedPhotos.enumerated()), id: \.element.id) { index, draft in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            startAnnotatingPhoto(draft.id, returnToPhotoTray: true)
                        } label: {
                            Image(uiImage: draft.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 62, height: 62)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.photo_preview.\(index + 1)")

                        Text("\(index + 1)")
                            .rdMono(size: 10, weight: .bold)
                            .foregroundStyle(Color.rdOnyx)
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.92))
                            .clipShape(Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(5)

                        Button {
                            removePhoto(draft.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: RDFontScale.size(9), weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.black.opacity(0.62))
                                .clipShape(Circle())
                        }
                        .buttonStyle(RDPressableButtonStyle())
                        .padding(4)
                        .accessibilityLabel(RDLocalization.format("analysis.home.view.1.fotografi.sil.63339467", table: .analysis, fallback: "%1$@. fotoğrafı sil", arguments: [String(describing: index + 1)]))
                    }
                    .frame(width: 62, height: 62)
                }

                if selectedPhotos.count < maxSelectablePhotos {
                    Button {
                        openPhotoTray()
                    } label: {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.rdFog)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.3, dash: [6, 4]))
                                    .foregroundStyle(Color.rdSlate.opacity(0.38))
                            )
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: RDFontScale.size(20), weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.rdSlate)
                            )
                            .frame(width: 62, height: 62)
                    }
                    .buttonStyle(RDPressableButtonStyle())
                    .accessibilityIdentifier("home.photo_preview.add")
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var lockedPhotoUploadContent: some View {
        ZStack {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(lockedPhotoIconBackground)
                        .frame(width: 74, height: 74)
                        .shadow(color: lockedPhotoIconShadow, radius: 16, x: 0, y: 8)

                    Circle()
                        .stroke(lockedPhotoCriticalColor, lineWidth: 6)
                        .frame(width: 56, height: 56)

                    Image(systemName: "lock.fill")
                        .font(.system(size: RDFontScale.size(20), weight: .bold, design: .rounded))
                        .foregroundStyle(lockedPhotoCriticalColor)
                }
                .frame(width: 82, height: 82)

                Text(RDLocalization.string("analysis.home.view.ucretsiz.hak.doldu.c16fcce9", table: .analysis, fallback: "Ücretsiz hak doldu"))
                    .font(.system(size: RDFontScale.size(18), weight: .bold, design: .rounded))
                    .foregroundStyle(lockedPhotoTitleColor)
                Text(RDLocalization.string("analysis.home.view.gunde.1.ucretsiz.analiz.hakkin.doldu.plus.veya.p.54c5c949", table: .analysis, fallback: "Günde 1 ücretsiz analiz hakkın doldu. Plus veya Pro ile devam et."))
                    .font(.system(size: RDFontScale.size(13), design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(lockedPhotoSubtitleColor)
                    .frame(maxWidth: 280)

                HStack(spacing: 5) {
                    Text(RDLocalization.string("analysis.home.view.yukselt.679408d0", table: .analysis, fallback: "Yükselt"))
                        .font(.system(size: RDFontScale.size(12), weight: .heavy, design: .rounded))
                    Image(systemName: "chevron.right")
                        .font(.system(size: RDFontScale.size(10), weight: .bold, design: .rounded))
                }
                .foregroundStyle(lockedPhotoActionColor)
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
                        colors: lockedPhotoBackgroundColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.7, dash: [6, 4])
                        )
                        .foregroundStyle(lockedPhotoBorderColor)
                )
        )
        .shadow(color: lockedPhotoCardShadow, radius: 16, x: 0, y: 8)
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var lockedPhotoBackgroundColors: [Color] {
        if isDarkMode {
            return [
                Color(hex: "#171B1C"),
                Color(hex: "#141718"),
                Color(hex: "#1B1112")
            ]
        }
        return [Color.rdWhite, Color.rdCriticalBg.opacity(0.68)]
    }

    private var lockedPhotoCriticalColor: Color {
        isDarkMode ? Color(hex: "#F05A4F") : Color.rdCritical
    }

    private var lockedPhotoIconBackground: Color {
        isDarkMode ? Color.rdCritical.opacity(0.16) : Color.rdCritical.opacity(0.10)
    }

    private var lockedPhotoIconShadow: Color {
        isDarkMode ? Color.rdCritical.opacity(0.24) : Color.rdCritical.opacity(0.18)
    }

    private var lockedPhotoTitleColor: Color {
        isDarkMode ? Color.white : Color.rdBlack
    }

    private var lockedPhotoSubtitleColor: Color {
        isDarkMode ? Color.rdCharcoal.opacity(0.92) : Color.rdSlate
    }

    private var lockedPhotoActionColor: Color {
        isDarkMode ? Color.rdPlanPlus : Color.rdCritical
    }

    private var lockedPhotoBorderColor: Color {
        isDarkMode ? Color.rdCritical.opacity(0.44) : Color.rdCritical.opacity(0.38)
    }

    private var lockedPhotoCardShadow: Color {
        isDarkMode ? Color.black.opacity(0.28) : Color.rdCritical.opacity(0.10)
    }

    private var freeQuotaHint: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isFreeQuotaExhausted {
                showPlainPaywall()
            }
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
                    Text(RDLocalization.string("analysis.home.view.ucretsiz.analiz.hakki.795e8ebb", table: .analysis, fallback: "Ücretsiz Analiz Hakkı"))
                        .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(freeQuotaHintSubtitle)
                        .font(.system(size: RDFontScale.size(11), design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Image(systemName: "gift.fill")
                    .font(.system(size: RDFontScale.size(12), weight: .heavy, design: .rounded))
                    .foregroundStyle(SubscriptionTier.plus.accentTextColor)
                    .frame(width: 28, height: 28)
                    .background(SubscriptionTier.plus.accentSoftColor)
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
        .homeCardDepth(colorScheme: colorScheme, radius: 14, y: 6)
        .accessibilityLabel(RDLocalization.format("analysis.home.view.free.kullanim.bilgisi.1.3f83c487", table: .analysis, fallback: "Free kullanım bilgisi. %1$@", arguments: [String(describing: freeQuotaHintSubtitle)]))
    }

    private var freeQuotaCompactText: String {
        guard let quotaUsage else { return "1/1" }
        return "\(quotaUsage.remaining)/\(quotaUsage.limit)"
    }

    private var freeQuotaHintSubtitle: String {
        if isFreeQuotaExhausted {
            return RDLocalization.string("analysis.home.view.bugunku.hakkin.doldu.daha.fazlasi.icin.hesabini..2f42126c", table: .analysis, fallback: "Bugünkü hakkın doldu. Daha fazlası için hesabını yükselt.")
        }
        return RDLocalization.string("analysis.home.view.gunde.1.ucretsiz.analiz.hakkin.hazir.904ba1c3", table: .analysis, fallback: "Günde 1 ücretsiz analiz hakkın hazır.")
    }


    private var recentSection: some View {
        homeSectionCard {
            sectionHeader(
                title: RDLocalization.string("analysis.home.view.son.uygunsuzluklar.4f75d259", table: .analysis, fallback: "Son uygunsuzluklar"),
                icon: "exclamationmark.triangle.fill",
                tint: Color.rdCritical,
                countLabel: RDLocalization.plural(
                    "analysis.count.records",
                    table: .analysis,
                    value: recentItems.count,
                    fallbackOne: "%lld kayıt",
                    fallbackOther: "%lld kayıt"
                )
            ) {
                app.activeTab = .analyses
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
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var generatedReportsSection: some View {
        homeSectionCard {
            sectionHeader(
                title: RDLocalization.string("analysis.home.view.olusturulan.raporlar.6b7245c9", table: .analysis, fallback: "Oluşturulan raporlar"),
                icon: "doc.richtext.fill",
                tint: Color.rdGreen,
                countLabel: RDLocalization.plural(
                    "reports.count.files",
                    table: .reports,
                    value: recentReports.count,
                    fallbackOne: "%lld dosya",
                    fallbackOther: "%lld dosya"
                )
            ) {
                app.activeTab = .reports
            }

            if recentReports.isEmpty {
                emptyReportsCard
            } else {
                VStack(spacing: 9) {
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
    }

    private func homeSectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: RDRadius.lg)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        .homeCardDepth(colorScheme: colorScheme, radius: 18, y: 8)
    }

    private func sectionHeader(
        title: String,
        icon: String,
        tint: Color,
        countLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .lineLimit(1)

                Text(countLabel)
                    .font(.system(size: RDFontScale.size(11.5), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdSlate.opacity(0.82))
                    .lineLimit(1)
            }

            Spacer()

            Button(action: action) {
                HStack(spacing: 4) {
                    Text(RDLocalization.string("analysis.home.view.tumu.51f59551", table: .analysis, fallback: "Tümü"))
                    Image(systemName: "chevron.right")
                        .font(.system(size: RDFontScale.size(8.5), weight: .black, design: .rounded))
                }
                .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreenDark)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Color.rdGreenSoft.opacity(0.72))
                .clipShape(Capsule())
            }
            .buttonStyle(RDPressableButtonStyle())
        }
    }

    private var emptyReportsCard: some View {
        RDCard {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: RDFontScale.size(18), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .frame(width: 42, height: 42)
                    .background(Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(RDLocalization.string("analysis.home.view.henuz.rapor.olusturulmadi.8ff986dc", table: .analysis, fallback: "Henüz rapor oluşturulmadı"))
                        .font(.system(size: RDFontScale.size(14), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(RDLocalization.string("analysis.home.view.pdf.veya.excel.ciktilari.burada.gorunecek.da7b3830", table: .analysis, fallback: "PDF veya Excel çıktıları burada görünecek."))
                        .font(.system(size: RDFontScale.size(12), design: .rounded))
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
                    .font(.system(size: RDFontScale.size(18), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdGreenDark)
                    .frame(width: 42, height: 42)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(RDLocalization.string("analysis.home.view.henuz.tamamlanmis.analiz.yok.40338932", table: .analysis, fallback: "Henüz tamamlanmış analiz yok"))
                        .font(.system(size: RDFontScale.size(14), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(RDLocalization.string("analysis.home.view.ilk.tarama.tamamlandiginda.burada.listelenecek.e43d3070", table: .analysis, fallback: "İlk tarama tamamlandığında burada listelenecek."))
                        .font(.system(size: RDFontScale.size(12), design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Helpers

    private var isFreeQuotaExhausted: Bool {
        !app.currentTier.isPaid && quotaUsage?.isExhausted == true
    }

    /// RDLocalization.string("analysis.home.view.taramayi.baslat.e82526ee", table: .analysis, fallback: "Taramayı Başlat") → foto yoksa medya tray; varsa sektör veya canvas seçimine geçer.
    private func startAnalysisFlow() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if app.requiresExplicitSafetyProfileSelection {
            presentAnalysisError(
                AppErrorMessage.make(
                    rawMessage: RDLocalization.string("analysis.home.view.choose.a.safety.terminology.profile.in.profile.b.e12b8d4c", table: .analysis, fallback: "Analize başlamadan önce Profil'de bir güvenlik terminolojisi profili seçin."),
                    context: RDLocalization.string("analysis.home.view.safety.terminology.required.f0f5c4a7", table: .analysis, fallback: "Güvenlik terminolojisi gerekli"),
                    fallbackTitle: RDLocalization.string("analysis.home.view.safety.terminology.required.a0bb8cf5", table: .analysis, fallback: "Güvenlik terminolojisi gerekli")
                )
            )
            return
        }
        if !app.currentTier.isPaid, quotaUsage?.isExhausted == true {
            showQuotaPaywall()
            return
        }
        if selectedPhotos.isEmpty {
            showSourceDialog = true
            return
        }
        beginPreAnalysisSelection()
    }

    private func openPhotoUploadCard() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if selectedPhotos.isEmpty {
            openInitialPhotoPickerFromHome()
        } else {
            openPhotoTray()
        }
    }

    private func openPhotoTray() {
        showSourceDialog = true
    }

    private func openInitialPhotoPickerFromHome() {
        #if DEBUG
        if Self.isUITestDirectHomePhotoPick {
            appendPickedPhotos(
                [Self.uiTestPhotoFixture(seed: 2)],
                shouldAnnotate: true,
                returnToPhotoTrayAfterAnnotate: true
            )
            return
        }
        #endif

        presentGalleryPicker()
    }

    private func resetAnalysisDraft() {
        selectedPhotos = []
        annotatingPhotoID = nil
        pendingAnnotateRequestID = nil
        queuedAnnotatePhotoIDs = []
        returnToPhotoTrayAfterAnnotation = false
        pendingPhotoTrayDismissDestination = nil
        pendingPhotoImport = nil
        continueAfterAnnotationDismiss = false
    }

    private func handleQuickScanRequest() {
        if !app.currentTier.isPaid, quotaUsage?.isExhausted == true {
            showQuotaPaywall()
            app.quickScanSource = .chooser
            return
        }
        let source = app.quickScanSource
        app.quickScanSource = .chooser
        switch source {
        case .camera:
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                presentCameraPicker()
            } else {
                presentGalleryPicker()
            }
            return
        case .gallery:
            presentGalleryPicker()
            return
        case .chooser:
            break
        }
        if selectedPhotos.isEmpty {
            showSourceDialog = true
        } else {
            beginPreAnalysisSelection()
        }
    }

    private func handlePendingQuickScanOnAppear() {
        guard app.quickScanSource != .chooser else { return }
        DispatchQueue.main.async {
            handleQuickScanRequest()
        }
    }

    /// Tray dışından başlatılan anotasyon sonrası sektör veya canvas seçimine geçer.
    private func continueFromAnnotatedPhoto() {
        guard !selectedPhotos.isEmpty else { return }
        if !app.currentTier.isPaid, quotaUsage?.isExhausted == true {
            showQuotaPaywall()
            return
        }
        beginPreAnalysisSelection()
    }

    private func continueAfterAnnotationStep() {
        if presentNextQueuedAnnotationIfNeeded() {
            return
        }
        if returnToPhotoTrayAfterAnnotation {
            returnToPhotoTrayAfterAnnotation = false
            DispatchQueue.main.async {
                showSourceDialog = true
            }
            return
        }
        continueFromAnnotatedPhoto()
    }

    @discardableResult
    private func presentNextQueuedAnnotationIfNeeded() -> Bool {
        queuedAnnotatePhotoIDs.removeAll { id in
            !selectedPhotos.contains(where: { $0.id == id })
        }
        guard let nextID = queuedAnnotatePhotoIDs.first else {
            return false
        }
        queuedAnnotatePhotoIDs.removeFirst()
        scheduleAnnotatePresentation(for: nextID)
        return true
    }

    private func queuePhotoAnnotations(
        for photoIDs: [UUID],
        returnToPhotoTray: Bool
    ) {
        let validIDs = photoIDs.filter { id in
            selectedPhotos.contains(where: { $0.id == id })
        }
        guard !validIDs.isEmpty else { return }
        queuedAnnotatePhotoIDs.append(contentsOf: validIDs)
        returnToPhotoTrayAfterAnnotation = returnToPhotoTray
        _ = presentNextQueuedAnnotationIfNeeded()
    }

    private func continueFromPhotoTrayToAnalysis() {
        guard !selectedPhotos.isEmpty else {
            showSourceDialog = true
            return
        }
        continueFromAnnotatedPhoto()
    }

    /// Fotoğraf hazır olduktan sonra ilk seçim adımı.
    private func beginPreAnalysisSelection() {
        if RDConfig.Features.activeAnalysisSectorEnabled {
            selectedAnalysisSector = nil
            showSectorSheet = true
        } else {
            showCanvasSheet = true
        }
    }

    /// Aktif sektör seçildikten sonra canvas seçimine geçer.
    private func continueAfterSectorSelection() {
        guard selectedAnalysisSector != nil else { return }
        showCanvasSheet = true
    }

    /// Canvas seçimi onaylandıktan sonra analizi başlatır.
    private func continueAfterCanvasSelection() {
        runAnalysis()
    }

    private var sectorPickerItems: [AnalysisSectorPickerItem] {
        let onboarding = AnalysisSectorPreferences.onboardingSectors(
            from: OnboardingAnswersService.shared.pendingDraft()
        )
        return AnalysisSectorPreferences.pickerItems(
            onboardingSectors: onboarding,
            lastUsed: AnalysisSectorPreferences.lastUsedSector()
        )
    }

    /// Canvas + opsiyonel firma seçimi tamamlandıktan sonra çağrılır.
    /// async closure oluştur → AnalyzingView'a ilet → o çalıştırır.
    private func runAnalysis() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // AuthService.session authStateChanges'ten geliyor — currentSession'dan daha güvenilir.
        guard let userID = app.auth.session?.user.id else {
            presentAnalysisError(AppErrorMessage.make(AnalysisService.AnalysisError.notAuthenticated))
            return
        }
        let canvases = selectedCanvasesForCurrentTier()
        let localization = app.localizationRequestForNewAnalysis
        if RDGlobalLocalizationBuildGate.isEnabled && localization == nil {
            presentAnalysisError(
                AppErrorMessage.make(
                    rawMessage: RDLocalization.string("analysis.home.view.safety.terminology.profile.is.required.562cf91b", table: .analysis, fallback: "Güvenlik terminolojisi profili gereklidir."),
                    context: RDLocalization.string("analysis.home.view.safety.terminology.required.2302b5ec", table: .analysis, fallback: "Güvenlik terminolojisi gerekli"),
                    fallbackTitle: RDLocalization.string("analysis.home.view.safety.terminology.required.bb477590", table: .analysis, fallback: "Güvenlik terminolojisi gerekli")
                )
            )
            return
        }
        let capturedImages = selectedImages
        let analysisSector: AnalysisSectorID?
        if RDConfig.Features.activeAnalysisSectorEnabled {
            guard let selected = selectedAnalysisSector else { return }
            analysisSector = selected
            AnalysisSectorPreferences.recordLastUsed(selected)
        } else {
            analysisSector = nil
        }

        guard let previewImage = capturedImages.first else {
            return
        }
        pendingJob = AnalysisJob(previewImage: previewImage, presentationMode: .photo, photoCount: capturedImages.count) {
            progress in
            if app.currentTier.isPaid {
                await app.refreshPlanState()
            }
            return try await AnalysisService.shared.runPhotoAnalysis(
                userID: userID,
                images: capturedImages,
                canvases: canvases,
                localization: localization,
                analysisSector: analysisSector,
                companyID: nil,
                onProgress: progress
            )
        }
    }

    private func handleAnalysisError(_ msg: String) {
        let normalized = AppErrorMessage.make(rawMessage: msg, context: RDLocalization.string("analysis.home.view.analiz.tamamlanamadi.7e7d3254", table: .analysis, fallback: "Analiz tamamlanamadı"), fallbackTitle: RDLocalization.string("analysis.home.view.analiz.tamamlanamadi.7e7d3254", table: .analysis, fallback: "Analiz tamamlanamadı"))
        if normalized.category == .quotaExceeded {
            analysisError = nil
            analysisErrorTitle = RDLocalization.string("analysis.home.view.analiz.hatasi.c6ebcb2d", table: .analysis, fallback: "Analiz Hatası")
            markFreeQuotaExhaustedLocally()
            showQuotaPaywall()
            Task { await loadQuotaUsage() }
        } else {
            presentAnalysisError(normalized)
        }
    }

    private func presentAnalysisError(_ error: AppErrorMessage) {
        analysisErrorTitle = error.title
        analysisError = error.fullText
    }

    private func selectedCanvasesForCurrentTier() -> [AnalysisCanvas] {
        let ordered = AnalysisCanvas.all.filter {
            selectedCanvases.contains($0)
                && ($0.id != AnalysisCanvas.legislation.id || app.legislationCanvasEnabled)
        }
        let allowed = ordered.filter { app.currentTier.includes($0.minTier) }
        let nonEmpty = allowed.isEmpty ? [.general] : allowed
        if app.currentTier.isPaid {
            return nonEmpty
        }
        return [nonEmpty.first ?? .general]
    }

    private func normalizeSelectedCanvasesForTier() {
        let allowed = Set(selectedCanvasesForCurrentTier())
        guard selectedCanvases != allowed else { return }
        selectedCanvases = allowed
    }

    private func showQuotaPaywall() {
        restoreCanvasSheetAfterPaywall = false
        paywallPresentation = PaywallPresentation()
    }

    private func showPlainPaywall(restoreCanvasAfterDismiss: Bool = false) {
        restoreCanvasSheetAfterPaywall = restoreCanvasAfterDismiss
        paywallPresentation = PaywallPresentation()
    }

    private func restoreCanvasSheetAfterPaywallIfNeeded() {
        guard restoreCanvasSheetAfterPaywall else { return }
        restoreCanvasSheetAfterPaywall = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard paywallPresentation == nil, !showCanvasSheet else { return }
            showCanvasSheet = true
        }
    }

    private func handlePaywallSubscription() {
        let shouldRestoreCanvas = restoreCanvasSheetAfterPaywall
        restoreCanvasSheetAfterPaywall = false
        paywallPresentation = nil
        Task {
            await app.auth.refreshProfile()
            guard shouldRestoreCanvas else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard paywallPresentation == nil, !showCanvasSheet else { return }
                showCanvasSheet = true
            }
        }
    }

    private func openCameraFromPhotoTray() {
        pendingPhotoTrayDismissDestination = .camera
        showSourceDialog = false
    }

    private func openGalleryFromPhotoTray() {
        pendingPhotoTrayDismissDestination = .gallery
        showSourceDialog = false
    }

    private func presentPendingPhotoTrayDestinationIfNeeded() {
        guard let destination = pendingPhotoTrayDismissDestination else { return }
        pendingPhotoTrayDismissDestination = nil

        // `onDismiss` tepsinin gerçek kapanış animasyonu tamamlandıktan sonra çağrılır.
        // Sabit gecikmeyle ikinci bir sheet açmak hızlı simülatörde çalışsa da gerçek
        // cihazda sunum çakışmasına ve ilk dokunuşun kaybolmasına yol açıyordu.
        DispatchQueue.main.async {
            guard !showSourceDialog else { return }
            switch destination {
            case .camera:
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    presentCameraPicker()
                } else {
                    presentGalleryPicker()
                }
            case .gallery:
                presentGalleryPicker()
            case let .annotation(photoID):
                scheduleAnnotatePresentation(for: photoID)
            case .preAnalysis:
                continueFromPhotoTrayToAnalysis()
            case .paywall:
                showPlainPaywall()
            }
        }
    }

    private func presentCameraPicker() {
        showCameraPicker = false
        pendingPhotoImport = nil
        DispatchQueue.main.async {
            guard !showSourceDialog else { return }
            showCameraPicker = true
        }
    }

    private func presentGalleryPicker() {
        showGalleryPicker = false
        pendingPhotoImport = nil
        DispatchQueue.main.async {
            guard !showSourceDialog else { return }
            showGalleryPicker = true
        }
    }

    private func appendPickedPhotos(
        _ images: [UIImage],
        shouldAnnotate: Bool,
        returnToPhotoTrayAfterAnnotate: Bool
    ) {
        let allowedCount = maxSelectablePhotos - selectedPhotos.count
        guard allowedCount > 0 else {
            if app.currentTier.isPaid {
                analysisErrorTitle = RDLocalization.string("analysis.home.view.fotograf.limiti.1a3eb0a6", table: .analysis, fallback: "Fotoğraf limiti")
                analysisError = RDLocalization.format("analysis.home.view.bu.planda.en.fazla.1.fotograf.analiz.edilebilir.03d1b16d", table: .analysis, fallback: "Bu planda en fazla %1$@ fotoğraf analiz edilebilir.", arguments: [String(describing: maxSelectablePhotos)])
            } else {
                showPlainPaywall()
            }
            return
        }
        let drafts = images.prefix(allowedCount).map { AnalysisPhotoDraft(image: $0) }
        guard !drafts.isEmpty else { return }
        selectedPhotos.append(contentsOf: drafts)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if images.count > allowedCount {
            analysisErrorTitle = RDLocalization.string("analysis.home.view.fotograf.limiti.03ab1131", table: .analysis, fallback: "Fotoğraf limiti")
            analysisError = RDLocalization.format("analysis.home.view.en.fazla.1.fotograf.eklenebilir.fazla.secimler.a.dddd1ee5", table: .analysis, fallback: "En fazla %1$@ fotoğraf eklenebilir. Fazla seçimler alınmadı.", arguments: [String(describing: maxSelectablePhotos)])
        }
        if shouldAnnotate {
            queuePhotoAnnotations(
                for: drafts.map(\.id),
                returnToPhotoTray: returnToPhotoTrayAfterAnnotate
            )
        } else if returnToPhotoTrayAfterAnnotate {
            showSourceDialog = true
        }
    }

    private func startAnnotatingPhoto(_ id: UUID, returnToPhotoTray: Bool = false) {
        guard selectedPhotos.contains(where: { $0.id == id }) else { return }
        queuedAnnotatePhotoIDs = []
        returnToPhotoTrayAfterAnnotation = returnToPhotoTray
        if showSourceDialog {
            pendingPhotoTrayDismissDestination = .annotation(id)
            showSourceDialog = false
        } else {
            scheduleAnnotatePresentation(for: id)
        }
    }

    private func updateAnnotatedPhoto(with image: UIImage) {
        guard let annotatingPhotoID,
              let index = selectedPhotos.firstIndex(where: { $0.id == annotatingPhotoID })
        else { return }
        selectedPhotos[index].image = image
    }

    private func removePhoto(_ id: UUID) {
        selectedPhotos.removeAll { $0.id == id }
        queuedAnnotatePhotoIDs.removeAll { $0 == id }
        if annotatingPhotoID == id {
            annotatingPhotoID = nil
            pendingAnnotateRequestID = nil
            showAnnotate = false
        }
        if selectedPhotos.isEmpty {
            resetEmptyPhotoDraftPresentationState()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func resetEmptyPhotoDraftPresentationState() {
        queuedAnnotatePhotoIDs = []
        annotatingPhotoID = nil
        pendingAnnotateRequestID = nil
        returnToPhotoTrayAfterAnnotation = false
        pendingPhotoTrayDismissDestination = nil
        pendingPhotoImport = nil
        continueAfterAnnotationDismiss = false
        showAnnotate = false
        showCameraPicker = false
        showGalleryPicker = false
    }

    private func movePhoto(_ id: UUID, offset: Int) {
        guard let currentIndex = selectedPhotos.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = currentIndex + offset
        guard selectedPhotos.indices.contains(newIndex) else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            selectedPhotos.swapAt(currentIndex, newIndex)
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func scheduleAnnotatePresentation(for photoID: UUID) {
        let requestID = UUID()
        annotatingPhotoID = photoID
        pendingAnnotateRequestID = requestID
        DispatchQueue.main.async {
            guard pendingAnnotateRequestID == requestID,
                  annotatingPhotoID == photoID,
                  selectedPhotos.contains(where: { $0.id == photoID })
            else { return }
            showAnnotate = true
        }
    }

    private func consumePendingPhotoImportAfterPickerDismissal() {
        guard let pendingPhotoImport else { return }
        self.pendingPhotoImport = nil
        DispatchQueue.main.async {
            appendPickedPhotos(
                pendingPhotoImport.images,
                shouldAnnotate: pendingPhotoImport.shouldAnnotate,
                returnToPhotoTrayAfterAnnotate: pendingPhotoImport.returnToPhotoTrayAfterAnnotate
            )
        }
    }

    private func stageGalleryPhotoImport(_ images: [UIImage]) {
        if !images.isEmpty {
            pendingPhotoImport = PendingPhotoImport(
                images: images,
                shouldAnnotate: true,
                returnToPhotoTrayAfterAnnotate: true
            )
        }
        showGalleryPicker = false
    }

    private func dismissAnnotationAndContinue() {
        pendingAnnotateRequestID = nil
        annotatingPhotoID = nil
        continueAfterAnnotationDismiss = true
        showAnnotate = false
    }

    private func continueAfterAnnotationPresentationDismissal() {
        guard continueAfterAnnotationDismiss else { return }
        continueAfterAnnotationDismiss = false
        DispatchQueue.main.async {
            continueAfterAnnotationStep()
        }
    }

    private func loadRecentItems() async {
        #if DEBUG
        if Self.isUITestMainLaunch {
            recentItems = RecentAnalysis.mock
            return
        }
        #endif
        guard app.auth.session != nil else {
            recentItems = []
            return
        }
        do {
            let rows = try await AnalysisService.shared.listRecent(limit: 30)
            let paths: [UUID: String]
            do {
                paths = try await AnalysisService.shared.firstPhotoPaths(analysisIDs: rows.map(\.id))
            } catch {
                paths = [:]
            }
            recentItems = rows.map { row in
                RecentAnalysis(row: row, photoPath: paths[row.id])
            }
            .prefix(8)
            .map { $0 }
        } catch {
            recentItems = []
        }
    }

    private func loadRecentReports() async {
        #if DEBUG
        if Self.isUITestMainLaunch {
            recentReports = Self.uiTestReports
            return
        }
        #endif
        guard app.auth.session != nil else {
            recentReports = []
            return
        }
        do {
            recentReports = try await AnalysisService.shared.listReports(limit: 5, photoAnalysesOnly: true)
        } catch {
            recentReports = []
        }
    }

    private func loadQuotaUsage() async {
        #if DEBUG
        if Self.isUITestMainLaunch {
            quotaUsage = nil
            return
        }
        #endif
        guard app.auth.session != nil, !app.currentTier.isPaid else {
            quotaUsage = nil
            return
        }
        do {
            let usage = try await AnalysisService.shared.dailyQuotaUsage()
            quotaUsage = usage
            cacheQuotaUsage(usage)
        } catch {
            if let cached = cachedQuotaUsageForCurrentUser() {
                quotaUsage = cached
            } else {
                quotaUsage = nil
            }
        }
    }

    private func loadProfessionalProgress() async {
        guard RDProfessionalProgressLocalizationReview.isAvailable else {
            professionalProgressSummary = nil
            showProfessionalTitlesSheet = false
            return
        }
        #if DEBUG
        if Self.isUITestMainLaunch {
            professionalProgressSummary = Self.uiTestProfessionalProgressSummary
            return
        }
        #endif
        guard app.auth.session != nil, RDConfig.Features.professionalProgressEnabled else {
            professionalProgressSummary = nil
            return
        }
        professionalProgressSummary = await ProfessionalProgressService.shared.fetchSummary()
    }

    private func preparePhotoTrayFixtureIfNeeded() {
        #if DEBUG
        if Self.isUITestPhotoTrayFixture {
            let targetCount = min(maxSelectablePhotos, 2)
            if selectedPhotos.count < targetCount {
                let missingPhotos = (selectedPhotos.count..<targetCount).map { index in
                    AnalysisPhotoDraft(image: Self.uiTestPhotoFixture(seed: index))
                }
                selectedPhotos.append(contentsOf: missingPhotos)
            }
            showSourceDialog = true
        } else if Self.isUITestOpenPhotoTray {
            showSourceDialog = true
        }
        #endif
    }

    #if DEBUG
    private static var isUITestMainLaunch: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_MAIN")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_MAIN"] == "1"
    }

    private static var isUITestPhotoTrayFixture: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_PHOTO_TRAY_WITH_PHOTOS")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_PHOTO_TRAY_WITH_PHOTOS"] == "1"
    }

    private static var isUITestOpenPhotoTray: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_OPEN_PHOTO_TRAY")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_OPEN_PHOTO_TRAY"] == "1"
    }

    private static var isUITestDirectHomePhotoPick: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_DIRECT_HOME_PHOTO_PICK")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_DIRECT_HOME_PHOTO_PICK"] == "1"
    }

    private static var isUITestSimulatedGalleryImport: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_SIMULATED_GALLERY_IMPORT")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_SIMULATED_GALLERY_IMPORT"] == "1"
    }

    private static var isUITestOpenResult: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_OPEN_RESULT")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_OPEN_RESULT"] == "1"
    }

    private static var isUITestOpenAnalyzing: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_OPEN_ANALYZING")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_OPEN_ANALYZING"] == "1"
    }

    private static var isUITestOpenAnalyzingCompletes: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_OPEN_ANALYZING_COMPLETES")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_OPEN_ANALYZING_COMPLETES"] == "1"
    }

    private static var isRealE2EAnalysisLaunch: Bool {
        ProcessInfo.processInfo.environment["RD_E2E_REAL_3_PHOTO_ANALYSIS"] == "1"
            || CommandLine.arguments.contains("RD_E2E_REAL_3_PHOTO_ANALYSIS")
    }

    private static func uiTestPhotoFixture(seed: Int) -> UIImage {
        let size = CGSize(width: 720, height: 960)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            let base = seed == 0 ? UIColor(red: 0.06, green: 0.40, blue: 0.26, alpha: 1) : UIColor(red: 0.10, green: 0.28, blue: 0.58, alpha: 1)
            let accent = seed == 0 ? UIColor(red: 0.91, green: 0.20, blue: 0.46, alpha: 1) : UIColor(red: 0.02, green: 0.77, blue: 0.31, alpha: 1)
            base.setFill()
            context.fill(rect)

            for index in 0..<9 {
                let inset = CGFloat(index * 34)
                let band = CGRect(x: inset - 120, y: CGFloat(index * 92), width: size.width + 220, height: 46)
                accent.withAlphaComponent(index.isMultiple(of: 2) ? 0.72 : 0.42).setFill()
                UIBezierPath(roundedRect: band, cornerRadius: 23).fill()
            }

            UIColor.white.withAlphaComponent(0.88).setStroke()
            let marker = UIBezierPath(ovalIn: CGRect(x: 205, y: 305, width: 310, height: 420))
            marker.lineWidth = 12
            marker.stroke()
        }
    }

    private static func e2eHazardPhotoFixture(seed: Int) -> UIImage {
        if seed == 0, let asset = UIImage(named: "TrialPreviewA") {
            return asset
        }

        let hazards: [(title: String, detail: String, color: UIColor)] = [
            ("KORKULUK YOK", "Yuksekte acik kenar", .systemRed),
            ("BARET YOK", "KKD eksikligi", .systemOrange),
            ("ISLAK ZEMIN", "Kayma ve dusme riski", .systemBlue),
            ("ACIK PANO", "Elektrik tehlikesi", .systemPurple),
            ("DUZENSIZ SAHA", "Malzeme ve kablo daginik", .systemGreen),
        ]
        let item = hazards[max(0, min(seed, hazards.count - 1))]
        let size = CGSize(width: 1024, height: 768)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(red: 0.78, green: 0.76, blue: 0.70, alpha: 1).setFill()
            context.fill(rect)

            UIColor(red: 0.42, green: 0.40, blue: 0.36, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 540, width: size.width, height: 228)).fill()

            UIColor(red: 0.63, green: 0.64, blue: 0.60, alpha: 1).setFill()
            for index in 0..<6 {
                UIBezierPath(rect: CGRect(x: CGFloat(index) * 178 - 40, y: 120, width: 42, height: 420)).fill()
            }

            UIColor(red: 0.16, green: 0.18, blue: 0.20, alpha: 1).setStroke()
            let platform = UIBezierPath()
            platform.move(to: CGPoint(x: 80, y: 350))
            platform.addLine(to: CGPoint(x: 930, y: 350))
            platform.lineWidth = 10
            platform.stroke()

            drawE2EWorker(in: CGRect(x: 430, y: 275, width: 110, height: 250), wearingHelmet: seed != 1)

            switch seed {
            case 0:
                item.color.setStroke()
                let openEdge = UIBezierPath()
                openEdge.move(to: CGPoint(x: 140, y: 310))
                openEdge.addLine(to: CGPoint(x: 880, y: 310))
                openEdge.lineWidth = 12
                openEdge.stroke()
            case 2:
                UIColor.systemCyan.withAlphaComponent(0.72).setFill()
                UIBezierPath(ovalIn: CGRect(x: 210, y: 560, width: 430, height: 70)).fill()
            case 3:
                UIColor.darkGray.setFill()
                UIBezierPath(roundedRect: CGRect(x: 690, y: 245, width: 170, height: 210), cornerRadius: 12).fill()
                UIColor.systemYellow.setStroke()
                let wire = UIBezierPath()
                wire.move(to: CGPoint(x: 725, y: 375))
                wire.addLine(to: CGPoint(x: 835, y: 430))
                wire.lineWidth = 8
                wire.stroke()
            case 4:
                UIColor.brown.setFill()
                for index in 0..<5 {
                    UIBezierPath(rect: CGRect(x: 170 + index * 90, y: 560 + (index % 2) * 36, width: 140, height: 18)).fill()
                }
            default:
                break
            }

            let banner = CGRect(x: 64, y: 58, width: 600, height: 116)
            UIColor.black.withAlphaComponent(0.68).setFill()
            UIBezierPath(roundedRect: banner, cornerRadius: 18).fill()

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 42, weight: .heavy),
                .foregroundColor: UIColor.white
            ]
            let detailAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 26, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.86)
            ]
            item.title.draw(in: CGRect(x: 92, y: 76, width: 550, height: 48), withAttributes: titleAttributes)
            item.detail.draw(in: CGRect(x: 92, y: 124, width: 550, height: 38), withAttributes: detailAttributes)
        }
    }

    private static func drawE2EWorker(in rect: CGRect, wearingHelmet: Bool) {
        UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1).setFill()
        UIBezierPath(ovalIn: CGRect(x: rect.midX - 28, y: rect.minY, width: 56, height: 56)).fill()
        if wearingHelmet {
            UIColor.systemYellow.setFill()
            UIBezierPath(roundedRect: CGRect(x: rect.midX - 38, y: rect.minY - 8, width: 76, height: 28), cornerRadius: 12).fill()
        }

        UIColor.systemYellow.withAlphaComponent(0.84).setFill()
        UIBezierPath(roundedRect: CGRect(x: rect.midX - 36, y: rect.minY + 62, width: 72, height: 92), cornerRadius: 14).fill()
        UIColor.black.setStroke()
        let leftArm = UIBezierPath()
        leftArm.move(to: CGPoint(x: rect.midX - 34, y: rect.minY + 82))
        leftArm.addLine(to: CGPoint(x: rect.midX - 80, y: rect.minY + 130))
        leftArm.lineWidth = 12
        leftArm.stroke()
        let rightArm = UIBezierPath()
        rightArm.move(to: CGPoint(x: rect.midX + 34, y: rect.minY + 82))
        rightArm.addLine(to: CGPoint(x: rect.midX + 78, y: rect.minY + 122))
        rightArm.lineWidth = 12
        rightArm.stroke()

        let leftLeg = UIBezierPath()
        leftLeg.move(to: CGPoint(x: rect.midX - 18, y: rect.minY + 154))
        leftLeg.addLine(to: CGPoint(x: rect.midX - 46, y: rect.maxY))
        leftLeg.lineWidth = 14
        leftLeg.stroke()
        let rightLeg = UIBezierPath()
        rightLeg.move(to: CGPoint(x: rect.midX + 18, y: rect.minY + 154))
        rightLeg.addLine(to: CGPoint(x: rect.midX + 48, y: rect.maxY))
        rightLeg.lineWidth = 14
        rightLeg.stroke()
    }

    private static var uiTestReports: [ReportRow] {
        [
            ReportRow(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000d301")!,
                userID: UUID(uuidString: "00000000-0000-0000-0000-00000000f201")!,
                analysisID: UUID(uuidString: "00000000-0000-0000-0000-00000000a301")!,
                companyID: nil,
                companySnapshot: nil,
                format: "pdf",
                kind: PDFReportKind.standard.rawValue,
                method: "fine_kinney",
                title: RDLocalization.string("analysis.home.view.genel.ui.test.a58b1874", table: .analysis, fallback: "Genel · UI Test"),
                storagePath: "ui-test/report-standard.pdf",
                fileName: "report-standard.pdf",
                mimeType: "application/pdf",
                fileSize: 128_000,
                requestID: "ui-test-report-1",
                supportID: "UI-TEST",
                createdAt: Self.uiTestISODate(minutesAgo: 8)
            ),
            ReportRow(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000d302")!,
                userID: UUID(uuidString: "00000000-0000-0000-0000-00000000f201")!,
                analysisID: UUID(uuidString: "00000000-0000-0000-0000-00000000a302")!,
                companyID: nil,
                companySnapshot: nil,
                format: "xlsx",
                kind: "risk_analysis",
                method: "matrix_5x5",
                title: RDLocalization.string("analysis.home.view.risk.analizi.ui.test.a01f53a7", table: .analysis, fallback: "Risk Analizi · UI Test"),
                storagePath: "ui-test/report-risk.xlsx",
                fileName: "report-risk.xlsx",
                mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                fileSize: 96_000,
                requestID: "ui-test-report-2",
                supportID: "UI-TEST",
                createdAt: Self.uiTestISODate(minutesAgo: 16)
            )
        ]
    }

    private static var uiTestProfessionalProgressSummary: ProfessionalProgressSummary {
        let userID = UUID(uuidString: "00000000-0000-0000-0000-00000000f201")!
        return ProfessionalProgressSummary(
            profile: ProfessionalProgressProfileRow(
                userID: userID,
                totalMDP: 1_065,
                currentTitleKey: ProfessionalProgressTitle.fieldObserver.rawValue,
                totalAnalyses: 8,
                totalReports: 2,
                totalFindings: 14,
                criticalFindings: 1,
                highFindings: 4,
                mediumFindings: 7,
                lowFindings: 2,
                unknownFindings: 0,
                activeDays: 4,
                lastEventAt: Self.uiTestISODate(minutesAgo: 8),
                lastTitleChangeAt: Self.uiTestISODate(minutesAgo: 8)
            ),
            competencies: [
                Self.uiTestCompetency(userID: userID, key: .ppe, findings: 5, reports: 2),
                Self.uiTestCompetency(userID: userID, key: .chemical, findings: 4, reports: 1),
                Self.uiTestCompetency(userID: userID, key: .construction, findings: 3, reports: 1),
                Self.uiTestCompetency(userID: userID, key: .workingAtHeight, findings: 2, reports: 1)
            ],
            badges: [],
            messages: [],
            weeklySummary: ProfessionalProgressWeeklySummary(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000e301")!,
                weekStart: Self.uiTestWeekStart,
                reportsCount: 2,
                analysesCount: 3,
                findingsCount: 8,
                topCompetencyKey: ProfessionalProgressCompetency.ppe.rawValue,
                messageTitle: "Haftalık Takip",
                messageBody: "Bu hafta 2 rapor tamamladın. 💪"
            )
        )
    }

    private static func uiTestCompetency(
        userID: UUID,
        key: ProfessionalProgressCompetency,
        findings: Int,
        reports: Int
    ) -> ProfessionalProgressCompetencyStat {
        ProfessionalProgressCompetencyStat(
            userID: userID,
            competencyKey: key.rawValue,
            analysisCount: max(reports, 1),
            reportCount: reports,
            findingCount: findings,
            criticalCount: key == .ppe ? 1 : 0,
            highCount: max(findings / 2, 0),
            mediumCount: max(findings / 2, 0),
            lowCount: 0,
            unknownCount: 0,
            onboardingSeed: false,
            lastDetectedAt: Self.uiTestISODate(minutesAgo: 10)
        )
    }

    private static var uiTestWeekStart: String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = RDConfig.Quota.businessTimeZone
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: start)
    }

    private static func uiTestISODate(minutesAgo: Int) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(-minutesAgo * 60)))
    }
    #endif

    private func markFreeQuotaExhaustedLocally() {
        guard !app.currentTier.isPaid else { return }
        let usage = DailyQuotaUsage(
            used: AnalysisService.freeDailyLimit,
            limit: AnalysisService.freeDailyLimit
        )
        quotaUsage = usage
        cacheQuotaUsage(usage)
        closeFreeQuotaEntryPointsIfNeeded()
    }

    private func closeFreeQuotaEntryPointsIfNeeded() {
        guard isFreeQuotaExhausted else { return }
        showSourceDialog = false
        showCameraPicker = false
        showGalleryPicker = false
        showCanvasSheet = false
        queuedAnnotatePhotoIDs = []
        returnToPhotoTrayAfterAnnotation = false
        pendingPhotoTrayDismissDestination = nil
        pendingPhotoImport = nil
        continueAfterAnnotationDismiss = false
    }

    private func cacheQuotaUsage(_ usage: DailyQuotaUsage) {
        guard let key = quotaCacheKeyForCurrentUser else { return }
        UserDefaults.standard.set(usage.used, forKey: "\(key).used")
        UserDefaults.standard.set(usage.limit, forKey: "\(key).limit")
    }

    private func cachedQuotaUsageForCurrentUser() -> DailyQuotaUsage? {
        guard let key = quotaCacheKeyForCurrentUser,
              UserDefaults.standard.object(forKey: "\(key).used") != nil,
              UserDefaults.standard.object(forKey: "\(key).limit") != nil
        else { return nil }
        let used = UserDefaults.standard.integer(forKey: "\(key).used")
        let limit = UserDefaults.standard.integer(forKey: "\(key).limit")
        guard limit > 0 else { return nil }
        return DailyQuotaUsage(used: used, limit: limit)
    }

    private var quotaCacheKeyForCurrentUser: String? {
        guard let userID = app.auth.session?.user.id.uuidString else { return nil }
        return "\(freeQuotaCachePrefix).\(userID).\(Self.istanbulDayKey())"
    }

    private static func istanbulDayKey() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = RDConfig.Quota.businessTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func openRecentAnalysis(_ item: RecentAnalysis) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        openAnalysisResult(analysisID: item.id, context: RDLocalization.string("analysis.home.view.analiz.acilamadi.bec78d0c", table: .analysis, fallback: "Analiz açılamadı"))
    }

    private func openAnalysisResult(analysisID: UUID, context: String) {
        guard openingRecentID == nil else { return }
        openingRecentID = analysisID
        Task {
            do {
                let result = try await AnalysisService.shared.result(analysisID: analysisID)
                analysisResult = result
                showResult = true
            } catch {
                presentAnalysisError(AppErrorMessage.make(error, context: context, fallbackTitle: context))
            }
            openingRecentID = nil
        }
    }

    private func openPendingAnalysisResultIfNeeded() {
        guard let analysisID = app.pendingAnalysisResultID,
              pendingJob == nil,
              !showResult,
              openingRecentID == nil else { return }
        app.pendingAnalysisResultID = nil
        openAnalysisResult(analysisID: analysisID, context: RDLocalization.string("analysis.home.view.analiz.sonucu.acilamadi.5e47c59a", table: .analysis, fallback: "Analiz sonucu açılamadı"))
    }

    private func resumeInFlightAnalysisIfNeeded() {
        guard pendingJob == nil,
              !showResult,
              openingRecentID == nil,
              resumingInFlightID == nil,
              app.pendingAnalysisResultID == nil,
              let userID = app.auth.session?.user.id,
              let inFlight = InFlightAnalysisStore.shared.load(for: userID) else {
            return
        }

        if inFlight.kind == "text" {
            InFlightAnalysisStore.shared.clear(analysisID: inFlight.analysisID)
            analysisErrorTitle = RDLocalization.string("analysis.home.view.metin.analizi.kaldirildi.905d5a82", table: .analysis, fallback: "Metin analizi kaldırıldı")
            analysisError = RDLocalization.string("analysis.home.view.metin.analizi.artik.desteklenmiyor.lutfen.fotogr.05e50fcd", table: .analysis, fallback: "Metin analizi artık desteklenmiyor. Lütfen fotoğraf yükleyerek yeni analiz başlatın.")
            return
        }

        resumingInFlightID = inFlight.analysisID
        pendingJob = AnalysisJob(
            previewImage: nil,
            presentationMode: .photo,
            photoCount: inFlight.photoCount
        ) { progress in
            try await AnalysisService.shared.resumeAnalysis(
                analysisID: inFlight.analysisID,
                onProgress: progress
            )
        }
    }

    private func openUITestResultIfNeeded() {
        #if DEBUG
        guard Self.isUITestOpenResult, !didOpenUITestResult else { return }
        didOpenUITestResult = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            openRecentAnalysis(RecentAnalysis.mock[0])
        }
        #endif
    }

    private func openAnalyzingFixtureIfNeeded() {
        #if DEBUG
        guard (Self.isUITestOpenAnalyzing || Self.isUITestOpenAnalyzingCompletes),
              !didOpenUITestAnalyzing,
              pendingJob == nil else { return }
        didOpenUITestAnalyzing = true
        pendingJob = AnalysisJob(
            previewImage: Self.uiTestPhotoFixture(seed: 2),
            presentationMode: .photo,
            photoCount: 3
        ) { progress in
            progress(.preparingInput)
            try await Task.sleep(nanoseconds: 420_000_000)
            progress(.creatingAnalysis)
            try await Task.sleep(nanoseconds: 420_000_000)
            progress(.uploadingPhotos)
            try await Task.sleep(nanoseconds: 420_000_000)
            progress(.submitting)
            try await Task.sleep(nanoseconds: 420_000_000)
            if Self.isUITestOpenAnalyzingCompletes {
                progress(.queued)
                try await Task.sleep(nanoseconds: 420_000_000)
                progress(.analyzing)
                try await Task.sleep(nanoseconds: 420_000_000)
                progress(.finalizingResult)
                try await Task.sleep(nanoseconds: 420_000_000)
                return try await AnalysisService.shared.resumeAnalysis(
                    analysisID: UUID(uuidString: "00000000-0000-0000-0000-00000000c071")!,
                    onProgress: nil
                )
            }
            progress(.retryingNetwork)
            try await Task.sleep(nanoseconds: 3_000_000_000)
            progress(.queued)
            try await Task.sleep(nanoseconds: 620_000_000)
            progress(.analyzing)
            try await Task.sleep(nanoseconds: 30_000_000_000)
            throw AnalysisService.AnalysisError.aiFailed("UI test analiz bekletildi.")
        }
        #endif
    }

    private func openRealE2EAnalysisIfNeeded() {
        #if DEBUG
        guard Self.isRealE2EAnalysisLaunch, !didOpenE2ERealAnalysis, pendingJob == nil else { return }
        guard let userID = app.auth.session?.user.id else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                openRealE2EAnalysisIfNeeded()
            }
            return
        }

        didOpenE2ERealAnalysis = true
        let images = (0..<3).map(Self.e2eHazardPhotoFixture(seed:))
        selectedPhotos = images.map { AnalysisPhotoDraft(image: $0) }
        selectedCanvases = [.general, .ppe, .warningSigns, .workingAtHeight, .electrical]
        selectedAnalysisSector = .construction

        pendingJob = AnalysisJob(
            previewImage: images.first,
            presentationMode: .photo,
            photoCount: images.count
        ) { progress in
            await app.refreshPlanState()
            return try await AnalysisService.shared.runPhotoAnalysis(
                userID: userID,
                images: images,
                canvases: [.general, .ppe, .warningSigns, .workingAtHeight, .electrical],
                analysisSector: .construction,
                companyID: nil,
                title: RDLocalization.format("analysis.home.view.e2e.3.fotograf.storage.1.c8cb48fa", table: .analysis, fallback: "E2E 3 Fotoğraf Storage %1$@", arguments: [String(describing: Self.uiTestISODate(minutesAgo: 0))]),
                onProgress: progress
            )
        }
        #endif
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
                presentAnalysisError(AppErrorMessage.make(
                    error,
                    context: RDLocalization.string("analysis.home.view.rapor.acilamadi.8d6f58ee", table: .analysis, fallback: "Rapor açılamadı"),
                    fallbackTitle: RDLocalization.string("analysis.home.view.rapor.acilamadi.95aed07e", table: .analysis, fallback: "Rapor açılamadı")
                ))
            }
            openingReportID = nil
        }
    }
}

// MARK: - HomeHeader

private struct HomeHeader: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPaywall = false

    private var preferredModalColorScheme: ColorScheme {
        app.themePreference.colorScheme ?? colorScheme
    }

    var body: some View {
        HStack {
            RDHeaderLogoButton(size: 18)
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
            FreeAwarePaywallView(onClose: { showPaywall = false },
                        onSubscribe: {
                            showPaywall = false
                            Task { await app.auth.refreshProfile() }
                        })
            .preferredColorScheme(preferredModalColorScheme)
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
                            .font(.system(size: RDFontScale.size(8.5), weight: .black, design: .rounded))
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
            .rdRowShadow()
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityIdentifier("home.recent_analysis.\(item.title)")
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
                    .font(.system(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                    .foregroundStyle(kindStyle.text)
                    .frame(width: 38, height: 38)
                    .background(kindStyle.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 5) {
                    Text(reportTitle)
                        .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(kindLabel)
                            .font(.system(size: RDFontScale.size(10.5), weight: .bold, design: .rounded))
                            .foregroundStyle(kindStyle.text)
                            .padding(.horizontal, 8)
                            .frame(height: 23)
                            .background(kindStyle.background)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        Text(dateText)
                            .font(.system(size: RDFontScale.size(11), weight: .medium, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: RDFontScale.size(13), weight: .bold, design: .rounded))
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
            .rdRowShadow()
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    private var iconName: String {
        if isExcel { return "tablecells.fill" }
        return isRiskAnalysis ? "tablecells" : "doc.richtext"
    }

    private var isExcel: Bool {
        report.isExcelReport
    }

    private var isRiskAnalysis: Bool {
        report.isRiskAnalysisReport
    }

    private var kindLabel: String {
        if isExcel { return RDLocalization.string("analysis.home.view.excel.tablo.84e74224", table: .analysis, fallback: "Excel tablo") }
        return isRiskAnalysis ? RDLocalization.string("analysis.home.view.risk.analizi.a7a9a6fd", table: .analysis, fallback: "Risk analizi") : RDLocalization.string("analysis.home.view.standart.rapor.e78add8a", table: .analysis, fallback: "Standart rapor")
    }

    private var kindStyle: (text: Color, background: Color) {
        if isExcel {
            return (Color(hex: "#2563EB"), Color(hex: "#EAF1FF"))
        }
        if isRiskAnalysis {
            return (Color.rdGreen, Color.rdGreenSoft)
        }
        return (Color.rdCharcoal, Color.rdFog)
    }

    private var reportTitle: String {
        guard let separatorRange = report.title.range(of: " · ", options: .backwards) else {
            return report.title
        }
        return String(report.title[..<separatorRange.lowerBound])
    }

    private var dateText: String {
        guard let date = report.createdAt.flatMap(Self.parseDate) else { return RDLocalization.string("analysis.home.view.tarih.yok.6cb91bbc", table: .analysis, fallback: "Tarih yok") }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }
}

private struct PhotoMediaTraySheet: View {
    let photos: [AnalysisPhotoDraft]
    let maxPhotoCount: Int
    let visibleSlotCount: Int
    let canAddMore: Bool
    let onCamera: () -> Void
    let onGallery: () -> Void
    let onAnnotate: (UUID) -> Void
    let onRemove: (UUID) -> Void
    let onMove: (UUID, Int) -> Void
    let onLockedSlot: () -> Void
    let onStartAnalysis: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    static func detentHeight(
        photosCount: Int,
        maxPhotoCount: Int,
        visibleSlotCount: Int
    ) -> CGFloat {
        let gridSpacing: CGFloat = 14
        let slotCount = max(visibleSlotCount, min(maxPhotoCount, photosCount + 1))
        let rowCount = max(1, Int(ceil(Double(slotCount) / 3.0)))
        let contentWidth = UIScreen.main.bounds.width - 40
        let availableWidth = contentWidth - (gridSpacing * 2)
        let tileSize = max(88, min(112, floor(availableWidth / 3)))
        let gridHeight = (CGFloat(rowCount) * tileSize) + (CGFloat(max(rowCount - 1, 0)) * gridSpacing) + 6
        let hasLockedSlots = slotCount > maxPhotoCount
        let verticalSpacing = CGFloat(hasLockedSlots ? 4 : 3) * 14
        let upgradePromptHeight: CGFloat = hasLockedSlots ? 38 : 0

        let contentHeight =
            18 + // top padding
            46 + // header
            46 + // source buttons
            gridHeight +
            upgradePromptHeight +
            58 + // primary button
            verticalSpacing +
            20 // bottom padding

        return ceil(min(max(contentHeight + 28, 360), 500))
    }

    private var isDarkMode: Bool { colorScheme == .dark }
    private var trayBackground: Color { isDarkMode ? Color(hex: "#151819") : Color.rdWhite }
    private var trayPrimaryText: Color { isDarkMode ? Color.white : Color.rdOnyx }
    private var traySecondaryText: Color { isDarkMode ? Color.white.opacity(0.64) : Color.rdSlate }
    private var traySurface: Color { isDarkMode ? Color.white.opacity(0.08) : Color.rdFog }
    private var trayTileSurface: Color { isDarkMode ? Color.white.opacity(0.06) : Color.rdWhite }
    private var trayLockedSurface: Color { isDarkMode ? Color.white.opacity(0.07) : Color.rdFog }
    private var trayStroke: Color { isDarkMode ? Color.white.opacity(0.13) : Color.rdLine }
    private var trayIconText: Color { isDarkMode ? Color.white : Color.black }
    private var trayCTA: Color { isDarkMode ? Color.rdGreen : Color.rdOnyx }

    var body: some View {
        VStack(spacing: 14) {
            header

            HStack(spacing: 10) {
                sourceButton(
                    title: RDLocalization.string("analysis.home.view.kamera.0bbfe23e", table: .analysis, fallback: "Kamera"),
                    icon: "camera.fill",
                    accessibilityID: "home.photo_tray.camera",
                    action: onCamera
                )
                sourceButton(
                    title: RDLocalization.string("analysis.home.view.galeri.a1a2ff1c", table: .analysis, fallback: "Galeri"),
                    icon: "photo.on.rectangle.angled",
                    accessibilityID: "home.photo_tray.gallery",
                    action: onGallery
                )
            }
            .disabled(!canAddMore)

            LazyVGrid(columns: gridColumns, alignment: .center, spacing: gridSpacing) {
                ForEach(0..<sheetSlotCount, id: \.self) { index in
                    slot(at: index, tileSize: tileSize)
                        .accessibilityIdentifier("home.photo_slot.\(index + 1)")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            .padding(.bottom, 4)

            if hasLockedSlots {
                multiPhotoUpgradePrompt
            }

            primaryButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(trayBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.photo_tray")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(RDLocalization.string("analysis.home.view.fotograflar.a049e496", table: .analysis, fallback: "Fotoğraflar"))
                    .font(.system(size: RDFontScale.size(23), weight: .bold, design: .rounded))
                    .foregroundStyle(trayPrimaryText)
                Text("\(photos.count)/\(maxPhotoCount)")
                    .rdMono(size: 12, weight: .semibold)
                    .foregroundStyle(traySecondaryText)
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                    .foregroundStyle(traySecondaryText)
                    .frame(width: 36, height: 36)
                    .background(traySurface)
                    .clipShape(Circle())
            }
            .buttonStyle(RDPressableButtonStyle())
            .accessibilityLabel(RDLocalization.string("analysis.home.view.kapat.349873ed", table: .analysis, fallback: "Kapat"))
        }
    }

    private var gridSpacing: CGFloat { 14 }

    private var tileSize: CGFloat {
        let contentWidth = UIScreen.main.bounds.width - 40
        let availableWidth = contentWidth - (gridSpacing * 2)
        return max(88, min(112, floor(availableWidth / 3)))
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(tileSize), spacing: gridSpacing), count: 3)
    }

    private var sheetSlotCount: Int {
        max(visibleSlotCount, min(maxPhotoCount, photos.count + 1))
    }

    private var hasLockedSlots: Bool {
        sheetSlotCount > maxPhotoCount
    }

    @ViewBuilder
    private func slot(at index: Int, tileSize: CGFloat) -> some View {
        if index < photos.count {
            selectedTile(photos[index], index: index, tileSize: tileSize)
        } else if index >= maxPhotoCount {
            lockedTile(index: index, tileSize: tileSize)
        } else {
            emptyTile(index: index, tileSize: tileSize)
        }
    }

    private func sourceButton(
        title: String,
        icon: String,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                Text(title)
                    .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(trayIconText)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(traySurface)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(trayStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityID)
    }

    private func selectedTile(_ draft: AnalysisPhotoDraft, index: Int, tileSize: CGFloat) -> some View {
        ZStack {
            Button {
                onAnnotate(draft.id)
            } label: {
                Image(uiImage: draft.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: tileSize, height: tileSize)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(.plain)

            VStack {
                HStack {
                    Text("\(index + 1)")
                        .rdMono(size: 10, weight: .bold)
                        .foregroundStyle(Color.rdOnyx)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.92))
                        .clipShape(Circle())

                    Spacer(minLength: 0)

                    Button {
                        onRemove(draft.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: RDFontScale.size(10), weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.black.opacity(0.56))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(RDLocalization.string("analysis.home.view.fotografi.sil.caa00980", table: .analysis, fallback: "Fotoğrafı sil"))
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    tileIconButton("chevron.left", disabled: index == 0) {
                        onMove(draft.id, -1)
                    }
                    tileIconButton("pencil.tip.crop.circle", disabled: false) {
                        onAnnotate(draft.id)
                    }
                    tileIconButton("chevron.right", disabled: index >= photos.count - 1) {
                        onMove(draft.id, 1)
                    }
                }
                .padding(4)
                .background(Color.white.opacity(0.90))
                .clipShape(Capsule())
            }
            .padding(7)
        }
        .frame(width: tileSize, height: tileSize)
        .accessibilityIdentifier("home.photo_tile.\(index + 1)")
    }

    private func emptyTile(index: Int, tileSize: CGFloat) -> some View {
        Button(action: onGallery) {
            RoundedRectangle(cornerRadius: 17)
                .fill(trayTileSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 17)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                        .foregroundStyle(traySecondaryText.opacity(isDarkMode ? 0.48 : 0.34))
                )
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: RDFontScale.size(31), weight: .light, design: .rounded))
                        .foregroundStyle(isDarkMode ? Color.white.opacity(0.72) : Color.rdSlate.opacity(0.58))
                )
                .frame(width: tileSize, height: tileSize)
        }
        .buttonStyle(RDPressableButtonStyle())
        .disabled(!canAddMore)
        .accessibilityLabel(RDLocalization.string("analysis.home.view.fotograf.ekle.279a8fb7", table: .analysis, fallback: "Fotoğraf ekle"))
    }

    private func lockedTile(index: Int, tileSize: CGFloat) -> some View {
        Button(action: onLockedSlot) {
            ZStack {
                RoundedRectangle(cornerRadius: 17)
                    .fill(trayLockedSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 17)
                            .stroke(trayStroke, lineWidth: 1)
                    )

                Image(systemName: "lock.fill")
                    .font(.system(size: RDFontScale.size(18), weight: .bold, design: .rounded))
                    .foregroundStyle(trayIconText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: tileSize, height: tileSize)
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityLabel(RDLocalization.format("analysis.home.view.1.slot.kilitli.plus.veya.pro.ile.acilir.55383064", table: .analysis, fallback: "%1$@. slot kilitli. Plus veya Pro ile açılır.", arguments: [String(describing: index + 1)]))
    }

    private var multiPhotoUpgradePrompt: some View {
        Button(action: onLockedSlot) {
            HStack(spacing: 9) {
                Image(systemName: "lock.fill")
                    .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                Text(RDLocalization.string("analysis.home.view.coklu.fotograf.ozelligi.icin.hesabinizi.yukselti.14166947", table: .analysis, fallback: "Çoklu fotoğraf özelliği için hesabınızı yükseltin"))
                    .font(.system(size: RDFontScale.size(12.5), weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: RDFontScale.size(10), weight: .black, design: .rounded))
            }
            .foregroundStyle(Color(hex: "#8A5A00"))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: "#FFF8D7"),
                        Color(hex: "#FFEFC2")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(hex: "#F0C24A"), lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color(hex: "#D9A300").opacity(0.13), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityIdentifier("home.photo_tray.multi_photo_upgrade")
    }

    private func tileIconButton(
        _ icon: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                .foregroundStyle(disabled ? Color.rdSlate.opacity(0.38) : Color.rdOnyx)
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var primaryButton: some View {
        Button {
            if photos.isEmpty {
                onGallery()
            } else {
                onStartAnalysis()
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: photos.isEmpty ? "plus.circle.fill" : "sparkles")
                    .font(.system(size: RDFontScale.size(17), weight: .semibold, design: .rounded))
                Text(
                    photos.isEmpty
                        ? RDLocalization.string(
                            "analysis.photo_tray.add_photo",
                            table: .analysis,
                            fallback: "Fotoğraf ekle"
                        )
                        : RDLocalization.string(
                            "analysis.photo_tray.continue_to_analysis",
                            table: .analysis,
                            fallback: "Analize geç"
                        )
                )
                    .font(.system(size: RDFontScale.size(17), weight: .semibold, design: .rounded))
                    .tracking(0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(photos.isEmpty && !canAddMore ? Color.rdSlate : trayCTA)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(RDPressableButtonStyle())
        .disabled(photos.isEmpty && !canAddMore)
        .accessibilityLabel(
            photos.isEmpty
                ? RDLocalization.string(
                    "analysis.photo_tray.add_photo",
                    table: .analysis,
                    fallback: "Fotoğraf ekle"
                )
                : RDLocalization.string(
                    "analysis.photo_tray.continue_to_analysis",
                    table: .analysis,
                    fallback: "Analize geç"
                )
        )
        .accessibilityIdentifier("home.photo_tray.primary")
    }
}

private extension View {
    func homeCardDepth(colorScheme: ColorScheme, radius: CGFloat = 16, y: CGFloat = 7) -> some View {
        rdCardShadow(
            colorScheme: colorScheme,
            radius: max(radius * 0.34, 3.5),
            x: max(y * 0.80, 4),
            y: y
        )
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
