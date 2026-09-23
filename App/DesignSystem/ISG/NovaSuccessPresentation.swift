import SwiftUI

enum NovaSuccessMessage {
    static let companyCreated = "Firma başarıyla eklendi!"
    static let companyUpdated = "Firma bilgileri başarıyla güncellendi!"
    static let companyLogoAdded = "Firma logosu başarıyla eklendi!"
    static let personnelCreated = "Tebrikler, personel eklendi!"
    static let personnelUpdated = "Personel bilgileri başarıyla güncellendi!"
    static let personnelArchived = "Personel başarıyla arşivlendi!"
    static let findingCreated = "Uygunsuzluk başarıyla eklendi!"
    static let trainingCreated = "Eğitim başarıyla eklendi!"
    static let trainingSaved = "Eğitim başarıyla kaydedildi!"
    static let emergencyPlanSaved = "Acil durum planı başarıyla kaydedildi!"
    static let periodicInspectionSaved = "Periyodik kontrol başarıyla kaydedildi!"
    static let equipmentCreated = "Ekipman başarıyla eklendi!"
    static let fileAdded = "Dosya başarıyla eklendi!"
    static func recordSaved(_ name: String) -> String { "\(name) başarıyla kaydedildi!" }

    /// Server receipts carry stable keys so a workspace mutation cannot inject
    /// presentation text. Unknown keys keep the success UI useful without
    /// exposing a backend identifier to the user.
    static func serverKey(_ key: String) -> String {
        switch key {
        case "analysis_finding_filed": return findingCreated
        case "analysis_finding_already_filed": return RDLocalization.string("localizable.nova.success.presentation.bu.uygunsuzluk.firmada.zaten.kayitli.bdfa6846", table: .localizable, fallback: "Bu uygunsuzluk firmada zaten kayıtlı.")
        case "ppe_handover_created": return recordSaved("KKD zimmeti")
        default: return RDLocalization.string("localizable.nova.success.presentation.islem.basariyla.tamamlandi.c654fd9d", table: .localizable, fallback: "İşlem başarıyla tamamlandı!")
        }
    }

    static func normalized(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return RDLocalization.string("localizable.nova.success.presentation.islem.basariyla.tamamlandi.040f01da", table: .localizable, fallback: "İşlem başarıyla tamamlandı!") }
        return value.last == "!" || value.last == "." ? value : value + "!"
    }
}

/// One session-owned event survives a form closing and is visible above an open popup.
@MainActor final class NovaSuccessStore: ObservableObject {
    struct Event: Identifiable { let id = UUID(); let text: String }
    @Published var event: Event?
    func show(_ text: String) { event = Event(text: NovaSuccessMessage.normalized(text)) }
}
private struct NovaSuccessStoreKey: EnvironmentKey { static let defaultValue: NovaSuccessStore? = nil }
extension EnvironmentValues {
    var novaSuccessStore: NovaSuccessStore? {
        get { self[NovaSuccessStoreKey.self] }
        set { self[NovaSuccessStoreKey.self] = newValue }
    }
}
struct NovaSuccessPresentation: ViewModifier {
    var account: UUID?
    @StateObject private var store = NovaSuccessStore()
    func body(content: Content) -> some View {
        content.environment(\.novaSuccessStore, store)
            .environment(\.novaCelebrate, { store.show($0) })
            .overlay { NovaSuccessOverlay(store: store) }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("isgada.mutation.succeeded"))) { event in
                guard let account, event.object as? UUID == account,
                      let message = event.userInfo?["message"] as? String else { return }
                store.show(message)
            }
    }
}
struct NovaSuccessOverlay: View {
    @ObservedObject var store: NovaSuccessStore
    @State private var appeared = false
    /// The confetti's own one-shot trigger. It used to key off `appeared`,
    /// which also drives the card's exit fade — so when the card left,
    /// `appeared` went back to `false` and the confetti's `.animation(value:)`
    /// replayed in reverse, flying every piece back toward center just as the
    /// card was fading out. Bursting is forward-only: set once on arrival,
    /// never unset, so there is nothing for the confetti to reverse into.
    @State private var burst = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Color.clear
            .overlay {
                if let event = store.event {
                    ZStack {
                        Color.black.opacity(appeared ? 0.30 : 0).ignoresSafeArea()
                        NovaCard(padding: 24) {
                            VStack(spacing: 14) {
                                HStack(spacing: 18) {
                                    Image(systemName: "sparkles").font(NovaFont.font(.sectionTitle)).foregroundStyle(.orange)
                                    Image(systemName: "checkmark.seal").font(.system(size: 44, weight: .light))
                                        .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                                    Image(systemName: "party.popper").font(NovaFont.font(.sectionTitle)).foregroundStyle(.purple)
                                }.accessibilityHidden(true)
                                    .overlay {
                                        if !reduceMotion {
                                            ForEach(0..<12) { index in
                                                RoundedRectangle(cornerRadius: 1)
                                                    .fill(index.isMultiple(of: 3) ? NovaColorToken.accent.color(in: scheme) : NovaColorToken.text.color(in: scheme).opacity(0.3))
                                                    .frame(width: 4, height: 7)
                                                    .rotationEffect(.degrees(burst ? Double(index * 37) : 0))
                                                    .offset(x: burst ? CGFloat(index - 6) * 17 : 0, y: burst ? CGFloat((index * 23) % 80) - 35 : 0)
                                                    .opacity(burst ? 0 : 0.9)
                                                    .animation(.easeOut(duration: 1.4).delay(Double(index % 3) * 0.06), value: burst)
                                            }
                                        }
                                    }
                                NovaText(text: "Tebrikler", style: .sectionTitle)
                                NovaText(text: event.text, style: .cardTitle)
                                    .multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity)
                        }.frame(maxWidth: 300).padding(24)
                            .scaleEffect(reduceMotion || appeared ? 1 : 0.9)
                            .opacity(appeared ? 1 : 0)
                    }
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.isModal)
                    .accessibilityIdentifier("nova.success")
                    .task(id: event.id) {
                        appeared = false
                        burst = false
                        // Saving a record is the rare, high-emotion moment this
                        // app has, so it gets the one spring with overshoot and
                        // the one success haptic — fired on the same frame as
                        // the visual, before any await.
                        withAnimation(NovaMotion.gated(NovaMotion.celebrate, reduceMotion: reduceMotion)) {
                            appeared = true
                        }
                        if !reduceMotion { burst = true }
                        NovaHaptics.success()
                        UIAccessibility.post(notification: .announcement, argument: event.text)
                        do { try await Task.sleep(nanoseconds: 2_300_000_000) } catch { return }
                        guard store.event?.id == event.id else { return }
                        // It used to disappear on a single frame. It leaves the
                        // way it arrived instead, so the screen underneath does
                        // not snap back into view.
                        withAnimation(NovaMotion.easeOut(NovaMotion.Duration.popover)) { appeared = false }
                        do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
                        if store.event?.id == event.id { store.event = nil }
                    }
                }
            }.allowsHitTesting(store.event != nil)
    }
}
