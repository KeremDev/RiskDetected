import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppState

    @State private var mode: HomeMode = .photo
    @State private var text: String = ""
    @State private var selectedCanvas: AnalysisCanvas = .general
    @State private var showCanvasSheet = false
    @State private var showAnnotate = false
    @State private var showAnalyzing = false
    @State private var showResult = false

    // Foto akışı state
    @State private var showSourceDialog = false
    @State private var showCameraPicker = false
    @State private var showGalleryPicker = false
    @State private var selectedImage: UIImage? = nil

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
                    greetingRow
                        .padding(.bottom, 16)

                    modeSegment
                        .padding(.bottom, 14)

                    if mode == .photo {
                        photoUploadCard
                    } else {
                        textInputArea
                    }

                    RDButton(title: "Taramayı Başlat", style: .detect, icon: "sparkles") {
                        startAnalysisFlow()
                    }
                    .frame(height: 56)
                    .padding(.top, 14)
                    .opacity(canStartAnalysis ? 1 : 0.5)
                    .disabled(!canStartAnalysis)

                    recentSection
                        .padding(.top, 28)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 110) // tab bar clearance
            }
        }
        .background(Color.rdPaper)
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
                selected: $selectedCanvas,
                isUserPro: app.isPro,
                onConfirm: {
                    showCanvasSheet = false
                    // Sheet kapanması bittikten sonra analizi başlat
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        runAnalysis()
                    }
                },
                onUpgradeRequested: { /* TODO: PaywallView */ }
            )
            .presentationDetents([.fraction(0.55), .large])
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
                onAnalyze: { _, _ in
                    showAnnotate = false
                }
            )
        }
        .fullScreenCover(isPresented: $showAnalyzing) {
            AnalyzingView(onComplete: {
                showAnalyzing = false
                // Sheet kapanır kapanmaz açılmaya çalışırsa transition'ları kaybeder; küçük bir gecikme ekle.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showResult = true
                }
            })
        }
        .fullScreenCover(isPresented: $showResult) {
            ResultView(onClose: { showResult = false })
                .environmentObject(app)
        }
    }

    // MARK: - Subviews

    private var greetingRow: some View {
        HStack {
            HStack(spacing: 6) {
                Circle().fill(Color.rdGreen).frame(width: 6, height: 6)
                Text("Saha modu aktif")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .foregroundStyle(Color.rdGreenDark)
            .background(Color.rdGreenSoft)
            .clipShape(Capsule())

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .medium))
                Text(currentDateLabel)
                    .rdMono(size: 12, weight: .medium)
            }
            .foregroundStyle(Color.rdSlate)
        }
    }

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
                } else {
                    ZStack {
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.rdGreenSoft)
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(Color.rdGreenDark)
                            }
                            .frame(width: 56, height: 56)

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
                                .foregroundStyle(Color.rdSlate)
                                .padding(.bottom, 14)
                        }
                    }
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.rdWhite)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                    .foregroundStyle(Color.rdLine)
                            )
                    )
                }
            }
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    private var textInputArea: some View {
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

            ForEach(RecentAnalysis.mock) { item in
                RecentAnalysisCard(item: item) { /* navigate to result */ }
            }
        }
    }

    // MARK: - Helpers

    private var currentDateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM · EEEE"
        return formatter.string(from: Date())
    }

    private var canStartAnalysis: Bool {
        switch mode {
        case .photo: return selectedImage != nil
        case .text:  return text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
        }
    }

    /// "Taramayı Başlat" basıldığında: önce AI Canvas seçimi için bottom sheet aç.
    private func startAnalysisFlow() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showCanvasSheet = true
    }

    /// Canvas seçildikten sonra çağrılır → asıl analiz/yükleme akışını başlatır.
    private func runAnalysis() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showAnalyzing = true
    }
}

// MARK: - HomeHeader

private struct HomeHeader: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack {
            RDLogo(size: 18)
            Spacer()
            HStack(spacing: 8) {
                if app.isPro { RDProBadge(small: true) }
                RDAvatar(
                    initials: app.profile?.displayInitials ?? "—",
                    size: 36,
                    pro: app.isPro
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

// MARK: - RecentAnalysisCard

struct RecentAnalysisCard: View {
    let item: RecentAnalysis
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RDPlaceholderPhoto()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.rdBlack)
                        .lineLimit(1)
                    Text(item.meta)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.rdSlate)
                        .lineLimit(1)

                    FlowLayout(spacing: 4, lineSpacing: 4) {
                        ForEach(item.findings) { finding in
                            RDChip(level: finding.level, label: finding.title)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing) {
                    Text("\(item.count) bulgu")
                        .rdMono(size: 11, weight: .semibold)
                        .foregroundStyle(Color.rdSlate)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.rdSlate)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.rdWhite)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.rdLine, lineWidth: 1)
                    )
            )
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
