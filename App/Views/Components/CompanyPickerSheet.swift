import PhotosUI
import SwiftUI
import UIKit

struct CompanyPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    static func presentationDetents(for accessTier: SubscriptionTier) -> Set<PresentationDetent> {
        accessTier.isPaid ? [.height(360), .large] : [.height(370)]
    }

    let title: String
    let accessTier: SubscriptionTier
    var selectedCompanyID: UUID?
    var allowNoCompany: Bool = true
    var allowsSelection: Bool = true
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
    #if DEBUG
    @State private var fixtureCompanies: [Company] = []
    #endif

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if accessTier.isPaid {
                        paidContent
                    } else {
                        lockedContent
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
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
        .task { await loadCompanies() }
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
            "Firmayı arşivle?",
            isPresented: Binding(
                get: { pendingArchive != nil },
                set: { if !$0 { pendingArchive = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingArchive {
                Button("Arşivle", role: .destructive) {
                    archive(pendingArchive)
                }
            }
            Button("Vazgeç", role: .cancel) {
                pendingArchive = nil
            }
        } message: {
            Text("Eski analiz ve rapor bağlantıları korunur; firma yeni seçimlerde görünmez.")
        }
        .alert("Firma işlemi tamamlanamadı", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Tamam") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var paidContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if shouldShowHeader {
                headerCard
            }

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
                VStack(spacing: 10) {
                    ForEach(companies) { company in
                        companyRow(company)
                    }
                }
            }

            addCompanyButton
        }
    }

    private var shouldShowHeader: Bool {
        !allowNoCompany || !companies.isEmpty
    }

    private var shouldShowBlockingLoadError: Bool {
        !allowNoCompany
    }

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "building.2.crop.circle")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.rdPlanPlus)
                .frame(width: 64, height: 64)
                .background(Color.rdPlanPlusSoft)
                .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 7) {
                Text("Firma arşivi Plus ve Pro’da")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.rdBlack)
                Text("Analizlerini firmalara bağla, raporlarını firma logosu ve tehlike sınıfıyla paylaş.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.rdSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }

            RDButton(title: "Planları incele", style: .detect, icon: "arrow.up.circle.fill") {
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

    private var headerCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.rdGreenDark)
                .frame(width: 38, height: 38)
                .background(Color.rdGreenSoft)
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 4) {
                Text(companies.isEmpty ? "Firma seçimi" : "\(companies.count)/\(companyLimit) firma")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.rdBlack)
                Text(companies.isEmpty ? "İstersen rapor aşamasında firma ekleyebilirsin." : "Seçili firma bilgileri raporda kullanılacak.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.rdSlate)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.rdWhite)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.rdLine, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var quietRetryButton: some View {
        Button {
            Task { await loadCompanies() }
        } label: {
            Label("Firmaları yenile", systemImage: "arrow.clockwise")
                .font(.system(size: 12.5, weight: .semibold))
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
            Text("Firmalar yükleniyor")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.rdSlate)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.rdWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Henüz firma yok")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.rdBlack)
            Text(allowNoCompany ? "İstersen firma eklemeden devam edebilir veya ilk firmayı buradan ekleyebilirsin." : "İlk firmayı buradan ekleyip analiz veya raporla eşleştirebilirsin.")
                .font(.system(size: 12, weight: .regular))
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.rdCriticalText)
                    .frame(width: 34, height: 34)
                    .background(Color.rdCriticalBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Firmalar yüklenemedi")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.rdBlack)
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.rdSlate)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task { await loadCompanies() }
                } label: {
                    Label("Tekrar dene", systemImage: "arrow.clockwise")
                        .font(.system(size: 12.5, weight: .semibold))
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
                        Text("Firma olmadan devam et")
                            .font(.system(size: 12.5, weight: .semibold))
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
                title: "Firma olmadan devam et",
                subtitle: "İstersen rapor aşamasında seçebilirsin.",
                isSelected: selectedCompanyID == nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("company_picker.no_company")
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
                Button("Düzenle") {
                    presentEditor(CompanyDraft(
                        id: company.id,
                        name: company.name,
                        hazardClass: company.hazardClass,
                        logoPath: company.logoPath,
                        address: company.address ?? "",
                        contactPerson: company.contactPerson ?? "",
                        department: company.department ?? "",
                        defaultResponsible: company.defaultResponsible ?? "",
                        defaultDueDaysText: company.defaultDueDays.map(String.init) ?? ""
                    ))
                }
                Button("Arşivle", role: .destructive) {
                    pendingArchive = company
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.rdSlate)
                    .frame(width: 40, height: 48)
                    .background(Color.rdWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
            }
            .accessibilityLabel("\(company.name) işlemleri")
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
                    .font(.system(size: 15, weight: .semibold))
                Text(companies.count >= companyLimit ? "Firma limiti doldu" : "Yeni firma ekle")
                    .font(.system(size: 14, weight: .semibold))
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
        }
        .buttonStyle(RDPressableButtonStyle())
        .disabled(companies.count >= companyLimit)
        .opacity(companies.count >= companyLimit ? 0.58 : 1)
        .accessibilityIdentifier("company_picker.add")
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? Color.rdGreenDark : Color.rdSlate)
                .frame(width: 34, height: 34)
                .background(isSelected ? Color.rdGreenSoft : Color.rdFog)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.rdBlack)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17, weight: .semibold))
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
                name: "QA Aktif Firma",
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
                    field("Firma adı", text: $draft.name, placeholder: "Örn. ABC İnşaat", identifier: "company.editor.name")
                    hazardSection
                    v2DetailsSection
                    defaultsSection

                    RDButton(
                        title: isSaving ? "Kaydediliyor..." : "Firmayı kaydet",
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
            .navigationTitle(draft.id == nil ? "Yeni firma" : "Firmayı düzenle")
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
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(Color.rdSlate)
                }
            }
            .frame(width: 76, height: 66)

            VStack(alignment: .leading, spacing: 5) {
                Text("Firma logosu")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.rdBlack)
                Text("Opsiyonel. Rapor başlığında görünür.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.rdSlate)
            }
            Spacer()
            PhotosPicker(selection: $selectedLogoItem, matching: .images) {
                Image(systemName: selectedLogoImage == nil ? "plus" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .semibold))
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
            Text("Tehlike sınıfı")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.rdSlate)
            ForEach(CompanyHazardClass.allCases) { hazard in
                Button {
                    draft.hazardClass = hazard
                } label: {
                    HStack {
                        Text(hazard.title)
                            .font(.system(size: 14, weight: .medium))
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
            Text("Firma detayları")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.rdSlate)
            field("Adres", text: $draft.address, placeholder: "Şantiye, fabrika veya merkez adresi", identifier: "company.editor.address")
            field("İlgili kişi", text: $draft.contactPerson, placeholder: "İSG sorumlusu veya firma yetkilisi", identifier: "company.editor.contact")
            field("Departman / ekip", text: $draft.department, placeholder: "Üretim, bakım, maden sahası...", identifier: "company.editor.department")
        }
    }

    private var defaultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rapor varsayılanları")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.rdSlate)
            field("Varsayılan sorumlu", text: $draft.defaultResponsible, placeholder: "Bakım ekibi, saha şefi...", identifier: "company.editor.responsible")
            field("Varsayılan termin günü", text: $draft.defaultDueDaysText, placeholder: "Örn. 30", keyboardType: .numberPad, identifier: "company.editor.due_days")
            if !draft.defaultDueDaysText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               draft.defaultDueDays == nil || !(1...365).contains(draft.defaultDueDays ?? 0) {
                Text("Termin günü 1-365 arasında olmalı.")
                    .font(.system(size: 11, weight: .medium))
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.rdSlate)
            TextField(placeholder, text: text)
                .font(.system(size: 15, weight: .regular))
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
