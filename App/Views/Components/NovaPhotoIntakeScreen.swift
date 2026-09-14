import SwiftUI
import PhotosUI

/// The first thing the expert sees in the photo flow: the picture area and one
/// green control, the same shape as the home card. Everything after this runs
/// in popups.
struct NovaPhotoIntakeScreen: View {
    @Binding var images: [UIImage]
    var maximum = 3
    let onStart: () -> Void
    let onBack: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var choosing = false
    @State private var camera = false
    @State private var gallery: [PhotosPickerItem] = []
    @State private var galleryOpen = false
    @State private var preview: NovaPreviewImage?
    @State private var notice: String?

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        NovaBackButton { onBack() }
                        NovaText(text: RDLocalization.string("localizable.nova.intake.title", table: .localizable, fallback: "Fotoğraf Analizi"), style: .screenTitle)
                        Spacer(minLength: 0)
                    }
                    NovaHelpHint(text: RDLocalization.string("localizable.nova.photo.intake.hint", table: .localizable,
                        fallback: "En fazla üç fotoğraf. Firma, sektör ve odak seçimini analizi başlatırken soracağız."))
                    if images.isEmpty { dropZone } else { grid }
                    NovaButton(label: RDLocalization.string("localizable.nova.intake.start", table: .localizable, fallback: "Analizi başlat"),
                        symbol: "sparkles", isEnabled: !images.isEmpty) { onStart() }
                        .accessibilityIdentifier("photo.intake.start")
                    if images.isEmpty {
                        NovaText(text: RDLocalization.string("localizable.nova.photo.intake.required", table: .localizable,
                            fallback: "Başlatmak için en az bir fotoğraf ekleyin."), style: .metaQuiet)
                    }
                }.padding(20).padding(.bottom, novaTabBarInset)
            }
        }
        .confirmationDialog(RDLocalization.string("localizable.nova.photo.intake.source", table: .localizable, fallback: "Fotoğrafı nereden ekleyelim?"),
            isPresented: $choosing, titleVisibility: .visible) {
            Button(RDLocalization.string("localizable.nova.photo.intake.camera", table: .localizable, fallback: "Kamera")) { camera = true }
            Button(RDLocalization.string("localizable.nova.photo.intake.gallery", table: .localizable, fallback: "Galeri")) { galleryOpen = true }
            Button(RDLocalization.string("localizable.nova.photo.intake.cancel", table: .localizable, fallback: "Vazgeç"), role: .cancel) { }
        }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { image in
                if let image { add([image]) }
                camera = false
            }.ignoresSafeArea()
        }
        .photosPicker(isPresented: $galleryOpen, selection: $gallery,
                      maxSelectionCount: max(1, maximum - images.count), matching: .images)
        .onChange(of: gallery) { _ in Task { await loadGallery() } }
        .fullScreenCover(item: $preview) { item in
            NovaPopup { NovaImageViewer(image: item.image) }
        }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button(RDLocalization.string("localizable.nova.bridge.alert.ok", table: .localizable, fallback: "Tamam")) { notice = nil }
        }
    }

    private var dropZone: some View {
        Button { choosing = true } label: {
            VStack(spacing: 9) {
                NovaIcon(symbol: "cameraLarge", size: 24)
                    .frame(width: 48, height: 48)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(NovaColorToken.accent.color(in: scheme)).offset(x: 5, y: 5)
                    }
                NovaText(text: RDLocalization.string("localizable.nova.expert.shell.fotograf.cek.veya.galeriden.sec.bea08bcc", table: .localizable, fallback: "Fotoğraf çek veya galeriden seç"),
                    style: .meta, color: NovaColorToken.textTertiary.color(in: scheme))
            }.frame(maxWidth: .infinity, minHeight: 168)
                .background { NovaPhotoBackdrop() }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(NovaColorToken.borderStrong.color(in: scheme), style: StrokeStyle(lineWidth: 1.6, dash: [5, 4])))
        }.buttonStyle(.plain).accessibilityIdentifier("photo.intake.add")
            .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.photo.intake.add", table: .localizable, fallback: "Fotoğraf ekle")))
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    thumbnail(image, index: index)
                }
                if images.count < maximum {
                    Button { choosing = true } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                            NovaText(text: RDLocalization.string("localizable.nova.photo.intake.add", table: .localizable, fallback: "Fotoğraf ekle"),
                                style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
                        }.foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                            .frame(maxWidth: .infinity).frame(height: 104)
                            .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(NovaColorToken.borderStrong.color(in: scheme), style: StrokeStyle(lineWidth: 1.4, dash: [5, 4])))
                    }.buttonStyle(.plain).accessibilityIdentifier("photo.intake.add")
                }
            }
            NovaText(text: String(format: RDLocalization.string("localizable.nova.photo.intake.count", table: .localizable,
                fallback: "%1$d / %2$d fotoğraf"), images.count, maximum), style: .metaQuiet)
        }
    }

    private func thumbnail(_ image: UIImage, index: Int) -> some View {
        Button { preview = .init(image: image) } label: {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(maxWidth: .infinity).frame(height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .topTrailing) {
                    Button { remove(index) } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NovaColorToken.onInverse.color(in: scheme))
                            .frame(width: 28, height: 28)
                            .background(NovaColorToken.inverse.color(in: scheme).opacity(0.75), in: Circle())
                    }.buttonStyle(.plain).padding(5)
                        .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.photo.intake.remove", table: .localizable, fallback: "Fotoğrafı çıkar")))
                        .accessibilityIdentifier("photo.intake.remove.\(index)")
                }
        }.buttonStyle(.plain).accessibilityIdentifier("photo.intake.thumbnail.\(index)")
    }

    private func add(_ values: [UIImage]) {
        let room = maximum - images.count
        guard room > 0 else {
            notice = String(format: RDLocalization.string("localizable.nova.photo.intake.full", table: .localizable,
                fallback: "En fazla %d fotoğraf eklenebilir."), maximum)
            return
        }
        images.append(contentsOf: values.prefix(room))
        if values.count > room {
            notice = String(format: RDLocalization.string("localizable.nova.photo.intake.full", table: .localizable,
                fallback: "En fazla %d fotoğraf eklenebilir."), maximum)
        }
    }
    private func remove(_ index: Int) {
        guard images.indices.contains(index) else { return }
        images.remove(at: index)
    }

    private func loadGallery() async {
        let items = gallery
        gallery = []
        guard !items.isEmpty else { return }
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        guard !loaded.isEmpty else {
            notice = RDLocalization.string("localizable.nova.bridge.photo.unreadable", table: .localizable,
                fallback: "Seçilen fotoğraflar okunamadı. Tekrar deneyin.")
            return
        }
        add(loaded)
    }
}

/// A picture the expert asked to see full size.
struct NovaPreviewImage: Identifiable, Equatable {
    let id = UUID()
    let image: UIImage
    static func == (lhs: NovaPreviewImage, rhs: NovaPreviewImage) -> Bool { lhs.id == rhs.id }
}

struct NovaImageViewer: View {
    let image: UIImage
    var caption: String?
    var body: some View {
        VStack(spacing: 10) {
            Image(uiImage: image).resizable().scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .accessibilityLabel(Text(verbatim: caption ?? RDLocalization.string("localizable.nova.photo.viewer", table: .localizable, fallback: "Analiz fotoğrafı")))
            if let caption { NovaText(text: caption, style: .metaQuiet) }
        }.padding(20).novaPopupContentSize()
    }
}
