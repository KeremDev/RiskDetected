import type { ExpertRegistryEntry } from "./contracts.ts";

/**
 * Hand-written, one entry per equipment family the model can report seeing.
 *
 * Every standard number, interval and measurement here is ours. The model
 * supplies only the family code. Where a figure was supplied by a domain
 * expert rather than read off the source text, `interval.verified` is false
 * and the rendered card states the figure without claiming a verified basis
 * -- the same convention the training catalogue uses.
 *
 * Revised 2026-08-30 against the 23.12.2025 iş ekipmanları değişikliği and
 * the 02.04.2026 eğitim rejimi: the earlier draft's "her yıl 1,25/1,1"
 * (lifting) and "her yıl 1,5 kat" (pressure) blanket claims were the kind of
 * shortcut the operator explicitly ruled out -- the actual regime is an
 * annual functional load test, with the full static/dynamic or hydrostatic
 * regime at three years or after major repair. Every entry now separates
 * periodic inspection, calibration, NDT, pre-use checks and process-integrity
 * inspection, and distinguishes a report's existence from a report's
 * validity: an equipment/serial match, an in-date İSG-KATİP contract, the
 * inspector's scope, gauge calibration, numeric results against a limit, and
 * -- after a major nonconformity -- a second inspection that closes it.
 *
 * All 22 families in the closed asset list now have an entry.
 */
export const EXPERT_REGISTRY: Record<string, ExpertRegistryEntry> = {
  overhead_crane: {
    family: "overhead_crane",
    recommendationClass: "periodic_inspection_record",
    titleTr: "Köprülü Vinç — Periyodik Kontrol, Yük Deneyi ve Emniyet Fonksiyonlarının Doğrulanması",
    categoryLabelTr: "Kaldırma ve İletme Ekipmanları",
    assetLabelTr: "köprülü vinç",
    observationTr:
      "Sahada köprülü vinç görülmektedir. Boya, genel görünüm veya vincin yüksüz çalışması; taşıyıcı kirişlerin yorulma durumunu, frenleme kapasitesini, sınırlandırıcıların güvenilirliğini ve yük altında oluşan sehimleri doğrulamaz. Fotoğraf yalnız ekipman ailesini tanımlar; kullanıma uygunluk, hukuken geçerli periyodik kontrol raporu, yük deneyi sonuçları, bakım geçmişi ve koruyucu fonksiyonların birlikte doğrulanmasıyla belirlenir.",
    requirementsTr: [
      "Ekipman kimliği; imalatçı, model, seri numarası, imal yılı, kaldırma kapasitesi, açıklık, kaldırma yüksekliği ve çalışma sınıfı ile sahadaki etiket üzerinden eşleştirilmiş; İSG-KATİP sözleşmesi, EKİPNET kaydı ve Bakanlığın güncel rapor/kriter formatı bulunmalıdır.",
      "Rapor, yıllık kontrolde beyan edilen çalışma kapasitesindeki yükle fonksiyon testini; en geç üç yılda bir veya kapsamlı bakım/tadilat sonrasında ise güncel ekipman kriterlerindeki statik ve dinamik deneyleri içermelidir. Test yükü ve kullanılan dinamometre/yük hücresi izlenebilir ve kalibrasyonlu olmalıdır.",
      "Köprü ve baş kirişleri, kaynaklar, cıvatalı birleşimler, tekerlekler, raylar, uç durdurucular, tamponlar ve yürüme yolları; çatlak, kalıcı deformasyon, gevşeme, hizasızlık ve anormal sehim açısından ölçülü olarak kontrol edilmeli; şüpheli bölgeler uygun NDT yöntemiyle doğrulanmalıdır.",
      "Kanca ve emniyet mandalı, halat veya yük zinciri, tambur, kasnaklar, halat kılavuzu, eşitleyiciler ve bağlantı elemanları üretici/standart hurdaya ayırma ölçütlerine göre ayrı ayrı değerlendirilmelidir.",
      "Kaldırma, yürütme ve köprü frenleri; üst-alt limitler, çapraz hareket limitleri, aşırı yük sınırlayıcı, anti-çarpışma sistemi, gevşek halat koruması ve varsa bölge sınırlama sistemi gerçek fonksiyon testiyle doğrulanmalı; yalnız görsel kontrolle “uygun” yazılmamalıdır.",
      "Kumanda düzeni, acil durdurma, yön işaretleri, kablosuz kumanda eşleştirmesi, enerji kesme ve kilitleme noktası, koruma iletkeni sürekliliği ve hareketli besleme kabloları elektriksel ve mekanik olarak kontrol edilmelidir.",
      "Operatör kullanım öncesi kontrol listesi; vardiya başında kanca, halat/zincir, fren, limit, ikaz, kumanda ve çalışma alanını kapsamalı; bildirilen kusurların kapatma kaydı bakım sistemiyle ilişkilendirilmelidir.",
      "Ağır kusur, kaza, aşırı yük, konstrüksiyon onarımı, ray ayarı, fren/halat değişimi veya kontrol sistemi modifikasyonu sonrasında ekipman tekrar kullanıma alınmadan önce ikinci kontrol ve gerektiğinde mühendislik değerlendirmesi yapılmalıdır.",
    ],
    ifPresentTr:
      "Rapor mevcutsa; ekipman seri numarasının sahadaki vinçle eşleştiğini, raporu düzenleyen kişinin güncel yetki kapsamını, İSG-KATİP sözleşme zamanını, test yükü ve cihaz kalibrasyonunu, ölçülen değerleri, ağır kusur sınıflandırmasını ve uygunsuzlukların ikinci kontrolle kapatıldığını inceleyin. Aynı raporun birden fazla vinç için kopyalanmadığını rapordaki fotoğraf, konum ve teknik verilerden doğrulayın.",
    ifAbsentTr:
      "Rapor yoksa, süresi geçmişse veya hukuki geçerlilik şartlarını taşımıyorsa vinci yük altına almayın; enerji ve kumanda erişimini kontrollü biçimde kısıtlayın. Yetkili kişiyle İSG-KATİP sözleşmesini zamanında kurarak Bakanlığın güncel formatında periyodik kontrol, gerekli yük deneyleri ve ağır kusur takibini tamamlatın.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, m.7, m.14/A ve Ek-III; 23.12.2025 değişiklikleri.",
      "Bakanlık kriteri — Kaldırma ve iletme ekipmanları için güncel periyodik kontrol rapor/kriter dokümanları ve EKİPNET uygulaması.",
      "Standart — TS EN 15011 Köprülü ve portal vinçler; TS EN 13001 serisi Vinçler — Genel tasarım.",
      "Standart — TS ISO 9927-1 Vinçlerin muayeneleri — Genel.",
      "İyi uygulama — ISO 12480-1 Vinçlerin güvenli kullanımı; HSE LOLER planlama ve kapsamlı muayene yaklaşımı.",
    ],
    interval: {
      textTr:
        "Standartlarda/imalatçı dokümanında daha kısa süre yoksa yılda bir; yıllık kontrolde çalışma kapasitesinde yükle fonksiyon deneyi, en geç üç yılda bir veya kapsamlı bakım/tadilat sonrasında güncel kriterlerdeki statik-dinamik deneyler",
      basisCode: "TR-IS-EKIPMANLARI-2025-EK3-KALDIRMA",
      verified: true,
    },
    relatedLayers: [5, 6, 7, 19],
  },

  lifting_accessory: {
    family: "lifting_accessory",
    recommendationClass: "periodic_inspection_record",
    titleTr: "Kaldırma Aksesuarları — Tekil Kimlik, WLL ve Hurdaya Ayırma Kriterlerinin Doğrulanması",
    categoryLabelTr: "Kaldırma ve İletme Ekipmanları",
    assetLabelTr: "sapan, zincir, halat, mapa, kanca",
    observationTr:
      "Sahada sapan, zincir, tel halat sapan, tekstil sapan, mapa, şakıl veya kanca türü kaldırma aksesuarı görülmektedir. Bu aksesuarlar vincin ayrılmaz parçası kabul edilmez; her biri kendi kimliği, çalışma yükü limiti ve kontrol kaydıyla izlenmelidir. Lif içi hasar, tel kırığı dağılımı, zincir uzaması ve ısı/kimyasal etkisi fotoğraftan güvenilir biçimde belirlenemez.",
    requirementsTr: [
      "Her aksesuar tekil ve kalıcı bir kimlik numarasıyla etiketlenmeli; WLL, sınıf/grade, çap veya ölçü, kol sayısı, etkin boy ve imalatçı bilgisi okunabilir olmalı; sahadaki numara kontrol raporuyla birebir eşleşmelidir.",
      "Aksesuarın imalatçı uygunluk beyanı ve ürün izlenebilirlik belgesi dosyada bulunmalı; sonradan kısaltma, kaynak, halka değişimi veya kombinasyon yapılmışsa yeni konfigürasyon mühendislik ve uygunluk açısından yeniden doğrulanmalıdır.",
      "Yıllık periyodik kontrolde aksesuar, türüne özel standardın ölçülebilir hurdaya ayırma kriterleriyle değerlendirilmelidir; yalnız “gözle kontrol edildi” ifadesi yeterli değildir.",
      "Zincirlerde çap kaybı, uzama, dönme, çatlak ve ısı izi; tel halat sapanlarda tel kırığı dağılımı, ezilme, kuş kafesi, korozyon ve soket/ferrül; tekstil sapanlarda kesik, dikiş hasarı, kimyasal/ısı izi ve etiket kaybı kaydedilmelidir.",
      "Kanca, şakıl ve bağlantı elemanlarında ağız açıklığı, eksen kaçıklığı, mandal işlevi, pim/diş durumu, yerel aşınma ve imalatçı işaretleri ölçülmeli; kapasitesi bilinmeyen veya farklı sınıftaki parçaların rastgele kombinasyonu yasaklanmalıdır.",
      "Sapan açısı, boğma/sepet bağlama, keskin kenar, asimetrik yük ve ağırlık merkezi için kapasite düşürme kuralları saha talimatında bulunmalı; operatörün yalnız düz kaldırma WLL değerini kullanması engellenmelidir.",
      "Asit, alkali, yüksek sıcaklık, kıvılcım, UV, deniz ortamı veya kriyojenik hizmet gibi maruziyetler envanterde işaretlenmeli; uygun malzeme seçimi ve kısaltılmış muayene aralığı imalatçı/standart/risk değerlendirmesiyle belirlenmelidir.",
      "Kullanım öncesi gözle kontrol, temiz ve kuru depolama, askı rafı, karantina alanı ve hurdaya ayrılan aksesuarın fiziksel olarak tekrar kullanılamaz hale getirilmesi için yazılı süreç oluşturulmalıdır.",
    ],
    ifPresentTr:
      "Kayıt mevcutsa; rapordaki tekil kimlikleri sahadaki aksesuarlarla birebir eşleştirin. Ölçüm sonuçlarının standardın reddetme sınırlarıyla karşılaştırıldığını, test yükünün/cihazın izlenebilirliğini, tamir veya bileşen değişiminin kayda işlendiğini ve “uygunsuz” ekipmanın karantinaya alındığını doğrulayın.",
    ifAbsentTr:
      "Kayıt veya okunabilir etiket yoksa aksesuarı derhal karantinaya alın; kapasiteyi tahmin ederek kullandırmayın. Yetkili kişiye türüne uygun kontrol yaptırın, yeniden etiketlenmesi teknik olarak kanıtlanamayan aksesuarı hurdaya ayırın ve tekil kimlikli envanter kurun.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III kaldırma aksesuarları hükümleri.",
      "Standart — TS EN 818 serisi kısa baklalı kaldırma zincirleri ve zincir sapanlar.",
      "Standart — TS EN 13414 serisi çelik tel halat sapanlar; TS EN 1492 serisi tekstil sapanlar.",
      "Standart — TS EN 1677 serisi kaldırma aksesuarı bileşenleri.",
      "İyi uygulama — ASME B30.9/B30.26 ve HSE kaldırma aksesuarı rehberleri; yalnız şirket standardı/iyi uygulama olarak.",
    ],
    interval: {
      textTr:
        "Standartlarda veya imalatçıda daha kısa süre yoksa yılda bir; kullanım öncesi kontrol her kullanımdan önce, hasar/şok yük/ısı-kimyasal maruziyet sonrası derhal özel kontrol",
      basisCode: "TR-IS-EKIPMANLARI-2025-EK3-KALDIRMA-AKSESUAR",
      verified: true,
    },
    relatedLayers: [7, 19],
  },

  storage_tank: {
    family: "storage_tank",
    recommendationClass: "measurement_record",
    titleTr: "Atmosferik Depolama Tankı — Yasal Sınıflandırma, API 653 Bütünlük Programı ve Korozyon Doğrulaması",
    categoryLabelTr: "Tank, Silo ve Proses Bütünlüğü",
    assetLabelTr: "atmosferik depolama tankı",
    observationTr:
      "Sahada atmosferik depolama tankı görülmektedir. Tankın dış yüzeyinin düzgün görünmesi; taban altı korozyonu, ürün tarafı incelme, çatı taşıyıcı zayıflığı, oturma, kaynak çatlağı, vakum/aşırı basınç veya taşma riskini dışlamaz. Önce tankın Ek-III’teki doğru satıra girip girmediği belirlenmeli, ardından mevzuat kontrolü ile API 653 temelli proses bütünlüğü programı birbirine karıştırılmadan birlikte yürütülmelidir.",
    requirementsTr: [
      "Tank; ürün, hacim, basınç/vakum, geometrik tip, yerüstü/yeraltı konumu, dikey-yatay yapı ve imalat standardına göre sınıflandırılmalı; Türkiye mevzuatındaki bir yıllık genel tank satırı ile on yıllık özel dikey kaynaklı atmosferik tank satırından hangisine girdiği teknik dosyada gerekçelendirilmelidir.",
      "İmalatçı veri kitabı, tank çizimleri, malzeme sertifikaları, kaynak/NDT kayıtları, tasarım kodu, tasarım sıvı seviyesi, özgül ağırlık, korozyon payı, vakum/basınç sınırları ve tüm tamir-tadilat/MOC kayıtları güncel olmalıdır.",
      "API 653 esaslı muayene planında dış muayene, çalışma sırasında muayene, iç muayene ve kalınlık ölçüm kapsamı; hizmet hasar mekanizmaları, korozyon hızı, önceki bulgular ve risk üzerinden tanımlanmalıdır.",
      "Kabuk, çatı ve kritik nozul bölgeleri için tekrarlanabilir CML/TML noktaları krokilendirilmeli; UT sonuçlarından korozyon hızı, minimum gerekli kalınlık ve kalan ömür hesaplanmalı; ölçüm yöntemi/kaplama düzeltmeleri trendi bozmayacak biçimde yönetilmelidir.",
      "Taban plakaları ve anüler bölge; uygun MFL/UT yöntemleri, vakum kutusu veya ilgili NDT ile değerlendirilmelidir. Taban altı korozyon, su girişi, kenar oturması, diferansiyel oturma, tank yuvarlaklığı ve düşeyliği ayrıca ölçülmelidir.",
      "Nozullar, takviye plakaları, merdiven-platform bağlantıları, kabuk/çatı kaynakları, yüzer çatı seal ve drenajları ile kırılgan birleşim tasarımı; çatlak, kaçak, yorulma ve yük aktarımı açısından kontrol edilmelidir.",
      "Normal/acil havalandırma, vakum kırıcı, alev tutucu, seviye ölçümü ve bağımsız yüksek-yüksek seviye/taşma önleme katmanları fonksiyon testine bağlanmalı; körlenmiş veya yanlış izole edilmiş vent hatları P&ID üzerinden doğrulanmalıdır.",
      "Set/bund hacmi ve geçirimsizliği, drenaj vanalarının yönetimi, yağmur suyu tahliyesi, topraklama-eşpotansiyel, yıldırımdan korunma, ATEX bölgelendirmesi, köpük/yangın suyu düzeni ve varsa katodik koruma ölçümleri tank bütünlük dosyasına bağlanmalıdır.",
    ],
    ifPresentTr:
      "Rapor mevcutsa; önce yasal tank sınıfı ve kontrol periyodu gerekçesini, sonra API 653 muayene kapsamını inceleyin. Ölçüm haritası ile saha düzeninin eşleştiğini, minimum kalınlık hesabında gerçek ürün yoğunluğu ve tasarım yüksekliğinin kullanıldığını, korozyon hızının güvenilir ölçüm setlerine dayandığını ve bir sonraki muayene tarihinin yalnız takvimle değil kalan ömür/risk ile belirlendiğini doğrulayın.",
    ifAbsentTr:
      "Yasal kontrol veya bütünlük dosyası yoksa tankı otomatik olarak “sağlam” kabul etmeyin. Tank sınıfını yetkin mühendisle belirleyin; acil dış muayene, kaçak/oturma kontrolü ve risk temelli UT taraması yaptırın. Alt kabuk-taban birleşimi, su cepleri, nozul bölgeleri ve CUI olasılığı olan noktaları önceliklendirin; kritik şüphede seviye düşürme veya kontrollü duruş uygulayın.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III tanklar ve tesisatlar tabloları.",
      "Mevzuat — Büyük Endüstriyel Kazaların Önlenmesi ve Etkilerinin Azaltılması Hakkında Yönetmelik; kapsam dahilindeyse güvenlik yönetim sistemi.",
      "Standart — API 653 Tank Inspection, Repair, Alteration, and Reconstruction; API 650 imalat dayanağı.",
      "Standart — API 651 katodik koruma; API 2000 havalandırma; API 2350 taşma önleme.",
      "İyi uygulama — API RP 580/581 risk temelli muayene ve API 579-1/ASME FFS-1 uygunluk değerlendirmesi.",
    ],
    interval: {
      textTr:
        "Yasal sınıfa göre: Ek-III’teki genel tank satırında standart/imalatçı daha kısa süre öngörmüyorsa yılda bir; ilgili özel dikey kaynaklı atmosferik tank satırında on yılda bir. API 653 bütünlük planı hasar mekanizması ve korozyon hızına göre bu süreleri kısaltabilir; yasal süre API programıyla uzatılamaz",
      basisCode: "TR-IS-EKIPMANLARI-2025-EK3-TANK-SINIFLANDIRMA",
      verified: true,
    },
    relatedLayers: [10, 11, 13, 14, 18, 19],
  },

  pressure_vessel: {
    family: "pressure_vessel",
    recommendationClass: "measurement_record",
    titleTr: "Basınçlı Kap ve Hava Tankı — Periyodik Kontrol, Basınç Deneyi ve Kalan Ömür Doğrulaması",
    categoryLabelTr: "Basınçlı Ekipman ve Proses Bütünlüğü",
    assetLabelTr: "basınçlı kap, hava tankı",
    observationTr:
      "Sahada basınçlı kap veya hava tankı görülmektedir. Dış boya ve manometrenin çalışıyor görünmesi; cidar incelmesi, lokal korozyon, kaynak kusuru, gerilme korozyonu, emniyet ventilinin yanlış ayarı veya destek/nozul yüklerini göstermez. Fotoğraf, cihazın basınç altında güvenli olduğunu kanıtlamaz; yasal kontrol ile hasar mekanizması odaklı bütünlük değerlendirmesi birlikte incelenmelidir.",
    requirementsTr: [
      "Ekipman türü, akışkan grubu, hacim, azami izin verilebilir basınç, tasarım sıcaklığı, imalat standardı, kategori ve seri numarası etiket/veri kitabıyla doğrulanmalı; sahadaki ayarların tasarım zarfını aşmadığı gösterilmelidir.",
      "Periyodik kontrol raporu; Bakanlığın güncel formatı, İSG-KATİP sözleşmesi, EKİPNET kaydı, yetkili kişi imzası, ölçüm cihazı kalibrasyonları ve ekipmanla eşleşen fotoğraf/konum bilgilerini taşımalıdır.",
      "Yıllık kontrolde hidrostatik deney işletme veya izin verilen azami basınçta; en geç üç yılda bir ve kapsamlı bakım/tadilat sonrasında imalat standardındaki deney basıncında, bu değer yoksa izin verilen azami basıncın 1,5 katında uygulanmalı; güvenli test planı hazırlanmalıdır.",
      "Hidrostatik deney yerine NDT kullanılacaksa bunun yalnız mevzuatın izin verdiği teknik koşullarda, ilgili standarda/imalatçıya göre ve en az seviye-2 yetkin personelce yapıldığı kanıtlanmalı; üretimi durduramama gerekçesi tek başına yeterli sayılmamalıdır.",
      "UT kalınlık haritası; kabuk, bombe, nozul boyunları, drenaj ve su birikim bölgelerini kapsamalı; minimum gerekli kalınlık, korozyon hızı ve kalan ömür tasarım koduna göre hesaplanmalıdır.",
      "Emniyet ventili/rupture disk için set basıncı, kapasite dayanağı, mühür, test/kalibrasyon kaydı, tahliye hattı karşı basıncı ve izolasyon vanalarının güvenli konumu doğrulanmalıdır.",
      "Manometreler, seviye cihazları, basınç-sıcaklık alarmları, tripler, otomatik drenajlar, çek valfler, destekler ve titreşimli küçük çaplı bağlantılar fonksiyon ve mekanik bütünlük açısından kontrol edilmelidir.",
      "Kaynaklı tamir, yama, nozul ekleme, malzeme değişimi veya çalışma koşulu artışı; onaylı tamir prosedürü, WPS/PQR-kaynakçı yeterliği, NDT/PWHT kayıtları, MOC ve devreye alma öncesi güvenlik gözden geçirmesiyle kapatılmalıdır.",
    ],
    ifPresentTr:
      "Rapor mevcutsa; “1,5 kat yapıldı” ifadesine tek başına güvenmeyin. Yıllık veya üç yıllık/onarım sonrası hangi rejimin uygulandığını, test basıncının etiket ve tasarım dosyasından nasıl türetildiğini, test ortamı/sıcaklığı/hava tahliyesini, kalibrasyonlu referans manometreyi ve deformasyon-kaçak kabul kriterlerini inceleyin. UT raporunda minimum değerin nerede bulunduğunu ve hesaplanan minimum kalınlığın üzerinde olduğunu doğrulayın.",
    ifAbsentTr:
      "Geçerli rapor yoksa basınçlı kabı körlemesine test ettirmeyin veya çalıştırmaya devam etmeyin. Önce veri kitabı ve hasar mekanizması incelemesiyle güvenli test koşullarını belirleyin; gerekli UT/NDT, emniyet ventili doğrulaması ve mevzuata uygun basınç deneyini planlayın. Ciddi incelme, sızıntı, şişme veya kaynak çatlağı şüphesinde ekipmanı basınçsızlaştırıp izole edin.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III basınçlı kap ve tesisatlar.",
      "Mevzuat — Basınçlı Ekipmanlar Yönetmeliği ve uygulanabildiği ölçüde Basit Basınçlı Kaplar Yönetmeliği.",
      "Standart — API 510 Pressure Vessel Inspection Code; API 572 muayene uygulamaları; API 571 hasar mekanizmaları.",
      "Standart — API 576 basınç tahliye cihazları; API 579-1/ASME FFS-1 uygunluk değerlendirmesi.",
      "Standart — TS EN 13445 serisi veya ekipmanın imalat/tasarım standardı; TS EN ISO 16809 UT kalınlık ölçümü.",
    ],
    interval: {
      textTr:
        "Standart/imalatçı daha kısa süre öngörmüyorsa yılda bir; yıllık hidrostatik deney işletme veya izin verilen azami basınçta, en geç üç yılda bir ve kapsamlı bakım/tadilat sonrasında imalat standardındaki deney basıncında; değer yoksa izin verilen azami basıncın 1,5 katında",
      basisCode: "TR-IS-EKIPMANLARI-2025-EK3-BASINCLI",
      verified: true,
    },
    relatedLayers: [12, 13, 14, 19],
  },

  process_piping: {
    family: "process_piping",
    recommendationClass: "measurement_record",
    titleTr: "Proses Borulaması — API 570 Muayene Devreleri, Hasar Mekanizmaları ve İzolasyon Doğrulaması",
    categoryLabelTr: "Basınçlı Ekipman ve Proses Bütünlüğü",
    assetLabelTr: "proses borulaması",
    observationTr:
      "Sahada proses borulaması ve bağlantı elemanları görülmektedir. Boru hattı dışarıdan düzgün ve boyalı görünse dahi dirsek dış yarıçapı, enjeksiyon noktası, ölü bacak, düşük nokta, küçük çaplı branşman ve izolasyon altı bölgelerde kritik incelme veya çatlak gelişebilir. Fotoğraf yalnız hattın varlığını gösterir; servis, tasarım zarfı, hasar mekanizması, kalınlık trendi ve izolasyon bütünlüğü kayıtlarla doğrulanmalıdır.",
    requirementsTr: [
      "Güncel P&ID, hat listesi, line class/specification, servis akışkanı, tasarım/işletme basınç-sıcaklığı, korozyon payı, malzeme ve yalıtım bilgileri ile sahadaki hat numarası ve akış yönü eşleştirilmelidir.",
      "Hatlar API 570 veya eşdeğer yetkinlikte bir program kapsamında muayene devrelerine ayrılmalı; risk sınıfı, hasar mekanizmaları, önceki bulgular ve kritikiyet üzerinden yazılı muayene planına bağlanmalıdır.",
      "CML/TML noktaları yalnız kolay erişilen düz borularda değil; dirsek, tee, redüksiyon, enjeksiyon/karışım noktası, ölü bacak, düşük nokta, kontrol vanası sonrası ve CUI riski yüksek bölgelerde tekrarlanabilir krokiyle tanımlanmalıdır.",
      "UT sonuçlarından kısa ve uzun dönem korozyon hızları, minimum gerekli kalınlık ve kalan ömür hesaplanmalı; lokal incelme, pitting, erozyon-korozyon, SCC, hidrojen hasarı, yüksek sıcaklık sürünmesi veya yorulma gibi olası mekanizmalar için uygun NDT seçilmelidir.",
      "Askı, destek, yaylı askı, kılavuz, ankraj, kompansatör ve genleşme düzeni; sıcak/soğuk konum, sürtünme, çökmüş destek ve nozula aktarılan yük açısından incelenmeli; titreşimli küçük çaplı bağlantılar ayrıca taranmalıdır.",
      "Vana gövdeleri, flanşlar, körler, esnek hortumlar, drenaj/ventler, basınç tahliye ve blowdown hatları ile geçici kelepçe/yamalar envanterlenmeli; geçici tamire mühendislik onaylı son tarih ve kalıcı onarım planı verilmelidir.",
      "Hat açma işi; kimyasal/enerji boşaltma, drenaj-havalandırma, pozitif izolasyon, körleme veya çift blok-boşaltma gereği, LOTO ve sıfır enerji doğrulamasıyla izin sistemine bağlanmalı; yalnız vana kapatmak güvenli izolasyon sayılmamalıdır.",
      "Kaynaklı tamir ve tadilatlarda malzeme doğrulama/PMI, WPS/PQR, kaynakçı yeterliği, NDT, PWHT ve basınç/sızdırmazlık testi kayıtları bulunmalı; servis/akışkan/kapasite değişiklikleri MOC ve PSSR ile kapatılmalıdır.",
    ],
    ifPresentTr:
      "Kayıt mevcutsa; rapordaki hat sınıfı ve servis bilgisini sahadaki P&ID ile karşılaştırın. Ölçüm noktalarının aynı noktadan tekrar alınmasını sağlayan koordinat/kroki bulunduğunu, ölçüm hatasının korozyon hızına etkisinin ele alındığını, kritik CUI/ölü bacak/enjeksiyon noktalarının kapsam dışında bırakılmadığını ve kalan ömrü aşan muayene tarihi verilmediğini doğrulayın.",
    ifAbsentTr:
      "Muayene devresi veya kalınlık trendi yoksa hattı tek parça olarak rastgele ölçtürmeyin. Önce servis ve hasar mekanizması analizi yapın, CML/TML planını hazırlayın ve başlangıç ölçümünü kaydedin. Kaçak, aktif korozyon, çökmüş destek, şiddetli titreşim veya geçici tamir görülüyorsa proses koşullarını düşürün ya da hattı kontrollü biçimde izole edin.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği; Ek-III kapsamına giren basınçlı tesisatlar ve genel güvenli kullanım hükümleri.",
      "Mevzuat — BEKRA kapsamındaki kuruluşlarda mekanik bütünlük, işletim kontrolü ve değişiklik yönetimi yükümlülükleri.",
      "Standart — API 570 Piping Inspection Code; API RP 574 piping system inspection practices.",
      "Standart — API 571 hasar mekanizmaları; API RP 578 malzeme doğrulama; API 579-1/ASME FFS-1.",
      "Standart — ASME B31.3 veya hattın tasarım/imalat standardı; TS EN ISO 16809 UT kalınlık ölçümü.",
    ],
    interval: {
      textTr:
        "Proses borulaması için tek bir genel takvim periyodu atanmaz; imalat/tasarım standardı, imalatçı talimatı, servis hasar mekanizması, korozyon hızı, kalan ömür ve risk değerlendirmesine göre yazılı muayene planı belirlenir. Ek-III’te özel olarak kapsama giren tesisat varsa ilgili yasal azami süre ayrıca uygulanır",
      basisCode: "TR-IS-EKIPMANLARI-2025-M7-RISK-BASED + API-570-PLAN",
      verified: true,
    },
    relatedLayers: [10, 11, 12, 13, 14],
  },

  electrical_panel: {
    family: "electrical_panel",
    recommendationClass: "measurement_record",
    titleTr: "Elektrik Panosu — Proje Uygunluğu, Koruma Düzeni ve Ölçüm Sonuçlarının Doğrulanması",
    categoryLabelTr: "Elektrik Tesisatı ve Tehlikeli Enerji",
    assetLabelTr: "elektrik panosu, dağıtım tablosu",
    observationTr:
      "Sahada elektrik panosu veya dağıtım tablosu görülmektedir. Kapakların kapalı ve panonun yeni görünmesi; kısa devre dayanımını, koruma iletkeni sürekliliğini, otomatik açma süresini, yalıtım direncini, RCD işlevini veya koruma koordinasyonunu göstermez. Fotoğraf yalnız görünür fiziksel düzeni değerlendirir; güvenlik iddiası proje, hesap, ölçüm ve fonksiyon testleriyle kurulmalıdır.",
    requirementsTr: [
      "Elektrik tesisatı periyodik kontrolü, güncel tek hat şeması ve onaylı/as-built proje üzerinden yapılmalı; pano adı, besleme kaynağı, ana kesici, devreler, kablo kesitleri, koruma cihazları ve topraklama sistemi sahayla eşleştirilmelidir.",
      "Rapor; yetkili elektrik mühendisi/teknik personel kapsamı, İSG-KATİP sözleşmesi, EKİPNET kaydı, Bakanlığın güncel formatı, kullanılan ölçüm cihazlarının seri numarası ve geçerli kalibrasyon kayıtlarını içermelidir.",
      "Koruma iletkeni ve eşpotansiyel sürekliliği, çevrim/arıza döngü empedansı ve otomatik açma koşulu; tesisatın TN/TT/IT düzenine ve koruma cihazının açma karakteristiğine göre devre bazında doğrulanmalı; tek bir genel topraklama direnci değeriyle yetinilmemelidir.",
      "Yalıtım direnci, polarite, faz sırası ve RCD/RCBO açma akımı-açma süresi ölçülmeli; test sonuçları ilgili sınırlarla sayısal olarak karşılaştırılmalı, yalnız test butonuna basılması ölçüm yerine geçmemelidir.",
      "Kısa devre akımı ve kesme kapasitesi, seçicilik/koordinasyon, aşırı akım ve termik koruma ayarları ile kablo taşıma kapasitesi proje hesaplarıyla uyumlu olmalı; ayarı mühürsüz veya gelişigüzel değiştirilmiş röleler düzeltilmeden kabul edilmemelidir.",
      "Pano gövdesi, kapı eşpotansiyeli, IP koruma, bara ve terminal örtüleri, kablo rakorları, nötr-PE ayrımı, kapı interlockları, iç ark/dokunma koruması ve kullanılmayan açıklıklar fiziksel olarak kontrol edilmelidir.",
      "Termal kamera taraması uygun yük altında ve emissivite/yansımalar dikkate alınarak yapılabilir; ancak termografi, elektriksel güvenlik ölçümlerinin veya bağlantı torku/bakım doğrulamasının yerine geçen tek başına uygunluk belgesi sayılmamalıdır.",
      "Pano önü çalışma mesafesi, yetkisiz erişim, etiketleme, ark/elektrik şoku sınırları, acil ayırma, LOTO noktaları ve elektrik işinde yetkilendirme/KKD prosedürü saha doğrulamasına bağlanmalıdır.",
    ],
    ifPresentTr:
      "Rapor mevcutsa; tek hat şemasının güncel revizyonunu, cihaz kalibrasyonunu ve her devre için ölçülen sayısal sonuçları inceleyin. Raporun yalnız “uygundur” ibaresi taşımadığını; RCD açma süresi, çevrim empedansı, PE sürekliliği ve yalıtım sonuçlarının koruma cihazı ayarlarıyla karşılaştırıldığını doğrulayın. Projesiz yapılan kontrolü tam uygunluk kanıtı kabul etmeyin.",
    ifAbsentTr:
      "Geçerli rapor veya proje yoksa yetkili kişiye önce as-built tek hat şeması ve devre envanteri hazırlatın; ardından mevzuata uygun ölçüm ve fonksiyon testlerini yaptırın. Açık bara, yanık izi, gevşek bağlantı, korumasız açıklık, gövde gerilimi veya çalışmayan RCD şüphesinde ilgili panoyu enerjisiz bırakın ve LOTO uygulayın.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III elektrik tesisatı tablosu.",
      "Mevzuat — Elektrik İç Tesisleri Yönetmeliği; Elektrik Tesislerinde Topraklamalar Yönetmeliği.",
      "Standart — TS HD 60364-4-41 elektrik çarpmasına karşı koruma; TS HD 60364-6 doğrulama.",
      "Standart — TS EN IEC 61439 serisi alçak gerilim anahtarlama ve kontrol düzenleri.",
      "Standart — TS EN 60204-1 makinelerin elektrik donanımı; uygulanabildiği ölçüde.",
    ],
    interval: {
      textTr:
        "Proje/standart/imalatçı daha kısa süre öngörmüyorsa yılda bir; tesisin yer değiştirmesi, esaslı tadilat, yangın/su basması, koruma düzeni değişikliği veya ciddi arıza sonrasında tekrar kullanımdan önce özel kontrol",
      basisCode: "TR-IS-EKIPMANLARI-2025-EK3-ELEKTRIK-TESISATI",
      verified: true,
    },
    relatedLayers: [5, 13, 18, 19],
  },

  earthing_system: {
    family: "earthing_system",
    recommendationClass: "measurement_record",
    titleTr: "Koruma Topraklaması ve Eşpotansiyel Sistem — Süreklilik, Açma Koşulu ve Proje Doğrulaması",
    categoryLabelTr: "Elektrik Tesisatı ve Tehlikeli Enerji",
    assetLabelTr: "gövde topraklaması gereken ekipman",
    observationTr:
      "Sahada iletken gövdeli elektrikli ekipman görülmektedir. Sarı-yeşil bir iletkenin varlığı, gövdenin gerçekten ana topraklama barasına kesintisiz bağlı olduğunu veya arıza akımının koruma cihazını süresinde açtıracağını kanıtlamaz. Güvenlik; sistem tipi, koruma düzeni, süreklilik, elektrot/çevrim ölçümleri ve eşpotansiyel bağlantıların birlikte değerlendirilmesiyle doğrulanmalıdır.",
    requirementsTr: [
      "Tesisin TN, TT veya IT topraklama düzeni, ana topraklama barası, elektrotlar, PE/PEN iletkenleri ve eşpotansiyel kuşaklama as-built proje üzerinde gösterilmeli; sahadaki bağlantılar projeyle eşleştirilmelidir.",
      "Her sabit makine, kaynak makinesi, kompresör, metal pano, kablo tavası ve iletken yabancı kısım için gövde-ana topraklama barası koruma iletkeni sürekliliği ekipman bazında ölçülmeli ve tekil envanterle kaydedilmelidir.",
      "Topraklama elektrodu direnci veya arıza döngü empedansı; koruma cihazının tipi, açma akımı ve izin verilen açma süresiyle birlikte değerlendirilmelidir. Tüm tesislere uygulanabilecek tek bir “ohm sınırı” uydurulmamalıdır.",
      "Ana ve ilave eşpotansiyel bağlantılar; borular, yapı çeliği, tanklar, kablo tavaları ve iletken hizmet hatlarında gevşeklik, korozyon, boya altında yalıtılma ve uygunsuz kesit açısından kontrol edilmelidir.",
      "Yıldırımdan korunma sistemi varsa yakalama uçları, iniş iletkenleri, test klemensleri, topraklayıcı düzeni, ayırma mesafesi ve SPD koordinasyonu TS EN 62305 temelli proje ve ölçüm kayıtlarıyla doğrulanmalıdır.",
      "ATEX veya yanıcı sıvı/gaz/toz alanlarında statik elektriğe karşı eşpotansiyel bağlantı, dolum-boşaltma bonding’i, hortum iletkenliği ve topraklama izleme interlockları proses koşulunda test edilmelidir.",
      "Seyyar ekipman, uzatma kablosu, fiş-priz ve kablo makarası için PE sürekliliği, mekanik hasar, uygun IP ve RCD koruması doğrulanmalı; sınıf II ekipman ile topraklama gerektiren sınıf I ekipman ayrımı doğru yapılmalıdır.",
      "Yeni ekipman eklenmesi, pano/trafo değişikliği, bina tadilatı, yıldırım olayı, kazı veya topraklayıcı onarımı sonrasında proje ve hesaplar güncellenmeli; ölçüm cihazı kalibrasyonu ve ölçüm koşulları rapora yazılmalıdır.",
    ],
    ifPresentTr:
      "Ölçüm kaydı mevcutsa; ekipman envanterinin sahayla eşleştiğini, yalnız elektrot direnci değil PE sürekliliği ve otomatik açma koşulunun da değerlendirildiğini inceleyin. Ölçüm yöntemini, prob yerleşimini, toprak nemi/bağlantı ayırma durumunu ve cihaz kalibrasyonunu doğrulayın; bir binanın tek nokta ölçümünü tüm makineler için uygunluk saymayın.",
    ifAbsentTr:
      "Kayıt yoksa, gövdeye rastgele topraklama kablosu bağlayıp işi kapatmayın. Yetkili elektrik mühendisine sistem tipini ve koruma düzenini doğrulatın; proje, PE sürekliliği, çevrim/elektrot ölçümü ve açma koşulu değerlendirmesini birlikte yaptırın. Kopuk PE, gövde gerilimi veya yanmış bağlantı şüphesinde ekipmanı enerjisiz bırakın.",
    referencesTr: [
      "Mevzuat — Elektrik Tesislerinde Topraklamalar Yönetmeliği.",
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III elektrik/topraklama tesisatı.",
      "Standart — TS HD 60364-5-54 topraklama düzenleri ve koruma iletkenleri; TS HD 60364-6 doğrulama.",
      "Standart — TS EN 62305 serisi yıldırımdan korunma.",
      "İyi uygulama — IEC TS 60079-32-1 patlayıcı ortamlarda elektrostatik tehlikeler; yalnız uygulanabilir alanlarda.",
    ],
    interval: {
      textTr:
        "Proje/standart daha kısa süre öngörmüyorsa yılda bir; tesis değişikliği, yıldırım/yangın/su basması, topraklayıcıya etki eden kazı veya ciddi elektrik arızası sonrasında tekrar kullanımdan önce özel kontrol",
      basisCode: "TR-IS-EKIPMANLARI-2025-EK3-TOPRAKLAMA",
      verified: true,
    },
    relatedLayers: [5, 6, 13, 19],
  },

  gas_cylinder: {
    family: "gas_cylinder",
    recommendationClass: "site_verification",
    titleTr: "Basınçlı Gaz Tüpleri — Ürün Kimliği, Test Damgası, Uyumluluk ve Kullanım Noktası Güvenliği",
    categoryLabelTr: "Kimyasal, Basınçlı Gaz ve Yangın Güvenliği",
    assetLabelTr: "basınçlı gaz tüpü",
    observationTr:
      "Sahada basınçlı gaz tüpü görülmektedir. Tüpün boyası veya genel görünümü gaz kimliğini, periyodik muayene süresini, vana/regülatör uyumunu, iç korozyonu ya da yanlış gaz komşuluğunu göstermez. Taşınabilir gaz tüpleri için iş ekipmanı periyodik kontrolü, ADR/taşınabilir basınçlı ekipman ve işyeri kimyasal güvenliği hükümleri aynı belge değildir; doğru rejim ürün ve kullanım biçimine göre belirlenmelidir.",
    requirementsTr: [
      "Gaz envanteri; UN numarası, gazın ticari/kimyasal adı, tehlike sınıfı, dolu-boş-karantina durumu, tüp seri numarası ve kullanım noktasını içermeli; tüp üzerindeki kalıcı damga ve etiket SDS ile eşleşmelidir. Renge tek başına güvenilmemelidir.",
      "Tüpün uygunluk işaretleri, imalat standardı, periyodik muayene/test damgası ve son geçerlilik tarihi; ADR/taşınabilir basınçlı ekipman rejimine göre yetkili dolum/dağıtım zincirinden doğrulanmalıdır. Damgası okunmayan veya süresi geçen tüp kullanılmamalıdır.",
      "Tüpler dik konumda ve gövdeyi tutan iki seviyeli zincir/kelepçe benzeri düzenle devrilmeye karşı sabitlenmeli; kullanılmayan tüpte vana koruma başlığı takılı olmalı, vana veya başlıktan kaldırma yapılmamalıdır.",
      "Yanıcı, oksitleyici, toksik, korozif ve inert gazlar için ürün özellikleri, miktar, bina/alan koşulları ve geçerli standartlara dayalı yazılı uyumluluk-yerleşim matrisi hazırlanmalıdır. Yabancı bir mevzuattaki sabit mesafeler Türkiye için otomatik yasal sınır gibi kopyalanmamalıdır.",
      "Dolu, boş ve karantina tüpleri işaretli alanlarda ayrılmalı; alan serin, kuru, darbe/ısı/ateşleme kaynaklarından uzak ve gazın yoğunluğuna uygun havalandırmalı olmalı; kaçış yolları ve elektrik panosu önleri depolama için kullanılmamalıdır.",
      "Regülatör, vana, adaptör ve hortum gaz hizmetine ve basınca uygun olmalı; oksijen ekipmanında yağ-gres bulunmamalı; yakıcı gaz sistemlerinde uygun çek valf/alev geri tepme emniyet cihazı ve kontrollü sızdırmazlık testi uygulanmalıdır.",
      "Taşıma, tüp arabası ve koruma başlığıyla yapılmalı; sürükleme, yuvarlama, mıknatısla kaldırma veya sapanı gövdeye dolama yasaklanmalıdır. Kapalı araçta taşıma/uzun süre bırakma boğucu gaz birikimi yönünden ayrıca kontrol edilmelidir.",
      "Toksik/boğucu/yanıcı gazlarda kaçak senaryosu, alarm-gaz algılama gereği, acil izolasyon, tahliye, ilk yardım ve müdahale sınırları yazılı olmalı; çalışanlar gaz özellikleri ve vana hasarında yapılmayacak müdahaleler konusunda uygulamalı eğitilmelidir.",
    ],
    ifPresentTr:
      "Depolama matrisi ve kayıt mevcutsa; gaz envanteriyle sahadaki tüpleri tek tek örnekleyin, test damgası ve gaz etiketini okuyun, regülatör bağlantısının gaz hizmetine uygunluğunu ve sabitlemenin vana bölgesine yük bindirmediğini doğrulayın. Matrisin yabancı bir kuraldan kopyalanmış sabit mesafeler yerine gerçek ürün/SDS ve yerel mevzuata dayandığını kontrol edin.",
    ifAbsentTr:
      "Kimlik, test damgası veya uyumluluk kaydı yoksa tüpü kullanımdan çıkarıp havalandırmalı karantina alanına alın; vana üzerinde deneme yapmayın ve içeriğini koklayarak belirlemeye çalışmayın. Yetkili tedarikçi/dolum kuruluşuyla kimlik ve test geçerliliğini doğrulayın; gaz envanteri, uyumluluk matrisi ve kullanım noktası kontrolünü tamamlayın.",
    referencesTr: [
      "Mevzuat — Kimyasal Maddelerle Çalışmalarda Sağlık ve Güvenlik Önlemleri Hakkında Yönetmelik; Patlayıcı Ortamların Tehlikelerinden Korunma Yönetmeliği.",
      "Mevzuat — Tehlikeli Maddelerin Karayoluyla Taşınması düzenlemeleri, ADR ve taşınabilir basınçlı ekipman mevzuatı; kapsama göre.",
      "Standart — TS EN ISO 11625 Gaz tüpleri — Güvenli elleçleme; TS EN ISO 7225 ihtiyati etiketler.",
      "Standart — TS EN ISO 11114 serisi gaz tüpleri ve vanaları için malzeme-gaz uyumluluğu.",
      "İyi uygulama — EIGA gaz tüpü depolama/elleçleme rehberleri ve OSHA/HSE kaynakları; Türk mevzuatının yerine değil boşluk analizi için.",
    ],
    interval: {
      textTr:
        "Tek bir genel iş ekipmanı periyodu atanmaz; tüpün periyodik muayene/test tarihi gaz türü ve tüp standardına göre omuz damgası ile ADR/taşınabilir basınçlı ekipman hükümlerinden doğrulanır. İşyeri depolama ve kullanım kontrolleri risk değerlendirmesine göre, ayrıca her teslim alma ve kullanım öncesinde yapılır",
      basisCode: "TR-ADR-TPED-CYLINDER-SPECIFIC + TR-CHEMICAL-WORKPLACE",
      verified: true,
    },
    relatedLayers: [10, 12, 13, 18],
  },

  mobile_crane: {
    family: "mobile_crane",
    recommendationClass: "periodic_inspection_record",
    titleTr: "Mobil Vinç — Periyodik Kontrol, Kaldırma Planı ve Zemin Taşıma Gücü Doğrulaması",
    categoryLabelTr: "Kaldırma ve İletme Ekipmanları",
    assetLabelTr: "mobil vinç",
    observationTr:
      "Sahada mobil vinç görülmektedir. Vincin çalışıyor olması veya bomun gözle sağlam görünmesi; seçilen bom/jib-kontra ağırlık konfigürasyonunda kapasiteyi, zeminin ayak reaksiyonlarını taşıyıp taşımadığını, yük moment sınırlayıcının doğru kalibre edildiğini ya da kaldırma operasyonunun planlandığını göstermez. Güvenlik, ekipman muayenesi ile her kaldırmaya özel mühendislik ve saha kontrollerinin birlikte doğrulanmasını gerektirir.",
    requirementsTr: [
      "Periyodik kontrol raporu sahadaki şasi ve üst yapı seri numaralarıyla eşleşmeli; İSG-KATİP sözleşmesi, EKİPNET kaydı, Bakanlık güncel rapor formatı, yetkili kişi ve kalibrasyonlu test yükü/ölçüm cihazı şartlarını taşımalıdır.",
      "Yıllık çalışma kapasitesi deneyi ile en geç üç yılda bir veya kapsamlı bakım/tadilat sonrasındaki statik-dinamik deneyler; bom uzunluğu, yarıçap, reeving, jib, kontra ağırlık ve ayak konfigürasyonu açıkça yazılarak yapılmalıdır.",
      "Kaldırma planı; yük ağırlığı ve ağırlık merkezi, kaldırma aparatları, başlangıç-bitiş yarıçapları, bom/jib konfigürasyonu, kapasite yüzdesi, rüzgâr sınırı, engeller, enerji hatları, kör alanlar, kaçış rotası ve olağan dışı durumları içermelidir.",
      "Zemin taşıma gücü ve yeraltı boşluğu/hatları değerlendirilmeli; üretici ayak reaksiyonlarından gerekli plaka/mat boyutu hesaplanmalı, ayaklar tam açılmıyorsa ilgili kısmi ayak kapasite tablosu dışında çalışma yapılmamalıdır.",
      "Bom, jib, teleskop pimleri, kaynaklar, döner tabla bağlantıları, halat-tambur-kasnak, kanca, hidrolik silindir/hatlar, outriggers, şasi, lastik ve frenler ölçülebilir kabul kriterleriyle kontrol edilmeli; kritik onarım bölgelerinde NDT kaydı bulunmalıdır.",
      "Yük moment/kapasite göstergesi, anti-two-block, bom açısı/uzunluk sensörleri, sınırlandırıcılar, seviye göstergesi, acil durdurma ve ikazlar gerçek konfigürasyonda fonksiyon testine tabi tutulmalı; bypass veya arıza kodu bulunmamalıdır.",
      "Vinç operatörü, sapancı/işaretçi ve kaldırma sorumlusu görevleri yazılı atanmalı; tek haberleşme yöntemi, kör kaldırmada işaretçi, 360 derece dönme/sıkışma alanı ve yük altına giriş yasağı saha bariyerleriyle uygulanmalıdır.",
      "Tandem kaldırma, personel sepeti, pick-and-carry, uzun bomda yüksek rüzgâr, gezer yük veya yüksek riskli kritik kaldırmalar için özel mühendislik planı, ilave onay, deneme ve kurtarma senaryosu hazırlanmalıdır.",
    ],
    ifPresentTr:
      "Rapor ve kaldırma planı mevcutsa; rapordaki vinç konfigürasyonu ile sahadaki kurulumun aynı olduğunu, yük tablosunun üreticiye ait doğru dilimden okunduğunu, kanca altı toplam ağırlığın hesaba katıldığını ve zemin hesabında en yüksek ayak reaksiyonunun kullanıldığını doğrulayın. Operatör ekranında arıza/bypass kaydı, ayak uzatma yüzdesi ve kapasite yüzdesini fiilen kontrol edin.",
    ifAbsentTr:
      "Geçerli rapor veya kaldırma planı yoksa yükü kaldırmayın. Vinci güvenli konuma alın, çalışma alanını izole edin; yetkili kişiye mevzuata uygun periyodik kontrol yaptırın ve yetkin kaldırma planlayıcısına yük, yarıçap, konfigürasyon ve zemin taşıma hesabını içeren plan hazırlatın. Zemini tahminle veya yalnız operatör tecrübesiyle kabul etmeyin.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III kaldırma ve iletme ekipmanları.",
      "Bakanlık kriteri — Mobil vinçler için güncel periyodik kontrol raporu/kriterleri ve EKİPNET.",
      "Standart — TS EN 13000 Mobil vinçler; TS ISO 9927-1 vinç muayeneleri.",
      "Standart — ISO 12480-1 Vinçlerin güvenli kullanımı; üretici yük tabloları ve kurulum talimatları.",
      "İyi uygulama — HSE LOLER kaldırma operasyonlarının yetkin kişi tarafından planlanması ve denetlenmesi.",
    ],
    interval: {
      textTr:
        "Standart/imalatçı daha kısa süre öngörmüyorsa yılda bir; yıllık çalışma kapasitesi deneyi, en geç üç yılda bir veya kapsamlı bakım/tadilat sonrasında statik-dinamik deneyler; kurulum ve kullanım öncesi kontroller her kaldırma/kurulum için ayrıca",
      basisCode: "TR-IS-EKIPMANLARI-2025-EK3-MOBIL-VINC",
      verified: true,
    },
    relatedLayers: [3, 4, 7, 8, 18, 19],
  },

  hoist: {
    family: "hoist",
    recommendationClass: "periodic_inspection_record",
    titleTr: "Caraskal ve Monoray Kaldırıcı — Taşıyıcı Bağlantı, Fren ve Yük Zinciri Doğrulaması",
    categoryLabelTr: "Kaldırma ve İletme Ekipmanları",
    assetLabelTr: "caraskal",
    observationTr:
      "Sahada manuel veya motorlu caraskal görülmektedir. Caraskal gövdesinin sağlam görünmesi, asıldığı kiriş/ankrajın kapasitesini, yük freninin tutma performansını, zincirin uzamasını veya üst-alt limitlerin işlevini göstermez. Ekipmanın muayenesi, taşıyıcı sistem ve bağlantı noktasının ayrı mühendislik doğrulamasıyla tamamlanmalıdır.",
    requirementsTr: [
      "Caraskal tekil kimlik, seri numarası, WLL, kaldırma yüksekliği, zincir/halat ölçüsü ve güç kaynağı bilgisiyle etiketlenmeli; periyodik kontrol raporu İSG-KATİP, EKİPNET ve güncel Bakanlık formatı şartlarını taşımalıdır.",
      "Caraskalın bağlı olduğu kiriş, monoray, trolley, ankraj, mapalı plaka veya geçici askı noktası; caraskal WLL’sini ve dinamik etkileri taşıyacak mühendislik hesabı/etiketiyle doğrulanmalı; konstrüksiyon üzerindeki rastgele noktaya asma yapılmamalıdır.",
      "Yıllık çalışma kapasitesi deneyi ile en geç üç yılda bir veya kapsamlı bakım/tadilat sonrasındaki statik-dinamik deneyler, caraskal ve taşıyıcı bağlantıyı birlikte temsil edecek biçimde kalibrasyonlu yükle kaydedilmelidir.",
      "Yük zinciri veya tel halat; çap kaybı, uzama, bükülme, çatlak, tel kırığı, korozyon, yağlama ve zincir ceplerine oturma açısından ölçülmeli; zincirin ters dönmesi, kaynaklı tamiri veya uygunsuz kısaltması kabul edilmemelidir.",
      "Kanca, mandal, döner bağlantı, tambur/cep çarkı, kasnak, halat kılavuzu ve trolley tekerlekleri; aşınma, ağız açıklığı, yan yük ve raydan çıkma riski yönünden türüne özel reddetme kriterleriyle kontrol edilmelidir.",
      "Yük freni, mekanik kilit, üst-alt limit, aşırı yük kavraması/sınırlayıcı, acil durdurma ve enerji kesme düzeni gerçek yük altında fonksiyon testine tabi tutulmalı; freni tutmayan ekipman ayar yapılarak deneme amaçlı bile kullanılmamalıdır.",
      "Elektrikli caraskalda pendant kumanda, yön işaretleri, kontrol gerilimi, kablo taşıma sistemi ve PE sürekliliği; pnömatikte hortum/bağlantılar ve hava kesme; manuelde el zinciri ve serbest bırakma düzeni kontrol edilmelidir.",
      "Yan çekme, yük sürükleme, iki caraskalla senkron olmayan kaldırma, kancaya doğrudan yük bağlama veya personel kaldırma yasakları; kullanım öncesi kontrol ve kusur bildirim talimatında açıkça yer almalıdır.",
    ],
    ifPresentTr:
      "Rapor mevcutsa; caraskal seri numarası kadar taşıyıcı kiriş/ankrajın da tanımlandığını, test yükünün askı noktasını kapsadığını, zincir ölçümlerinin sayısal verildiğini ve fren-limit fonksiyonlarının gerçek yükte doğrulandığını inceleyin. Aynı kirişte birden fazla caraskal varsa eşzamanlı en elverişsiz yük durumunun hesaba katıldığını kontrol edin.",
    ifAbsentTr:
      "Geçerli rapor veya taşıyıcı bağlantı kapasitesi bilinmiyorsa caraskalı kullanımdan çıkarın ve kancayı/pendantı “kullanma” etiketiyle kontrol altına alın. Yetkili kişiye periyodik kontrol, yük deneyi ve kiriş/ankraj mühendislik doğrulaması yaptırın; kapasitesi kanıtlanmamış geçici askı noktasını tahminle kullanmayın.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III kaldırma ekipmanları.",
      "Bakanlık kriteri — Caraskal/monoray kaldırıcılar için güncel periyodik kontrol kriterleri.",
      "Standart — TS EN 13157 Elle çalıştırılan vinçler; TS EN 14492-2 Güç tahrikli vinçler ve caraskallar.",
      "Standart — TS ISO 9927-1 genel muayene ilkeleri; üretici bakım ve reddetme kriterleri.",
      "İyi uygulama — HSE kaldırma ekipmanı ve askı noktası bütünlüğü yaklaşımı.",
    ],
    interval: {
      textTr:
        "Standart/imalatçı daha kısa süre öngörmüyorsa yılda bir; yıllık çalışma kapasitesi deneyi, en geç üç yılda bir veya kapsamlı bakım/tadilat sonrasında statik-dinamik deney; kullanım öncesi kontrol her vardiya/kullanım öncesinde",
      basisCode: "TR-IS-EKIPMANLARI-2025-EK3-CARASKAL",
      verified: true,
    },
    relatedLayers: [4, 7, 19],
  },

  forklift: {
    family: "forklift",
    recommendationClass: "periodic_inspection_record",
    titleTr: "Forklift — Periyodik Kontrol, Ataşmanlı Kapasite ve Saha Trafik Güvenliği Doğrulaması",
    categoryLabelTr: "Mobil İş Ekipmanları ve Saha Trafiği",
    assetLabelTr: "forklift",
    observationTr:
      "Sahada forklift görülmektedir. Forkliftin hareket etmesi ve çatalların yükü kaldırması; gerçek ataşmanlı kapasiteyi, mast/zincir yıpranmasını, fren performansını, stabiliteyi veya yaya çarpışma riskini doğrulamaz. Fotoğraf ekipmanı tanımlar; güvenlik periyodik kontrol, vardiya öncesi kontrol, operatör yetkinliği ve tesis trafik planının birlikte değerlendirilmesini gerektirir.",
    requirementsTr: [
      "Periyodik kontrol raporu, şasi seri numarası ve enerji türüyle eşleşmeli; İSG-KATİP sözleşmesi, EKİPNET kaydı, güncel rapor formatı, yetkili kişi ve kalibrasyonlu yük/ölçüm cihazı şartlarını taşımalıdır.",
      "Kapasite plakası; mast tipi, maksimum kaldırma yüksekliği, yük merkezi ve takılı ataşmanı göstermelidir. Side-shift, balya kıskacı, rotator, uzatma veya başka ataşman kapasiteyi düşürüyorsa üretici/onaylı yeni kapasite plakası olmadan kullanılmamalıdır.",
      "Çatallar; topuk çatlağı, kalınlık kaybı, seviye farkı, kilit ve taşıyıcıya oturma; mast, makaralar, zincirler ve ankrajlar ise uzama, aşınma, eşitlik, yağlama ve deformasyon açısından ölçülmelidir.",
      "Servis ve park frenleri, direksiyon, lastik/jantlar, hidrolik silindir-hortumlar, kaldırma/eğme fonksiyonları, korna, ışık, geri ikaz ve varsa hız sınırlama sistemi gerçek kullanım koşulunda test edilmelidir.",
      "Üst koruyucu, yük sırtlığı, operatör kabini, emniyet kemeri ve koltuk/kapı interlockları bulunmalı ve kullanılmalı; devrilmede atlama yerine koruyucu yapı içinde kalma eğitimi uygulanmalıdır.",
      "Tesis trafik planı; yaya-araç ayrımı, bariyerli yollar, kavşaklar, kör köşeler, hız limitleri, tek yön, rampa, kapı ve yükleme alanı kurallarını içermeli; yalnız sesli ikaza güvenilmemelidir.",
      "Akülü forklift şarj alanında havalandırma, asit sıçrama ve ateşleme kaynağı kontrolü; LPG/dizel ekipmanda tüp/yakıt değişimi, sızıntı, egzoz ve kapalı alan kullanımı; hidrojen, CO ve yangın riskleri açısından yönetilmelidir.",
      "Operatör yetkilendirme ve uygulamalı yeterlik değerlendirmesi, günlük kontrol formu ve anahtar yönetimi bulunmalı; palet üzerinde, çatallarda veya onaysız sepetle insan kaldırma engellenmelidir.",
    ],
    ifPresentTr:
      "Rapor mevcutsa; kapasite plakasındaki ataşman ve yük merkezini sahadaki konfigürasyonla karşılaştırın. Çatal kalınlığı/zincir uzaması gibi ölçümlerin sayısal olduğunu, fren test yöntemini, emniyet kemeri-interlock işlevini ve ağır kusur sonrası ikinci kontrolü inceleyin. Ayrıca son kaza/çarpışma kayıtları ile tesis trafik planındaki kör noktalarda fiili gözlem yapın.",
    ifAbsentTr:
      "Geçerli rapor yoksa veya kapasite plakası ataşmanla uyuşmuyorsa forklifti yük taşımada kullanmayın; anahtarı kontrollü olarak alın. Yetkili kişiye periyodik kontrol yaptırın, üretici/onaylı kapasite verisini temin edin ve trafik planındaki kritik ayrımları kurun. Çatal çatlağı, zincir hasarı, fren zayıflığı veya kemer eksikliğinde ekipmanı derhal karantinaya alın.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III istif makineleri.",
      "Bakanlık kriteri — Forklift/istif makineleri için güncel periyodik kontrol rapor ve kriterleri.",
      "Standart — TS EN ISO 3691-1 Endüstriyel araçlar — Güvenlik kuralları; TS ISO 5057 çatal kolların muayenesi.",
      "Standart — ISO 22915 serisi endüstriyel araçların stabilite doğrulaması; üretici kapasite tabloları.",
      "İyi uygulama — ÇSGB forklift rehberleri; HSE lift truck güvenli kullanım yaklaşımı.",
    ],
    interval: {
      textTr:
        "Standart/imalatçı daha kısa süre öngörmüyorsa yılda bir; kaza, devrilme, mast/çatal onarımı, ataşman veya kapasiteyi etkileyen değişiklik sonrası tekrar kullanımdan önce özel kontrol; vardiya başlangıcında kullanım öncesi kontrol",
      basisCode: "TR-IS-EKIPMANLARI-2025-EK3-ISTIF-MAKINELERI",
      verified: true,
    },
    relatedLayers: [6, 8, 9, 17, 18, 19],
  },

  mewp: {
    family: "mewp",
    recommendationClass: "periodic_inspection_record",
    titleTr: "Yükseltilebilir Çalışma Platformu — Periyodik Kontrol, Zemin-Sıkışma Riski ve Kurtarma Doğrulaması",
    categoryLabelTr: "Yüksekte Çalışma ve Mobil İş Ekipmanları",
    assetLabelTr: "yükseltilebilir çalışma platformu",
    observationTr:
      "Sahada makaslı, eklemli veya teleskopik yükseltilebilir çalışma platformu görülmektedir. Platformun yükselmesi; eğim/aşırı yük sınırlayıcılarını, acil indirme sistemini, zeminin teker/ayak yükünü taşımasını, üstten sıkışma riskini veya sahadaki kurtarma hazırlığını göstermez. Fotoğraf, tip ve görünür durum hakkında ipucu verir; güvenli kullanım teknik rapor ve operasyonel doğrulama ister.",
    requirementsTr: [
      "Periyodik kontrol raporu makinenin tipini, seri numarasını, çalışma yüksekliğini, platform SWL’sini ve enerji türünü doğru göstermeli; İSG-KATİP, EKİPNET, güncel Bakanlık formatı, yetkili kişi ve kalibrasyon şartlarını taşımalıdır.",
      "Yıllık çalışma kapasitesi deneyi ile en geç üç yılda bir veya kapsamlı bakım/tadilat sonrasındaki güncel kriter testleri; platformun uygun konfigürasyonu, destek ayakları ve yük dağılımı belirtilerek uygulanmalıdır.",
      "Zemin taşıma gücü, eğim, çukur/kapak/kenar, ayak veya teker nokta yükleri ve rüzgâr sınırı üretici verisiyle değerlendirilmelidir; eğim alarmı çalışsa bile üretici limitinin dışında kurulum yapılmamalıdır.",
      "Platform korkulukları, giriş kapısı, ankraj noktaları, uzatma tablası, şasi-bom/makas yapısı, pim/burçlar, kaynaklar, hidrolik silindir/hortumlar ve teker/ayaklar ölçülü olarak kontrol edilmelidir.",
      "Eğim ve aşırı yük algılama, yüksekte sürüş kısıtı, hareket limitleri, çukur koruması, salınımlı aks kilidi, alt/üst kumanda önceliği, acil durdurma ve acil indirme sistemi fonksiyon testiyle doğrulanmalıdır.",
      "Üstten sıkışma/ezilme riski için güzergâh ve çalışma alanı kontrol edilmeli; uygun makinede ikincil koruma/temas çubuğu gibi sistemler değerlendirilmeli, gözcü ve dışlama bölgesi kurulmalıdır.",
      "Düşüş önleyici sistem seçimi platform tipine ve üretici talimatına göre yapılmalı; özellikle bomlu platformlarda doğru ankraj ve kısa bağlantı, makaslı platformda dışarı tırmanma/kapıya oturma yasağı uygulanmalıdır.",
      "Operatör eğitimi makine tipine özel familiarizasyon ve uygulamalı yeterlikle tamamlanmalı; günlük kontrol, yerdeki kişinin acil indirme yetkinliği ve askıda/sıkışmış kişiyi kurtarma planı düzenli tatbikatla doğrulanmalıdır.",
    ],
    ifPresentTr:
      "Rapor mevcutsa; makine tipini ve SWL’yi saha etiketiyle eşleştirin, eğim/aşırı yük/acil indirme fonksiyonlarının gerçek test kaydını inceleyin. Çalışma noktasında zemin, rüzgâr, üst engel ve enerji hattını ayrıca değerlendirin; periyodik kontrol raporunu iş planı ve kurtarma planı yerine kullanmayın. Yabancı altı aylık LOLER kuralını Türkiye’deki yasal periyot diye aktarmayın.",
    ifAbsentTr:
      "Geçerli rapor veya kurtarma planı yoksa platformu yükseltmeyin; anahtarı kontrol altına alın. Yetkili kişiye periyodik kontrol yaptırın, üretici sınırlarına göre zemin/rüzgâr/engel değerlendirmesi ve makine tipine özgü kurtarma planı hazırlayın. Arızalı acil indirme, eğim/aşırı yük sistemi veya korkulukta ekipmanı derhal karantinaya alın.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III yükseltilebilir seyyar iş platformları.",
      "Mevzuat — Yapı İşlerinde İş Sağlığı ve Güvenliği Yönetmeliği; çalışma yapı işiyse.",
      "Standart — TS EN 280 Mobil yükseltilebilir iş platformları — Tasarım hesapları ve güvenlik.",
      "İyi uygulama — ISO 18893 MEWP güvenli kullanım, muayene ve bakım; IPAF/HSE rehberleri.",
      "Üretici dokümanı — Tip özel kullanım, rüzgâr, eğim, ankraj ve kurtarma talimatları.",
    ],
    interval: {
      textTr:
        "Standart/imalatçı daha kısa süre öngörmüyorsa yılda bir; kapsamlı bakım/tadilat, kaza/devrilme veya taşıyıcı-sınırlayıcı sistem değişikliği sonrası tekrar kullanımdan önce özel kontrol; kullanım öncesi kontrol her vardiya",
      basisCode: "TR-IS-EKIPMANLARI-2025-EK3-MEWP",
      verified: true,
    },
    relatedLayers: [3, 4, 6, 8, 18, 19],
  },

  earthmoving_equipment: {
    family: "earthmoving_equipment",
    recommendationClass: "periodic_inspection_record",
    titleTr: "İş Makinesi — Periyodik Kontrol, Görüş Alanı, Hızlı Bağlantı ve Saha Ayrımı Doğrulaması",
    categoryLabelTr: "Mobil İş Ekipmanları ve Saha Trafiği",
    assetLabelTr: "iş makinesi",
    observationTr:
      "Sahada ekskavatör, yükleyici, beko-loder, dozer, greyder veya benzeri iş makinesi görülmektedir. Makinenin yürüyebilmesi ve ataşmanın hareket etmesi; ROPS/FOPS bütünlüğünü, kör alanların yönetimini, hızlı bağlantı kilidini, frenleri ya da zeminin/şevin stabilitesini doğrulamaz. Önce makinenin tam tipi ve kullanım amacı belirlenmeli, ardından ekipman kontrolü ile saha operasyonu ayrı ayrı değerlendirilmelidir.",
    requirementsTr: [
      "Makinenin tipi, model-seri numarası, imal yılı, çalışma ağırlığı, ataşmanları ve kullanım amacı tekil envanterde tanımlanmalı; Ek-III kapsamındaki iş makinesi için rapor İSG-KATİP, EKİPNET ve Bakanlığın güncel format koşullarını taşımalıdır.",
      "ROPS/FOPS/TOPS koruyucu yapı, kabin ve montaj noktaları; kaynak, delik veya kesme gibi yetkisiz modifikasyonlar açısından kontrol edilmeli; emniyet kemeri çalışır ve operatör kullanımını sağlayacak denetim düzeni bulunmalıdır.",
      "Servis/park freni, direksiyon, palet/lastikler, akslar, yürüyüş mekanizması, hidrolik silindir-hortumlar, pim-burçlar, ataşman ve kilitleme düzeni ölçülebilir kabul kriterleriyle kontrol edilmelidir.",
      "Hızlı bağlantı kuplöründe birincil ve ikincil kilit, kabinden görsel/işitsel doğrulama ve “shake test” benzeri üretici kullanım kontrolü uygulanmalı; yalnız hidrolik basınç kilit kabul edilmemelidir.",
      "Kamera, ayna ve doğrudan görüş birlikte değerlendirilerek makine etrafındaki kör alan haritası çıkarılmalı; geri hareketi mümkün olduğunca azaltan trafik düzeni, bariyer, işaretçi ve dışlama bölgesi kurulmalıdır.",
      "Kazı kenarı, dolgu, platform, şev, yeraltı boşluğu ve geçiş güzergâhının taşıma gücü/geometrisi makine ağırlığı ve dinamik etkilerle uyumlu olmalı; makine kazı kenarına gelişigüzel yaklaştırılmamalıdır.",
      "Enerji hatlarına yaklaşma, kaldırma amacıyla ekskavatör kullanımı, yıkım, su içinde çalışma, eğimli zeminde çalışma ve gece çalışması için ayrı JSA/iş planı hazırlanmalı; üretici kullanım sınırları aşılmamalıdır.",
      "Operatör belgesi, makine tipine özel uygulamalı yeterlik, günlük kontrol, anahtar yönetimi, haberleşme ve bakım sırasında ataşmanın mekanik olarak desteklenmesi/LOTO talimatı bulunmalıdır.",
    ],
    ifPresentTr:
      "Rapor mevcutsa; rapordaki makine ve ataşmanların sahayla eşleştiğini, fren/direksiyon test yöntemini, ROPS/FOPS üzerindeki tadilatları, hızlı kuplör kilit fonksiyonunu ve kör alan önlemlerini doğrulayın. Kaza veya ataşman düşmesi geçmişi varsa yalnız yıllık rapora değil olay sonrası mühendislik ve ikinci kontrol kayıtlarına bakın.",
    ifAbsentTr:
      "Geçerli rapor, çalışır emniyet kemeri, fren veya ataşman kilidi yoksa makineyi çalıştırmayın; anahtarı kontrol altına alın. Yetkili kişiye periyodik kontrol yaptırın, saha trafik/zemin planını kurun ve makine tipine özel uygulamalı operatör yeterliğini doğrulayın.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III iş makineleri tablosu.",
      "Mevzuat — Yapı İşlerinde İş Sağlığı ve Güvenliği Yönetmeliği; kazı/yapı işlerinde.",
      "Standart — TS EN 474/ISO 20474 serisi hafriyat makineleri güvenliği.",
      "Standart — ISO 3471 ROPS; ISO 3449 FOPS; ISO 5006 operatör görüş alanı.",
      "İyi uygulama — HSE iş makinelerinde görüş alanı, yaya ayrımı ve hızlı kuplör rehberleri.",
    ],
    interval: {
      textTr:
        "Ek-III’te sayılan iş makinelerinde standart/imalatçı daha kısa süre öngörmüyorsa yılda bir; kaza/devrilme, ROPS-FOPS onarımı, ataşman veya güvenlik sistemini etkileyen değişiklik sonrasında tekrar kullanımdan önce özel kontrol; kullanım öncesi kontrol her vardiya",
      basisCode: "TR-IS-EKIPMANLARI-2025-EK3-IS-MAKINELERI",
      verified: true,
    },
    relatedLayers: [4, 8, 15, 18, 19],
  },

  boiler: {
    family: "boiler",
    recommendationClass: "periodic_inspection_record",
    titleTr: "Kazan — Basınç Bütünlüğü, Brülör Emniyeti, Su Seviyesi ve İşletme Disiplini Doğrulaması",
    categoryLabelTr: "Basınçlı Ekipman ve Proses Güvenliği",
    assetLabelTr: "kazan",
    observationTr:
      "Sahada buhar, kızgın su, sıcak su veya ısıtma kazanı görülmektedir. Kazanın yanıyor ve basınç üretiyor olması; basınçlı gövde kalınlığını, düşük su seviyesi kesicisini, alev gözetimini, emniyet ventili kapasitesini, su kimyasını veya yanma odasında yakıt birikmesi riskini doğrulamaz. Kazan güvenliği; basınçlı ekipman kontrolü, brülör güvenlik dizisi ve yetkin işletme kayıtlarının birlikte incelenmesini gerektirir.",
    requirementsTr: [
      "Kazan tipi, yakıt, kapasite, izin verilen azami basınç/sıcaklık, imalat standardı, seri numarası ve emniyet donanımı veri kitabı/etiketle eşleştirilmeli; periyodik kontrol raporu İSG-KATİP, EKİPNET ve güncel Bakanlık formatı şartlarını taşımalıdır.",
      "Yıllık ve üç yıllık/tadilat sonrası basınç deney rejimi basınçlı ekipman kartındaki güncel kurala göre uygulanmalı; iç/dış muayene, UT ölçümü ve erişilebilen kaynak/nozul bölgeleri raporlanmalıdır.",
      "Emniyet ventilleri set basıncı, kapasite, tahliye hattı, izolasyon vanası konumu ve mühür/test kayıtlarıyla doğrulanmalı; birden fazla kazanın ortak kolektöre tahliyesinde karşı basınç ve güvenli deşarj değerlendirilmelidir.",
      "En az iki bağımsız düşük su seviyesi koruması, yüksek basınç/sıcaklık limitleri, alev kaybı, hava/yakıt basıncı, fan ve damper interlockları gerçek trip testiyle doğrulanmalı; yalnız gösterge simülasyonu yeterli sayılmamalıdır.",
      "Brülör purge süresi ve hava debisi, ateşleme sırası, pilot/ana alev, çift emniyet kapatma vanası, gaz valfi sızdırmazlık kontrolü ve reset mantığı üretici/standart dizisine uygun olmalıdır.",
      "Besi suyu, blöf, kondens dönüşü ve su kimyası programı; sertlik, iletkenlik/TDS, pH, çözünmüş oksijen ve arıtma kayıtlarıyla takip edilmeli; ölçek/korozyon bulguları kalınlık trendiyle ilişkilendirilmelidir.",
      "Baca çekişi, yanma havası, CO/O2 ve yanma verimi ölçümleri, kazan dairesi havalandırması, gaz algılama, patlama tahliyesi ve acil yakıt kesme düzeni kontrol edilmelidir.",
      "Yetkili kazan operatörü, vardiya kayıt defteri, alarm-trip test takvimi, devreye alma/durdurma talimatı, LOTO, sıcak iş ve kapalı alan izinleri ile düşük su/alev sönmesi acil durum senaryoları bulunmalıdır.",
    ],
    ifPresentTr:
      "Rapor mevcutsa; yalnız hidrostatik test sonucuna değil düşük su kesicisi, alev gözetimi, yüksek limit ve gaz valfi güvenlik dizisinin gerçek fonksiyon testlerine bakın. Emniyet ventili kapasite dayanağını, su kimyası trendini, iç muayene bulgularını ve son onarımın WPS/PQR-NDT kayıtlarını doğrulayın.",
    ifAbsentTr:
      "Geçerli rapor, çalışır düşük su seviyesi kesicisi veya doğrulanmış emniyet ventili yoksa kazanı devreye almayın. Yetkili kişiyle basınçlı ekipman kontrolünü, brülör yetkili servisiyle güvenlik dizisi testini ve su kimyası/baca ölçümlerini birlikte planlayın. Basınç kaçağı, şişme, kızarma veya sık trip resetinde kontrollü duruş yapın.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III kazanlar ve basınçlı ekipman hükümleri.",
      "Mevzuat — Basınçlı Ekipmanlar Yönetmeliği; Binaların Yangından Korunması Hakkında Yönetmelik, uygulanabildiği ölçüde.",
      "Standart — TS EN 12952 su borulu kazanlar; TS EN 12953 silindirik kazanlar; TS EN 12828 ısıtma sistemleri.",
      "Standart — TS EN 676/TS EN 267 brülörler; üretici burner management sistemi talimatları.",
      "İyi uygulama — HSE endüstriyel buhar ve sıcak su kazanlarının güvenli yönetimi; ASME/NBIC iyi uygulamaları.",
    ],
    interval: {
      textTr:
        "Standart/imalatçı daha kısa süre öngörmüyorsa yılda bir periyodik kontrol; yıllık hidrostatik deney işletme veya izin verilen azami basınçta, en geç üç yılda bir ve kapsamlı bakım/tadilat sonrasında imalat standardındaki deney basıncında; emniyet interlock proof-test sıklığı üretici ve risk planına göre ayrıca",
      basisCode: "TR-IS-EKIPMANLARI-2025-EK3-KAZAN",
      verified: true,
    },
    relatedLayers: [5, 10, 12, 13, 14, 18, 19],
  },

  compressor: {
    family: "compressor",
    recommendationClass: "periodic_inspection_record",
    titleTr: "Kompresör ve Hava Tankı — Basınç Kabı, Tahliye, Yoğuşma ve Makine Koruyucularının Doğrulanması",
    categoryLabelTr: "Basınçlı Ekipman ve Makine Güvenliği",
    assetLabelTr: "kompresör",
    observationTr:
      "Sahada kompresör görülmektedir. Kompresörün hava üretmesi; hava tankının cidar bütünlüğünü, emniyet ventili kapasitesini, separator/yağ taşınmasını, yüksek sıcaklık tripini, kayış-kasnak korumasını veya kapalı hacimde gürültü ve ısı birikimini doğrulamaz. Kompresör paketi ile basınçlı hava tankı aynı kontrol kalemi değildir; ayrı teknik rejimler birlikte yönetilmelidir.",
    requirementsTr: [
      "Kompresör ve hava tankı seri numaraları, kapasite, azami basınç, tank hacmi ve imalat standardı ayrı envanterlenmeli; hava tankı için yasal periyodik kontrol raporu güncel İSG-KATİP/EKİPNET şartlarını taşımalıdır.",
      "Hava tankının yıllık ve üç yıllık/tadilat sonrası basınç deney rejimi güncel basınçlı ekipman hükmüne göre uygulanmalı; UT kalınlık ölçümü özellikle yoğuşma biriken alt bölge, drenaj ve nozul çevrelerini kapsamalıdır.",
      "Emniyet ventili set basıncı/kapasitesi, manometre doğruluğu, otomatik drenaj, minimum basınç/çek valf ve tank izolasyon vanası konumu doğrulanmalı; emniyet ventilinin önü kapatılamamalıdır.",
      "Kompresörde yüksek çıkış sıcaklığı, yağ basıncı/seviyesi, fan ve havalandırma, motor aşırı akım, faz koruma ve basınç tripleri gerçek fonksiyon testiyle doğrulanmalıdır.",
      "Kayış-kasnak, kaplin, fan ve sıcak yüzey koruyucuları; kapak interlockları, acil durdurma, enerji izolasyon noktaları ve bakım sırasında birikmiş basıncı sıfırlama düzeni kontrol edilmelidir.",
      "Basınçlı hava borulaması, esnek hortumlar, quick-coupling ve whip-check gereği; mekanik hasar, uygunsuz malzeme, titreşim ve destek aralığı açısından kontrol edilmeli; PVC benzeri uygun olmayan boru kullanılmamalıdır.",
      "Basınçlı hava insan temizleme, giysi üfleme veya solvent püskürtmede kullanılmamalı; proses için düşük basınç gerekiyorsa basınç düşürücü/nozul koruması ve ayrı risk değerlendirmesi uygulanmalıdır.",
      "Kompresör odasında taze hava ve sıcak hava tahliyesi, gürültü ölçümü, yağ/yoğuşma atığı, yangın yükü ve bakım erişimi değerlendirilmelidir; bakım planı yağ analizi, filtre/separator ve üretici servis limitlerini kapsamalıdır.",
    ],
    ifPresentTr:
      "Rapor mevcutsa; raporun kompresör motorunu değil doğru hava tankını kapsadığını, tank alt bölgesinde ölçüm yapıldığını, emniyet ventili set/kapsam kaydını ve otomatik drenajın çalıştığını doğrulayın. Kompresör kontrol panelindeki trip geçmişini, tekrarlayan yüksek sıcaklık veya separator basınç farkı alarmlarını inceleyin.",
    ifAbsentTr:
      "Hava tankı raporu veya emniyet ventili doğrulaması yoksa tankı basınç altında çalıştırmayın; basıncı güvenli biçimde boşaltın ve LOTO uygulayın. Yetkili kişiye tank kontrolü, üretici servisine kompresör emniyet interlock/bakım kontrolü yaptırın. Şişme, yoğun korozyon, yağ kaçağı veya anormal sıcaklıkta sistemi durdurun.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III basınçlı hava tankları/basınçlı kaplar.",
      "Mevzuat — Makina Emniyeti Yönetmeliği ve elektrik/gürültü mevzuatı; uygulanabilirlik tarih ve ekipmana göre.",
      "Standart — TS EN 1012-1 Kompresörler ve vakum pompaları — Güvenlik kuralları.",
      "Standart — TS EN 286-1 basit basınçlı hava/azot kapları veya ekipmanın imalat standardı.",
      "İyi uygulama — HSE basınç sistemleri written scheme yaklaşımı; üretici bakım ve trip test talimatları.",
    ],
    interval: {
      textTr:
        "Hava tankı/basınçlı kap için standart/imalatçı daha kısa süre öngörmüyorsa yılda bir ve güncel basınç deneyi rejimi; kompresör ana makine bakımı ve interlock testleri üretici/risk planına göre",
      basisCode: "TR-IS-EKIPMANLARI-2025-EK3-BASINCLI-HAVA",
      verified: true,
    },
    relatedLayers: [5, 6, 12, 16, 18, 19],
  },

  welding_machine: {
    family: "welding_machine",
    recommendationClass: "site_verification",
    titleTr: "Kaynak Makinesi ve Sıcak İş — Elektriksel Test, Duman Kontrolü ve Yangın İzni Doğrulaması",
    categoryLabelTr: "Kaynak, Sıcak İş ve Tehlikeli Enerji",
    assetLabelTr: "kaynak makinesi",
    observationTr:
      "Sahada kaynak makinesi görülmektedir. Makinenin ark oluşturması; çıkış devresi yalıtımını, koruma iletkeni sürekliliğini, açık devre gerilimini, kablo/pense durumunu, kaynak dumanı maruziyetini veya sıcak iş alanındaki yangın-patlama riskini doğrulamaz. Kaynak makinesi kontrolü ile kaynak prosesinin izin, havalandırma, gaz ve yangın gözcülüğü kontrolleri birlikte ele alınmalıdır.",
    requirementsTr: [
      "Makine tipi, seri numarası, görev çevrimi, besleme ve çıkış değerleri etiketle doğrulanmalı; CE işareti, uygunluk beyanı ve Türkçe talimat ürünün piyasaya arz dönemine göre incelenmelidir.",
      "TS EN IEC 60974-4 temelli periyodik/onarım sonrası testte koruma iletkeni sürekliliği, yalıtım direnci, kaçak akım, çıkış devresi ve fonksiyon testleri sayısal sonuçlarla kaydedilmeli; test cihazı kalibrasyonlu olmalıdır.",
      "Elektrot pensesi/torç, dönüş klempi, kaynak ve besleme kabloları, fiş-priz, uzatma düzeni, gövde, fan ve kapaklar mekanik/termal hasar açısından kontrol edilmeli; dönüş akımı rastgele yapı elemanları veya borulama üzerinden yürütülmemelidir.",
      "Kaynak dumanı için proses, ana metal ve sarf malzemesine göre Cr(VI), Ni, Mn ve diğer bileşenler değerlendirilerek kaynak noktasında etkili lokal emiş kurulmalı; genel havalandırma tek başına varsayılan yeterli kontrol sayılmamalıdır.",
      "Kapalı/yarı kapalı alanlarda atmosfer ölçümü, zorlamalı havalandırma, gaz tüpü dışarıda konumlandırma, gözcü ve kurtarma planı uygulanmalı; oksijen zenginleştirme veya oksijenle havalandırma yasaklanmalıdır.",
      "Sıcak iş izni; yanıcı maddelerin uzaklaştırılması/korunması, kör bölgeler, alt katlar, drenajlar, patlayıcı ortam, gaz ölçümü, yangın söndürücü ve yangın gözcüsü süresini kapsamalıdır.",
      "Oksijen-yakıt gazı sisteminde doğru regülatör, hortum rengi/hizmeti, çek valf ve alev geri tepme emniyet cihazları; sızdırmazlık ve vana kullanımı talimatı doğrulanmalıdır.",
      "Kaynakçı yeterliği, WPS/PQR gereği, ekranlama, UV/IR ve sıçrantı KKD’si, işitme/gürültü, ergonomi ve kaynak sonrası yangın gözetimi eğitim ve denetim kayıtlarına bağlanmalıdır.",
    ],
    ifPresentTr:
      "Test kaydı ve sıcak iş izni mevcutsa; testin doğru seri numaralı makineye ait olduğunu, sayısal elektriksel sonuçları, tamir sonrası yeniden testi ve kablo/pense durumunu inceleyin. İzin formunda yalnız imza değil gerçek gaz ölçümü, alan hazırlığı, yangın gözcüsü ve iş bitimi sonrası takip kaydını doğrulayın. Kaynak dumanı için emiş debisi/etkinlik ölçümünü ve iş hijyeni sonuçlarını kontrol edin.",
    ifAbsentTr:
      "Elektriksel test veya koruyucu iletken bütünlüğü bilinmiyorsa makineyi kullanımdan çıkarın; yetkin servise TS EN IEC 60974-4 temelli test yaptırın. Sıcak iş izni, etkili lokal emiş veya patlayıcı ortam kontrolü yoksa kaynak işini başlatmayın. Hasarlı kabloyu bantla geçici kapatıp kullanmayın; uygun parça ile değiştirin.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği genel güvenli kullanım/bakım hükümleri; Elektrik tesisatı mevzuatı.",
      "Mevzuat — Kimyasal Maddelerle Çalışmalarda Sağlık ve Güvenlik Önlemleri; Patlayıcı Ortamlar; Acil Durumlar; Binaların Yangından Korunması hükümleri.",
      "Standart — TS EN IEC 60974-1 Ark kaynak donanımı; TS EN IEC 60974-4 periyodik muayene ve deney.",
      "Standart — TS EN ISO 15012 serisi kaynak dumanı yakalama/ayırma; ISO 9606 kaynakçı yeterliği; ISO 3834 kalite gerekleri.",
      "İyi uygulama — HSE kaynak dumanı kontrolü; OSHA 1910 Subpart Q ve NFPA 51B sıcak iş yaklaşımı.",
    ],
    interval: {
      textTr:
        "Kaynak makinesi için Ek-III’te her durumda geçerli sabit bir “yılda bir” hükmü atanmaz; TS EN IEC 60974-4, imalatçı ve risk planına göre periyodik, onarım sonrası ve güvenliği etkileyen olay sonrası test yapılır. Sıcak iş izni her iş/alan değişiminde yenilenir",
      basisCode: "TR-IS-EKIPMANLARI-M7-RISK + IEC-60974-4",
      verified: true,
    },
    relatedLayers: [5, 6, 10, 13, 15, 16, 18],
  },

  machine_tool: {
    family: "machine_tool",
    recommendationClass: "periodic_inspection_record",
    titleTr: "Tezgâh ve Pres — Tip-C Standardı, Koruyucu Sistem ve Beklenmedik Çalıştırma Doğrulaması",
    categoryLabelTr: "Makine Güvenliği ve Fonksiyonel Emniyet",
    assetLabelTr: "tezgâh, pres, torna",
    observationTr:
      "Sahada tezgâh, pres, torna veya benzeri sabit makine görülmektedir. Koruyucu kapağın varlığı; doğru güvenlik mesafesini, interlock performans seviyesini, frenleme süresini, iki el kumandasının anti-tie-down özelliğini veya bakımda beklenmedik çalıştırmanın önlendiğini göstermez. Önce makine türü tanımlanmalı; genel standartlar kadar o makineye özgü Tip-C standardı ve üretici risk değerlendirmesi esas alınmalıdır.",
    requirementsTr: [
      "Makine kimliği, imal yılı, seri numarası, CE işareti, uygunluk beyanı, Türkçe talimat ve orijinal güvenlik devresi dokümanı bulunmalı; sonradan yapılan otomasyon/koruyucu değişiklikleri MOC ve yeni risk değerlendirmesiyle incelenmelidir.",
      "Ek-III tablosunda sayılan tezgâh için rapor İSG-KATİP/EKİPNET ve güncel format şartlarını taşımalı; makine türüne göre mekanik pres, hidrolik pres, CNC/işleme merkezi, torna, taşlama vb. doğru standarda göre kontrol edilmelidir.",
      "Sabit/hareketli koruyucular, interlock ve guard locking, ışık perdesi, lazer tarayıcı, basınç hassas paspas ve iki el kumandası için güvenlik mesafesi ile durma süresi ölçülmeli; yalnız sensörün ışığının yanması fonksiyonel doğrulama sayılmamalıdır.",
      "Emniyet rölesi/PLC, kontaktör geri besleme, kanal mimarisi, reset ve yeniden başlatma önleme işlevleri; ISO 13849-1/IEC 62061’e göre gereken performans seviyesine karşı doğrulanmalıdır.",
      "Acil durdurma erişilebilir ve durdurma sonrası kendiliğinden yeniden başlatmayı önler durumda olmalı; acil durdurma normal çevrim durdurma veya enerji izolasyonu yerine kullanılmamalıdır.",
      "Preslerde kavrama-fren, stroku tekleme, kalıp alanı koruması, tonaj/yükleme ve kalıp bağlama; torna/işleme merkezlerinde ayna-iş parçası tutma, kapı kilidi, takım fırlaması ve talaş tahliyesi kontrol edilmelidir.",
      "Elektrik, hidrolik, pnömatik, yerçekimi, yay ve birikmiş enerji için LOTO noktaları tanımlanmalı; bakım/kalıp değişiminde mekanik bloklama ve sıfır enerji doğrulaması uygulanmalıdır.",
      "Kullanım öncesi koruyucu kontrolü, arıza/bypass kaydı, yetkili ayar-bakım personeli, takım/taş muayenesi, talaş temizleme araçları, ergonomi ve iş hijyeni maruziyetleri eğitim ve bakım sistemine bağlanmalıdır.",
    ],
    ifPresentTr:
      "Rapor mevcutsa; raporda doğru makine türü standardının kullanıldığını, durma süresi ve güvenlik mesafesinin sayısal ölçüldüğünü, interlockların her kanalda arıza algıladığını ve bypass/muting fonksiyonlarının yetkisiz kullanılamadığını doğrulayın. CE etiketi ve acil stopun varlığını tek başına makine güvenliği kabul etmeyin.",
    ifAbsentTr:
      "Ek-III kapsamındaki makinede geçerli rapor yoksa veya koruyucu/interlock devre dışıysa makineyi çalıştırmayın; enerji ve kumandayı LOTO ile kontrol altına alın. Makine tipine yetkin mühendisle risk değerlendirmesi, güvenlik devresi doğrulaması, durma süresi ölçümü ve Bakanlık formatında kontrol yaptırın. Koruyucuyu sökerek üretime devam etmeyin.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III tezgâhlar tablosu ve Ek-II kullanım hükümleri.",
      "Mevzuat — Makina Emniyeti Yönetmeliği; 7223 sayılı Ürün Güvenliği ve Teknik Düzenlemeler Kanunu, piyasaya arz dönemine göre.",
      "Standart — TS EN ISO 12100; TS EN ISO 13849-1; TS EN ISO 14119; TS EN ISO 14120; TS EN ISO 13850; TS EN ISO 14118.",
      "Standart — TS EN ISO 16092 serisi presler; TS EN ISO 23125 torna; TS EN ISO 16090-1 işleme merkezleri; makine türüne göre.",
      "İyi uygulama — OSHA machine guarding ve control of hazardous energy; HSE PUWER yaklaşımı.",
    ],
    interval: {
      textTr:
        "Ek-III’te sayılan tezgâhlarda standart/imalatçı daha kısa süre öngörmüyorsa yılda bir; koruyucu devre, fren, kontrol sistemi veya çalışma yöntemini etkileyen değişiklik/onarım sonrasında tekrar kullanımdan önce özel doğrulama. Ek-III dışında kalan makinede üretici/risk planı uygulanır",
      basisCode: "TR-IS-EKIPMANLARI-2025-EK3-TEZGAHLAR",
      verified: true,
    },
    relatedLayers: [5, 6, 17, 19],
  },

  fire_equipment: {
    family: "fire_equipment",
    recommendationClass: "periodic_inspection_record",
    titleTr: "Yangın Söndürme Sistemleri — Proje, Hidrolik Performans ve Bakım Kayıtlarının Doğrulanması",
    categoryLabelTr: "Yangın, Acil Durum ve Proses Güvenliği",
    assetLabelTr: "söndürücü, yangın dolabı, hidrant",
    observationTr:
      "Sahada taşınabilir yangın söndürücü, yangın dolabı, hidrant veya sabit söndürme tesisatı görülmektedir. Cihazın yerinde ve manometresinin yeşil bölgede olması; doğru söndürücü tipini, gerçek dolum miktarını, hortum/nozul bütünlüğünü, pompa debi-basıncını veya hidrolik olarak en elverişsiz noktadaki performansı kanıtlamaz. Yangın güvenliği; proje, envanter, periyodik kontrol, bakım ve tatbikat kayıtlarıyla doğrulanmalıdır.",
    requirementsTr: [
      "Yangın tesisatı, onaylı/as-built proje ve yangın senaryosu üzerinden envanterlenmeli; su deposu, pompa, kolektör, hidrant, dolap, sprinkler, köpük/gazlı sistem ve alarm-arayüzleri sahayla eşleştirilmelidir.",
      "Sabit yangın tesisatı periyodik kontrol raporu, İSG-KATİP/EKİPNET ve Bakanlığın güncel format koşullarını taşımalı; proje, borulama, pompa, vana, alarm ve uç cihaz sonuçlarını sayısal olarak içermelidir.",
      "Yangın pompalarında shut-off, nominal ve gerektiğinde yüksek debi noktalarını gösteren debi-basınç testi; otomatik çalıştırma, jokey pompa, yedek güç/yakıt, kaçak ve haftalık kullanıcı testleri kayıt altına alınmalıdır.",
      "Hidrant ve dolaplarda en elverişsiz noktadaki statik/dinamik basınç ve debi ölçülmeli; hortum, lans/nozul, vana, kapak, erişim ve donma/korozyon durumu kontrol edilmelidir.",
      "Sprinkler ve diğer sabit sistemlerde kontrol vanası konumu/mühürleme, akış anahtarı, alarm, drenaj testi, tıkanma-korozyon, askı/destek ve başlıkların uygunluğu değerlendirilmelidir.",
      "Taşınabilir söndürücüler risk sınıfına uygun tip, kapasite, dağılım ve erişimde olmalı; gövde, hortum, emniyet pimi/mühür, basınç/kütle, bakım etiketi ve geçerli hidrostatik test işaretleri uygulanabilir ürün standardına göre kontrol edilmelidir.",
      "Köpük, temiz gaz, CO2 veya mutfak söndürme sistemlerinde ajan miktarı, nozullar, tahliye/boşalma, abort-manuel tetik, havalandırma/enerji interlocku ve personel tahliye gecikmesi fonksiyon testiyle doğrulanmalıdır.",
      "Yangın kapıları, bölmelendirme, algılama-alarm, acil aydınlatma, kaçış yolları, itfaiye bağlantıları ve yangın suyu sürekliliği aynı senaryo içinde test edilmeli; tatbikat bulguları düzeltici faaliyet sistemine bağlanmalıdır.",
    ],
    ifPresentTr:
      "Rapor mevcutsa; yalnız “pompa çalıştı” ifadesini kabul etmeyin. Debi-basınç eğrisini tasarım noktasıyla, en elverişsiz hidrant/dolap sonuçlarını proje hesabıyla, taşınabilir söndürücü envanterini saha seri numaralarıyla ve sabit sistem alarm/interlock testlerini yangın senaryosuyla karşılaştırın. Kapalı/bağlanmış vanaları ve sahada yapılan proje dışı değişiklikleri özellikle arayın.",
    ifAbsentTr:
      "Geçerli proje veya sabit tesisat raporu yoksa yetkili kişiye as-built doğrulama ve tam performans testi yaptırın. Yangın suyu yok, pompa devre dışı, ana vana kapalı veya kritik koruma eksikse faaliyet riskini yeniden değerlendirin; geçici yangın gözcüsü/ek söndürücü gibi tedbirleri yazılı planla uygulayın ve kritik alan çalışmasını gerektiğinde durdurun.",
    referencesTr: [
      "Mevzuat — Binaların Yangından Korunması Hakkında Yönetmelik ve güncel değişiklikleri.",
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III yangın tesisatı.",
      "Standart — TS EN 12845 sprinkler; TS EN 671 serisi yangın dolapları/hortum sistemleri; TS EN 12259 bileşenler.",
      "Standart — TS EN 3 serisi taşınabilir söndürücüler; TS ISO 11602-2 bakım/muayene, uygulanabilir sürüm ve ürün tipine göre.",
      "İyi uygulama — NFPA 10/13/20/25/72; Türk mevzuat ve projesinin yerine değil performans boşluk analizi için.",
    ],
    interval: {
      textTr:
        "Sabit yangın tesisatı için proje/standart daha kısa süre öngörmüyorsa yılda bir periyodik kontrol; kullanıcı işletme testleri ve taşınabilir söndürücü bakımları ilgili standart, imalatçı ve yangın planındaki daha sık aralıklarda",
      basisCode: "TR-IS-EKIPMANLARI-2025-EK3-YANGIN-TESISATI",
      verified: true,
    },
    relatedLayers: [13, 18, 19],
  },

  ventilation_system: {
    family: "ventilation_system",
    recommendationClass: "measurement_record",
    titleTr: "Havalandırma ve Lokal Emiş — Proje, Yakalama Etkinliği ve Maruziyet Kontrolünün Doğrulanması",
    categoryLabelTr: "İş Hijyeni, Havalandırma ve Patlamadan Korunma",
    assetLabelTr: "havalandırma, duman emiş",
    observationTr:
      "Sahada genel havalandırma veya lokal emiş sistemi görülmektedir. Fanın dönmesi ya da kanalda hava hissedilmesi; kirleticinin kaynakta yakalandığını, tasarım debisinin korunduğunu, filtrenin kaçırmadığını veya egzozun güvenli yere atıldığını göstermez. Sistem performansı, proje ve referans ölçümlerle karşılaştırılan başlık debisi/hızı, statik basınç, kanal akışı ve iş hijyeni sonuçlarıyla doğrulanmalıdır.",
    requirementsTr: [
      "Sistem için proses/kirletici, kaput tipi ve konumu, tasarım debisi, kanal çapları, fan eğrisi, filtre ve egzoz noktası içeren onaylı/as-built proje bulunmalı; periyodik kontrol güncel İSG-KATİP/EKİPNET formatında yapılmalıdır.",
      "Her kaput/emme ağzında uygun yöntemle yakalama veya yüzey hızı, kanal hız basıncı/debisi ve sistem statik basıncı ölçülmeli; sonuçlar devreye alma referans değerleri ve tasarım kriterleriyle karşılaştırılmalıdır.",
      "Kaputun kaynağa mesafesi, çalışan ile kaynak arasındaki konumu, çapraz hava akımları ve proses hareketi gözlenmeli; “yüksek debi” yerine kaynağı etkin çevreleyen/yakalayan tasarım esas alınmalıdır.",
      "Kanal, dirsek, esnek bağlantı, damper, fan, filtre ve deşarj; tıkanma, kaçak, aşınma, korozyon, birikme, balans bozukluğu ve erişilebilir temizlik yönünden kontrol edilmelidir.",
      "Filtre diferansiyel basıncı, pulse-cleaning/torba bütünlüğü, HEPA sızdırmazlık veya aktif karbon doygunluğu ilgili sisteme göre izlenmeli; filtre değişimi sırasında maruziyet ve atık yönetimi planlanmalıdır.",
      "Yanıcı toz/buhar/gaz taşıyan sistemlerde ATEX bölgelendirmesi, fan ve elektrik donanımı uygunluğu, topraklama/eşpotansiyel, kıvılcım/yangın algılama, patlama tahliyesi/izolasyonu ve kanal içi birikme değerlendirilmelidir.",
      "Egzoz, taze hava emişinden ve komşu çalışma/yaşam alanlarından güvenli yere verilmelidir; telafi havası sağlanmadan aşırı negatif basınç, yanma cihazlarında geri tepme veya kapıların açılmaması gibi ikincil riskler yaratılmamalıdır.",
      "Mühendislik kontrolünün yeterliliği iş hijyeni ölçümleriyle doğrulanmalı; çalışan maruziyeti sınır altında olsa dahi kaput performansının bozulma trendi izlenmeli, operatöre günlük gösterge/akış kontrolü ve arıza bildirimi öğretilmelidir.",
    ],
    ifPresentTr:
      "Rapor mevcutsa; yalnız fan motor akımını veya kanal ağzındaki tek hız ölçümünü yeterli kabul etmeyin. Ölçüm noktalarını projeyle, kaput sonuçlarını devreye alma referansıyla ve iş hijyeni sonuçlarını gerçek görev/sürelerle karşılaştırın. Filtre diferansiyel basıncı, damper konumu ve işletme sırasında açık kapı/pencere etkisini inceleyin.",
    ifAbsentTr:
      "Proje veya performans raporu yoksa sistemi “çalışıyor” kabul etmeyin. Yetkili kişiye as-built proje, kaput/debi/statik basınç ölçümü ve maruziyet değerlendirmesi yaptırın; kritik toksik veya kanserojen maruziyette etkili kontrol doğrulanana kadar işi sınırlayın ya da uygun geçici muhafaza/solunum korumasını yazılı planla uygulayın.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III havalandırma/klima tesisatı.",
      "Mevzuat — Kimyasal Maddelerle Çalışmalarda Sağlık ve Güvenlik Önlemleri; Tozla Mücadele; Kanserojen veya Mutajen Maddeler; İş Hijyeni Ölçüm Test ve Analiz hükümleri.",
      "Standart — TS EN 16798 serisi bina havalandırması; proses özelinde TS EN ISO 15012 kaynak dumanı ve ilgili ürün standartları.",
      "İyi uygulama — HSE HSG258 LEV tasarım, devreye alma ve kapsamlı muayene yaklaşımı; ACGIH Industrial Ventilation.",
      "İyi uygulama — ISO/IEC 60079 ve NFPA yanıcı toz havalandırma/patlama koruma ilkeleri; uygulanabildiği ölçüde.",
    ],
    interval: {
      textTr:
        "Proje/standart/imalatçı daha kısa süre öngörmüyorsa yılda bir periyodik kontrol; filtre ve kritik LEV performans göstergeleri risk/üretici planında daha sık izlenir; proses, kaput veya kanal değişiminden sonra yeniden devreye alma testi yapılır",
      basisCode: "TR-IS-EKIPMANLARI-2025-EK3-HAVALANDIRMA",
      verified: true,
    },
    relatedLayers: [10, 13, 16, 18, 19],
  },

  scaffold: {
    family: "scaffold",
    recommendationClass: "periodic_inspection_record",
    titleTr: "İskele — Statik Proje, Kurulum Etiketi, Haftalık Kontrol ve Periyodik Kontrol Ayrımı",
    categoryLabelTr: "Yüksekte Çalışma ve Geçici Yapılar",
    assetLabelTr: "iskele",
    observationTr:
      "Sahada cephe iskelesi, çalışma iskelesi veya seyyar erişim kulesi görülmektedir. İskelenin ayakta durması; zemin oturmasını, ankraj örüntüsünü, rüzgâr yükünü, platform sınıfını, eksik çaprazları veya yetkisiz değişiklikleri göstermez. “Haftalık kullanım kontrolü” ile Ek-III periyodik kontrolü aynı kayıt değildir; ikisi farklı amaçlarla birlikte yürütülmelidir.",
    requirementsTr: [
      "İskele tipi, yük sınıfı, yükseklik, cephe kaplaması/ağ, konsol, köprüleme ve özel geometriler için üretici kurulum kılavuzu veya statik hesap/proje bulunmalı; standart konfigürasyon dışındaki düzen mühendislik hesabıyla doğrulanmalıdır.",
      "Zemin taşıma gücü, taban plakası/kalası, dikmelerin düşeyliği, yatay ve çapraz elemanlar, ankraj/bağlar, konsol ve birleşimler projeye göre kontrol edilmelidir.",
      "Platformlar tam döşeli, kaymaya/kalkmaya karşı emniyetli; ana/ara korkuluk ve topuk levhası eksiksiz; duvar-iskeleden düşme boşluğu ve düşen cisim riski uygun toplu koruma ile yönetilmiş olmalıdır.",
      "Güvenli erişim merdiveni/merdiven kulesi, kapaklar, kat geçişleri, malzeme yükleme noktaları ve acil tahliye güzergâhı bulunmalı; çaprazlara tırmanma veya dış cepheden geçiş yapılmamalıdır.",
      "Kurulum, söküm ve değişiklik yalnız yetkin ekip ve gözetim altında, düşmeye karşı toplu/kişisel koruma ve kurulum sırası planıyla yapılmalıdır; kullanıcının ankraj sökmesi, konsol eklemesi veya platform kaldırması engellenmelidir.",
      "Yapı işlerinde kullanılmadan önce, haftada en az bir kez, değişiklikten sonra, olumsuz hava/sismik etki veya sağlamlığı etkileyen olaydan sonra yetkin kişi kontrolü kaydedilmeli ve iskele etiketi güncellenmelidir.",
      "Ek-III periyodik kontrolü; cephe iskelesi ve seyyar kule sınıfına göre doğru yasal azami süre, İSG-KATİP/EKİPNET ve güncel rapor formatıyla yapılmalıdır. Haftalık kontrol bu raporun; periyodik rapor da haftalık kontrolün yerine geçmez.",
      "Elektrik hattı yaklaşımı, araç çarpması, vinç yükü, brandanın rüzgâr etkisi, kar/buz, kazı kenarı ve komşu yapı bağlantıları iş planına dahil edilmeli; iskele üzerinde izin verilen yük görünür şekilde işaretlenmelidir.",
    ],
    ifPresentTr:
      "Proje, etiket ve rapor mevcutsa; sahadaki ankraj örüntüsü, taban, çapraz ve platformları projeyle karşılaştırın. Etiket tarihinin haftalık/olay sonrası kontrolü, periyodik raporun ise doğru iskele sınıfı ve yasal süreyi gösterdiğini doğrulayın. Rapor sonrası kullanıcılarca sökülen ankraj veya korkulukları ayrıca araştırın.",
    ifAbsentTr:
      "Proje, kurulum teslimi veya güncel kontrol etiketi yoksa iskeleye çıkışı fiziksel olarak engelleyin. Yetkin kişiyle statik/üretici konfigürasyonunu, haftalık kontrolü ve uygulanabilir Ek-III periyodik kontrolünü tamamlatın. Eksik ankrajı rastgele boru/tel ile telafi etmeyin; onaylı eleman ve düzen kullanın.",
    referencesTr: [
      "Mevzuat — Yapı İşlerinde İş Sağlığı ve Güvenliği Yönetmeliği, iskelelerin kontrol ve güvenli kullanım hükümleri.",
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III iskeleler.",
      "Standart — TS EN 12811-1 Geçici iş donanımları — İskeleler; TS EN 12810 cephe iskeleleri.",
      "Standart — TS EN 1004 serisi seyyar erişim/çalışma kuleleri; TS EN 74 bağlantı elemanları.",
      "Bakanlık rehberi — Güvenli İnşaat iskele SSS/kontrol listeleri ve ÇSGB iskele yayınları.",
    ],
    interval: {
      textTr:
        "Ek-III sınıfına göre cephe/ilgili iskelelerde altı ay, seyyar erişim ve çalışma kulelerinde bir yıl; yapı işlerinde ayrıca kullanılmadan önce, haftada en az bir kez, değişiklik ve sağlamlığı etkileyen olaylardan sonra kayıtlı saha kontrolü",
      basisCode: "TR-IS-EKIPMANLARI-2025-EK3-ISKELE + TR-YAPI-ISLERI-ISKELE-KONTROL",
      verified: true,
    },
    relatedLayers: [3, 4, 18, 19],
  },

  ladder: {
    family: "ladder",
    recommendationClass: "site_verification",
    titleTr: "Taşınabilir Merdiven — İş Seçimi, 1:4 Kurulum, Sabitleme ve Kullanım Öncesi Kontrol",
    categoryLabelTr: "Yüksekte Çalışma ve Erişim",
    assetLabelTr: "merdiven",
    observationTr:
      "Sahada taşınabilir veya sabit merdiven görülmektedir. Basamakların yerinde olması, merdivenin doğru iş için seçildiğini, zeminde kaymayacağını, üst noktada devrilmeyeceğini veya uzun süreli/iki elle iş için uygun olduğunu göstermez. Merdiven çoğu durumda kısa süreli ve düşük riskli erişim aracıdır; platform/iskele/MEWP ile daha güvenli çözüm mümkünse merdiven varsayılan seçenek olmamalıdır.",
    requirementsTr: [
      "İşin süresi, yüksekliği, iki el gereksinimi, yan yük, taşıma, acil durum ve zemin koşulları değerlendirilerek merdiven kullanımının gerekçesi yazılmalı; daha güvenli toplu korumalı erişim mümkünse merdiven seçilmemelidir.",
      "Taşınabilir merdiven üretici etiketi, sınıfı, azami yükü, uzunluğu ve TS EN 131 uygunluğu ile tanımlanmalı; ev tipi/etiketsiz merdiven endüstriyel işte kullanılmamalıdır.",
      "Dayamalı merdiven yaklaşık 1:4 açıyla kurulmalı, sağlam-düz zemine basmalı, mümkünse üstten ve alttan sabitlenmeli; kapı, geçit, araç yolu ve hareketli ekipman alanında bariyer/kapı kilitleme uygulanmalıdır.",
      "Erişim için kullanılan merdiven, güvenli el tutuşu sağlayacak biçimde iniş/çıkış seviyesinin üzerine yeterli uzanmalı veya eşdeğer sağlam tutamak bulunmalıdır; son basamaklarda tehlikeli uzanma yapılmamalıdır.",
      "Üç temas noktası korunmalı; kullanıcı gövdesini yan dikmeler dışına taşımamalı, ağır/uzun yük taşımamalı ve iki elle kuvvet gerektiren iş yapmamalıdır. Aletler kemer/torba veya ayrı taşıma yöntemiyle aktarılmalıdır.",
      "A tipi merdiven tam açılmış ve gergi/kilitleri devrede kullanılmalı; kapalı A tipi merdiven dayamalı merdiven gibi kullanılmamalı, üst platformu bu amaç için tasarlanmamışsa basamak olarak kullanılmamalıdır.",
      "Kullanım öncesi kontrolde yan dikme, basamak, ayak, pabuç, bağlantı, gergi, kilit, korozyon ve kirlenme incelenmeli; hasarlı merdiven “kullanma” etiketiyle karantinaya alınmalı, sahada kaynak/çiviyle yetkisiz tamir edilmemelidir.",
      "Sabit merdivenlerde platform/geçiş, düşüş önleme sistemi, kafesin uygunluğu, dinlenme platformu, kapı ve erişim güvenliği ilgili tasarım standardına göre mühendislik değerlendirmesine tabi tutulmalıdır.",
    ],
    ifPresentTr:
      "Kontrol kaydı mevcutsa; yalnız yıllık etiket aramayın. Merdivenin o günkü kullanım öncesi kontrolünü, iş seçiminin gerekçesini, açı/sabitleme ve çevresel koşulları sahada doğrulayın. Kayıtların hasarlı merdiveni karantinaya alma ve imha sürecini içerdiğini kontrol edin.",
    ifAbsentTr:
      "Etiketsiz, hasarlı, kaygan, yetersiz uzunlukta veya sabitlenemeyen merdiveni kullanmayın. Uygun platform/MEWP sağlayın veya doğru sınıfta merdiven seçip kullanım öncesi kontrol ve sabitleme uygulayın. Merdivene bir kişiyle elle tutturmayı kalıcı mühendislik kontrolü yerine kullanmayın.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-II yüksekte çalışma ve merdiven kullanım hükümleri.",
      "Mevzuat — Yapı İşlerinde İş Sağlığı ve Güvenliği Yönetmeliği; yapı işlerinde erişim/düşme önleme hükümleri.",
      "Standart — TS EN 131 serisi taşınabilir merdivenler; TS EN ISO 14122-4 sabit merdivenler.",
      "İyi uygulama — HSE merdivenlerde kısa süreli iş, 1:4 açı ve üç temas noktası yaklaşımı.",
      "İyi uygulama — OSHA merdiven güvenliği hükümleri; Türk mevzuatının yerine değil boşluk analizi için.",
    ],
    interval: {
      textTr:
        "Taşınabilir merdiven için Ek-III’te tüm işyerlerine uygulanacak sabit yıllık periyodik kontrol süresi atanmaz; kullanım öncesi kontrol her kullanımda, ayrıntılı kayıtlı kontrol imalatçı ve risk değerlendirmesine göre; düşme/hasar sonrası derhal. Sabit merdivenler tesis/makine bütünlüğü planına bağlanır",
      basisCode: "TR-IS-EKIPMANLARI-EK2-MERDIVEN + RISK-MFR",
      verified: true,
    },
    relatedLayers: [3, 4, 18],
  },

  conveyor: {
    family: "conveyor",
    recommendationClass: "periodic_inspection_record",
    titleTr: "Konveyör — Sıkışma Noktaları, Halatlı Acil Durdurma, Yeniden Başlatma ve LOTO Doğrulaması",
    categoryLabelTr: "Makine, Malzeme Taşıma ve Proses Güvenliği",
    assetLabelTr: "konveyör",
    observationTr:
      "Sahada bantlı, rulolu, zincirli, vidalı veya başka tip konveyör görülmektedir. Bandın düzgün ilerlemesi; baş-kuyruk tamburlarındaki sıkışma noktalarını, dönüş rulolarını, acil durdurma halatının tüm hat boyunca çalışmasını, tıkanma temizliğinde beklenmedik hareketi veya taşınan malzemenin yangın/patlama riskini doğrulamaz. Konveyör, yalnız motor ve bant değil, tüm hat ve çevresindeki insan-makine arayüzüdür.",
    requirementsTr: [
      "Konveyör tipi, hat sınırları, motorlar, transfer noktaları, kapasiteler, taşınan malzeme ve kontrol felsefesi güncel çizim/teknik dosyada tanımlanmalı; Ek-III kapsamındaki konveyör için İSG-KATİP/EKİPNET ve güncel rapor formatı bulunmalıdır.",
      "Baş-kuyruk tamburu, tahrik, dönüş ruloları, zincir-dişli, gergi ağırlığı, kaplin ve diğer çekme/sıkışma noktaları erişimi önleyen sabit veya interlocklu koruyucularla kapatılmalı; bakım gereksinimi koruyucu sökme kolaylığıyla değil güvenli erişim tasarımıyla çözülmelidir.",
      "Hat boyunca halatlı acil durdurma veya erişilebilir acil durdurmalar, her iki yönde çekme/halat kopması gevşemesi ve reset fonksiyonuyla test edilmeli; reset sonrası konveyör kendiliğinden yeniden başlamamalıdır.",
      "Çalıştırma öncesi sesli/ışıklı ikaz, başlatma gecikmesi, hatlar arası sekans ve downstream-upstream interlocklar gerçek proses koşulunda doğrulanmalı; operatörün kör noktadaki kişiyi görmeden çalıştırması engellenmelidir.",
      "Bant kayması, hız, hizasızlık, tıkanma, seviye, kapak/interlock ve metal/sıcaklık algılama sistemleri taşınan malzeme riskine göre test edilmeli; bypasslar erişim kontrollü ve süreli olmalıdır.",
      "Temizlik, sıkışma açma, rulman/bant değişimi ve gergi ayarında elektrik, pnömatik/hidrolik, yerçekimi ve gerilmiş bant/karşı ağırlık enerjileri LOTO ve mekanik bloklama ile sıfırlanmalıdır.",
      "Geçiş köprüleri, korkuluklar, acil kaçış, altından geçiş koruması, dökülen malzeme temizliği ve yaya-araç yolları düzenlenmeli; konveyör üzerine basma, altından sürünme veya hareketli bantta elle ayar yasaklanmalıdır.",
      "Yanıcı toz/üründe birikme, sıcak rulman, statik elektrik, kıvılcım, yangın algılama/söndürme, patlama tahliyesi/izolasyonu ve toz emiş sistemi proses güvenliği planına bağlanmalıdır.",
    ],
    ifPresentTr:
      "Rapor mevcutsa; konveyörün tüm uzunluğu ve transfer noktalarının raporda olduğunu, acil halatın her segmentte ve kopma/gevşeme halinde çalıştığını, yeniden başlatma önlemini ve LOTO noktalarını doğrulayın. Yalnız motor akımını veya bant dönüşünü test eden raporu koruyucu sistem uygunluğu saymayın.",
    ifAbsentTr:
      "Geçerli rapor veya çalışan acil durdurma/koruyucu yoksa konveyörü durdurun ve LOTO uygulayın. Yetkili kişiye hat bazlı periyodik kontrol ve makine risk değerlendirmesi yaptırın; sıkışma noktalarını standarda uygun koruyucu ile kapatın, halatlı acil durdurma ve güvenli yeniden başlatma mantığını doğrulayın.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III konveyörler ve bantlı iletim makineleri; Ek-II makine kullanımı.",
      "Mevzuat — Makina Emniyeti Yönetmeliği; Patlayıcı Ortamlar ve Tozla Mücadele hükümleri, malzemeye göre.",
      "Standart — TS EN 620 Sürekli taşıma donanımı ve sistemleri — Sabit bantlı konveyörler için güvenlik.",
      "Standart — TS EN 619 parça yük konveyörleri; TS EN 618 dökme malzeme mekanik taşıma; uygulanabilir tipe göre.",
      "İyi uygulama — OSHA conveyor guarding/LOTO ve HSE PUWER; NFPA 652/654 yanıcı toz yaklaşımı, uygun olduğunda.",
    ],
    interval: {
      textTr:
        "Ek-III kapsamındaki konveyör ve bantlı iletim makinelerinde standart/imalatçı daha kısa süre öngörmüyorsa yılda bir; koruyucu, acil durdurma, kontrol sistemi veya hat konfigürasyonunu etkileyen değişiklik/onarım sonrasında tekrar kullanımdan önce özel kontrol; kullanım öncesi fonksiyon kontrolü vardiya planına göre",
      basisCode: "TR-IS-EKIPMANLARI-2025-EK3-KONVEYOR",
      verified: true,
    },
    relatedLayers: [5, 6, 9, 13, 14, 19],
  },

};
