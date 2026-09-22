import PhotosUI
import SwiftUI
import UIKit

struct CompanyPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    static func presentationDetents(for accessTier: SubscriptionTier, allowNoCompany: Bool = true) -> Set<PresentationDetent> {
        _ = accessTier
        _ = allowNoCompany
        return [.medium, .large]
    }

    let title: String
    let accessTier: SubscriptionTier
    var selectedCompanyID: UUID?
    var allowNoCompany: Bool = true
    var allowsSelection: Bool = true
    var startsInCreateMode: Bool = false
    var onSelect: (Company?) -> Void
    var onPaywall: () -> Void

    @State private var companies: [Company] = []
    @State private var isLoading = false
    @State private var loadErrorMessage: String?
    @State private var errorMessage: String?
    @State private var editorDraft = CompanyDraft()
    @State private var editorLogoImage: UIImage?
    @State private var isEditorPresented = false
    @State private var pendingArchive: Company?
    @State private var didAutoPresentCreateMode = false
    #if DEBUG
    @State private var fixtureCompanies: [Company] = []
    #endif

    var body: some View {
        NavigationStack {
            Group {
                if accessTier.isPaid {
                    paidContent
                        .padding(20)
                        .padding(.bottom, 14)
                } else {
                    ScrollView(showsIndicators: false) {
                        lockedContent
                            .padding(20)
                            .padding(.bottom, 24)
                    }
                }
            }
            .background(Color.rdPaper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("company_picker.root")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    RDModalCloseButton {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadCompanies()
            guard startsInCreateMode, accessTier.isPaid, !didAutoPresentCreateMode else { return }
            didAutoPresentCreateMode = true
            presentEditor(CompanyDraft())
        }
        .sheet(isPresented: $isEditorPresented) {
            CompanyEditorSheet(
                draft: editorDraft,
                selectedLogoImage: $editorLogoImage,
                onSave: { saved, logo in
                    isEditorPresented = false
                    await save(saved, logo: logo)
                },
                onClose: { isEditorPresented = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            RDLocalization.string("localizable.company.picker.sheet.firmayi.arsivle.64554b03", table: .localizable, fallback: "Firmayı arşivle?"),
            isPresented: Binding(
                get: { pendingArchive != nil },
                set: { if !$0 { pendingArchive = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingArchive {
                Button(RDLocalization.string("localizable.company.picker.sheet.arsivle.e740a0ce", table: .localizable, fallback: "Arşivle"), role: .destructive) {
                    archive(pendingArchive)
                }
            }
            Button(RDLocalization.string("localizable.company.picker.sheet.vazgec.a83075ac", table: .localizable, fallback: "Vazgeç"), role: .cancel) {
                pendingArchive = nil
            }
        } message: {
            Text(RDLocalization.string("localizable.company.picker.sheet.eski.analiz.ve.rapor.baglantilari.korunur.firma..3ddbac8b", table: .localizable, fallback: "Eski analiz ve rapor bağlantıları korunur; firma yeni seçimlerde görünmez."))
        }
        .alert(RDLocalization.string("localizable.company.picker.sheet.firma.islemi.tamamlanamadi.4713d6a7", table: .localizable, fallback: "Firma işlemi tamamlanamadı"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(RDLocalization.string("localizable.company.picker.sheet.tamam.f3dc324e", table: .localizable, fallback: "Tamam")) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var paidContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if allowNoCompany {
                noCompanyRow
            }

            if isLoading {
                loadingCard
            } else if let loadErrorMessage {
                if shouldShowBlockingLoadError {
                    loadErrorCard(loadErrorMessage)
                } else {
                    quietRetryButton
                }
            } else if companies.isEmpty {
                if !allowNoCompany {
                    emptyCard
                }
            } else {
                companyList
            }

            addCompanyButton
        }
    }

    private var shouldShowBlockingLoadError: Bool {
        !allowNoCompany
    }

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "building.2.crop.circle")
                .font(RDTypography.font(size: RDFontScale.size(32), weight: .semibold))
                .foregroundStyle(Color.rdPlanPlus)
                .frame(width: 64, height: 64)
                .background(Color.rdPlanPlusSoft)
                .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 7) {
                Text(RDLocalization.string("localizable.company.picker.sheet.firma.arsivi.plus.ve.pro.da.db83145a", table: .localizable, fallback: "Firma arşivi Plus ve Pro’da"))
                    .font(RDTypography.font(size: RDFontScale.size(20), weight: .semibold))
                    .foregroundStyle(Color.rdBlack)
                Text(
                    RDLanguage.current == .turkish
                        ? RDLocalization.string("localizable.company.picker.sheet.analizlerini.firmalara.bagla.raporlarini.firma.l.0124f450", table: .localizable, fallback: "Analizlerini firmalara bağla, raporlarını firma logosu ve tehlike sınıfıyla paylaş.")
                        : RDLocalization.string("localizable.company.picker.sheet.link.analyses.to.companies.and.share.reports.wit.5472f22c", table: .localizable, fallback: "Analizleri şirketlere bağlayın ve raporları şirket bağlamı ve markalamayla paylaşın.")
                )
                    .font(RDTypography.font(size: RDFontScale.size(13), weight: .regular))
                    .foregroundStyle(Color.rdSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }

            RDButton(title: RDLocalization.string("localizable.company.picker.sheet.planlari.incele.30a8c8b4", table: .localizable, fallback: "Planları incele"), style: .detect, icon: "arrow.up.circle.fill") {
                dismiss()
                onPaywall()
            }
            .accessibilityIdentifier("company_picker.paywall")
        }
        .padding(16)
        .background(Color.rdWhite)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.rdLine, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var quietRetryButton: some View {
        Button {
            Task { await loadCompanies() }
        } label: {
            Label(RDLocalization.string("localizable.company.picker.sheet.firmalari.yenile.a94d30d6", table: .localizable, fallback: "Firmaları yenile"), systemImage: "arrow.clockwise")
                .font(RDTypography.font(size: RDFontScale.size(12.5), weight: .semibold))
                .foregroundStyle(Color.rdSlate)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.rdFog.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(RDLocalization.string("localizable.company.picker.sheet.firmalar.yukleniyor.f6abf38c", table: .localizable, fallback: "Firmalar yükleniyor"))
                .font(RDTypography.font(size: RDFontScale.size(13), weight: .medium))
                .foregroundStyle(Color.rdSlate)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.rdWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(RDLocalization.string("localizable.company.picker.sheet.henuz.firma.yok.6eb914f0", table: .localizable, fallback: "Henüz firma yok"))
                .font(RDTypography.font(size: RDFontScale.size(15), weight: .semibold))
                .foregroundStyle(Color.rdBlack)
            Text(allowNoCompany ? RDLocalization.string("localizable.company.picker.sheet.istersen.firma.eklemeden.devam.edebilir.veya.ilk.8e98ae0a", table: .localizable, fallback: "İstersen firma eklemeden devam edebilir veya ilk firmayı buradan ekleyebilirsin.") : RDLocalization.string("localizable.company.picker.sheet.ilk.firmayi.buradan.ekleyip.analiz.veya.raporla..04afdaa5", table: .localizable, fallback: "İlk firmayı buradan ekleyip analiz veya raporla eşleştirebilirsin."))
                .font(RDTypography.font(size: RDFontScale.size(12), weight: .regular))
                .foregroundStyle(Color.rdSlate)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.rdWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func loadErrorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(RDTypography.font(size: RDFontScale.size(15), weight: .semibold))
                    .foregroundStyle(Color.rdCriticalText)
                    .frame(width: 34, height: 34)
                    .background(Color.rdCriticalBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(RDLocalization.string("localizable.company.picker.sheet.firmalar.yuklenemedi.9ecbeff1", table: .localizable, fallback: "Firmalar yüklenemedi"))
                        .font(RDTypography.font(size: RDFontScale.size(14), weight: .semibold))
                        .foregroundStyle(Color.rdBlack)
                    Text(message)
                        .font(RDTypography.font(size: RDFontScale.size(11.5)))
                        .foregroundStyle(Color.rdSlate)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task { await loadCompanies() }
                } label: {
                    Label(RDLocalization.string("localizable.company.picker.sheet.tekrar.dene.5c9f2cfe", table: .localizable, fallback: "Tekrar dene"), systemImage: "arrow.clockwise")
                        .font(RDTypography.font(size: RDFontScale.size(12.5), weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .foregroundStyle(Color.rdBlack)
                        .background(Color.rdFog)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                if allowNoCompany {
                    Button {
                        guard allowsSelection else { return }
                        onSelect(nil)
                        dismiss()
                    } label: {
                        Text(RDLocalization.string("localizable.company.picker.sheet.firma.olmadan.devam.et.e0933905", table: .localizable, fallback: "Firma olmadan devam et"))
                            .font(RDTypography.font(size: RDFontScale.size(12.5), weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .foregroundStyle(Color.white)
                            .background(Color.rdOnyx)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(Color.rdWhite)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.rdCritical.opacity(0.26), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var noCompanyRow: some View {
        Button {
            guard allowsSelection else { return }
            onSelect(nil)
            dismiss()
        } label: {
            rowContent(
                icon: "minus.circle",
                title: RDLocalization.string("localizable.company.picker.sheet.firma.olmadan.devam.et.9441e553", table: .localizable, fallback: "Firma olmadan devam et"),
                subtitle: RDLocalization.string("localizable.company.picker.sheet.istersen.rapor.asamasinda.secebilirsin.fb445a25", table: .localizable, fallback: "İstersen rapor aşamasında seçebilirsin."),
                isSelected: selectedCompanyID == nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("company_picker.no_company")
    }

    private var companyList: some View {
        ScrollView(showsIndicators: companies.count > visibleCompanyLimit) {
            LazyVStack(spacing: 10) {
                ForEach(companies) { company in
                    companyRow(company)
                }
            }
        }
        .frame(maxHeight: companyListMaxHeight)
    }

    private func companyRow(_ company: Company) -> some View {
        HStack(spacing: 8) {
            Button {
                guard allowsSelection else { return }
                onSelect(company)
                dismiss()
            } label: {
                rowContent(
                    icon: "building.2",
                    title: company.name,
                    subtitle: company.listSubtitle,
                    isSelected: selectedCompanyID == company.id
                )
            }
            .buttonStyle(.plain)

            Menu {
                Button(RDLocalization.string("localizable.company.picker.sheet.duzenle.1b01b979", table: .localizable, fallback: "Düzenle")) {
                    presentEditor(CompanyDraft(
                        id: company.id,
                        name: company.name,
                        hazardClass: company.hazardClass,
                        logoPath: company.logoPath,
                        address: company.address ?? "",
                        city: company.city ?? "",
                        phone: company.phone ?? "",
                        naceCode: company.naceCode ?? "",
                        workplaceRegistryNo: company.workplaceRegistryNo ?? "",
                        workplaceProfile: company.workplaceProfile,
                        workplaceProfiles: company.workplaceProfiles ?? (company.workplaceProfile.map { [$0] } ?? []),
                        responsibleContacts: company.responsibleContacts ?? [],
                        departments: company.departments ?? (company.department.map { [$0] } ?? []),
                        contactPerson: company.contactPerson ?? "",
                        department: company.department ?? "",
                        defaultResponsible: company.defaultResponsible ?? "",
                        defaultDueDaysText: company.defaultDueDays.map(String.init) ?? ""
                    ))
                }
                Button(RDLocalization.string("localizable.company.picker.sheet.arsivle.8d9aafc3", table: .localizable, fallback: "Arşivle"), role: .destructive) {
                    pendingArchive = company
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(RDTypography.font(size: RDFontScale.size(14), weight: .semibold))
                    .foregroundStyle(Color.rdSlate)
                    .frame(width: 40, height: 48)
                    .background(Color.rdWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
            }
            .accessibilityLabel(RDLocalization.format("localizable.company.picker.sheet.1.islemleri.b4ccbb3f", table: .localizable, fallback: "%1$@ işlemleri", arguments: [String(describing: company.name)]))
        }
    }

    private func presentEditor(_ draft: CompanyDraft) {
        editorDraft = draft
        editorLogoImage = nil
        isEditorPresented = true
    }

    private var addCompanyButton: some View {
        Button {
            presentEditor(CompanyDraft())
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "plus.circle.fill")
                    .font(RDTypography.font(size: RDFontScale.size(15), weight: .semibold))
                Text(companies.count >= companyLimit ? RDLocalization.string("localizable.company.picker.sheet.firma.limiti.doldu.ff0873d2", table: .localizable, fallback: "Firma limiti doldu") : RDLocalization.string("localizable.company.picker.sheet.yeni.firma.ekle.96174dc6", table: .localizable, fallback: "Yeni firma ekle"))
                    .font(RDTypography.font(size: RDFontScale.size(14), weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundStyle(addCompanyForeground)
            .background(addCompanyBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(allowNoCompany ? Color.rdLine : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color.rdOnyx.opacity(allowNoCompany ? 0 : 0.12), radius: 10, x: 0, y: 5)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("company_picker.add")
        }
        .buttonStyle(RDPressableButtonStyle())
        .disabled(companies.count >= companyLimit)
        .opacity(companies.count >= companyLimit ? 0.58 : 1)
        .accessibilityLabel(addCompanyAccessibilityLabel)
        .accessibilityIdentifier("company_picker.add")
    }

    private var addCompanyAccessibilityLabel: String {
        #if DEBUG
        if Self.usesUITestCompanyFixtures {
            return "company_picker.add"
        }
        #endif
        return companies.count >= companyLimit ? RDLocalization.string("localizable.company.picker.sheet.firma.limiti.doldu.e6596da1", table: .localizable, fallback: "Firma limiti doldu") : RDLocalization.string("localizable.company.picker.sheet.yeni.firma.ekle.15077fc2", table: .localizable, fallback: "Yeni firma ekle")
    }

    private var addCompanyForeground: Color {
        allowNoCompany ? Color.rdBlack : .white
    }

    private var addCompanyBackground: Color {
        allowNoCompany ? Color.rdWhite : Color.rdOnyx
    }

    private func rowContent(icon: String, title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(RDTypography.font(size: RDFontScale.size(15), weight: .semibold))
                .foregroundStyle(isSelected ? Color.rdGreenDark : Color.rdSlate)
                .frame(width: 34, height: 34)
                .background(isSelected ? Color.rdGreenSoft : Color.rdFog)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RDTypography.font(size: RDFontScale.size(13), weight: .medium))
                    .foregroundStyle(Color.rdBlack)
                    .lineLimit(1)
                Text(subtitle)
                    .font(RDTypography.font(size: RDFontScale.size(11)))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(RDTypography.font(size: RDFontScale.size(17), weight: .semibold))
                .foregroundStyle(isSelected ? Color.rdGreen : Color.rdSlate.opacity(0.35))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.rdWhite)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color.rdGreen.opacity(0.36) : Color.rdLine, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var companyLimit: Int {
        switch accessTier {
        case .free: return 0
        case .plus: return 5
        case .pro: return 25
        }
    }

    private var visibleCompanyLimit: Int {
        3
    }

    private var companyListMaxHeight: CGFloat {
        let visibleRows = min(companies.count, visibleCompanyLimit)
        let rowHeight: CGFloat = 66
        let rowSpacing: CGFloat = 10
        return CGFloat(visibleRows) * rowHeight + CGFloat(max(visibleRows - 1, 0)) * rowSpacing
    }

    private func loadCompanies() async {
        guard accessTier.isPaid else { return }
        #if DEBUG
        if Self.usesUITestCompanyFixtures {
            loadErrorMessage = nil
            if fixtureCompanies.isEmpty {
                fixtureCompanies = Self.uiTestCompanies
            }
            companies = fixtureCompanies.filter { !$0.isArchived }
            return
        }
        #endif
        isLoading = true
        loadErrorMessage = nil
        defer { isLoading = false }
        do {
            companies = try await CompanyService.shared.listCompanies()
        } catch {
            companies = []
            loadErrorMessage = error.localizedDescription
        }
    }

    private func save(_ draft: CompanyDraft, logo: UIImage?) async {
        do {
            #if DEBUG
            if Self.usesUITestCompanyFixtures {
                let saved = saveFixtureCompany(draft)
                await loadCompanies()
                if allowsSelection {
                    onSelect(saved)
                    dismiss()
                }
                return
            }
            #endif

            var saved = try await CompanyService.shared.saveCompany(draft)
            if let logo {
                let path = try await CompanyService.shared.uploadLogo(logo, companyID: saved.id)
                var updatedDraft = draft
                updatedDraft.id = saved.id
                updatedDraft.logoPath = path
                saved = try await CompanyService.shared.saveCompany(updatedDraft)
            }
            await loadCompanies()
            if allowsSelection {
                onSelect(saved)
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func archive(_ company: Company) {
        pendingArchive = nil
        Task {
            do {
                #if DEBUG
                if Self.usesUITestCompanyFixtures {
                    archiveFixtureCompany(company)
                    await loadCompanies()
                    if selectedCompanyID == company.id {
                        onSelect(nil)
                    }
                    return
                }
                #endif

                try await CompanyService.shared.archiveCompany(company)
                await loadCompanies()
                if selectedCompanyID == company.id {
                    onSelect(nil)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    #if DEBUG
    private static var usesUITestCompanyFixtures: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_COMPANY_FIXTURES")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_COMPANY_FIXTURES"] == "1"
    }

    private static var uiTestCompanies: [Company] {
        [
            Company(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000c001")!,
                userID: UUID(uuidString: "00000000-0000-0000-0000-00000000f201")!,
                name: "Test Aktif Firma",
                hazardClass: .high,
                logoPath: nil,
                address: "Test Mah. Güvenlik Cad. No: 10",
                contactPerson: "Ayşe Denetim",
                department: "Bakım Ekibi",
                defaultResponsible: "Saha Şefi",
                defaultDueDays: 30,
                isArchived: false,
                createdAt: nil,
                updatedAt: nil
            )
        ]
    }

    private func saveFixtureCompany(_ draft: CompanyDraft) -> Company {
        let resolvedID = draft.id ?? UUID(uuidString: "00000000-0000-0000-0000-00000000c010")!
        let company = Company(
            id: resolvedID,
            userID: UUID(uuidString: "00000000-0000-0000-0000-00000000f201")!,
            name: draft.trimmedName,
            hazardClass: draft.hazardClass,
            logoPath: draft.logoPath,
            address: draft.address.nonEmptyForFixture,
            contactPerson: draft.contactPerson.nonEmptyForFixture,
            department: draft.department.nonEmptyForFixture,
            defaultResponsible: draft.defaultResponsible.nonEmptyForFixture,
            defaultDueDays: draft.defaultDueDays,
            isArchived: false,
            createdAt: nil,
            updatedAt: nil
        )
        if let index = fixtureCompanies.firstIndex(where: { $0.id == resolvedID }) {
            fixtureCompanies[index] = company
        } else {
            fixtureCompanies.insert(company, at: 0)
        }
        return company
    }

    private func archiveFixtureCompany(_ company: Company) {
        guard let index = fixtureCompanies.firstIndex(where: { $0.id == company.id }) else { return }
        let archived = Company(
            id: company.id,
            userID: company.userID,
            name: company.name,
            hazardClass: company.hazardClass,
            logoPath: company.logoPath,
            address: company.address,
            contactPerson: company.contactPerson,
            department: company.department,
            defaultResponsible: company.defaultResponsible,
            defaultDueDays: company.defaultDueDays,
            isArchived: true,
            createdAt: company.createdAt,
            updatedAt: company.updatedAt
        )
        fixtureCompanies[index] = archived
    }
    #endif
}

private struct CompanyEditorSheet: View {
    @State var draft: CompanyDraft
    @Binding var selectedLogoImage: UIImage?
    let onSave: (CompanyDraft, UIImage?) async -> Void
    let onClose: () -> Void

    @State private var selectedLogoItem: PhotosPickerItem?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    logoSection
                    field(RDLocalization.string("localizable.company.picker.sheet.firma.adi.32866b14", table: .localizable, fallback: "Firma adı"), text: $draft.name, placeholder: RDLocalization.string("localizable.company.picker.sheet.orn.abc.insaat.8e319f37", table: .localizable, fallback: "Örn. ABC İnşaat"), identifier: "company.editor.name")
                    if RDLanguage.current == .turkish {
                        hazardSection
                    }
                    v2DetailsSection
                    defaultsSection

                    RDButton(
                        title: isSaving ? RDLocalization.string("localizable.company.picker.sheet.kaydediliyor.ff126ef4", table: .localizable, fallback: "Kaydediliyor...") : RDLocalization.string("localizable.company.picker.sheet.firmayi.kaydet.d6d3b0f2", table: .localizable, fallback: "Firmayı kaydet"),
                        style: .detect,
                        icon: isSaving ? "hourglass" : "checkmark.circle.fill"
                    ) {
                        save()
                    }
                    .disabled(isSaving || !draft.isValid)
                    .opacity((isSaving || !draft.isValid) ? 0.65 : 1)
                }
                .padding(20)
                .padding(.bottom, 24)
                .keyboardAdaptivePadding(extra: 16)
            }
            .background(Color.rdPaper)
            .navigationTitle(draft.id == nil ? RDLocalization.string("localizable.company.picker.sheet.yeni.firma.a8263565", table: .localizable, fallback: "Yeni firma") : RDLocalization.string("localizable.company.picker.sheet.firmayi.duzenle.36f32993", table: .localizable, fallback: "Firmayı düzenle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    RDModalCloseButton(action: onClose)
                }
            }
        }
        .onChange(of: selectedLogoItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        selectedLogoImage = image
                    }
                }
            }
        }
    }

    private var logoSection: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.rdWhite)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.rdLine, lineWidth: 1))
                if let selectedLogoImage {
                    Image(uiImage: selectedLogoImage)
                        .resizable()
                        .scaledToFit()
                        .padding(9)
                } else {
                    Image(systemName: "building.2.crop.circle")
                        .font(RDTypography.font(size: RDFontScale.size(27), weight: .semibold))
                        .foregroundStyle(Color.rdSlate)
                }
            }
            .frame(width: 76, height: 66)

            VStack(alignment: .leading, spacing: 5) {
                Text(RDLocalization.string("localizable.company.picker.sheet.firma.logosu.92fa5dc7", table: .localizable, fallback: "Firma logosu"))
                    .font(RDTypography.font(size: RDFontScale.size(14), weight: .semibold))
                    .foregroundStyle(Color.rdBlack)
                Text(RDLocalization.string("localizable.company.picker.sheet.opsiyonel.rapor.basliginda.gorunur.92cd94bb", table: .localizable, fallback: "Opsiyonel. Rapor başlığında görünür."))
                    .font(RDTypography.font(size: RDFontScale.size(12), weight: .regular))
                    .foregroundStyle(Color.rdSlate)
            }
            Spacer()
            PhotosPicker(selection: $selectedLogoItem, matching: .images) {
                Image(systemName: selectedLogoImage == nil ? "plus" : "arrow.triangle.2.circlepath")
                    .font(RDTypography.font(size: RDFontScale.size(15), weight: .semibold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(Color.rdGreenDark)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(12)
        .background(Color.rdWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var hazardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(RDLocalization.string("localizable.company.picker.sheet.tehlike.sinifi.6d2efbcb", table: .localizable, fallback: "Tehlike sınıfı"))
                .font(RDTypography.font(size: RDFontScale.size(12), weight: .semibold))
                .foregroundStyle(Color.rdSlate)
            ForEach(CompanyHazardClass.allCases) { hazard in
                Button {
                    draft.hazardClass = hazard
                } label: {
                    HStack {
                        Text(hazard.title)
                            .font(RDTypography.font(size: RDFontScale.size(14), weight: .medium))
                            .foregroundStyle(Color.rdBlack)
                        Spacer()
                        Image(systemName: draft.hazardClass == hazard ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(draft.hazardClass == hazard ? Color.rdGreen : Color.rdSlate.opacity(0.36))
                    }
                    .padding(12)
                    .background(Color.rdWhite)
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(draft.hazardClass == hazard ? Color.rdGreen.opacity(0.42) : Color.rdLine, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var v2DetailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(RDLocalization.string("localizable.company.picker.sheet.firma.detaylari.c3be8b4e", table: .localizable, fallback: "Firma detayları"))
                .font(RDTypography.font(size: RDFontScale.size(12), weight: .semibold))
                .foregroundStyle(Color.rdSlate)
            field(RDLocalization.string("localizable.company.picker.sheet.adres.e4e185fe", table: .localizable, fallback: "Adres"), text: $draft.address, placeholder: RDLocalization.string("localizable.company.picker.sheet.santiye.fabrika.veya.merkez.adresi.de545f4b", table: .localizable, fallback: "Şantiye, fabrika veya merkez adresi"), identifier: "company.editor.address")
            field(RDLocalization.string("localizable.company.picker.sheet.ilgili.kisi.c54dd4c6", table: .localizable, fallback: "İlgili kişi"), text: $draft.contactPerson, placeholder: RDLocalization.string("localizable.company.picker.sheet.isg.sorumlusu.veya.firma.yetkilisi.45dfd5be", table: .localizable, fallback: "İSG sorumlusu veya firma yetkilisi"), identifier: "company.editor.contact")
            field(RDLocalization.string("localizable.company.picker.sheet.departman.ekip.2516a7e8", table: .localizable, fallback: "Departman / ekip"), text: $draft.department, placeholder: RDLocalization.string("localizable.company.picker.sheet.uretim.bakim.maden.sahasi.515dcd3f", table: .localizable, fallback: "Üretim, bakım, maden sahası..."), identifier: "company.editor.department")
        }
    }

    private var defaultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(RDLocalization.string("localizable.company.picker.sheet.rapor.varsayilanlari.5b1f6b5a", table: .localizable, fallback: "Rapor varsayılanları"))
                .font(RDTypography.font(size: RDFontScale.size(12), weight: .semibold))
                .foregroundStyle(Color.rdSlate)
            field(RDLocalization.string("localizable.company.picker.sheet.varsayilan.sorumlu.db86c4e1", table: .localizable, fallback: "Varsayılan sorumlu"), text: $draft.defaultResponsible, placeholder: RDLocalization.string("localizable.company.picker.sheet.bakim.ekibi.saha.sefi.eda8136e", table: .localizable, fallback: "Bakım ekibi, saha şefi..."), identifier: "company.editor.responsible")
            field(RDLocalization.string("localizable.company.picker.sheet.varsayilan.termin.gunu.c7e3038e", table: .localizable, fallback: "Varsayılan termin günü"), text: $draft.defaultDueDaysText, placeholder: RDLocalization.string("localizable.company.picker.sheet.orn.30.710ccf45", table: .localizable, fallback: "Örn. 30"), keyboardType: .numberPad, identifier: "company.editor.due_days")
            if !draft.defaultDueDaysText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               draft.defaultDueDays == nil || !(1...365).contains(draft.defaultDueDays ?? 0) {
                Text(RDLocalization.string("localizable.company.picker.sheet.termin.gunu.1.365.arasinda.olmali.a8db8f60", table: .localizable, fallback: "Termin günü 1-365 arasında olmalı."))
                    .font(RDTypography.font(size: RDFontScale.size(11), weight: .medium))
                    .foregroundStyle(Color.rdCritical)
            }
        }
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        keyboardType: UIKeyboardType = .default,
        identifier: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(RDTypography.font(size: RDFontScale.size(12), weight: .semibold))
                .foregroundStyle(Color.rdSlate)
            TextField(placeholder, text: text)
                .font(RDTypography.font(size: RDFontScale.size(15), weight: .regular))
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(Color.rdWhite)
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.rdLine, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .accessibilityIdentifier(identifier ?? "company.editor.\(title)")
        }
    }

    private func save() {
        isSaving = true
        Task {
            await onSave(draft, selectedLogoImage)
            await MainActor.run {
                isSaving = false
            }
        }
    }
}

#if DEBUG
private extension String {
    var nonEmptyForFixture: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif
