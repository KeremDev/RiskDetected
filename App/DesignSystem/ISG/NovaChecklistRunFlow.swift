import SwiftUI

/// Full-screen field mode. One question, one decision, one visible progress
/// indicator. Supporting information is moved to explicit secondary pages.
struct NovaChecklistRunTaskScreen: View {
    let run: NovaChecklistRun
    var canWrite = true
    let onAnswer: (NovaChecklistAnswerDraft) async -> String?
    let onSubmit: () async -> String?
    let onCancel: () async -> String?
    let onRevise: () async -> String?
    let onClose: () -> Void

    private enum Page { case question, answers, summary, result, information, extras, nonconformity, notApplicable, cancel }
    @State private var page: Page = .question
    @State private var currentIndex = 0
    @State private var localDrafts: [String: NovaChecklistAnswerDraft] = [:]
    @State private var editingDraft: NovaChecklistAnswerDraft?
    @State private var issueDescription = ""
    @State private var correctionSuggestion = ""
    @State private var selectedSeverity: NovaChecklistSeverity?
    @State private var cancellationReason = ""
    @State private var failure: String?
    @State private var working = false
    @State private var showingExitConfirmation = false
    @State private var exportURL: URL?
    @Environment(\.colorScheme) private var scheme

    private var orderedAnswers: [NovaChecklistAnswer] { run.answers.sorted { $0.position < $1.position } }
    private var currentAnswer: NovaChecklistAnswer? {
        guard orderedAnswers.indices.contains(currentIndex) else { return nil }
        return orderedAnswers[currentIndex]
    }
    private var scopeTitle: String {
        let text = [run.companyName, run.workplaceName].compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? "Bağımsız kontrol" : text
    }

    var body: some View {
        NovaPageSurface(onEdgeBack: handleBack) {
            Group {
                switch page {
                case .question: questionPage
                case .answers: answersPage
                case .summary: summaryPage
                case .result: resultPage
                case .information: informationPage
                case .extras: extrasPage
                case .nonconformity: nonconformityPage
                case .notApplicable: notApplicablePage
                case .cancel: cancelPage
                }
            }
        }
        .onAppear {
            currentIndex = firstUnansweredIndex
            if run.state == .submitted || run.state == .cancelled { page = .result }
            else if run.remaining == 0 { page = .summary }
        }
        .onChange(of: run.state) { state in
            if state == .submitted || state == .cancelled { page = .result }
        }
        .alert(RDLocalization.string("localizable.nova.checklist.run.flow.kontrolden.cikmak.istiyor.musunuz.5cc055e0", table: .localizable, fallback: "Kontrolden çıkmak istiyor musunuz?"), isPresented: $showingExitConfirmation) {
            Button(RDLocalization.string("localizable.nova.checklist.run.flow.kontrolde.kal.c4057787", table: .localizable, fallback: "Kontrolde kal"), role: .cancel) {}
            Button(RDLocalization.string("localizable.nova.checklist.run.flow.kontrolden.cik.4fe28282", table: .localizable, fallback: "Kontrolden çık")) { onClose() }
        } message: {
            Text(RDLocalization.string("localizable.nova.checklist.run.flow.cevaplariniz.kaydedildi.daha.sonra.kaldiginiz.ye.c26131a7", table: .localizable, fallback: "Cevaplarınız kaydedildi. Daha sonra kaldığınız yerden devam edebilirsiniz."))
        }
        .sheet(item: $exportURL) { NovaFileShareSheet(url: $0) }
    }

    private var firstUnansweredIndex: Int {
        orderedAnswers.firstIndex(where: { !$0.isAnswered }) ?? max(0, orderedAnswers.count - 1)
    }

    private var questionPage: some View {
        VStack(spacing: 0) {
            taskHeader(title: run.templateTitle ?? run.templateCode, backTitle: "Kontrolden çık", back: requestExit) {
                Button { page = .answers } label: {
                    NovaText(text: RDLocalization.format("localizable.nova.checklist.run.flow.yanitlar.1.61b22c64", table: .localizable, fallback: "Yanıtlar %1$@", arguments: [String(describing: run.answered)]), style: .buttonSm)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(NovaRowPressStyle())
                .accessibilityLabel(RDLocalization.format("localizable.nova.checklist.run.flow.yanitlar.1.tamamlandi.f4ffef30", table: .localizable, fallback: "Yanıtlar, %1$@ tamamlandı", arguments: [String(describing: run.answered)]))
            }
            if let answer = currentAnswer {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 7) {
                            NovaText(text: scopeTitle, style: .meta,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                            HStack {
                                NovaText(text: "\(run.answered) / \(run.expected)", style: .label)
                                Spacer()
                            }
                            ProgressView(value: Double(run.answered), total: Double(max(run.expected, 1)))
                                .tint(NovaColorToken.accentInk.color(in: scheme))
                                .accessibilityLabel(RDLocalization.format("localizable.nova.checklist.run.flow.kontrol.ilerlemesi.1.sorudan.2.tamamlandi.1f498606", table: .localizable, fallback: "Kontrol ilerlemesi: %1$@ sorudan %2$@ tamamlandı", arguments: [String(describing: run.expected), String(describing: run.answered)]))
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            NovaText(text: "Soru \(answer.position)", style: .sectionTitle,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                            NovaText(text: answer.prompt, style: .screenTitle)
                        }

                        if let help = answer.helpText, !help.isEmpty {
                            DisclosureGroup {
                                NovaText(text: help, style: .meta,
                                    color: NovaColorToken.textSecondary.color(in: scheme))
                                    .padding(.top, 8)
                            } label: {
                                Label(RDLocalization.string("localizable.nova.checklist.run.flow.neye.bakmaliyim.f808507c", table: .localizable, fallback: "Neye bakmalıyım?"), systemImage: "info.circle")
                                    .font(NovaFont.font(.label))
                            }
                            .padding(.vertical, 6)
                        }

                        secondaryActions(answer)

                        if let result = answer.result {
                            HStack(spacing: 7) {
                                Image(systemName: result.symbol)
                                NovaText(text: result.title, style: .label)
                                if answer.nonconformityID != nil {
                                    NovaText(text: RDLocalization.string("localizable.nova.checklist.run.flow.uygunsuzluk.e5ad8f83", table: .localizable, fallback: "· Uygunsuzluk"), style: .meta,
                                        color: NovaColorToken.statusWarningInk.color(in: scheme))
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(tone(result).tokens.background.color(in: scheme),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        if let failure { errorText(failure) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { answerBar(answer) }
            } else {
                NovaChecklistMessageState(symbol: "checklist", title: RDLocalization.string("localizable.nova.checklist.run.flow.bu.kontrolde.soru.yok.30911f8d", table: .localizable, fallback: "Bu kontrolde soru yok"),
                    message: RDLocalization.string("localizable.nova.checklist.run.flow.kontrol.listesi.icerigi.bulunamadi.3aa590bc", table: .localizable, fallback: "Kontrol listesi içeriği bulunamadı."), actionTitle: nil, action: {})
            }
        }
    }

    private func secondaryActions(_ answer: NovaChecklistAnswer) -> some View {
        HStack(spacing: 12) {
            Button { openExtras(answer) } label: {
                Label(noteLabel(answer), systemImage: "note.text.badge.plus")
                    .font(NovaFont.font(.label)).frame(minHeight: 44)
            }
            .buttonStyle(NovaRowPressStyle())
            Button { openExtras(answer) } label: {
                Label(evidenceLabel(answer), systemImage: "camera")
                    .font(NovaFont.font(.label)).frame(minHeight: 44)
            }
            .buttonStyle(NovaRowPressStyle())
        }
    }

    private func noteLabel(_ answer: NovaChecklistAnswer) -> String {
        let note = localDrafts[answer.itemCode]?.note ?? answer.note ?? ""
        return note.isEmpty ? "Not ekle" : "1 not"
    }

    private func evidenceLabel(_ answer: NovaChecklistAnswer) -> String {
        let hasEvidence = localDrafts[answer.itemCode]?.attachment != nil || answer.evidenceAssetID != nil
        return hasEvidence ? "1 kanıt" : "Fotoğraf ekle"
    }

    private func answerBar(_ answer: NovaChecklistAnswer) -> some View {
        VStack(spacing: 9) {
            if canWrite && run.state == .open {
                NovaChecklistAnswerButton(result: .conform, selected: answer.result == .conform, working: working) {
                    saveDirect(answer, result: .conform)
                }
                NovaChecklistAnswerButton(result: .nonconform, selected: answer.result == .nonconform, working: working) {
                    openNonconformity(answer)
                }
                if answer.allowsNotApplicable {
                    NovaChecklistAnswerButton(result: .notApplicable,
                        selected: answer.result == .notApplicable, working: working) {
                        openNotApplicable(answer)
                    }
                }
            }
            HStack {
                Button { currentIndex = max(0, currentIndex - 1) } label: {
                    Label(RDLocalization.string("localizable.nova.checklist.run.flow.onceki.29aeea44", table: .localizable, fallback: "Önceki"), systemImage: "chevron.left").frame(minHeight: 44)
                }
                .buttonStyle(NovaRowPressStyle()).disabled(currentIndex == 0 || working)
                Spacer()
                Button { moveNext() } label: {
                    Label(currentIndex == orderedAnswers.count - 1 ? "Özete git" : "Sonraki",
                        systemImage: "chevron.right").labelStyle(.titleAndIcon).frame(minHeight: 44)
                }
                .buttonStyle(NovaRowPressStyle())
                .disabled(!answer.isAnswered || working)
            }
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)
        .background(NovaColorToken.surface.color(in: scheme).shadow(color: .black.opacity(0.06), radius: 10, y: -2))
    }

    private var answersPage: some View {
        VStack(spacing: 0) {
            taskHeader(title: RDLocalization.string("localizable.nova.checklist.run.flow.yanitlar.ccad1860", table: .localizable, fallback: "Yanıtlar"), backTitle: "Kontrole dön", back: { page = .question }) { EmptyView() }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(orderedAnswers.enumerated()), id: \.element.id) { index, answer in
                        Button {
                            currentIndex = index
                            page = .question
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: answer.result?.symbol ?? "circle")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(answer.result.map { tone($0).tokens.ink.color(in: scheme) }
                                        ?? NovaColorToken.textMuted.color(in: scheme))
                                    .frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    NovaText(text: "\(answer.position). \(answer.prompt)", style: .body)
                                    NovaText(text: answer.result?.title ?? "Cevaplanmadı", style: .meta,
                                        color: NovaColorToken.textSecondary.color(in: scheme))
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
                            }
                            .padding(.vertical, 14).contentShape(Rectangle())
                        }
                        .buttonStyle(NovaRowPressStyle())
                        Divider().overlay(NovaColorToken.hairline.color(in: scheme))
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
        }
    }

    private var summaryPage: some View {
        VStack(spacing: 0) {
            taskHeader(title: RDLocalization.string("localizable.nova.checklist.run.flow.kontrol.ozeti.8ab76220", table: .localizable, fallback: "Kontrol özeti"), backTitle: "Kontrole dön", back: { page = .question }) { EmptyView() }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        NovaText(text: run.remaining == 0 ? "Kontrol tamamlanmaya hazır" : "Kontrol henüz tamamlanmadı",
                            style: .screenTitle)
                        NovaText(text: RDLocalization.format("localizable.nova.checklist.run.flow.1.2.soru.yanitlandi.8a9188f2", table: .localizable, fallback: "%1$@ / %2$@ soru yanıtlandı", arguments: [String(describing: run.answered), String(describing: run.expected)]), style: .body,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    VStack(spacing: 0) {
                        summaryRow("Uygun", value: run.conform, symbol: "checkmark.circle")
                        Divider()
                        summaryRow("Uygun değil", value: run.nonconform, symbol: "exclamationmark.triangle")
                        Divider()
                        summaryRow("Uygulanamaz", value: run.notApplicable, symbol: "minus.circle")
                        Divider()
                        summaryRow("Uygunsuzluk kaydı", value: run.nonconformitiesOpened,
                            symbol: "exclamationmark.bubble")
                    }
                    Button { page = .answers } label: {
                        HStack {
                            NovaText(text: RDLocalization.string("localizable.nova.checklist.run.flow.yanitlari.gozden.gecir.af3aa195", table: .localizable, fallback: "Yanıtları gözden geçir"), style: .label)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .frame(minHeight: 52).contentShape(Rectangle())
                    }
                    .buttonStyle(NovaRowPressStyle())
                    if let failure { errorText(failure) }
                }
                .padding(20).padding(.bottom, 100)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NovaButton(label: working ? "Tamamlanıyor…" : "Kontrolü tamamla",
                    symbol: "checkmark.circle", variant: .primary, isEnabled: run.remaining == 0,
                    isLoading: working) {
                    Task {
                        guard run.remaining == 0 else { return }
                        working = true; failure = await onSubmit(); working = false
                        if failure == nil { page = .result }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(NovaColorToken.surface.color(in: scheme))
            }
        }
    }

    private var resultPage: some View {
        VStack(spacing: 0) {
            taskHeader(title: run.state == .cancelled ? "Kontrol iptal edildi" : "Kontrol sonucu",
                backTitle: "Kontroller", back: onClose) { EmptyView() }
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: run.state == .cancelled ? "xmark.circle" : "checkmark.circle.fill")
                        .font(.system(size: 52, weight: .regular))
                        .foregroundStyle(run.state == .cancelled
                            ? NovaColorToken.textMuted.color(in: scheme)
                            : NovaColorToken.statusSuccessInk.color(in: scheme))
                    NovaText(text: run.state == .cancelled ? "Kontrol iptal edildi" : "Kontrol tamamlandı",
                        style: .screenTitle).multilineTextAlignment(.center)
                    VStack(spacing: 5) {
                        NovaText(text: run.templateTitle ?? run.templateCode, style: .cardTitle)
                            .multilineTextAlignment(.center)
                        NovaText(text: scopeTitle, style: .body,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                        NovaText(text: NovaChecklistUXDate.display(run.startedOn), style: .meta,
                            color: NovaColorToken.textMuted.color(in: scheme))
                    }
                    if run.state == .submitted {
                        VStack(spacing: 0) {
                            summaryRow("Soru", value: run.expected, symbol: "list.number")
                            Divider()
                            summaryRow("Uygun", value: run.conform, symbol: "checkmark.circle")
                            Divider()
                            summaryRow("Uygun değil", value: run.nonconform, symbol: "exclamationmark.triangle")
                            Divider()
                            summaryRow("Uygulanamaz", value: run.notApplicable, symbol: "minus.circle")
                        }
                        NovaButton(label: RDLocalization.string("localizable.nova.checklist.run.flow.raporu.goruntule.34ca2856", table: .localizable, fallback: "Raporu görüntüle"), symbol: "doc.richtext", variant: .primary) {
                            do { exportURL = try NovaChecklistExport.pdf(run: run) }
                            catch { failure = "Rapor oluşturulamadı." }
                        }
                        HStack(spacing: 10) {
                            NovaButton(label: "Excel", symbol: "tablecells", variant: .surface) {
                                do { exportURL = try NovaChecklistExport.xlsx(run: run) }
                                catch { failure = "Excel dosyası oluşturulamadı." }
                            }
                            if canWrite {
                                NovaButton(label: RDLocalization.string("localizable.nova.checklist.run.flow.yeni.dogrulama.55027e7b", table: .localizable, fallback: "Yeni doğrulama"), symbol: "arrow.triangle.2.circlepath",
                                    variant: .surface) {
                                    Task {
                                        working = true; failure = await onRevise(); working = false
                                        if failure == nil { currentIndex = 0; page = .question }
                                    }
                                }
                            }
                        }
                    }
                    if let failure { errorText(failure) }
                    NovaButton(label: RDLocalization.string("localizable.nova.checklist.run.flow.kontrollerime.don.89c164ab", table: .localizable, fallback: "Kontrollerime dön"), symbol: "chevron.left", variant: .surface,
                        action: onClose)
                }
                .padding(20).padding(.bottom, 30)
            }
        }
    }

    private var informationPage: some View {
        VStack(spacing: 0) {
            taskHeader(title: RDLocalization.string("localizable.nova.checklist.run.flow.kontrol.bilgileri.b3e75f78", table: .localizable, fallback: "Kontrol bilgileri"), backTitle: "Kontrole dön", back: { page = .question }) { EmptyView() }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    informationRow("Liste", run.templateTitle ?? run.templateCode)
                    informationRow("Liste sürümü", "v\(run.templateVersion)")
                    informationRow("Kontrol tarihi", NovaChecklistUXDate.display(run.startedOn))
                    informationRow("Kapsam", scopeTitle)
                    if let area = run.areaLabel, !area.isEmpty { informationRow("Bölüm / alan", area) }
                    if let equipment = run.equipmentLabel, !equipment.isEmpty { informationRow("Makine / ekipman", equipment) }
                    if !run.sourceIDs.isEmpty {
                        informationRow("Kaynaklar", run.sourceIDs.joined(separator: " · "))
                    }
                    NovaText(text: RDLocalization.string("localizable.nova.checklist.run.flow.bu.kontrol.basladigi.andaki.soru.surumunu.saklar.48fa0dd3", table: .localizable, fallback: "Bu kontrol, başladığı andaki soru sürümünü saklar. Sonraki liste değişiklikleri bu kaydı değiştirmez."),
                        style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                }
                .padding(20)
            }
        }
    }

    private var extrasPage: some View {
        NovaChecklistQuestionExtrasScreen(draft: editingDraft ?? NovaChecklistAnswerDraft(),
            onBack: { page = .question }, onSave: { draft in
                localDrafts[draft.itemCode] = draft
                editingDraft = draft
                page = .question
            })
    }

    private var notApplicablePage: some View {
        NovaChecklistNotApplicableScreen(draft: editingDraft ?? NovaChecklistAnswerDraft(), working: working,
            failure: failure, onBack: { page = .question }) { draft in
                Task { await persist(draft, thenAdvance: true) }
            }
    }

    private var nonconformityPage: some View {
        NovaChecklistNonconformityScreen(draft: editingDraft ?? NovaChecklistAnswerDraft(),
            companyName: run.companyName, description: $issueDescription,
            recommendation: $correctionSuggestion, severity: $selectedSeverity,
            working: working, failure: failure, onBack: { page = .question }) { draft in
                Task { await persist(draft, thenAdvance: true) }
            }
    }

    private var cancelPage: some View {
        VStack(spacing: 0) {
            taskHeader(title: RDLocalization.string("localizable.nova.checklist.run.flow.kontrolu.iptal.et.bbcaed9f", table: .localizable, fallback: "Kontrolü iptal et"), backTitle: "Kontrole dön", back: { page = .question }) { EmptyView() }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NovaText(text: RDLocalization.string("localizable.nova.checklist.run.flow.bu.kontrol.tamamlanmis.sayilmayacak.kaydedilmis..fea2bbc3", table: .localizable, fallback: "Bu kontrol tamamlanmış sayılmayacak. Kaydedilmiş yanıtlar geçmişte kalacak."),
                        style: .body, color: NovaColorToken.textSecondary.color(in: scheme))
                    VStack(alignment: .leading, spacing: 8) {
                        NovaText(text: RDLocalization.string("localizable.nova.checklist.run.flow.iptal.nedeni.25e30c32", table: .localizable, fallback: "İptal nedeni *"), style: .label)
                        Picker(RDLocalization.string("localizable.nova.checklist.run.flow.iptal.nedeni.beec9285", table: .localizable, fallback: "İptal nedeni"), selection: $cancellationReason) {
                            Text(RDLocalization.string("localizable.nova.checklist.run.flow.secin.d682b3f3", table: .localizable, fallback: "Seçin")).tag("")
                            Text(RDLocalization.string("localizable.nova.checklist.run.flow.kontrol.artik.gerekli.degil.fe5f8097", table: .localizable, fallback: "Kontrol artık gerekli değil")).tag("not_required")
                            Text(RDLocalization.string("localizable.nova.checklist.run.flow.yanlis.kapsam.veya.liste.secildi.9509766b", table: .localizable, fallback: "Yanlış kapsam veya liste seçildi")).tag("wrong_scope")
                            Text(RDLocalization.string("localizable.nova.checklist.run.flow.saha.kosullari.uygun.degil.4a3a6143", table: .localizable, fallback: "Saha koşulları uygun değil")).tag("site_unavailable")
                            Text(RDLocalization.string("localizable.nova.checklist.run.flow.diger.c31d7e85", table: .localizable, fallback: "Diğer")).tag("other")
                        }
                        .pickerStyle(.menu)
                        .padding(12).novaControlBackground(cornerRadius: 12)
                    }
                    if let failure { errorText(failure) }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NovaButton(label: working ? "İptal ediliyor…" : "Kontrolü iptal et",
                    symbol: "xmark.circle", variant: .danger,
                    isEnabled: !cancellationReason.isEmpty, isLoading: working) {
                    Task {
                        working = true; failure = await onCancel(); working = false
                        if failure == nil { page = .result }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(NovaColorToken.surface.color(in: scheme))
            }
        }
    }

    private func taskHeader<Action: View>(title: String, backTitle: String, back: @escaping () -> Void,
        @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: 10) {
            Button(action: back) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                    NovaText(text: backTitle, style: .buttonSm)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(NovaRowPressStyle())
            Spacer(minLength: 8)
            action()
        }
        .overlay {
            NovaText(text: title, style: .label).lineLimit(1).padding(.horizontal, 90)
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
    }

    private func summaryRow(_ title: String, value: Int, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 24)
            NovaText(text: title, style: .body)
            Spacer()
            NovaText(text: "\(value)", style: .label)
        }
        .padding(.vertical, 13)
    }

    private func informationRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NovaText(text: title, style: .meta,
                color: NovaColorToken.textSecondary.color(in: scheme))
            NovaText(text: value, style: .body)
        }
    }

    private func errorText(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.circle")
            NovaText(text: text, style: .meta,
                color: NovaColorToken.statusDangerInk.color(in: scheme))
        }
        .accessibilityElement(children: .combine)
    }

    private func handleBack() {
        switch page {
        case .question: requestExit()
        case .result: onClose()
        default: page = .question
        }
    }

    private func requestExit() {
        if run.state == .open { showingExitConfirmation = true }
        else { onClose() }
    }

    private func moveNext() {
        if currentIndex < orderedAnswers.count - 1 { currentIndex += 1 }
        else { page = .summary }
    }

    private func draft(for answer: NovaChecklistAnswer) -> NovaChecklistAnswerDraft {
        if let local = localDrafts[answer.itemCode] { return local }
        return .init(runID: run.id, itemCode: answer.itemCode, prompt: answer.prompt,
            allowsNotApplicable: answer.allowsNotApplicable,
            verificationMethod: answer.verificationMethod, helpText: answer.helpText,
            naReasonRequired: answer.naReasonRequired,
            evidenceRecommended: answer.evidenceRecommended, photoRequired: answer.photoRequired,
            result: answer.result ?? .conform, note: answer.note ?? "",
            evidenceAssetID: answer.evidenceAssetID,
            openNonconformity: answer.nonconformityID != nil,
            expectedRevision: run.revision)
    }

    private func openExtras(_ answer: NovaChecklistAnswer) {
        editingDraft = draft(for: answer)
        page = .extras
    }

    private func openNotApplicable(_ answer: NovaChecklistAnswer) {
        var value = draft(for: answer)
        value.result = .notApplicable
        value.openNonconformity = false
        editingDraft = value
        page = .notApplicable
    }

    private func openNonconformity(_ answer: NovaChecklistAnswer) {
        var value = draft(for: answer)
        value.result = .nonconform
        value.openNonconformity = !run.isPersonal
        editingDraft = value
        issueDescription = answer.note ?? value.note
        correctionSuggestion = ""
        selectedSeverity = nil
        page = .nonconformity
    }

    private func saveDirect(_ answer: NovaChecklistAnswer, result: NovaChecklistResult) {
        var value = draft(for: answer)
        value.result = result
        value.openNonconformity = false
        Task { await persist(value, thenAdvance: true) }
    }

    @MainActor private func persist(_ draft: NovaChecklistAnswerDraft, thenAdvance: Bool) async {
        working = true
        failure = await onAnswer(draft)
        working = false
        guard failure == nil else { return }
        localDrafts[draft.itemCode] = nil
        editingDraft = nil
        if thenAdvance {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if currentIndex < orderedAnswers.count - 1 {
                currentIndex += 1
                page = .question
            } else {
                page = .summary
            }
        }
    }

    private func tone(_ result: NovaChecklistResult) -> NovaStatus {
        switch result {
        case .conform: return .success
        case .nonconform: return .warning
        case .notApplicable: return .neutral
        }
    }
}

private struct NovaChecklistAnswerButton: View {
    let result: NovaChecklistResult
    let selected: Bool
    let working: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var status: NovaStatus {
        switch result {
        case .conform: return .success
        case .nonconform: return .warning
        case .notApplicable: return .neutral
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: result.symbol).font(.system(size: 17, weight: .semibold))
                NovaText(text: result.title, style: .buttonSm)
                Spacer()
                if selected { Image(systemName: "checkmark") }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(status.tokens.background.color(in: scheme),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? status.tokens.ink.color(in: scheme) : .clear, lineWidth: 1.5))
        }
        .buttonStyle(NovaRowPressStyle())
        .disabled(working)
        .accessibilityLabel(RDLocalization.format("localizable.nova.checklist.run.flow.bu.soruyu.1.olarak.isaretle.3e7f6459", table: .localizable, fallback: "Bu soruyu %1$@ olarak işaretle", arguments: [String(describing: result.title.lowercased())]))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct NovaChecklistQuestionExtrasScreen: View {
    @State var draft: NovaChecklistAnswerDraft
    let onBack: () -> Void
    let onSave: (NovaChecklistAnswerDraft) -> Void
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            simpleHeader("Not ve fotoğraf", back: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NovaText(text: draft.prompt, style: .bodyStrong)
                    VStack(alignment: .leading, spacing: 8) {
                        NovaText(text: "Not", style: .label)
                        TextEditor(text: $draft.note)
                            .frame(minHeight: 140).padding(8)
                            .scrollContentBackground(.hidden)
                            .background(NovaColorToken.surface.color(in: scheme),
                                in: RoundedRectangle(cornerRadius: 12))
                            .focused($focused)
                    }
                    IsgWorkspaceInlineAttachmentField(title: RDLocalization.string("localizable.nova.checklist.run.flow.fotograf.veya.belge.ekle.b1ceb55d", table: .localizable, fallback: "Fotoğraf veya belge ekle"),
                        help: "Görsel, PDF veya Office belgesi · en fazla 50 MB",
                        attachment: $draft.attachment)
                    NovaText(text: RDLocalization.string("localizable.nova.checklist.run.flow.not.ve.kanit.soruyu.yanitladiginizda.kaydedilir.fd84deec", table: .localizable, fallback: "Not ve kanıt, soruyu yanıtladığınızda kaydedilir."), style: .meta,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                }
                .padding(20).padding(.bottom, 90)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NovaButton(label: RDLocalization.string("localizable.nova.checklist.run.flow.kaydet.e1429b8e", table: .localizable, fallback: "Kaydet"), symbol: "checkmark", variant: .primary) { onSave(draft) }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(NovaColorToken.surface.color(in: scheme))
            }
        }
    }

    private func simpleHeader(_ title: String, back: @escaping () -> Void) -> some View {
        HStack {
            Button(action: back) { Label("Geri", systemImage: "chevron.left").frame(minHeight: 44) }
                .buttonStyle(NovaRowPressStyle())
            Spacer()
        }
        .overlay { NovaText(text: title, style: .label) }
        .padding(.horizontal, 16).padding(.vertical, 4)
    }
}

private struct NovaChecklistNotApplicableScreen: View {
    @State var draft: NovaChecklistAnswerDraft
    let working: Bool
    let failure: String?
    let onBack: () -> Void
    let onSave: (NovaChecklistAnswerDraft) -> Void
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NovaText(text: draft.prompt, style: .bodyStrong)
                    VStack(alignment: .leading, spacing: 8) {
                        NovaText(text: RDLocalization.string("localizable.nova.checklist.run.flow.neden.uygulanamaz.b49a6217", table: .localizable, fallback: "Neden uygulanamaz? *"), style: .label)
                        TextEditor(text: $draft.note)
                            .frame(minHeight: 150).padding(8)
                            .scrollContentBackground(.hidden)
                            .background(NovaColorToken.surface.color(in: scheme),
                                in: RoundedRectangle(cornerRadius: 12))
                            .focused($focused)
                    }
                    if let failure { NovaText(text: failure, style: .meta,
                        color: NovaColorToken.statusDangerInk.color(in: scheme)) }
                }
                .padding(20).padding(.bottom, 90)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NovaButton(label: working ? "Kaydediliyor…" : "Kaydet ve devam et", symbol: "checkmark",
                    variant: .primary, isEnabled: !draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    isLoading: working) { focused = false; onSave(draft) }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(NovaColorToken.surface.color(in: scheme))
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) { Label("Geri", systemImage: "chevron.left").frame(minHeight: 44) }
                .buttonStyle(NovaRowPressStyle())
            Spacer()
        }
        .overlay { NovaText(text: "Uygulanamaz", style: .label) }
        .padding(.horizontal, 16).padding(.vertical, 4)
    }
}

private struct NovaChecklistNonconformityScreen: View {
    @State var draft: NovaChecklistAnswerDraft
    let companyName: String?
    @Binding var description: String
    @Binding var recommendation: String
    @Binding var severity: NovaChecklistSeverity?
    let working: Bool
    let failure: String?
    let onBack: () -> Void
    let onSave: (NovaChecklistAnswerDraft) -> Void
    @FocusState private var focus: Field?
    @Environment(\.colorScheme) private var scheme
    private enum Field { case description, recommendation }

    private var canSave: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (companyName == nil || severity != nil)
            && (!draft.photoRequired || draft.attachment != nil || draft.evidenceAssetID != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        NovaText(text: "Soru", style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                        NovaText(text: draft.prompt, style: .bodyStrong)
                    }
                    editor(title: RDLocalization.string("localizable.nova.checklist.run.flow.aciklama.bcdb9738", table: .localizable, fallback: "Açıklama *"), placeholder: RDLocalization.string("localizable.nova.checklist.run.flow.tespit.edilen.durumu.yazin.c2ce044f", table: .localizable, fallback: "Tespit edilen durumu yazın…"),
                        text: $description, field: .description)
                    IsgWorkspaceInlineAttachmentField(
                        title: draft.photoRequired ? "Fotoğraf ekle *" : "Fotoğraf ekle",
                        help: "Görsel, PDF veya Office belgesi · en fazla 50 MB",
                        attachment: $draft.attachment)
                    if companyName != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            NovaText(text: RDLocalization.string("localizable.nova.checklist.run.flow.onem.b3873a61", table: .localizable, fallback: "Önem *"), style: .label)
                            ForEach(NovaChecklistSeverity.allCases) { value in
                                Button { severity = value } label: {
                                    HStack {
                                        Image(systemName: severity == value ? "largecircle.fill.circle" : "circle")
                                        NovaText(text: value.title, style: .body)
                                        Spacer()
                                    }
                                    .frame(minHeight: 44).contentShape(Rectangle())
                                }
                                .buttonStyle(NovaRowPressStyle())
                            }
                        }
                        NovaDayField(label: RDLocalization.string("localizable.nova.checklist.run.flow.duzeltme.tarihi.6adfe3d6", table: .localizable, fallback: "Düzeltme tarihi"), value: $draft.dueOn,
                            identifier: "nova.checklist.issue.due", isClearable: true)
                    }
                    editor(title: RDLocalization.string("localizable.nova.checklist.run.flow.duzeltme.onerisi.1f81d6e3", table: .localizable, fallback: "Düzeltme önerisi"), placeholder: RDLocalization.string("localizable.nova.checklist.run.flow.istege.bagli.aciklama.ekleyin.2d15404a", table: .localizable, fallback: "İsteğe bağlı açıklama ekleyin…"),
                        text: $recommendation, field: .recommendation)
                    if let companyName {
                        NovaText(text: RDLocalization.format("localizable.nova.checklist.run.flow.uygunsuzluk.kaydi.1.65921b3e", table: .localizable, fallback: "Uygunsuzluk kaydı · %1$@", arguments: [String(describing: companyName)]), style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    } else {
                        NovaText(text: RDLocalization.string("localizable.nova.checklist.run.flow.bagimsiz.kontrolde.firma.uygunsuzlugu.acilmaz.ol.4316653b", table: .localizable, fallback: "Bağımsız kontrolde firma uygunsuzluğu açılmaz; olumsuz gözlem yalnız bu kontrolde saklanır."),
                            style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    if let failure { NovaText(text: failure, style: .meta,
                        color: NovaColorToken.statusDangerInk.color(in: scheme)) }
                }
                .padding(20).padding(.bottom, 100)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NovaButton(label: working ? "Kaydediliyor…" : "Kaydet ve devam et",
                    symbol: "checkmark", variant: .primary, isEnabled: canSave,
                    isLoading: working) { save() }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(NovaColorToken.surface.color(in: scheme))
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) { Label("Geri", systemImage: "chevron.left").frame(minHeight: 44) }
                .buttonStyle(NovaRowPressStyle())
            Spacer()
        }
        .overlay { NovaText(text: "Uygunsuzluk", style: .label) }
        .padding(.horizontal, 16).padding(.vertical, 4)
    }

    private func editor(title: String, placeholder: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: title, style: .label)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    NovaText(text: placeholder, style: .meta,
                        color: NovaColorToken.textMuted.color(in: scheme))
                        .padding(.horizontal, 13).padding(.vertical, 14)
                }
                TextEditor(text: text).frame(minHeight: 120).padding(8)
                    .scrollContentBackground(.hidden).focused($focus, equals: field)
            }
            .background(NovaColorToken.surface.color(in: scheme),
                in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func save() {
        guard canSave else { return }
        focus = nil
        draft.result = .nonconform
        draft.openNonconformity = companyName != nil
        if let severity { draft.severity = severity }
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRecommendation = recommendation.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.note = cleanRecommendation.isEmpty ? cleanDescription
            : cleanDescription + "\n\nDüzeltme önerisi: " + cleanRecommendation
        onSave(draft)
    }
}
