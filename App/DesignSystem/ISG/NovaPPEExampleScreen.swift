import SwiftUI

/// The KKD module offers one editable sample file and creates no handover record.
struct NovaPPEExampleScreen: View {
    let onBack: () -> Void

    private var documentURL: URL? {
        let name = "ISGADA_KKD_Zimmet_ve_Teslim_Formu_Duzenlenebilir"
        return Bundle.main.url(forResource: name, withExtension: "docx",
                               subdirectory: "PPEFormAssets/ppe_forms")
            ?? Bundle.main.url(forResource: name, withExtension: "docx")
    }

    var body: some View {
        content.onAppear { NovaForYouOutbox.recordUse("ppe_form") }
    }
    @ViewBuilder private var content: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NovaPageHeading(title: RDLocalization.string("localizable.nova.ppeexample.screen.kkd.zimmet.formu.ornegi.8f8f826c", table: .localizable, fallback: "KKD Zimmet Formu Örneği"), onBack: onBack)
                    NovaHelpHint(text: RDLocalization.string("localizable.nova.ppeexample.screen.duzenlenebilir.word.ornegini.indirin.kendi.isyer.9360234c", table: .localizable, fallback: "Düzenlenebilir Word örneğini indirin, kendi işyerinizin bilgileriyle doldurun ve kullanın. Uygulama burada zimmet veya teslim kaydı oluşturmaz."))
                    NovaCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 9) {
                            NovaText(text: RDLocalization.string("localizable.nova.ppeexample.screen.kkd.zimmet.ve.teslim.formu.2b5523f0", table: .localizable, fallback: "KKD Zimmet ve Teslim Formu"), style: .cardTitle)
                            NovaText(text: RDLocalization.string("localizable.nova.ppeexample.screen.calisan.bilgileri.teslim.edilen.donanimlar.imzal.be4d3f4d", table: .localizable, fallback: "Çalışan bilgileri, teslim edilen donanımlar, imzalar, ek teslim ve iade alanları içerir."), style: .meta)
                            NovaText(text: RDLocalization.string("localizable.nova.ppeexample.screen.word.duzenlenebilir.ornek.2b83a550", table: .localizable, fallback: "Word · Düzenlenebilir örnek"), style: .metaQuiet)
                            if let documentURL {
                                ShareLink(item: documentURL) {
                                    Label(RDLocalization.string("localizable.nova.ppeexample.screen.word.dosyasini.indir.019e3026", table: .localizable, fallback: "Word dosyasını indir"), systemImage: "square.and.arrow.up")
                                        .font(NovaFont.font(.bodyStrong))
                                }
                                .accessibilityIdentifier("ppe.example.download")
                            } else {
                                NovaText(text: RDLocalization.string("localizable.nova.ppeexample.screen.word.dosyasi.bulunamadi.0f2fbe98", table: .localizable, fallback: "Word dosyası bulunamadı"), style: .metaQuiet)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, novaTabBarInset)
            }
        }
    }
}
