import {
  type HazardMechanismCode,
  MODULE_IDS,
  type ModuleID,
  type PhotoAnalysisV3,
} from "./contracts.ts";

export const SECTOR_PROFILE_VERSION = "sector-profile-v2";

export const SECTOR_IDS = [
  "general",
  "construction",
  "manufacturing",
  "mining",
  "energy",
  "office",
  "logistics_warehouse",
  "chemical_laboratory",
  "healthcare",
  "food_production",
  "agriculture_livestock",
  "retail",
  "municipal_field_services",
  "education",
  "hospitality",
] as const;

export type SectorID = typeof SECTOR_IDS[number];
export type TypicalHazardClass =
  | "unspecified"
  | "low"
  | "hazardous"
  | "very_hazardous"
  | "hazardous_or_very_hazardous"
  | "low_or_hazardous";

export type MandatoryModuleOutcomeStatus =
  | "actionable"
  | "checked_no_hazard"
  | "not_visible"
  | "uncertain";

export const SECTOR_CONTEXT_MODIFIER_CODES = [
  "visible_active_work",
  "maintenance_state_visible",
  "underground_production_face",
  "manned_control_area",
  "continuous_traffic_visible",
  "continuous_line_operation",
  "daily_animal_care",
] as const;
export type SectorContextModifierCode =
  typeof SECTOR_CONTEXT_MODIFIER_CODES[number];

export const SECTOR_NEGATIVE_RULE_CODES = [
  "unreadable_identity_claim",
  "photo_measurement_claim",
  "missing_document_or_qualification_claim",
  "operation_state_without_visual_cue",
  "occupancy_behavior_psychosocial_inference",
  "sector_based_severity_increase",
  "cab_occupant_ppe_claim",
  "profile_specific_negative_rule",
] as const;
export type SectorNegativeRuleCode = typeof SECTOR_NEGATIVE_RULE_CODES[number];

export type SectorCriticalEquipment = {
  familyCode: string;
  labels: { tr: string; en: string };
  aliases: string[];
  components: string[];
  checkCodes: string[];
  checkComponentAliases: Record<string, string[]>;
};

export type SectorProfileV2 = {
  sectorId: SectorID;
  labels: { tr: string; en: string };
  typicalHazardClass: TypicalHazardClass;
  mandatoryModules: ModuleID[];
  priorityModules: ModuleID[];
  criticalEquipment: SectorCriticalEquipment[];
  fatalMechanismCodes: HazardMechanismCode[];
  fatalMechanismAnchors: string[];
  frequencyPrior: {
    defaultF: number | null;
    rationale: string;
    modifiers: Array<{
      code: SectorContextModifierCode;
      f: number;
      cueGuidance: string;
    }>;
  };
  controlPreferences: string[];
  preferredControlIntents: string[];
  controlHierarchy: Array<
    "elimination" | "engineering" | "administrative" | "ppe"
  >;
  allowedControlIntents: string[];
  negativeRuleCodes: SectorNegativeRuleCode[];
  negativeRules: string[];
  assuranceScope: string[];
  regulationAnchors: string[];
};

const RELATED_EQUIPMENT_ALIASES: Record<string, string[]> = {
  tower_crane: [
    "tower crane",
    "kule vinç",
    "kule vinc",
    "tower jib",
    "vinç bomu",
  ],
  mobile_crane: [
    "mobile crane",
    "mobil vinç",
    "mobil vinc",
    "outrigger",
    "denge ayağı",
    "denge ayagi",
  ],
  overhead_crane: [
    "bridge crane",
    "crane hook",
    "vinç kancası",
    "hook block",
    "kanca bloğu",
    "wire rope",
    "çelik halat",
    "hoist",
    "caraskal",
  ],
  pressure_vessel: [
    "process vessel",
    "process_vessel",
    "vessel shell",
    "process tank",
    "process_tank",
    "proses tankı",
    "basınçlı tank",
  ],
  rotating_drive: [
    "electric motor",
    "agitator",
    "agitator drive",
    "mixer drive",
    "coupling",
    "kaplin",
    "shaft drive",
    "tahrik motoru",
  ],
};

const e = (
  familyCode: string,
  tr: string,
  en: string,
  components: string,
  checkCodes: string[],
  aliases: string[] = [],
): SectorCriticalEquipment => {
  const componentList = components.split("; ");
  return {
    familyCode,
    labels: { tr, en },
    aliases: [
      familyCode,
      tr,
      en,
      ...(RELATED_EQUIPMENT_ALIASES[familyCode] ?? []),
      ...aliases,
    ],
    components: componentList,
    checkCodes,
    checkComponentAliases: Object.fromEntries(
      checkCodes.map((code) => [
        code,
        CHECK_COMPONENT_ALIASES[code] ?? componentList,
      ]),
    ),
  };
};

const CHECK_COMPONENT_ALIASES: Record<string, string[]> = {
  machine_guard_integrity: [
    "guard",
    "machine guard",
    "muhafaza",
    "koruyucu",
    "kaplin",
    "coupling",
    "belt",
    "kayış",
    "kasnak",
    "pulley",
    "shaft",
    "mil",
    "chain",
    "zincir",
  ],
  emergency_stop_presence: [
    "emergency stop",
    "e-stop",
    "acil durdurma",
    "stop button",
    "durdurma butonu",
  ],
  nip_point_guard_integrity: [
    "nip point",
    "pinch point",
    "sıkışma noktası",
    "tambur",
    "drum",
    "pulley",
    "kasnak",
  ],
  pin_retainer_joint_integrity: [
    "hook",
    "kanca",
    "hook block",
    "kanca bloğu",
    "latch",
    "mandal",
    "pin",
    "pim",
    "retainer",
    "segman",
    "joint",
    "bağlantı",
  ],
  load_path_integrity: [
    "girder",
    "kiriş",
    "hoist",
    "caraskal",
    "wire rope",
    "halat",
    "drum",
    "tambur",
    "hook",
    "kanca",
    "hook block",
    "kanca bloğu",
    "load path",
    "yük yolu",
  ],
  pressure_relief_integrity: [
    "pressure gauge",
    "gauge",
    "manometre",
    "relief valve",
    "safety valve",
    "emniyet ventili",
    "tahliye",
    "relief line",
    "nameplate",
    "plaka",
    "anchor",
    "ankraj",
  ],
  electrical_enclosure_integrity: [
    "panel",
    "pano",
    "enclosure",
    "kapak",
    "door",
    "kilit",
    "label",
    "etiket",
  ],
  mobile_equipment_integrity: [
    "fork",
    "çatal",
    "overhead guard",
    "koruma kafesi",
    "mirror",
    "ayna",
    "wheel",
    "teker",
    "track",
    "palet",
    "chassis",
    "şasi",
    "brake",
    "fren",
  ],
  fall_arrest_anchor_presence: [
    "harness",
    "emniyet kemeri",
    "parasut tipi emniyet kemeri",
    "paraşüt tipi emniyet kemeri",
    "full body harness",
    "lanyard",
    "kanca",
    "lifeline",
    "yasam hatti",
    "yaşam hattı",
    "anchor",
    "ankraj",
    "ankraj noktasi",
    "ankraj noktası",
    "fall arrest",
    "dusme durdurma",
    "düşme durdurma",
  ],
  collective_fall_protection_presence: [
    "safety net",
    "guvenlik agi",
    "güvenlik ağı",
    "koruma agi",
    "koruma ağı",
    "net",
    "toplu koruma",
    "collective protection",
    "kapatilmis bosluk",
    "kapatılmış boşluk",
    "bosluk kapagi",
    "boşluk kapağı",
  ],
  guard_barrier_integrity: [
    "guardrail",
    "railing",
    "korkuluk",
    "top rail",
    "üst korkuluk",
    "midrail",
    "mid rail",
    "intermediate rail",
    "ara korkuluk",
    "orta korkuluk",
    "ara bariyer",
    "orta bariyer",
    "toe board",
    "kick plate",
    "etek tahtası",
    "etek sacı",
    "etek elemanı",
    "topuk levhası",
    "süpürgelik",
    "open edge",
    "açık kenar",
  ],
};

const COMMON_NEGATIVE_RULE_CODES: SectorNegativeRuleCode[] = [
  "unreadable_identity_claim",
  "photo_measurement_claim",
  "missing_document_or_qualification_claim",
  "operation_state_without_visual_cue",
  "occupancy_behavior_psychosocial_inference",
  "sector_based_severity_increase",
  "cab_occupant_ppe_claim",
  "profile_specific_negative_rule",
];

const COMMON_CONTROL_INTENTS = [
  "stop_use",
  "restrict_access",
  "isolate_energy",
  "replace_component",
  "secure_connection",
  "restore_barrier",
  "restore_hook_latch",
  "lifting_accessory_inspection",
  "reorganize_storage",
  "storage_stacking_standard",
  "clear_walkway",
  "housekeeping_program",
  "reroute_hose",
  "repair_weld",
  "ndt_inspection",
  "install_guard",
  "guard_pinch_point",
  "electrical_isolation",
  "leak_control",
  "stabilize_structure",
  "stabilize_ground",
  "ground_acceptance",
  "stabilize_slope",
  "clear_loose_material",
  "slope_acceptance",
  "engineering_inspection",
  "provide_ppe",
  "ppe_program",
];

const profile = (
  value:
    & Omit<
      SectorProfileV2,
      | "negativeRuleCodes"
      | "allowedControlIntents"
      | "controlHierarchy"
      | "preferredControlIntents"
    >
    & Partial<
      Pick<
        SectorProfileV2,
        | "negativeRuleCodes"
        | "allowedControlIntents"
        | "controlHierarchy"
        | "preferredControlIntents"
      >
    >,
): SectorProfileV2 => ({
  ...value,
  controlHierarchy: value.controlHierarchy ?? [
    "elimination",
    "engineering",
    "administrative",
    "ppe",
  ],
  negativeRuleCodes: value.negativeRuleCodes ?? COMMON_NEGATIVE_RULE_CODES,
  allowedControlIntents: value.allowedControlIntents ?? COMMON_CONTROL_INTENTS,
  preferredControlIntents: value.preferredControlIntents ?? [],
});

export const SECTOR_PROFILES: Record<SectorID, SectorProfileV2> = {
  general: profile({
    sectorId: "general",
    labels: { tr: "Genel İSG", en: "General OHS" },
    typicalHazardClass: "unspecified",
    mandatoryModules: ["egress_housekeeping", "ppe", "emergency_equipment"],
    priorityModules: [],
    criticalEquipment: [],
    fatalMechanismCodes: [],
    fatalMechanismAnchors: [],
    frequencyPrior: {
      defaultF: null,
      rationale:
        "Sektöre özel prior yoktur; yalnız görünür aktif maruziyet ayrımı kullanılır.",
      modifiers: [],
    },
    controlPreferences: [
      "Kontrolü yalnız görünür mekanizma ve ekipman ailesine göre seç.",
    ],
    negativeRules: [
      "Sahne başka bir sektöre benziyor diye o sektörün profilini uygulama.",
    ],
    assuranceScope: [],
    regulationAnchors: [],
  }),
  construction: profile({
    sectorId: "construction",
    labels: { tr: "İnşaat", en: "Construction" },
    typicalHazardClass: "very_hazardous",
    mandatoryModules: [
      "access_and_work_at_height",
      "scaffold_and_ladder",
      "excavation_slope_shoring",
      "lifting_operations",
      "mobile_equipment_traffic",
      "ppe",
    ],
    priorityModules: [
      "structural_mechanical_integrity",
      "electrical_safety",
      "egress_housekeeping",
      "hot_work_fire_explosion",
      "emergency_equipment",
    ],
    criticalEquipment: [
      e(
        "scaffold",
        "İskele",
        "Scaffold",
        "dikme tabanı/taban plakası; çapraz; ankraj; platform tahtası; ara korkuluk; süpürgelik",
        ["guard_barrier_integrity", "structural_support_integrity"],
      ),
      e(
        "edge_protection",
        "Kenar koruma",
        "Edge protection",
        "ana korkuluk; ara korkuluk; topuk levhası; bağlantı elemanı; kalıp kenarı; döşeme kenarı; döşeme boşluğu",
        ["guard_barrier_integrity"],
      ),
      // Personal and collective fall protection were missing from the profile
      // entirely. A construction photograph showing a worker at height with no
      // harness, no anchor and no net produced no finding for any of them,
      // because nothing downstream was looking for the components.
      e(
        "fall_arrest_system",
        "Düşme durdurma sistemi",
        "Fall arrest system",
        "paraşüt tipi emniyet kemeri; lanyard; ankraj noktası; yaşam hattı",
        ["fall_arrest_anchor_presence"],
      ),
      e(
        "collective_fall_protection",
        "Toplu düşme koruması",
        "Collective fall protection",
        "güvenlik ağı; kapatılmış boşluk; koruma platformu",
        ["collective_fall_protection_presence"],
      ),
      e(
        "tower_crane",
        "Kule vinç",
        "Tower crane",
        "kanca mandalı; halat; sapan/kanca gözü; karşı ağırlık; bom bağlantıları",
        ["pin_retainer_joint_integrity", "load_path_integrity"],
      ),
      e(
        "mobile_crane",
        "Mobil vinç",
        "Mobile crane",
        "kanca mandalı; halat; sapan/kanca gözü; denge ayağı; outrigger pabucu",
        ["pin_retainer_joint_integrity", "load_path_integrity"],
      ),
      e(
        "excavation",
        "Kazı",
        "Excavation",
        "şev açısı; tahkimat/iksa; kazı kenarı yükü; su birikintisi; giriş-çıkış merdiveni",
        ["slope_shoring_integrity", "edge_load_clearance"],
      ),
      e(
        "temporary_electrical",
        "Geçici elektrik",
        "Temporary electrical",
        "pano kapağı; kaçak akım rölesi; kablo ekleri; seyyar kablo güzergâhı",
        ["electrical_enclosure_integrity"],
      ),
      e(
        "concrete_pump",
        "Beton pompası",
        "Concrete pump",
        "boru kelepçesi; hortum ucu emniyeti; outrigger; boru destek",
        ["pipe_hose_connection_integrity"],
      ),
    ],
    fatalMechanismCodes: [
      "fall_from_height",
      "excavation_collapse_rockfall",
      "falling_object",
      "vehicle_equipment_strike",
      "electrical_contact_arc",
    ],
    fatalMechanismAnchors: [
      "korumasız kenardan düşme",
      "kazı göçüğü",
      "kaldırılan yük altında ezilme",
      "iş makinesi çarpması",
      "yüksekten düşen malzeme",
      "enerjili iletkene temas",
    ],
    frequencyPrior: {
      defaultF: 3,
      rationale:
        "Şantiye kadrajı çoğunlukla aktif çalışma alanıdır; vardiya sürekliliği fotoğraftan doğrulanamaz.",
      modifiers: [{
        code: "visible_active_work",
        f: 6,
        cueGuidance: "Çalışan ve yaptığı aktif iş aynı kadrajda görünür.",
      }],
    },
    controlPreferences: [
      "Kenar/boşluk kapatma",
      "Bariyerleme ve erişim kısıtlama",
      "Geçici platform veya iksa",
      "Çalışma izni",
      "KKD",
    ],
    negativeRules: [
      "İskele etiketi görünmüyorsa kontrolsüzlük iddiası kurma.",
      "Kazı derinliğini kesin ölçüyle yazma.",
      "Kabin içindeki kişi için baret bulgusu üretme.",
    ],
    assuranceScope: [
      "iskele kontrol kartı",
      "kaldırma ekipmanı periyodik muayenesi",
      "yetki belgeleri",
      "kazı statik hesabı",
      "elektrik tesisatı ölçüm raporu",
    ],
    regulationAnchors: [
      "Yapı İşlerinde İSG Yönetmeliği",
      "İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği",
      "KKD Kullanılması Hakkında Yönetmelik",
      "TS EN 13374",
      "TS EN 12811",
    ],
  }),
  manufacturing: profile({
    sectorId: "manufacturing",
    labels: { tr: "İmalat / Fabrika", en: "Manufacturing / Factory" },
    typicalHazardClass: "hazardous_or_very_hazardous",
    mandatoryModules: [
      "machine_safety_loto",
      "structural_mechanical_integrity",
      "mobile_equipment_traffic",
      "access_and_work_at_height",
      "egress_housekeeping",
      "ppe",
    ],
    priorityModules: [
      "electrical_safety",
      "storage_racking",
      "lifting_operations",
      "pressure_process_safety",
      "ergonomics",
      "hot_work_fire_explosion",
      "emergency_equipment",
    ],
    criticalEquipment: [
      e(
        "elevated_work_platform",
        "Yükseltilmiş çalışma platformu",
        "Elevated work platform",
        "üst korkuluk; ara korkuluk; etek sacı; açık kenar; platform geçişi",
        ["guard_barrier_integrity"],
        [
          "platform guardrail",
          "platform railing",
          "working platform",
          "elevated platform",
          "guardrail",
          "railing",
          "korkuluk",
          "ara korkuluk",
          "orta korkuluk",
          "midrail",
          "toe board",
          "kick plate",
          "etek sacı",
          "etek elemanı",
          "topuk levhası",
          "süpürgelik",
        ],
      ),
      e(
        "machine_press",
        "Tezgâh / pres",
        "Machine / press",
        "operasyon noktası koruyucusu; iki el kumandası; ışık perdesi; acil durdurma",
        ["machine_guard_integrity", "emergency_stop_presence"],
      ),
      e(
        "rotating_drive",
        "Dönen tahrik",
        "Rotating drive",
        "kayış-kasnak muhafazası; kaplin kapağı; açık mil; zincir-dişli",
        ["machine_guard_integrity"],
        [
          "motor",
          "electric motor",
          "agitator",
          "agitator drive",
          "mixer drive",
          "coupling",
          "kaplin",
          "shaft drive",
          "tahrik motoru",
        ],
      ),
      e(
        "conveyor",
        "Konveyör",
        "Conveyor",
        "sıkışma noktası; kuyruk tamburu; çekme halatı acil durdurma",
        ["nip_point_guard_integrity"],
      ),
      e(
        "overhead_crane",
        "Köprü vinç",
        "Overhead crane",
        "kanca mandalı; halat; kanca gözü; limit switch; kumanda askısı",
        ["pin_retainer_joint_integrity", "load_path_integrity"],
        [
          "bridge crane",
          "köprü vinç",
          "kopru vinc",
          "hook block",
          "kanca bloğu",
          "crane hook",
          "vinç kancası",
          "wire rope",
          "çelik halat",
          "hoist",
          "caraskal",
        ],
      ),
      e(
        "forklift",
        "Forklift",
        "Forklift",
        "çatal; koruma kafesi; ayna; ikaz sesi/ışığı; park pozisyonu",
        ["mobile_equipment_integrity"],
      ),
      e(
        "electrical_panel",
        "Elektrik panosu",
        "Electrical panel",
        "kapak; kilit; IP bütünlüğü; etiket; ön serbest alan",
        ["electrical_enclosure_integrity"],
      ),
      e(
        "pressure_vessel",
        "Basınçlı kap",
        "Pressure vessel",
        "manometre; emniyet ventili; tahliye hattı; plaka; ankraj",
        ["pressure_relief_integrity"],
        [
          "process vessel",
          "process_vessel",
          "vessel shell",
          "process tank",
          "process_tank",
          "tank",
          "proses tankı",
          "basınçlı tank",
        ],
      ),
    ],
    fatalMechanismCodes: [
      "fall_from_height",
      "caught_in_pinch_shear",
      "mechanical_separation_release",
      "falling_object",
      "vehicle_equipment_strike",
      "fire_explosion",
      "electrical_contact_arc",
    ],
    fatalMechanismAnchors: [
      "yükseltilmiş platformdan düşme",
      "makineye yakalanma",
      "izolasyonsuz bakımda beklenmedik çalışma",
      "asılı yük düşmesi",
      "forklift ezmesi",
      "basınçlı kap patlaması",
      "elektrik çarpması veya ark",
    ],
    frequencyPrior: {
      defaultF: 6,
      rationale: "Üretim alanı günlük maruziyet için başlangıç priorı sağlar.",
      modifiers: [{
        code: "maintenance_state_visible",
        f: 2,
        cueGuidance: "Makinenin duruş/bakım durumu fiziksel olarak görünür.",
      }],
    },
    controlPreferences: [
      "Sabit muhafaza",
      "Enterloklu muhafaza",
      "Işık perdesi veya iki el kumandası",
      "LOTO",
      "İşaretleme",
      "KKD",
    ],
    preferredControlIntents: [
      "install_guard",
      "restore_barrier",
      "guard_pinch_point",
      "isolate_energy",
      "engineering_inspection",
      "provide_ppe",
    ],
    negativeRules: [
      "CE veya uygunluk durumunu fotoğraftan iddia etme.",
      "dB değeri tahmin etme.",
      "Görünür enerji kaynağı/kilit noktası olmadan LOTO yokluğu iddia etme.",
    ],
    assuranceScope: [
      "vinç ve basınçlı ekipman periyodik kontrolleri",
      "LOTO prosedürü",
      "gürültü/toz ölçümleri",
      "operatör yetki belgeleri",
    ],
    regulationAnchors: [
      "İş Ekipmanları Yönetmeliği",
      "Makine Emniyeti Yönetmeliği",
      "Gürültü Yönetmeliği",
      "TS EN ISO 14120",
      "TS EN ISO 13857",
      "TS EN ISO 13850",
    ],
  }),
  mining: profile({
    sectorId: "mining",
    labels: { tr: "Maden", en: "Mining" },
    typicalHazardClass: "very_hazardous",
    mandatoryModules: [
      "excavation_slope_shoring",
      "mobile_equipment_traffic",
      "structural_mechanical_integrity",
      "emergency_equipment",
      "ppe",
    ],
    priorityModules: [
      "hot_work_fire_explosion",
      "electrical_safety",
      "lifting_operations",
      "environmental_release_leak",
      "egress_housekeeping",
    ],
    criticalEquipment: [
      e(
        "ground_support",
        "Tahkimat",
        "Ground support",
        "bağ/direk aralığı; deformasyon; ayak tahkimatı; tavan cıvatası plakası",
        ["ground_support_integrity"],
      ),
      e(
        "mine_slope",
        "Şev / basamak",
        "Mine slope / bench",
        "basamak geometrisi; gevşek blok; çatlak; drenaj; şev topuğu yükü",
        ["slope_shoring_integrity"],
      ),
      e(
        "mine_conveyor",
        "Nakliyat",
        "Mine haulage",
        "bant sıkışma noktası; kuyruk tamburu; acil durdurma; bant hizası",
        ["nip_point_guard_integrity"],
      ),
      e(
        "heavy_mobile_equipment",
        "Ağır ekipman",
        "Heavy mobile equipment",
        "geri ikazı; ayna/kamera; kör nokta; lastik; ROPS/FOPS kabin",
        ["mobile_equipment_integrity"],
      ),
      e(
        "mine_ventilation",
        "Havalandırma",
        "Mine ventilation",
        "vantüp; hava perdesi; kapı/regülatör",
        ["ventilation_path_integrity"],
      ),
      e(
        "mine_electrical",
        "Elektrik",
        "Mine electrical",
        "Ex armatür; kablo askısı; pano bütünlüğü",
        ["electrical_enclosure_integrity"],
      ),
    ],
    fatalMechanismCodes: [
      "excavation_collapse_rockfall",
      "fire_explosion",
      "vehicle_equipment_strike",
      "caught_in_pinch_shear",
      "environmental_release",
    ],
    fatalMechanismAnchors: [
      "göçük",
      "kaya düşmesi",
      "grizu/toz patlaması",
      "ağır ekipman ezmesi",
      "nakliyatta yakalanma",
      "su baskını",
      "havasız ortam",
    ],
    frequencyPrior: {
      defaultF: 6,
      rationale: "Maden üretim alanı günlük maruziyet priorı sağlar.",
      modifiers: [{
        code: "underground_production_face",
        f: 10,
        cueGuidance:
          "Yeraltı üretim aynası ve üretim faaliyeti birlikte görünür.",
      }],
    },
    controlPreferences: [
      "Tahliye ve erişim yasağı",
      "Tahkimat veya şev düzeltme",
      "Gaz/toz ölçümü ve havalandırma",
      "Trafik ayrımı",
      "İzinli çalışma",
      "KKD",
    ],
    negativeRules: [
      "Gaz veya toz konsantrasyonu iddia etme.",
      "Tahkimatı statik hesap gibi değerlendirme.",
      "Sektöre dayanarak otomatik S=100 verme.",
    ],
    assuranceScope: [
      "gaz ölçümleri",
      "tahkimat projesi",
      "patlatma planı",
      "kurtarma ve tatbikat kayıtları",
      "havalandırma ölçümü",
    ],
    regulationAnchors: [
      "Maden İşyerlerinde İSG Yönetmeliği",
      "Tozla Mücadele Yönetmeliği",
      "Patlayıcı Ortamlar Yönetmeliği",
    ],
  }),
  energy: profile({
    sectorId: "energy",
    labels: { tr: "Enerji", en: "Energy" },
    typicalHazardClass: "hazardous_or_very_hazardous",
    mandatoryModules: [
      "electrical_safety",
      "machine_safety_loto",
      "access_and_work_at_height",
      "emergency_equipment",
      "ppe",
    ],
    priorityModules: [
      "structural_mechanical_integrity",
      "hot_work_fire_explosion",
      "pressure_process_safety",
      "lifting_operations",
      "egress_housekeeping",
    ],
    criticalEquipment: [
      e(
        "switchboard",
        "OG/AG panosu",
        "MV/LV switchboard",
        "kapak; kilit; kilit dili; IP contası; uyarı; ön serbest alan",
        ["electrical_enclosure_integrity"],
      ),
      e(
        "transformer",
        "Trafo",
        "Transformer",
        "bariyer/çit; kapı kilidi; topraklama iletkeni; yağ havuzu; mesafe levhası",
        ["electrical_isolation_barrier"],
      ),
      e(
        "generator",
        "Jeneratör",
        "Generator",
        "egzoz yönü; yakıt hattı; akü bağlantısı; susturucu; kabin kapağı",
        ["fuel_line_integrity"],
      ),
      e(
        "switchyard",
        "Şalt sahası",
        "Switchyard",
        "çit; kapı kilidi; emniyet mesafesi; ayırıcı; topraklama seti",
        ["electrical_isolation_barrier"],
      ),
      e(
        "battery_room",
        "Akü odası",
        "Battery room",
        "havalandırma; göz duşu; nötrleyici; kıvılcım kaynağı",
        ["ventilation_path_integrity"],
      ),
      e(
        "renewable_generation",
        "PV / rüzgâr",
        "PV / wind",
        "DC kablo; konnektör; yaşam hattı; tırmanma sistemi; kilitli kapak",
        ["electrical_enclosure_integrity", "fall_arrest_anchor_presence"],
      ),
    ],
    fatalMechanismCodes: [
      "electrical_contact_arc",
      "fall_from_height",
      "fire_explosion",
      "environmental_release",
    ],
    fatalMechanismAnchors: [
      "enerjili iletkene temas",
      "ark patlaması",
      "geri besleme",
      "yüksekten düşme",
      "egzoz/gaz birikimi",
    ],
    frequencyPrior: {
      defaultF: 2,
      rationale: "Enerji tesisindeki çoğu saha sürekli insanlı değildir.",
      modifiers: [{
        code: "manned_control_area",
        f: 6,
        cueGuidance:
          "İnsanlı operatör kabini veya kontrol alanı ve kullanım cue'su görünür.",
      }],
    },
    controlPreferences: [
      "Enerjiyi kes",
      "Kesme noktasını kilitle/etiketle",
      "Gerilim yokluğunu doğrula",
      "Toprakla ve kısa devre et",
      "Komşu enerjili bölümü bariyerle",
    ],
    negativeRules: [
      "Gerilim seviyesini kesin belirleme.",
      "Topraklama ölçüm değeri veya ark enerjisi iddia etme.",
    ],
    assuranceScope: [
      "topraklama ölçümü",
      "arc flash çalışması",
      "yetkilendirme",
      "LOTO envanteri",
      "termal kamera raporu",
    ],
    regulationAnchors: [
      "Elektrik Kuvvetli Akım Tesisleri Yönetmeliği",
      "Elektrik Tesislerinde Topraklamalar Yönetmeliği",
      "İş Ekipmanları Yönetmeliği",
    ],
  }),
  office: profile({
    sectorId: "office",
    labels: { tr: "Ofis", en: "Office" },
    typicalHazardClass: "low",
    mandatoryModules: [
      "egress_housekeeping",
      "emergency_equipment",
      "ergonomics",
      "electrical_safety",
    ],
    priorityModules: [
      "storage_racking",
      "structural_mechanical_integrity",
      "ppe",
    ],
    criticalEquipment: [
      e(
        "workstation",
        "Çalışma istasyonu",
        "Workstation",
        "ekran; klavye; koltuk desteği; ayak desteği; kablo yönetimi",
        ["ergonomic_setup_integrity"],
      ),
      e(
        "egress_route",
        "Kaçış yolu",
        "Egress route",
        "koridor; kapı önü; yönlendirme armatürü; kilit",
        ["egress_path_clearance"],
      ),
      e(
        "fire_equipment",
        "Yangın ekipmanı",
        "Fire equipment",
        "söndürücü; dolap önü; işaretleme; basınç göstergesi",
        ["emergency_equipment_access"],
      ),
      e(
        "office_storage",
        "Dolap / raf",
        "Cabinet / shelving",
        "devrilme sabitlemesi; üst raf; ağırlık dağılımı",
        ["storage_stability_integrity"],
      ),
      e(
        "office_electrical",
        "Elektrik",
        "Office electrical",
        "çoklu priz; hasarlı kablo; zemin kablosu; pano erişimi",
        ["electrical_enclosure_integrity"],
      ),
    ],
    fatalMechanismCodes: [
      "fire_explosion",
      "structural_collapse",
      "fall_from_height",
    ],
    fatalMechanismAnchors: [
      "yangında tıkalı kaçış",
      "ağır dolap devrilmesi",
      "merdivenden düşme",
    ],
    frequencyPrior: {
      defaultF: 6,
      rationale: "Ofis alanı günlük kullanılır.",
      modifiers: [],
    },
    controlPreferences: [
      "Fiziksel düzenleme",
      "Kablo kanalı",
      "Dolap sabitleme",
      "Kaçış yolunu açma",
      "İstasyon ayarı",
    ],
    negativeRules: [
      "Psikososyal durum çıkarma.",
      "Lux değeri tahmin etme.",
      "Ergonomiye ölümcül/kalıcı sonuç atama.",
    ],
    assuranceScope: [
      "tahliye planı ve tatbikat",
      "elektrik kontrolü",
      "göz muayenesi",
      "aydınlatma ölçümü",
    ],
    regulationAnchors: [
      "İşyeri Bina ve Eklentileri Yönetmeliği",
      "Ekranlı Araçlarla Çalışma Yönetmeliği",
      "Binaların Yangından Korunması Yönetmeliği",
    ],
  }),
  logistics_warehouse: profile({
    sectorId: "logistics_warehouse",
    labels: { tr: "Depo / Lojistik", en: "Warehouse / Logistics" },
    typicalHazardClass: "hazardous",
    mandatoryModules: [
      "mobile_equipment_traffic",
      "storage_racking",
      "egress_housekeeping",
      "emergency_equipment",
    ],
    priorityModules: [
      "lifting_operations",
      "structural_mechanical_integrity",
      "ergonomics",
      "electrical_safety",
      "ppe",
    ],
    criticalEquipment: [
      e(
        "racking_system",
        "Raf sistemi",
        "Racking system",
        "raf ayağı; çapraz; kiriş emniyet pimi; taban plakası; yük etiketi",
        ["racking_frame_integrity", "beam_locking_pin_presence"],
      ),
      e(
        "forklift",
        "Forklift",
        "Forklift",
        "çatal; koruma kafesi; zincir; park pozisyonu; şarj alanı",
        ["mobile_equipment_integrity"],
      ),
      e(
        "pedestrian_vehicle_separation",
        "Yaya-araç ayrımı",
        "Pedestrian-vehicle separation",
        "zemin çizgisi; bariyer; ayna; kör nokta; geçiş; hız kesici",
        ["pedestrian_segregation_integrity"],
      ),
      e(
        "loading_dock",
        "Yükleme rampası",
        "Loading dock",
        "kenar koruma; dok tamponu; takoz; seviye platformu",
        ["dock_edge_protection"],
      ),
      e(
        "stacked_load",
        "İstif",
        "Stacked load",
        "yük yüksekliği; palet; sarkma; devrilme; streç",
        ["storage_stability_integrity"],
      ),
    ],
    fatalMechanismCodes: [
      "vehicle_equipment_strike",
      "structural_collapse",
      "falling_object",
      "fall_from_height",
      "equipment_overturn",
    ],
    fatalMechanismAnchors: [
      "forklift-yaya çarpışması",
      "raf çökmesi",
      "palet/yük düşmesi",
      "rampadan düşme",
      "forklift devrilmesi",
    ],
    frequencyPrior: {
      defaultF: 6,
      rationale: "Depo faaliyeti günlük maruziyet priorı sağlar.",
      modifiers: [{
        code: "continuous_traffic_visible",
        f: 10,
        cueGuidance: "Aktif sevkiyat veya araç trafiği görünür.",
      }],
    },
    controlPreferences: [
      "Yaya yolunu fiziksel ayır",
      "Ayna veya sensör",
      "Hasarlı rafı boşalt",
      "Yük/istif sınırı",
      "Trafik planı",
      "KKD",
    ],
    negativeRules: [
      "Raf kapasitesi veya yük ağırlığı hesaplama.",
      "Operatör yetkisi çıkarma.",
    ],
    assuranceScope: [
      "raf muayenesi",
      "forklift periyodik kontrolü",
      "operatör belgesi",
      "trafik planı",
      "kapasite etiketi doğruluğu",
    ],
    regulationAnchors: [
      "İş Ekipmanları Yönetmeliği",
      "İşyeri Bina ve Eklentileri Yönetmeliği",
      "Elle Taşıma Yönetmeliği",
      "TS EN 15635",
    ],
  }),
  chemical_laboratory: profile({
    sectorId: "chemical_laboratory",
    labels: { tr: "Kimya / Laboratuvar", en: "Chemical / Laboratory" },
    typicalHazardClass: "very_hazardous",
    mandatoryModules: [
      "chemical_risk",
      "environmental_release_leak",
      "emergency_equipment",
      "ppe",
      "pressure_process_safety",
    ],
    priorityModules: [
      "pipe_hose_connections",
      "hot_work_fire_explosion",
      "electrical_safety",
      "egress_housekeeping",
      "machine_safety_loto",
    ],
    criticalEquipment: [
      e(
        "chemical_storage",
        "Kimyasal depolama",
        "Chemical storage",
        "etiket; uyumsuz madde yakınlığı; ikincil tutma; raf; kapak",
        ["chemical_segregation_integrity", "secondary_containment_presence"],
      ),
      e(
        "fume_hood",
        "Çeker ocak",
        "Fume hood",
        "ön cam; hava akış göstergesi; iç düzen; priz",
        ["ventilation_path_integrity"],
      ),
      e(
        "emergency_equipment",
        "Acil ekipman",
        "Emergency equipment",
        "göz/vücut duşu; işaretleme; test etiketi; erişim",
        ["emergency_equipment_access"],
      ),
      e(
        "gas_cylinder",
        "Gaz tüpü",
        "Gas cylinder",
        "sabitleme; dik konum; kapak; regülatör; hortum",
        ["cylinder_restraint_integrity"],
      ),
      e(
        "process_line",
        "Proses hattı",
        "Process line",
        "flanş; conta; korozyon; hortum kelepçesi; etiket; tahliye",
        ["pipe_hose_connection_integrity"],
      ),
      e(
        "pressure_reactor",
        "Basınçlı kap/reaktör",
        "Pressure vessel/reactor",
        "manometre; emniyet ventili; patlama diski; tahliye; ankraj; seviye",
        ["pressure_relief_integrity"],
      ),
    ],
    fatalMechanismCodes: [
      "chemical_contact_release",
      "fire_explosion",
      "environmental_release",
    ],
    fatalMechanismAnchors: [
      "uyumsuz kimyasal reaksiyonu",
      "basınçlı kap patlaması",
      "parlayıcı buhar tutuşması",
      "korozif yanık",
      "oksijen yetersizliği",
    ],
    frequencyPrior: {
      defaultF: 3,
      rationale:
        "Laboratuvar/depo kadrajı tek başına sürekli maruziyet göstermez.",
      modifiers: [{
        code: "visible_active_work",
        f: 6,
        cueGuidance: "Kimyasalla aktif çalışma ve kişi/iş ilişkisi görünür.",
      }],
    },
    controlPreferences: [
      "Ayır veya ikame et",
      "Kapalı sistem ve lokal havalandırma",
      "İkincil tutma",
      "Etiket/SDS",
      "Miktar sınırlama",
      "KKD",
    ],
    negativeRules: [
      "Okunamayan etiketten kimlik, konsantrasyon veya sınıf çıkarma.",
      "ppm veya mg/m³ yazma.",
      "Renkten madde tahmin etme.",
      "İki kimlik görünmeden uyumsuz depolama iddia etme.",
    ],
    assuranceScope: [
      "SDS envanteri",
      "maruziyet ölçümü",
      "çeker ocak hava hızı",
      "duş testi",
      "basınçlı kap muayenesi",
      "ATEX dokümanı",
    ],
    regulationAnchors: [
      "Kimyasal Maddelerle Çalışma Yönetmeliği",
      "Kanserojen veya Mutajen Maddeler Yönetmeliği",
      "Patlayıcı Ortamlar Yönetmeliği",
      "SEA Yönetmeliği",
      "İş Ekipmanları Yönetmeliği",
    ],
  }),
  healthcare: profile({
    sectorId: "healthcare",
    labels: { tr: "Sağlık / Hastane", en: "Healthcare / Hospital" },
    typicalHazardClass: "hazardous_or_very_hazardous",
    mandatoryModules: [
      "egress_housekeeping",
      "emergency_equipment",
      "ergonomics",
      "chemical_risk",
    ],
    priorityModules: [
      "electrical_safety",
      "environmental_release_leak",
      "storage_racking",
      "ppe",
      "pressure_process_safety",
    ],
    criticalEquipment: [
      e(
        "medical_waste_station",
        "Atık istasyonu",
        "Medical waste station",
        "atık kabı; kesici kabı doluluk çizgisi; kapak; ayrım",
        ["waste_segregation_integrity"],
      ),
      e(
        "medical_gas",
        "Medikal gaz",
        "Medical gas",
        "tüp sabitleme; regülatör; hortum; oksijen ayrımı; uyarı",
        ["cylinder_restraint_integrity"],
      ),
      e(
        "patient_transfer",
        "Hasta transfer",
        "Patient transfer",
        "lift/transfer ekipmanı; yatak freni; koridor",
        ["ergonomic_transfer_support"],
      ),
      e(
        "clinical_egress",
        "Zemin/geçiş",
        "Clinical egress",
        "ıslak zemin; kablo; kapı önü; sedye güzergâhı",
        ["egress_path_clearance"],
      ),
      e(
        "disinfectant_station",
        "Dezenfektan",
        "Disinfectant",
        "etiket; kapalı kap; havalandırma; göz duşu",
        ["chemical_segregation_integrity"],
      ),
      e(
        "clinical_electrical",
        "Elektrik",
        "Clinical electrical",
        "çoklu priz; yatak çevresi kablo; UPS/jeneratör erişimi",
        ["electrical_enclosure_integrity"],
      ),
    ],
    fatalMechanismCodes: [
      "fire_explosion",
      "structural_collapse",
      "electrical_contact_arc",
      "mechanical_separation_release",
    ],
    fatalMechanismAnchors: [
      "tahliyesi güç hastada kaçış engeli",
      "oksijen zengin ortamda yangın",
      "gaz tüpü regülatör kırılması",
      "elektrik çarpması",
    ],
    frequencyPrior: {
      defaultF: 10,
      rationale: "Klinik alanlar 7/24 kullanılır.",
      modifiers: [],
    },
    controlPreferences: [
      "Kesici kabını doğru konuma al",
      "Atığı fiziksel ayır",
      "Transfer ekipmanı",
      "Kaçış yolunu aç",
      "İşaretleme",
      "KKD",
    ],
    negativeRules: [
      "Enfeksiyon veya biyolojik etken sınıfı iddia etme.",
      "Hasta mahremiyeti çıkarımı yapma.",
      "Sterilizasyon yeterliliği değerlendirme.",
    ],
    assuranceScope: [
      "atık planı",
      "biyolojik risk değerlendirmesi",
      "medikal gaz kontrolü",
      "tahliye planı/tatbikatı",
      "bağışıklama kayıtları",
    ],
    regulationAnchors: [
      "Biyolojik Etkenler Yönetmeliği",
      "Tıbbi Atıkların Kontrolü Yönetmeliği",
      "Hasta ve Çalışan Güvenliği Yönetmeliği",
      "Binaların Yangından Korunması Yönetmeliği",
    ],
  }),
  food_production: profile({
    sectorId: "food_production",
    labels: { tr: "Gıda Üretimi", en: "Food Production" },
    typicalHazardClass: "hazardous",
    mandatoryModules: [
      "machine_safety_loto",
      "egress_housekeeping",
      "chemical_risk",
      "ergonomics",
    ],
    priorityModules: [
      "structural_mechanical_integrity",
      "electrical_safety",
      "pressure_process_safety",
      "mobile_equipment_traffic",
      "emergency_equipment",
      "ppe",
    ],
    criticalEquipment: [
      e(
        "food_cutting_machine",
        "Kesme/doğrama",
        "Cutting machine",
        "bıçak muhafazası; itici; acil durdurma; besleme ağzı",
        ["machine_guard_integrity"],
      ),
      e(
        "food_mixer",
        "Karıştırıcı/hamur",
        "Mixer/kneader",
        "kapak enterloku; palet koruyucu; kazan ağzı",
        ["machine_guard_integrity"],
      ),
      e(
        "food_conveyor",
        "Konveyör/dolum",
        "Conveyor/filling",
        "sıkışma noktası; koruyucu; temizlik izolasyonu",
        ["nip_point_guard_integrity"],
      ),
      e(
        "steam_hot_line",
        "Buhar/sıcak hat",
        "Steam/hot line",
        "yalıtım; kondenstop; vana etiketi; sıcak yüzey uyarısı",
        ["hot_surface_protection"],
      ),
      e(
        "cold_room",
        "Soğuk oda",
        "Cold room",
        "iç açma mandalı; alarm; buzlanma; kapı contası",
        ["cold_room_egress_integrity"],
      ),
      e(
        "cip_cleaning",
        "CIP / temizlik",
        "CIP / cleaning",
        "kimyasal etiket; dozaj pompası; hortum; göz duşu; ayrık depolama",
        ["chemical_segregation_integrity"],
      ),
      e(
        "food_floor",
        "Zemin",
        "Food production floor",
        "ıslaklık; kaymaz yüzey; drenaj; eğim",
        ["slip_surface_integrity"],
      ),
    ],
    fatalMechanismCodes: [
      "caught_in_pinch_shear",
      "thermal_contact",
      "environmental_release",
      "fire_explosion",
    ],
    fatalMechanismAnchors: [
      "temizlikte makineye yakalanma",
      "buhar/sıcak sıvı",
      "soğuk odada mahsur kalma",
      "soğutucu sızıntısı",
      "tank/siloda boğulma",
    ],
    frequencyPrior: {
      defaultF: 6,
      rationale: "Üretim alanı günlük maruziyet priorı sağlar.",
      modifiers: [{
        code: "continuous_line_operation",
        f: 10,
        cueGuidance:
          "Çalışır üretim hattı ve sürekli besleme/çıkış hareketi görünür.",
      }],
    },
    controlPreferences: [
      "Yıkanabilir mühendislik kontrolü",
      "Enterlok",
      "Kaymaz zemin/drenaj",
      "Sıcak yüzey yalıtımı",
      "Soğuk oda iç açma/alarm",
      "İkame",
      "KKD",
    ],
    negativeRules: [
      "HACCP veya ürün güvenliği bulgusu üretme.",
      "Soğutucu gaz türü iddia etme.",
      "Sürtünme katsayısı yazma.",
    ],
    assuranceScope: [
      "LOTO ve temizlik talimatı",
      "soğutma acil planı",
      "kapalı alan izni",
      "kazan periyodik kontrolü",
    ],
    regulationAnchors: [
      "İş Ekipmanları Yönetmeliği",
      "Makine Emniyeti Yönetmeliği",
      "Kimyasal Maddelerle Çalışma Yönetmeliği",
      "İşyeri Bina ve Eklentileri Yönetmeliği",
    ],
  }),
  agriculture_livestock: profile({
    sectorId: "agriculture_livestock",
    labels: { tr: "Tarım / Hayvancılık", en: "Agriculture / Livestock" },
    typicalHazardClass: "low_or_hazardous",
    mandatoryModules: [
      "mobile_equipment_traffic",
      "machine_safety_loto",
      "chemical_risk",
      "ppe",
    ],
    priorityModules: [
      "structural_mechanical_integrity",
      "access_and_work_at_height",
      "electrical_safety",
      "hot_work_fire_explosion",
      "ergonomics",
      "emergency_equipment",
    ],
    criticalEquipment: [
      e(
        "tractor",
        "Traktör",
        "Tractor",
        "ROPS; emniyet kemeri; PTO muhafazası; el freni; basamak",
        ["rollover_protection_presence", "pto_guard_integrity"],
      ),
      e(
        "pto_shaft",
        "PTO / kuyruk mili",
        "PTO shaft",
        "teleskopik kılıf; zincir; bağlantı pimi",
        ["pto_guard_integrity"],
      ),
      e(
        "harvester_baler",
        "Balya / hasat makinesi",
        "Baler / harvester",
        "besleme ağzı; acil durdurma; bıçak muhafazası",
        ["machine_guard_integrity"],
      ),
      e(
        "farm_silo",
        "Silo / yem deposu",
        "Silo / feed store",
        "giriş kapağı; düşme boşluğu; merdiven; kilit",
        ["confined_space_access_control"],
      ),
      e(
        "animal_handling_area",
        "Hayvan alanı",
        "Animal handling area",
        "kaçış yolu; bariyer; kapı yönü; zemin; sıkışma noktası",
        ["animal_handling_barrier_integrity"],
      ),
      e(
        "pesticide_store",
        "Pestisit deposu",
        "Pesticide store",
        "kilit; etiket; havalandırma; ayrık depolama; karışım alanı",
        ["chemical_segregation_integrity"],
      ),
    ],
    fatalMechanismCodes: [
      "equipment_overturn",
      "caught_in_pinch_shear",
      "environmental_release",
      "vehicle_equipment_strike",
    ],
    fatalMechanismAnchors: [
      "traktör devrilmesi",
      "PTO'ya sarılma",
      "hasat makinesinde yakalanma",
      "siloda boğulma",
      "hayvan ezmesi",
      "gübre çukuru gazı",
    ],
    frequencyPrior: {
      defaultF: 3,
      rationale: "Tarımsal faaliyet mevsimlik ve değişkendir.",
      modifiers: [{
        code: "daily_animal_care",
        f: 6,
        cueGuidance: "Hayvan bakım alanı ve aktif bakım ilişkisi görünür.",
      }],
    },
    controlPreferences: [
      "ROPS ve kemer",
      "PTO kılıfı",
      "Besleme ağzı koruyucusu",
      "Hayvan bariyeri ve kaçış",
      "Kilitli pestisit deposu",
      "KKD",
    ],
    negativeRules: [
      "Pestisit türü veya bekleme süresi iddia etme.",
      "Zoonoz varsayma.",
      "Tek kişi görünmesinden yalnız çalışma çıkarma.",
    ],
    assuranceScope: [
      "ekipman periyodik kontrolü",
      "pestisit kayıtları",
      "zoonoz programı",
      "yalnız çalışma prosedürü",
    ],
    regulationAnchors: [
      "İş Ekipmanları Yönetmeliği",
      "Kimyasal Maddelerle Çalışma Yönetmeliği",
      "Biyolojik Etkenler Yönetmeliği",
      "Bitki Koruma Ürünleri Yönetmeliği",
    ],
  }),
  retail: profile({
    sectorId: "retail",
    labels: { tr: "Perakende / Mağaza", en: "Retail / Store" },
    typicalHazardClass: "low",
    mandatoryModules: [
      "egress_housekeeping",
      "storage_racking",
      "emergency_equipment",
    ],
    priorityModules: [
      "ergonomics",
      "electrical_safety",
      "access_and_work_at_height",
      "mobile_equipment_traffic",
      "structural_mechanical_integrity",
    ],
    criticalEquipment: [
      e(
        "display_shelving",
        "Teşhir rafı",
        "Display shelving",
        "sabitleme; üst raf ağırlığı; devrilme; köşe koruma",
        ["storage_stability_integrity"],
      ),
      e(
        "retail_egress",
        "Kaçış yolu",
        "Retail egress",
        "koridor; kapı önü; acil çıkış kilidi; yönlendirme",
        ["egress_path_clearance"],
      ),
      e(
        "step_ladder",
        "Merdiven/basamak",
        "Step ladder",
        "kaymaz ayak; kilit; yükseklik; kullanım konumu",
        ["ladder_stability_integrity"],
      ),
      e(
        "back_store",
        "Depo arkası",
        "Back store",
        "istif; transpalet; geçiş; aydınlatma",
        ["storage_stability_integrity"],
      ),
      e(
        "retail_electrical",
        "Elektrik",
        "Retail electrical",
        "çoklu priz; kablo; armatür; kasa çevresi",
        ["electrical_enclosure_integrity"],
      ),
      e(
        "retail_floor",
        "Zemin",
        "Retail floor",
        "ıslaklık; uyarı; halı kenarı; seviye farkı",
        ["slip_surface_integrity"],
      ),
    ],
    fatalMechanismCodes: [
      "fire_explosion",
      "structural_collapse",
      "falling_object",
    ],
    fatalMechanismAnchors: [
      "yangında tıkalı çıkış",
      "teşhir ünitesi devrilmesi",
      "yüksek istiften ağır ürün düşmesi",
    ],
    frequencyPrior: {
      defaultF: 6,
      rationale: "Mağaza alanı günlük kullanılır.",
      modifiers: [],
    },
    controlPreferences: [
      "Rafı sabitle",
      "Ağır ürünü aşağı al",
      "Kaçış yolunu aç",
      "Uygun merdiven",
      "Islak zemin kontrolü",
    ],
    negativeRules: [
      "Müşteri yoğunluğu çıkarma.",
      "Ürün ağırlığını kesin yazma.",
      "Görünmeyen çalışma süresinden ergonomi çıkarma.",
    ],
    assuranceScope: [
      "tahliye planı",
      "raf sabitleme uygunluğu",
      "elektrik kontrolü",
      "elle taşıma eğitimi",
    ],
    regulationAnchors: [
      "İşyeri Bina ve Eklentileri Yönetmeliği",
      "Binaların Yangından Korunması Yönetmeliği",
      "Elle Taşıma Yönetmeliği",
      "İş Ekipmanları Yönetmeliği",
    ],
  }),
  municipal_field_services: profile({
    sectorId: "municipal_field_services",
    labels: {
      tr: "Belediye / Kamu Saha İşleri",
      en: "Municipal / Public Field Services",
    },
    typicalHazardClass: "hazardous",
    mandatoryModules: [
      "mobile_equipment_traffic",
      "excavation_slope_shoring",
      "ppe",
      "egress_housekeeping",
    ],
    priorityModules: [
      "lifting_operations",
      "electrical_safety",
      "access_and_work_at_height",
      "environmental_release_leak",
      "structural_mechanical_integrity",
      "emergency_equipment",
    ],
    criticalEquipment: [
      e(
        "traffic_control_zone",
        "Trafik güvenliği",
        "Traffic control zone",
        "koni/delineatör; ön uyarı; levha; ikaz lambası; geçiş",
        ["traffic_control_zone_integrity"],
      ),
      e(
        "utility_excavation",
        "Kazı (altyapı)",
        "Utility excavation",
        "şev/iksa; kenar yükü; geçiş köprüsü; aydınlatma; bariyer",
        ["slope_shoring_integrity", "public_barrier_continuity"],
      ),
      e(
        "manhole_confined_space",
        "Rögar/kapalı alan",
        "Manhole/confined space",
        "kapak; üçayak/vinç; gaz ölçer; fan; giriş bariyeri",
        ["confined_space_access_control"],
      ),
      e(
        "refuse_vehicle",
        "Çöp toplama aracı",
        "Refuse collection vehicle",
        "sıkıştırma koruyucusu; basamak; geri ikazı; ayna",
        ["mobile_equipment_integrity"],
      ),
      e(
        "aerial_platform_vehicle",
        "Sepetli araç",
        "Aerial platform vehicle",
        "outrigger; sepet korkuluğu; ankraj; enerji hattı mesafesi",
        ["fall_arrest_anchor_presence"],
      ),
      e(
        "tree_work",
        "Ağaç/budama",
        "Tree work",
        "testere muhafazası; düşme bölgesi bariyeri; yaşam hattı",
        ["machine_guard_integrity"],
      ),
    ],
    fatalMechanismCodes: [
      "vehicle_equipment_strike",
      "excavation_collapse_rockfall",
      "environmental_release",
      "fall_from_height",
      "electrical_contact_arc",
      "caught_in_pinch_shear",
    ],
    fatalMechanismAnchors: [
      "trafikte çarpılma",
      "kazı göçüğü",
      "kapalı alanda zehirlenme/oksijensizlik",
      "sepetten düşme",
      "enerji hattı teması",
      "sıkıştırma haznesine kapılma",
      "üçüncü kişinin alana düşmesi",
    ],
    frequencyPrior: {
      defaultF: 3,
      rationale: "Saha ekipleri iş bazlı çalışır.",
      modifiers: [{
        code: "visible_active_work",
        f: 6,
        cueGuidance: "Aktif trafik ve aktif çalışma birlikte görünür.",
      }],
    },
    controlPreferences: [
      "Kamuyu sürekli bariyerle ayır",
      "Trafik yönlendirme ve ön uyarı",
      "İksa veya şev",
      "Kapalı alan izni ve ölçüm",
      "Yüksek görünürlük",
    ],
    negativeRules: [
      "Gaz konsantrasyonu veya trafik hızı iddia etme.",
      "Bariyer arkasını varsayma.",
    ],
    assuranceScope: [
      "trafik planı onayı",
      "kapalı alan izni ve ölçümü",
      "sepetli araç kontrolü",
      "kazı ruhsatı ve altyapı sorgusu",
    ],
    regulationAnchors: [
      "Yapı İşlerinde İSG Yönetmeliği",
      "Karayolları Trafik Yönetmeliği",
      "İş Ekipmanları Yönetmeliği",
      "Kimyasal Maddelerle Çalışma Yönetmeliği",
    ],
  }),
  education: profile({
    sectorId: "education",
    labels: { tr: "Eğitim Kurumu", en: "Educational Institution" },
    typicalHazardClass: "low",
    mandatoryModules: [
      "egress_housekeeping",
      "emergency_equipment",
      "structural_mechanical_integrity",
    ],
    priorityModules: [
      "chemical_risk",
      "machine_safety_loto",
      "electrical_safety",
      "access_and_work_at_height",
      "storage_racking",
      "ppe",
    ],
    criticalEquipment: [
      e(
        "school_stair_corridor",
        "Merdiven/koridor",
        "Stair/corridor",
        "korkuluk; çubuk aralığı; basamak; tahliye genişliği",
        ["guard_barrier_integrity", "egress_path_clearance"],
      ),
      e(
        "school_egress",
        "Kaçış yolu",
        "School egress",
        "kapı yönü; panik bar; kilit; yönlendirme; toplanma yönü",
        ["egress_path_clearance"],
      ),
      e(
        "school_laboratory",
        "Laboratuvar",
        "School laboratory",
        "çeker ocak; kimyasal dolabı; göz duşu; gaz ana kesme",
        ["chemical_segregation_integrity"],
      ),
      e(
        "school_workshop",
        "Atölye",
        "School workshop",
        "tezgâh koruyucu; acil durdurma; ana şalter; öğrenci mesafesi",
        ["machine_guard_integrity"],
      ),
      e(
        "school_furniture",
        "Mobilya/dolap",
        "Furniture/cabinet",
        "sabitleme; devrilme; keskin köşe; cam",
        ["storage_stability_integrity"],
      ),
      e(
        "play_sports_area",
        "Oyun/spor alanı",
        "Play/sports area",
        "darbe emici zemin; ankraj; düşme yüksekliği",
        ["impact_surface_integrity"],
      ),
    ],
    fatalMechanismCodes: [
      "fire_explosion",
      "fall_from_height",
      "structural_collapse",
      "chemical_contact_release",
      "caught_in_pinch_shear",
    ],
    fatalMechanismAnchors: [
      "tahliyede kaçış engeli",
      "korkuluktan düşme",
      "dolap devrilmesi",
      "laboratuvar/atölye erişimi",
    ],
    frequencyPrior: {
      defaultF: 6,
      rationale: "Alanlar ders saatlerinde günlük kullanılır.",
      modifiers: [],
    },
    controlPreferences: [
      "Erişimi fiziksel kilitle",
      "Tırmanmayı engelleyen korkuluk",
      "Mobilya sabitleme",
      "Köşe koruması",
      "Tahliye yolunu açık tut",
    ],
    negativeRules: [
      "Öğrenci sayısı/doluluk çıkarma.",
      "Gözetim yeterliliği varsayma.",
      "Çocuk davranışını kesin risk faktörü yapma.",
    ],
    assuranceScope: [
      "tahliye planı/tatbikatı",
      "kimyasal envanter",
      "atölye ekipman kontrolü",
      "oyun ekipmanı uygunluğu",
    ],
    regulationAnchors: [
      "İşyeri Bina ve Eklentileri Yönetmeliği",
      "Binaların Yangından Korunması Yönetmeliği",
      "Kimyasal Maddelerle Çalışma Yönetmeliği",
    ],
  }),
  hospitality: profile({
    sectorId: "hospitality",
    labels: { tr: "Otel / Konaklama", en: "Hotel / Hospitality" },
    typicalHazardClass: "low_or_hazardous",
    mandatoryModules: [
      "egress_housekeeping",
      "emergency_equipment",
      "electrical_safety",
    ],
    priorityModules: [
      "chemical_risk",
      "machine_safety_loto",
      "ergonomics",
      "access_and_work_at_height",
      "pressure_process_safety",
      "storage_racking",
    ],
    criticalEquipment: [
      e(
        "hotel_egress",
        "Kaçış yolu",
        "Hotel egress",
        "koridor; yangın kapısı; panik bar; acil aydınlatma; kat planı",
        ["egress_path_clearance"],
      ),
      e(
        "commercial_kitchen",
        "Mutfak",
        "Commercial kitchen",
        "davlumbaz filtresi; söndürme nozulu; fritöz; kesici koruyucu",
        ["kitchen_suppression_integrity", "machine_guard_integrity"],
      ),
      e(
        "laundry",
        "Çamaşırhane",
        "Laundry",
        "ütü/pres enterloku; sıcak yüzey; buhar; dozaj",
        ["machine_guard_integrity", "hot_surface_protection"],
      ),
      e(
        "boiler_room",
        "Kazan dairesi",
        "Boiler room",
        "manometre; emniyet ventili; gaz dedektörü; havalandırma; kesme vanası",
        ["pressure_relief_integrity"],
      ),
      e(
        "pool_wet_area",
        "Havuz / ıslak alan",
        "Pool / wet area",
        "kaymaz zemin; derinlik işareti; kurtarma ekipmanı; kimyasal odası",
        ["slip_surface_integrity"],
      ),
      e(
        "guest_area",
        "Misafir alanı",
        "Guest area",
        "halı kenarı; seviye farkı; cam işareti; balkon korkuluğu",
        ["guard_barrier_integrity"],
      ),
    ],
    fatalMechanismCodes: [
      "fire_explosion",
      "fall_from_height",
      "chemical_contact_release",
    ],
    fatalMechanismAnchors: [
      "yangında kaçış/yangın kapısı kaybı",
      "davlumbaz yangını",
      "kazan patlaması/gaz kaçağı",
      "korkuluktan düşme",
      "havuz kimyasalı karışması",
    ],
    frequencyPrior: {
      defaultF: 10,
      rationale: "Konaklama tesisi 7/24 misafir barındırır.",
      modifiers: [],
    },
    controlPreferences: [
      "Otomatik kapatıcı",
      "Davlumbaz kontrolü",
      "Kaymaz zemin",
      "Korkuluk yükseltme",
      "Kimyasal odası kilidi",
      "Mühendislik kontrolü",
    ],
    negativeRules: [
      "Doluluk veya misafir sayısı çıkarma.",
      "Dedektör görüntüsünden algılama sistemi çalışırlığı iddia etme.",
      "Havuz kimyasal seviyesi yazma.",
    ],
    assuranceScope: [
      "yangın sistemi kontrolü",
      "davlumbaz temizlik kaydı",
      "kazan/asansör muayenesi",
      "havuz su analizi",
      "tahliye tatbikatı",
    ],
    regulationAnchors: [
      "Binaların Yangından Korunması Yönetmeliği",
      "İşyeri Bina ve Eklentileri Yönetmeliği",
      "İş Ekipmanları Yönetmeliği",
      "Kimyasal Maddelerle Çalışma Yönetmeliği",
      "Yüzme Havuzları Sağlık Esasları Yönetmeliği",
    ],
  }),
};

const VALID_SECTOR_IDS = new Set<string>(SECTOR_IDS);
const VALID_MODULE_IDS = new Set<string>(MODULE_IDS);

export function normalizeSectorID(value: unknown): SectorID | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase();
  return VALID_SECTOR_IDS.has(normalized) ? normalized as SectorID : null;
}

export function getSectorProfile(value: unknown): SectorProfileV2 | null {
  const id = normalizeSectorID(value);
  return id ? SECTOR_PROFILES[id] : null;
}

export type VNextSectorSelection = {
  sectorID: SectorID | null;
  source: "database" | "request_fallback" | "none";
  requestMismatch: boolean;
  shouldBackfillDatabase: boolean;
};

export function resolveVNextSectorSelection(
  databaseValue: unknown,
  requestValue: unknown,
): VNextSectorSelection {
  const databaseSector = normalizeSectorID(databaseValue);
  const requestSector = normalizeSectorID(requestValue);
  const databaseHasAuthoritativeValue = typeof databaseValue === "string" &&
    databaseValue.trim().length > 0;
  if (databaseHasAuthoritativeValue) {
    const requestWasSupplied = typeof requestValue === "string" &&
      requestValue.trim().length > 0;
    return {
      sectorID: databaseSector,
      source: "database",
      requestMismatch: requestWasSupplied && requestSector !== databaseSector,
      shouldBackfillDatabase: false,
    };
  }
  if (requestSector) {
    return {
      sectorID: requestSector,
      source: "request_fallback",
      requestMismatch: false,
      shouldBackfillDatabase: true,
    };
  }
  return {
    sectorID: null,
    source: "none",
    requestMismatch: false,
    shouldBackfillDatabase: false,
  };
}

export function orderedSectorModules(profile: SectorProfileV2): ModuleID[] {
  return [
    ...new Set([
      ...profile.mandatoryModules,
      ...profile.priorityModules,
      ...MODULE_IDS,
    ]),
  ].filter((id): id is ModuleID => VALID_MODULE_IDS.has(id));
}

export function sectorEquipmentForEntity(
  profile: SectorProfileV2,
  equipmentFamily: string,
  component = "",
): SectorCriticalEquipment[] {
  const haystack = `${equipmentFamily} ${component}`.toLocaleLowerCase("tr-TR")
    .replace(/[_/\\-]+/g, " ");
  return profile.criticalEquipment.filter((entry) =>
    entry.aliases.some((alias) => {
      const needle = alias.toLocaleLowerCase("tr-TR").replace(/[_/\\-]+/g, " ");
      return needle.length >= 3 &&
        (haystack.includes(needle) || needle.includes(haystack));
    })
  );
}

export function sectorCheckCodesForEntity(
  equipment: SectorCriticalEquipment,
  equipmentFamily: string,
  component = "",
): string[] {
  const haystack = `${equipmentFamily} ${component}`.toLocaleLowerCase("tr-TR")
    .replace(/[_/\\-]+/g, " ");
  return equipment.checkCodes.filter((checkCode) =>
    (equipment.checkComponentAliases[checkCode] ?? []).some((alias) => {
      const needle = alias.toLocaleLowerCase("tr-TR").replace(
        /[_/\\-]+/g,
        " ",
      );
      return needle.length >= 3 && haystack.includes(needle);
    })
  );
}

export function renderSectorProfilePrompt(
  profile: SectorProfileV2,
  language: string,
  features: {
    frequencyPrior?: boolean;
    controlPreferences?: boolean;
    negativeRules?: boolean;
  } = {},
): string {
  const tr = language.toLowerCase().startsWith("tr");
  const equipment = profile.criticalEquipment.map((entry) =>
    `- ${tr ? entry.labels.tr : entry.labels.en}: ${
      entry.components.join(", ")
    } [${entry.checkCodes.join(", ")}]`
  ).join("\n");
  const modifiers = profile.frequencyPrior.modifiers.map((item) =>
    `- ${item.code}: F=${item.f}; ${item.cueGuidance}`
  ).join("\n");
  const frequencyEnabled = features.frequencyPrior !== false;
  const controlsEnabled = features.controlPreferences !== false;
  const negativesEnabled = features.negativeRules !== false;
  return `SEKTÖR PROFİLİ (${SECTOR_PROFILE_VERSION})
- Kimlik: ${profile.sectorId}; etiket: ${
    tr ? profile.labels.tr : profile.labels.en
  }
- Tipik tehlike sınıfı yalnız metadatadır; skor veya hukuki sınıflandırma değildir: ${profile.typicalHazardClass}
- Zorunlu modüller: ${profile.mandatoryModules.join(", ")}
- Öncelikli modüller: ${profile.priorityModules.join(", ") || "dinamik"}
- Görünürse kritik ekipman/bileşen kontrolleri:
${
    equipment ||
    "- Sektör-tipik ekipman arama; yalnız fiilen görünen ekipmanı tara."
  }
- Ölümcül mekanizma tarama çapaları: ${
    profile.fatalMechanismAnchors.join("; ") || "yalnız görünür mekanizma"
  }
- Kontrol hiyerarşisi: ${profile.controlHierarchy.join(" → ")}
${
    controlsEnabled
      ? `- Kontrol tercih sırası: ${
        profile.controlPreferences.join(" → ")
      }\n- İzin verilen kontrol niyetleri: ${
        profile.allowedControlIntents.join(", ")
      }`
      : "- Sektör kontrol tercihleri kapalı; ortak mekanizma-kontrol kataloğunu kullan."
  }
${
    negativesEnabled
      ? `- Negatif varsayım kuralları: ${profile.negativeRules.join("; ")}`
      : "- Sektör negatif kuralları kapalı; ortak kanıt validatorlarını kullan."
  }
${
    frequencyEnabled
      ? `- Frekans priorı: ${
        profile.frequencyPrior.defaultF ?? "yok"
      }. Model bu değeri fact içine yazmaz; sunucu uygular.\n${
        modifiers
          ? `- Görünür frekans değiştirici adayları:\n${modifiers}`
          : "- Görünür frekans değiştiricisi yok."
      }`
      : "- Sektör frekans priorı kapalı; sector_context_evidence boş dizi olsun."
  }

Zorunlu modüllerin her biri için mandatory_module_outcomes içinde tam bir sonuç üret: actionable, checked_no_hazard, not_visible veya uncertain. actionable yalnız ilişkili hazard_fact ya da somut inspection_signal ve entity_ref varsa geçerlidir. uncertain olumlu fiziksel anomali yoksa fact/signal üretmez.
sector_context_evidence yalnız sektör frekans priorı açıksa ve yukarıdaki izin verilen değiştirici kodlarından biri somut görünür cue ve scene_inventory entity_ref ile doğrulanıyorsa üret; aksi halde boş dizi döndür.
Sektör yalnız tarama sırasını ve uygun kontrol niyetini etkiler. Yeni bulgu uydurmaz, seçilmeyen modülü kapsam dışına çıkarmaz, P/S veya consequence_class yükseltmez. Sektör dışı fakat görünür tehlikeyi normal biçimde analiz et. Mevzuat çapası üretme.`;
}

export type SectorModifierResolution = {
  code: SectorContextModifierCode;
  f: number;
  entityRefs: string[];
  affirmativeCues: string[];
};

export function validSectorModifierEvidence(
  profile: SectorProfileV2,
  output: PhotoAnalysisV3,
): SectorModifierResolution[] {
  const inventory = new Set(
    output.scene_inventory.map((item) => item.entity_ref),
  );
  const allowed = new Map(
    profile.frequencyPrior.modifiers.map((item) => [item.code, item]),
  );
  return output.sector_context_evidence.flatMap((evidence) => {
    const modifier = allowed.get(evidence.code);
    if (
      !modifier || evidence.affirmative_cues.length === 0 ||
      !evidence.entity_refs.some((ref) => inventory.has(ref))
    ) return [];
    return [{
      code: evidence.code,
      f: modifier.f,
      entityRefs: evidence.entity_refs.filter((ref) => inventory.has(ref)),
      affirmativeCues: evidence.affirmative_cues,
    }];
  });
}
