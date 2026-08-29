// The training catalogue. Nothing outside this file may be recommended.
//
// Each entry is written once, by hand, and the rules only choose between them.
// That is the whole defence against the failure mode this domain punishes: a
// generative sentence that turns MYK into a course, a forklift authorisation
// into a driving licence, or a low-voltage panel into a high-voltage permit.
//
// `topics` is the substance -- what the training actually covers. It is what
// separates a usable recommendation from "İSG eğitimi verilsin", which tells a
// reader nothing. Five topics is the ceiling for one sentence.
//
// `direct` vs `conditional` is mood, not strength. A task the photograph shows
// being performed earns "görev yapan personele"; a machine standing idle earns
// "kullanacak personele", because the picture does not show anyone operating it
// and saying otherwise would be a claim about a person.

import type {
  AudienceCode,
  StatutoryDuration,
  TrainingGroupCode,
  TrainingRecommendationClass,
} from "./contracts.ts";

export interface TrainingCatalogEntry {
  code: string;
  title: string;
  recommendationClass: TrainingRecommendationClass;
  groupCode: TrainingGroupCode;
  audiences: AudienceCode[];
  /** Subject matter, in the order a trainer would cover it. */
  topics: string[];
  /** Context clause for the direct mood: "<context> görev yapan personele". */
  directContext?: string;
  /** Context clause for the conditional mood: "<context> kullanacak personele". */
  conditionalContext?: string;
  /** Optional second sentence. Used where a real distinction must be drawn. */
  secondSentence?: string;
  /**
   * Only where the regulation itself fixes a duration.
   *
   * Two entries have one. Everything else in this catalogue is a training whose
   * length is a matter of content and competence, not law, and putting an hour
   * figure on it would read as a legal minimum that does not exist.
   */
  statutoryDuration?: StatutoryDuration;
  /** Entries sharing a merge key collapse to one card. */
  mergeKey: string;
}

/**
 * Trigger codes.
 *
 * A trigger is a code the analysis already produced: a hazard mechanism, an
 * assurance topic, an equipment family or a sector. Nothing here reads a
 * sentence the model wrote.
 */
export type TrainingRule = {
  entry: string;
  /** Any one of these fires the rule. */
  mechanisms?: string[];
  assuranceTopics?: string[];
  equipment?: string[];
  sectors?: string[];
  /** Fires on any completed analysis. */
  always?: boolean;
  /**
   * Direct when the photograph shows people exposed to the hazard, conditional
   * when it only shows the equipment or the condition.
   */
  directWhenPeopleVisible?: boolean;
  /** A role somebody has to be appointed to before the training applies. */
  specialRole?: boolean;
};

export const TRAINING_CATALOG: Record<string, TrainingCatalogEntry> = {
  // --- General and induction ---------------------------------------------
  "TRN-GEN-002": {
    code: "TRN-GEN-002",
    title: "Temel İş Sağlığı ve Güvenliği Eğitimi",
    recommendationClass: "statutory_ohs_training",
    groupCode: "general_and_induction",
    audiences: ["all_employees"],
    topics: [
      "yasal hak ve yükümlülükler",
      "işyerindeki genel riskler",
      "korunma yöntemleri",
      "sağlık gözetimi",
      "acil durum davranışları",
    ],
    conditionalContext: "Bu işyerinde",
    // Ek-2 fixes the hours and Madde 6 the refresh interval, both on the
    // workplace hazard class. Neither is visible in a photograph, so the
    // renderer shows all three rows whenever the class is unknown.
    statutoryDuration: {
      hoursByHazardClass: { low: 8, medium: 12, high: 16 },
      refreshYearsByHazardClass: { low: 3, medium: 2, high: 1 },
      basisCode: "TR-EGITIM-YONETMELIK-EK2",
      verified: true,
    },
    mergeKey: "general_ohs",
  },
  "TRN-GEN-001": {
    code: "TRN-GEN-001",
    title: "İşe ve İşyerine Özgü Uyum Eğitimi",
    recommendationClass: "site_or_job_induction",
    groupCode: "general_and_induction",
    audiences: ["new_or_transferred_employees"],
    topics: [
      "işyeri kuralları",
      "alana özgü riskler",
      "yasak ve kısıtlı bölgeler",
      "acil durum düzeni",
      "tehlike bildirimi",
    ],
    conditionalContext: "Bu alanda",
    // Carried as a domain expert's statement, not a verified citation: the
    // two-hour floor for pre-start orientation was supplied rather than read
    // off the text, so `verified` stays false until it is checked. The figure
    // renders; no claim to a verified basis is made anywhere alongside it.
    statutoryDuration: {
      minimumHours: 2,
      noteTr: "İşe başlamadan önce",
      basisCode: "TR-EGITIM-YONETMELIK-ISBASI",
      verified: false,
    },
    mergeKey: "induction",
  },

  // --- Hazard-driven practical training ----------------------------------
  "TRN-WAH-001": {
    code: "TRN-WAH-001",
    title: "Yüksekte Güvenli Çalışma ve Düşmeden Korunma",
    recommendationClass: "task_specific_practical_training",
    groupCode: "task_and_equipment",
    audiences: ["work_at_height_personnel"],
    topics: [
      "toplu korunma tedbirleri",
      "paraşüt tipi emniyet kemeri",
      "bağlantı elemanları",
      "uygun ankraj seçimi",
      "acil kurtarma",
    ],
    directContext: "Açık kenar ve yükseltilmiş çalışma alanında",
    conditionalContext: "Açık kenar ve yükseltilmiş çalışma alanında",
    mergeKey: "work_at_height",
  },
  "TRN-MAC-001": {
    code: "TRN-MAC-001",
    title: "Makine Güvenliği ve Enerji İzolasyonu",
    recommendationClass: "task_specific_practical_training",
    groupCode: "task_and_equipment",
    audiences: ["equipment_operators", "maintenance_personnel"],
    topics: [
      "koruyucuların işlevi",
      "güvenli durdurma",
      "enerji kaynaklarının tanınması",
      "kilitleme-etiketleme",
      "yeniden devreye alma kontrolleri",
    ],
    directContext: "Hareketli parçalara erişim bulunan ekipmanlarda",
    conditionalContext: "Hareketli parçalara erişim bulunan ekipmanlarda",
    mergeKey: "machine_safety",
  },
  "TRN-ELE-001": {
    code: "TRN-ELE-001",
    title: "Elektrik Güvenliği ve Geçici Tesisat",
    recommendationClass: "task_specific_practical_training",
    groupCode: "task_and_equipment",
    audiences: ["electrical_personnel", "all_employees"],
    topics: [
      "geçici tesisat kuralları",
      "kablo güzergâhı ve mekanik hasar",
      "yalıtım kontrolü",
      "kaçak akım koruması",
      "enerjisiz çalışma esasları",
    ],
    directContext: "Geçici elektrik tesisatı bulunan alanda",
    conditionalContext: "Geçici elektrik tesisatı bulunan alanda",
    secondSentence:
      "Yüksek gerilim tesisinde çalışma söz konusuysa görevle eşleşen özel yetki koşulu ayrıca değerlendirilmelidir.",
    mergeKey: "electrical_safety",
  },
  "TRN-HK-001": {
    code: "TRN-HK-001",
    title: "Saha Düzeni ve Geçiş Güvenliği",
    recommendationClass: "task_specific_practical_training",
    groupCode: "task_and_equipment",
    audiences: ["all_employees"],
    topics: [
      "geçiş yollarının açık tutulması",
      "malzeme istifleme",
      "ıslak ve düzensiz zemin",
      "açıkta kalan sivri uçların işaretlenmesi",
      "döküntü yönetimi",
    ],
    directContext: "Geçiş güzergâhı ve istif alanlarında",
    conditionalContext: "Geçiş güzergâhı ve istif alanlarında",
    mergeKey: "housekeeping",
  },
  "TRN-CHM-001": {
    code: "TRN-CHM-001",
    title: "Kimyasal Güvenliği ve Dökülmeye Müdahale",
    recommendationClass: "task_specific_practical_training",
    groupCode: "task_and_equipment",
    audiences: ["chemical_handlers"],
    topics: [
      "güvenlik bilgi formunun okunması",
      "etiketleme ve uyumluluk",
      "sızıntı ve taşma belirtileri",
      "dökülme müdahalesi",
      "kişisel korunma",
    ],
    directContext: "Kimyasal madde bulunan alanda",
    conditionalContext: "Kimyasal madde bulunan alanda",
    mergeKey: "chemical_safety",
  },
  "TRN-HOT-001": {
    code: "TRN-HOT-001",
    title: "Sıcak Çalışma ve Yangın Gözcülüğü",
    recommendationClass: "task_specific_practical_training",
    groupCode: "task_and_equipment",
    audiences: ["welders_and_hot_work_team"],
    topics: [
      "iş izni sistemi",
      "yanıcı ortamın uzaklaştırılması",
      "gaz tüplerinin güvenli kullanımı",
      "yangın gözcüsü görevi",
      "çalışma sonrası bekleme süresi",
    ],
    directContext: "Kaynak ve kesme işlerinin yürütüldüğü alanda",
    conditionalContext: "Kaynak ve kesme işleri yürütülecekse",
    mergeKey: "hot_work",
  },
  "TRN-LFT-001": {
    code: "TRN-LFT-001",
    title: "Kaldırma Operasyonu, Sapancılık ve İşaretçilik",
    recommendationClass: "task_specific_practical_training",
    groupCode: "task_and_equipment",
    audiences: ["riggers_slingers_signalers"],
    topics: [
      "yük hesabı ve sapan seçimi",
      "kanca ve mapa ön kontrolü",
      "dışlama bölgesi",
      "tek işaretçiyle iletişim",
      "askıdaki yük altında bulunmama",
    ],
    directContext: "Kaldırma operasyonu yürütülen alanda",
    conditionalContext: "Kaldırma operasyonu yürütülecekse",
    mergeKey: "lifting",
  },
  "TRN-PRC-001": {
    code: "TRN-PRC-001",
    title: "Tank ve Proses Güvenliği Farkındalığı",
    recommendationClass: "task_specific_practical_training",
    groupCode: "task_and_equipment",
    audiences: ["chemical_handlers", "maintenance_personnel"],
    topics: [
      "depolanan maddenin güvenlik bilgi formu",
      "sızıntı ve korozyon belirtileri",
      "ateşleme kaynaklarının kontrolü",
      "güvenli erişim",
      "acil durum davranışları",
    ],
    directContext: "Tank ve proses ekipmanı bulunan alanda",
    conditionalContext: "Tank ve proses ekipmanı bulunan alanda",
    secondSentence:
      "Tank içine giriş yapılacaksa kapalı alan çalışma ve kurtarma eğitimi ayrıca ele alınmalıdır.",
    mergeKey: "process_safety",
  },
  "TRN-PPE-002": {
    code: "TRN-PPE-002",
    title: "Düşüş Durdurma Sistemlerinin Uygulamalı Kullanımı",
    recommendationClass: "task_specific_practical_training",
    groupCode: "task_and_equipment",
    audiences: ["work_at_height_personnel"],
    topics: [
      "kemer ve bağlantı elemanı ön kontrolü",
      "ankraj dayanımı",
      "düşüş açıklığı hesabı",
      "askıda kalma",
      "kullanım sonrası muayene",
    ],
    directContext: "Kişisel düşüş durdurma sistemi kullanılan çalışmalarda",
    conditionalContext: "Kişisel düşüş durdurma sistemi kullanılacaksa",
    mergeKey: "fall_arrest_ppe",
  },

  // --- Equipment operator authorisation ----------------------------------
  "TRN-OPR-FORKLIFT": {
    code: "TRN-OPR-FORKLIFT",
    title: "Forklift Operatörlüğü ve Saha İçi Güvenli Kullanım",
    recommendationClass: "meb_operator_authorization",
    groupCode: "qualification_and_authorization",
    audiences: ["equipment_operators"],
    topics: [
      "yük tipi ve kapasite",
      "görüş alanı",
      "yaya yolları ve saha trafiği",
      "rampa ve manevra",
      "akü veya LPG işlemleri",
    ],
    conditionalContext: "Forklift",
    mergeKey: "operator_forklift",
  },
  "TRN-OPR-CRANE": {
    code: "TRN-OPR-CRANE",
    title: "Vinç Operatörlüğü ve Ekipmana Özgü Kullanım",
    recommendationClass: "meb_operator_authorization",
    groupCode: "qualification_and_authorization",
    audiences: ["equipment_operators"],
    topics: [
      "yük diyagramı",
      "kurulum ve zemin taşıma gücü",
      "rüzgâr ve görüş sınırları",
      "işaretçi ile iletişim",
      "günlük ön kontrol",
    ],
    conditionalContext: "Vinç",
    mergeKey: "operator_crane",
  },
  "TRN-OPR-EARTHMOVING": {
    code: "TRN-OPR-EARTHMOVING",
    title: "İş Makinesi Operatörlüğü ve Saha Uygulaması",
    recommendationClass: "meb_operator_authorization",
    groupCode: "qualification_and_authorization",
    audiences: ["equipment_operators"],
    topics: [
      "ekipman sınıfına özgü kullanım",
      "kör nokta ve yaya ayrımı",
      "zemin ve şev koşulları",
      "yeraltı hatları",
      "günlük ön kontrol",
    ],
    conditionalContext: "İş makinesi",
    mergeKey: "operator_earthmoving",
  },

  // --- Qualification verification ----------------------------------------
  "TRN-QUA-SCAFFOLD": {
    code: "TRN-QUA-SCAFFOLD",
    title: "İskele Kurulum Görevi ve Mesleki Yeterlilik",
    recommendationClass: "myk_qualification_verification",
    groupCode: "qualification_and_authorization",
    audiences: ["work_at_height_personnel"],
    topics: [],
    conditionalContext: "İskele kurma veya sökme",
    mergeKey: "qualification_scaffold",
  },

  // --- Emergency ----------------------------------------------------------
  "TRN-EMR-001": {
    code: "TRN-EMR-001",
    title: "Acil Durum ve Tahliye Farkındalığı",
    recommendationClass: "emergency_response_training",
    groupCode: "emergency_and_rescue",
    audiences: ["all_employees"],
    topics: [
      "alarm ve haberleşme",
      "tahliye güzergâhı",
      "toplanma alanı",
      "acil çıkışların açık tutulması",
      "olay bildirimi",
    ],
    conditionalContext: "Bu işyerinde",
    mergeKey: "emergency_awareness",
  },
  "TRN-EMR-008": {
    code: "TRN-EMR-008",
    title: "Yüksekte Kurtarma",
    recommendationClass: "special_regulated_role_training",
    groupCode: "emergency_and_rescue",
    audiences: ["rescue_team"],
    topics: [
      "askıda kalan çalışana erişim",
      "kurtarma ekipmanının kurulumu",
      "askıda kalma travması",
      "haberleşme",
      "tatbikatla pekiştirme",
    ],
    conditionalContext: "Yüksekte kurtarma ekibinde",
    mergeKey: "rescue_height",
  },
  "TRN-EMR-004": {
    code: "TRN-EMR-004",
    title: "İlk Yardım Farkındalığı",
    recommendationClass: "emergency_response_training",
    groupCode: "emergency_and_rescue",
    audiences: ["all_employees"],
    topics: [
      "olay yerinin güvenliği",
      "yardım çağırma",
      "temel müdahale sınırları",
      "kanamada ilk davranış",
      "sertifikalı ilk yardımcıya yönlendirme",
    ],
    conditionalContext: "Bu işyerinde",
    mergeKey: "first_aid_awareness",
  },
};

/**
 * Rules. Order matters only for readability; matching is by trigger.
 *
 * Sector baselines are deliberately thin. A photograph of a workplace supports
 * "basic OHS training is relevant here" and very little else at that level, and
 * padding the list with sector guesses buries the recommendations that came
 * from something actually visible.
 */
export const TRAINING_RULES: TrainingRule[] = [
  { entry: "TRN-GEN-002", always: true },
  { entry: "TRN-GEN-001", always: true },
  { entry: "TRN-EMR-001", always: true },

  {
    entry: "TRN-WAH-001",
    mechanisms: ["fall_from_height"],
    assuranceTopics: ["working_at_height_access"],
    directWhenPeopleVisible: true,
  },
  {
    entry: "TRN-PPE-002",
    mechanisms: ["fall_from_height"],
    directWhenPeopleVisible: true,
  },
  {
    entry: "TRN-EMR-008",
    mechanisms: ["fall_from_height"],
    specialRole: true,
  },
  {
    entry: "TRN-MAC-001",
    mechanisms: ["caught_in_pinch_shear"],
    assuranceTopics: ["machine_protective_systems", "energy_isolation_controls"],
    directWhenPeopleVisible: true,
  },
  {
    entry: "TRN-ELE-001",
    mechanisms: ["electrical_contact_arc"],
    assuranceTopics: ["electrical_internal_integrity"],
    directWhenPeopleVisible: true,
  },
  {
    entry: "TRN-HK-001",
    mechanisms: ["fall_same_level", "sharp_edge_contact"],
    directWhenPeopleVisible: true,
  },
  {
    entry: "TRN-CHM-001",
    mechanisms: ["chemical_contact_release"],
    assuranceTopics: ["chemical_identity_and_exposure"],
    directWhenPeopleVisible: true,
  },
  {
    entry: "TRN-HOT-001",
    mechanisms: ["thermal_contact"],
    assuranceTopics: ["hot_work_controls"],
    directWhenPeopleVisible: true,
  },
  {
    entry: "TRN-LFT-001",
    mechanisms: ["falling_object"],
    assuranceTopics: ["lifting_inspection"],
    equipment: ["crane"],
    directWhenPeopleVisible: true,
  },
  {
    entry: "TRN-PRC-001",
    mechanisms: ["mechanical_separation_release", "hydraulic_pneumatic_release"],
    assuranceTopics: [
      "process_containment_integrity",
      "hose_assembly_integrity",
    ],
    equipment: ["tank"],
    directWhenPeopleVisible: true,
  },

  { entry: "TRN-OPR-FORKLIFT", equipment: ["forklift"] },
  { entry: "TRN-OPR-CRANE", equipment: ["crane"] },
  { entry: "TRN-OPR-EARTHMOVING", equipment: ["earthmoving"] },
  { entry: "TRN-QUA-SCAFFOLD", equipment: ["scaffold"] },

  { entry: "TRN-EMR-004", sectors: ["construction"], always: false },
];

/**
 * Equipment families, resolved from the asset ref the analysis recorded.
 *
 * Asset refs are engine-side identifiers like "crane_01" or "scaffolding_01",
 * not model prose, so matching them is matching a code. An unrecognised ref
 * yields nothing rather than a guess: recommending forklift authorisation
 * because a word looked close enough is the exact failure this catalogue is
 * built to prevent.
 */
export const EQUIPMENT_FAMILY_PATTERNS: Array<
  { family: string; pattern: RegExp }
> = [
  { family: "forklift", pattern: /forklift|istif_?makinesi|transpalet/u },
  { family: "crane", pattern: /crane|vinc|vinç|hoist|caraskal/u },
  {
    family: "earthmoving",
    pattern: /excavator|ekskavator|loader|yukleyici|dozer|backhoe|beko/u,
  },
  { family: "scaffold", pattern: /scaffold|iskele/u },
  { family: "tank", pattern: /tank|silo|vessel|reaktor|reaktör/u },
];
