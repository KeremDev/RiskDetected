import PhotosUI
import SwiftUI
import UIKit

struct CompanyPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    static func presentationDetents(for accessTier: SubscriptionTier) -> Set<PresentationDetent> {
        accessTier.isPaid ? [.height(400), .large] : [.height(370)]
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
    @State private var errorMessage: String?
    @State private var editorDraft = CompanyDraft()
    @State private var editorLogoImage: UIImage?
    @State private var isEditorPresented = false
    @State private var pendingArchive: Company?

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
        VStack(alignment: .leading, spacing: 14) {
            headerCard

            if isLoading {
                loadingCard
            } else if companies.isEmpty {
                emptyCard
            } else {
                VStack(spacing: 10) {
                    if allowNoCompany {
                        noCompanyRow
                    }

                    ForEach(companies) { company in
                        companyRow(company)
                    }
                }
            }

            addCompanyButton
        }
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
                Text("\(companies.count)/\(companyLimit) firma")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.rdBlack)
                Text("Firma adı, logo ve tehlike sınıfı raporlarında kullanılacak.")
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
            Text("İlk firmayı buradan ekleyip analiz veya raporla eşleştirebilirsin.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.rdSlate)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.rdWhite)
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
                title: "Firma seçmeden devam et",
                subtitle: "Rapor aşamasında tekrar seçebilirsin.",
                isSelected: selectedCompanyID == nil
            )
        }
        .buttonStyle(.plain)
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
            .foregroundStyle(.white)
            .background(Color.rdOnyx)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color.rdOnyx.opacity(0.12), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(RDPressableButtonStyle())
        .disabled(companies.count >= companyLimit)
        .opacity(companies.count >= companyLimit ? 0.58 : 1)
        .accessibilityIdentifier("company_picker.add")
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
            companies = Self.uiTestCompanies
            return
        }
        #endif
        isLoading = true
        defer { isLoading = false }
        do {
            companies = try await CompanyService.shared.listCompanies()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save(_ draft: CompanyDraft, logo: UIImage?) async {
        do {
            var saved = try await CompanyService.shared.saveCompany(draft)
            if let logo {
                let path = try await CompanyService.shared.uploadLogo(logo, companyID: saved.id)
                let updatedDraft = CompanyDraft(
                    id: saved.id,
                    name: saved.name,
                    hazardClass: saved.hazardClass,
                    logoPath: path
                )
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
                    field("Firma adı", text: $draft.name, placeholder: "Örn. ABC İnşaat")
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
            field("Adres", text: $draft.address, placeholder: "Şantiye, fabrika veya merkez adresi")
            field("İlgili kişi", text: $draft.contactPerson, placeholder: "İSG sorumlusu veya firma yetkilisi")
            field("Departman / ekip", text: $draft.department, placeholder: "Üretim, bakım, maden sahası...")
        }
    }

    private var defaultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rapor varsayılanları")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.rdSlate)
            field("Varsayılan sorumlu", text: $draft.defaultResponsible, placeholder: "Bakım ekibi, saha şefi...")
            field("Varsayılan termin günü", text: $draft.defaultDueDaysText, placeholder: "Örn. 30", keyboardType: .numberPad)
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
        keyboardType: UIKeyboardType = .default
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
