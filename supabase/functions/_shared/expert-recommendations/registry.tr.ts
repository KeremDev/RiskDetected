import type { ExpertRegistryEntry } from "./contracts.ts";

/**
 * Hand-written, one entry per equipment family the model can report seeing.
 *
 * Every standard number, interval and measurement here is ours. The model
 * supplies only the family code. Where a figure was supplied by a domain
 * expert rather than read off the source text, `interval.verified` is false and
 * the rendered card states the figure without claiming a verified basis --
 * the same convention the training catalogue uses.
 *
 * Seeded with the families the operator specified. The rest of the closed list
 * in EXPERT_ASSET_FAMILIES has no entry yet, and a family without an entry
 * produces no card: an empty section is honest, an invented interval is not.
 */
export const EXPERT_REGISTRY: Record<string, ExpertRegistryEntry> = {
  overhead_crane: {
    family: "overhead_crane",
    recommendationClass: "periodic_inspection_record",
    titleTr: "Köprülü Vinç — Periyodik Kontrol Raporunun Doğrulanması",
    categoryLabelTr: "Kaldırma Ekipmanları",
    assetLabelTr: "köprülü vinç",
    observationTr:
      "Sahada köprülü vinç görülmektedir. Kaldırma ve iletme ekipmanları, fiziksel durumları kusursuz görünse dahi, mevzuatın aradığı periyodik kontrol raporu olmadan yük altına alınamaz. Ekipmanın kendisi değil, kaydı sorgulanmaktadır.",
    requirementsTr: [
      "Periyodik kontrol raporu, makine mühendisi veya yetkilendirilmiş muayene kuruluşu tarafından düzenlenmiş ve imzalanmış olmalıdır.",
      "Rapor; kanca ve mandalı, halat veya zinciri, tamburu, frenleri, limit anahtarlarını, kumanda düzenini ve acil durdurmayı ayrı ayrı kapsamalıdır.",
      "Statik yük deneyi beyan edilen kapasitenin 1,25 katı, dinamik yük deneyi 1,1 katı ile yapılmış olmalıdır.",
      "Beyan edilen kaldırma kapasitesi, ekipman üzerinde uzaktan okunabilir şekilde bulunmalıdır.",
      "Raporda uygunsuzluk kaydedilmişse, kapatıldığına dair takip kaydı da dosyada bulunmalıdır.",
    ],
    ifPresentTr:
      "Rapor mevcutsa; düzenleme tarihini, raporu düzenleyen kişinin yetki belgesini ve uygunsuzluk maddelerinin kapatılıp kapatılmadığını inceleyin.",
    ifAbsentTr:
      "Rapor yoksa veya süresi dolmuşsa, ekipmanı yük altına almadan önce periyodik kontrolü yetkili kişiye yaptırın ve kontrol sonuçlanana kadar kullanımı kısıtlayın.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III.",
      "Standart — TS ISO 9927-1 Vinçlerin Muayenesi.",
      "Standart — TS EN 13001 Kaldırma Makineleri, Genel Tasarım Esasları.",
    ],
    interval: {
      textTr: "Standartlarda aksi belirtilmedikçe yılda bir",
      basisCode: "TR-IS-EKIPMANLARI-EK3-KALDIRMA",
      verified: false,
    },
    relatedLayers: [7],
  },

  lifting_accessory: {
    family: "lifting_accessory",
    recommendationClass: "periodic_inspection_record",
    titleTr: "Sapan, Zincir ve Kaldırma Aksesuarları — Kontrol Kaydı",
    categoryLabelTr: "Kaldırma Ekipmanları",
    assetLabelTr: "kaldırma aksesuarı",
    observationTr:
      "Sahada sapan, zincir, halat, mapa veya kanca türü kaldırma aksesuarı görülmektedir. Bu elemanlar vinçten bağımsız birer iş ekipmanıdır ve kendi kontrol kayıtlarını gerektirir; vincin raporu bunları kapsamaz.",
    requirementsTr: [
      "Her aksesuarın üzerinde okunabilir bir tanıtım etiketi ve beyan edilen çalışma yükü limiti bulunmalıdır.",
      "Etiket numarası ile eşleşen periyodik kontrol kaydı ve imalatçı uygunluk beyanı dosyada olmalıdır.",
      "Kontrolde; kopmuş tel, bükülme, düğüm, aşınma, korozyon, deformasyon, kanca ağız açıklığı ve mandal işlevi kayıt altına alınmış olmalıdır.",
      "Kullanım öncesi gözle muayenenin kim tarafından ve hangi sıklıkta yapıldığı tanımlı olmalıdır.",
    ],
    ifPresentTr:
      "Kayıt mevcutsa; etiket numaralarının sahadaki aksesuarlarla birebir eşleştiğini ve hurdaya ayırma ölçütlerinin uygulandığını doğrulayın.",
    ifAbsentTr:
      "Kayıt yoksa, etiketsiz ve kaydı bulunmayan aksesuarları kullanım dışı bırakın ve yetkili kişiye kontrol ettirerek envanteri etiketleyin.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III.",
      "Standart — TS EN 818 Kaldırma Zincirleri.",
      "Standart — TS EN 13414 Çelik Tel Halat Sapanlar.",
    ],
    interval: {
      textTr: "Standartlarda aksi belirtilmedikçe yılda bir",
      basisCode: "TR-IS-EKIPMANLARI-EK3-KALDIRMA",
      verified: false,
    },
    relatedLayers: [7],
  },

  storage_tank: {
    family: "storage_tank",
    recommendationClass: "measurement_record",
    titleTr: "Depolama Tankı — API 653 Muayenesi ve Et Kalınlığı Ölçümü",
    categoryLabelTr: "Basınçlı ve Depolama Ekipmanları",
    assetLabelTr: "depolama tankı",
    observationTr:
      "Sahada atmosferik depolama tankı görülmektedir. Bu ekipmanlarda kabuk, taban ve çatı kalınlığı işletme süresince korozyonla azalır ve kayıp gözle görülmez; bu nedenle tankın durumu yalnızca ölçüm kayıtlarıyla bilinebilir.",
    requirementsTr: [
      "Tank, API 653 kapsamında yetkili muayene personeli tarafından muayene edilmiş olmalıdır.",
      "Kabuk, taban ve çatı için ultrasonik et kalınlığı ölçüm raporu bulunmalı; ölçülen değerler hesaplanan minimum kalınlığın üzerinde olmalıdır.",
      "Ölçüm noktaları krokilendirilmiş olmalı ve önceki ölçümle karşılaştırılarak korozyon hızı hesaplanmış olmalıdır.",
      "Bir sonraki muayene tarihi, hesaplanan korozyon hızı ve kalan ömür üzerinden belirlenmiş olmalıdır.",
      "Tankın imalat dayanağı (API 650 veya eşdeğeri) ve varsa tamir-tadilat kayıtları dosyada bulunmalıdır.",
      "Katodik koruma uygulanıyorsa API 651 kapsamındaki ölçüm kayıtları da istenmelidir.",
    ],
    ifPresentTr:
      "Rapor mevcutsa; ölçüm tarihini, ölçülen minimum kalınlığı, hesaplanan korozyon hızını ve bir sonraki muayene tarihinin geçilip geçilmediğini inceleyin.",
    ifAbsentTr:
      "Ölçüm kaydı yoksa, API 653 kapsamında dış muayene ve ultrasonik et kalınlığı ölçümü yaptırın; taban ve alt kabuk bölgesini öncelikli ölçüm alanı olarak tanımlayın.",
    referencesTr: [
      "Standart — API 653 Tank Inspection, Repair, Alteration and Reconstruction.",
      "Standart — API 650 Welded Tanks for Oil Storage.",
      "Standart — API 651 Cathodic Protection of Aboveground Storage Tanks.",
      "Standart — TS EN ISO 16809 Ultrasonik Kalınlık Ölçümü.",
    ],
    interval: {
      textTr: "Dış muayene en çok 5 yılda bir; iç muayene hesaplanan korozyon hızına göre",
      basisCode: "API-653-INSPECTION-INTERVAL",
      verified: false,
    },
    relatedLayers: [11, 12],
  },

  pressure_vessel: {
    family: "pressure_vessel",
    recommendationClass: "measurement_record",
    titleTr: "Basınçlı Kap — Periyodik Kontrol ve API 510 Muayenesi",
    categoryLabelTr: "Basınçlı ve Depolama Ekipmanları",
    assetLabelTr: "basınçlı kap",
    observationTr:
      "Sahada basınçlı kap, hava tankı veya kazan görülmektedir. Basınçlı ekipmanın iç yüzeyi ve cidar kalınlığı dışarıdan değerlendirilemez; güvenli olduğu yalnız basınç testi ve kalınlık ölçümü kayıtlarıyla söylenebilir.",
    requirementsTr: [
      "Periyodik kontrol, makine mühendisi veya yetkilendirilmiş muayene kuruluşu tarafından yapılmış olmalıdır.",
      "Hidrostatik test, işletme basıncının 1,5 katı ile uygulanmış ve sonucu raporlanmış olmalıdır.",
      "Ultrasonik et kalınlığı ölçümü yapılmış ve ölçülen değerler hesaplanan minimum kalınlığın üzerinde olmalıdır.",
      "Emniyet ventili ayar basıncı, ekipmanın tasarım basıncına göre doğrulanmış ve mühürlenmiş olmalıdır.",
      "Manometre kalibrasyon kaydı bulunmalı ve gösterge işletme aralığında okunabilir olmalıdır.",
      "İmalatçı uygunluk beyanı, tasarım basıncı ve hacim bilgisi ekipman etiketinde bulunmalıdır.",
    ],
    ifPresentTr:
      "Rapor mevcutsa; test tarihini, uygulanan test basıncını, et kalınlığı sonuçlarını ve emniyet ventili ayar kaydını inceleyin.",
    ifAbsentTr:
      "Kayıt yoksa, ekipmanı işletmeden çıkarmadan önce periyodik kontrolü planlayın; hidrostatik test, et kalınlığı ölçümü ve emniyet ventili doğrulamasını birlikte yaptırın.",
    referencesTr: [
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III.",
      "Mevzuat — Basınçlı Ekipmanlar Yönetmeliği.",
      "Standart — API 510 Pressure Vessel Inspection Code.",
      "Standart — TS EN ISO 16809 Ultrasonik Kalınlık Ölçümü.",
    ],
    interval: {
      textTr: "Standartlarda aksi belirtilmedikçe yılda bir",
      basisCode: "TR-IS-EKIPMANLARI-EK3-BASINCLI",
      verified: false,
    },
    relatedLayers: [12, 14],
  },

  process_piping: {
    family: "process_piping",
    recommendationClass: "measurement_record",
    titleTr: "Proses Borulaması — API 570 Muayenesi",
    categoryLabelTr: "Basınçlı ve Depolama Ekipmanları",
    assetLabelTr: "proses borulaması",
    observationTr:
      "Sahada proses borulaması ve bağlantı elemanları görülmektedir. Boru hatlarında incelme dirsek, redüksiyon ve destek noktalarında yoğunlaşır; bu bölgeler boyalı yüzey altında gözle değerlendirilemez.",
    requirementsTr: [
      "Boru hatları API 570 kapsamında sınıflandırılmış ve muayene planına bağlanmış olmalıdır.",
      "Kalınlık ölçüm noktaları (TML) tanımlanmış ve ölçüm sonuçları kayıt altına alınmış olmalıdır.",
      "Destek, askı ve genleşme düzeninin muayene kaydı bulunmalıdır.",
      "Hat üzerindeki geçici tamirlerin kaydı ve kalıcı onarım planı dosyada olmalıdır.",
    ],
    ifPresentTr:
      "Kayıt mevcutsa; ölçüm noktalarının kroki ile eşleştiğini ve kalan ömür hesabının güncel olduğunu doğrulayın.",
    ifAbsentTr:
      "Kayıt yoksa, hattı API 570 kapsamında sınıflandırın, kalınlık ölçüm noktalarını belirleyin ve ilk ölçümü yaptırın.",
    referencesTr: [
      "Standart — API 570 Piping Inspection Code.",
      "Standart — TS EN ISO 16809 Ultrasonik Kalınlık Ölçümü.",
    ],
    relatedLayers: [12, 14],
  },

  electrical_panel: {
    family: "electrical_panel",
    recommendationClass: "measurement_record",
    titleTr: "Elektrik Panosu — İç Tesisat ve Topraklama Ölçüm Raporları",
    categoryLabelTr: "Elektrik Tesisatı",
    assetLabelTr: "elektrik panosu",
    observationTr:
      "Sahada elektrik panosu veya dağıtım tesisatı görülmektedir. Tesisatın güvenli olduğu gözle değil ölçümle bilinir; yalıtım direnci, topraklama direnci ve kaçak akım koruma işlevi ancak rapora bakılarak değerlendirilebilir.",
    requirementsTr: [
      "Elektrik iç tesisat uygunluk raporu ve topraklama ölçüm raporu, yetkili elektrik mühendisi tarafından düzenlenmiş olmalıdır.",
      "Raporda ölçülen topraklama direnci değeri sayısal olarak yer almalı ve tesisatın koruma düzenine göre sınır değerin altında olmalıdır.",
      "Kaçak akım koruma rölesinin açma akımı ve açma süresi ölçülmüş, test butonu denemesi kayıt altına alınmış olmalıdır.",
      "Yalıtım direnci ölçüm sonuçları devre bazında raporlanmış olmalıdır.",
      "Rapor yalnız 'uygundur' ibaresi taşımamalı; ölçülen değerleri ve ölçüm cihazının kalibrasyon kaydını içermelidir.",
      "Pano önünde serbest çalışma alanı bırakılmış, pano kapağı kilitli ve ilgisiz kişilerin erişimine kapalı olmalıdır.",
    ],
    ifPresentTr:
      "Rapor mevcutsa; ölçüm tarihini, ölçülen direnç değerlerini ve bu değerlerin sınırların altında kalıp kalmadığını inceleyin. Raporun varlığı yeterli değildir, sonucun uygun olması gerekir.",
    ifAbsentTr:
      "Rapor yoksa veya süresi dolmuşsa, elektrik iç tesisat ve topraklama ölçümlerini yetkili kişiye yaptırın; ölçüm sonucu uygun çıkmayan devrelerde düzeltme tamamlanana kadar kullanımı kısıtlayın.",
    referencesTr: [
      "Mevzuat — Elektrik Tesislerinde Topraklamalar Yönetmeliği.",
      "Mevzuat — Elektrik İç Tesisleri Yönetmeliği.",
      "Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III.",
      "Standart — TS HD 60364 Alçak Gerilim Elektrik Tesisatı.",
    ],
    interval: {
      textTr: "Standartlarda aksi belirtilmedikçe yılda bir",
      basisCode: "TR-TOPRAKLAMA-YONETMELIK",
      verified: false,
    },
    relatedLayers: [5],
  },

  earthing_system: {
    family: "earthing_system",
    recommendationClass: "site_verification",
    titleTr: "Ekipman Gövde Topraklamaları",
    categoryLabelTr: "Elektrik Tesisatı",
    assetLabelTr: "elektrikli ekipman",
    observationTr:
      "Sahada gövdesi iletken elektrikli ekipman görülmektedir. Yalıtım arızasında gövde üzerinde tehlikeli gerilim oluşur; gövde topraklaması, bu gerilimi koruma düzeninin açacağı seviyeye taşıyan tek düzenektir.",
    requirementsTr: [
      "Tezgâh, kaynak makinesi, kompresör ve benzeri sabit ekipmanların gövdeleri koruma iletkeni ile topraklanmış olmalıdır.",
      "Gövde topraklaması ile pano toprak barası arasındaki süreklilik ölçülmüş ve kayıt altına alınmış olmalıdır.",
      "Topraklama iletkeninin kesiti, beslediği devrenin akımına göre seçilmiş olmalıdır.",
      "Seyyar ekipmanlarda topraklama iletkeninin fiş ve prizde kesintisiz olduğu doğrulanmalıdır.",
    ],
    ifPresentTr:
      "Süreklilik ölçüm kaydı mevcutsa; ölçümün ekipman bazında yapıldığını ve sahadaki envanterle eşleştiğini doğrulayın.",
    ifAbsentTr:
      "Gövde topraklaması bulunmayan veya sürekliliği ölçülmemiş ekipmanların topraklamasını mutlaka yaptırın ve süreklilik ölçümünü ekipman bazında kayda geçirin.",
    referencesTr: [
      "Mevzuat — Elektrik Tesislerinde Topraklamalar Yönetmeliği.",
      "Standart — TS HD 60364 Alçak Gerilim Elektrik Tesisatı.",
    ],
    relatedLayers: [5, 6],
  },

  gas_cylinder: {
    family: "gas_cylinder",
    recommendationClass: "site_verification",
    titleTr: "Basınçlı Gaz Tüpleri — Depolama Düzeni ve Uyumluluk Matrisi",
    categoryLabelTr: "Basınçlı ve Depolama Ekipmanları",
    assetLabelTr: "basınçlı gaz tüpü",
    observationTr:
      "Sahada basınçlı gaz tüpü görülmektedir. Tüplerde asıl belirleyici olan tüpün kendi durumundan çok nasıl depolandığıdır; yanlış komşuluk, devrilme ve vana hasarı en sık görülen üç başlangıç olayıdır.",
    requirementsTr: [
      "Tüplerin depolandığı alan için gaz uyumluluk (depolama) matrisi hazırlanmış ve alanda uygulanıyor olmalıdır.",
      "Yanıcı gaz tüpleri ile oksitleyici gaz tüpleri ayrı bölmelerde depolanmalı; ayrım mesafesi sağlanamıyorsa aralarına yanmaz bariyer konulmalıdır.",
      "Tüpler dik konumda, devrilmeye karşı zincir veya kelepçe ile sabitlenmiş olmalıdır.",
      "Kullanılmayan tüplerde vana koruma başlığı takılı olmalıdır.",
      "Dolu ve boş tüpler ayrı ve işaretlenmiş alanlarda bulunmalıdır.",
      "Depolama alanı üstten havalandırmalı, ısı kaynaklarından ve elektrik tesisatından uzak olmalıdır.",
      "Tüplerin periyodik hidrostatik test tarihleri, tüp omuzundaki damgadan okunabilir olmalıdır.",
    ],
    ifPresentTr:
      "Depolama matrisi mevcutsa; sahadaki yerleşimin matrisle uyuştuğunu, ayrım mesafelerinin korunduğunu ve test damgalarının süresinin geçmediğini doğrulayın.",
    ifAbsentTr:
      "Depolama matrisi yoksa, sahadaki gaz envanterini çıkarın, uyumluluk matrisini hazırlayın ve yerleşimi matrise göre yeniden düzenleyin.",
    referencesTr: [
      "Mevzuat — Kimyasal Maddelerle Çalışmalarda Sağlık ve Güvenlik Önlemleri Hakkında Yönetmelik.",
      "Standart — TS EN ISO 11114 Gaz Tüpleri, Malzeme Uyumluluğu.",
      "Standart — TS 11891 Basınçlı Gaz Tüpleri, Depolama ve Taşıma Kuralları.",
    ],
    relatedLayers: [10, 13],
  },
};
