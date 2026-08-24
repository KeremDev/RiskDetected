import {
  type ConsequenceClass,
  type HazardMechanismCode,
} from "./contracts.ts";

export const ASSET_ASSURANCE_CATALOG_VERSION = "asset-assurance-v8";

export type AssetInventoryItem = {
  entity_ref: string;
  equipment_family: string;
  component: string;
  visible_condition_summary: string;
};

type LocalizedCopy = { tr: string; en: string };

export type AssetAssuranceTemplate = {
  conditionCode: string;
  component: LocalizedCopy;
  conditionText: LocalizedCopy;
  mechanismCode: HazardMechanismCode;
  mechanism: LocalizedCopy;
  energySource: LocalizedCopy;
  eventPath: LocalizedCopy;
  exposedEntity: LocalizedCopy;
  observation: LocalizedCopy;
  significance: LocalizedCopy;
  consequence: ConsequenceClass;
  controlIntents: string[];
};

export type AssetAssuranceProfile = {
  profileID: string;
  priority: number;
  equipmentFamily: LocalizedCopy;
  include: RegExp;
  exclude?: RegExp;
  templates: AssetAssuranceTemplate[];
};

export type ResolvedAssetAssuranceProfile = {
  profile: AssetAssuranceProfile;
  items: AssetInventoryItem[];
};

export function normalizeAssetText(value: string): string {
  return value.toLowerCase().normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "").replace(/ı/g, "i")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function itemContext(item: AssetInventoryItem): string {
  return normalizeAssetText(
    `${item.equipment_family} ${item.component}`,
  );
}

const CATALOG: AssetAssuranceProfile[] = [
  {
    profileID: "lng_storage_system",
    priority: 120,
    equipmentFamily: {
      tr: "LNG ve kriyojenik gaz depolama sistemi",
      en: "LNG and cryogenic-gas storage system",
    },
    include:
      /(?:\blng\b|liquefied natural gas|sivilastirilmis dogal gaz|cryogenic storage tank|kriyojenik (?:depolama )?tank|refrigerated liquefied gas)/u,
    exclude: /(?:\blpg\b|propane|propan|butane|butan)/u,
    templates: [{
      conditionCode: "lng_storage_integrity_assurance",
      component: {
        tr:
          "İç/dış tank, taban-çatı, temel, ankraj, izolasyon, nozullar ve kriyojenik hatlar",
        en:
          "Inner/outer tank, bottom-roof, foundation, anchors, insulation, nozzles and cryogenic lines",
      },
      conditionText: {
        tr:
          "LNG tank sisteminde kriyojenik bütünlük ve periyodik muayene programı",
        en:
          "Cryogenic integrity and periodic inspection programme for the LNG tank system",
      },
      mechanismCode: "mechanical_separation_release",
      mechanism: {
        tr:
          "Kriyojenik depolama sınırının veya destek/izolasyon sisteminin bozulması",
        en:
          "Degradation of the cryogenic containment, support or insulation system",
      },
      energySource: {
        tr: "Kriyojenik sıvı envanteri, sıvı kolonu, düşük sıcaklık ve basınç",
        en:
          "Cryogenic liquid inventory, liquid head, low temperature and pressure",
      },
      eventPath: {
        tr:
          "İç/dış tank, taban, çatı, penetrasyon, temel veya izolasyon bütünlüğündeki bozulma kriyojenik salıma, gevrek kırılmaya ve yanıcı buhar bulutu oluşumuna yol açabilir.",
        en:
          "Degradation of the inner/outer tank, bottom, roof, penetrations, foundation or insulation can cause cryogenic release, brittle fracture and a flammable vapour cloud.",
      },
      exposedEntity: {
        tr: "Operatörler, bakım ve acil müdahale çalışanları, tesis ve çevre",
        en:
          "Operators, maintenance and emergency personnel, plant and environment",
      },
      observation: {
        tr:
          "Fotoğrafta LNG veya soğutmalı sıvılaştırılmış gaz depolama sınıfında bir tank sistemi görülmektedir. Bu sınıflandırma ekipmanın mevcut bütünlük durumunu veya muayene kayıtlarını tek başına doğrulamaz.",
        en:
          "A tank system in the LNG or refrigerated-liquefied-gas storage class is visible. This classification alone does not establish its current integrity or inspection status.",
      },
      significance: {
        tr:
          "Periyodik bütünlük programı iç ve dış tankı, taban/çatı ve penetrasyonları, temel-oturma davranışını, ankrajları, izolasyon ve annüler alanı, kriyojenik vana/hatları, sıcaklık-basınç eğilimlerini ve sızdırmazlık sınırını birlikte kapsamalıdır. Gerçek tasarım ve kapasite kapsamı uygunsa API 625 ve ilgili LNG tesis standardı; kapsam dışındaysa ekipmanın kendi tasarım standardı esas alınmalıdır.",
        en:
          "The periodic integrity programme should jointly cover inner and outer tanks, bottom/roof and penetrations, foundation settlement, anchors, insulation and annular space, cryogenic valves/lines, temperature-pressure trends and containment. Use API 625 and the applicable LNG facility standard only where the actual design and capacity fit their scope; otherwise use the governing design standard.",
      },
      consequence: "multiple_fatality_major_environmental",
      controlIntents: [
        "verify_periodic_control_status",
        "lng_cryogenic_integrity_inspection",
      ],
    }, {
      conditionCode: "lng_process_safeguard_assurance",
      component: {
        tr:
          "Seviye/taşma, basınç-vakum tahliyesi, boil-off gas, gaz algılama, ESD ve döküntü tutma",
        en:
          "Level/overfill, pressure-vacuum relief, boil-off gas, gas detection, ESD and spill impoundment",
      },
      conditionText: {
        tr:
          "LNG tesisinde proses emniyeti, gaz algılama ve acil durdurma fonksiyonları",
        en:
          "Process safety, gas detection and emergency shutdown functions at the LNG installation",
      },
      mechanismCode: "fire_explosion",
      mechanism: {
        tr:
          "LNG salımının algılanamaması veya izolasyon/tahliye katmanlarıyla sınırlandırılamaması",
        en:
          "Failure to detect or contain an LNG release through isolation and relief layers",
      },
      energySource: {
        tr:
          "Yanıcı kriyojenik envanter, buharlaşma ve olası tutuşturucu kaynaklar",
        en:
          "Flammable cryogenic inventory, vaporisation and potential ignition sources",
      },
      eventPath: {
        tr:
          "Taşma, aşırı/düşük basınç veya sızıntının zamanında algılanıp izole edilememesi soğuk temas, oksijen azalması, yanıcı buhar bulutu, yangın veya patlamaya dönüşebilir.",
        en:
          "Failure to detect and isolate overfill, pressure/vacuum deviation or leakage can develop into cold exposure, oxygen deficiency, a flammable vapour cloud, fire or explosion.",
      },
      exposedEntity: {
        tr: "Operatörler, bakım ve acil müdahale çalışanları ile tesis çevresi",
        en:
          "Operators, maintenance and emergency personnel and the surrounding facility",
      },
      observation: {
        tr:
          "LNG depolama güvenliği yalnız tank gövdesine değil, dolum-boşaltım, boil-off gas yönetimi, algılama, tahliye, izolasyon ve acil durum katmanlarına da bağlıdır.",
        en:
          "LNG storage safety depends on filling/transfer, boil-off-gas management, detection, relief, isolation and emergency layers as well as the tank boundary.",
      },
      significance: {
        tr:
          "Uygulanabilir yüksek-yüksek seviye ve bağımsız taşma önleme, basınç-vakum tahliyesi, boil-off gas yönetimi, yanıcı gaz ve düşük sıcaklık/oksijen algılama, uzaktan ESD, kriyojenik uyumlu izolasyon, döküntü tutma ve acil durum senaryoları tanımlı set değerleriyle fonksiyon testine tabi tutulmalıdır.",
        en:
          "Applicable independent high-high level/overfill prevention, pressure-vacuum relief, boil-off-gas management, flammable-gas and low-temperature/oxygen detection, remote ESD, cryogenic isolation, spill impoundment and emergency scenarios should be function-tested against defined set points.",
      },
      consequence: "multiple_fatality_major_environmental",
      controlIntents: [
        "verify_periodic_control_status",
        "lng_safeguard_emergency_control",
      ],
    }],
  },
  {
    profileID: "lpg_storage_system",
    priority: 118,
    equipmentFamily: {
      tr: "LPG depolama ve transfer sistemi",
      en: "LPG storage and transfer system",
    },
    include:
      /(?:\blpg\b|liquefied petroleum gas|sivilastirilmis petrol gazi|propane tank|propan tank|butane tank|butan tank|lpg bullet|lpg sphere)/u,
    templates: [{
      conditionCode: "lpg_storage_integrity_assurance",
      component: {
        tr:
          "Basınçlı gövde, kaynaklar, nozullar, destekler, ankrajlar, vanalar ve transfer hatları",
        en:
          "Pressure shell, welds, nozzles, supports, anchors, valves and transfer lines",
      },
      conditionText: {
        tr:
          "LPG depolama sisteminde basınç bütünlüğü ve periyodik kontrol programı",
        en:
          "Pressure-integrity and periodic inspection programme for the LPG storage system",
      },
      mechanismCode: "mechanical_separation_release",
      mechanism: {
        tr: "Basınçlı LPG depolama veya transfer sınırının bozulması",
        en: "Failure of the pressurised LPG storage or transfer boundary",
      },
      energySource: {
        tr: "Basınçlı yanıcı gaz/sıvı envanteri ve depolanmış basınç enerjisi",
        en:
          "Pressurised flammable gas/liquid inventory and stored pressure energy",
      },
      eventPath: {
        tr:
          "Gövde, kaynak, nozul, vana, destek veya transfer hattındaki bütünlük kaybı basınçlı LPG salımına, buhar bulutuna, yangına ve ısınan kapta ağır basınç olayına yol açabilir.",
        en:
          "Loss of integrity in the shell, weld, nozzle, valve, support or transfer line can cause pressurised LPG release, a vapour cloud, fire and a severe pressure event in a fire-exposed vessel.",
      },
      exposedEntity: {
        tr: "Operatörler, dolum ve bakım çalışanları, tesis ve çevre",
        en:
          "Operators, transfer and maintenance personnel, plant and environment",
      },
      observation: {
        tr:
          "Fotoğrafta LPG depolama veya transfer sınıfında basınçlı ekipman görülmektedir. Bu kayıt, ekipmanın muayenesinin geciktiği veya gövdesinin kusurlu olduğu iddiası değildir.",
        en:
          "Pressurised equipment in the LPG storage or transfer class is visible. This record does not allege that inspection is overdue or that the pressure boundary is defective.",
      },
      significance: {
        tr:
          "Periyodik kontrol; tasarım basıncı/sıcaklığı, gövde ve kaynaklar, nozullar, destek/ankrajlar, korozyon ve kalınlık ölçümleri, vana/hat bütünlüğü, emniyet tahliye cihazları ve önceki ölçüm eğilimlerini kapsamalıdır. Tesisin tasarım ve yerleşim kapsamı uygunsa API 2510; hizmet içi muayenede ise ekipmanın gerçek basınçlı kap ve borulama standardı esas alınmalıdır.",
        en:
          "Periodic inspection should cover design pressure/temperature, shell and welds, nozzles, supports/anchors, corrosion and thickness measurements, valve/line integrity, relief devices and previous trends. Use API 2510 where its installation scope fits and the actual governing pressure-vessel and piping standards for in-service inspection.",
      },
      consequence: "multiple_fatality_major_environmental",
      controlIntents: [
        "verify_periodic_control_status",
        "lpg_installation_integrity_inspection",
      ],
    }, {
      conditionCode: "lpg_safeguard_assurance",
      component: {
        tr:
          "Tahliye, aşırı dolum, gaz algılama, uzaktan izolasyon, ESD, transfer ve yangın koruması",
        en:
          "Relief, overfill, gas detection, remote isolation, ESD, transfer and fire protection",
      },
      conditionText: {
        tr: "LPG tesisinde emniyet fonksiyonları ve acil durum kontrolleri",
        en: "Safety functions and emergency controls at the LPG installation",
      },
      mechanismCode: "fire_explosion",
      mechanism: {
        tr:
          "LPG salımının algılanamaması veya acil izolasyon ve koruma katmanlarıyla sınırlandırılamaması",
        en:
          "Failure to detect or contain an LPG release through emergency isolation and protection layers",
      },
      energySource: {
        tr: "Basınçlı yanıcı envanter, transfer akışı ve tutuşturucu kaynaklar",
        en:
          "Pressurised flammable inventory, transfer flow and ignition sources",
      },
      eventPath: {
        tr:
          "Dolum/boşaltım veya ekipman sızıntısının algılanıp durdurulamaması düşük noktalarda buhar birikimine, parlamaya, yangına veya patlamaya yol açabilir.",
        en:
          "Failure to detect and stop a transfer or equipment leak can allow vapour accumulation in low areas and lead to flash fire, fire or explosion.",
      },
      exposedEntity: {
        tr:
          "Operatörler, dolum personeli, acil müdahale çalışanları ve tesis çevresi",
        en:
          "Operators, transfer personnel, emergency responders and the surrounding facility",
      },
      observation: {
        tr:
          "LPG tesis güvenliği; basınç sınırının yanında tahliye, dolum kontrolü, gaz algılama, uzaktan izolasyon, transfer bağlantıları ve yangın senaryolarına bağlıdır.",
        en:
          "LPG installation safety depends on relief, filling control, gas detection, remote isolation, transfer connections and fire scenarios as well as the pressure boundary.",
      },
      significance: {
        tr:
          "Emniyet valfi ve tahliye yönü, aşırı dolum önleme, sabit/taşınabilir gaz algılama, acil durdurma ve uzaktan izolasyon vanaları, hortum-kopma koruması, topraklama/eşpotansiyel bağlama, ayırma mesafeleri ve uygulanabilir yangın koruma fonksiyonları kayıtlı periyotlarda test edilmelidir.",
        en:
          "Relief devices and discharge routing, overfill prevention, fixed/portable gas detection, emergency shutdown and remote isolation, hose-break protection, bonding/earthing, separation distances and applicable fire-protection functions should be tested at documented intervals.",
      },
      consequence: "multiple_fatality_major_environmental",
      controlIntents: [
        "verify_periodic_control_status",
        "lpg_safeguard_periodic_test",
      ],
    }],
  },
  {
    profileID: "flammable_gas_ex_area",
    priority: 116,
    equipmentFamily: {
      tr: "Yanıcı gaz ve patlayıcı ortam",
      en: "Flammable-gas and explosive atmosphere",
    },
    include:
      /(?:\blng\b|\blpg\b|liquefied natural gas|liquefied petroleum gas|sivilastirilmis dogal gaz|sivilastirilmis petrol gazi|propane|propan|butane|butan|flammable gas)/u,
    templates: [{
      conditionCode: "flammable_gas_ex_area_assurance",
      component: {
        tr:
          "Tehlikeli bölge sınıflandırması, elektrikli/elektriksiz Ex ekipman, kablolama, topraklama ve tutuşturucu kaynaklar",
        en:
          "Hazardous-area classification, electrical/non-electrical Ex equipment, wiring, earthing and ignition sources",
      },
      conditionText: {
        tr:
          "LNG/LPG alanında tehlikeli bölge sınıflandırması ve Ex ekipman uygunluğu",
        en:
          "Hazardous-area classification and Ex-equipment suitability in the LNG/LPG area",
      },
      mechanismCode: "fire_explosion",
      mechanism: {
        tr:
          "Yanıcı gaz atmosferinin uygun olmayan ekipman veya başka bir tutuşturucu kaynakla ateşlenmesi",
        en:
          "Ignition of a flammable-gas atmosphere by unsuitable equipment or another ignition source",
      },
      energySource: {
        tr:
          "Yanıcı gaz/buhar ve elektriksel, mekanik, sıcak yüzey veya statik tutuşturma enerjisi",
        en:
          "Flammable gas/vapour and electrical, mechanical, hot-surface or electrostatic ignition energy",
      },
      eventPath: {
        tr:
          "Sızıntı kaynağı ve havalandırmaya göre oluşabilecek patlayıcı atmosferin uygun olmayan ekipman, sıcak yüzey, kıvılcım veya statik boşalmayla tutuşması yangın ve patlamaya yol açabilir.",
        en:
          "An explosive atmosphere arising from a release source and ventilation conditions can ignite on unsuitable equipment, a hot surface, spark or electrostatic discharge and cause fire or explosion.",
      },
      exposedEntity: {
        tr: "Operatörler, bakım ve acil müdahale çalışanları ile tesis çevresi",
        en:
          "Operators, maintenance and emergency personnel and the surrounding facility",
      },
      observation: {
        tr:
          "Fotoğrafta LNG/LPG veya başka bir yanıcı gaz sistemi sınıfında ekipman görülmektedir. Fotoğraf tek başına bölge zonunu veya ekipmanın Ex uygunluğunu belirlemez; bunlar proses verisi ve yerinde envanterle doğrulanır.",
        en:
          "Equipment in an LNG/LPG or other flammable-gas system class is visible. The photograph alone cannot establish the zone or Ex suitability; these require process data and an on-site equipment inventory.",
      },
      significance: {
        tr:
          "Sızıntı kaynakları, salım derecesi, gaz özellikleri ve havalandırmaya göre IEC 60079-10-1 yaklaşımıyla tehlikeli bölge sınıflandırması yapılmalı; zon içine giren elektrikli ve uygulanabilir elektriksiz ekipman gaz grubu, sıcaklık sınıfı, EPL/kategori, koruma tipi ve ortam koşullarıyla uyumlu seçilmelidir. Tasarım/ilk doğrulama ve periyodik Ex denetimleri IEC 60079-14 ve IEC 60079-17 ile uygulanabilir ATEX ve yerel mevzuat çerçevesinde yürütülmelidir.",
        en:
          "Classify hazardous areas from release sources, grade of release, gas properties and ventilation using IEC 60079-10-1; select electrical and applicable non-electrical equipment within the zone for the correct gas group, temperature class, EPL/category, protection concept and environment. Design/initial verification and periodic Ex inspection should follow IEC 60079-14, IEC 60079-17 and applicable ATEX/local requirements.",
      },
      consequence: "multiple_fatality_major_environmental",
      controlIntents: [
        "verify_periodic_control_status",
        "hazardous_area_ex_equipment_control",
      ],
    }],
  },
  {
    profileID: "pressure_equipment",
    priority: 100,
    equipmentFamily: {
      tr: "Basınçlı ekipman",
      en: "Pressure equipment",
    },
    include:
      /(?:pressure vessel|basinc kabi|air receiver|hava tanki|boiler|kazan|compressed gas cylinder|basincli tup|gaz tupu|compressor receiver)/u,
    exclude:
      /(?:process vessel|storage tank|proses tank|depolama tank|\blpg\b|propane|propan|butane|butan)/u,
    templates: [{
      conditionCode: "pressure_equipment_integrity_assurance",
      component: {
        tr: "Gövde, kaynaklar, nozullar, destekler ve basınç sınırı",
        en: "Shell, welds, nozzles, supports and pressure boundary",
      },
      conditionText: {
        tr: "Basınçlı ekipmanın bütünlük ve periyodik kontrol programı",
        en:
          "Integrity and periodic inspection programme for pressure equipment",
      },
      mechanismCode: "mechanical_separation_release",
      mechanism: {
        tr: "Basınç sınırının bozulmasıyla ani enerji ve akışkan salımı",
        en:
          "Sudden energy and fluid release following pressure-boundary failure",
      },
      energySource: {
        tr: "İç basınç, sıcaklık ve depolanmış mekanik enerji",
        en: "Internal pressure, temperature and stored mechanical energy",
      },
      eventPath: {
        tr:
          "Gövde, kaynak, nozul veya bağlantı bütünlüğündeki bozulma ani basınç salımına, parça fırlamasına ve ciddi yaralanmaya yol açabilir.",
        en:
          "Degradation of the shell, welds, nozzles or connections can cause sudden pressure release, projectiles and serious injury.",
      },
      exposedEntity: {
        tr: "Operatörler, bakım çalışanları ve yakındaki kişiler",
        en: "Operators, maintenance personnel and nearby persons",
      },
      observation: {
        tr:
          "Fotoğrafta basınç altında çalışabilen ekipman ve basınç sınırını oluşturan gövde/bağlantı bileşenleri görülmektedir.",
        en:
          "Equipment capable of operating under pressure and its pressure-boundary components are visible.",
      },
      significance: {
        tr:
          "Periyodik kontrol; tasarım bilgileri, çalışma basıncı/sıcaklığı, korozyon payı, kaynak ve nozul bölgeleri, destekler ve önceki ölçüm eğilimleriyle birlikte yürütülmelidir. Uygun yöntemde görsel muayene, ultrasonik kalınlık ölçümü ve gerekli yüzey/hacimsel NDT uygulanır.",
        en:
          "Periodic inspection should combine design data, operating pressure/temperature, corrosion allowance, weld/nozzle areas, supports and measurement trends, using visual examination, ultrasonic thickness measurement and appropriate surface or volumetric NDT.",
      },
      consequence: "single_fatality",
      controlIntents: [
        "verify_periodic_control_status",
        "pressure_equipment_integrity_inspection",
      ],
    }, {
      conditionCode: "pressure_safety_device_assurance",
      component: {
        tr:
          "Emniyet valfi, basınç göstergesi, limit ve izolasyon fonksiyonları",
        en: "Relief valve, pressure indication, limits and isolation functions",
      },
      conditionText: {
        tr: "Basınç emniyet cihazlarının ayar ve fonksiyon doğrulaması",
        en: "Set-point and functional verification of pressure safety devices",
      },
      mechanismCode: "mechanical_separation_release",
      mechanism: {
        tr: "Aşırı basıncın emniyet cihazlarıyla sınırlandırılamaması",
        en: "Failure to limit overpressure through safety devices",
      },
      energySource: {
        tr: "Basınç ve proses enerjisi",
        en: "Pressure and process energy",
      },
      eventPath: {
        tr:
          "Tahliye, gösterge, limit veya izolasyon fonksiyonunun talep anında çalışmaması aşırı basıncı ekipman hasarı ve ani salıma dönüştürebilir.",
        en:
          "Failure on demand of relief, indication, limit or isolation functions can develop overpressure into equipment damage and sudden release.",
      },
      exposedEntity: {
        tr: "Operatörler ve bakım çalışanları",
        en: "Operators and maintenance personnel",
      },
      observation: {
        tr:
          "Basınçlı ekipmanın güvenliği, mekanik gövdeyle birlikte uygulanabilir tahliye, gösterge ve izolasyon fonksiyonlarına bağlıdır.",
        en:
          "Pressure-equipment safety depends on applicable relief, indication and isolation functions as well as the mechanical boundary.",
      },
      significance: {
        tr:
          "Emniyet valfi set basıncı ve kapasitesi, gösterge doğruluğu, basınç limitleri, tahliye hattı ve izolasyon düzeni proses şartlarına göre tanımlanmalı; kalibrasyon ve fonksiyon testleri kayıtlı periyotlarda yapılmalıdır.",
        en:
          "Relief set pressure/capacity, indication accuracy, pressure limits, discharge routing and isolation should be defined from process conditions and tested at documented intervals.",
      },
      consequence: "single_fatality",
      controlIntents: [
        "verify_periodic_control_status",
        "pressure_safety_device_test",
      ],
    }],
  },
  {
    profileID: "mobile_work_equipment",
    priority: 95,
    equipmentFamily: {
      tr: "Mobil iş ekipmanı",
      en: "Mobile work equipment",
    },
    include:
      /(?:mobile equipment|heavy equipment|is makinesi|ekskavator|excavator|loader|yukleyici|forklift|telehandler|bulldozer|dozer|backhoe|greyder|grader)/u,
    exclude: /(?:overhead crane|bridge crane|kopru vinc)/u,
    templates: [{
      conditionCode: "mobile_equipment_periodic_integrity_assurance",
      component: {
        tr:
          "Şasi, bom/ataşman, pimler, hidrolik sistem, lastik/palet ve bağlantılar",
        en:
          "Chassis, boom/attachment, pins, hydraulics, tyres/tracks and joints",
      },
      conditionText: {
        tr:
          "Mobil iş ekipmanının mekanik bütünlük ve periyodik bakım kontrolleri",
        en:
          "Mechanical integrity and periodic maintenance checks for mobile equipment",
      },
      mechanismCode: "mechanical_separation_release",
      mechanism: {
        tr:
          "Yük taşıyan veya hareket ileten bileşenin hizmet sırasında bozulması",
        en:
          "In-service failure of a load-bearing or motion-transmitting component",
      },
      energySource: {
        tr: "Yerçekimi, hidrolik basınç ve hareket enerjisi",
        en: "Gravity, hydraulic pressure and motion energy",
      },
      eventPath: {
        tr:
          "Bom, ataşman, pim, hidrolik hat veya yürüyüş sistemindeki bütünlük kaybı kontrolsüz hareket, parça ayrılması ya da devrilmeye yol açabilir.",
        en:
          "Integrity loss in the boom, attachment, pins, hydraulics or running gear can cause uncontrolled movement, separation or overturning.",
      },
      exposedEntity: {
        tr: "Operatör, bakım çalışanları ve çalışma alanındaki kişiler",
        en: "Operator, maintenance personnel and people in the work zone",
      },
      observation: {
        tr:
          "Fotoğrafta hareket, yük aktarımı ve hidrolik enerji kullanan mobil iş ekipmanı görülmektedir.",
        en:
          "Mobile work equipment using motion, load transfer and hydraulic energy is visible.",
      },
      significance: {
        tr:
          "Bakım ve kontrol programı; şasi/ROPS-FOPS yapısı, bom-ataşman yük yolu, pim-tutucular, hortumlar, silindirler, fren/park sistemi ve lastik-palet durumunu üretici limitleriyle değerlendirmelidir.",
        en:
          "The maintenance and inspection programme should assess chassis/ROPS-FOPS, boom-attachment load path, pins/retainers, hoses, cylinders, brakes/parking system and tyres/tracks against manufacturer limits.",
      },
      consequence: "single_fatality",
      controlIntents: [
        "verify_periodic_control_status",
        "mobile_equipment_periodic_inspection",
      ],
    }, {
      conditionCode: "mobile_equipment_safety_function_assurance",
      component: {
        tr:
          "Fren, direksiyon, ikaz, görüş, acil durdurma ve operatör koruma fonksiyonları",
        en:
          "Braking, steering, warning, visibility, emergency and operator-protection functions",
      },
      conditionText: {
        tr: "Mobil ekipmanın operasyonel emniyet fonksiyonlarının doğrulanması",
        en: "Verification of operational safety functions on mobile equipment",
      },
      mechanismCode: "vehicle_equipment_strike",
      mechanism: {
        tr:
          "Kontrol, görüş veya uyarı fonksiyonunun bozulmasıyla çarpma/ezilme",
        en:
          "Strike or crush event following control, visibility or warning-function failure",
      },
      energySource: {
        tr: "Araç hareketi ve makine çalışma enerjisi",
        en: "Vehicle motion and machine operating energy",
      },
      eventPath: {
        tr:
          "Fren, direksiyon, geri hareket ikazı, kamera/ayna, korna veya operatör koruma fonksiyonunun çalışmaması kişi ya da ekipmanla çarpışmaya yol açabilir.",
        en:
          "Failure of brakes, steering, reversing warning, cameras/mirrors, horn or operator protection can lead to collision with people or equipment.",
      },
      exposedEntity: {
        tr: "Operatör ve çalışma alanındaki kişiler",
        en: "Operator and people in the work area",
      },
      observation: {
        tr:
          "Mobil ekipmanın güvenli işletimi yalnız görünür mekanik duruma değil, hareket ve operatör koruma fonksiyonlarının çalışmasına da bağlıdır.",
        en:
          "Safe operation depends not only on visible mechanical condition but also on motion-control and operator-protection functions.",
      },
      significance: {
        tr:
          "Vardiya öncesi kontrol ve periyodik test; servis/park freni, direksiyon, geri hareket ikazı, korna, aydınlatma, kamera/ayna, emniyet kemeri ve uygulanabilir limit/engelleme fonksiyonlarını kapsamalıdır.",
        en:
          "Pre-use checks and periodic tests should cover service/parking brakes, steering, reverse warning, horn, lighting, cameras/mirrors, seat belt and applicable limiting/interlock functions.",
      },
      consequence: "single_fatality",
      controlIntents: [
        "verify_periodic_control_status",
        "mobile_equipment_safety_function_test",
      ],
    }],
  },
  {
    profileID: "road_and_industrial_vehicle",
    priority: 90,
    equipmentFamily: {
      tr: "Endüstriyel araç",
      en: "Industrial vehicle",
    },
    include:
      /(?:truck|kamyon|dump truck|damperli|tanker truck|beton mikseri kamyon|concrete mixer truck|tractor unit|cekici|industrial vehicle)/u,
    templates: [{
      conditionCode: "industrial_vehicle_safety_assurance",
      component: {
        tr:
          "Fren, direksiyon, lastik, aydınlatma, ikaz ve üstyapı bağlantıları",
        en: "Brakes, steering, tyres, lighting, warnings and body attachments",
      },
      conditionText: {
        tr: "Endüstriyel aracın yol ve operasyon emniyeti kontrolleri",
        en:
          "Roadworthiness and operational safety checks for the industrial vehicle",
      },
      mechanismCode: "vehicle_equipment_strike",
      mechanism: {
        tr: "Araç kontrolü veya üstyapı bütünlüğünün kaybı",
        en: "Loss of vehicle control or body integrity",
      },
      energySource: {
        tr: "Araç hareketi, yük ve hidrolik/mekanik üstyapı enerjisi",
        en: "Vehicle motion, load and hydraulic/mechanical body energy",
      },
      eventPath: {
        tr:
          "Fren, direksiyon, lastik, ikaz veya üstyapı bağlantılarındaki bozulma çarpışma, devrilme, yük kaybı veya sıkışmaya yol açabilir.",
        en:
          "Degradation of brakes, steering, tyres, warnings or body attachments can lead to collision, overturning, load loss or crushing.",
      },
      exposedEntity: {
        tr: "Sürücü, saha çalışanları ve diğer yol kullanıcıları",
        en: "Driver, site personnel and other road users",
      },
      observation: {
        tr:
          "Fotoğrafta saha veya yol operasyonunda kullanılan endüstriyel araç görülmektedir.",
        en: "An industrial vehicle used in site or road operations is visible.",
      },
      significance: {
        tr:
          "Kontrol kapsamı yol uygunluğu ile birlikte üstyapı, damper/mikser/tanker bağlantıları, hidrolik kaldırma elemanları, geri hareket uyarısı, görüş yardımcıları ve acil durum ekipmanını da içermelidir.",
        en:
          "Inspection scope should cover roadworthiness plus body, tipper/mixer/tanker attachments, hydraulic lifting elements, reversing warnings, visibility aids and emergency equipment.",
      },
      consequence: "single_fatality",
      controlIntents: [
        "verify_periodic_control_status",
        "industrial_vehicle_safety_inspection",
      ],
    }],
  },
  {
    profileID: "machine_tool",
    priority: 88,
    equipmentFamily: {
      tr: "Takım tezgâhı",
      en: "Machine tool",
    },
    include:
      /(?:lathe|torna|cnc|machining center|isleme merkezi|drill press|matkap tezgahi|milling machine|freze|press brake|abkant|mechanical press|hidrolik pres)/u,
    templates: [{
      conditionCode: "machine_tool_guarding_assurance",
      component: {
        tr:
          "İş mili, ayna/takım, hareket eksenleri, koruyucular ve interlocklar",
        en: "Spindle, chuck/tool, motion axes, guards and interlocks",
      },
      conditionText: {
        tr:
          "Takım tezgâhında koruyucu ve emniyet fonksiyonlarının doğrulanması",
        en: "Verification of guarding and safety functions on the machine tool",
      },
      mechanismCode: "caught_in_pinch_shear",
      mechanism: {
        tr:
          "Döner veya doğrusal hareketli parçaya erişim ve beklenmeyen hareket",
        en: "Access to rotating/linear motion or unexpected movement",
      },
      energySource: {
        tr: "Elektrik, dönme, sıkıştırma ve eksen hareketi",
        en: "Electrical, rotational, clamping and axis-motion energy",
      },
      eventPath: {
        tr:
          "Ayna, takım, iş mili veya hareket eksenine erişim; parça fırlaması, sarılma, sıkışma ya da kesilme yaralanmasına yol açabilir.",
        en:
          "Access to the chuck, tool, spindle or motion axes can cause ejection, entanglement, crushing or cutting injuries.",
      },
      exposedEntity: {
        tr: "Operatörler ve bakım/ayar çalışanları",
        en: "Operators and maintenance/setup personnel",
      },
      observation: {
        tr:
          "Fotoğrafta kesme, döndürme, delme veya eksen hareketi oluşturan takım tezgâhı görülmektedir.",
        en:
          "A machine tool producing cutting, rotation, drilling or axis motion is visible.",
      },
      significance: {
        tr:
          "Koruyucular, kapı interlockları, acil durdurma, yeniden başlatma önleme, iş parçası bağlama ve talaş/sıvı muhafazası üretici güvenlik fonksiyonlarına göre test edilmelidir.",
        en:
          "Guards, door interlocks, emergency stop, restart prevention, workholding and chip/fluid containment should be tested against manufacturer safety functions.",
      },
      consequence: "permanent_disability",
      controlIntents: [
        "verify_periodic_control_status",
        "machine_guarding_function_test",
      ],
    }, {
      conditionCode: "machine_tool_loto_maintenance_assurance",
      component: {
        tr: "Elektrik, pnömatik/hidrolik ve depolanmış enerji izolasyonu",
        en: "Electrical, pneumatic/hydraulic and stored-energy isolation",
      },
      conditionText: {
        tr: "Takım tezgâhında bakım, ayar ve LOTO güvenliği",
        en: "Maintenance, setup and LOTO safety for the machine tool",
      },
      mechanismCode: "caught_in_pinch_shear",
      mechanism: {
        tr: "Bakım veya ayar sırasında beklenmeyen çalıştırma",
        en: "Unexpected startup during maintenance or setup",
      },
      energySource: {
        tr: "Elektrik ve depolanmış mekanik/akışkan enerjisi",
        en: "Electrical and stored mechanical/fluid energy",
      },
      eventPath: {
        tr:
          "Enerji izolasyonunun eksik veya etkisiz olması bakım/ayar sırasında beklenmeyen hareket ve sıkışma-kesilme olayına yol açabilir.",
        en:
          "Incomplete or ineffective isolation can cause unexpected movement and caught-in/shear events during maintenance or setup.",
      },
      exposedEntity: {
        tr: "Bakım, temizlik ve ayar çalışanları",
        en: "Maintenance, cleaning and setup personnel",
      },
      observation: {
        tr:
          "Takım tezgâhı, normal işletme dışında bakım, takım değişimi, temizlik ve ayar sırasında da birden fazla enerji taşır.",
        en:
          "The machine tool carries multiple energies during maintenance, tool change, cleaning and setup as well as normal operation.",
      },
      significance: {
        tr:
          "Enerji kesme noktaları, kilitleme imkânı, sıfır enerji testi, eksen/başlık düşmesine karşı mekanik blokaj ve kontrollü yeniden devreye alma adımları görev bazında tanımlanmalıdır.",
        en:
          "Isolation points, lockability, zero-energy testing, mechanical blocking against axis/head descent and controlled recommissioning should be task-defined.",
      },
      consequence: "permanent_disability",
      controlIntents: [
        "verify_periodic_control_status",
        "machine_loto_maintenance_control",
      ],
    }],
  },
  {
    profileID: "bulk_process_machine",
    priority: 86,
    equipmentFamily: {
      tr: "Kırma-eleme ve proses makinesi",
      en: "Bulk-processing machinery",
    },
    include:
      /(?:^| )(?:crusher|kirici|screening machine|vibrating screen|elek|mill|degirmen|conveyor|konveyor|belt conveyor|bant|industrial mixer|karistirici|concrete mixer|beton mikseri)(?: |$)/u,
    exclude: /(?:truck|kamyon|process vessel|proses tank)/u,
    templates: [{
      conditionCode: "bulk_machine_guard_loto_assurance",
      component: {
        tr: "Besleme/boşaltma, tahrik, bant-kasnak, rotor ve sıkışma bölgeleri",
        en: "Feed/discharge, drives, belt-pulley, rotor and entrapment zones",
      },
      conditionText: {
        tr: "Proses makinesinde koruyucu, acil durdurma ve LOTO kontrolleri",
        en:
          "Guarding, emergency-stop and LOTO controls for processing machinery",
      },
      mechanismCode: "caught_in_pinch_shear",
      mechanism: {
        tr: "Döner/öteleme hareketine erişim veya birikmiş enerjinin boşalması",
        en: "Access to rotating/translating motion or release of stored energy",
      },
      energySource: {
        tr: "Elektrik, dönme, titreşim, yerçekimi ve malzeme basıncı",
        en: "Electrical, rotational, vibration, gravity and material pressure",
      },
      eventPath: {
        tr:
          "Besleme, boşaltma, rotor, bant-kasnak veya tahrik bölgesine erişim sarılma, sıkışma, ezilme ya da malzeme fırlamasına yol açabilir.",
        en:
          "Access to feed, discharge, rotor, belt-pulley or drive zones can cause entanglement, crushing or material ejection.",
      },
      exposedEntity: {
        tr: "Operatörler, temizlik ve bakım çalışanları",
        en: "Operators, cleaning and maintenance personnel",
      },
      observation: {
        tr:
          "Fotoğrafta malzemeyi kıran, eleyen, taşıyan, öğüten veya karıştıran proses makinesi görülmektedir.",
        en:
          "Machinery that crushes, screens, conveys, mills or mixes material is visible.",
      },
      significance: {
        tr:
          "Muhafazalar, besleme-boşaltma erişimi, bant hizası, acil durdurma halatı/butonu, hız-sapma interlockları ve tıkanıklık açma için enerji izolasyonu birlikte doğrulanmalıdır.",
        en:
          "Guards, feed/discharge access, belt alignment, emergency stops, speed/deviation interlocks and isolation for clearing blockages should be verified together.",
      },
      consequence: "single_fatality",
      controlIntents: [
        "verify_periodic_control_status",
        "bulk_machine_guard_loto_inspection",
      ],
    }, {
      conditionCode: "bulk_machine_integrity_assurance",
      component: {
        tr:
          "Şase, rotor/elek, yataklar, bağlantılar, astarlar ve taşıyıcı yapı",
        en:
          "Frame, rotor/screen, bearings, joints, liners and supporting structure",
      },
      conditionText: {
        tr: "Proses makinesinin mekanik ve yapısal bütünlük programı",
        en:
          "Mechanical and structural integrity programme for processing machinery",
      },
      mechanismCode: "mechanical_separation_release",
      mechanism: {
        tr: "Titreşimli veya döner bileşenin yorulma/aşınmayla ayrılması",
        en: "Fatigue/wear separation of a vibrating or rotating component",
      },
      energySource: {
        tr: "Dönme, titreşim, malzeme yükü ve yerçekimi",
        en: "Rotation, vibration, material load and gravity",
      },
      eventPath: {
        tr:
          "Yatak, bağlantı, rotor/elek, astar veya taşıyıcı yapıda ilerleyen bozulma parça kopması, dengesizlik, malzeme saçılması veya yapısal kayba yol açabilir.",
        en:
          "Progressive degradation of bearings, joints, rotor/screen, liners or structure can cause separation, imbalance, material ejection or structural loss.",
      },
      exposedEntity: {
        tr: "Operatörler ve bakım çalışanları",
        en: "Operators and maintenance personnel",
      },
      observation: {
        tr:
          "Görünen proses makinesi sürekli veya çevrimsel titreşim, darbe, aşınma ve malzeme yüküne maruz kalan bileşenlerden oluşur.",
        en:
          "The visible processing machinery comprises components exposed to cyclic vibration, impact, wear and material loads.",
      },
      significance: {
        tr:
          "Periyodik bakım; titreşim/sıcaklık eğilimi, yataklar, cıvatalı-kaynaklı birleşimler, astar/elek aşınması, hizalama ve temel/şase bağlantıları için ölçülü kabul kriterleri içermelidir.",
        en:
          "Periodic maintenance should include measured acceptance criteria for vibration/temperature trends, bearings, bolted/welded joints, liner/screen wear, alignment and foundation/frame attachments.",
      },
      consequence: "permanent_disability",
      controlIntents: [
        "verify_periodic_control_status",
        "rotating_equipment_integrity_inspection",
      ],
    }],
  },
  {
    profileID: "pump_system",
    priority: 82,
    equipmentFamily: { tr: "Pompa sistemi", en: "Pump system" },
    include: /(?:pump|pompa|pump skid|pompa skidi)/u,
    templates: [{
      conditionCode: "pump_integrity_assurance",
      component: {
        tr:
          "Pompa gövdesi, kaplin, salmastra/keçe, yatak, temel ve bağlantılar",
        en: "Pump casing, coupling, seal, bearings, foundation and connections",
      },
      conditionText: {
        tr:
          "Pompa sisteminde bütünlük, sızdırmazlık ve durum izleme kontrolleri",
        en:
          "Integrity, containment and condition-monitoring checks for the pump system",
      },
      mechanismCode: "mechanical_separation_release",
      mechanism: {
        tr: "Döner ekipman veya sızdırmazlık elemanının bozulması",
        en: "Failure of rotating equipment or sealing elements",
      },
      energySource: {
        tr: "Dönme, basınç ve proses akışkanı",
        en: "Rotation, pressure and process fluid",
      },
      eventPath: {
        tr:
          "Kaplin, yatak, salmastra/keçe, gövde veya bağlantı bozulması parça ayrılması, sıcak/tehlikeli akışkan salımı ya da yangın riskine yol açabilir.",
        en:
          "Coupling, bearing, seal, casing or connection failure can cause separation, hot/hazardous fluid release or fire risk.",
      },
      exposedEntity: {
        tr: "Operatörler, bakım çalışanları ve çevre",
        en: "Operators, maintenance personnel and environment",
      },
      observation: {
        tr:
          "Fotoğrafta döner mekanik enerji ile proses akışkanını taşıyan pompa sistemi görülmektedir.",
        en:
          "A pump system transferring process fluid through rotating mechanical energy is visible.",
      },
      significance: {
        tr:
          "Kontrol programı kaplin koruyucusu, hizalama, titreşim/sıcaklık eğilimi, yataklama, salmastra/keçe sızıntısı, kavitasyon göstergeleri, temel-ankraj ve emiş/basma bağlantı yüklerini kapsamalıdır.",
        en:
          "The programme should cover coupling guards, alignment, vibration/temperature trends, bearings, seal leakage, cavitation indicators, foundation/anchors and suction/discharge nozzle loads.",
      },
      consequence: "permanent_disability",
      controlIntents: [
        "verify_periodic_control_status",
        "pump_integrity_maintenance",
      ],
    }],
  },
  {
    profileID: "process_line",
    priority: 80,
    equipmentFamily: {
      tr: "Proses hattı",
      en: "Process line",
    },
    include:
      /(?:process piping|chemical line|proses hatti|kimyasal hat|piping|boru hatti|pipeline|flanged connection|flansli baglanti|process valve|proses vanasi)/u,
    exclude: /(?:hydraulic|hidrolik|mobile equipment|is makinesi)/u,
    templates: [{
      conditionCode: "process_line_integrity_assurance",
      component: {
        tr:
          "Boru, flanş, vana, destek, conta, izolasyon ve sızdırmazlık sınırı",
        en:
          "Pipe, flange, valve, supports, gasket, insulation and containment boundary",
      },
      conditionText: {
        tr: "Proses hattında mekanik bütünlük ve sızdırmazlık programı",
        en:
          "Mechanical-integrity and containment programme for the process line",
      },
      mechanismCode: "mechanical_separation_release",
      mechanism: {
        tr: "Hat veya bağlantı bütünlüğünün bozulmasıyla akışkan salımı",
        en: "Fluid release following loss of line or connection integrity",
      },
      energySource: {
        tr: "Proses basıncı, sıcaklığı ve akışkan envanteri",
        en: "Process pressure, temperature and fluid inventory",
      },
      eventPath: {
        tr:
          "Boru, flanş, conta, vana veya destek bozulması sızıntı, püskürme, akışkan/termal temas ve çevresel yayılıma yol açabilir.",
        en:
          "Failure of pipe, flange, gasket, valve or support can cause leakage, spray, fluid/thermal contact and environmental spread.",
      },
      exposedEntity: {
        tr: "Operatörler, bakım çalışanları ve çevre",
        en: "Operators, maintenance personnel and environment",
      },
      observation: {
        tr:
          "Fotoğrafta proses akışkanını taşıyan boru, bağlantı veya vana bileşenleri görülmektedir.",
        en:
          "Piping, connection or valve components carrying process fluid are visible.",
      },
      significance: {
        tr:
          "Bütünlük programı akışkan tehlikesi ve proses koşuluna göre korozyon/erozyon devreleri, kalınlık ölçümleri, flanş-conta yönetimi, destek yükleri, vana/izolasyon işlevi ve sızıntı eğilimlerini kapsamalıdır.",
        en:
          "The integrity programme should cover corrosion/erosion circuits, thickness measurements, flange/gasket management, support loads, valve/isolation function and leak trends based on fluid hazards and process conditions.",
      },
      consequence: "permanent_disability",
      controlIntents: [
        "verify_periodic_control_status",
        "process_line_integrity_inspection",
      ],
    }],
  },
  {
    profileID: "furnace_and_thermal_process",
    priority: 78,
    equipmentFamily: {
      tr: "Fırın ve termal proses",
      en: "Furnace and thermal process",
    },
    include: /(?:furnace|firin|oven|kiln|kurutucu|dryer|burner|brulor)/u,
    templates: [{
      conditionCode: "combustion_safeguard_assurance",
      component: {
        tr:
          "Brülör, yakıt treni, alev gözetimi, havalandırma ve emniyet interlockları",
        en:
          "Burner, fuel train, flame supervision, ventilation and safety interlocks",
      },
      conditionText: {
        tr:
          "Fırın yakma ve aşırı sıcaklık emniyet fonksiyonlarının doğrulanması",
        en: "Verification of combustion and over-temperature safety functions",
      },
      mechanismCode: "fire_explosion",
      mechanism: {
        tr:
          "Yakıt birikimi, alev kaybı veya aşırı sıcaklığın sınırlandırılamaması",
        en:
          "Failure to control fuel accumulation, flame loss or over-temperature",
      },
      energySource: {
        tr: "Yakıt, ateşleme ve termal enerji",
        en: "Fuel, ignition and thermal energy",
      },
      eventPath: {
        tr:
          "Yakıt kesme, purge, alev gözetimi, hava-yakıt oranı veya sıcaklık limitinin çalışmaması yangın, patlama ya da sıcak malzeme salımına yol açabilir.",
        en:
          "Failure of fuel shutoff, purge, flame supervision, air-fuel ratio or temperature limits can cause fire, explosion or hot-material release.",
      },
      exposedEntity: {
        tr: "Operatörler, bakım çalışanları ve tesis",
        en: "Operators, maintenance personnel and plant",
      },
      observation: {
        tr:
          "Fotoğrafta yakma veya yüksek sıcaklıkla proses yürüten termal ekipman görülmektedir.",
        en:
          "Thermal equipment operating through combustion or elevated temperature is visible.",
      },
      significance: {
        tr:
          "Başlatma-durdurma sıralaması, purge, alev dedektörü, çift blok/boşaltma veya uygulanabilir yakıt izolasyonu, basınç limitleri, aşırı sıcaklık kesmesi ve acil durdurma kayıtlı fonksiyon testleriyle doğrulanmalıdır.",
        en:
          "Start/stop sequencing, purge, flame detection, applicable fuel isolation, pressure limits, high-temperature trips and emergency shutdown should be verified by recorded functional tests.",
      },
      consequence: "multiple_fatality_major_environmental",
      controlIntents: [
        "verify_periodic_control_status",
        "combustion_safeguard_function_test",
      ],
    }],
  },
  {
    profileID: "tire_inflation",
    priority: 76,
    equipmentFamily: {
      tr: "Lastik şişirme ekipmanı",
      en: "Tyre-inflation equipment",
    },
    include:
      /(?:tire inflation|tyre inflation|lastik sisirme|jant lastik|wheel rim|lastik servis)/u,
    templates: [{
      conditionCode: "tire_inflation_assurance",
      component: {
        tr:
          "Lastik-jant grubu, şişirme kafesi, hortum, manometre ve uzaktan kumanda",
        en: "Tyre-rim assembly, restraint cage, hose, gauge and remote control",
      },
      conditionText: {
        tr: "Lastik şişirmede patlama ve fırlama enerjisi kontrolleri",
        en: "Burst and projectile-energy controls for tyre inflation",
      },
      mechanismCode: "mechanical_separation_release",
      mechanism: {
        tr: "Basınçlı lastik/jant bileşeninin ani ayrılması veya patlaması",
        en: "Sudden separation or burst of a pressurised tyre/rim component",
      },
      energySource: {
        tr: "Sıkıştırılmış hava ve lastik/jantta depolanan enerji",
        en: "Compressed air and energy stored in the tyre/rim",
      },
      eventPath: {
        tr:
          "Uyumsuz, hasarlı veya yanlış monte edilmiş lastik-jant grubu şişirme sırasında ayrılarak parçaları yüksek enerjiyle fırlatabilir.",
        en:
          "An incompatible, damaged or incorrectly assembled tyre/rim can separate during inflation and project components at high energy.",
      },
      exposedEntity: {
        tr: "Lastik servis çalışanları ve yakındaki kişiler",
        en: "Tyre-service personnel and nearby persons",
      },
      observation: {
        tr:
          "Fotoğrafta lastik/jant montajı veya basınçlı şişirme işiyle ilişkili ekipman görülmektedir.",
        en:
          "Equipment associated with tyre/rim assembly or pressurised inflation is visible.",
      },
      significance: {
        tr:
          "Uyumluluk ve hasar kontrolü, üretici basınç limiti, kalibre manometre, klipsli uzatma hortumu, uzaktan şişirme, çalışanı fırlama hattından çıkarma ve gerekli durumda uygun tutma kafesi birlikte uygulanmalıdır.",
        en:
          "Compatibility/damage checks, manufacturer pressure limits, calibrated gauge, clip-on extension hose, remote inflation, exclusion from the trajectory and a suitable restraint cage where required should be applied together.",
      },
      consequence: "single_fatality",
      controlIntents: [
        "verify_periodic_control_status",
        "tire_inflation_safety_control",
      ],
    }],
  },
  {
    profileID: "chemical_material_management",
    priority: 74,
    equipmentFamily: {
      tr: "Kimyasal madde yönetimi",
      en: "Chemical-material management",
    },
    include:
      /(?:chemical container|kimyasal kap|chemical drum|kimyasal varil|\bibc\b|\breagent\b|\bsolvent\b|\bacid\b|(?:^| )asit(?: |$)|\balkali\b|(?:^| )baz(?: |$)|chemical storage|kimyasal depolama)/u,
    templates: [{
      conditionCode: "chemical_information_storage_assurance",
      component: {
        tr:
          "Kimyasal envanter, etiket/SDS, uyumluluk, depolama ve ikincil tutma",
        en:
          "Chemical inventory, label/SDS, compatibility, storage and secondary containment",
      },
      conditionText: {
        tr: "Kimyasal bilgi, uyumluluk ve depolama kontrollerinin doğrulanması",
        en:
          "Verification of chemical information, compatibility and storage controls",
      },
      mechanismCode: "chemical_contact_release",
      mechanism: {
        tr:
          "Kimyasalın yanlış tanımlanması, uyumsuz teması veya kontrolsüz yayılımı",
        en:
          "Chemical misidentification, incompatible contact or uncontrolled spread",
      },
      energySource: {
        tr: "Kimyasal reaktivite, toksisite, yanıcılık ve kap içeriği",
        en:
          "Chemical reactivity, toxicity, flammability and container inventory",
      },
      eventPath: {
        tr:
          "Kimyasal bilgi, ayırma veya tutma kontrolünün etkisizliği döküntü, reaksiyon, yangın ya da çalışan maruziyetine yol açabilir.",
        en:
          "Ineffective chemical-information, segregation or containment controls can lead to spill, reaction, fire or worker exposure.",
      },
      exposedEntity: {
        tr: "Kimyasal kullanan çalışanlar, acil müdahale ekibi ve çevre",
        en: "Chemical users, emergency responders and environment",
      },
      observation: {
        tr:
          "Fotoğrafta kimyasal içerebilecek kaplar veya kimyasal depolama/kullanım alanı görülmektedir.",
        en:
          "Containers or an area used for chemical storage/handling are visible.",
      },
      significance: {
        tr:
          "Kontrol; güncel kimyasal envanter, kap etiketiyle SDS eşleşmesi, Türkçe ve erişilebilir SDS, maruziyet/ilk yardım bilgisi, uyumsuz kimyasalların ayrılması, uygun dolap-havalandırma ve ikincil tutma kapasitesini kapsamalıdır. Bu kayıt, SDS'nin mevcut veya eksik olduğu yönünde bir uygunluk iddiası içermez.",
        en:
          "Controls should cover current inventory, container-to-SDS matching, accessible SDS, exposure/first-aid information, incompatible segregation, suitable cabinets/ventilation and secondary containment. This record makes no compliance claim about whether an SDS is available or missing.",
      },
      consequence: "permanent_disability",
      controlIntents: [
        "verify_chemical_inventory_controls",
        "chemical_sds_storage_control",
      ],
    }],
  },
  {
    profileID: "rail_system",
    priority: 72,
    equipmentFamily: {
      tr: "Raylı sistem",
      en: "Rail system",
    },
    include:
      /(?:^| )(?:rail system|rayli sistem|railway|demiryolu|locomotive|lokomotif|train|tren|rail track|ray hatti|tram|metro)(?: |$)/u,
    templates: [{
      conditionCode: "rail_system_integrity_assurance",
      component: {
        tr:
          "Ray, makas, bağlantı, tekerlek/aks, fren, sinyal ve geçiş korumaları",
        en:
          "Rail, points, fastenings, wheel/axle, brakes, signalling and crossing protection",
      },
      conditionText: {
        tr: "Raylı sistem altyapısı ve araç emniyet kontrolleri",
        en: "Infrastructure and vehicle safety checks for the rail system",
      },
      mechanismCode: "vehicle_equipment_strike",
      mechanism: {
        tr: "Hat, araç, fren veya sinyal bütünlüğünün kaybı",
        en: "Loss of track, vehicle, braking or signalling integrity",
      },
      energySource: {
        tr: "Raylı araç hareketi, yük ve elektrik/mekanik enerji",
        en: "Rail-vehicle motion, load and electrical/mechanical energy",
      },
      eventPath: {
        tr:
          "Ray-makas-bağlantı, tekerlek/aks, fren veya sinyal bozulması çarpışma, raydan çıkma ya da geçiş bölgesinde ezilmeye yol açabilir.",
        en:
          "Track/points/fastening, wheel/axle, brake or signalling degradation can lead to collision, derailment or crushing at crossings.",
      },
      exposedEntity: {
        tr: "Araç personeli, yolcular ve hat çevresindeki çalışanlar",
        en: "Vehicle personnel, passengers and workers near the line",
      },
      observation: {
        tr:
          "Fotoğrafta raylı araç, hat veya raylı hareket altyapısı görülmektedir.",
        en: "A rail vehicle, track or rail-motion infrastructure is visible.",
      },
      significance: {
        tr:
          "Periyodik kontrol; ray geometrisi ve bağlantıları, makaslar, tekerlek/aks, fren ve tutma sistemleri, sinyal/iletişim, geçit korumaları ve bakım sırasında enerji-hareket izolasyonunu kapsamalıdır.",
        en:
          "Periodic inspection should cover track geometry/fastenings, points, wheel/axle, braking/restraint, signalling/communications, crossing protection and motion/energy isolation during maintenance.",
      },
      consequence: "multiple_fatality_major_environmental",
      controlIntents: [
        "verify_periodic_control_status",
        "rail_system_safety_inspection",
      ],
    }],
  },
  {
    profileID: "electrical_distribution",
    priority: 68,
    equipmentFamily: {
      tr: "Elektrik dağıtım ekipmanı",
      en: "Electrical distribution equipment",
    },
    include:
      /(?:electrical panel|elektrik panosu|switchgear|mcc|motor control center|trafo|transformer|distribution board|dagitim panosu)/u,
    templates: [{
      conditionCode: "electrical_system_assurance",
      component: {
        tr:
          "Pano/mahfaza, koruma düzeni, topraklama, termal durum ve izolasyon",
        en:
          "Enclosure, protection scheme, earthing, thermal condition and isolation",
      },
      conditionText: {
        tr: "Elektrik dağıtım ekipmanında koruma ve periyodik test programı",
        en:
          "Protection and periodic-test programme for electrical distribution equipment",
      },
      mechanismCode: "electrical_contact_arc",
      mechanism: {
        tr:
          "İzolasyon veya koruma düzeninin bozulmasıyla elektrik çarpması/ark",
        en:
          "Electric shock or arc following insulation/protection-system failure",
      },
      energySource: {
        tr: "Elektrik gerilimi ve ark enerjisi",
        en: "Electrical voltage and arc energy",
      },
      eventPath: {
        tr:
          "İzolasyon, topraklama, aşırı akım/kaçak koruması veya bağlantı bütünlüğündeki bozulma temas, ark ve yangına yol açabilir.",
        en:
          "Degradation of insulation, earthing, overcurrent/residual protection or connections can cause contact, arc and fire.",
      },
      exposedEntity: {
        tr: "Elektrik çalışanları, operatörler ve tesis",
        en: "Electrical personnel, operators and plant",
      },
      observation: {
        tr:
          "Fotoğrafta elektrik dağıtımı veya motor kontrolü yapan pano/şalt ekipmanı görülmektedir.",
        en:
          "Panel or switchgear equipment used for electrical distribution or motor control is visible.",
      },
      significance: {
        tr:
          "Kontrol programı pano bütünlüğü ve açıklıkları, bağlantı torku/termal tarama, koruma rölesi ve kaçak akım testleri, topraklama sürekliliği, izolasyon ve LOTO düzenini ekipmanın gerilim/ark riskine göre kapsamalıdır.",
        en:
          "The programme should cover enclosure integrity, connection torque/thermal scanning, protective-device testing, earth continuity, insulation and LOTO based on voltage and arc risk.",
      },
      consequence: "single_fatality",
      controlIntents: [
        "verify_electrical_protection_status",
        "electrical_periodic_test_program",
      ],
    }],
  },
  {
    profileID: "workshop_system",
    priority: 20,
    equipmentFamily: {
      tr: "Atölye çalışma sistemi",
      en: "Workshop work system",
    },
    include: /(?:workshop|atolye|maintenance shop|bakim atoly)/u,
    templates: [{
      conditionCode: "workshop_system_assurance",
      component: {
        tr:
          "Makine yerleşimi, enerji izolasyonu, geçişler, yangın ve acil durum düzeni",
        en:
          "Machine layout, energy isolation, access, fire and emergency arrangements",
      },
      conditionText: {
        tr: "Atölye genelinde makine, enerji ve acil durum denetimi",
        en: "Workshop-wide machinery, energy and emergency review",
      },
      mechanismCode: "other_visible_physical",
      mechanism: {
        tr:
          "Birden fazla ekipman ve iş akışındaki ortak kontrollerin yetersiz kalması",
        en:
          "Failure of shared controls across multiple equipment and workflows",
      },
      energySource: {
        tr: "Mekanik, elektrik, basınç, sıcak iş ve malzeme hareketi",
        en:
          "Mechanical, electrical, pressure, hot-work and material-handling energies",
      },
      eventPath: {
        tr:
          "Yerleşim, geçiş, enerji izolasyonu veya acil durum düzenindeki sistematik zayıflık farklı işlerde tekrarlayan maruziyetlere yol açabilir.",
        en:
          "Systemic weakness in layout, access, energy isolation or emergency arrangements can create repeated exposures across tasks.",
      },
      exposedEntity: {
        tr: "Atölye çalışanları, bakım personeli ve ziyaretçiler",
        en: "Workshop staff, maintenance personnel and visitors",
      },
      observation: {
        tr:
          "Fotoğrafta birden fazla ekipman ve iş faaliyetini barındıran atölye ortamı görülmektedir.",
        en:
          "A workshop environment containing multiple equipment and work activities is visible.",
      },
      significance: {
        tr:
          "Ekipman bazlı kontrollerin yanında yerleşim, güvenli geçiş, LOTO standardı, kaldırma/taşıma, sıcak iş, kimyasal yönetimi, elektrik, yangın ve acil durum erişimi ortak bir atölye denetim planında birleştirilmelidir.",
        en:
          "Equipment-specific controls should be integrated with layout, access, LOTO, lifting/handling, hot work, chemicals, electrical, fire and emergency access in a workshop audit plan.",
      },
      consequence: "serious_reversible",
      controlIntents: [
        "verify_periodic_control_status",
        "workshop_system_audit",
      ],
    }],
  },
];

export function resolveAssetAssuranceProfiles(
  inventory: AssetInventoryItem[],
): ResolvedAssetAssuranceProfile[] {
  return CATALOG.map((profile) => ({
    profile,
    items: inventory.filter((item) => {
      const context = itemContext(item);
      return profile.include.test(context) &&
        !(profile.exclude?.test(context) ?? false);
    }),
  })).filter((entry) => entry.items.length > 0).sort((left, right) =>
    right.profile.priority - left.profile.priority
  );
}
