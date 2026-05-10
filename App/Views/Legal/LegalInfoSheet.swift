import SwiftUI

struct LegalInfoSheet: View {
    let onClose: () -> Void
    @State private var selectedDocument: LegalDocumentKind = .kvkk

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    documentPicker
                    LegalDocumentView(document: selectedDocument.document)
                    acceptanceNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(Color.rdPaper)
            .navigationTitle("Yasal Bilgilendirme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat", action: onClose)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 46, height: 46)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 5) {
                    Text("RiskDetected yasal merkezi")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .tracking(-0.2)
                        .foregroundStyle(Color.rdBlack)
                    Text("KVKK, kullanım koşulları ve AI veri işleme bilgilendirmelerini tek yerde, okunabilir bölümler halinde gösterir.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                headerMetric(icon: "lock.shield", title: "KVKK")
                headerMetric(icon: "doc.text", title: "Koşullar")
                headerMetric(icon: "sparkles", title: "AI veri")
            }
        }
        .padding(16)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private func headerMetric(icon: String, title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreen)
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdCharcoal)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(Color.rdFog)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var documentPicker: some View {
        VStack(spacing: 8) {
            ForEach(LegalDocumentKind.allCases) { kind in
                let active = selectedDocument == kind
                Button {
                    selectedDocument = kind
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(active ? Color.white : Color.rdCharcoal)
                            .frame(width: 38, height: 38)
                            .background(active ? Color.rdSelected : Color.rdFog)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(kind.title)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.rdBlack)
                            Text(kind.subtitle)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.rdSlate)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: active ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .foregroundStyle(active ? Color.rdGreen : Color.rdSlate.opacity(0.55))
                    }
                    .padding(12)
                    .background(Color.rdWhite)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(active ? Color.rdGreen.opacity(0.45) : Color.rdLine, lineWidth: active ? 1.5 : 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(RDPressableButtonStyle())
            }
        }
    }

    private var acceptanceNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreen)
                .padding(.top, 1)

            Text("Üye olarak, giriş yaparak veya analiz başlatarak RiskDetected kullanım koşullarını ve ilgili veri işleme bilgilendirmelerini kabul etmiş sayılırsın. Nihai metinler yayın öncesi hukuki gözden geçirme gerektirir.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.rdFog)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: document.icon)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text(document.badge)
                        .rdMono(size: 11, weight: .bold)
                }
                .foregroundStyle(Color.rdGreen)

                Text(document.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(-0.3)
                    .foregroundStyle(Color.rdBlack)

                Text(document.summary)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Son güncelleme: \(document.updatedAt)")
                    .rdMono(size: 11, weight: .semibold)
                    .foregroundStyle(Color.rdSlate)
                    .padding(.top, 2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.rdWhite, Color.rdFog],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))

            ForEach(document.sections) { section in
                LegalSectionCard(section: section)
            }
        }
    }
}

private struct LegalSectionCard: View {
    let section: LegalSection

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Text(section.number)
                    .rdMono(size: 12, weight: .bold)
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 30, height: 30)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    if let subtitle = section.subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(section.body)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.rdCharcoal)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private enum LegalDocumentKind: String, CaseIterable, Identifiable {
    case kvkk
    case terms
    case aiProcessing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kvkk: return "KVKK ve Gizlilik"
        case .terms: return "Kullanım Koşulları"
        case .aiProcessing: return "AI Veri İşleme"
        }
    }

    var subtitle: String {
        switch self {
        case .kvkk: return "Kişisel veri ve gizlilik bilgilendirmesi."
        case .terms: return "Uygulama kullanım şartları ve sorumluluklar."
        case .aiProcessing: return "Fotoğraf, metin ve rapor üretiminde AI işleme."
        }
    }

    var icon: String {
        switch self {
        case .kvkk: return "person.text.rectangle"
        case .terms: return "doc.text.magnifyingglass"
        case .aiProcessing: return "sparkles"
        }
    }

    var document: LegalDocument {
        switch self {
        case .kvkk: return .kvkk
        case .terms: return .terms
        case .aiProcessing: return .aiProcessing
        }
    }
}

private struct LegalDocument {
    let icon: String
    let badge: String
    let title: String
    let summary: String
    let updatedAt: String
    let sections: [LegalSection]
}

private struct LegalSection: Identifiable {
    let id = UUID()
    let number: String
    let title: String
    let subtitle: String?
    let body: String
}

private extension LegalDocument {
    static let kvkk = LegalDocument(
        icon: "lock.shield",
        badge: "KVKK",
        title: "KVKK ve Gizlilik Aydınlatma Metni",
        summary: "RiskDetected hesabı, analiz kayıtları, fotoğraf/metin girdileri ve rapor arşivi için temel kişisel veri işleme çerçevesi.",
        updatedAt: "10 Mayıs 2026",
        sections: [
            .init(
                number: "01",
                title: "Veri sorumlusu ve kapsam",
                subtitle: "Bu alanı şirket/uygulama bilgilerine göre güncelle.",
                body: "RiskDetected, iş güvenliği analiz ve raporlama süreçlerini desteklemek amacıyla kullanılan bir dijital asistandır. Bu metin; hesap oluşturma, giriş, analiz başlatma, rapor oluşturma ve destek süreçlerinde işlenebilecek kişisel verilere ilişkin genel bilgilendirme sağlar."
            ),
            .init(
                number: "02",
                title: "İşlenen veri kategorileri",
                subtitle: nil,
                body: "Kimlik ve iletişim bilgileri, hesap bilgileri, firma/profil bilgileri, uygulama kullanım kayıtları, analiz metinleri, saha fotoğrafları, rapor içerikleri, cihaz ve bildirim token bilgileri hizmetin sunulması için işlenebilir."
            ),
            .init(
                number: "03",
                title: "İşleme amaçları",
                subtitle: nil,
                body: "Veriler; kullanıcı hesabının yönetilmesi, analiz sonuçlarının oluşturulması, PDF raporlarının hazırlanması, rapor arşivinin tutulması, güvenlik ve hata izlenebilirliği, destek süreçleri ve ürün kalitesinin artırılması amaçlarıyla işlenir."
            ),
            .init(
                number: "04",
                title: "Saklama, silme ve başvuru hakları",
                subtitle: "Uzun hukuki metni burada genişletebilirsin.",
                body: "Kullanıcı, profilindeki veri yönetimi alanlarından dışa aktarma, rapor/analiz silme ve hesap silme talebi süreçlerini başlatabilir. KVKK kapsamındaki başvuru hakları, nihai yayın metninde belirtilen resmi iletişim kanalları üzerinden kullanılabilir."
            ),
        ]
    )

    static let terms = LegalDocument(
        icon: "doc.text",
        badge: "KOŞULLAR",
        title: "Kullanım Koşulları",
        summary: "RiskDetected kullanımına ilişkin temel kurallar, kullanıcı sorumlulukları ve AI destekli analiz çıktılarının niteliği.",
        updatedAt: "10 Mayıs 2026",
        sections: [
            .init(
                number: "01",
                title: "Hizmetin niteliği",
                subtitle: nil,
                body: "RiskDetected; saha fotoğrafı veya metin girdilerinden iş güvenliği risklerini tespit etmeye ve raporlamaya yardımcı olan bir karar destek aracıdır. Uygulama, yetkili iş güvenliği uzmanının mesleki değerlendirmesinin yerine geçmez."
            ),
            .init(
                number: "02",
                title: "Kullanıcı sorumluluğu",
                subtitle: nil,
                body: "Kullanıcı; yüklediği içeriklerin doğruluğundan, kişisel veri veya gizli bilgi içermesi halinde gerekli izinleri almaktan, analiz sonuçlarını saha gerçekliği ve mevzuat ile birlikte değerlendirmekten sorumludur."
            ),
            .init(
                number: "03",
                title: "AI çıktılarının sınırı",
                subtitle: nil,
                body: "AI analizleri hata, eksik yorum veya bağlam dışı öneri içerebilir. Nihai karar, denetim, önlem planı ve uygulama sorumluluğu kullanıcıya ve ilgili yetkili uzmana aittir."
            ),
            .init(
                number: "04",
                title: "Pro özellikler ve raporlar",
                subtitle: nil,
                body: "Pro özellikler; detaylı risk analiz tabloları, rapor özelleştirme, firma/profil bilgileri ve gelişmiş PDF çıktıları gibi ek fonksiyonlar sunabilir. Ücretlendirme, abonelik ve iptal koşulları nihai yayın metninde ayrıca açıklanır."
            ),
        ]
    )

    static let aiProcessing = LegalDocument(
        icon: "sparkles",
        badge: "AI",
        title: "AI Veri İşleme Bilgilendirmesi",
        summary: "Saha fotoğrafları, metin girdileri ve rapor üretimi sırasında yapay zeka sistemleriyle yapılan veri işleme süreçleri.",
        updatedAt: "10 Mayıs 2026",
        sections: [
            .init(
                number: "01",
                title: "AI analiz girdileri",
                subtitle: nil,
                body: "Kullanıcının yüklediği saha fotoğrafları, yazdığı gözlem/prosedür metinleri ve seçtiği analiz odakları risk tespiti, sınıflandırma, özetleme ve rapor üretimi için AI servislerine gönderilebilir."
            ),
            .init(
                number: "02",
                title: "Güvenlik ve maskeleme",
                subtitle: nil,
                body: "Uygulama, mümkün olan akışlarda maliyet ve gizlilik açısından gereksiz veriyi azaltmayı hedefler. Kullanıcıların fotoğraf ve metinlerde gereksiz kişisel veri, gizli ticari bilgi veya hassas veri paylaşmaması önerilir."
            ),
            .init(
                number: "03",
                title: "Model sağlayıcıları ve yedeklilik",
                subtitle: nil,
                body: "RiskDetected, analiz sürekliliği ve kota yönetimi için birden fazla AI sağlayıcı veya API anahtarı kullanabilir. Bu kullanım, yalnızca hizmetin sağlanması, hata azaltma ve performans sürekliliği amaçlarıyla yapılandırılır."
            ),
            .init(
                number: "04",
                title: "Çıktıların değerlendirilmesi",
                subtitle: nil,
                body: "AI tarafından üretilen bulgular, risk skorları, öneriler ve rapor metinleri otomatik karar niteliği taşımaz. Kullanıcı, çıktıları yetkili uzman değerlendirmesi, saha koşulları ve yürürlükteki mevzuatla birlikte kontrol etmelidir."
            ),
        ]
    )
}

#Preview {
    LegalInfoSheet(onClose: {})
}
