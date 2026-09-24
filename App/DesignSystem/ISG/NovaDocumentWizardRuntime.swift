import Foundation
import JavaScriptCore
import UIKit
import CoreText

struct NovaWizardQuestion: Decodable, Identifiable {
    let id: String
    let field: String
    let text_tr: String
    let help_tr: String
}
struct NovaWizardChoice: Decodable, Identifiable {
    let id: String
    let label: String
    let aliases: [String]
}
struct NovaWizardPreview: Decodable {
    struct Row: Decodable, Identifiable { let id: String; let scenario_tr: String; let consequences_tr: String }
    struct Card: Decodable, Identifiable { let id: String; let title_tr: String }
    struct Gap: Decodable, Identifiable { let id: String; let title: String; let missing_labels: [String] }
    struct Omitted: Decodable, Identifiable { let id: String; let title: String; let severe: Bool }
    let rows: [Row]
    let cards: [Card]
    let unresolved: [Gap]
    let omitted: [Omitted]
    let input_conflicts: [String]
    let content_sha256: String
    let eligible_count: Int
}
struct NovaWizardBlock: Decodable {
    let type: String
    let text: String?
    let rows: [[String]]?
}
struct NovaWizardDownload {
    let name: String
    let data: Data
}
enum NovaWizardError: LocalizedError {
    case unavailable, invalid(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: return RDLocalization.string("localizable.nova.document.wizard.runtime.sihirbaz.icerigi.yuklenemedi.f292ce07", table: .localizable, fallback: "Sihirbaz içeriği yüklenemedi.")
        case .invalid(let message): return message
        }
    }
}

/// Offline, bundled-only JavaScript. No JSExport objects, network or storage API.
/// User strings are passed as values; they are never interpolated into source.
@MainActor final class NovaDocumentWizardRuntime {
    let questions: [NovaWizardQuestion]
    let choices: [String: [NovaWizardChoice]]
    let options: [String: [String: String]]
    private let context: JSContext
    private let engine: JSValue
    private var snapshot: JSValue?

    init(bundle: Bundle = .main) throws {
        func asset(_ name: String, _ ext: String) throws -> Data {
            guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "WizardAssets/isg_wizard")
                ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "isg_wizard")
                ?? bundle.url(forResource: name, withExtension: ext) else { throw NovaWizardError.unavailable }
            return try Data(contentsOf: url)
        }
        guard let vm = JSContext() else { throw NovaWizardError.unavailable }
        context = vm
        for name in ["engine", "export"] {
            guard let code = String(data: try asset(name, "js"), encoding: .utf8) else { throw NovaWizardError.unavailable }
            vm.evaluateScript(code)
            if vm.exception != nil { throw NovaWizardError.unavailable }
        }
        let catalog = try JSONSerialization.jsonObject(with: asset("isgada-catalog", "json"))
        guard let value = vm.objectForKeyedSubscript("ISGWizard")?.invokeMethod("create", withArguments: [catalog]),
              vm.exception == nil, !value.isUndefined else { throw NovaWizardError.unavailable }
        engine = value
        func decode<T: Decodable>(_ key: String, as type: T.Type) throws -> T {
            guard let data = value.forProperty(key)?.toObject() else { throw NovaWizardError.unavailable }
            return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: data))
        }
        questions = try decode("questions", as: [NovaWizardQuestion].self)
        choices = try decode("choices", as: [String: [NovaWizardChoice]].self)
        options = try decode("options", as: [String: [String: String]].self)
    }

    private func check() throws {
        if let error = context.exception {
            context.exception = nil
            throw NovaWizardError.invalid(error.toString() ?? "Belge oluşturulamadı.")
        }
    }
    func generate(answers: [String: Any], domain: String) throws -> NovaWizardPreview {
        snapshot = nil
        let value = engine.invokeMethod("generate", withArguments: [answers, domain])
        try check()
        guard let value, let result = value.toObject() else { throw NovaWizardError.unavailable }
        let preview = try JSONDecoder().decode(NovaWizardPreview.self, from: JSONSerialization.data(withJSONObject: result))
        snapshot = value
        return preview
    }
    func blocks() throws -> [NovaWizardBlock] {
        guard let snapshot else { throw NovaWizardError.unavailable }
        let value = engine.invokeMethod("blocks", withArguments: [snapshot])
        try check()
        guard let data = value?.toObject() else { throw NovaWizardError.unavailable }
        return try JSONDecoder().decode([NovaWizardBlock].self, from: JSONSerialization.data(withJSONObject: data))
    }
    func download(format: String) throws -> NovaWizardDownload {
        guard let snapshot else { throw NovaWizardError.unavailable }
        if format == "pdf" {
            return .init(name: "ISGADA_\(snapshot.forProperty("content_sha256")?.toString().prefix(10) ?? "taslak").pdf",
                         data: try Self.pdf(blocks: blocks()))
        }
        let file = context.objectForKeyedSubscript("ISGWizard")?.invokeMethod("exportFile", withArguments: [engine, snapshot, format])
        try check()
        guard let name = file?.forProperty("name")?.toString(), let base64 = file?.forProperty("base64")?.toString(),
              let data = Data(base64Encoded: base64) else { throw NovaWizardError.unavailable }
        return .init(name: name, data: data)
    }

    /// CoreText paginates by fitted glyph range, including long controls and Turkish text.
    static func pdf(blocks: [NovaWizardBlock]) throws -> Data {
        let document = NSMutableAttributedString(string: "")
        for block in blocks {
            let text = block.rows?.map { $0.joined(separator: "  ·  ") }.joined(separator: "\n") ?? block.text ?? ""
            let heading = ["title", "heading", "subheading"].contains(block.type)
            let size: CGFloat = block.type == "title" ? 20 : heading ? 13 : 10.5
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = heading ? 9 : 6
            paragraph.lineSpacing = 2
            document.append(NSAttributedString(string: text + "\n", attributes: [.font: heading ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black, .paragraphStyle: paragraph]))
        }
        let setter = CTFramesetterCreateWithAttributedString(document)
        let rect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: rect)
        var incomplete = false
        let data = renderer.pdfData { pdf in
            var offset = 0
            var page = 0
            while offset < document.length {
                pdf.beginPage(); page += 1
                let canvas = pdf.cgContext
                canvas.saveGState(); canvas.translateBy(x: 0, y: rect.height); canvas.scaleBy(x: 1, y: -1)
                let frame = CTFramesetterCreateFrame(setter, CFRange(location: offset, length: 0), CGPath(rect: CGRect(x: 42, y: 48, width: 528, height: 696), transform: nil), nil)
                let fitted = CTFrameGetVisibleStringRange(frame)
                guard fitted.length > 0 else { incomplete = true; canvas.restoreGState(); break }
                CTFrameDraw(frame, canvas); offset += fitted.length; canvas.restoreGState()
                ("İSGADA · \(page)" as NSString).draw(at: CGPoint(x: 42, y: 765), withAttributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.darkGray])
            }
        }
        if incomplete { throw NovaWizardError.invalid("PDF sayfaları oluşturulamadı.") }
        return data
    }
}
