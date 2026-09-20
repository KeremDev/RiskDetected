import SwiftUI
import PhotosUI
import CryptoKit

/// The hand-entered record, asked one step at a time. Every step is revisitable,
/// a finished step carries a green tick, and the bar counts exactly the steps
/// that are finished — never a step that was merely opened.
struct NovaManualNonconformityScreen: View {
    let companies: [NovaAnalysisCompanyOption]
    /// The workplaces of one company, fetched when it is chosen.
    let workplaces: (UUID) async throws -> [NovaNonconformityWorkplace]
    let fileClient: NovaFileLibraryClient
    let save: (NovaManualDraft) async -> String?
    let onBack: () -> Void
    var isImprovementAllowed = true
    @Environment(\.colorScheme) private var scheme
    @State private var draft = NovaManualDraft()
    // The picture is what the expert has in hand when they open this form, so
    // its step starts open.
    @State private var open: NovaManualStep? = .photo
    @State private var places: [NovaNonconformityWorkplace] = []
    @State private var loadingPlaces = false
    @State private var saving = false
    @State private var error: String?
    @State private var photos: [UIImage] = []
    @State private var choosing = false
    @State private var camera = false
    @State private var galleryOpen = false
    @State private var gallery: [PhotosPickerItem] = []
    @State private var preview: NovaPreviewImage?

    var body: some View {
        NovaPageSurface(onEdgeBack: saving ? nil : onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    progress
                    ForEach(NovaManualStep.allCases) { step in
                        accordion(step)
                    }
                    if let error {
                        NovaCard(padding: 14) {
                            NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
                        }
                    }
                    saveButton
                }.padding(20).padding(.bottom, novaTabBarInset)
            }
        }

        .confirmationDialog(RDLocalization.string("localizable.nova.photo.intake.source", table: .localizable, fallback: "Fotoğrafı nereden ekleyelim?"),
            isPresented: $choosing, titleVisibility: .visible) {
            Button(RDLocalization.string("localizable.nova.photo.intake.camera", table: .localizable, fallback: "Kamera")) { camera = true }
            Button(RDLocalization.string("localizable.nova.photo.intake.gallery", table: .localizable, fallback: "Galeri")) { galleryOpen = true }
            Button(RDLocalization.string("localizable.nova.photo.intake.cancel", table: .localizable, fallback: "Vazgeç"), role: .cancel) { }
        }
        .novaFullScreenCover(isPresented: $camera) {
            CameraPicker { image in
                if let image { photos.append(image); draft.photoCount = photos.count }
                camera = false
            }.ignoresSafeArea()
        }
        .photosPicker(isPresented: $galleryOpen, selection: $gallery, maxSelectionCount: 3, matching: .images)
        .onChange(of: gallery) { _ in Task { await loadGallery() } }
        .novaPopupCover(item: $preview) { item in
            NovaPopup { NovaImageViewer(image: item.image) }
        }
    }

    private func loadGallery() async {
        let items = gallery
        gallery = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                photos.append(image)
            }
        }
        draft.photoCount = photos.count
    }

    private var header: some View {
        HStack(spacing: 10) {
            NovaBackButton(isEnabled: !saving) { onBack() }
            VStack(alignment: .leading, spacing: 2) {
                NovaText(text: RDLocalization.string("localizable.nova.manual.title", table: .localizable, fallback: "Elle Uygunsuzluk"), style: .screenTitle)
                    .lineLimit(1).minimumScaleFactor(0.7)
                NovaText(text: RDLocalization.string("localizable.nova.manual.subtitle", table: .localizable,
                    fallback: "Yapay zekâ kullanılmaz; bilgileri siz girersiniz."), style: .metaQuiet)
            }
            Spacer(minLength: 0)
        }
    }

    private var progress: some View {
        NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    NovaText(text: String(format: RDLocalization.string("localizable.nova.manual.progress", table: .localizable,
                        fallback: "%1$d/%2$d başlık tamamlandı"), draft.completedCount, NovaManualStep.allCases.count), style: .label)
                    Spacer(minLength: 0)
                    if draft.canSave {
                        NovaStatusPill(label: RDLocalization.string("localizable.nova.manual.ready", table: .localizable, fallback: "Kaydedilebilir"), status: .success)
                    } else {
                        NovaStatusPill(label: RDLocalization.string("localizable.nova.manual.pending", table: .localizable, fallback: "Zorunlu alan eksik"), status: .warning)
                    }
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NovaColorToken.borderMuted.color(in: scheme))
                        Capsule().fill(NovaColorToken.accent.color(in: scheme))
                            .frame(width: max(0, proxy.size.width * draft.progress))
                    }
                }.frame(height: 6)
                NovaText(text: RDLocalization.string("localizable.nova.manual.progress.hint", table: .localizable,
                    fallback: "Fotoğraf, mevzuat, sorumlu ve skorlama isteğe bağlıdır; girildiğinde tamamlandı sayılır."), style: .metaQuiet)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .combine)
            .accessibilityIdentifier("manual.progress")
    }

    @ViewBuilder private func accordion(_ step: NovaManualStep) -> some View {
        NovaCompanyAccordion(title: title(step), symbol: symbol(step),
            state: draft.isComplete(step) ? .complete : .missing,
            identifier: "manual.step.\(step.rawValue)",
            expanded: Binding(get: { open == step }, set: { open = $0 ? step : nil })) {
            VStack(alignment: .leading, spacing: 10) {
                switch step {
                case .photo: photoStep
                case .company: companyStep
                case .hazard: hazardStep
                case .scoring: NovaRiskScoreEditor(score: $draft.score)
                case .legislation:
                    area(RDLocalization.string("localizable.nova.manual.legislation.hint", table: .localizable,
                        fallback: "İlgili madde, yönetmelik veya standart"), $draft.legislation, id: "legislation")
                case .responsible:
                    field(RDLocalization.string("localizable.nova.manual.responsible.hint", table: .localizable,
                        fallback: "Firmadaki sorumlu kişi"), $draft.responsible, id: "responsible")
                    NovaText(text: RDLocalization.string("localizable.nova.manual.responsible.note", table: .localizable,
                        fallback: "Bu kişi bir uygulama kullanıcısı değildir; yalnız kayıtta görünür."), style: .metaQuiet)
                }
                advance(step)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A finished step offers the next unfinished one instead of leaving the
    /// expert to find it.
    @ViewBuilder private func advance(_ step: NovaManualStep) -> some View {
        if draft.isComplete(step), let next = draft.nextIncomplete(after: step) {
            NovaButton(label: String(format: RDLocalization.string("localizable.nova.manual.next", table: .localizable,
                fallback: "Sıradaki: %@"), title(next)), symbol: "chevron.down", variant: .surface) { open = next }
                .accessibilityIdentifier("manual.next.\(step.rawValue)")
        }
    }

    /// The site photo is asked for first because that is how the expert works.
    /// It is not sent to the record yet, and the step says so rather than
    /// implying a picture was filed.
    @ViewBuilder private var photoStep: some View {
        if photos.isEmpty {
            Button { choosing = true } label: {
                VStack(spacing: 7) {
                    NovaIcon(symbol: "camera", size: 22)
                        .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                    NovaText(text: RDLocalization.string("localizable.nova.expert.shell.fotograf.cek.veya.galeriden.sec.bea08bcc", table: .localizable, fallback: "Fotoğraf çek veya galeriden seç"),
                        style: .meta, color: NovaColorToken.textTertiary.color(in: scheme))
                }.frame(maxWidth: .infinity, minHeight: 104)
                    .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(NovaColorToken.borderStrong.color(in: scheme), style: StrokeStyle(lineWidth: 1.4, dash: [5, 4])))
            }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("manual.photo.add")
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, image in
                    Button { preview = .init(image: image) } label: {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(maxWidth: .infinity).frame(height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    photos.remove(at: index); draft.photoCount = photos.count
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(NovaColorToken.text.color(in: scheme))
                                        .frame(width: 26, height: 26)
                                }.buttonStyle(NovaRowPressStyle()).padding(4)
                                    .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.photo.intake.remove", table: .localizable, fallback: "Fotoğrafı çıkar")))
                            }
                    }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("manual.photo.thumbnail.\(index)")
                }
                if photos.count < 3 {
                    Button { choosing = true } label: {
                        Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                            .frame(maxWidth: .infinity).frame(height: 92)
                    }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("manual.photo.add")
                        .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.photo.intake.add", table: .localizable, fallback: "Fotoğraf ekle")))
                }
            }
        }
    }

    @ViewBuilder private var companyStep: some View {
        if companies.isEmpty {
            NovaText(text: RDLocalization.string("localizable.nova.manual.no.company", table: .localizable,
                fallback: "Bu hesapta kayıt açılacak firma yok."), style: .metaQuiet)
        } else {
            ForEach(companies) { company in
                Button { Task { await choose(company) } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: draft.companyID == company.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(draft.companyID == company.id ? NovaColorToken.accentInk.color(in: scheme)
                                                                           : NovaColorToken.borderStrong.color(in: scheme))
                        VStack(alignment: .leading, spacing: 1) {
                            NovaText(text: company.name, style: .cardTitle)
                            if !company.detail.isEmpty { NovaText(text: company.detail, style: .micro,
                                color: NovaColorToken.textTertiary.color(in: scheme)) }
                        }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(NovaRowPressStyle())
                    .accessibilityIdentifier("manual.company.\(company.id.uuidString.lowercased())")
            }
        }
        if draft.companyID != nil {
            Divider()
            NovaText(text: RDLocalization.string("localizable.nova.manual.workplace.optional", table: .localizable,
                fallback: "İşyeri / departman · isteğe bağlı"), style: .label,
                color: NovaColorToken.textTertiary.color(in: scheme))
            if loadingPlaces {
                NovaText(text: RDLocalization.string("localizable.nova.manual.workplace.loading", table: .localizable,
                    fallback: "İşyerleri yükleniyor…"), style: .metaQuiet)
            } else if places.isEmpty {
                NovaText(text: RDLocalization.string("localizable.nova.bridge.no.workplace", table: .localizable,
                    fallback: "Bu firmada kayıt açılacak bir işyeri yok."), style: .metaQuiet)
            } else if places.count == 1 {
                // One workplace is not a choice; it is already selected.
                NovaText(text: String(format: RDLocalization.string("localizable.nova.manual.workplace.used", table: .localizable,
                    fallback: "Kayıt %@ işyerine açılacak."), places[0].name), style: .micro,
                    color: NovaColorToken.textTertiary.color(in: scheme))
            } else {
                ForEach(places) { place in
                    Button { draft.workplaceID = place.id } label: {
                        HStack(spacing: 8) {
                            Image(systemName: draft.workplaceID == place.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(draft.workplaceID == place.id ? NovaColorToken.accentInk.color(in: scheme)
                                                                               : NovaColorToken.borderStrong.color(in: scheme))
                            NovaText(text: place.name)
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(NovaRowPressStyle())
                        .accessibilityIdentifier("manual.workplace.\(place.id.uuidString.lowercased())")
                }
                // The record has to land on a workplace, so the first one is
                // taken when the expert does not choose. The screen names it
                // instead of filing the record somewhere unseen.
                if let chosen = places.first(where: { $0.id == draft.workplaceID }) {
                    NovaText(text: String(format: RDLocalization.string("localizable.nova.manual.workplace.used", table: .localizable,
                        fallback: "Kayıt %@ işyerine açılacak."), chosen.name), style: .micro,
                        color: NovaColorToken.textTertiary.color(in: scheme))
                }
            }
        }
    }

    private func choose(_ company: NovaAnalysisCompanyOption) async {
        draft.companyID = company.id
        draft.workplaceID = nil
        places = []
        loadingPlaces = true
        do { places = try await workplaces(company.id) }
        catch { places = [] }
        loadingPlaces = false
        draft.workplaceID = places.first?.id
    }

    @ViewBuilder private var hazardStep: some View {
        field(RDLocalization.string("localizable.nova.manual.hazard.title", table: .localizable, fallback: "Tehlike başlığı"), $draft.title, id: "title")
        area(RDLocalization.string("localizable.nova.manual.hazard.description", table: .localizable, fallback: "Açıklama"), $draft.hazardDescription, id: "description")
        area(RDLocalization.string("localizable.nova.manual.hazard.measure", table: .localizable, fallback: "Önlem"), $draft.controlMeasure, id: "measure")
        VStack(alignment: .leading, spacing: 4) {
            NovaText(text: RDLocalization.string("localizable.nova.nonconformity.field.severity", table: .localizable, fallback: "Önem derecesi"), style: .label,
                color: NovaColorToken.textTertiary.color(in: scheme))
            Picker("", selection: $draft.severity) {
                ForEach(NovaNonconformitySeverity.allCases) { value in
                    Text(verbatim: NovaNonconformityWords.severity(value)).tag(value)
                }
            }.pickerStyle(.segmented).accessibilityIdentifier("manual.field.severity")
        }
        if isImprovementAllowed {
            VStack(alignment: .leading, spacing: 4) {
                NovaText(text: RDLocalization.string("localizable.nova.analysis.file.kind", table: .localizable, fallback: "Kayıt türü"), style: .label,
                    color: NovaColorToken.textTertiary.color(in: scheme))
                Picker("", selection: $draft.recordKind) {
                    ForEach(NovaNonconformityRecordKind.allCases) { value in
                        Text(verbatim: NovaNonconformityWords.recordKind(value)).tag(value)
                    }
                }.pickerStyle(.segmented).accessibilityIdentifier("manual.field.kind")
            }
        }
    }

    private func field(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextField(label, text: text).font(NovaFont.font(.body))
                .frame(minHeight: 36).accessibilityIdentifier("manual.field.\(id)")
        }
    }
    private func area(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextEditor(text: text).font(NovaFont.font(.body))
                .frame(minHeight: 72).scrollContentBackground(.hidden)
                .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("manual.field.\(id)")
        }
    }

    private var saveButton: some View {
        NovaButton(label: RDLocalization.string("localizable.nova.manual.save", table: .localizable, fallback: "Kaydı aç"),
            symbol: "checkmark", isEnabled: draft.canSave && !saving, isLoading: saving) {
            Task {
                saving = true; error = nil
                if let company = draft.companyID, !photos.isEmpty {
                    let uploaded = await uploadEvidence(company: company)
                    guard !uploaded.isEmpty else {
                        error = RDLocalization.string("localizable.nova.manual.photo.upload.failed", table: .localizable,
                            fallback: "Fotoğraflar yüklenemedi. Bağlantıyı kontrol edip tekrar deneyin.")
                        saving = false
                        return
                    }
                    draft.evidenceAssetIDs = uploaded
                }
                error = await save(draft)
                saving = false
            }
        }.accessibilityIdentifier("manual.save")
    }

    /// JPEG-encodes and files each photo before the record itself is opened,
    /// so the server only ever sees clean, already-owned assets to attach —
    /// the same rule every other module's evidence attach follows.
    private func uploadEvidence(company: UUID) async -> [UUID] {
        var ids: [UUID] = []
        for image in photos {
            guard let data = image.jpegData(compressionQuality: 0.85) else { continue }
            var fileDraft = NovaFileDraft()
            fileDraft.title = RDLocalization.string("localizable.nova.manual.photo.evidence.title", table: .localizable,
                fallback: "Uygunsuzluk fotoğrafı")
            fileDraft.category = "nonconformity_evidence"
            fileDraft.fileName = "uygunsuzluk-\(UUID().uuidString.prefix(8)).jpg"
            fileDraft.fileExtension = "jpg"
            fileDraft.bytes = data.count
            fileDraft.sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if let entry = try? await fileClient.file(company, fileDraft, data), let id = entry.assetID {
                ids.append(id)
            }
        }
        return ids
    }

    private func title(_ step: NovaManualStep) -> String {
        switch step {
        case .photo: return RDLocalization.string("localizable.nova.manual.step.photo", table: .localizable, fallback: "Fotoğraf")
        case .company: return RDLocalization.string("localizable.nova.manual.step.firma", table: .localizable, fallback: "Firma")
        case .hazard: return RDLocalization.string("localizable.nova.manual.step.hazard", table: .localizable, fallback: "Uygunsuzluk")
        case .scoring: return RDLocalization.string("localizable.nova.manual.step.scoring", table: .localizable, fallback: "Risk metodu ve skorlama")
        case .legislation: return RDLocalization.string("localizable.nova.manual.step.legislation", table: .localizable, fallback: "Mevzuat bilgisi")
        case .responsible: return RDLocalization.string("localizable.nova.manual.step.responsible", table: .localizable, fallback: "Firma sorumlusu")
        }
    }
    private func symbol(_ step: NovaManualStep) -> String {
        switch step {
        case .photo: return "camera"
        case .company: return "building.2"
        case .hazard: return "exclamationmark.triangle"
        case .scoring: return "chart.bar"
        case .legislation: return "doc.text"
        case .responsible: return "person.crop.rectangle"
        }
    }
}
