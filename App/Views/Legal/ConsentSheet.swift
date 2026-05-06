import SwiftUI

struct ConsentSheet: View {
    let isSaving: Bool
    let onAccept: () -> Void
    let onClose: () -> Void

    @State private var acceptsLegal = false
    @State private var acceptsAIProcessing = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    legalSummary
                    consentChecklist
                    versionBlock

                    RDButton(
                        title: isSaving ? "Kaydediliyor..." : "Kabul et ve devam et",
                        style: canContinue ? .detect : .secondary,
                        icon: isSaving ? "hourglass" : "checkmark.seal.fill",
                        height: 54
                    ) {
                        guard canContinue, !isSaving else { return }
                        onAccept()
                    }
                    .disabled(!canContinue || isSaving)
                    .padding(.top, 2)
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(Color.rdPaper)
            .navigationTitle("Yasal Onay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat", action: onClose)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        }
    }

    private var header: some View {
        RDCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.rdGreenDark)
                    .frame(width: 46, height: 46)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 6) {
                    Text("İlk analizden önce onay gerekiyor")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.rdBlack)
                    Text("RiskDetected, saha fotoğraflarını ve yazdığın açıklamaları yalnızca risk analizi ve rapor üretimi için işler.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var legalSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryRow(
                icon: "person.text.rectangle",
                title: "KVKK aydınlatması",
                body: "Hesap, analiz, fotoğraf, rapor ve kullanım kayıtları hizmetin sunulması, güvenlik ve ürün geliştirme amacıyla işlenir."
            )
            summaryRow(
                icon: "camera.viewfinder",
                title: "Görsel veri işleme",
                body: "Yüklediğin saha fotoğrafları Gemini tabanlı analiz için Supabase altyapısı üzerinden işlenir ve rapor geçmişinde saklanabilir."
            )
            summaryRow(
                icon: "doc.text.magnifyingglass",
                title: "Kullanım koşulları",
                body: "AI bulguları karar destek niteliğindedir. Nihai İSG değerlendirmesi yetkili uzman sorumluluğundadır."
            )
        }
    }

    private var consentChecklist: some View {
        VStack(spacing: 10) {
            checkboxRow(
                checked: $acceptsLegal,
                title: "KVKK Aydınlatma Metni ve Kullanım Koşulları'nı okudum, kabul ediyorum."
            )
            checkboxRow(
                checked: $acceptsAIProcessing,
                title: "Fotoğraf ve metin girdilerimin AI risk analizi için işlenmesine açık rıza veriyorum."
            )
        }
    }

    private var versionBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("VERSİYONLAR")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
            Text("\(ConsentService.kvkkVersion) · \(ConsentService.termsVersion) · \(ConsentService.explicitConsentVersion)")
                .rdMono(size: 10)
        }
        .foregroundStyle(Color.rdSlate)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rdFog)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var canContinue: Bool {
        acceptsLegal && acceptsAIProcessing
    }

    private func summaryRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.rdGreenDark)
                .frame(width: 34, height: 34)
                .background(Color.rdGreenSoft)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.rdBlack)
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.rdSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func checkboxRow(checked: Binding<Bool>, title: String) -> some View {
        Button {
            checked.wrappedValue.toggle()
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: checked.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(checked.wrappedValue ? Color.rdGreen : Color.rdSlate)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.rdBlack)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(checked.wrappedValue ? Color.rdGreenSoft : Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(checked.wrappedValue ? Color.rdGreen.opacity(0.45) : Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ConsentSheet(isSaving: false, onAccept: {}, onClose: {})
}
