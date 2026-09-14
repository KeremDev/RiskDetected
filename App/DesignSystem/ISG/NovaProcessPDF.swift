import UIKit
import CoreText

@MainActor enum NovaProcessPDF {
    static func write(_ row:NovaProcessRow,kind:NovaProcessKind,owner:UUID) throws -> URL {
        let bounds = CGRect(x:0,y:0,width:595,height:842)
        let data = UIGraphicsPDFRenderer(bounds:bounds).pdfData { context in
            var y:CGFloat = 44; var page = 0
            func start() {
                context.beginPage(); page += 1; y = 44
                ("İSGADA · \(row.number ?? row.id.uuidString) · v\(row.revision ?? 1) · Sayfa \(page)" as NSString).draw(at:CGPoint(x:36,y:813),withAttributes:[.font:UIFont.systemFont(ofSize:8),.foregroundColor:UIColor.darkGray])
            }
            func paragraph(_ text:String,size:CGFloat = 11,bold:Bool = false) {
                let style=NSMutableParagraphStyle();style.lineSpacing=4
                let font=UIFont(name:bold ? "PlusJakartaSans-Bold":"PlusJakartaSans-Regular",size:size) ?? UIFont.systemFont(ofSize:size)
                let attr=NSAttributedString(string:text,attributes:[.font:font,.foregroundColor:UIColor.black,.paragraphStyle:style])
                let setter=CTFramesetterCreateWithAttributedString(attr)
                var offset=0
                while offset<attr.length {
                    if y>750 {start()}
                    let height=CGFloat(780)-y
                    let path=CGPath(rect:CGRect(x:36,y:842-y-height,width:523,height:height),transform:nil)
                    let frame=CTFramesetterCreateFrame(setter,CFRange(location:offset,length:0),path,nil)
                    let visible=CTFrameGetVisibleStringRange(frame)
                    if visible.length==0 {start();continue}
                    context.cgContext.saveGState();context.cgContext.translateBy(x:0,y:842);context.cgContext.scaleBy(x:1,y:-1)
                    CTFrameDraw(frame,context.cgContext);context.cgContext.restoreGState()
                    let used=CTFramesetterSuggestFrameSizeWithConstraints(setter,CFRange(location:offset,length:visible.length),nil,CGSize(width:523,height:height),nil).height
                    y+=ceil(used)+12;offset+=visible.length
                }
            }
            func display(_ value:NovaModuleValue)->String {
                switch value {
                case .array(let a):return a.map(display).joined(separator:"\n")
                case .object(let o):return o["name"]?.text ?? o.values.map(display).joined(separator:" · ")
                case .number(let n):return n.rounded()==n ? String(Int(n)):String(n)
                case .null:return "—"
                default:return value.text
                }
            }
            start();paragraph(kind.title.uppercased(),size:19,bold:true)
            paragraph("Firma: "+row.company_name)
            for field in kind.fields {
                let val=row.values[field.id] ?? .null
                let value = field.id == "workplace_id" ? (row.workplace_name ?? "İşyeri") : (field.choices[val.text] ?? display(val))
                paragraph(field.title,size:10,bold:true);paragraph(value)
            }
            if let children = row.children, let childCode = row.child_kind {
                let child = NovaProcessKind.get(childCode)
                for (index, entry) in children.enumerated() {
                    paragraph("\(index + 1). \(child.title)",size:13,bold:true)
                    for field in child.fields {
                        let val = entry.values[field.id] ?? .null
                        paragraph(field.title + ": " + (field.choices[val.text] ?? display(val)))
                    }
                }
            }
            if kind.code == "work_permit" {paragraph("Bu form hazırlama aracıdır. Çalışmayı başlatma yetkisi veya saha onayı vermez.",size:9)}
            if kind.code == "katip_contract" {paragraph("Uzman tarafından kaydedilen sözleşme bilgileridir. Resmî İSG-KATİP işlemi yapılmamıştır.",size:9)}
            if y>650 {start()}
            paragraph("Düzenleyen / İmza                         İlgili kişi / İmza",bold:true);y+=72
        }
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("process-\(owner.uuidString)")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let url=folder.appendingPathComponent("\(kind.code)-\(row.id)-\(row.expected.prefix(8)).pdf")
        try data.write(to:url,options:[.atomic,.completeFileProtection]);return url
    }
}
