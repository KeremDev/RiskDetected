import SwiftUI
import UIKit
import PDFKit
import CoreText
import UniformTypeIdentifiers

struct NovaEducationPDFFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor enum NovaEducationCertificatePDF {
    static let rendererVersion = 3
    private struct Block { let text: String; var size: CGFloat = 10; var bold = false; var space: CGFloat = 6; var height: CGFloat? }
    private struct Placed { let block: Block; let y: CGFloat; let height: CGFloat }
    static func data(_ snapshot: NovaEducationCertificate.Snapshot) -> Data {
        let width: CGFloat = 527; let margin: CGFloat = 34
        let s = snapshot.scope
        let logo = snapshot.logo_png_base64.flatMap { Data(base64Encoded: $0) }.flatMap { UIImage(data: $0) }
        func font(_ b: Block) -> UIFont {
            UIFont(name: b.bold ? "PlusJakartaSans-Bold" : "PlusJakartaSans-Regular", size: b.size) ?? (b.bold ? .boldSystemFont(ofSize: b.size) : .systemFont(ofSize: b.size))
        }
        func attrs(_ b: Block) -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 2
            return [.font: font(b), .foregroundColor: b.bold ? UIColor(red: 0.08, green: 0.15, blue: 0.25, alpha: 1) : UIColor.black, .paragraphStyle: paragraph]
        }
        func signature(_ text: String) -> Block {
            let base = Block(text: text)
            let height = ceil((text as NSString).boundingRect(with: CGSize(width: width, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs(base), context: nil).height)
            return .init(text: text, height: height + 64)
        }
        let times = Dictionary(grouping: s.lessons) { NovaEducationClock.day(NovaEducationClock.date($0.starts_at) ?? .distantPast) }.sorted { $0.key < $1.key }.map { _, lessons -> String in
            let sorted = lessons.sorted { $0.starts_at < $1.starts_at }
            guard let first = sorted.first, let last = sorted.last,
                  let start = NovaEducationClock.date(first.starts_at), let endStart = NovaEducationClock.date(last.starts_at) else { return "" }
            let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.timeZone = NovaEducationClock.calendar.timeZone; f.dateFormat = "dd.MM.yyyy HH:mm"
            let startText = f.string(from: start); f.dateFormat = "HH:mm"
            return startText + "–" + f.string(from: endStart.addingTimeInterval(Double(last.instruction_minutes + last.break_minutes) * 60))
        }
        let methods = Set(s.topics.map(\.method))
        let cycle = NovaEducationScope.cycles.first { $0.0 == s.cycle }?.1 ?? s.cycle
        var front: [Block] = [
            .init(text: s.legal_name, size: 15, bold: true, space: 14),
            .init(text: snapshot.is_draft ? "TASLAK · " + snapshot.title : snapshot.title, size: 21, bold: true, space: 18),
            .init(text: snapshot.person.name ?? "", size: 18, bold: true),
            .init(text: "Unvan: \(snapshot.person.job_title.isEmpty ? "____________________" : snapshot.person.job_title)", size: 11),
            .init(text: "\(s.workplace_name == nil ? "Firma" : "İşyeri"): \(s.workplace_name ?? s.company_name) · \(hazardName(s.hazard_class))", size: 10),
            .init(text: "Düzenleyen: \(snapshot.provider_name)", size: 11),
            .init(text: "Eğitim: \(cycle)", size: 11),
            .init(text: "Gerçekleşen gün ve saatler (Europe/Istanbul)\n" + times.joined(separator: "\n")),
            .init(text: "Süre: \(s.instruction_minutes) dk öğretim + \(s.break_minutes) dk ara = \(s.instruction_minutes + s.break_minutes) dk", size: 11, bold: true),
            .init(text: "Yöntem: \(methods.count > 1 ? "Karma" : trainingMethodName(methods.first ?? "face_to_face")) · Konu bazında yöntem arka yüzde gösterilmiştir."),
            .init(text: "Düzenleme: \(snapshot.issued_on)" + (s.valid_until.map { " · Tekrar tarihi: \($0)" } ?? ""))
        ]
        front.append(.init(text: snapshot.is_draft
            ? "TASLAK — Belge numarası tahsis edilmemiştir. Eğitim ve belge bilgileri tamamlanmadan başarı belgesi olarak kullanılamaz."
            : "Yukarıda bilgileri bulunan çalışan, belirtilen tarihlerde gerçekleştirilen ve içeriği izleyen sayfalarda yer alan eğitimi başarıyla tamamlamıştır.", size: 11, space: 12))
        front.append(.init(text: "Eğiticiler ve imza alanları", size: 11, bold: true))
        for trainer in snapshot.trainers {
            let groups = Set(s.topics.filter { $0.trainer_ids.contains(trainer.id) }.map(\.group)).sorted().joined(separator: ", ")
            front.append(signature("\(trainer.name) · \(trainer.title)\nKonu kapsamı: \(groups)\nİmza:"))
        }
        front.append(signature("İşveren / vekili adı: ____________________\nSıfatı: ____________________\nİmza / kaşe:"))
        front.append(.init(text: "Belge, düzenleyen uzmanın kaydına ve beyanına dayanır. İmza alanları fiziki imza için boş bırakılmıştır.", size: 8))
        var back: [Block] = [.init(text: "EĞİTİM KONULARI VE SÜRELERİ", size: 16, bold: true, space: 12)]
        for group in ["G1","G2","G3","G4"] {
            let topics = s.topics.filter { $0.group == group }; guard !topics.isEmpty else { continue }
            back.append(.init(text: "\(group) · \(["G1":"Genel konular","G2":"Sağlık konuları","G3":"Teknik konular","G4":"İşyerine özgü riskler"][group]!) · \(topics.reduce(0) { $0 + $1.instruction_minutes }) dk", size: 11, bold: true, space: 6))
            for t in topics {
                back.append(.init(text: "\(t.parent_code ?? t.code)  \(t.parent_code == nil ? t.title : (t.legal_title ?? "") + ": " + t.title) — \(t.instruction_minutes) dk · \(trainingMethodName(t.method))", size: 9, space: 3))
            }
        }
        back.append(.init(text: "Öğretim: \(s.instruction_minutes) dk · Ara: \(s.break_minutes) dk · Toplam: \(s.instruction_minutes + s.break_minutes) dk", size: 10, bold: true))
        var pages: [[Placed]] = []
        func layout(_ blocks: [Block]) {
            var current: [Placed] = []; var y: CGFloat = 52
            for block in blocks {
                // Split paragraphs by measured lines so a long context never clips or shrinks to illegibility.
                let attributed = NSAttributedString(string: block.text, attributes: attrs(block))
                let framesetter = CTFramesetterCreateWithAttributedString(attributed)
                var offset = 0
                repeat {
                    let available = 782 - y
                    let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: max(available, 1)), transform: nil)
                    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
                    let range = CTFrameGetVisibleStringRange(frame)
                    let required = block.height ?? ceil(attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
                    if (block.height != nil && required > available) || range.length == 0 {
                        pages.append(current); current = []; y = 52; continue
                    }
                    let count = min(range.length, attributed.length - offset)
                    var piece = block; piece = .init(text: (block.text as NSString).substring(with: NSRange(location: offset, length: count)), size: block.size, bold: block.bold, space: block.space, height: block.height)
                    let height = block.height ?? ceil((piece.text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs(piece), context: nil).height)
                    current.append(.init(block: piece, y: y, height: height)); y += height + block.space; offset += count
                    if offset < attributed.length { pages.append(current); current = []; y = 52 }
                } while offset < attributed.length
            }
            if !current.isEmpty { pages.append(current) }
        }
        if logo != nil { front.insert(.init(text: " ", height: 60), at: 0) }
        layout(front); layout(back)
        if pages.count % 2 != 0 { pages.append([.init(block: .init(text: "Bu sayfa çift taraflı baskı düzeni için boş bırakılmıştır.", size: 11), y: 400, height: 40)]) }
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for (index, page) in pages.enumerated() {
                context.beginPage(); UIColor.white.setFill(); context.cgContext.fill(bounds)
                UIColor(red: 0.1, green: 0.4, blue: 0.45, alpha: 1).setFill(); context.cgContext.fill(CGRect(x: margin, y: 34, width: width, height: 2))
                if index == 0, let logo, logo.size.width > 0, logo.size.height > 0 {
                    let factor = min(120 / logo.size.width, 50 / logo.size.height)
                    logo.draw(in: CGRect(x: margin, y: 52, width: logo.size.width * factor, height: logo.size.height * factor))
                }
                for row in page { (row.block.text as NSString).draw(in: CGRect(x: margin, y: row.y, width: width, height: row.height + 3), withAttributes: attrs(row.block)) }
                let footer = "\(snapshot.person.name ?? "") · \(snapshot.is_draft ? "TASLAK" : snapshot.number) · R\(snapshot.revision) · \(index + 1)/\(pages.count)"
                (footer as NSString).draw(in: CGRect(x: margin, y: 801, width: width, height: 24), withAttributes: attrs(.init(text: footer, size: 8)))
            }
        }
    }
    static func file(_ certificate: NovaEducationCertificate) throws -> URL {
        let owner = certificate.owner_id.uuidString
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EducationCertificates").appendingPathComponent(owner)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        let filename = certificate.document_id.map { "\($0.uuidString)-r\(certificate.revision ?? 0)-renderer\(rendererVersion)" } ?? "draft-\(certificate.snapshot.source_session_id)-\(certificate.snapshot.person.id)"
        let url = folder.appendingPathComponent(filename).appendingPathExtension("pdf")
        if certificate.snapshot.is_draft || !FileManager.default.fileExists(atPath: url.path) {
            try data(certificate.snapshot).write(to: url, options: [.atomic, .completeFileProtection])
            var values = URLResourceValues(); values.isExcludedFromBackup = true; var directory = folder; try directory.setResourceValues(values)
        }
        return url
    }
    private static func hazardName(_ value: String) -> String { ["low":"Az tehlikeli","medium":"Tehlikeli","high":"Çok tehlikeli","hazardous":"Tehlikeli","very_hazardous":"Çok tehlikeli"][value] ?? value }
}

#if !EDUCATION_RENDER_TEST
struct NovaEducationCertificateScreen: View {
    let identity: NovaSessionIdentity
    let session: NovaTrainingSession
    let scopeID: UUID
    let personID: UUID
    let canIssue: Bool
    var documentID: UUID?
    var documentRevision: Int?
    @Environment(\.dismiss) private var dismiss
    @State private var issued = Date()
    @State private var logoPNG: String?
    @State private var result: NovaEducationCertificate?
    @State private var url: URL?
    @State private var showingDocument = false
    @State private var busy = false
    @State private var error: String?
    @State private var exporting = false
    @State private var exportFile: NovaEducationPDFFile?
    var body: some View {
        VStack(spacing: 12) {
            HStack { Text("Kişisel eğitim belgesi").font(NovaFont.font(.cardTitle)); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").padding(10) } }
            if busy { ProgressView() }
            if let error { NovaHelpHint(text: error) }
            if let result {
                if !result.issues.isEmpty {
                    NovaCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            NovaText(text: "Sertifika için eğitim içeriğini tamamlayın", style: .cardTitle)
                            ForEach(result.issues, id: \.self) { code in
                                Label(NovaEducationService.issue(code), systemImage: "info.circle")
                                    .font(NovaFont.font(.meta))
                            }
                            NovaText(text: "Eğitimi açıp işaretlenen içeriği düzelttikten sonra sertifika otomatik hazırlanır.", style: .metaQuiet)
                            NovaCompactActionButton(title: "Eğitim içeriğine dön", symbol: "arrow.left") { dismiss() }
                        }
                    }
                } else if result.snapshot.is_draft {
                    NovaText(text: "Sertifika hazırlanıyor…", style: .metaQuiet)
                } else {
                    NovaCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            NovaText(text: "Sertifika hazır", style: .cardTitle)
                            NovaText(text: result.snapshot.number, style: .metaQuiet)
                        }
                    }
                }
                if !result.snapshot.is_draft {
                HStack(spacing: 12) {
                    if let url {
                        Button("Görüntüle") { showingDocument = true }
                        ShareLink(item: url) { Label("Paylaş", systemImage: "square.and.arrow.up") }
                        Button("Kaydet") { do { exportFile = .init(data: try Data(contentsOf: url)); exporting = true } catch { self.error = error.localizedDescription } }
                        Button("Yazdır") {
                            let controller = UIPrintInteractionController.shared
                            controller.printingItem = url; let info = UIPrintInfo(dictionary: nil); info.jobName = result.snapshot.title; info.duplex = .longEdge; controller.printInfo = info
                            controller.present(animated: true)
                        }
                    }
                }.font(NovaFont.font(.meta)).disabled(busy)
                }
            } else if !busy { Button("Tekrar dene") { Task { await load(issue: false) } } }
        }.padding(18).task {
            if documentID == nil, let path = session.education?.scopes.first(where: { $0.id == scopeID })?.logo_path,
               path.lowercased().hasPrefix(identity.userID.uuidString.lowercased() + "/companies/"),
               let image = try? await CompanyService.shared.logoImage(path: path), image.size.width > 0, image.size.height > 0 {
                let ratio = min(256 / image.size.width, 256 / image.size.height, 1)
                let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let png = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.pngData()
                if let png, png.count <= 262144 { logoPNG = png.base64EncodedString() }
            }
            await load(issue: false)
            if canIssue, result?.snapshot.is_draft == true, result?.issues.isEmpty == true {
                await load(issue: true)
            }
        }
        .sheet(isPresented: $showingDocument) {
            if let url { NovaEducationPDFPreview(url: url) }
        }
        .fileExporter(isPresented: $exporting, document: exportFile, contentType: .pdf, defaultFilename: result?.snapshot.is_draft == false ? result?.snapshot.number ?? "Eğitim belgesi" : "TASLAK eğitim belgesi") { outcome in
            if case .failure(let error) = outcome { self.error = error.localizedDescription }
        }
    }
    private func load(issue: Bool) async {
        busy = true; error = nil; defer { busy = false }
        do {
            let service = NovaEducationService(identity: identity)
            let request: NovaEducationService.CertificateRequest = !issue && documentID != nil
                ? .init(action: "read", document_id: documentID, revision: documentRevision)
                : .init(action: issue ? "issue" : "preview", session_id: session.id, scope_id: scopeID, person_id: personID, expected_version: session.version, issued_on: NovaEducationClock.day(issued), logo_png_base64: logoPNG)
            let certificate = try await service.certificate(request)
            try service.check()
            url = certificate.snapshot.is_draft ? nil : try NovaEducationCertificatePDF.file(certificate)
            result = certificate
        } catch { self.error = NovaEducationService.message(error) }
    }
}
private struct NovaEducationPDFPreview: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; return view }
    func updateUIView(_ uiView: PDFView, context: Context) { if uiView.document?.documentURL != url { uiView.document = PDFDocument(url: url) } }
}

#endif
