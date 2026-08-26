// Unscored items (assurance_requirement, verification_request) shipped with an
// empty recommended_measures array, so the report told the reader that a tank's
// internal integrity could not be confirmed and then said nothing about what to
// actually do. This module carries the deterministic playbook for those items:
// concrete field steps plus a curated reference list.
//
// References are hand-curated on purpose. ANALYSIS_DEPTH_AND_SCORING_PLAN's rule
// is that an empty reference is safer than a wrong one and that the model must
// never invent an article number, so nothing here comes from the provider and no
// entry carries a Resmî Gazete or clause number.

import type { V4ModuleID } from "./contracts.ts";

export type AssurancePlaybook = {
  /** Ordered field steps, published as the corrective measure. */
  steps: string[];
  /** Standing arrangement that keeps the assurance valid. */
  preventive: string;
  /** Curated standard and regulation names. Empty when none is defensible. */
  references: string[];
};

const GENERIC: AssurancePlaybook = {
  steps: [
    "Varlığı ve tehlike konusunu sahada tanımlayın; belge, ölçüm veya test gerektiren yönü yazılı olarak belirleyin.",
    "Doğrulamayı yetkili kişiye yaptırın ve sonucu tarih, sorumlu ve kabul ölçütüyle kayıt altına alın.",
    "Doğrulama tamamlanana kadar alandaki maruziyeti sınırlandırın.",
  ],
  preventive:
    "Bu varlık için doğrulama sıklığını, sorumlusunu ve kayıt yerini belirleyip periyodik kontrol planına ekleyin.",
  references: [
    "İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği",
  ],
};

const BY_TOPIC: Record<string, AssurancePlaybook> = {
  process_containment_integrity: {
    steps: [
      "Tank veya borulama hattının kimliğini, hizmet sınıfını, tasarım basıncını ve içindeki maddeyi ekipman dosyasından teyit edin.",
      "Yürürlükteki kalınlık ölçümü, dip plakası ve kaynak dikişi muayene kayıtlarını, bir sonraki muayene tarihiyle birlikte kontrol edin; atmosferik depolama tankında API 653, proses borulamasında API 570, basınçlı kapta API 510 muayene kapsamını esas alın.",
      "Emniyet valfi, tahliye hattı, seviye ve basınç göstergelerinin son kalibrasyon ve test kayıtlarını doğrulayın.",
      "İkincil muhafaza, drenaj ve dökülme toplama düzeninin hacim yeterliliğini sahada ölçün.",
      "İzolasyon noktalarını, acil boşaltma senaryosunu ve müdahale ekipmanının yerini yerinde kontrol edin.",
    ],
    preventive:
      "Ekipmanı risk bazlı muayene programına bağlayın; muayene aralığını, kalınlık ölçüm noktalarını ve kabul sınırlarını yazılı hale getirip periyodik kontrol takvimine işleyin.",
    references: [
      "API 653 — Atmosferik depolama tanklarında muayene, onarım ve değiştirme",
      "API 570 — Proses borulamasında muayene ve değerlendirme",
      "API 510 — Basınçlı kaplarda muayene",
      "Basınçlı Ekipmanlar Yönetmeliği (2014/68/AB)",
      "İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği — periyodik kontroller",
    ],
  },
  machine_protective_systems: {
    steps: [
      "Makinenin sabit ve hareketli koruyucularının yerinde, sağlam ve alet gerektirmeden sökülemez olduğunu kontrol edin.",
      "Kilitlemeli koruyucularda kapak açıldığında hareketin durduğunu; kilitleme elemanının kolayca aldatılamadığını fiilen deneyin.",
      "Acil durdurma butonlarının erişilebilirliğini, kilitli kalışını ve durdurma süresini test edin.",
      "CE işareti, uygunluk beyanı, kullanma talimatı ve makineye yapılmış değişikliklerin risk değerlendirmesini belge üzerinden doğrulayın.",
      "Bakım ve temizlik sırasında enerji izolasyonunun nasıl sağlandığını operatörle birlikte teyit edin.",
    ],
    preventive:
      "Koruyucu, kilitleme ve acil durdurma işlevlerini vardiya öncesi kontrol listesine ve periyodik bakım planına bağlayın; koruyucu devre dışı bırakma için yasak ve yaptırım kuralı tanımlayın.",
    references: [
      "TS EN ISO 12100 — Makinelerde risk değerlendirmesi ve risk azaltma",
      "TS EN ISO 14120 — Koruyucular: sabit ve hareketli koruyucuların tasarımı",
      "TS EN ISO 14119 — Koruyucularla ilgili kilitleme tertibatları",
      "TS EN ISO 13850 — Acil durdurma işlevi",
      "TS EN 60204-1 — Makinelerde elektrik donanımı",
      "Makina Emniyeti Yönetmeliği (2006/42/AT)",
    ],
  },
  lifting_inspection: {
    steps: [
      "Kaldırma ekipmanının ve kaldırma aksesuarlarının üzerindeki kimlik, anma yükü ve son periyodik kontrol etiketini okuyun.",
      "Periyodik kontrol raporunun geçerlilik tarihini ve raporu düzenleyen kişinin yetkisini doğrulayın.",
      "Kanca, mandal, sapan, zincir ve mapaları gözle muayene edin; deformasyon, aşınma, çatlak ve kesit kaybı olanları hizmet dışı bırakın.",
      "Kaldırılacak yükün ağırlığını, ağırlık merkezini ve sapan açısını hesaplayarak ekipman kapasitesiyle karşılaştırın.",
      "Yük altında ve salınım alanında insan bulunmamasını sağlayacak saha düzenini ve işaretçi görevlendirmesini teyit edin.",
    ],
    preventive:
      "Kaldırma ekipmanı ve aksesuarları için envanter, periyodik kontrol takvimi ve kullanım öncesi gözle muayene kaydı tutun; operatör ve sapancı yetkilendirmesini belgelendirin.",
    references: [
      "İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği — kaldırma ekipmanlarında periyodik kontrol",
      "TS EN 1677 — Kaldırma aksesuarları: dövme çelik parçalar ve kancalar",
      "TS EN 13155 — Vinçler: ayrılabilir yük kaldırma donanımı",
      "TS ISO 12480-1 — Vinçlerin güvenli kullanımı",
    ],
  },
  working_at_height_access: {
    steps: [
      "Açık kenarın tamamında korkuluk sürekliliğini ölçün; ana korkuluk, ara korkuluk ve topuk levhasının kesintisiz olduğunu doğrulayın.",
      "Korkuluk yüksekliğini, boşluk mesafelerini ve yatay yük dayanımını üretici veya tasarım verisiyle karşılaştırın.",
      "Platform, döşeme ve erişim merdivenlerinin sabitliğini, taşıma kapasitesini ve boşluk kapaklarını kontrol edin.",
      "Toplu koruma uygulanamıyorsa ankraj noktasının hesaplanmış olduğunu, kişisel düşme durdurma sisteminin uygun ve kontrollü olduğunu belgeleyin.",
      "Düşen cisim yolunu kapatan topuk levhası, ağ veya alt kordon düzenini sahada teyit edin.",
    ],
    preventive:
      "Kenar koruma planını iş programına bağlayın; kurulum, değişiklik ve söküm yetkisini tek sorumluya verip vardiya öncesi kenar bütünlüğü kontrolünü zorunlu kılın.",
    references: [
      "Yapı İşlerinde İş Sağlığı ve Güvenliği Yönetmeliği — yüksekte çalışma ve kenar koruması",
      "TS EN 13374 — Geçici kenar koruma sistemleri",
      "TS EN 12811-1 — Geçici iş donanımı: iş iskeleleri",
      "TS EN 795 — Ankraj cihazları",
      "Kişisel Koruyucu Donanımların İşyerlerinde Kullanılması Hakkında Yönetmelik",
    ],
  },
  electrical_internal_integrity: {
    steps: [
      "Panonun veya ekipmanın besleme kaynağını, koruma cihazı seçiciliğini ve kısa devre dayanımını proje üzerinden doğrulayın.",
      "Topraklama sürekliliğini ve topraklama direncini ölçtürün; ölçüm raporunun geçerlilik tarihini kontrol edin.",
      "Kaçak akım koruma cihazının test tuşuyla ve test cihazıyla açma süresini deneyin.",
      "Pano kapağı, kilit, IP koruma sınıfı ve etiketlemenin ortam koşuluna uygunluğunu kontrol edin.",
      "İşlemleri yalnız yetkili elektrik personeline yaptırın; ölçüm ve test sonuçlarını kayıt altına alın.",
    ],
    preventive:
      "Elektrik tesisinin periyodik ölçüm ve muayene takvimini oluşturun; pano açma yetkisini sınırlandırıp değişiklikleri tek hat şemasına işleyin.",
    references: [
      "Elektrik Tesislerinde Topraklamalar Yönetmeliği",
      "Elektrik Kuvvetli Akım Tesisleri Yönetmeliği",
      "Elektrik İç Tesisleri Yönetmeliği",
      "TS EN 60204-1 — Makinelerde elektrik donanımı",
      "İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği — elektrik tesisatı periyodik kontrolü",
    ],
  },
  energy_isolation_controls: {
    steps: [
      "Ekipmanı besleyen tüm enerji kaynaklarını (elektrik, basınçlı akışkan, buhar, yerçekimi, yay, kimyasal) tek tek listeleyin.",
      "Her kaynak için izolasyon noktasını belirleyin; kilit ve etiket uygulanabilirliğini sahada kontrol edin.",
      "Birikmiş enerjiyi boşaltın ve sıfır enerji durumunu ölçerek doğrulayın.",
      "Kilit anahtarının tek kişide kaldığını, grup çalışmasında grup kilit kutusu kullanıldığını teyit edin.",
      "Yeniden enerjilendirme öncesi alan boşaltma ve kilit kaldırma sırasını yazılı prosedürle karşılaştırın.",
    ],
    preventive:
      "Ekipman bazlı izolasyon talimatı hazırlayın; kilit-etiket ekipmanını, yetkili personel listesini ve yıllık tatbikat planını tanımlayın.",
    references: [
      "TS EN ISO 14118 — Beklenmeyen çalıştırmanın önlenmesi",
      "TS EN 1037 — Makinelerde beklenmeyen çalışmaya karşı önlemler",
      "İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği — bakım ve onarım güvenliği",
    ],
  },
  chemical_identity_and_exposure: {
    steps: [
      "Kabın etiketini okuyun; madde adını, CAS numarasını ve zararlılık işaretlerini kayıt altına alın.",
      "Güvenlik bilgi formunu temin edip depolama, geçimsizlik ve müdahale bölümlerini sahadaki uygulamayla karşılaştırın.",
      "Ortam ölçümü gerekiyorsa maruziyet sınır değerine göre kişisel veya ortam ölçümü planlayın.",
      "Havalandırma, göz duşu, acil duş ve dökülme seti erişilebilirliğini test edin.",
      "Seçilen kişisel koruyucu donanımın malzemeye ve maruziyet süresine uygunluğunu belge üzerinden doğrulayın.",
    ],
    preventive:
      "Kimyasal envanterini güncel tutun; güvenlik bilgi formlarını erişilebilir kılın ve geçimsiz maddeler için ayrık depolama kuralı tanımlayın.",
    references: [
      "Kimyasal Maddelerle Çalışmalarda Sağlık ve Güvenlik Önlemleri Hakkında Yönetmelik",
      "Zararlı Maddeler ve Karışımlara İlişkin Güvenlik Bilgi Formları Hakkında Yönetmelik",
      "Maddelerin ve Karışımların Sınıflandırılması, Etiketlenmesi ve Ambalajlanması Hakkında Yönetmelik (SEA)",
    ],
  },
  confined_space_controls: {
    steps: [
      "Alanın kapalı alan tanımına girip girmediğini yazılı ölçütle belirleyin ve giriş izni sistemine bağlayın.",
      "Girişten önce oksijen, patlayıcı gaz ve toksik gaz ölçümü yaptırın; ölçümü giriş süresince sürdürün.",
      "Besleme hatlarını kör tapa veya fiziksel ayırma ile izole edin ve mekanik hareketi kilitleyin.",
      "Sürekli havalandırmayı kurun; gözcü, iletişim düzeni ve geri çekme ekipmanını hazır bulundurun.",
      "Kurtarma planını, kurtarma ekibini ve tatbikat kaydını girişten önce doğrulayın.",
    ],
    preventive:
      "Kapalı alan envanteri çıkarın, girişleri izin sistemine bağlayın ve gözcü, ölçüm, kurtarma eğitimlerini periyodik tekrarlayın.",
    references: [
      "İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği",
      "Çalışanların Patlayıcı Ortamların Tehlikelerinden Korunması Hakkında Yönetmelik",
      "Kişisel Koruyucu Donanımların İşyerlerinde Kullanılması Hakkında Yönetmelik",
    ],
  },
  excavation_stability_controls: {
    steps: [
      "Kazı derinliğini, şev açısını ve zemin sınıfını yetkili kişiye tespit ettirin.",
      "İksa veya şev tasarımının hesabını ve uygulama uygunluğunu belge üzerinden doğrulayın.",
      "Yeraltı hizmet hatlarının yerini kurum bilgisi ve dedektörle tespit edin.",
      "Kazı kenarına malzeme ve araç yaklaşma mesafesini işaretleyip fiziksel bariyerle ayırın.",
      "Su, titreşim ve hava koşulu sonrası kazıyı yeniden muayene ettirin.",
    ],
    preventive:
      "Kazı için yetkili kişi görevlendirin; günlük muayene kaydı, giriş-çıkış düzeni ve hava koşulu sonrası yeniden değerlendirme kuralı tanımlayın.",
    references: [
      "Yapı İşlerinde İş Sağlığı ve Güvenliği Yönetmeliği — kazı işleri",
      "TS 8853 — Zemin işleri ve iksa uygulamaları",
    ],
  },
  hot_work_controls: {
    steps: [
      "Sıcak çalışma iznini işe başlamadan önce düzenleyin; izin süresini ve alan sınırını yazın.",
      "Yanıcı ve parlayıcı malzemeyi çalışma alanından uzaklaştırın ya da yanmaz örtüyle koruyun.",
      "Gerekli yerlerde gaz ölçümü yaptırın ve ölçümü çalışma boyunca tekrarlayın.",
      "Yangın gözcüsü görevlendirin, uygun söndürücüyü alanda bulundurun.",
      "Çalışma bittikten sonra alanı en az yarım saat izleyin ve izni kapatın.",
    ],
    preventive:
      "Sıcak çalışma izin sistemini yazılı hale getirin; izin veren, uygulayan ve gözcü rollerini yetkilendirip kayıtları saklayın.",
    references: [
      "Binaların Yangından Korunması Hakkında Yönetmelik",
      "Çalışanların Patlayıcı Ortamların Tehlikelerinden Korunması Hakkında Yönetmelik",
      "İşyerlerinde Acil Durumlar Hakkında Yönetmelik",
    ],
  },
  mobile_equipment_controls: {
    steps: [
      "Ekipmanın kimliğini, kapasitesini ve son periyodik kontrol kaydını doğrulayın.",
      "Operatör yetki belgesini ve ekipmana özgü yetkilendirmeyi kontrol edin.",
      "Fren, korna, ikaz lambası, ayna ve kamera işlevlerini kullanım öncesi test ettirin.",
      "Yaya–araç ayrımını, geçiş yollarını, hız sınırını ve kör nokta düzenlemesini sahada ölçün.",
      "Günlük kullanım öncesi kontrol formunun doldurulduğunu ve arızaların takip edildiğini teyit edin.",
    ],
    preventive:
      "Saha trafik planı hazırlayın; yaya yollarını fiziksel olarak ayırın, kullanım öncesi kontrol ve bakım takvimini zorunlu kılın.",
    references: [
      "İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği",
      "TS ISO 3691 — Endüstriyel araçlar: güvenlik kuralları",
      "İşyeri Bina ve Eklentilerinde Alınacak Sağlık ve Güvenlik Önlemlerine İlişkin Yönetmelik — geçiş yolları",
    ],
  },
  combustible_dust_controls: {
    steps: [
      "Tozun patlayabilirlik özelliklerini malzeme verisi veya laboratuvar analiziyle belirleyin.",
      "Patlayıcı ortam oluşabilecek bölgeleri sınıflandırıp patlamadan korunma dokümanına işleyin.",
      "Toz birikimini ölçün; yatay yüzeylerdeki birikimi kaldıracak temizlik yöntemini tanımlayın.",
      "Tutuşturucu kaynakları (statik elektrik, sıcak yüzey, kıvılcım, uygun olmayan ekipman) tek tek eleyin.",
      "Toplama, havalandırma ve patlama tahliye düzeninin performansını belge üzerinden doğrulayın.",
    ],
    preventive:
      "Patlamadan korunma dokümanını güncel tutun; toz temizlik sıklığını, ekipman seçim kuralını ve statik topraklama kontrolünü planlayın.",
    references: [
      "Çalışanların Patlayıcı Ortamların Tehlikelerinden Korunması Hakkında Yönetmelik",
      "TS EN 60079-10-2 — Patlayıcı ortamlar: yanıcı toz ortamlarının sınıflandırılması",
      "NFPA 652 — Yanıcı toz tehlikelerinin temel esasları",
    ],
  },
  fire_emergency_readiness: {
    steps: [
      "Yangın söndürücü, dolap ve algılama cihazlarının yerini, erişilebilirliğini ve son kontrol etiketini doğrulayın.",
      "Kaçış yollarının ve acil çıkış kapılarının açık, işaretli ve engelsiz olduğunu ölçün.",
      "Acil durum planını, görevlendirmeleri ve son tatbikat kaydını belge üzerinden kontrol edin.",
      "Tutuşturucu kaynak kontrolünü ve yanıcı madde depolama düzenini sahada inceleyin.",
      "Algılama, uyarı ve söndürme sistemlerinin bakım kayıtlarını doğrulayın.",
    ],
    preventive:
      "Acil durum planını yılda en az bir kez tatbikatla sınayın; ekipman bakım takvimini ve kaçış yolu denetimini periyodik kontrol listesine bağlayın.",
    references: [
      "Binaların Yangından Korunması Hakkında Yönetmelik",
      "İşyerlerinde Acil Durumlar Hakkında Yönetmelik",
      "TS EN 3 — Taşınabilir yangın söndürücüler",
    ],
  },
  biosecurity_controls: {
    steps: [
      "Maruz kalınan biyolojik etkeni ve risk grubunu belirleyin.",
      "Bulaş yolunu keserek çalışma düzenini gözden geçirin; havalandırma ve ayrım önlemlerini kontrol edin.",
      "Dekontaminasyon, atık ayrıştırma ve taşıma akışını sahada izleyin.",
      "Koruyucu donanım seçimini ve giyme-çıkarma sırasını uygulamalı olarak doğrulayın.",
      "Sağlık gözetimi ve bağışıklama kayıtlarının güncelliğini kontrol edin.",
    ],
    preventive:
      "Biyolojik risk envanteri tutun; dekontaminasyon prosedürünü, atık akışını ve sağlık gözetimi takvimini yazılı hale getirin.",
    references: [
      "Biyolojik Etkenlere Maruziyet Risklerinin Önlenmesi Hakkında Yönetmelik",
      "Kişisel Koruyucu Donanımların İşyerlerinde Kullanılması Hakkında Yönetmelik",
    ],
  },
  asset_assurance_generic: GENERIC,
};

// A verification_request is raised when the module itself stayed unresolved, so
// it is keyed by module rather than by assurance topic.
const MODULE_TO_TOPIC: Partial<Record<V4ModuleID, string>> = {
  falls_falling_objects: "working_at_height_access",
  work_at_height: "working_at_height_access",
  machinery: "machine_protective_systems",
  electrical: "electrical_internal_integrity",
  energy: "energy_isolation_controls",
  vehicles_mobile_equipment: "mobile_equipment_controls",
  logistics: "mobile_equipment_controls",
  lifting: "lifting_inspection",
  process_integrity: "process_containment_integrity",
  chemical: "chemical_identity_and_exposure",
  confined_space: "confined_space_controls",
  excavation: "excavation_stability_controls",
  hot_work: "hot_work_controls",
  biosecurity: "biosecurity_controls",
  combustible_dust: "combustible_dust_controls",
  fire_explosion_release: "fire_emergency_readiness",
};

export function playbookForTopic(topicID: string): AssurancePlaybook {
  return BY_TOPIC[topicID] ?? GENERIC;
}

export function playbookForModule(moduleID: V4ModuleID): AssurancePlaybook {
  return playbookForTopic(MODULE_TO_TOPIC[moduleID] ?? "asset_assurance_generic");
}

/**
 * Curated references, joined for `findings.references_text`. Returns "" for any
 * profile whose jurisdiction policy does not allow references, because a wrong
 * or out-of-jurisdiction citation is worse than none.
 */
export function referencesTextFor(
  playbook: AssurancePlaybook,
  policy: string | null,
): string {
  if (policy !== "tr_current") return "";
  return playbook.references.join("\n");
}

export function assuranceMeasures(
  playbook: AssurancePlaybook,
  correctiveTitle: string,
): Array<{ kind: "corrective" | "preventive"; title: string; text: string }> {
  const steps = playbook.steps
    .map((step, index) => `${index + 1}. ${step}`)
    .join("\n");
  return [
    { kind: "corrective", title: correctiveTitle, text: steps },
    { kind: "preventive", title: "Kalıcı önleme", text: playbook.preventive },
  ];
}
