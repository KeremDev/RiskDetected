import type {
  Criticality,
  HardRejection,
  ModuleCoverage,
  NormalizedCandidate,
  ProviderPhotoOutput,
  RoutedItem,
  RoutingLedgerEntry,
  SafetyItemClass,
  V4ModuleID,
} from "./contracts.ts";
import {
  assuranceTopic,
  assuranceTopicForModule,
} from "./assurance-topic-catalog.ts";
import { controlPlaybook, correctiveSteps } from "./control-playbook.ts";
import {
  assuranceMeasures,
  moduleConsequenceRank,
  playbookForModule,
  playbookForTopic,
  referencesTextFor,
  topicConsequenceRank,
} from "./assurance-playbook.ts";

const SCORES = {
  probability: [0.2, 0.5, 1, 3, 6, 10],
  frequency: [0.5, 1, 2, 3, 6, 10],
  severity: [1, 3, 7, 15, 40, 100],
} as const;

const SECTOR_F: Record<string, number | null> = {
  general: null,
  construction: 3,
  manufacturing: 6,
  mining: 6,
  energy: 2,
  office: 6,
  logistics_warehouse: 6,
  chemical_laboratory: 3,
  healthcare: 10,
  food_production: 6,
  agriculture_livestock: 3,
  retail: 6,
  municipal_field_services: 3,
  education: 6,
  hospitality: 10,
};

const CONTROL_CATALOG: Record<string, string> = {
  falls_falling_objects:
    "Erişimi durdurun; açık kenar ve düşen cisim yolunu uygun mühendislik tipi koruma ile güvenli hale getirin.",
  work_at_height:
    "Yüksekte çalışmayı durdurun; platform, erişim ve toplu düşmeye karşı korumayı olay yolunu kesecek biçimde tamamlayın.",
  energy:
    "Tehlikeli enerjiye erişimi kesin; kaynağı izole edin, istem dışı yeniden enerjilenmeyi önleyin ve doğrulayın.",
  electrical:
    "Enerjili bölgeye erişimi engelleyin; uygun kapatma, izolasyon ve yetkili elektrik kontrolü sağlayın.",
  vehicles_mobile_equipment:
    "Yaya ile araç hareketini fiziksel olarak ayırın; görüş ve geçiş çakışmasını ortadan kaldırın.",
  logistics:
    "Yaya ve ekipman yollarını fiziksel olarak ayırın; kör nokta ve kontrolsüz geçişleri giderin.",
  machinery:
    "Tehlikeli hareketle teması mühendislik koruması ve güvenli durdurma düzeniyle engelleyin.",
  lifting:
    "Yük altı ve salınım alanını boşaltın; kaldırma düzenini uygun ekipman ve kontrollü operasyonla güvenli hale getirin.",
  fire_explosion_release:
    "Tutuşturucu kaynakları ve yanıcı yükü ayırın; salımın yayılmasını ve erişimi kontrol altına alın.",
  process_integrity:
    "Prosesi güvenli duruma alın; görünen kaçak veya bütünlük kaybı yolunu izole edip yetkili inceleme yapın.",
  chemical:
    "Teması ve yayılımı durdurun; kaynağı güvenli biçimde kapatın, alanı sınırlandırın ve uygun müdahale sağlayın.",
  access_egress:
    "Geçişi açın ve erişim yolunu fiziksel engel, düşme ve çarpma risklerinden arındırın.",
  housekeeping_physical_contact:
    "Temas veya takılma yolunu ortadan kaldırın; malzemeyi güvenli biçimde sabitleyin ya da kaldırın.",
  excavation:
    "Kazıya erişimi durdurun; kenar, göçük ve giriş düzenini mühendislik önlemleriyle güvenli hale getirin.",
  confined_space:
    "Girişi durdurun; izolasyon, atmosfer, gözetim ve kurtarma güvenceleri doğrulanmadan alana girmeyin.",
  hot_work:
    "Sıcak çalışmayı durdurun; yanıcıları ayırın ve yangın önleme düzenini sahada doğrulayın.",
  combustible_dust:
    "Toz yayılımını ve tutuşturma kaynaklarını kontrol altına alın; birikimi güvenli yöntemle giderin.",
  biosecurity:
    "Maruziyet yolunu sınırlandırın; uygun biyogüvenlik ve dekontaminasyon kontrollerini uygulayın.",
  people_exposure:
    "Kişinin tehlike yoluna erişimini durdurun ve kaynağı fiziksel olarak kontrol altına alın.",
};

/**
 * A module says more than the mechanism only where its wording adds a real
 * detail. Everything else now comes from the mechanism playbook, keyed on the
 * causal path rather than on which routing bucket the candidate landed in.
 */
const MODULE_ROOT_CAUSE_OVERRIDE: Record<
  string,
  { mechanisms: string[]; text: string }
> = {
  electrical: {
    mechanisms: ["electrical_contact_arc"],
    text:
      "Hat ve ıslak yüzey arasındaki fiziksel ayrım güvenli temas yolunu koruyacak biçimde sağlanmamıştır.",
  },
  access_egress: {
    mechanisms: ["fall_same_level"],
    text:
      "Çalışma alanı yerleşimi, güvenli ve kesintisiz bir geçiş yolu korunacak biçimde düzenlenmemiştir.",
  },
  housekeeping_physical_contact: {
    mechanisms: ["fall_same_level"],
    text:
      "Malzeme yerleşimi ve yüzey koşulları güvenli yürüme alanı korunacak biçimde düzenlenmemiştir.",
  },
  people_exposure: {
    mechanisms: ["ergonomic_overexertion"],
    text:
      "Malzeme taşıma yöntemi, çalışanın görüş ve güvenli hareket alanını koruyacak biçimde düzenlenmemiştir.",
  },
};

/**
 * Module ids are routing keys, not category names. The live report showed
 * "work_at_height", "housekeeping_physical_contact" and "people_exposure" to
 * the reader in English snake_case.
 */
const MODULE_CATEGORY_TR: Record<string, string> = {
  people_exposure: "Çalışan maruziyeti",
  falls_falling_objects: "Düşme ve düşen cisim",
  energy: "Tehlikeli enerji",
  vehicles_mobile_equipment: "Araç ve mobil ekipman",
  access_egress: "Erişim ve kaçış yolları",
  fire_explosion_release: "Yangın, patlama ve salım",
  housekeeping_physical_contact: "Düzen ve fiziksel temas",
  work_at_height: "Yüksekte çalışma",
  process_integrity: "Proses bütünlüğü",
  lifting: "Kaldırma operasyonları",
  machinery: "Makine güvenliği",
  logistics: "Lojistik ve istif",
  electrical: "Elektrik güvenliği",
  confined_space: "Kapalı alan",
  hot_work: "Sıcak çalışma",
  excavation: "Kazı ve şev",
  chemical: "Kimyasal güvenlik",
  combustible_dust: "Yanıcı toz",
  biosecurity: "Biyogüvenlik",
};

function categoryLabel(moduleID: string): string {
  return MODULE_CATEGORY_TR[moduleID] ?? "Genel fiziksel güvenlik";
}

function cleanText(value: string, fallback: string): string {
  const cleaned = value
    .replace(
      /\b(?:fotoğraf|görsel|resim)\s*\d+\s*(?:'?[dt][ae])?\b/giu,
      "görüntüde",
    )
    .replace(/\b\d+\s*(?:numaralı|nolu)\b/giu, "")
    // The scene graph writes person_2, with an underscore. The generic person
    // rule already allowed one; these two did not, so "person_2'de" missed them,
    // fell through to the bare-id rule and published "çalışan'de".
    .replace(
      /(?:[İi]şçi|[Çç]alışan|[Pp]ersonel|[Ww]orker|[Pp]erson)[\s_-]*(?:[Pp])?\d+\s*['’](?:nin|nın|nun|nün|in|ın|un|ün)/gu,
      "çalışanın",
    )
    .replace(
      /(?:[İi]şçi|[Çç]alışan|[Pp]ersonel|[Ww]orker|[Pp]erson)[\s_-]*(?:[Pp])?\d+\s*['’](?:de|da|dan|den)/gu,
      "çalışanda",
    )
    .replace(
      /(?:[İi]şçi|[Çç]alışan|[Pp]ersonel|[Ww]orker|[Pp]erson)[\s_-]*(?:[Pp])?\d+/gu,
      "çalışan",
    )
    // Scene-graph ids arrive as person_2 / asset_3 and were published inside
    // titles. Parentheses left behind by the substitution are cleared too.
    .replace(/\b(?:asset|entity|equipment|region|zone)[\s_-]*\d+\b/gu, "")
    .replace(/\(\s*\)/g, "")
    .replace(/\bP\d+\s*['’](?:de|da|dan|den|nin|nın|nun|nün)\b/gu, "çalışanda")
    .replace(/\bP\d+\b/gu, "çalışan")
    // Any apostrophe suffix orphaned by an identifier substitution.
    .replace(/\bçalışan\s*['’](?:de|da|dan|den|nin|nın|nun|nün)\b/gu, "çalışanda")
    .replace(/\bkötü düzenleme\b/giu, "düzensiz malzeme yerleşimi")
    .replace(/\s+/g, " ").trim();
  return (cleaned || fallback).slice(0, 900);
}

// Rebar appears in two different hazards: protruding starter bars a person can
// be impaled on, and lengths of rebar lying among site clutter you trip over.
// Matching the noun alone put a muddy walkway under the title "Açıkta kalan
// sivri filiz veya donatı uçları" with mechanism sharp_edge_contact. The event
// path already separates them: one ends in saplanma, the other in a same-level
// fall.
function impalementIntent(candidate: NormalizedCandidate): boolean {
  const path = `${candidate.event_path.source} ${
    candidate.event_path.contact_or_failure
  } ${candidate.event_path.consequence}`.toLocaleLowerCase("tr-TR");
  if (
    /(?:aynı seviyede düşme|ayni seviyede dusme|takıl|takil|kayma|slip|trip)/u
      .test(path)
  ) return false;
  return /(?:saplan|delin|batma|kesik|yırtıl|yirtil|impale|puncture|laceration)/u
    .test(path) ||
    /(?:çıkıntı|cikinti|sivri|keskin|protrud|sharp)/u.test(path);
}

function conciseTitle(candidate: NormalizedCandidate): string {
  const context = scoringContext(candidate);
  // A missing mid-rail and a completely unprotected roof edge both resolved to
  // one fixed string, so the report published the same title twice at FK 1440
  // for two different hazards.
  if (
    candidate.condition_code === "visible_structural_absence" &&
    ["falls_falling_objects", "work_at_height", "people_exposure"].includes(
      candidate.module_id,
    )
  ) {
    if (
      /(?:kemer|harness|lanyard|yasam hatti|yaşam hattı|ankraj|dusme durdurma|düşme durdurma|kisisel dusme|kişisel düşme)/u
        .test(context)
    ) {
      return "Yüksekte çalışanda düşme durdurma sistemi bulunmaması";
    }
    if (/(?:ara korkuluk|orta korkuluk|midrail|mid rail)/u.test(context)) {
      return "Korkuluk sisteminde ara korkuluk eksikliği";
    }
    if (/(?:etek tahtasi|etek tahtası|toeboard|toe board)/u.test(context)) {
      return "Korkuluk sisteminde etek tahtası eksikliği";
    }
    if (/(?:cati|çatı|roof)/u.test(context)) {
      return "Çatı kenarında düşmeye karşı koruma bulunmaması";
    }
    if (/(?:iskele|scaffold)/u.test(context)) {
      return "İskele platformunda düşmeye karşı koruma eksikliği";
    }
    return "Çalışma kenarında düşmeye karşı koruma eksikliği";
  }
  if (candidate.condition_code === "electrical_identity_unresolved") {
    return "Su birikintisi yakınındaki hat veya kablonun elektriksel durumu";
  }
  if (
    candidate.module_id === "housekeeping_physical_contact" &&
    /(?:donatı|donati|filiz|rebar|sivri)/u.test(context) &&
    impalementIntent(candidate)
  ) return "Açıkta kalan sivri filiz veya donatı uçları";
  if (candidate.module_id === "housekeeping_physical_contact") {
    // This used to be one fixed string that always claimed a wet floor, so a
    // photo showing only cardboard on the ground was published as "ıslak
    // zeminde ... kayma riski" with no wet-surface evidence anywhere in it.
    const wet =
      /(?:ıslak|islak|kaygan|su birikinti|sıvı döküntü|sivi dokuntu|yağ döküntü|yag dokuntu|wet|slippery)/u
        .test(context);
    const clutter =
      /(?:dağınık|daginik|malzeme|karton|kablo|hortum|eşya|esya|atık|atik|engel)/u
        .test(context);
    // Rocky, uneven ground on an excavation site was published under the
    // clutter title, so a warehouse floor full of cardboard and a boulder field
    // read as the same finding and the uniqueness pass hid it behind a "(2)".
    const uneven =
      /(?:engebeli|kayalık|kayalik|düzensiz zemin|duzensiz zemin|çukur|cukur|bozuk zemin|uneven|rocky)/u
        .test(context);
    if (wet && clutter) {
      return "Dağınık malzemeler ve ıslak zeminde takılma veya kayma riski";
    }
    if (wet) return "Islak veya kaygan zeminde kayma riski";
    if (clutter) return "Zemindeki dağınık malzemelerde takılma riski";
    if (uneven) return "Engebeli ve düzensiz zeminde takılma riski";
    // Neither pattern matched: the model's own label describes it better than
    // any canned string.
    return cleanText(candidate.normalized_label, "Zeminde takılma riski")
      .replace(/[.!?]+$/g, "");
  }
  // Three hooks each missing a latch produced three titles naming a side, and
  // the one that survived dedup told the reader only about the top hook.
  if (candidate.module_id === "lifting" && /(?:mandal|latch)/u.test(context)) {
    return "Vinç kancasında emniyet mandalı eksikliği";
  }
  if (candidate.module_id === "access_egress") {
    return "Güvenli geçiş yolunun dağınık malzemelerle engellenmesi";
  }
  if (
    candidate.module_id === "people_exposure" &&
    /(?:boru|uzun malzeme|taşı)/u.test(context)
  ) return "Uzun malzeme taşınırken görüş ve hareket alanının kısıtlanması";
  return cleanText(candidate.normalized_label, "Güvenlik koşulu").replace(
    /[.!?]+$/g,
    "",
  );
}

function titleFor(
  candidate: NormalizedCandidate,
  itemClass: SafetyItemClass,
): string {
  const raw = conciseTitle(candidate);
  if (itemClass === "assurance_requirement") {
    // The item class is already labelled in the report, so a "saha teyidi" /
    // "saha güvencesi gerekli" suffix on every title was pure repetition -- and
    // it pushed the distinguishing part of the name past the truncation point.
    return raw.slice(0, 180);
  }
  return raw.charAt(0).toLocaleUpperCase("tr-TR") + raw.slice(1, 180);
}

function descriptionFor(
  candidate: NormalizedCandidate,
  itemClass: SafetyItemClass,
): string {
  const cues = candidate.affirmative_cues.map((cue) => cleanText(cue, ""))
    .filter(Boolean).slice(0, 3).join("; ");
  if (itemClass === "assurance_requirement") {
    return cleanText(
      `Görünen varlıkla ilgili ${
        candidate.normalized_label.toLocaleLowerCase("tr-TR")
      } konusu belge, ölçüm, test veya iç bütünlük doğrulaması gerektiriyor.`,
      "Saha doğrulaması gerekli.",
    );
  }
  if (itemClass === "verification_request") {
    if (candidate.condition_code === "electrical_identity_unresolved") {
      return cleanText(
        `${endSentence(cues)} Görünen hattın elektrik kablosu olup olmadığı ve enerji durumu görüntüden kesinleştirilemiyor.`,
        "Görünen hattın niteliği ve enerji durumu sahada doğrulanmalı.",
      );
    }
    return cleanText(
      `${
        endSentence(cues || "Kritik geometri kısmen görünür")
      } Görünen fiziksel koşulun sürekliliği ve erişim ilişkisi sahada doğrulanmalı.`,
      "Kritik koşul sahada doğrulanmalı.",
    );
  }
  return sentenceCase(cleanText(
    `${endSentence(cues)} Bu durum ${
      candidate.event_path.contact_or_failure.toLocaleLowerCase("tr-TR")
    } yoluyla ${
      candidate.event_path.consequence.toLocaleLowerCase("tr-TR")
    } sonucuna neden olabilir.`,
    candidate.normalized_label,
  ));
}

// Observed findings open with the provider's own cue text, which arrives
// lowercase, so every scored finding in the report started mid-sentence while
// the assurance items around it started with a capital.
function sentenceCase(value: string): string {
  if (!value) return value;
  return value.charAt(0).toLocaleUpperCase("tr-TR") + value.slice(1);
}

// Cue text sometimes already ends in a full stop, and the sentence template
// appended a second one: "...görülmektedir.. Bu durum ...".
function endSentence(value: string): string {
  const trimmed = value.trim().replace(/[.;,\s]+$/u, "");
  return trimmed ? `${trimmed}.` : "";
}

// The control catalog is keyed by module, so a person falling through a missing
// mid-rail was told to secure the "düşen cisim yolu". Split the falls module by
// the mechanism that was actually resolved.
// Only the falls module was split by mechanism here, so a missing safety pin, a
// corroded coupling and a cracked hose -- three different failures in one
// report -- all published CONTROL_CATALOG["process_integrity"] word for word.
// The mechanism playbook already carries a line per mechanism; the module
// catalog stays as the fallback for anything it does not cover.
function controlTextFor(candidate: NormalizedCandidate): string {
  const mechanism = mechanismCode(candidate);
  if (mechanism !== "other_visible_physical") {
    return controlPlaybook(mechanism).control;
  }
  return CONTROL_CATALOG[candidate.module_id] ??
    controlPlaybook(mechanism).control;
}

function verificationAction(candidate: NormalizedCandidate): string {
  if (candidate.condition_code === "electrical_identity_unresolved") {
    return "Alanı geçici olarak sınırlandırın; görünen hattın niteliğini, bağlantısını ve enerji durumunu yetkili kişiyle sahada doğrulayın.";
  }
  if (
    ["falls_falling_objects", "work_at_height"].includes(candidate.module_id)
  ) {
    return "Kenar çevresindeki erişimi sınırlandırın; toplu korumanın sürekliliğini ve çalışanla olay yolu ilişkisini sahada doğrulayın.";
  }
  return "Kritik fiziksel koşulu farklı açıdan ve sahadaki erişim ilişkisiyle doğrulayın; doğrulanana kadar maruziyeti sınırlandırın.";
}

// Root cause used to be keyed by module over six of the nineteen modules, so
// material falling out of an excavator bucket was given the guardrail sentence
// "Görünen çalışma kenarında toplu düşmeye karşı koruma sürekliliği
// sağlanmamıştır" -- it shares a module with edge protection. Mechanism is the
// causal axis; the module catalog stays only as a more specific override where
// it genuinely says more.
function rootCauseFor(
  candidate: NormalizedCandidate,
  itemClass: SafetyItemClass,
): string {
  if (itemClass !== "observed_finding") return "";
  const mechanism = mechanismCode(candidate);
  const moduleSpecific = MODULE_ROOT_CAUSE_OVERRIDE[candidate.module_id];
  return cleanText(
    moduleSpecific?.mechanisms.includes(mechanism)
      ? moduleSpecific.text
      : controlPlaybook(mechanism).rootCause,
    "",
  );
}

function measuresFor(
  candidate: NormalizedCandidate,
  itemClass: SafetyItemClass,
): RoutedItem["recommended_measures"] {
  // An assurance_requirement returned an empty measure list, so the report told
  // the reader a tank's internal integrity could not be confirmed from the photo
  // and then offered no step at all. Unscored items now carry the deterministic
  // field playbook for their topic.
  if (itemClass === "assurance_requirement") {
    return assuranceMeasures(
      playbookForTopic(assuranceTopic(candidate).id),
      "Saha doğrulama adımları",
    );
  }
  if (itemClass === "verification_request") {
    const playbook = playbookForModule(candidate.module_id);
    return [{
      kind: "corrective",
      title: "Geçici koruma",
      text: verificationAction(candidate),
    }, {
      kind: "corrective",
      title: "Saha doğrulama adımları",
      text: playbook.steps.map((step, index) => `${index + 1}. ${step}`).join(
        "\n",
      ),
    }, {
      kind: "preventive",
      title: "Kalıcı önleme",
      text: playbook.preventive,
    }];
  }
  if (itemClass !== "observed_finding") return [];
  const playbook = controlPlaybook(mechanismCode(candidate));
  return [{
    kind: "corrective",
    title: "Acil düzeltme",
    text: correctiveSteps(playbook),
  }, {
    kind: "preventive",
    title: "Kalıcı önleme",
    text: playbook.preventive,
  }];
}

// v4 hard-coded an empty references_text for every item even on profiles whose
// jurisdiction policy allows references. The list is curated in code, never taken
// from the provider, and stays empty on any profile that does not allow it.
function referencesFor(
  candidate: NormalizedCandidate,
  itemClass: SafetyItemClass,
  policy: string | null,
): string {
  const playbook = itemClass === "assurance_requirement"
    ? playbookForTopic(assuranceTopic(candidate).id)
    : playbookForModule(candidate.module_id);
  return referencesTextFor(playbook, policy);
}

function severity(criticality: Criticality): number {
  // Fine-Kinney: 40 death, 15 permanent disability, 7 serious but reversible,
  // 3 first aid. "ordinary" returned 7 as well, so a trip hazard scored the
  // same severity as an impalement and the two were indistinguishable in the
  // report.
  return criticality === "fatal"
    ? 40
    : criticality === "permanent"
    ? 15
    : criticality === "serious"
    ? 7
    : 3;
}

function bands(fk: number, m5: number) {
  const fkBand = fk <= 70
    ? "low"
    : fk <= 200
    ? "medium"
    : fk <= 400
    ? "high"
    : "critical";
  const m5Band = m5 <= 4
    ? "low"
    : m5 <= 9
    ? "medium"
    : m5 <= 19
    ? "high"
    : "critical";
  return { fkBand, m5Band } as const;
}

function scoringContext(candidate: NormalizedCandidate): string {
  return `${candidate.normalized_label} ${candidate.module_id} ${
    candidate.affirmative_cues.join(" ")
  } ${candidate.event_path.source} ${candidate.event_path.contact_or_failure} ${candidate.event_path.consequence}`
    .toLocaleLowerCase("tr-TR");
}

// scoringContext folds module_id into the text it matches against. The module id
// `falls_falling_objects` literally contains "falling" and "object", so the
// falling-object test below matched every single candidate of that module and
// the fall_from_height branch was unreachable. A missing mid-rail was therefore
// scored as a falling object, which skipped the partial-barrier severity cap and
// published FK 720 / critical where FK 270 / high was correct. Mechanism has to
// be decided from the evidence alone, never from the module's own name.
function mechanismContext(candidate: NormalizedCandidate): string {
  return `${candidate.normalized_label} ${
    candidate.affirmative_cues.join(" ")
  } ${candidate.event_path.source} ${candidate.event_path.contact_or_failure} ${candidate.event_path.consequence}`
    .toLocaleLowerCase("tr-TR");
}

function mechanismCode(candidate: NormalizedCandidate): string {
  const context = mechanismContext(candidate);
  if (candidate.module_id === "work_at_height") return "fall_from_height";
  if (candidate.module_id === "falls_falling_objects") {
    // A person falling wins over a load falling when both read as present: the
    // person path carries the higher consequence and its own severity cap.
    if (
      /(?:kişinin düşmesi|kisinin dusmesi|yüksekten düşme|yuksekten dusme|çalışanın düşmesi|calisanin dusmesi|person fall|fall from height)/u
        .test(context)
    ) return "fall_from_height";
    // "nesne düşmesi ... aşağıdaki kişiye çarpma" resolved to fall_from_height
    // because the list wanted the exact words "cisim" or "düşen": a missing
    // toeboard dropping material on someone below was filed as a person falling.
    return /(?:düşen|dusen|falling|üstten|yukarıdan|cisim|object)/u.test(context) ||
        /(?:nesne|malzeme|yük|taş|tas|parça|parca|alet|ekipman|moloz|kepçe|kepce)[^.]{0,24}(?:düş|dus|kay|dök|dok|devril)/u
          .test(context) ||
        /(?:etek tahtası|etek tahtasi|toeboard|toe board)/u.test(context)
      ? "falling_object"
      : "fall_from_height";
  }
  if (
    ["vehicles_mobile_equipment", "logistics"].includes(candidate.module_id)
  ) {
    return "vehicle_equipment_strike";
  }
  if (candidate.module_id === "machinery") return "caught_in_pinch_shear";
  if (candidate.module_id === "lifting") return "falling_object";
  if (candidate.module_id === "electrical") return "electrical_contact_arc";
  if (candidate.module_id === "fire_explosion_release") return "fire_explosion";
  if (candidate.module_id === "excavation") {
    return "excavation_collapse_rockfall";
  }
  if (candidate.module_id === "chemical") return "chemical_contact_release";
  if (candidate.module_id === "hot_work") {
    return /(?:yangın|yangin|patlama|fire|explosion|yanıcı|yanici)/u.test(
        context,
      )
      ? "fire_explosion"
      : "thermal_contact";
  }
  if (candidate.module_id === "process_integrity") {
    // The hydraulic cap of 15 exists for fluid injected into tissue. A coupling
    // letting go, a hose whipping or a line bursting is stored energy released
    // as a whole and belongs at 40. Matching the phrase "basınçlı akışkan"
    // alone put the fatal coupling-separation candidate under the lower cap
    // while the two lesser corrosion findings beside it kept the higher one.
    const path = `${candidate.event_path.source} ${
      candidate.event_path.contact_or_failure
    } ${candidate.event_path.consequence}`.toLocaleLowerCase("tr-TR");
    if (
      /(?:ayrıl|ayril|kopma|kopar|fırla|firla|savrul|kamçı|kamci|whip|patla|burst|separat)/u
        .test(path)
    ) return "mechanical_separation_release";
    if (
      /(?:enjeksiyon|injection|deri altı|deri alti|dokuya|jet|püskür|puskur)/u
        .test(path)
    ) return "hydraulic_pneumatic_release";
    return /(?:hidrolik|hydraulic|pnömatik|pneumatic|basınçlı akışkan)/u.test(
        context,
      )
      ? "hydraulic_pneumatic_release"
      : "mechanical_separation_release";
  }
  if (candidate.module_id === "energy") {
    if (/(?:elektr|electric|pano|kablo|gerilim|volt|arc)/u.test(context)) {
      return "electrical_contact_arc";
    }
    // High-pressure hydraulic lines arrive under the energy module and fell to
    // other_visible_physical, which capped a fluid injection injury at 15 and
    // gave it the generic control text.
    if (
      /(?:hidrolik|hydraulic|pnömatik|pnomatik|pneumatic|basınçlı|basincli|hortum|enjeksiyon|injection)/u
        .test(context)
    ) return "hydraulic_pneumatic_release";
    return "other_visible_physical";
  }
  if (candidate.module_id === "access_egress") return "fall_same_level";
  if (candidate.module_id === "housekeeping_physical_contact") {
    if (
      /(?:sivri|keskin|sharp|çıkıntı|cikinti|filiz|donatı|donati)/u.test(
        context,
      ) && impalementIntent(candidate)
    ) {
      return "sharp_edge_contact";
    }
    return "fall_same_level";
  }
  if (candidate.module_id === "combustible_dust") return "fire_explosion";
  // people_exposure had no entry, so a worker at an unprotected edge with no
  // harness fell through to other_visible_physical and was capped at 15 while
  // the edge itself beside it scored 40.
  if (candidate.module_id === "people_exposure") {
    if (
      /(?:yuksek|yüksek|kenar|dusme|düşme|fall|height|kemer|harness|lanyard|yasam hatti|yaşam hattı|ankraj|catı|çatı|platform|iskele|scaffold)/u
        .test(context)
    ) return "fall_from_height";
    // Carrying was enough to call it overexertion, so a timber swinging into
    // someone -- consequence "kişinin nesne tarafından çarpılması" -- was capped
    // at the strain ceiling of 7. Overexertion needs a strain consequence.
    if (
      /(?:tasi|taşı|kaldir|kaldır|zorlan|ergonom)/u.test(context) &&
      /(?:zorlan|incin|bel |kas |ergonom|tutulma|sırt|sirt|strain|sprain)/u
        .test(
          `${candidate.event_path.contact_or_failure} ${candidate.event_path.consequence}`
            .toLocaleLowerCase("tr-TR"),
        )
    ) {
      return "ergonomic_overexertion";
    }
  }
  return "other_visible_physical";
}

function probability(candidate: NormalizedCandidate): {
  value: number;
  basis: string;
} {
  const context = scoringContext(candidate);
  if (
    /(?:aktif (?:yangın|sizinti|salım)|active (?:fire|leak|release)|düşmekte|dusmekte|falling now|kopmakta|detaching|temas halinde|in contact)/u
      .test(context)
  ) return { value: 10, basis: "absent_or_failed_event_active" };
  const absence = candidate.condition_code === "visible_structural_absence" ||
    /(?:eksik|yok|bulunmuyor|korumasız|korumasiz|açık kenar|acik kenar|kapaksız|kapaksiz|bariyersiz|korkuluksuz|muhafazasız|muhafazasiz)/u
      .test(context);
  if (absence && candidate.person_ref) {
    return { value: 6, basis: "absent_or_failed_event_direct" };
  }
  // Exposed rebar ends scored P=1 - practically impossible - because the
  // probability model only recognised barrier absence and a named person. A
  // hazard that is physically present on a reachable walking or working path
  // is at least conditionally probable.
  if (
    absence || candidate.person_ref || candidate.accessible_event_path ||
    candidate.evidence_level === "E5"
  ) {
    return { value: 3, basis: "partial_event_direct_or_conditional" };
  }
  return { value: 1, basis: "visible_effective_event_conditional" };
}

type VisibleSectorContext = {
  constructionActiveWork: boolean;
};

function visibleSectorContext(
  photoOutputs: Array<{ photoIndex: number; output: ProviderPhotoOutput }>,
): VisibleSectorContext {
  const visiblePeople = photoOutputs.flatMap(({ output }) =>
    output.people.filter((person) => person.visible)
  );
  const activityText = [
    ...visiblePeople.flatMap((
      person,
    ) => [person.label, ...(person.cues ?? [])]),
    ...photoOutputs.flatMap(({ output }) =>
      output.candidates.flatMap((candidate) => [
        candidate.raw_label,
        ...candidate.affirmative_cues,
      ])
    ),
  ].join(" ").toLocaleLowerCase("tr-TR");
  return {
    constructionActiveWork: visiblePeople.length > 0 &&
      /(?:çalışıyor|calisiyor|taşıyor|tasiyor|yürüyor|yuruyor|kuruyor|söküyor|sokuyor|kaldırıyor|kaldiriyor|operating|working|carrying|walking)/u
        .test(activityText),
  };
}

function frequency(
  candidate: NormalizedCandidate,
  sectorID: string | null,
  visibleContext: VisibleSectorContext,
): {
  value: number;
  sectorPriorUsed: boolean;
  sectorDefaultF: number | null;
  modifierCode: string | null;
  reasonCode: string;
} {
  const context = scoringContext(candidate);
  if (
    /(?:çok nadir|cok nadir|catalogued rare|yılda bir|yilda bir)/u.test(context)
  ) {
    return {
      value: 0.5,
      sectorPriorUsed: false,
      sectorDefaultF: sectorID ? SECTOR_F[sectorID] ?? null : null,
      modifierCode: null,
      reasonCode: "catalogued_rare",
    };
  }
  if (sectorID === "construction" && visibleContext.constructionActiveWork) {
    return {
      value: 6,
      sectorPriorUsed: true,
      sectorDefaultF: SECTOR_F.construction,
      modifierCode: "visible_active_work",
      reasonCode: "sector_visible_modifier_applied",
    };
  }
  const modifiers: Record<
    string,
    { pattern: RegExp; value: number; code: string }
  > = {
    construction: {
      pattern:
        /(?:aktif çalışma|aktif calisma|çalışan|calisan|işçi|isci|worker|operating)/u,
      value: 6,
      code: "visible_active_work",
    },
    manufacturing: {
      pattern: /(?:bakım|bakim|maintenance|duruş|durus|shutdown)/u,
      value: 2,
      code: "manufacturing_visible_maintenance_shutdown",
    },
    mining: {
      pattern:
        /(?:yeraltı|yeralti|underground).{0,80}(?:üretim aynası|uretim aynasi|production face|ayna)/u,
      value: 10,
      code: "mining_underground_production_face",
    },
    energy: {
      pattern:
        /(?:insanlı|insanli|manned|operatörlü|operatorlu).{0,80}(?:kontrol|control)/u,
      value: 6,
      code: "energy_manned_control_area",
    },
    logistics_warehouse: {
      pattern:
        /(?:sürekli|surekli|continuous).{0,80}(?:trafik|traffic|forklift|araç|arac)/u,
      value: 10,
      code: "warehouse_continuous_visible_traffic",
    },
    chemical_laboratory: {
      pattern:
        /(?:aktif çalışma|aktif calisma|active work|çalışan|calisan|operator)/u,
      value: 6,
      code: "chemical_visible_active_work",
    },
    food_production: {
      pattern:
        /(?:sürekli|surekli|continuous).{0,80}(?:hat|line|üretim|uretim)/u,
      value: 10,
      code: "food_continuous_line_operation",
    },
    agriculture_livestock: {
      pattern: /(?:hayvan bakım|hayvan bakim|animal care)/u,
      value: 6,
      code: "agriculture_animal_care_area",
    },
    municipal_field_services: {
      pattern:
        /(?:aktif|active).{0,80}(?:trafik|traffic).{0,80}(?:çalışma|calisma|work)|(?:çalışma|calisma|work).{0,80}(?:aktif|active).{0,80}(?:trafik|traffic)/u,
      value: 6,
      code: "municipal_visible_active_traffic_work",
    },
  };
  const modifier = sectorID ? modifiers[sectorID] : undefined;
  if (modifier?.pattern.test(context)) {
    return {
      value: modifier.value,
      sectorPriorUsed: true,
      sectorDefaultF: SECTOR_F[sectorID!] ?? null,
      modifierCode: modifier.code,
      reasonCode: "sector_visible_modifier_applied",
    };
  }
  if (sectorID && sectorID !== "general" && SECTOR_F[sectorID] !== null) {
    return {
      value: SECTOR_F[sectorID] ?? 1,
      sectorPriorUsed: true,
      sectorDefaultF: SECTOR_F[sectorID] ?? null,
      modifierCode: null,
      reasonCode: "sector_frequency_prior_applied",
    };
  }
  return {
    value: candidate.person_ref ? 3 : 1,
    sectorPriorUsed: false,
    sectorDefaultF: null,
    modifierCode: null,
    reasonCode: candidate.person_ref
      ? "general_visible_active_exposure"
      : "missing_invalid_fallback",
  };
}

function severityWithMechanismCap(candidate: NormalizedCandidate): {
  value: number;
  mechanismCode: string;
  cap: number;
  reasonCode: string | null;
} {
  const mechanism = mechanismCode(candidate);
  const context = scoringContext(candidate);
  const maximum: Record<string, number> = {
    fall_same_level: 7,
    fall_from_height: 40,
    falling_object: 40,
    vehicle_equipment_strike: 40,
    caught_in_pinch_shear: 15,
    mechanical_separation_release: 40,
    hydraulic_pneumatic_release: 15,
    electrical_contact_arc: 15,
    fire_explosion: 100,
    structural_collapse: 100,
    equipment_overturn: 40,
    excavation_collapse_rockfall: 40,
    chemical_contact_release: 15,
    thermal_contact: 15,
    sharp_edge_contact:
      /(?:donatı|donati|rebar|filiz|saplanma|impale)/u.test(context) ? 40 : 7,
    ergonomic_overexertion: 7,
    environmental_release: 15,
    other_visible_physical: 15,
  };
  let cap = maximum[mechanism] ?? 15;
  if (
    mechanism === "fall_from_height" &&
    /(?:(?:üst|ana|top)\s*korkuluk|top\s*rail).{0,60}(?:mevcut|görülüyor|goruluyor|sağlam|saglam|present|intact)/u
      .test(context) &&
    /(?:orta korkuluk|ara korkuluk|midrail|etek tahtası|etek tahtasi|toeboard)/u
      .test(context) &&
    // "görünmüyor" was not in this list, so the same scaffold scored 540 or 202
    // depending on which verb the model happened to choose.
    /(?:eksik|yok|bulunmuyor|bulunmama|görünmüyor|gorunmuyor|görülmüyor|gorulmuyor|mevcut değil|mevcut degil|missing|absent|açık boşluk|acik bosluk|open gap)/u
      .test(context)
  ) cap = Math.min(cap, 15);
  const raw = severity(candidate.criticality);
  return {
    value: Math.min(raw, cap),
    mechanismCode: mechanism,
    cap,
    reasonCode: raw > cap ? "severity_capped_by_mechanism_policy" : null,
  };
}

function score(
  candidate: NormalizedCandidate,
  sectorID: string | null,
  visibleContext: VisibleSectorContext,
) {
  const probabilityResolution = probability(candidate);
  const frequencyResolution = frequency(candidate, sectorID, visibleContext);
  const severityResolution = severityWithMechanismCap(candidate);
  const p = probabilityResolution.value;
  const f = frequencyResolution.value;
  const s = severityResolution.value;
  const m5p = p <= 0.5 ? 1 : p === 1 ? 2 : p === 3 ? 3 : p === 6 ? 4 : 5;
  const m5s = s <= 3 ? 1 : s === 7 ? 2 : s === 15 ? 3 : s === 40 ? 4 : 5;
  const band = bands(p * f * s, m5p * m5s);
  return {
    fk_probability: SCORES.probability.includes(p as never) ? p : 1,
    fk_frequency: SCORES.frequency.includes(f as never) ? f : 1,
    fk_severity: SCORES.severity.includes(s as never) ? s : 7,
    fk_band: band.fkBand,
    m5_probability: m5p,
    m5_severity: m5s,
    m5_band: band.m5Band,
    sector_prior_used: frequencyResolution.sectorPriorUsed,
    scoring_frequency_basis: frequencyResolution.sectorPriorUsed
      ? "sector_prior"
      : frequencyResolution.reasonCode,
    sector_default_frequency: frequencyResolution.sectorDefaultF,
    sector_modifier_code: frequencyResolution.modifierCode,
    probability_basis: probabilityResolution.basis,
    mechanism_code: severityResolution.mechanismCode,
    severity_cap: severityResolution.cap,
    score_policy_reason_codes: [severityResolution.reasonCode].filter(Boolean),
  };
}

function routeClass(
  candidate: NormalizedCandidate,
): { itemClass?: SafetyItemClass; reason: string; reject?: string } {
  if (candidate.hard_reject_reason) {
    return {
      reason: candidate.hard_reject_reason,
      reject: candidate.hard_reject_reason,
    };
  }
  if (candidate.evidence_level === "E0") {
    return {
      reason: "no_affirmative_visual_evidence",
      reject: "no_affirmative_visual_evidence",
    };
  }
  // An energized line that cannot be identified is decided before the
  // assurance shortcut: the normalizer already judged it a verification topic,
  // and cables in standing water were published as an unscored paperwork item
  // because the model had also ticked requires_document_or_measurement.
  if (candidate.condition_code === "electrical_identity_unresolved") {
    return {
      itemClass: "verification_request",
      reason: "electrical_identity_or_energy_unresolved",
    };
  }
  if (candidate.requires_document_or_measurement && candidate.asset_ref) {
    return {
      itemClass: "assurance_requirement",
      reason: "visible_asset_nonvisual_assurance_topic",
    };
  }
  const critical = candidate.criticality === "fatal" ||
    candidate.criticality === "permanent";
  // Severity does not raise the evidence bar. The critical check used to run
  // first, so in one live run three ordinary E3 candidates became findings
  // while the single fatal E3 candidate - accessible path, no occlusion - was
  // demoted to a verification request. The escape hatch beside it demanded
  // counter_cues.length === 0, which punished the model for writing the
  // counter-cues the prompt asks for. A fatal hazard at E3 is the same
  // observation as an ordinary one at E3 and is judged the same way.
  if (
    ["E3", "E4", "E5"].includes(candidate.evidence_level) &&
    candidate.accessible_event_path
  ) {
    return {
      itemClass: "observed_finding",
      reason: candidate.condition_code === "visible_structural_absence"
        ? "visible_structural_absence"
        : "localized_visual_event_path",
    };
  }
  if (critical) {
    return {
      itemClass: "verification_request",
      reason: ["E1", "E2"].includes(candidate.evidence_level)
        ? "critical_geometry_unresolved"
        : "critical_candidate_preserved",
    };
  }
  if (candidate.evidence_level === "E1") {
    return {
      itemClass: "not_assessable",
      reason: "image_not_sufficient_for_claim",
    };
  }
  return { itemClass: "not_assessable", reason: "no_accessible_event_path" };
}

function priority(
  itemClass: SafetyItemClass,
  criticality: Criticality,
): number {
  const critical = criticality === "fatal"
    ? 0
    : criticality === "permanent"
    ? 10
    : criticality === "serious"
    ? 20
    : 30;
  const klass = itemClass === "observed_finding"
    ? 0
    : itemClass === "verification_request"
    ? 5
    : itemClass === "assurance_requirement"
    ? 15
    : 40;
  return critical + klass;
}

/**
 * A short human noun that separates two hazards sharing one title: the roof,
 * the scaffold, the platform. Never a scene id.
 */
function assetLabel(candidate: NormalizedCandidate): string {
  const context = scoringContext(candidate);
  const known: Array<[RegExp, string]> = [
    [/(?:cati|çatı|roof)/u, "çatı"],
    [/(?:iskele|scaffold)/u, "iskele"],
    [/(?:doseme|döşeme|slab|kat kenari|kat kenarı)/u, "döşeme kenarı"],
    [/(?:kalip|kalıp|formwork)/u, "kalıp kenarı"],
    [/(?:platform)/u, "platform"],
    [/(?:merdiven|stair|ladder)/u, "merdiven"],
    [/(?:bosluk|boşluk|opening|shaft)/u, "boşluk"],
  ];
  for (const [pattern, label] of known) {
    if (pattern.test(context)) return label;
  }
  return "";
}

function semanticEventKey(candidate: NormalizedCandidate): string {
  const compact = (value: string) =>
    value.toLocaleLowerCase("tr-TR")
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(
        /\b(?:fotoğraf|fotograf|görsel|gorsel|resim|görüntü|goruntu)\b/gu,
        "",
      )
      .replace(/[^a-z0-9çğıöşü]+/giu, " ")
      .trim();
  return [
    candidate.module_id,
    compact(candidate.event_path.source),
    compact(candidate.event_path.contact_or_failure),
    compact(candidate.event_path.consequence),
  ].join(":").slice(0, 500);
}

function dedupEventKey(candidate: NormalizedCandidate): string {
  const mechanism = mechanismCode(candidate);
  if (
    mechanism === "fall_same_level" &&
    ["access_egress", "housekeeping_physical_contact"].includes(
      candidate.module_id,
    )
  ) return `${candidate.photo_index}:ground_access_fall_same_level`;
  return semanticEventKey(candidate);
}

// The provider claimed a missing mid-rail and a missing toeboard on a guardrail
// whose photograph shows both, four times in one run, with empty counter_cues --
// so nothing downstream had anything to gate on. It does however publish
// positive controls, and in an earlier run it asserted "Üst platformda tam
// korkuluk sistemi (üst korkuluk, ara korkuluk, etek tahtası) mevcuttur" in the
// same photo as a candidate claiming that system incomplete. When the model
// contradicts itself about the same component, the honest output is a field
// check, not a scored finding: nothing is lost, because the engine already held
// both statements.
const BARRIER_COMPONENTS: Array<{ code: string; pattern: RegExp }> = [
  {
    code: "mid_rail",
    pattern: /(?:ara korkuluk|orta korkuluk|midrail|mid rail)/u,
  },
  {
    code: "toeboard",
    pattern: /(?:etek tahtası|etek tahtasi|topuk levhası|topuk levhasi|toeboard|toe board)/u,
  },
  {
    code: "top_rail",
    pattern: /(?:üst korkuluk|ust korkuluk|ana korkuluk|top rail|handrail)/u,
  },
  {
    code: "guard",
    pattern: /(?:koruyucu|muhafaza|guard(?:ing)?)/u,
  },
];

const ABSENCE_WORD =
  /(?:eksik|yok(?:tur)?|bulunmuyor|bulunmama|bulunmamakta|görünmüyor|gorunmuyor|mevcut değil|mevcut degil|missing|absent)/u;
const PRESENCE_WORD =
  /(?:mevcut(?!\s*değil)(?!\s*degil)|var(?:dır)?\b|görülüyor|goruluyor|görünür|gorunur|takılı|takili|present|intact)/u;

function componentsClaimedAbsent(candidate: NormalizedCandidate): string[] {
  if (candidate.condition_code !== "visible_structural_absence") return [];
  const text = `${candidate.normalized_label}. ${
    candidate.affirmative_cues.join(". ")
  }`.toLocaleLowerCase("tr-TR");
  // Clause by clause, never across a boundary: "üst korkuluk mevcut; ara
  // korkuluk bulunmuyor" states the top rail is there and only the mid-rail is
  // missing, and a flat window over the whole sentence read both as absent.
  const clauses = text.split(/[;.,]|\s+ve\s+|\s+ancak\s+|\s+fakat\s+/u)
    .map((clause) => clause.trim())
    .filter(Boolean);
  const absent = new Set<string>();
  const present = new Set<string>();
  for (const clause of clauses) {
    const hasAbsence = ABSENCE_WORD.test(clause);
    const hasPresence = PRESENCE_WORD.test(clause);
    for (const component of BARRIER_COMPONENTS) {
      if (!component.pattern.test(clause)) continue;
      if (hasPresence && !hasAbsence) present.add(component.code);
      else if (hasAbsence) absent.add(component.code);
    }
  }
  return [...absent].filter((code) => !present.has(code));
}

/**
 * Components the photo's own positive controls say are present.
 *
 * A control may carve the flagged candidate out of its own statement -- the
 * provider writes "Korkuluklarda ara korkuluk mevcut (C1 hariç)" -- and that is
 * consistency, not contradiction. Reading it as a flat affirmation would demote
 * a genuine localised defect, so an excluding control is reported separately:
 * `general` still means the component exists along the run, `flat` means the
 * control claimed it present with no carve-out at all.
 */
function componentsAffirmedPresent(
  output: ProviderPhotoOutput,
  moduleID: string,
  candidateKey: string,
): { flat: Set<string>; general: Set<string> } {
  const flat = new Set<string>();
  const general = new Set<string>();
  const key = candidateKey.replace(/^p\d+:/, "").toLocaleLowerCase("tr-TR");
  for (const control of output.positive_controls) {
    if (control.module_id !== moduleID) continue;
    const text = `${control.description} ${control.affirmative_cues.join(" ")}`
      .toLocaleLowerCase("tr-TR");
    const carvesOut = /(?:hariç|haric|dışında|disinda|except|excluding)/u
      .test(text) || (key.length >= 2 && text.includes(key));
    for (const component of BARRIER_COMPONENTS) {
      if (!component.pattern.test(text)) continue;
      general.add(component.code);
      if (!carvesOut) flat.add(component.code);
    }
  }
  return { flat, general };
}

// A macro close-up of a hose coupling produced "Yerdeki gevşek tel ve
// döküntülerden kaynaklanan takılma tehlikesi" from an offcut of wire and some
// dry grass in the gravel. There is no walking route in that frame: the model
// declared a single accessible region covering the whole image with
// is_global set, which says "ground is everywhere", not "people walk here".
// Scenes with a real trip hazard look different -- the construction photos carry
// four people and named routes ("Zemin geçiş yolu", "İskele platformu"), none of
// them global.
function sceneHasWalkableRoute(output: ProviderPhotoOutput): boolean {
  if (output.people.length > 0) return true;
  return output.accessible_regions.some((region) =>
    region.visible && region.region?.is_global !== true
  );
}

function assuranceModuleForVisibleAsset(
  kind: string,
  label: string,
): V4ModuleID | null {
  const text = `${kind} ${label}`.toLocaleLowerCase("tr-TR");
  if (/(?:vinç|vinc|crane|hoist|kaldırma|kaldirma)/u.test(text)) {
    return "lifting";
  }
  if (
    /(?:mikser|mixer|makine|machine|tezgâh|tezgah|konveyör|konveyor)/u.test(
      text,
    )
  ) {
    return "machinery";
  }
  if (/(?:elektrik|electrical|pano|panel|trafo|transformer)/u.test(text)) {
    return "electrical";
  }
  if (
    /(?:tank|vessel|basınçlı kap|basincli kap|proses boru|process pipe)/u.test(
      text,
    ) ||
    // A pressurised hose assembly and its coupling carry the same
    // non-visual assurance as fixed piping -- pressure rating, test
    // certificate, inspection date, whip restraint -- and matched nothing, so a
    // close-up of a hose coupling produced no assurance item at all.
    /(?:hortum|hose|kaplin|kaplın|coupling|rakor|rakör|kelepçe|kelepce|flanş|flans|fitting|bağlantı elemanı|baglanti elemani)/u
      .test(text)
  ) {
    return "process_integrity";
  }
  if (
    /(?:forklift|kamyon|truck|loader|yükleyici|yukleyici|mobil ekipman)/u.test(
      text,
    )
  ) {
    return "vehicles_mobile_equipment";
  }
  return null;
}

function visibleAssetAssuranceItem(params: {
  photoIndex: number;
  entityID: string;
  entityKind: string;
  entityLabel: string;
  moduleID: V4ModuleID;
  referencePolicy: string | null;
}): RoutedItem {
  const topic = assuranceTopicForModule(params.moduleID, params.entityLabel);
  const playbook = playbookForTopic(topic.id);
  return {
    id: crypto.randomUUID(),
    item_class: "assurance_requirement",
    is_scored: false,
    criticality: "ordinary",
    ordinal: 0,
    title: topic.title,
    category: categoryLabel(params.moduleID),
    description: topic.description,
    recommended_action: topic.action,
    recommended_measures: assuranceMeasures(playbook, "Saha doğrulama adımları"),
    references_text: referencesTextFor(playbook, params.referencePolicy),
    root_cause_text: "",
    confidence: 1,
    ai_confidence: 1,
    needs_field_verification: true,
    source_photo_indices: [params.photoIndex],
    display_group: "assurance_requirement",
    display_order: priority("assurance_requirement", "ordinary"),
    internal_priority: {
      assurance_topic_id: topic.id,
      visible_entity_id: params.entityID,
      visible_entity_kind: params.entityKind,
      dedup_key: topic.id,
      consequence_rank: topicConsequenceRank(topic.id),
      route_reason: "visible_asset_deterministic_assurance",
    },
  };
}

export function routeCandidates(params: {
  candidates: NormalizedCandidate[];
  photoOutputs: Array<{ photoIndex: number; output: ProviderPhotoOutput }>;
  sectorID: string | null;
  /** `analyses.regulatory_reference_policy`; only "tr_current" emits references. */
  referencePolicy?: string | null;
}): {
  items: RoutedItem[];
  ledger: RoutingLedgerEntry[];
  hardRejections: HardRejection[];
} {
  const items: RoutedItem[] = [];
  const ledger: RoutingLedgerEntry[] = [];
  const hardRejections: HardRejection[] = [];
  const referencePolicy = params.referencePolicy ?? null;
  const sectorContext = visibleSectorContext(params.photoOutputs);
  const outputByPhoto = new Map(
    params.photoOutputs.map((entry) => [entry.photoIndex, entry.output]),
  );
  for (const candidate of params.candidates) {
    const route = routeClass(candidate);
    if (route.reject) {
      hardRejections.push({
        candidate_id: candidate.id,
        reason_code: route.reject,
        criticality: candidate.criticality,
        evidence_snapshot: {
          cues: candidate.affirmative_cues,
          counter_cues: candidate.counter_cues,
        },
      });
      ledger.push({
        candidate_id: candidate.id,
        from_state: "candidate",
        to_state: "hard_reject",
        reason_code: route.reason,
        evidence_level: candidate.evidence_level,
      });
      continue;
    }
    let itemClass = route.itemClass!;
    let routeReason = route.reason;
    const photoForCandidate = outputByPhoto.get(candidate.photo_index);
    if (
      itemClass === "observed_finding" &&
      mechanismCode(candidate) === "fall_same_level" &&
      photoForCandidate && !sceneHasWalkableRoute(photoForCandidate)
    ) {
      hardRejections.push({
        candidate_id: candidate.id,
        reason_code: "no_walkable_route_in_scene",
        criticality: candidate.criticality,
        evidence_snapshot: {
          label: candidate.normalized_label,
          people_in_scene: photoForCandidate.people.length,
          accessible_regions: photoForCandidate.accessible_regions.length,
        },
      });
      ledger.push({
        candidate_id: candidate.id,
        from_state: "candidate",
        to_state: "hard_reject",
        reason_code: "no_walkable_route_in_scene",
        evidence_level: candidate.evidence_level,
      });
      continue;
    }
    // Self-contradiction: the same photo's positive controls affirm the very
    // component this candidate calls missing. Demote rather than publish a
    // scored absence the model itself disputed.
    if (itemClass === "observed_finding") {
      const photoOutput = photoForCandidate;
      const claimedAbsent = photoOutput ? componentsClaimedAbsent(candidate) : [];
      if (photoOutput && claimedAbsent.length > 0) {
        const affirmed = componentsAffirmedPresent(
          photoOutput,
          candidate.module_id,
          candidate.candidate_key,
        );
        const contradicted = claimedAbsent.filter((component) =>
          affirmed.flat.has(component)
        );
        // The component the model says is present along the run but missing at
        // this one spot. That is a localised gap, and telling it apart from a
        // rail seen edge-on or hidden behind plant is finer geometry than a
        // flattened photo carries -- the engine's own rule for partially
        // resolved critical geometry is to ask for a field check.
        const localised = claimedAbsent.filter((component) =>
          !affirmed.flat.has(component) && affirmed.general.has(component)
        );
        if (contradicted.length > 0) {
          itemClass = "verification_request";
          routeReason = `provider_self_contradiction:${contradicted.join("+")}`;
        } else if (localised.length > 0) {
          itemClass = "verification_request";
          routeReason = `localized_barrier_gap_unresolved:${localised.join("+")}`;
        }
      }
    }
    const scored = itemClass === "observed_finding";
    const assurance = itemClass === "assurance_requirement"
      ? assuranceTopic(candidate)
      : null;
    const scoreValues = scored
      ? score(candidate, params.sectorID, sectorContext)
      : null;
    const confidence = Math.max(
      0,
      Math.min(
        1,
        (
          candidate.confidence.visibility + candidate.confidence.localization +
          candidate.confidence.mechanism
        ) / 3,
      ),
    );
    items.push({
      id: crypto.randomUUID(),
      candidate_id: candidate.id,
      item_class: itemClass,
      is_scored: scored,
      criticality: candidate.criticality,
      ordinal: 0,
      title: assurance?.title ?? titleFor(candidate, itemClass),
      category: categoryLabel(candidate.module_id),
      description: assurance?.description ??
        descriptionFor(candidate, itemClass),
      recommended_action: itemClass === "assurance_requirement"
        ? assurance!.action
        : itemClass === "verification_request"
        ? verificationAction(candidate)
        : controlTextFor(candidate),
      recommended_measures: measuresFor(candidate, itemClass),
      references_text: referencesFor(candidate, itemClass, referencePolicy),
      root_cause_text: rootCauseFor(candidate, itemClass),
      confidence,
      ai_confidence: confidence,
      needs_field_verification: !scored ||
        scoreValues?.sector_prior_used === true,
      source_photo_indices: [candidate.photo_index],
      display_group: itemClass,
      display_order: priority(itemClass, candidate.criticality),
      ...(scoreValues ?? {}),
      score_payload: scoreValues ?? undefined,
      internal_priority: {
        criticality: candidate.criticality,
        route_reason: routeReason,
        mechanism_code: mechanismCode(candidate),
        // Distinguishing noun for the title-uniqueness pass, taken from the
        // hazard's own words rather than a scene id.
        asset_label: assetLabel(candidate),
        dedup_key: itemClass === "assurance_requirement"
          ? assurance!.id
          : dedupEventKey(candidate),
        // Drives which unscored item survives the report budget. Without it the
        // tie-break fell through to the Turkish alphabet.
        consequence_rank: assurance
          ? topicConsequenceRank(assurance.id)
          : moduleConsequenceRank(candidate.module_id),
        ...(assurance ? { assurance_topic_id: assurance.id } : {}),
      },
    });
    ledger.push({
      candidate_id: candidate.id,
      from_state: "candidate",
      to_state: itemClass,
      reason_code: routeReason,
      evidence_level: candidate.evidence_level,
    });
  }

  for (const { photoIndex, output } of params.photoOutputs) {
    for (const entity of output.scene_entities.filter((item) => item.visible)) {
      const moduleID = assuranceModuleForVisibleAsset(
        entity.kind,
        entity.label,
      );
      if (!moduleID) continue;
      items.push(visibleAssetAssuranceItem({
        photoIndex,
        entityID: entity.id,
        entityKind: entity.kind,
        entityLabel: entity.label,
        moduleID,
        referencePolicy,
      }));
    }
    for (const control of output.positive_controls) {
      items.push({
        id: crypto.randomUUID(),
        item_class: "positive_control",
        is_scored: false,
        criticality: "ordinary",
        ordinal: 0,
        title: cleanText(control.description, "Görünür olumlu kontrol"),
        category: categoryLabel(control.module_id),
        description: cleanText(
          control.affirmative_cues.join("; "),
          control.description,
        ),
        recommended_action: "",
        recommended_measures: [],
        references_text: "",
        root_cause_text: "",
        confidence: 0.8,
        ai_confidence: 0.8,
        needs_field_verification: false,
        source_photo_indices: [photoIndex],
        display_group: "positive_control",
        display_order: 900,
        internal_priority: { control_key: control.control_key },
      });
    }
    const noCandidates = new Set(
      output.candidates.map((candidate) => candidate.module_id),
    );
    for (
      const coverage of output.module_coverage.filter((entry) =>
        entry.outcome === "not_assessable_due_to_image" &&
        !noCandidates.has(entry.module_id)
      )
    ) {
      items.push(notAssessableItem(photoIndex, coverage));
    }
    // The prompt instructs the model to answer unresolved_requires_verification
    // when critical geometry is occluded but the possible consequence is heavy.
    // Only not_assessable_due_to_image produced an item, so those answers were
    // dropped without a trace: one run marked electrical, confined_space and
    // chemical unresolved on the same photo and the reader saw nothing.
    for (
      const coverage of output.module_coverage.filter((entry) =>
        entry.outcome === "unresolved_requires_verification" &&
        !noCandidates.has(entry.module_id)
      )
    ) {
      items.push(
        unresolvedModuleVerificationItem(photoIndex, coverage, referencePolicy),
      );
    }
  }

  // Deduplicate only inside a class. Cross-class records intentionally survive.
  const deduped = new Map<string, RoutedItem>();
  for (const item of items) {
    const key = `${item.item_class}:${
      String(
        item.internal_priority.dedup_key ??
          item.internal_priority.control_key ??
          `${item.category}:${item.title.toLocaleLowerCase("tr-TR")}`,
      )
    }`;
    const previous = deduped.get(key);
    if (!previous) {
      deduped.set(key, item);
      continue;
    }
    // The loser's identity used to vanish here. Three crane hooks each missing
    // a latch merged into one finding, and the critical-fate audit reported
    // two demotions for candidates that had in fact been reported: the alarm
    // fired on its own dedup.
    const winner = priority(item.item_class, item.criticality) <
        priority(previous.item_class, previous.criticality)
      ? item
      : previous;
    const loser = winner === item ? previous : item;
    winner.source_photo_indices = [
      ...new Set([
        ...winner.source_photo_indices,
        ...loser.source_photo_indices,
      ]),
    ].sort();
    winner.internal_priority.merged_candidate_ids = [
      ...new Set([
        ...(winner.internal_priority.merged_candidate_ids as string[] ?? []),
        ...(loser.internal_priority.merged_candidate_ids as string[] ?? []),
        ...(loser.candidate_id ? [loser.candidate_id] : []),
      ]),
    ];
    deduped.set(key, winner);
  }
  // A merged finding covers more than one point, and the report has to say so
  // rather than name whichever one survived.
  for (const item of deduped.values()) {
    const merged = (item.internal_priority.merged_candidate_ids as string[]) ??
      [];
    if (merged.length === 0 || item.item_class !== "observed_finding") continue;
    item.description = `${item.description} Aynı ekipman veya alanda ${
      merged.length + 1
    } ayrı noktada aynı koşul görülmektedir.`.slice(0, 1200);
  }
  const ordered = [...deduped.values()].sort((a, b) =>
    a.display_order - b.display_order || a.title.localeCompare(b.title, "tr")
  );
  // Dedup keys are semantic, so two genuinely different hazards may still
  // resolve to one title. The roof edge and the scaffold mid-rail were both
  // published as "Çalışma kenarında düşmeye karşı koruma eksikliği" at FK 1440.
  const titleSeen = new Map<string, number>();
  for (const item of ordered) {
    const key = `${item.item_class}:${item.title.toLocaleLowerCase("tr-TR")}`;
    const count = (titleSeen.get(key) ?? 0) + 1;
    titleSeen.set(key, count);
    if (count === 1) continue;
    const qualifier = cleanText(
      String(item.internal_priority.asset_label ?? ""),
      "",
    ) || `${count}`;
    item.title = `${item.title} (${qualifier})`.slice(0, 180);
  }
  ordered.forEach((item, index) => {
    item.ordinal = index + 1;
    item.display_order = index + 1;
  });
  return { items: ordered, ledger, hardRejections };
}

function notAssessableItem(
  photoIndex: number,
  coverage: ModuleCoverage,
): RoutedItem {
  return {
    id: crypto.randomUUID(),
    item_class: "not_assessable",
    is_scored: false,
    criticality: "ordinary",
    ordinal: 0,
    // The raw routing key used to be the title here. These items are not
    // published, but nothing should carry an English snake_case id as its name.
    title: `${categoryLabel(coverage.module_id)} değerlendirilemedi`,
    category: categoryLabel(coverage.module_id),
    description: coverage.note?.trim() ||
      "Görüntü bu modülü değerlendirmeye uygun değil.",
    recommended_action: "",
    recommended_measures: [],
    references_text: "",
    root_cause_text: "",
    confidence: 0,
    ai_confidence: 0,
    needs_field_verification: false,
    source_photo_indices: [photoIndex],
    display_group: "not_assessable",
    display_order: 950,
    internal_priority: { coverage_outcome: coverage.outcome },
  };
}

// A module the model could not resolve becomes a published verification request
// rather than silence. There is no candidate behind it, so it carries the
// module's assurance playbook and is never scored.
function unresolvedModuleVerificationItem(
  photoIndex: number,
  coverage: ModuleCoverage,
  referencePolicy: string | null,
): RoutedItem {
  const playbook = playbookForModule(coverage.module_id);
  const label = categoryLabel(coverage.module_id);
  return {
    id: crypto.randomUUID(),
    item_class: "verification_request",
    is_scored: false,
    criticality: "ordinary",
    ordinal: 0,
    title: label,
    category: label,
    description: cleanText(
      coverage.note?.trim() ?? "",
      `${label} konusunda kritik geometri görüntüde tam çözülemedi; olası sonuç ağır olduğu için koşul kapatılmadı.`,
    ),
    recommended_action:
      "Maruziyeti sınırlandırın ve koşulu yetkili kişiyle sahada doğrulayın.",
    recommended_measures: [{
      kind: "corrective",
      title: "Saha doğrulama adımları",
      text: playbook.steps.map((step, index) => `${index + 1}. ${step}`).join(
        "\n",
      ),
    }, {
      kind: "preventive",
      title: "Kalıcı önleme",
      text: playbook.preventive,
    }],
    references_text: referencesTextFor(playbook, referencePolicy),
    root_cause_text: "",
    confidence: 0.5,
    ai_confidence: 0.5,
    needs_field_verification: true,
    source_photo_indices: [photoIndex],
    display_group: "verification_request",
    display_order: priority("verification_request", "ordinary"),
    internal_priority: {
      coverage_outcome: coverage.outcome,
      dedup_key: `unresolved_module:${coverage.module_id}`,
      consequence_rank: moduleConsequenceRank(coverage.module_id),
      route_reason: "module_coverage_unresolved",
    },
  };
}

export function assertCriticalCandidateFates(
  candidates: NormalizedCandidate[],
  items: RoutedItem[],
  hardRejections: HardRejection[],
  routingLedger: RoutingLedgerEntry[] = [],
): void {
  const itemCandidates = new Set(
    items.map((item) => item.candidate_id).filter(Boolean),
  );
  const rejected = new Set(hardRejections.map((item) => item.candidate_id));
  const routed = new Set(
    routingLedger.filter((entry) =>
      entry.candidate_id && entry.reason_code &&
      [
        "observed_finding",
        "assurance_requirement",
        "verification_request",
        "positive_control",
        "not_assessable",
        "hard_reject",
      ].includes(entry.to_state)
    ).map((entry) => entry.candidate_id!),
  );
  // A candidate absorbed by dedup was reported, not demoted.
  const observed = new Set(
    items.filter((item) => item.item_class === "observed_finding")
      .flatMap((item) => [
        item.candidate_id,
        ...((item.internal_priority.merged_candidate_ids as string[]) ?? []),
      ]).filter(Boolean),
  );
  const demotions: string[] = [];
  for (const candidate of candidates) {
    if (!["fatal", "permanent"].includes(candidate.criticality)) continue;
    if (
      !itemCandidates.has(candidate.id) && !rejected.has(candidate.id) &&
      !routed.has(candidate.id)
    ) {
      throw new Error(`critical_silent_drop:${candidate.candidate_key}`);
    }
    // A record is not the same as a finding. The original invariant was
    // satisfied by the demotion that hid a fatal hazard among the field-check
    // items, and reported zero silent drops while doing it.
    if (
      ["E3", "E4", "E5"].includes(candidate.evidence_level) &&
      candidate.accessible_event_path && !candidate.hard_reject_reason &&
      !observed.has(candidate.id)
    ) {
      // Bare keys made every demotion look the same. An electrical line whose
      // energy state genuinely cannot be read from a photo is a doctrine-driven
      // field check; an unexplained one is a defect. The reason tells them apart.
      const reason = routingLedger.find((entry) =>
        entry.candidate_id === candidate.id
      )?.reason_code ?? "unknown";
      demotions.push(`${candidate.candidate_key}:${reason}`);
    }
  }
  criticalDemotions.length = 0;
  criticalDemotions.push(...demotions);
}

/**
 * Critical candidates that had a visible, reachable event path and still did
 * not become an observed finding. Surfaced in the quality trace so a demotion
 * is auditable instead of invisible.
 */
export const criticalDemotions: string[] = [];
