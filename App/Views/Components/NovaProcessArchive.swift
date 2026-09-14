import SwiftUI

struct NovaProcessArchive: View {
    let identity: NovaSessionIdentity
    var onBack: () -> Void = {}
    struct Entry: Decodable, Identifiable {
        let id: UUID; let version: Int; let document_no: String
        let company_name: String; let kind: String
        var key: String { "\(id):\(version)" }
    }
    @State private var legacy = false
    @State private var entries: [Entry] = []
    @State private var busy = false
    @State private var failure: String?
    @State private var more = false
    @State private var file: URL?
    private var service: NovaProcessService { .init(identity: identity) }
    var body: some View {
        VStack {
            NovaPageHeading(title: "Rapor Arşivi", onBack: onBack).padding(.horizontal, 16)
            Picker("Raporlar", selection: $legacy) {
                Text("Süreç belgeleri").tag(false)
                Text("Analiz raporları").tag(true)
            }.pickerStyle(.segmented).padding(.horizontal)
            if legacy { ReportView() }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if busy { ProgressView("Yükleniyor…") }
                        if let failure { Text(failure).font(NovaFont.font(.meta));Button("Yeniden dene") {Task {await load()}} }
                        if entries.isEmpty && !busy { NovaText(text:"Hazırladığınız süreç belgeleri ve önceki sürümleri burada görünür.",style:.body) }
                        ForEach(entries,id:\.key) { entry in
                            NovaCard(padding:16) {
                                VStack(alignment:.leading,spacing:8) {
                                    NovaText(text:NovaProcessKind.get(entry.kind).title,style:.cardTitle)
                                    NovaText(text:entry.company_name,style:.meta)
                                    NovaText(text:"\(entry.document_no) · Sürüm \(entry.version)",style:.meta)
                                    HStack {
                                        Button("PDF indir") {Task {await open(entry,excel:false)}}
                                        Button("Excel indir") {Task {await open(entry,excel:true)}}
                                    }.disabled(busy)
                                }
                            }
                        }
                        if more {Button("Daha fazla") {Task {await load(append:true)}}.disabled(busy)}
                    }.padding(16)
                }
            }
        }.task {await load()}.sheet(item:$file) {NovaFileShareSheet(url:$0)}
    }
    private func load(append:Bool = false) async {
        busy=true;failure=nil;defer{busy=false}
        do {
            let data=try await service.documents(offset:append ? entries.count:0)
            let page=try JSONDecoder().decode([Entry].self,from:data)
            entries=append ? entries+page:page;more=page.count==20
        } catch {failure=NovaProcessService.message(error)}
    }
    private func open(_ entry:Entry,excel:Bool) async {
        busy=true;failure=nil;defer{busy=false}
        do {
            let snapshot=try JSONDecoder().decode(NovaProcessRow.self,from:await service.documents(document:entry.id,version:entry.version))
            file=try excel ? NovaProcessXLSX.write(snapshot,kind:.get(entry.kind),owner:identity.userID):NovaProcessPDF.write(snapshot,kind:.get(entry.kind),owner:identity.userID)
        } catch {failure=NovaProcessService.message(error)}
    }
}
