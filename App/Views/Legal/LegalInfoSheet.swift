import SwiftUI

struct LegalInfoSheet: View {
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    legalRow(
                        icon: "person.text.rectangle",
                        title: "KVKK ve gizlilik",
                        body: "Hesap, analiz, fotoğraf, rapor ve kullanım kayıtları hizmetin sunulması, güvenlik ve ürün geliştirme amacıyla işlenir."
                    )

                    legalRow(
                        icon: "camera.viewfinder",
                        title: "AI görsel/metin işleme",
                        body: "Yüklediğin saha fotoğrafları ve yazdığın metinler risk analizi ve rapor üretimi için AI altyapısı üzerinden işlenebilir."
                    )

                    legalRow(
                        icon: "doc.text.magnifyingglass",
                        title: "Kullanım koşulları",
                        body: "AI çıktıları karar destek niteliğindedir. Nihai iş güvenliği değerlendirmesi ve uygulanacak önlemler yetkili uzman sorumluluğundadır."
                    )

                    Text("Üye olarak, giriş yaparak veya analiz başlatarak RiskDetected kullanım koşullarını ve ilgili veri işleme bilgilendirmelerini kabul etmiş sayılırsın.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.rdFog)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(Color.rdPaper)
            .navigationTitle("Yasal Bilgilendirme")
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
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.rdGreenDark)
                    .frame(width: 46, height: 46)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Analiz akışını kesmeden açık bilgilendirme")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.rdBlack)
                    Text("Bu alan, sözleşme ve veri işleme özetini hızlıca görmen için eklendi. Nihai metinler yayın öncesi hukuki gözden geçirme gerektirir.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func legalRow(icon: String, title: String, body: String) -> some View {
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
}

#Preview {
    LegalInfoSheet(onClose: {})
}
