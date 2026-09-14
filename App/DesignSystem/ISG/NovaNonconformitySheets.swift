import SwiftUI

/// Shared shape for the small record popups: a title, a body, one green
/// control, and a failure line that says what the server actually refused.
private struct NovaRecordSheetShell<Content: View>: View {
    let title: String
    let hint: String
    let action: String
    let symbol: String
    let isEnabled: Bool
    let run: () async throws -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaText(text: title, style: .sheetTitle)
                if !hint.isEmpty { NovaHelpHint(text: hint) }
                content()
                if let error {
                    NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
                }
                NovaButton(label: action, symbol: symbol, isEnabled: isEnabled && !busy, isLoading: busy) {
                    Task {
                        busy = true; error = nil
                        do { try await run() }
                        catch let failure as NovaNonconformityFailure { error = NovaNonconformityWords.failure(failure) }
                        catch {
                            self.error = RDLocalization.string("localizable.nova.nonconformity.error.save", table: .localizable,
                                fallback: "Kayıt açılamadı. Bilgileri kontrol edip aynı işlemi tekrar deneyin.")
                        }
                        busy = false
                    }
                }.accessibilityIdentifier("record.sheet.run")
            }.padding(20).novaPopupContentSize()
        }.background(NovaKeyboardDismissArea())
    }
}

/// Edits only the detail of an existing record. Title, severity and workplace
/// belong to the record itself and are not touched here.
struct NovaNonconformityDetailSheet: View {
    @State var draft: NovaNonconformityDetailDraft
    let save: (NovaNonconformityDetailDraft) async throws -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaRecordSheetShell(
            title: RDLocalization.string("localizable.nova.nonconformity.detail.title", table: .localizable, fallback: "Kayıt detayı"),
            hint: RDLocalization.string("localizable.nova.nonconformity.detail.hint", table: .localizable,
                fallback: "Ekranda gördüğünüz detayın tamamı kaydedilir; boşalttığınız alan kayıttan da silinir."),
            action: RDLocalization.string("localizable.nova.analysis.edit.save", table: .localizable, fallback: "Değişiklikleri kaydet"),
            symbol: "checkmark",
            isEnabled: draft.score.isEmpty || draft.score.isComplete,
            run: { try await save(draft) }) {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    area(RDLocalization.string("localizable.nova.manual.hazard.description", table: .localizable, fallback: "Açıklama"), $draft.description, id: "description")
                    area(RDLocalization.string("localizable.nova.manual.hazard.measure", table: .localizable, fallback: "Önlem"), $draft.measure, id: "measure")
                    area(RDLocalization.string("localizable.nova.manual.step.legislation", table: .localizable, fallback: "Mevzuat bilgisi"), $draft.legislation, id: "legislation")
                    field(RDLocalization.string("localizable.nova.manual.step.responsible", table: .localizable, fallback: "Firma sorumlusu"), $draft.responsible, id: "responsible")
                }
            }
            NovaRiskScoreEditor(score: $draft.score)
        }
    }

    private func field(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextField(label, text: text).font(.custom("PlusJakartaSans-Medium", size: 14))
                .frame(minHeight: 36).accessibilityIdentifier("record.detail.\(id)")
        }
    }
    private func area(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextEditor(text: text).font(.custom("PlusJakartaSans-Medium", size: 14))
                .frame(minHeight: 70).scrollContentBackground(.hidden)
                .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("record.detail.\(id)")
        }
    }
}

struct NovaCorrectiveActionSheet: View {
    let save: (String, String, String?) async throws -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var description = ""
    @State private var assignee = ""

    var body: some View {
        NovaRecordSheetShell(
            title: RDLocalization.string("localizable.nova.nonconformity.actions.title", table: .localizable, fallback: "Düzeltici aksiyonlar"),
            hint: RDLocalization.string("localizable.nova.nonconformity.actions.hint", table: .localizable,
                fallback: "Aksiyonun sorumlusu bir uygulama kullanıcısı değildir; yalnız kayıtta görünür."),
            action: RDLocalization.string("localizable.nova.nonconformity.actions.add", table: .localizable, fallback: "Ekle"),
            symbol: "plus",
            isEnabled: !description.trimmingCharacters(in: .whitespaces).isEmpty,
            run: { try await save(description, assignee, nil) }) {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.actions.description", table: .localizable, fallback: "Yapılacak iş"),
                        style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
                    TextEditor(text: $description).font(.custom("PlusJakartaSans-Medium", size: 14))
                        .frame(minHeight: 76).scrollContentBackground(.hidden)
                        .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("record.action.description")
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.actions.assignee", table: .localizable, fallback: "Sorumlu"),
                        style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
                    TextField(RDLocalization.string("localizable.nova.nonconformity.actions.assignee", table: .localizable, fallback: "Sorumlu"), text: $assignee)
                        .font(.custom("PlusJakartaSans-Medium", size: 14)).frame(minHeight: 36)
                        .accessibilityIdentifier("record.action.assignee")
                }
            }
        }
    }
}

struct NovaVerificationSheet: View {
    let save: (Bool, String) async throws -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var accepted = true
    @State private var note = ""

    var body: some View {
        NovaRecordSheetShell(
            title: RDLocalization.string("localizable.nova.nonconformity.verification.title", table: .localizable, fallback: "Uzman doğrulaması"),
            hint: RDLocalization.string("localizable.nova.nonconformity.verification.hint", table: .localizable,
                fallback: "Reddedilen doğrulama kaydı kapatmaz; yeni bir döngü başlatır."),
            action: RDLocalization.string("localizable.nova.nonconformity.verification.add", table: .localizable, fallback: "Doğrula"),
            symbol: "checkmark.shield", isEnabled: true,
            run: { try await save(accepted, note) }) {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $accepted) {
                        Text(verbatim: RDLocalization.string("localizable.nova.nonconformity.verification.accepted", table: .localizable, fallback: "Kabul")).tag(true)
                        Text(verbatim: RDLocalization.string("localizable.nova.nonconformity.verification.rejected", table: .localizable, fallback: "Ret")).tag(false)
                    }.pickerStyle(.segmented).accessibilityIdentifier("record.verify.outcome")
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.verification.note", table: .localizable, fallback: "Not"),
                        style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
                    TextEditor(text: $note).font(.custom("PlusJakartaSans-Medium", size: 14))
                        .frame(minHeight: 70).scrollContentBackground(.hidden)
                        .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("record.verify.note")
                }
            }
        }
    }
}

/// Asks for exactly what this edge needs, and nothing else. A reason the
/// server will refuse as too short is refused here first.
struct NovaTransitionSheet: View {
    let edge: NovaNonconformityEdge
    let save: (String, String) async throws -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var reason = ""
    @State private var assignee = ""

    private var ready: Bool {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if edge.requiresReason && trimmedReason.count < 5 { return false }
        if edge.requiresAssignee && assignee.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return true
    }

    var body: some View {
        NovaRecordSheetShell(
            title: String(format: RDLocalization.string("localizable.nova.nonconformity.move.title", table: .localizable,
                fallback: "Durumu %@ yap"), NovaNonconformityWords.state(edge.to.rawValue)),
            hint: edge.requiresReason
                ? RDLocalization.string("localizable.nova.nonconformity.move.reason.hint", table: .localizable,
                    fallback: "Bu geçiş gerekçesiz kaydedilmez; en az beş karakter yazın.")
                : "",
            action: RDLocalization.string("localizable.nova.nonconformity.move.action", table: .localizable, fallback: "Geçişi kaydet"),
            symbol: "arrow.right", isEnabled: ready,
            run: { try await save(reason, assignee) }) {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    if edge.requiresAssignee {
                        NovaText(text: RDLocalization.string("localizable.nova.nonconformity.move.assignee", table: .localizable, fallback: "Atanan kişi"),
                            style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
                        TextField(RDLocalization.string("localizable.nova.nonconformity.move.assignee", table: .localizable, fallback: "Atanan kişi"), text: $assignee)
                            .font(.custom("PlusJakartaSans-Medium", size: 14)).frame(minHeight: 36)
                            .accessibilityIdentifier("record.move.assignee")
                    }
                    NovaText(text: edge.requiresReason
                        ? RDLocalization.string("localizable.nova.nonconformity.move.reason.required", table: .localizable, fallback: "Gerekçe *")
                        : RDLocalization.string("localizable.nova.nonconformity.move.reason", table: .localizable, fallback: "Gerekçe"),
                        style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
                    TextEditor(text: $reason).font(.custom("PlusJakartaSans-Medium", size: 14))
                        .frame(minHeight: 70).scrollContentBackground(.hidden)
                        .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("record.move.reason")
                }
            }
        }
    }
}
