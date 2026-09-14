import SwiftUI

/// The legacy management view remains the fallback when rollout/RPC/auth is unavailable.
struct NovaCompanyManagementGate<Fallback: View>: View {
    let onClose: () -> Void
    @ViewBuilder let fallback: () -> Fallback
    @StateObject private var controller = NovaWorkspaceController()
    @State private var legacyRequested = false
    @State private var sceneRevalidation = NovaSceneRevalidation()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if controller.resolving {
                NovaPageSurface { VStack(spacing: 18) { ProgressView(); NovaText(text: RDLocalization.string("localizable.nova.company.management.gate.firma.erisimi.dogrulaniyor.3bf732f2", table: .localizable, fallback: "Firma erişimi doğrulanıyor…")); NovaButton(label: RDLocalization.string("localizable.nova.company.management.gate.kapat.3148ed17", table: .localizable, fallback: "Kapat"), symbol: "xmark", variant: .surface, action: onClose) }.padding(18) }
            } else if controller.isAvailable && !legacyRequested {
                NavigationStack {
                    if let scope = controller.scope {
                        NovaCompanyWorkspace(scope: scope, companyName: controller.capability?.company_name ?? "Firma", canWrite: controller.canWrite,
                            personnel: controller.personnelClient, directory: controller.directoryClient, onBack: { controller.select(nil) })
                    } else {
                        VStack(spacing: 0) {
                            NovaCompanyDestination(host: Binding(get: { controller.host }, set: { _ in }),
                                loadCompanies: { try await loadNovaOwnedCompanies(includeArchived: $0) }, includeArchived: true, onSelect: controller.select, onBack: onClose)
                            NovaButton(label: RDLocalization.string("localizable.nova.company.management.gate.firma.ekle.duzenle.005d0121", table: .localizable, fallback: "Firma ekle / düzenle"), symbol: "building.2", variant: .surface) { legacyRequested = true }.padding(18)
                        }.background(NovaColorToken.canvas.color(in: .light))
                    }
                }.id(controller.host.navigation.epoch)
                .preferredColorScheme(.light)
            } else {
                VStack(spacing: 0) {
                    if legacyRequested && controller.isAvailable {
                        NovaButton(label: RDLocalization.string("localizable.nova.company.gate.back.to.management", table: .localizable, fallback: "Personel ve işyeri yönetimine dön"), symbol: "chevron.left", variant: .surface) { legacyRequested = false; controller.select(nil) }.padding(12)
                    }
                    fallback()
                }
            }
        }
        .task { await controller.observe() }
        .onChange(of: scenePhase) { phase in
            if sceneRevalidation.update(isBackground: phase == .background, isActive: phase == .active) { controller.refresh() }
        }
        .onChange(of: controller.host.identity) { _ in legacyRequested = false }
    }
}

struct NovaCompanyWorkspace: View {
    let scope: NovaPersonnelScope
    let companyName: String
    let canWrite: Bool
    let personnel: NovaPersonnelClient
    let directory: NovaDirectoryClient
    let onBack: () -> Void
    var loadSummary: (() async throws -> NovaPilotCompanySummary?)? = nil
    @State private var summary: NovaPilotCompanySummary?
    @State private var summaryFailed = false
    @State private var summaryRevision = UUID()
    @Environment(\.colorScheme) private var scheme
    @State private var sheet: Sheet?
    @State private var personnelPage = false
    @State private var companyExpanded = false
    @State private var expandedSections = Set<NovaCompanySection>()
    private enum Sheet: Identifiable {
        case personnel, addPersonnel, editCompany, deleteCompany, directory(NovaDirectoryKind)
        var id: String { switch self { case .personnel: return "personnel"; case .addPersonnel: return "add-personnel"; case .editCompany: return "edit-company"; case .deleteCompany: return "delete-company"; case .directory(let kind): return kind.rawValue } }
    }
    private var progress: NovaCompanyProgress {
        // Empty headings are visibly incomplete in the pilot preview. This keeps
        // the score and status pills useful before mutation endpoints are wired.
        var result = NovaCompanyProgress(states: Dictionary(uniqueKeysWithValues: NovaCompanySection.allCases.map { ($0, NovaCompletionState.missing) }))
        if let summary { result.states[.personnel] = summary.personnel_count > 0 ? .complete : .missing }
        return result
    }
    var body: some View {
        NovaPageSurface {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        NovaPageHeading(title: RDLocalization.string("localizable.nova.company.detail.title", table: .localizable, fallback: "Firma Detayı"), onBack: onBack)
                        companyCard
                        HStack(spacing: 10) {
                            NovaButton(label: RDLocalization.string("localizable.nova.company.management.gate.dosya.ekle.b9bb8c93", table: .localizable, fallback: "Dosya Ekle"), symbol: "folder.badge.plus", isEnabled: false) {}
                            NovaButton(label: RDLocalization.string("localizable.nova.company.management.gate.evrak.ekle.386b7009", table: .localizable, fallback: "Evrak Ekle"), symbol: "doc.badge.plus", isEnabled: false) {}
                        }
                        if !canWrite { NovaCard(padding: 16) { Label(RDLocalization.string("localizable.nova.company.management.gate.salt.okunur.kayitlariniz.korunuyor.2cc72e1b", table: .localizable, fallback: "Salt okunur · kayıtlarınız korunuyor"), systemImage: "lock"); NovaText(text: RDLocalization.string("localizable.nova.company.management.gate.yeni.kayit.ve.duzenleme.su.anda.kullanilamiyor.d83e8253", table: .localizable, fallback: "Yeni kayıt ve düzenleme şu anda kullanılamıyor."), style: .metaQuiet) } }
                        NovaCompanyAccordion(title: RDLocalization.string("localizable.nova.workspace.company.info", table: .localizable, fallback: "Firma Bilgileri"), symbol: "building.2", expanded: $companyExpanded) {
                            ForEach([NovaCompanySection.logo, .personnel]) { section in
                                sectionView(section, outlinesWhenExpanded: false)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                            ForEach([NovaDirectoryKind.workplaces, .departments, .jobs, .contractors], id: \.self) { kind in
                                entry(kind.title, kind.symbol, tone: kind == .departments ? .statusWarningInk : .accentInk) { sheet = .directory(kind) }
                            }
                            }
                        }
                        ForEach(Array(NovaCompanySection.allCases.dropFirst(2))) { section in sectionView(section) }
                    }.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 18)
                }
                .task(id: summaryRevision) {
                    summary = nil; summaryFailed = false
                    guard let loadSummary else { return }
                    do { let value = try await loadSummary(); try Task.checkCancellation(); summary = value }
                    catch { if !Task.isCancelled { summaryFailed = true } }
                }
        }.navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $personnelPage) {
            NovaPersonnelDestination(scope: scope, companyName: companyName, client: personnel,
                onBack: { personnelPage = false }, directory: directory, canWrite: canWrite, preview: false)
        }
        .fullScreenCover(item: $sheet, onDismiss: { summaryRevision = UUID() }) { destination in
            NovaPopup {
            NavigationStack {
                switch destination {
                case .editCompany:
                    NovaCompanyVisualEditor(name: summary?.name ?? companyName, sector: summary?.sector ?? "", email: summary?.email ?? "", hazard: summary?.hazard_class ?? "medium")
                case .deleteCompany:
                    NovaCompanyVisualDelete(name: summary?.name ?? companyName)
                case .addPersonnel:
                    NovaPersonnelCreateSheet(scope: scope, companyName: companyName, client: personnel)
                case .personnel:
                    NovaPersonnelDestination(scope: scope, companyName: companyName, client: personnel,
                        onBack: { sheet = nil }, directory: directory, canWrite: canWrite, preview: true,
                        onShowAll: { sheet = nil; personnelPage = true })
                case .directory(let kind):
                    NovaDirectoryDestination(scope: scope, kind: kind, client: directory,
                        onBack: { sheet = nil }, canWrite: canWrite)
                }
            }
            }
        }
    }
    private func sectionView(_ section: NovaCompanySection, outlinesWhenExpanded: Bool = true) -> some View {
        NovaCompanyAccordion(title: section.title, symbol: section.symbol, state: progress[section],
            identifier: "company.section.\(section.rawValue)",
            outlinesWhenExpanded: outlinesWhenExpanded,
            expanded: Binding(get: { expandedSections.contains(section) }, set: { value in
                if value { expandedSections.insert(section) } else { expandedSections.remove(section) }
            })) {
                if section == .personnel {
                    HStack(spacing: 8) {
                        NovaButton(label: "Personeller", symbol: "person.2", variant: .muted) { sheet = .personnel }
                        NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.personel.ekle.565c83dd", table: .localizable, fallback: "Personel Ekle"), symbol: "plus", isEnabled: canWrite) { sheet = .addPersonnel }
                            .accessibilityIdentifier("company.personnel.add")
                    }
                } else {
                    NovaHelpHint(text: RDLocalization.string("localizable.nova.workspace.section.pending", table: .localizable, fallback: "Bu bölümün kayıt servisi henüz bağlanmadı. Eksik veya tamamlandı bilgisi doğrulanamıyor."))
                }
            }
    }
    private var companyCard: some View {
        NovaCard(padding: 14, tint: NovaColorToken.surfaceMuted.color(in: scheme)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            NovaIcon(symbol: "building.2", size: 24).foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                            NovaSizedText(text: summary?.name ?? companyName, size: 17, weight: "Bold")
                        }
                        // Fixed two-column grid: six compact tags in three rows.
                        LazyVGrid(columns: [GridItem(.flexible(minimum: 70), spacing: 6), GridItem(.flexible(minimum: 70), spacing: 6)], alignment: .leading, spacing: 4) {
                            badge("Tehlike", value: summary.flatMap { CompanyHazardClass(rawValue: $0.hazard_class)?.title }, icon: "exclamationmark.triangle", tone: .statusWarningInk)
                            badge(RDLocalization.string("localizable.nova.company.sector", table: .localizable, fallback: "Sektör"), value: summary?.sector, icon: "square.grid.2x2", tone: .statusInfoInk)
                            badge("Personel", value: summary.map { String($0.personnel_count) }, icon: "person.2", tone: .accentInk)
                            badge("Uygunsuzluk", value: summary?.finding_count.map(String.init), icon: "risk", tone: .statusDangerInk)
                            badge("Evrak", value: summary?.document_count.map(String.init), icon: "doc.text", tone: .statusInfoInk)
                            badge("Tamamlanma", value: progress.score.map(String.init), icon: "chart.bar", tone: .statusSuccessInk)
                        }
                    }
                    Spacer(minLength: 0)
                    NovaCompanyScoreRing(progress: progress).accessibilityIdentifier("company.score.ring")
                }
                HStack(spacing: 4) {
                    Spacer()
                    Button { sheet = .editCompany } label: { Image(systemName: "pencil").frame(width: 36, height: 30) }
                        .accessibilityLabel(RDLocalization.string("localizable.nova.visual.2", table: .localizable, fallback: "Güncelle")).accessibilityIdentifier("company.edit")
                    Button { sheet = .deleteCompany } label: { Image(systemName: "trash").foregroundStyle(.red).frame(width: 36, height: 30) }
                        .accessibilityLabel(RDLocalization.string("localizable.nova.visual.3", table: .localizable, fallback: "Sil")).accessibilityIdentifier("company.delete")
                }.buttonStyle(.plain)
                if summaryFailed {
                    NovaButton(label: RDLocalization.string("localizable.nova.company.summary.retry", table: .localizable, fallback: "Özeti tekrar yükle"), symbol: "arrow.clockwise", variant: .surface) { summaryRevision = UUID() }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func badge(_ label: String, value: String?, icon: String, tone: NovaColorToken) -> some View {
        HStack(spacing: 5) {
            NovaIcon(symbol: icon, size: 14).foregroundStyle(tone.color(in: scheme))
            Text(value ?? "—").font(.custom("PlusJakartaSans-Medium", size: 10)).lineLimit(1).minimumScaleFactor(0.75)
        }.padding(.vertical, 1).frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label) · \(value ?? "—")")
    }
    private func entry(_ title: String, _ icon: String, tone: NovaColorToken, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NovaCard(padding: 9) {
                HStack(spacing: 9) {
                    NovaIcon(symbol: icon, size: 19).foregroundStyle(tone.color(in: scheme))
                    Text(title).font(.custom("PlusJakartaSans-SemiBold", size: 12))
                    Spacer(minLength: 0)
                    NovaIcon(symbol: "chevron.right", size: 12)
                }.frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            }
        }.buttonStyle(.plain)
    }
}
