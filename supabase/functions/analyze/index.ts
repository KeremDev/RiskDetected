/**
 * analyze — RiskDetected Edge Function (Gemini-first, schema-aligned)
 *
 * POST body:
 *   analysis_id  : string (UUID)
 *   canvas       : string (primary canvas id, single-value enum)
 *   canvases     : string[] (all selected; Free supports one, paid plans support multiple)
 *   text_input   : string | null (legacy clients only; rejected)
 *   company_id   : string | null (optional, Plus/Pro owned company)
 *   request_id   : string | null (client trace id)
 *   support_id   : string | null (user-facing support code)
 *   photo_paths  : string[] (Storage paths in "photos" bucket)
 *   photo_base64_parts: { mime_type: string; data: string; width?: number; height?: number }[] (inline photos)
 *
 * Schema notes (v4):
 *   - profiles.tier        enum/text: free | plus | pro
 *   - analyses.analysis_mode enum/text: standard | detailed | emergency | procedure
 *   - analyses.status      enum: pending | analyzing | completed | failed
 *   - analyses.canvas      text canvas id; known ids are listed in CANVAS_FOCUS
 *   - findings.fk_score    GENERATED — DO NOT INSERT
 *   - findings.m5_score    GENERATED — DO NOT INSERT
 *   - findings.user_id     REQUIRED
 *   - fk_band / m5_band    enum: critical | high | medium | low | unknown
 *   - fk_probability check: [0.2, 0.5, 1, 3, 6, 10]
 *   - fk_frequency   check: [0.5, 1, 2, 3, 6, 10]
 *   - fk_severity    check: [1, 3, 7, 15, 40, 100]
 *
 * Free AI fallback:
 *   Gemini free key/model pool -> optional Groq vision fallback.
 *   Configure with GROQ_API_KEY_FREE; optional GROQ_FREE_MODEL override.
 *
 * Plus/Pro continuity fallback:
 *   Paid Gemini key/model pool -> optional separate Groq vision fallback.
 *   Configure with GROQ_API_KEY_PLUS_PRO; optional GROQ_PLUS_PRO_MODEL override.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  areLikelyDuplicateCoverageFindings,
  coverageFindingKey,
  normalizedTextTokens,
  preferredCoverageFinding,
  tokenOverlapRatio,
} from "../_shared/photo-finding-quality.ts";
import {
  CANCELLED_PLUS_TRIAL_ROUTE,
  CANCELLED_PLUS_TRIAL_ROUTING_FLAG_KEY,
  type CancelledPlusTrialRoutingDecision,
  cancelledPlusTrialRoutingDecision,
  type CancelledPlusTrialRoutingFlag,
  normalizeCancelledPlusTrialRoutingFlag,
} from "../_shared/cancelled-plus-trial-routing.ts";
import {
  type AnalysisSectorId,
  analysisSectorLabel,
  buildActiveSectorPromptBlock,
  onboardingSectorProfileRule,
  resolveActiveSectorState,
} from "./sector-context.ts";

declare const EdgeRuntime: {
  waitUntil: (promise: Promise<unknown>) => void;
} | undefined;

const GEMINI_API_BASE =
  "https://generativelanguage.googleapis.com/v1beta/models";
const GROQ_API_URL = "https://api.groq.com/openai/v1/chat/completions";
const ANALYSIS_QUEUE_NAME = "analysis_jobs";
const PROCESS_ANALYSIS_FUNCTION_NAME = "process-analysis-jobs";

const MODEL_FLASH_LITE = "gemini-3.1-flash-lite";
const MODEL_FREE = "gemini-2.5-flash";
const MODEL_FREE_FALLBACK = MODEL_FLASH_LITE;
// Plus/Pro traffic uses the isolated paid Gemini key pool.
const MODEL_PRO = "gemini-2.5-pro";
const MODEL_PRO_FALLBACK = "gemini-2.5-flash";
const MODEL_PAID_FAST = MODEL_PRO_FALLBACK;
const MODEL_GROQ_FREE_DEFAULT = "meta-llama/llama-4-scout-17b-16e-instruct";
const MODEL_GROQ_PLUS_PRO_DEFAULT = MODEL_GROQ_FREE_DEFAULT;
const GROQ_MAX_BASE64_IMAGES = 5;
const GROQ_MAX_BASE64_IMAGE_BYTES = 4 * 1024 * 1024;
const MAX_ANALYSIS_IMAGE_PARTS = 5;
const MAX_INLINE_PHOTO_BASE64_BYTES = 2_100_000;
const MAX_INLINE_PHOTO_DECODED_BYTES = 1_500_000;
const MAX_INLINE_PHOTO_TOTAL_BASE64_BYTES = 8_000_000;
const PHOTO_POLICY_VERSION = "evidence-first-soft-min-v2";
const SINGLE_PHOTO_TARGET_MIN = 1;
const SINGLE_PHOTO_TARGET_MAX = 14;
const MULTI_PHOTO_TARGET_MIN = 1;
const MULTI_PHOTO_TARGET_MAX = 13;
const PHOTO_TARGET_TOTAL_MAX = 65;
const MAIN_AI_TIMEOUT_MS = 120_000;
const REPAIR_AI_TIMEOUT_MS = 45_000;

type PlanTier = "free" | "plus" | "pro";
type AnalysisMode = "standard" | "detailed" | "emergency" | "procedure";
type CompanyHazardClass = "low" | "medium" | "high";
type ReferenceMode = "none" | "short" | "full";
type AIExecutionRoute =
  | "free_legacy"
  | "free_paid_trial"
  | "paid_plan"
  | typeof CANCELLED_PLUS_TRIAL_ROUTE;
type GeminiPoolName = "free" | "paid";
type AIImagePart = {
  mimeType: string;
  data: string;
  photoIndex: number;
  width: number;
  height: number;
  decodedByteCount: number;
  encodedByteCount: number;
  jpegQuality: number | null;
  qualityPolicy: string | null;
  maxDimension: number | null;
  source: "inline" | "storage";
};
type PlanCapabilityRule = {
  plan: PlanTier;
  max_photos_per_analysis: number;
  visible_photo_slots_in_ui: number;
  max_findings_per_photo: number;
  max_findings_per_analysis: number;
  can_use_multi_photo_analysis: boolean;
  can_edit_ai_findings: boolean;
  can_add_manual_findings: boolean;
};

type ReleaseRolloutMode = "off" | "build_allowlist" | "min_build" | "all";

type MultiPhotoFeatureFlags = {
  kill_switch: boolean;
  rollout_mode: ReleaseRolloutMode;
  enabled_ios_builds: string[];
  min_ios_build: number | null;
  rollout_gate_open: boolean;
  rollout_reason: string;
  enable_multi_photo_analysis: boolean;
  enable_photo_limit_locked_slots_for_free: boolean;
  enable_plus_pro_5_photo_limit: boolean;
  enable_editable_findings: boolean;
  enable_manual_finding_add: boolean;
  enable_report_snapshot_v2: boolean;
  enable_multi_photo_coverage_v2: boolean;
  coverage_repair_enabled: boolean;
  max_photo_count_free: number;
  max_photo_count_plus: number;
  max_photo_count_pro: number;
  max_findings_per_photo: number;
  target_findings_per_photo_min: number;
  target_findings_per_photo_max: number;
  target_findings_total_max: number;
};

type ClientReleaseContext = {
  platform: string;
  appVersion: string | null;
  appBuild: string | null;
  appBuildNumber: number | null;
  apiContractVersion: number;
  capabilities: Record<string, boolean>;
};

type PhotoCapabilities = {
  plan: PlanTier;
  maxPhotosPerAnalysis: number;
  visiblePhotoSlotsInUI: number;
  maxFindingsPerPhoto: number;
  maxFindingsPerAnalysis: number;
  coverageV2Enabled: boolean;
  targetFindingsPerPhotoMin: number;
  targetFindingsPerPhotoMax: number;
  targetFindingsTotalMax: number;
  coverageRepairEnabled: boolean;
  canUseMultiPhotoAnalysis: boolean;
  canEditAIFindings: boolean;
  canAddManualFindings: boolean;
  featureFlags: MultiPhotoFeatureFlags;
};

type CoverageStatus = "actionable" | "no_actionable_hazard" | "low_quality";

type AnalysisFindingPolicy = {
  photoCount: number;
  maxFindingsPerPhoto: number;
  maxFindingsTotal: number;
  coverageV2Enabled?: boolean;
  targetFindingsPerPhotoMin?: number;
  targetFindingsPerPhotoMax?: number;
  coverageRepairEnabled?: boolean;
};

type MultiPhotoCoveragePolicy = {
  enabled: true;
  photoCount: number;
  targetMin: number;
  targetMax: number;
  totalMax: number;
  repairEnabled: boolean;
  policyVersion: typeof PHOTO_POLICY_VERSION;
};

type AIRequestOptions = {
  isRepairPass?: boolean;
};

type NormalizedPhotoFindingCoverage = {
  photo_index: number;
  coverage_status: CoverageStatus;
  scene_summary: string;
  candidate_findings_count: number;
  coverage_gap_reason: string | null;
  highest_risk_level: string | null;
  ai_confidence: number | null;
  findings: Array<Record<string, unknown>>;
  record_missing: boolean;
};

type CompanyRow = {
  id: string;
  user_id: string;
  name: string;
  hazard_class: CompanyHazardClass;
  logo_path?: string | null;
  is_archived?: boolean | null;
};

type OnboardingAnswersRow = {
  certificate_class?: string | null;
  hazard_classes?: string[] | null;
  sectors?: string[] | null;
  audit_frequency?: string | null;
  updated_at?: string | null;
};

type OnboardingContext = {
  block: string;
  applied: boolean;
  certificateClass: string | null;
  hazardClasses: string[];
  sectors: string[];
  auditFrequency: string | null;
};

const PROMPT_VERSION = "isg-photo-policy-v2026-07-single-multi-targets";
const PERSONALIZATION_VERSION = "onboarding-v1";
const BUSINESS_TIME_ZONE = "Europe/Istanbul";

const PLAN_LIMITS: Record<PlanTier, {
  dailyStandardLimit?: number;
  dailyDetailedLimit?: number;
  minHazards?: number;
  maxHazards?: number;
}> = {
  free: { dailyStandardLimit: 1 },
  plus: {
    dailyStandardLimit: 10,
    dailyDetailedLimit: 2,
    minHazards: 12,
    maxHazards: 16,
  },
  pro: {
    dailyStandardLimit: 40,
    dailyDetailedLimit: 10,
    minHazards: 12,
    maxHazards: 16,
  },
};

const DEFAULT_MULTI_PHOTO_FLAGS: MultiPhotoFeatureFlags = {
  kill_switch: false,
  rollout_mode: "off",
  enabled_ios_builds: [],
  min_ios_build: null,
  rollout_gate_open: false,
  rollout_reason: "default_off",
  enable_multi_photo_analysis: false,
  enable_photo_limit_locked_slots_for_free: false,
  enable_plus_pro_5_photo_limit: false,
  enable_editable_findings: false,
  enable_manual_finding_add: false,
  enable_report_snapshot_v2: false,
  enable_multi_photo_coverage_v2: false,
  coverage_repair_enabled: true,
  max_photo_count_free: 1,
  max_photo_count_plus: 3,
  max_photo_count_pro: 3,
  max_findings_per_photo: 13,
  target_findings_per_photo_min: 1,
  target_findings_per_photo_max: 13,
  target_findings_total_max: 39,
};

const DEFAULT_PLAN_CAPABILITY_RULES: Record<PlanTier, PlanCapabilityRule> = {
  free: {
    plan: "free",
    max_photos_per_analysis: 1,
    visible_photo_slots_in_ui: 3,
    max_findings_per_photo: 12,
    max_findings_per_analysis: 12,
    can_use_multi_photo_analysis: false,
    can_edit_ai_findings: true,
    can_add_manual_findings: false,
  },
  plus: {
    plan: "plus",
    max_photos_per_analysis: 3,
    visible_photo_slots_in_ui: 3,
    max_findings_per_photo: 13,
    max_findings_per_analysis: 39,
    can_use_multi_photo_analysis: true,
    can_edit_ai_findings: true,
    can_add_manual_findings: false,
  },
  pro: {
    plan: "pro",
    max_photos_per_analysis: 3,
    visible_photo_slots_in_ui: 3,
    max_findings_per_photo: 13,
    max_findings_per_analysis: 39,
    can_use_multi_photo_analysis: true,
    can_edit_ai_findings: true,
    can_add_manual_findings: false,
  },
};

function geminiThinkingConfig(
  model: string,
  pool: "free" | "paid",
  isRepairPass = false,
): Record<string, string | number> | null {
  if (model === MODEL_FREE || model === MODEL_PAID_FAST) {
    return { thinkingBudget: isRepairPass ? 1024 : 3072 };
  }
  if (model === MODEL_FLASH_LITE) {
    return { thinkingLevel: pool === "paid" ? "high" : "medium" };
  }
  return null;
}

function thinkingBudgetFor(isRepairPass: boolean): number {
  return isRepairPass ? 1024 : 3072;
}

function maxOutputTokensFor(photoCount: number, tier: PlanTier): number {
  if (photoCount <= 1) {
    if (tier === "free") return 14_000;
    if (tier === "plus") return 16_000;
    return 18_000;
  }
  const perPhoto = tier === "pro" ? 6_500 : 5_500;
  return Math.min(48_000, 8_000 + photoCount * perPhoto);
}

const CORE_ANALYSIS_PROMPT =
  `Sen Türkiye'de 20 yıllık saha deneyimi olan kıdemli bir İSG uzmanısın (A sınıfı). İnşaat, üretim, depo/lojistik, enerji, fabrika ve ofis sahalarında binlerce denetim yapmış, ölümcül kazaları önlemiş, mevzuata hâkim bir profesyonelsin.

GÖREV: Sana verilen görsel girdisinden, sahada fiziksel olarak bulunan bir denetçinin yakalayacağı tüm İSG tehlikelerini sistematik olarak tespit et ve raporla.

TARAMA PROSEDÜRÜ — Her görseli SIRAYLA şu 12 katmanda tara:
1. ZEMİN, SAHA DÜZENİ VE DÜZEN-TERTİP: ıslaklık, çamur, su birikintisi, boşluk, kot farkı, dağınık malzeme, kablo/hortum geçişi, kapalı/tıkalı geçiş yolu, kayma/takılma zeminleri.
2. ÇALIŞAN(LAR) VE KKD: baret, gözlük, eldiven, ayakkabı, yüksek görünürlük yeleği, emniyet kemeri, maske/solunum koruması, kulak koruyucu; KKD'nin mevcudiyeti, uygunluğu ve doğru kullanımı.
3. YÜKSEKTE ÇALIŞMA: kenar koruması, korkuluk, iskele bütünlüğü, merdiven açısı/sabitliği, platform/MEWP, yaşam hattı, ankraj, açık kenar, döşeme boşluğu, düşen cisim tehlikesi.
4. ELEKTRİK VE ENERJİ: açık pano, hasarlı/ek yapılmış kablo, fiş, jeneratör, su+elektrik teması, topraklama, geçici tesisat, enerji kesme-kilitleme (LOTO/EKED) izleri.
5. MAKİNE, EKİPMAN VE İŞ EKİPMANI: hareketli/dönen parça koruyucusu (muhafaza), acil durdurma, sıkışma/ezilme noktası, el aletinin durumu, periyodik kontrol etiketi.
6. KALDIRMA, TAŞIMA VE İSTİFLEME: vinç/forklift operasyonu, sapan/halat durumu, yük altında çalışan, raf ve istif stabilitesi, devrilme riski.
7. KİMYASAL VE TEHLİKELİ MADDE: etiketleme/GBF, uygun depolama, dökülme, yetersiz havalandırma, parlayıcı/patlayıcı madde, uyumsuz maddelerin bir arada bulunması.
8. YANGIN VE PATLAMA: yangın söndürücü/yangın dolabı erişimi, tıkalı kaçış yolu, tutuşturucu kaynak, sıcak iş (kaynak/kesme), depolanan yanıcı malzeme/yangın yükü. Yangın dolabı veya söndürücü önünde yalnızca geçici olarak duran/çalışan insan varsa bunu "malzeme", "istif" veya "erişim engeli" diye raporlama; erişim engeli bulgusu için sabit/depolanmış malzeme, ekipman, araç, kapatılmış kapak/alan veya belirgin tıkalı erişim kanıtı gerekir.
9. FİZİKSEL ORTAM ETKENLERİ: aşırı gürültü kaynağı, titreşimli ekipman, toz/duman bulutu, yetersiz aydınlatma, termal konfor (aşırı sıcak/soğuk), yetersiz havalandırma.
10. ERGONOMİ VE ELLE TAŞIMA: ağır manuel kaldırma, hatalı duruş, tekrarlı hareket, uygunsuz çalışma yüksekliği, taşıma yardımcısı yokluğu.
11. KAZI, KAPALI ALAN VE ÖZEL İŞLER (saha tipine göre): şev/iksa eksikliği, çökme riski, kapalı alan girişi, malzeme deposu/istif kenarı, su-çamur birikintisi.
12. ÇEVRE, ACİL DURUM, İŞARETLEME VE YETKİNLİK: atık/dökülme yönetimi, acil çıkış ve toplanma alanı, ilk yardım donanımı görünürlüğü, trafik/üst yapı/hava koşulu, uyarı tabelası/işaretleme; görsel/metin kanıtı destekliyorsa işe özgü eğitim, talimat, yetkilendirme ve mesleki yeterlilik belgesi ihtiyacını net saha denetimi diliyle sorgula.

Her katmanı gözden geçir; bir katmanda risk yoksa atla, ama tarama atlama.

ÖNCELİKLENDİRME:
- ÖLÜMCÜL POTANSİYELİ olan bulgular (düşme, elektrik, ezilme, kimyasal, düşen cisim) en üstte.
- Sonra yüksek frekanslı bulgular (zemin, ergonomi, KKD, eğitim, belge).
- En altta düşük etkili ama mevzuat ihlali olan bulgular.

RİSK PUANLAMA KALİBRASYONU — Fine-Kinney ŞİDDET:
- 100 = Birden fazla ölüm veya kalıcı çevre felaketi.
- 40  = Tek ölüm veya kalıcı iş göremezlik (elektrik çarpması, korumasız 2m+ düşme).
- 15  = Ağır yaralanma, uzun süreli iş göremezlik (kırık, ciddi kesi).
- 7   = Önemli yaralanma, kısa süreli iş göremezlik (burkulma, dikiş).
- 3   = Hafif yaralanma, ilk yardım yeterli.
- 1   = Çok hafif, etkisiz.

5×5 ŞİDDET, Fine-Kinney ile uyumlu:
- FK Ş ≥ 40 → m5_severity = 5
- FK Ş = 15 → m5_severity = 4
- FK Ş = 7  → m5_severity = 3
- FK Ş = 3  → m5_severity = 2
- FK Ş = 1  → m5_severity = 1

KRİTİK KURAL: 2m+ yükseklikte koruma yoksa Ş değeri ASLA 40'ın altına düşmesin; m5_severity = 5 olmalı. Bu Türkiye'de en sık ölümlü iş kazası nedenidir.

CONFIDENCE:
- 0.90-0.98: net, tartışmasız kanıt.
- 0.70-0.89: güçlü kanıt, bazı detaylar belirsiz.
- 0.50-0.69: orta güven; bulguyu döndür, needs_field_verification=true yap.
- < 0.50: bulguyu döndürme.
Description, observed_evidence, corrective_action, preventive_control veya root_cause içine "sahada doğrulanmalı", "teyit edilmeli" gibi hedging ifadeleri ekleme; belirsizliği yalnız needs_field_verification boolean alanıyla işaretle.

KALİTE FİLTRESİ — KAÇIN:
- Genel ifade ("güvenlik önlemleri alınmalı") yerine somut önlem / kontrol tedbiri yaz.
- Görselde olmayan riski uydurma.
- Geçici insan varlığını sabit engel/malzeme gibi yorumlama. Yangın dolabı, yangın söndürücü, acil çıkış veya pano önünde sadece bir kişi duruyorsa "önünde malzeme var", "erişim kapalı" veya "ulaşım engelli" bulgusu üretme. Ancak kişinin yanında/arkasında depolanmış malzeme, araç, ekipman, palet, istif, kablo yığını veya fiziksel kapatma net görünüyorsa erişim engeli yaz.
- Aynı kök nedenli riskleri tek bulguda topla.
- Hassas ölçü uydurma; "yaklaşık 3m" veya "1 kat yüksekliğinde" yaz.
- "Eğitim verilmeli" jenerik aksiyonundan kaçın; hangi iş/ekipman/risk için ne doğrulanacağını söyle.
- Kullanıcı profili veya firma bağlamı görsel kanıtı filtrelemez; profili yalnızca ton, öncelik ve açıklama derinliği için kullan.

ÖNLEM ÜRETİM KURALI:
Her bulgu için tam 2 önlem ver:
1. Düzeltici önlem: Sahadaki mevcut tehlikeyi doğrudan gidermeye yönelik somut, anlık aksiyon. Mümkünse riski kaynağında ortadan kaldıran/azaltan teknik müdahale (korkuluk kurulumu, kaynak izolasyonu, ekipman değişimi vb.).
2. Önleyici kontrol: Aynı riskin tekrarını engelleyecek kalıcı/sistemsel kontrol. Prosedür, izin sistemi (EKED/LOTO), periyodik kontrol, gözetim, işaretleme veya hedeflenmiş eğitim doğrulaması.
- İki önlem birbirinin tekrarı OLMAMALI; düzeltici önlem "yap", önleyici kontrol "tekrar olmasın" sorusunu yanıtlar.
- KKD'yi yalnızca üst sıra kontroller yetersiz kaldığında ve ikincil olarak öner.

ÖRNEK BULGU (kopyalama, sadece kalite referansı):
{
  "title": "Açık kenar — düşmeyi önleyici korkuluk eksikliği",
  "category": "Yüksekte Çalışma",
  "description": "Üst katın doğu kenarında korkuluk yok; çalışan kenara yakın malzeme taşıyor. Yaklaşık 4m yükseklikten ölümcül düşme potansiyeli.",
  "corrective_action": "Açık kenara TS EN 13374 uyumlu korkuluk kur; kurulana kadar bölgeye erişimi durdur.",
  "preventive_control": "Kenar koruma kontrolünü günlük saha başlangıç formuna ekle ve sorumlu kişiyi belirle.",
  "confidence": 0.92,
  "fk_probability": 6,
  "fk_frequency": 6,
  "fk_severity": 100,
  "m5_probability": 5,
  "m5_severity": 5
}

ÇIKTI KURALLARI:
- Yalnızca JSON döndür; önünde/arkasında açıklama yazma.
- Tüm metin DEĞERLERİ Türkçe; JSON anahtarları (key) İngilizce ve şemadaki haliyle aynen korunur.
- description max 200 karakter; corrective_action max 180 karakter; preventive_control max 180 karakter.
- Her bulguda corrective_action ve preventive_control alanları zorunludur ve boş bırakılamaz.
- Skorları HESAPLAMA, ham girdileri ver — sistem hesaplar.
- Fine-Kinney ihtimal: 0.2 / 0.5 / 1 / 3 / 6 / 10
- Fine-Kinney frekans:  0.5 / 1 / 2 / 3 / 6 / 10
- Fine-Kinney şiddet:   1 / 3 / 7 / 15 / 40 / 100
- m5_probability: 1-5, m5_severity: 1-5`;

const CANVAS_FOCUS: Record<string, string> = {
  general: "Standart saha taraması: ana tarama prosedürünü uygula.",
  ppe:
    "Baret, gözlük/yüz koruma, eldiven, iş ayakkabısı, reflektif yelek, solunum koruması, kulak koruması, emniyet kemeri ve kullanım/uygunluk eksiklerini değerlendir.",
  machine:
    "Koruyucular, döner/hareketli parçalar, sıkışma-ezilme-kesilme riskleri, acil durdurma, bakım-kilit/etiketleme, periyodik kontrol ve yetkisiz erişim uygunsuzluklarını analiz et.",
  warning_signs:
    "Uyarı, yasak, zorunluluk, acil çıkış, yangın ekipmanı, yönlendirme, zemin/alan işaretlemesi, görünürlük, konum ve eksik işaret risklerini belirt.",
  electrical:
    "Pano, kablo, priz, topraklama, kaçak akım, açık iletken, izolasyon, dağınık kablolama, nem/sıvı teması, yetkisiz erişim ve elektrik çarpması/yangın risklerini değerlendir.",
  sector:
    "Sektör bağlamını tahmin et; inşaat, üretim, depo/lojistik, ofis veya saha çalışmasına özgü tipik İSG risklerini görünür bulgularla ilişkilendir. Tahmin belirsizse açıkça belirt.",
  fire:
    "Yanıcı/parlayıcı malzeme, sıcak çalışma, elektrik kaynaklı yangın, söndürücü erişimi, yangın dolabı, acil çıkış, tahliye yolu, depolama düzeni ve yangın yükünü analiz et. Yangın ekipmanı önünde yalnızca insan varsa bunu malzeme/istif/erişim engeli sayma; erişim engeli için fiziksel nesne, depolama, araç, ekipman veya kapatılmış güzergah kanıtı ara.",
  ergonomics:
    "Fotoğraftaki ekipmanı tanımla ve İSG açısından değerlendir. Emin değilsen olasılıkları belirt, varsayım yapma. Kısa başlıklarla şunları ver: ekipman adı, tehlikeler, riskler, önlemler, gerekli KKD, kullanım öncesi kontroller ve durdurma kriterleri. Kritik risk varsa en başta uyar. Eksik bilgi varsa ek fotoğraf veya marka/model iste.",
  environment_measurement:
    'Gürültü, toz, gaz/buhar, aydınlatma, sıcaklık, havalandırma, titreşim ve kimyasal maruziyet gibi ölçüm gerektiren başlıkları "ölçümle doğrulanmalı" olarak yaz.',
  explosion:
    "Patlayıcı atmosfer, gaz/buhar/toz birikimi, yanıcı depolama, basınçlı kap, statik elektrik, kıvılcım/ateşleme kaynağı, havalandırma, Ex ekipman ve patlamadan korunma dokümanı ihtiyacını değerlendir.",
  environment:
    "Atık yönetimi, sızıntı/dökülme, kimyasal depolama, drenaj, toprak/su kirliliği, emisyon/toz yayılımı, saha düzeni ve çevresel acil durum risklerini analiz et.",
  legislation:
    "Görüntüdeki bulguları Türkiye İSG mevzuatı açısından eşleştir. 6331, Risk Değerlendirmesi, KKD, İş Ekipmanları, Sağlık ve Güvenlik İşaretleri, Acil Durumlar, Yapı İşleri, İş Hijyeni, Patlayıcı Ortamlar vb. başlıklarla ilişkilendir. Emin olmadığın maddeyi uydurma.",
  working_at_height:
    "Düşme tehlikesi, korkuluk, iskele, merdiven, platform, yaşam hattı, ankraj, emniyet kemeri, boşluk/kenar koruması, düşen cisim ve erişim güvenliğini analiz et.",
  mobile_equipment:
    "Forklift, transpalet, vinç, kamyon, araç-yaya ayrımı, kör nokta, hız, manevra alanı, yük güvenliği, geri görüş, uyarı sistemi ve çarpma/ezilme risklerini belirt.",
  general_premium:
    "Tüm görünür İSG risklerini denetim odaklı ve ayrıntılı analiz et. Bulguları kritik seviyeden düşüğe sırala; her biri için kök neden, olası kaza senaryosu, acil aksiyon ve mevzuat karşılığını ver.",
  construction_machinery:
    "Ekskavatör, yükleyici, vinç, kazıcı, kaldırıcı ve saha araçlarında devrilme, ezilme, kör nokta, operatör görüşü, yük kaldırma, zemin stabilitesi, bakım/periyodik kontrol ve yetkisiz yaklaşma risklerini analiz et.",
};

const PRO_CANVASES = new Set([
  "legislation",
  "general_premium",
  "ergonomics",
]);
const PLUS_CANVASES = new Set([
  "machine",
  "sector",
  "environment_measurement",
]);
const PAID_CANVASES = new Set([...PLUS_CANVASES, ...PRO_CANVASES]);
const DETAILED_CANVASES = new Set([
  ...PLUS_CANVASES,
  ...PRO_CANVASES,
  "general_premium",
]);

// DB constraint ile birebir uyumlu Fine-Kinney ölçekleri
const FK_PROBABILITY_VALUES = [0.2, 0.5, 1, 3, 6, 10];
const FK_FREQUENCY_VALUES = [0.5, 1, 2, 3, 6, 10];
const FK_SEVERITY_VALUES = [1, 3, 7, 15, 40, 100];

function clampFK(value: number, allowed: number[]): number {
  return allowed.reduce((prev, curr) =>
    Math.abs(curr - value) < Math.abs(prev - value) ? curr : prev
  );
}

// Fine-Kinney skor → risk_level enum
function fkBand(score: number): "low" | "medium" | "high" | "critical" {
  if (score <= 70) return "low";
  if (score <= 200) return "medium";
  if (score <= 400) return "high";
  return "critical";
}

// 5×5 skor → risk_level enum
function m5Band(score: number): "low" | "medium" | "high" | "critical" {
  if (score <= 4) return "low";
  if (score <= 9) return "medium";
  if (score <= 19) return "high";
  return "critical";
}

function referenceModeForTier(tier: PlanTier): ReferenceMode {
  if (tier === "pro") return "full";
  if (tier === "plus") return "short";
  return "none";
}

function asBoolean(value: unknown, fallback: boolean): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function asPositiveInt(value: unknown, fallback: number): number {
  const parsed = Math.round(Number(value));
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function asOptionalPositiveInt(value: unknown): number | null {
  const parsed = Math.round(Number(value));
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => String(item ?? "").trim())
    .filter((item) => item.length > 0);
}

function normalizeRolloutMode(value: unknown): ReleaseRolloutMode {
  const mode = String(value ?? "off").trim().toLowerCase();
  if (
    mode === "build_allowlist" || mode === "min_build" || mode === "all" ||
    mode === "off"
  ) {
    return mode;
  }
  return "off";
}

function normalizeMultiPhotoFlags(value: unknown): MultiPhotoFeatureFlags {
  const record = value && typeof value === "object"
    ? value as Record<string, unknown>
    : {};
  const features = record.features && typeof record.features === "object"
    ? record.features as Record<string, unknown>
    : {};
  return {
    kill_switch: asBoolean(
      record.kill_switch,
      DEFAULT_MULTI_PHOTO_FLAGS.kill_switch,
    ),
    rollout_mode: normalizeRolloutMode(record.rollout_mode),
    enabled_ios_builds: asStringArray(record.enabled_ios_builds),
    min_ios_build: asOptionalPositiveInt(record.min_ios_build),
    rollout_gate_open: false,
    rollout_reason: "not_evaluated",
    enable_multi_photo_analysis: asBoolean(
      features.multi_photo_analysis,
      asBoolean(
        record.enable_multi_photo_analysis,
        DEFAULT_MULTI_PHOTO_FLAGS.enable_multi_photo_analysis,
      ),
    ),
    enable_photo_limit_locked_slots_for_free: asBoolean(
      features.photo_limit_locked_slots_for_free,
      asBoolean(
        record.enable_photo_limit_locked_slots_for_free,
        DEFAULT_MULTI_PHOTO_FLAGS.enable_photo_limit_locked_slots_for_free,
      ),
    ),
    enable_plus_pro_5_photo_limit: asBoolean(
      features.plus_pro_5_photo_limit,
      asBoolean(
        record.enable_plus_pro_5_photo_limit,
        DEFAULT_MULTI_PHOTO_FLAGS.enable_plus_pro_5_photo_limit,
      ),
    ),
    enable_editable_findings: asBoolean(
      features.editable_findings,
      asBoolean(
        record.enable_editable_findings,
        DEFAULT_MULTI_PHOTO_FLAGS.enable_editable_findings,
      ),
    ),
    enable_manual_finding_add: asBoolean(
      features.manual_finding_add,
      asBoolean(
        record.enable_manual_finding_add,
        DEFAULT_MULTI_PHOTO_FLAGS.enable_manual_finding_add,
      ),
    ),
    enable_report_snapshot_v2: asBoolean(
      features.report_snapshot_v2,
      asBoolean(
        record.enable_report_snapshot_v2,
        DEFAULT_MULTI_PHOTO_FLAGS.enable_report_snapshot_v2,
      ),
    ),
    enable_multi_photo_coverage_v2: asBoolean(
      features.multi_photo_coverage_v2,
      asBoolean(
        record.enable_multi_photo_coverage_v2,
        DEFAULT_MULTI_PHOTO_FLAGS.enable_multi_photo_coverage_v2,
      ),
    ),
    coverage_repair_enabled: asBoolean(
      record.coverage_repair_enabled,
      DEFAULT_MULTI_PHOTO_FLAGS.coverage_repair_enabled,
    ),
    max_photo_count_free: asPositiveInt(
      record.max_photo_count_free,
      DEFAULT_MULTI_PHOTO_FLAGS.max_photo_count_free,
    ),
    max_photo_count_plus: asPositiveInt(
      record.max_photo_count_plus,
      DEFAULT_MULTI_PHOTO_FLAGS.max_photo_count_plus,
    ),
    max_photo_count_pro: asPositiveInt(
      record.max_photo_count_pro,
      DEFAULT_MULTI_PHOTO_FLAGS.max_photo_count_pro,
    ),
    max_findings_per_photo: asPositiveInt(
      record.max_findings_per_photo,
      DEFAULT_MULTI_PHOTO_FLAGS.max_findings_per_photo,
    ),
    target_findings_per_photo_min: asPositiveInt(
      record.target_findings_per_photo_min,
      DEFAULT_MULTI_PHOTO_FLAGS.target_findings_per_photo_min,
    ),
    target_findings_per_photo_max: asPositiveInt(
      record.target_findings_per_photo_max,
      DEFAULT_MULTI_PHOTO_FLAGS.target_findings_per_photo_max,
    ),
    target_findings_total_max: asPositiveInt(
      record.target_findings_total_max,
      DEFAULT_MULTI_PHOTO_FLAGS.target_findings_total_max,
    ),
  };
}

function parseClientReleaseContext(
  body: Record<string, unknown>,
): ClientReleaseContext {
  const appBuild = typeof body.client_app_build === "string"
    ? body.client_app_build.trim()
    : null;
  const appBuildNumber = appBuild ? asOptionalPositiveInt(appBuild) : null;
  const capabilities = body.client_capabilities &&
      typeof body.client_capabilities === "object"
    ? Object.fromEntries(
      Object.entries(body.client_capabilities as Record<string, unknown>)
        .map(([key, value]) => [key, value === true]),
    )
    : {};
  return {
    platform: typeof body.client_platform === "string"
      ? body.client_platform.trim().toLowerCase()
      : "unknown",
    appVersion: typeof body.client_app_version === "string"
      ? body.client_app_version.trim()
      : null,
    appBuild,
    appBuildNumber,
    apiContractVersion: asPositiveInt(body.api_contract_version, 1),
    capabilities,
  };
}

function releaseGateDecision(
  flags: MultiPhotoFeatureFlags,
  client: ClientReleaseContext,
): { open: boolean; reason: string } {
  if (flags.kill_switch) return { open: false, reason: "kill_switch" };
  if (client.platform !== "ios") return { open: false, reason: "platform" };
  if (client.apiContractVersion < 2) {
    return { open: false, reason: "api_contract" };
  }
  if (!client.appBuild) return { open: false, reason: "missing_build" };

  switch (flags.rollout_mode) {
    case "all":
      return { open: true, reason: "all" };
    case "build_allowlist":
      if (flags.enabled_ios_builds.includes(client.appBuild)) {
        return { open: true, reason: "build_allowlist" };
      }
      if (
        client.appBuildNumber != null &&
        flags.enabled_ios_builds
          .map((build) => asOptionalPositiveInt(build))
          .some((build) => build === client.appBuildNumber)
      ) {
        return { open: true, reason: "build_allowlist_numeric" };
      }
      return { open: false, reason: "build_not_allowed" };
    case "min_build":
      if (client.appBuildNumber == null || flags.min_ios_build == null) {
        return { open: false, reason: "missing_min_build" };
      }
      return client.appBuildNumber >= flags.min_ios_build
        ? { open: true, reason: "min_build" }
        : { open: false, reason: "build_below_min" };
    default:
      return { open: false, reason: "rollout_off" };
  }
}

function applyReleaseGateToFlags(
  flags: MultiPhotoFeatureFlags,
  client: ClientReleaseContext,
): MultiPhotoFeatureFlags {
  const decision = releaseGateDecision(flags, client);
  const supports = (feature: string) => client.capabilities[feature] === true;
  const enabled = (feature: string, flag: boolean) =>
    decision.open && supports(feature) && flag;
  return {
    ...flags,
    rollout_gate_open: decision.open,
    rollout_reason: decision.reason,
    enable_multi_photo_analysis: enabled(
      "multi_photo_analysis",
      flags.enable_multi_photo_analysis,
    ),
    enable_photo_limit_locked_slots_for_free: enabled(
      "multi_photo_analysis",
      flags.enable_photo_limit_locked_slots_for_free,
    ),
    enable_plus_pro_5_photo_limit: enabled(
      "multi_photo_analysis",
      flags.enable_plus_pro_5_photo_limit,
    ),
    enable_editable_findings: enabled(
      "editable_findings",
      flags.enable_editable_findings,
    ),
    enable_manual_finding_add: enabled(
      "manual_finding_add",
      flags.enable_manual_finding_add,
    ),
    enable_report_snapshot_v2: enabled(
      "report_snapshot_v2",
      flags.enable_report_snapshot_v2,
    ),
    enable_multi_photo_coverage_v2: enabled(
      "multi_photo_coverage_v2",
      flags.enable_multi_photo_coverage_v2,
    ),
  };
}

function coverageTargetsFromFlags(flags: MultiPhotoFeatureFlags): {
  targetMin: number;
  targetMax: number;
  targetTotalMax: number;
} {
  const targetMin = Math.max(1, flags.target_findings_per_photo_min);
  const targetMax = Math.max(targetMin, flags.target_findings_per_photo_max);
  const targetTotalMax = Math.max(targetMax, flags.target_findings_total_max);
  return { targetMin, targetMax, targetTotalMax };
}

function fallbackPhotoCapabilities(
  tier: PlanTier,
  flags: MultiPhotoFeatureFlags = DEFAULT_MULTI_PHOTO_FLAGS,
): PhotoCapabilities {
  const rule = DEFAULT_PLAN_CAPABILITY_RULES[tier];
  const paidMultiPhotoEnabled = flags.enable_multi_photo_analysis &&
    flags.enable_plus_pro_5_photo_limit &&
    tier !== "free";
  const maxPhotos = tier === "free"
    ? flags.max_photo_count_free
    : paidMultiPhotoEnabled
    ? (tier === "pro" ? flags.max_photo_count_pro : flags.max_photo_count_plus)
    : 1;
  const maxFindingsPerPhoto = flags.max_findings_per_photo ||
    rule.max_findings_per_photo;
  const coverageTargets = coverageTargetsFromFlags(flags);
  const maxFindingsPerAnalysis = Math.max(1, maxPhotos * maxFindingsPerPhoto);
  const coverageV2Enabled = flags.enable_multi_photo_coverage_v2 &&
    paidMultiPhotoEnabled &&
    maxPhotos > 1;
  return {
    plan: tier,
    maxPhotosPerAnalysis: Math.max(1, maxPhotos),
    visiblePhotoSlotsInUI: rule.visible_photo_slots_in_ui,
    maxFindingsPerPhoto,
    maxFindingsPerAnalysis,
    coverageV2Enabled,
    targetFindingsPerPhotoMin: coverageTargets.targetMin,
    targetFindingsPerPhotoMax: coverageTargets.targetMax,
    targetFindingsTotalMax: Math.min(
      maxFindingsPerAnalysis,
      coverageTargets.targetTotalMax,
    ),
    coverageRepairEnabled: flags.coverage_repair_enabled,
    canUseMultiPhotoAnalysis: paidMultiPhotoEnabled,
    canEditAIFindings: flags.enable_editable_findings &&
      rule.can_edit_ai_findings,
    canAddManualFindings: flags.enable_manual_finding_add &&
      rule.can_add_manual_findings,
    featureFlags: flags,
  };
}

async function resolvePhotoCapabilities(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  tier: PlanTier,
  client: ClientReleaseContext,
): Promise<PhotoCapabilities> {
  let flags = DEFAULT_MULTI_PHOTO_FLAGS;
  try {
    const { data } = await supabase
      .from("app_feature_flags")
      .select("value")
      .eq("key", "multi_photo_analysis")
      .maybeSingle();
    flags = applyReleaseGateToFlags(
      normalizeMultiPhotoFlags(data?.value),
      client,
    );
  } catch {
    flags = DEFAULT_MULTI_PHOTO_FLAGS;
  }

  try {
    const { data } = await supabase
      .from("plan_capability_rules")
      .select("*")
      .eq("plan", tier)
      .maybeSingle();
    const rule =
      (data ?? DEFAULT_PLAN_CAPABILITY_RULES[tier]) as PlanCapabilityRule;
    const paidMultiPhotoEnabled = flags.enable_multi_photo_analysis &&
      flags.enable_plus_pro_5_photo_limit &&
      tier !== "free";
    const maxPhotos = tier === "free"
      ? Math.min(rule.max_photos_per_analysis, flags.max_photo_count_free)
      : paidMultiPhotoEnabled
      ? Math.min(
        rule.max_photos_per_analysis,
        tier === "pro" ? flags.max_photo_count_pro : flags.max_photo_count_plus,
      )
      : 1;
    const maxFindingsPerPhoto = Math.min(
      rule.max_findings_per_photo,
      flags.max_findings_per_photo,
    );
    const maxFindingsPerAnalysis = Math.max(
      1,
      Math.min(
        rule.max_findings_per_analysis,
        maxPhotos * maxFindingsPerPhoto,
      ),
    );
    const coverageTargets = coverageTargetsFromFlags(flags);
    const coverageV2Enabled = flags.enable_multi_photo_coverage_v2 &&
      paidMultiPhotoEnabled &&
      maxPhotos > 1 &&
      rule.can_use_multi_photo_analysis;
    return {
      plan: tier,
      maxPhotosPerAnalysis: Math.max(1, maxPhotos),
      visiblePhotoSlotsInUI: rule.visible_photo_slots_in_ui,
      maxFindingsPerPhoto,
      maxFindingsPerAnalysis,
      coverageV2Enabled,
      targetFindingsPerPhotoMin: coverageTargets.targetMin,
      targetFindingsPerPhotoMax: coverageTargets.targetMax,
      targetFindingsTotalMax: Math.min(
        maxFindingsPerAnalysis,
        coverageTargets.targetTotalMax,
      ),
      coverageRepairEnabled: flags.coverage_repair_enabled,
      canUseMultiPhotoAnalysis: paidMultiPhotoEnabled &&
        rule.can_use_multi_photo_analysis,
      canEditAIFindings: flags.enable_editable_findings &&
        rule.can_edit_ai_findings,
      canAddManualFindings: flags.enable_manual_finding_add &&
        rule.can_add_manual_findings,
      featureFlags: flags,
    };
  } catch {
    return fallbackPhotoCapabilities(tier, flags);
  }
}

function photoCapabilitiesSnapshot(
  capabilities: PhotoCapabilities,
): Record<string, unknown> {
  return {
    plan: capabilities.plan,
    max_photos_per_analysis: capabilities.maxPhotosPerAnalysis,
    visible_photo_slots_in_ui: capabilities.visiblePhotoSlotsInUI,
    max_findings_per_photo: capabilities.maxFindingsPerPhoto,
    max_findings_per_analysis: capabilities.maxFindingsPerAnalysis,
    coverage_v2_enabled: capabilities.coverageV2Enabled,
    target_findings_per_photo_min: capabilities.targetFindingsPerPhotoMin,
    target_findings_per_photo_max: capabilities.targetFindingsPerPhotoMax,
    target_findings_total_max: capabilities.targetFindingsTotalMax,
    coverage_repair_enabled: capabilities.coverageRepairEnabled,
    can_use_multi_photo_analysis: capabilities.canUseMultiPhotoAnalysis,
    can_edit_ai_findings: capabilities.canEditAIFindings,
    can_add_manual_findings: capabilities.canAddManualFindings,
  };
}

function safeText(value: unknown, fallback = ""): string {
  if (value === null || value === undefined) return fallback;
  return String(value).trim();
}

function stripPhotoMarkerReferences(value: unknown): string {
  const text = safeText(value);
  if (!text) return "";
  return text
    .replace(
      /\bFOTO[_\s-]*(\d+)(?:'d[ae]|'t[ae]|'deki|deki|daki|taki|teki|’d[ae]|’t[ae]|de|da|te|ta)?\s*(?:ve\s+FOTO[_\s-]*\d+(?:'d[ae]|'t[ae]|'deki|deki|daki|taki|teki|’d[ae]|’t[ae]|de|da|te|ta)?\s*)*/giu,
      "",
    )
    .replace(/\bFOTO[_\s-]*\d+\b/giu, "")
    .replace(/^\s*(?:ve|ile)\s+/giu, "")
    .replace(/\s{2,}/g, " ")
    .replace(/\s+([,.])/g, "$1")
    .replace(/^\s*[,.;:-]\s*/g, "")
    .trim();
}

function stripFieldVerificationHedging(value: unknown): string {
  const text = safeText(value);
  if (!text) return "";
  return text
    .replace(
      /\s*\(?\b(?:sahada|yerinde)?\s*(?:doğrulanmalı|dogrulanmali|teyit edilmeli|kontrol edilmeli|ölçümle doğrulanmalı|olcumle dogrulanmali)\b\.?\)?/giu,
      "",
    )
    .replace(/\s{2,}/g, " ")
    .replace(/\s+([,.])/g, "$1")
    .trim();
}

function cleanHazardNarrative(value: unknown): string {
  return stripFieldVerificationHedging(stripPhotoMarkerReferences(value));
}

function sanitizePhotoHazardTextFields(
  hazard: Record<string, unknown>,
): Record<string, unknown> {
  const sanitized: Record<string, unknown> = { ...hazard };
  for (
    const field of [
      "observed_evidence",
      "description",
      "corrective_action",
      "preventive_control",
      "recommended_action",
      "root_cause",
      "references",
    ]
  ) {
    if (field in sanitized) {
      sanitized[field] = cleanHazardNarrative(sanitized[field]);
    }
  }

  if (Array.isArray(sanitized.recommended_measures)) {
    sanitized.recommended_measures = sanitized.recommended_measures.map(
      (item) => {
        if (!item || typeof item !== "object") return item;
        const record = item as Record<string, unknown>;
        return {
          ...record,
          text: cleanHazardNarrative(record.text),
        };
      },
    );
  }

  if (Array.isArray(sanitized.per_photo_observations)) {
    sanitized.per_photo_observations = sanitized.per_photo_observations.map(
      (item) => {
        if (!item || typeof item !== "object") return item;
        const record = item as Record<string, unknown>;
        return {
          ...record,
          observation: cleanHazardNarrative(record.observation),
        };
      },
    );
  }

  return sanitized;
}

function numericMetadata(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value !== "string") return null;
  const parsed = Number(value.trim());
  return Number.isFinite(parsed) ? parsed : null;
}

function imagePartMarkerText(part: AIImagePart): string {
  return `<foto index="${part.photoIndex}" label="FOTO_${part.photoIndex}">
Sıradaki görsel FOTO_${part.photoIndex}. Bu marker yalnızca makine-okunur kaynak eşleştirme içindir. Kullanıcıya gösterilecek title, observed_evidence, description, root_cause, corrective_action, preventive_control, references, photo_summaries ve per_photo_observations metinlerinde FOTO_${part.photoIndex} veya başka FOTO_* marker adını yazma. Bu görselden çıkardığın bulgularda source_photo_indices alanına yalnızca ${part.photoIndex} yaz. Aynı bulgu başka fotoğraflarda da görünüyorsa tüm ilgili FOTO numaralarını source_photo_indices içinde birleştir. Her fotoğraf için photo_summaries içinde ayrı özet üret.
</foto>`;
}

function imagePartAudit(part: AIImagePart): Record<string, unknown> {
  return {
    photo_index: part.photoIndex,
    source: part.source,
    width: part.width,
    height: part.height,
    decoded_byte_count: part.decodedByteCount,
    encoded_byte_count: part.encodedByteCount,
    jpeg_quality: part.jpegQuality,
    quality_policy: part.qualityPolicy,
    max_dimension: part.maxDimension,
  };
}

function normalizeRecommendedMeasures(
  hazard: Record<string, unknown>,
): Array<{ kind: string; title: string; text: string }> {
  const correctiveAction = safeText(hazard.corrective_action);
  const preventiveControl = safeText(hazard.preventive_control);
  const rawMeasures = Array.isArray(hazard.recommended_measures)
    ? hazard.recommended_measures
    : [];
  const normalized = rawMeasures
    .map((item) => {
      if (!item || typeof item !== "object") return null;
      const record = item as Record<string, unknown>;
      const rawKind = safeText(record.kind).toLowerCase();
      const kind = rawKind === "preventive" ? "preventive" : "corrective";
      const title = kind === "preventive"
        ? "Önleyici Kontrol"
        : "Düzeltici Önlem";
      const text = safeText(record.text);
      return text ? { kind, title, text } : null;
    })
    .filter((item): item is { kind: string; title: string; text: string } =>
      item !== null
    );

  const corrective = correctiveAction
    ? { kind: "corrective", title: "Düzeltici Önlem", text: correctiveAction }
    : normalized.find((measure) => measure.kind === "corrective");
  const preventive = preventiveControl
    ? { kind: "preventive", title: "Önleyici Kontrol", text: preventiveControl }
    : normalized.find((measure) => measure.kind === "preventive");
  const fallback = safeText(hazard.recommended_action);

  return [
    corrective ?? {
      kind: "corrective",
      title: "Düzeltici Önlem",
      text: fallback ||
        "Uygunsuzluğu sahada güvenli hale getirecek düzeltici kontrolü uygula.",
    },
    preventive ?? {
      kind: "preventive",
      title: "Önleyici Kontrol",
      text:
        "Tekrarı önlemek için kontrol sorumlusu, periyodik kontrol ve saha doğrulama kaydı tanımla.",
    },
  ];
}

function normalizeSourcePhotoIndices(
  value: unknown,
  photoCount: number,
): number[] {
  if (photoCount <= 0) return [];
  const raw = Array.isArray(value) ? value : [1];
  const indices = [
    ...new Set(
      raw
        .map((item) => Math.round(Number(item)))
        .filter((item) =>
          Number.isFinite(item) && item >= 1 && item <= photoCount
        ),
    ),
  ].sort((a, b) => a - b);
  return indices.length > 0 ? indices : [1];
}

function normalizePerPhotoObservations(
  value: unknown,
  sourcePhotoIndices: number[],
): Array<{ photo_index: number; observation: string }> {
  if (!Array.isArray(value)) return [];
  const allowed = new Set(sourcePhotoIndices);
  return value
    .slice(0, 8)
    .map((item) => {
      if (!item || typeof item !== "object") return null;
      const record = item as Record<string, unknown>;
      const photoIndex = Math.round(Number(record.photo_index));
      const observation = safeText(record.observation).slice(0, 600);
      if (!allowed.has(photoIndex) || !observation) return null;
      return { photo_index: photoIndex, observation };
    })
    .filter((item): item is { photo_index: number; observation: string } =>
      item !== null
    );
}

function enforceFindingBudget(
  hazards: unknown[],
  photoCount: number,
  maxFindingsPerPhoto: number,
  maxTotalFindings: number,
): Array<Record<string, unknown>> {
  const perPhotoCounts = new Map<number, number>();
  const accepted: Array<Record<string, unknown>> = [];

  for (const rawHazard of hazards) {
    if (!rawHazard || typeof rawHazard !== "object") continue;
    if (accepted.length >= maxTotalFindings) break;
    const hazard = rawHazard as Record<string, unknown>;
    const sourcePhotoIndices = normalizeSourcePhotoIndices(
      hazard.source_photo_indices,
      photoCount,
    );
    const wouldExceed = sourcePhotoIndices.some((photoIndex) =>
      (perPhotoCounts.get(photoIndex) ?? 0) >= maxFindingsPerPhoto
    );
    if (wouldExceed) continue;
    for (const photoIndex of sourcePhotoIndices) {
      perPhotoCounts.set(photoIndex, (perPhotoCounts.get(photoIndex) ?? 0) + 1);
    }
    accepted.push({
      ...hazard,
      source_photo_indices: sourcePhotoIndices,
      per_photo_observations: normalizePerPhotoObservations(
        hazard.per_photo_observations,
        sourcePhotoIndices,
      ),
    });
  }

  return accepted;
}

function hazardConfidence(hazard: Record<string, unknown>): number {
  const value = Number(hazard.confidence);
  return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0;
}

function hasHeightFatalityPattern(hazard: Record<string, unknown>): boolean {
  const text = [
    hazard.title,
    hazard.category,
    hazard.observed_evidence,
    hazard.description,
    hazard.root_cause,
  ].map((value) => safeText(value).toLocaleLowerCase("tr-TR")).join(" ");
  const heightMention =
    /\b(?:2|3|4|5|6|7|8|9|10)\s*(?:m|metre)\b/u.test(text) ||
    /yüksekte|yuksekte|açık kenar|acik kenar|kenar koruma|korkuluk|iskele|platform|döşeme boşluğu|doseme boslugu|merdiven/u
      .test(text);
  const protectionMissing =
    /korumasız|korumasiz|korkuluk yok|korkuluk eksik|kenar koruması yok|kenar korumasi yok|yaşam hattı yok|yasam hatti yok|emniyet kemeri yok|düşme|dusme/u
      .test(text);
  return heightMention && protectionMissing;
}

function calibratedRiskInputs(hazard: Record<string, unknown>): {
  fkP: number;
  fkF: number;
  fkS: number;
  m5P: number;
  m5S: number;
} {
  const fkP = clampFK(Number(hazard.fk_probability), FK_PROBABILITY_VALUES);
  const fkF = clampFK(Number(hazard.fk_frequency), FK_FREQUENCY_VALUES);
  let fkS = clampFK(Number(hazard.fk_severity), FK_SEVERITY_VALUES);
  const m5P = Math.max(
    1,
    Math.min(5, Math.round(Number(hazard.m5_probability))),
  );
  let m5S = Math.max(1, Math.min(5, Math.round(Number(hazard.m5_severity))));

  if (hazardConfidence(hazard) >= 0.7 && hasHeightFatalityPattern(hazard)) {
    fkS = Math.max(fkS, 40);
    m5S = 5;
  }

  return { fkP, fkF, fkS, m5P, m5S };
}

function coveragePolicyFor(
  capabilities: PhotoCapabilities,
  photoCount: number,
): MultiPhotoCoveragePolicy | null {
  if (photoCount < 1) return null;
  if (photoCount > 1 && !capabilities.coverageV2Enabled) return null;
  const targetMin = photoCount === 1
    ? SINGLE_PHOTO_TARGET_MIN
    : MULTI_PHOTO_TARGET_MIN;
  const targetMax = photoCount === 1 ? SINGLE_PHOTO_TARGET_MAX : Math.max(
    targetMin,
    MULTI_PHOTO_TARGET_MAX,
    capabilities.targetFindingsPerPhotoMax,
  );
  const totalMax = photoCount === 1 ? SINGLE_PHOTO_TARGET_MAX : Math.min(
    PHOTO_TARGET_TOTAL_MAX,
    capabilities.maxFindingsPerAnalysis,
    photoCount * MULTI_PHOTO_TARGET_MAX,
  );
  return {
    enabled: true,
    photoCount,
    targetMin,
    targetMax,
    totalMax,
    repairEnabled: capabilities.coverageRepairEnabled,
    policyVersion: PHOTO_POLICY_VERSION,
  };
}

function normalizeCoverageStatus(
  value: unknown,
  findingsCount: number,
  candidateCount: number,
): CoverageStatus {
  const raw = safeText(value).toLowerCase();
  if (raw === "low_quality") return "low_quality";
  if (raw === "no_actionable_hazard") return "no_actionable_hazard";
  if (raw === "actionable") return "actionable";
  return findingsCount > 0 || candidateCount > 0
    ? "actionable"
    : "no_actionable_hazard";
}

function normalizeCoverageGapReason(
  status: CoverageStatus,
  rawReason: unknown,
  findingsCount: number,
  targetMin: number,
  recordMissing: boolean,
): string | null {
  const reason = stripPhotoMarkerReferences(rawReason).slice(0, 500);
  if (status === "actionable" && findingsCount >= targetMin) return null;
  if (reason) return reason;
  if (recordMissing) {
    return "AI bu fotoğraf için ayrı coverage özeti döndürmedi.";
  }
  if (status === "low_quality") {
    return "Görüntü kalitesi güvenilir bulgu üretmek için yetersiz.";
  }
  if (status === "no_actionable_hazard") {
    return "Aksiyonlanabilir risk kanıtı güvenilir şekilde doğrulanamadı.";
  }
  if (findingsCount < targetMin) {
    return `Bu fotoğrafta ${targetMin} ayrı ve duplicate olmayan güvenilir risk kanıtı doğrulanamadı.`;
  }
  return null;
}

function sanitizeCoverageFinding(
  rawFinding: unknown,
  photoIndex: number,
  photoCount: number,
): Record<string, unknown> | null {
  if (!rawFinding || typeof rawFinding !== "object") return null;
  const sanitized = sanitizePhotoHazardTextFields(
    rawFinding as Record<string, unknown>,
  );
  const sourcePhotoIndices = normalizeSourcePhotoIndices(
    sanitized.source_photo_indices,
    photoCount,
  ).filter((index) => index === photoIndex);
  const effectiveSourcePhotoIndices = sourcePhotoIndices.length > 0
    ? sourcePhotoIndices
    : [photoIndex];
  return {
    ...sanitized,
    source_photo_indices: effectiveSourcePhotoIndices,
    per_photo_observations: normalizePerPhotoObservations(
      sanitized.per_photo_observations,
      effectiveSourcePhotoIndices,
    ),
  };
}

function normalizePhotoFindingCoverage(
  rawPhotoFindings: unknown,
  policy: MultiPhotoCoveragePolicy,
): NormalizedPhotoFindingCoverage[] | null {
  if (!Array.isArray(rawPhotoFindings)) return null;
  const recordsByPhoto = new Map<number, NormalizedPhotoFindingCoverage>();

  for (const item of rawPhotoFindings) {
    if (!item || typeof item !== "object") continue;
    const record = item as Record<string, unknown>;
    const photoIndex = Math.round(Number(record.photo_index));
    if (
      !Number.isFinite(photoIndex) || photoIndex < 1 ||
      photoIndex > policy.photoCount
    ) {
      continue;
    }
    const findings = (Array.isArray(record.findings) ? record.findings : [])
      .map((finding) =>
        sanitizeCoverageFinding(finding, photoIndex, policy.photoCount)
      )
      .filter((finding): finding is Record<string, unknown> => finding !== null)
      .slice(0, policy.targetMax);
    const candidateCount = Math.max(
      findings.length,
      Math.round(Number(record.candidate_findings_count ?? findings.length)),
    );
    const status = normalizeCoverageStatus(
      record.coverage_status,
      findings.length,
      candidateCount,
    );
    recordsByPhoto.set(photoIndex, {
      photo_index: photoIndex,
      coverage_status: status,
      scene_summary: stripPhotoMarkerReferences(record.scene_summary).slice(
        0,
        1200,
      ),
      candidate_findings_count: candidateCount,
      coverage_gap_reason: normalizeCoverageGapReason(
        status,
        record.coverage_gap_reason,
        findings.length,
        policy.targetMin,
        false,
      ),
      highest_risk_level: safeText(record.highest_risk_level).slice(0, 40) ||
        null,
      ai_confidence: typeof record.ai_confidence === "number"
        ? Math.max(0, Math.min(1, record.ai_confidence))
        : null,
      findings,
      record_missing: false,
    });
  }

  return Array.from({ length: policy.photoCount }, (_, index) => {
    const photoIndex = index + 1;
    return recordsByPhoto.get(photoIndex) ?? {
      photo_index: photoIndex,
      coverage_status: "no_actionable_hazard" as CoverageStatus,
      scene_summary: "",
      candidate_findings_count: 0,
      coverage_gap_reason: normalizeCoverageGapReason(
        "no_actionable_hazard",
        "",
        0,
        policy.targetMin,
        true,
      ),
      highest_risk_level: null,
      ai_confidence: null,
      findings: [],
      record_missing: true,
    };
  });
}

function mergeDuplicateCoverageHazards(
  hazards: Array<Record<string, unknown>>,
  photoCount: number,
  totalMax: number,
): Array<Record<string, unknown>> {
  const accepted: Array<Record<string, unknown>> = [];

  for (const hazard of hazards) {
    if (accepted.length >= totalMax) break;
    const key = coverageFindingKey(hazard);
    if (!key) continue;
    const sourcePhotoIndices = normalizeSourcePhotoIndices(
      hazard.source_photo_indices,
      photoCount,
    );
    const perPhotoObservations = normalizePerPhotoObservations(
      hazard.per_photo_observations,
      sourcePhotoIndices,
    );
    const existingIndex = accepted.findIndex((candidate) =>
      areLikelyDuplicateCoverageFindings(candidate, hazard)
    );
    if (existingIndex >= 0) {
      accepted[existingIndex] = mergeDuplicateCoverageFinding(
        accepted[existingIndex],
        hazard,
        photoCount,
      );
      continue;
    }
    const normalizedHazard = {
      ...hazard,
      source_photo_indices: sourcePhotoIndices,
      per_photo_observations: perPhotoObservations,
    };
    accepted.push(normalizedHazard);
  }

  return accepted;
}

function mergeDuplicateCoverageFinding(
  existing: Record<string, unknown>,
  incoming: Record<string, unknown>,
  photoCount: number,
): Record<string, unknown> {
  const mergedSourcePhotoIndices = [
    ...new Set([
      ...normalizeSourcePhotoIndices(existing.source_photo_indices, photoCount),
      ...normalizeSourcePhotoIndices(incoming.source_photo_indices, photoCount),
    ]),
  ].sort((a, b) => a - b);
  const observationKey = (
    item: { photo_index: number; observation: string },
  ) => `${item.photo_index}:${item.observation}`;
  const mergedObservations = [
    ...normalizePerPhotoObservations(
      existing.per_photo_observations,
      mergedSourcePhotoIndices,
    ),
    ...normalizePerPhotoObservations(
      incoming.per_photo_observations,
      mergedSourcePhotoIndices,
    ),
  ];
  const uniqueObservations = Array.from(
    new Map(
      mergedObservations.map((item) => [observationKey(item), item]),
    ).values(),
  ).slice(0, 10);

  return {
    ...preferredCoverageFinding(existing, incoming),
    source_photo_indices: mergedSourcePhotoIndices,
    per_photo_observations: uniqueObservations,
  };
}

function composeFindingDescription(hazard: Record<string, unknown>): string {
  const evidence = cleanHazardNarrative(hazard.observed_evidence);
  const description = cleanHazardNarrative(hazard.description);
  if (!evidence) return description;
  if (!description) return evidence;

  const overlap = tokenOverlapRatio(evidence, description);
  if (overlap >= 0.45) {
    return description.length >= evidence.length ? description : evidence;
  }

  return `${evidence}\n\n${description}`.trim();
}

function mergeCoverageRepairRecords(
  baseRecords: NormalizedPhotoFindingCoverage[],
  repairRecords: NormalizedPhotoFindingCoverage[],
  policy: MultiPhotoCoveragePolicy,
): void {
  const baseByPhoto = new Map(
    baseRecords.map((record) => [record.photo_index, record]),
  );
  for (const repair of repairRecords) {
    const base = baseByPhoto.get(repair.photo_index);
    if (!base) continue;
    if (repair.scene_summary) base.scene_summary = repair.scene_summary;
    base.highest_risk_level = repair.highest_risk_level ??
      base.highest_risk_level;
    base.ai_confidence = repair.ai_confidence ?? base.ai_confidence;
    if (
      repair.coverage_status !== "no_actionable_hazard" ||
      base.record_missing
    ) {
      base.coverage_status = repair.coverage_status;
    }
    base.record_missing = false;
    for (const finding of repair.findings) {
      if (base.findings.length >= policy.targetMax) break;
      const key = coverageFindingKey(finding);
      if (!key) continue;
      const existingIndex = base.findings.findIndex((existing) =>
        areLikelyDuplicateCoverageFindings(existing, finding)
      );
      if (existingIndex >= 0) {
        base.findings[existingIndex] = mergeDuplicateCoverageFinding(
          base.findings[existingIndex],
          finding,
          policy.photoCount,
        );
        continue;
      }
      base.findings.push(finding);
    }
    base.candidate_findings_count = Math.max(
      base.candidate_findings_count,
      repair.candidate_findings_count,
      base.findings.length,
    );
    base.coverage_gap_reason = normalizeCoverageGapReason(
      base.coverage_status,
      repair.coverage_gap_reason ?? base.coverage_gap_reason,
      base.findings.length,
      policy.targetMin,
      false,
    );
  }
}

function coverageRepairCandidates(
  records: NormalizedPhotoFindingCoverage[],
  policy: MultiPhotoCoveragePolicy,
): number[] {
  return records
    .filter((record) =>
      record.record_missing ||
      (record.coverage_status === "actionable" &&
        record.findings.length < policy.targetMin)
    )
    .map((record) => record.photo_index);
}

function normalizeRepairPhotoIndices(
  value: unknown,
  photoCount: number,
): number[] {
  if (photoCount <= 0 || !Array.isArray(value)) return [];
  return [
    ...new Set(
      value
        .map((item) => Math.round(Number(item)))
        .filter((item) =>
          Number.isFinite(item) && item >= 1 && item <= photoCount
        ),
    ),
  ].sort((a, b) => a - b);
}

function buildCoverageRepairContext(
  baseContext: string,
  policy: MultiPhotoCoveragePolicy,
  records: NormalizedPhotoFindingCoverage[],
  photoIndices: number[],
): string {
  const existingFindings = records
    .filter((record) => photoIndices.includes(record.photo_index))
    .map((record) => {
      const lines = record.findings
        .map((finding, index) =>
          `${index + 1}. ${safeText(finding.title)} | ${
            safeText(finding.observed_evidence)
          } | ${safeText(finding.corrective_action)}`
        )
        .join("\n");
      return `Foto ${record.photo_index}: mevcut ${record.findings.length} bulgu\n${
        lines || "Mevcut bulgu yok."
      }`;
    })
    .join("\n\n");

  return `${baseContext}
<coverage_repair_pass>
Yalnız şu fotoğraflar için ikinci kısa tarama yap: ${
    photoIndices.map((index) => `FOTO_${index}`).join(", ")
  }.
Amaç: bulgusu eksik görünen fotoğraflarda yalnız yeni, kanıtlı ve duplicate olmayan bulguları eklemek; fotoğraf başına üst sınır ${policy.targetMax}.
Mevcut bulguları tekrar etme; aynı kök neden + aynı kontrol tedbiri + aynı görsel kanıt varsa yeni bulgu sayma. Minimumu doldurmak için bulgu üretme.
Temiz, ilgisiz veya düşük kaliteli fotoğrafta risk uydurma; coverage_status değerini "no_actionable_hazard" veya "low_quality" yap ve coverage_gap_reason yaz.
Yanıtı yine photo_findings[] formatında üret; sadece istenen fotoğraf indekslerini döndür.
<mevcut_bulgular>
${existingFindings}
</mevcut_bulgular>
</coverage_repair_pass>`;
}

function buildPhotoSummariesFromCoverage(
  records: NormalizedPhotoFindingCoverage[],
  policy: MultiPhotoCoveragePolicy,
): Array<Record<string, unknown>> {
  return records.map((record) => ({
    photo_index: record.photo_index,
    scene_summary: record.scene_summary,
    candidate_findings_count: Math.max(
      record.candidate_findings_count,
      record.findings.length,
    ),
    generated_findings_count: record.findings.length,
    highest_risk_level: record.highest_risk_level,
    ai_confidence: record.ai_confidence,
    coverage_status: record.coverage_status,
    coverage_gap_reason: normalizeCoverageGapReason(
      record.coverage_status,
      record.coverage_gap_reason,
      record.findings.length,
      policy.targetMin,
      record.record_missing,
    ),
    target_findings_min: policy.targetMin,
    target_findings_max: policy.targetMax,
  }));
}

function responseSchema(
  tier: PlanTier,
  coveragePolicy?: MultiPhotoCoveragePolicy | null,
) {
  const includesPaidFields = tier !== "free";
  const hazardProperties: Record<string, unknown> = {
    title: { type: "STRING" },
    category: { type: "STRING" },
    observed_evidence: { type: "STRING" },
    description: { type: "STRING" },
    root_cause: { type: "STRING" },
    corrective_action: { type: "STRING" },
    preventive_control: { type: "STRING" },
    confidence: { type: "NUMBER" },
    needs_field_verification: { type: "BOOLEAN" },
    fk_probability: { type: "NUMBER" },
    fk_frequency: { type: "NUMBER" },
    fk_severity: { type: "NUMBER" },
    m5_probability: { type: "NUMBER" },
    m5_severity: { type: "NUMBER" },
    source_photo_indices: {
      type: "ARRAY",
      items: { type: "INTEGER" },
    },
    per_photo_observations: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          photo_index: { type: "INTEGER" },
          observation: { type: "STRING" },
        },
        required: ["photo_index", "observation"],
      },
    },
  };
  if (includesPaidFields) {
    hazardProperties.references = { type: "STRING" };
  }
  const requiredHazardFields = [
    "title",
    "category",
    "observed_evidence",
    "description",
    "root_cause",
    "corrective_action",
    "preventive_control",
    "confidence",
    "needs_field_verification",
    "fk_probability",
    "fk_frequency",
    "fk_severity",
    "m5_probability",
    "m5_severity",
    ...(includesPaidFields ? ["references"] : []),
  ];
  const hazardSchema = {
    type: "OBJECT",
    properties: hazardProperties,
    required: requiredHazardFields,
    propertyOrdering: [
      "title",
      "category",
      "observed_evidence",
      "description",
      "root_cause",
      "corrective_action",
      "preventive_control",
      "confidence",
      "needs_field_verification",
      "fk_probability",
      "fk_frequency",
      "fk_severity",
      "m5_probability",
      "m5_severity",
      ...(includesPaidFields ? ["references"] : []),
      "source_photo_indices",
      "per_photo_observations",
    ],
  };

  if (coveragePolicy?.enabled) {
    return {
      type: "OBJECT",
      properties: {
        photo_findings: {
          type: "ARRAY",
          items: {
            type: "OBJECT",
            properties: {
              photo_index: { type: "INTEGER" },
              coverage_status: { type: "STRING" },
              scene_summary: { type: "STRING" },
              candidate_findings_count: { type: "INTEGER" },
              coverage_gap_reason: { type: "STRING" },
              highest_risk_level: { type: "STRING" },
              ai_confidence: { type: "NUMBER" },
              findings: {
                type: "ARRAY",
                items: hazardSchema,
              },
            },
            required: [
              "photo_index",
              "coverage_status",
              "scene_summary",
              "candidate_findings_count",
              "findings",
            ],
          },
        },
        analysis_quality: {
          type: "OBJECT",
          properties: {
            photo_policy_version: { type: "STRING" },
            coverage_target_met: { type: "BOOLEAN" },
            shortfall_photo_indices: {
              type: "ARRAY",
              items: { type: "INTEGER" },
            },
            repair_recommended: { type: "BOOLEAN" },
          },
        },
        ai_summary: { type: "STRING" },
        photo_summaries: {
          type: "ARRAY",
          items: {
            type: "OBJECT",
            properties: {
              photo_index: { type: "INTEGER" },
              scene_summary: { type: "STRING" },
              candidate_findings_count: { type: "INTEGER" },
              highest_risk_level: { type: "STRING" },
              ai_confidence: { type: "NUMBER" },
              coverage_status: { type: "STRING" },
              coverage_gap_reason: { type: "STRING" },
            },
            required: ["photo_index", "scene_summary"],
          },
        },
        limitations: { type: "STRING" },
      },
      required: ["photo_findings", "ai_summary"],
    };
  }

  return {
    type: "OBJECT",
    properties: {
      hazards: {
        type: "ARRAY",
        items: hazardSchema,
      },
      ai_summary: { type: "STRING" },
      photo_summaries: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          properties: {
            photo_index: { type: "INTEGER" },
            scene_summary: { type: "STRING" },
            candidate_findings_count: { type: "INTEGER" },
            highest_risk_level: { type: "STRING" },
            ai_confidence: { type: "NUMBER" },
          },
          required: ["photo_index", "scene_summary"],
        },
      },
      limitations: { type: "STRING" },
    },
    required: ["hazards", "ai_summary"],
  };
}

function groqResponseSchemaInstruction(
  tier: PlanTier,
  coveragePolicy?: MultiPhotoCoveragePolicy | null,
): string {
  const referenceField = tier !== "free"
    ? `,\n          "references": "${
      tier === "pro"
        ? "emin olunan tam mevzuat referansı"
        : "emin olunan kısa mevzuat referansı"
    }"`
    : "";
  const rootCauseExample = tier === "pro"
    ? "sistematik kök neden özeti"
    : "kısa saha diliyle kök neden";
  if (coveragePolicy?.enabled) {
    return `Aşağıdaki JSON yapısına birebir uy. Markdown, açıklama veya kod bloğu ekleme:
{
  "photo_findings": [
    {
      "photo_index": 1,
      "coverage_status": "actionable",
      "scene_summary": "fotoğraftaki sahnenin kısa özeti",
      "candidate_findings_count": ${coveragePolicy.targetMin},
      "coverage_gap_reason": "",
      "highest_risk_level": "high",
      "ai_confidence": 0.7,
      "findings": [
        {
          "title": "kısa tehlike başlığı",
          "category": "risk kategorisi",
          "observed_evidence": "rapora uygun nesnel saha kanıtı",
          "description": "riskin kısa açıklaması",
          "root_cause": "${rootCauseExample}",
          "corrective_action": "mevcut uygunsuzluğu sahada düzelten kısa uygulanabilir önlem",
          "preventive_control": "tekrarını önleyen kısa kontrol/prosedür/izleme tedbiri",
          "confidence": 0.0,
          "needs_field_verification": false,
          "fk_probability": 1,
          "fk_frequency": 1,
          "fk_severity": 1,
          "m5_probability": 1,
          "m5_severity": 1,
          "source_photo_indices": [1],
          "per_photo_observations": [
            { "photo_index": 1, "observation": "fotoğraftaki kısa gözlem" }
          ]${referenceField}
        }
      ]
    }
  ],
  "photo_summaries": [
    {
      "photo_index": 1,
      "scene_summary": "fotoğraftaki sahnenin kısa özeti",
      "candidate_findings_count": ${coveragePolicy.targetMin},
      "highest_risk_level": "high",
      "ai_confidence": 0.7,
      "coverage_status": "actionable",
      "coverage_gap_reason": ""
    }
  ],
  "ai_summary": "kısa özet",
  "limitations": "varsa belirsizlikler"
}`;
  }
  return `Aşağıdaki JSON yapısına birebir uy. Markdown, açıklama veya kod bloğu ekleme:
{
  "hazards": [
    {
      "title": "kısa tehlike başlığı",
      "category": "risk kategorisi",
      "observed_evidence": "rapora uygun nesnel saha kanıtı; metin modunda kullanıcı notunu alıntılama",
      "description": "riskin kısa açıklaması",
      "root_cause": "${rootCauseExample}",
      "corrective_action": "mevcut uygunsuzluğu sahada düzelten kısa uygulanabilir önlem",
      "preventive_control": "tekrarını önleyen kısa kontrol/prosedür/izleme tedbiri",
      "confidence": 0.0,
      "needs_field_verification": false,
      "fk_probability": 1,
      "fk_frequency": 1,
      "fk_severity": 1,
      "m5_probability": 1,
      "m5_severity": 1${
    tier !== "free"
      ? ',\n      "references": "emin olunan kısa mevzuat referansı"'
      : ""
  }
    }
  ],
  "photo_summaries": [
    {
      "photo_index": 1,
      "scene_summary": "fotoğraftaki sahnenin kısa özeti",
      "candidate_findings_count": 3,
      "highest_risk_level": "high",
      "ai_confidence": 0.7
    }
  ],
  "ai_summary": "kısa özet",
  "limitations": "varsa belirsizlikler"
}`;
}

class GeminiAPIError extends Error {
  status: number;
  body: string;

  constructor(status: number, body: string) {
    super(`Gemini HTTP ${status}: ${body}`);
    this.status = status;
    this.body = body;
  }
}

class AIRequestTimeoutError extends Error {
  constructor(provider: string, timeoutMs: number) {
    super(`${provider} request timed out after ${timeoutMs}ms`);
  }
}

class AITruncatedResponseError extends Error {
  finishReason: string;

  constructor(finishReason: string) {
    super(`AI response truncated with finishReason=${finishReason}`);
    this.finishReason = finishReason;
  }
}

class GroqAPIError extends Error {
  status: number;
  body: string;

  constructor(status: number, body: string) {
    super(`Groq HTTP ${status}: ${body}`);
    this.status = status;
    this.body = body;
  }
}

type GeminiKeyAlias =
  | "gemini_primary"
  | "gemini_secondary"
  | "gemini_tertiary"
  | "gemini_paid_primary"
  | "gemini_paid_secondary";

type GroqKeyAlias = "groq_free_primary" | "groq_plus_pro_primary";

type AIProvider = "gemini" | "groq";

type GeminiKeyConfig = {
  alias: GeminiKeyAlias;
  key: string;
  pool: "free" | "paid";
};

type GroqKeyConfig = {
  alias: GroqKeyAlias;
  key: string;
};

type AISimulationMode = "429" | "500" | "502" | "503" | "504" | "invalid_json";

type AISimulationConfig = {
  enabled: boolean;
  mode: AISimulationMode | null;
  once: boolean;
  remainingFailures: number;
};

type TraceMeta = {
  requestID: string;
  supportID: string;
};

type GeminiAttemptFailure = {
  apiKeyAlias: GeminiKeyAlias;
  model: string;
  attempt: number;
  retryable: boolean;
  error: Record<string, unknown>;
};

function aiSimulationConfig(): AISimulationConfig {
  const enabled =
    Deno.env.get("RISKDETECTED_ENABLE_TEST_SIMULATION") === "true";
  const rawMode = Deno.env.get("SIMULATE_AI_ERROR_CODE")?.trim().toLowerCase();
  const validModes = new Set<AISimulationMode>([
    "429",
    "500",
    "502",
    "503",
    "504",
    "invalid_json",
  ]);
  const mode = validModes.has(rawMode as AISimulationMode)
    ? rawMode as AISimulationMode
    : null;
  const once = Deno.env.get("SIMULATE_AI_ERROR_ONCE") !== "false";

  return {
    enabled: enabled && mode !== null,
    mode,
    once,
    remainingFailures: once ? 1 : Number.POSITIVE_INFINITY,
  };
}

function maybeSimulateAIError(simulation?: AISimulationConfig) {
  if (
    !simulation?.enabled || !simulation.mode ||
    simulation.remainingFailures <= 0
  ) {
    return;
  }

  simulation.remainingFailures -= 1;
  console.warn(
    "RiskDetected AI simulation triggered",
    JSON.stringify({
      mode: simulation.mode,
      once: simulation.once,
    }),
  );

  if (simulation.mode === "invalid_json") {
    throw new SyntaxError("Simulated invalid AI JSON response.");
  }

  const status = Number(simulation.mode);
  throw new GeminiAPIError(
    status,
    JSON.stringify({
      error: {
        code: status,
        message: `Simulated Gemini HTTP ${status}`,
        status: status === 429 ? "RESOURCE_EXHAUSTED" : "UNAVAILABLE",
      },
    }),
  );
}

function tierRank(tier: PlanTier): number {
  switch (tier) {
    case "pro":
      return 2;
    case "plus":
      return 1;
    case "free":
    default:
      return 0;
  }
}

function normalizeTier(raw: unknown): PlanTier {
  return raw === "pro" || raw === "plus" ? raw : "free";
}

function hasActiveSubscription(
  row:
    | { status?: string | null; current_period_ends_at?: string | null }
    | null,
): boolean {
  if (!row) return false;
  if (
    !["active", "trialing", "grace_period"].includes(String(row.status ?? ""))
  ) return false;
  if (!row.current_period_ends_at) return true;
  const expiresAt = Date.parse(row.current_period_ends_at);
  return Number.isFinite(expiresAt) && expiresAt > Date.now();
}

function resolvePlanTier(
  subscription: {
    tier?: string | null;
    status?: string | null;
    current_period_ends_at?: string | null;
  } | null,
): PlanTier {
  return hasActiveSubscription(subscription)
    ? normalizeTier(subscription?.tier)
    : "free";
}

function canUseCanvas(tier: PlanTier, canvasID: string): boolean {
  if (PRO_CANVASES.has(canvasID)) return tier === "pro";
  if (PLUS_CANVASES.has(canvasID)) return tier === "plus" || tier === "pro";
  return !PAID_CANVASES.has(canvasID);
}

function normalizeAnalysisMode(
  rawMode: unknown,
  canvasIDs: string[],
): AnalysisMode {
  if (
    rawMode === "detailed" || rawMode === "emergency" || rawMode === "procedure"
  ) {
    return rawMode;
  }
  if (canvasIDs.some((id) => DETAILED_CANVASES.has(id))) return "detailed";
  return "standard";
}

function istanbulDayStartISO(): string {
  const day = new Intl.DateTimeFormat("en-CA", {
    timeZone: BUSINESS_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
  return `${day}T00:00:00+03:00`;
}

function buildSystemPrompt(): string {
  return CORE_ANALYSIS_PROMPT;
}

function buildSubscriptionContext(
  tier: PlanTier,
  findingPolicy?: AnalysisFindingPolicy,
): string {
  const minHazards = PLAN_LIMITS[tier].minHazards;
  const maxHazards = PLAN_LIMITS[tier].maxHazards;
  const hazardCountRule = findingPolicy && findingPolicy.photoCount > 0
    ? findingPolicy.coverageV2Enabled
      ? `Bu analizde ${findingPolicy.photoCount} fotoğraf var. Görseller FOTO_1...FOTO_${findingPolicy.photoCount} marker'larıyla sırayla verilir; source_photo_indices alanında sadece bu marker numaralarını kullan. FOTO_* marker adlarını kullanıcıya gösterilecek hiçbir metin alanında yazma; kullanıcı metinde yalnızca "Foto 1" gibi kaynak etiketini arayüzde görür. Çıktıyı photo_findings[] formatında fotoğraf bazlı üret. Her fotoğraf için coverage_status alanını "actionable", "no_actionable_hazard" veya "low_quality" olarak yaz. Aksiyonlanabilir risk kanıtı olan her fotoğrafta yalnız kanıta dayalı ve duplicate olmayan bulguları üret; fotoğraf başına üst sınır ${findingPolicy.targetFindingsPerPhotoMax}, toplam final bulgu üst sınırı ${findingPolicy.maxFindingsTotal}. Temiz, ilgisiz, çok bulanık veya risk kanıtı zayıf fotoğrafta bulgu uydurma; listeyi doldurmak için aynı tehlikeyi farklı başlıklarla tekrar yazma; coverage_gap_reason alanında neden düşük kaldığını açıkla. Aynı tehlikeyi aynı kök neden, aynı kontrol tedbiri veya aynı görsel kanıt varsa birleştir; farklı fotoğraftaki farklı tehlikeleri yalnız sayıyı azaltmak için birleştirme. Her bulguda source_photo_indices, per_photo_observations ve fotoğraf özeti alanlarını doldur.`
      : `Bu analizde ${findingPolicy.photoCount} fotoğraf var. Görseller FOTO_1...FOTO_${findingPolicy.photoCount} marker'larıyla sırayla verilir; source_photo_indices alanında sadece bu marker numaralarını kullan. FOTO_* marker adlarını kullanıcıya gösterilecek hiçbir metin alanında yazma; kullanıcı metinde yalnızca "Foto 1" gibi kaynak etiketini arayüzde görür. Her fotoğraf için photo_summaries içinde ayrı özet üret. Her fotoğraf için 12 katmanlı taramadan çıkan tüm anlamlı bulgu adaylarını yaz; fotoğraf başına en fazla ${findingPolicy.maxFindingsPerPhoto}, toplamda en fazla ${findingPolicy.maxFindingsTotal} final bulgu üret. Kanıt varsa listeyi gereksiz kısaltma: çok fotoğraflı bir analizde tehlike kanıtı güçlü olan her fotoğraftan genellikle birden fazla bulgu beklenir. Risk kanıtı zayıfsa bulgu uydurma. Aynı tehlikeyi yalnız aynı kök neden ve aynı kontrol tedbiri olduğunda birleştir; farklı fotoğraftaki farklı tehlikeleri yalnız sayıyı azaltmak için birleştirme. source_photo_indices ve per_photo_observations alanlarını doldur.`
    : minHazards && maxHazards
    ? `${minHazards} ile ${maxHazards} arasında tehlike döndür; önem sırasına göre sırala.`
    : maxHazards
    ? `En fazla ${maxHazards} tehlike döndür; önem sırasına göre sırala.`
    : "10 ile 13 arasında bulgu döndür. Daha azı eksik, daha fazlası odak dağıtır.";

  if (tier === "free") {
    return `<abonelik_seviyesi tier="free">
ÇIKTI KAPSAMI:
- ${hazardCountRule}
- root_cause alanını her bulguda en fazla 1 kısa cümleyle üret.
- references alanı üretme; ayrı mevzuat/referans alanı Free'de kapalı.
- corrective_action veya preventive_control alanlarında kullanıcıya uygulanabilir değer sağlayan standart veya mevzuat adı geçebilir.
- RG tarihi, uzun mevzuat dökümü, madde listesi veya ayrı referans açıklaması verme.
</abonelik_seviyesi>`;
  }

  if (tier === "plus") {
    return `<abonelik_seviyesi tier="plus">
ÇIKTI KAPSAMI:
- ${hazardCountRule}
- Her bulguda references alanını kısa tut: kanun/yönetmelik adı + yalnız emin olduğun kısa madde bilgisi.
- RG tarihi verme; standart numarasını sadece kritik ve güvenli olduğun durumda kısa yaz.
- Her bulguda root_cause alanını en fazla 1 kısa cümleyle, saha diliyle yaz.
</abonelik_seviyesi>`;
  }

  return `<abonelik_seviyesi tier="pro">
ÇIKTI KAPSAMI:
- ${hazardCountRule}
- Her bulguda references alanını daha tam yaz: yönetmelik/kanun + madde + güvenliysen RG tarihi.
- TS EN/ISO gibi standartları yalnız ilgili ve emin olduğun bulgularda kullan; emin değilsen standart numarası yazma.
- Her bulguda root_cause alanını sistematik, teknik ve kısa kök neden perspektifiyle yaz.
</abonelik_seviyesi>`;
}

function safeStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => typeof item === "string" ? item.trim() : "")
    .filter((item) => item.length > 0);
}

function certificateContext(value: string | null): string {
  switch (value) {
    case "A":
      return "Uzmanlık: A sınıfı İSG uzmanı. Teknik derinlik yüksek; sistem etkileşimleri, ölümcül potansiyel ve kök neden dili daha profesyonel olabilir.";
    case "B":
      return "Uzmanlık: B sınıfı İSG uzmanı. Saha uygulamasına dönük, profesyonel ama hızlı tüketilebilir aksiyonlar öncelikli.";
    case "C":
      return "Uzmanlık: C sınıfı İSG uzmanı. Pratik, anlaşılır ve sahada hemen uygulanabilir aksiyon dili kullan.";
    case "doctor":
      return "Profil: İşyeri hekimi. Sağlık gözetimi, maruziyet, ergonomi ve hijyen boyutunu uygun olduğunda hatırlat; İSG uzmanı yetkisi varsayma.";
    case "otherHealth":
      return "Profil: Diğer sağlık personeli. Sağlık gözetimi, ilk yardım, maruziyet ve saha bildirimlerini uygun olduğunda sade dille hatırlat.";
    default:
      return "Uzmanlık: Belirtilmedi. Nötr, profesyonel ve uygulanabilir İSG dili kullan.";
  }
}

function onboardingHazardContext(values: string[]): string {
  if (values.length === 0) {
    return "Tehlike sınıfı: Belirtilmedi. Görsel/metin kanıtına göre standart risk kalibrasyonu uygula.";
  }

  const labels = values.map((value) => {
    switch (value) {
      case "critical":
        return "Çok Tehlikeli";
      case "high":
        return "Tehlikeli";
      case "low":
        return "Az Tehlikeli";
      default:
        return value;
    }
  }).join(", ");

  const guidance: string[] = [];
  if (values.includes("critical")) {
    guidance.push(
      "ölümcül potansiyelli düşme, elektrik, ezilme, patlama, kapalı alan ve kaldırma risklerini güçlü önceliklendir",
    );
  }
  if (values.includes("high")) {
    guidance.push(
      "makine koruyucu, kimyasal maruziyet, manuel taşıma, yangın ve yetkinlik kontrollerini öne çıkar",
    );
  }
  if (values.includes("low")) {
    guidance.push(
      "ergonomi, ekranlı çalışma, aydınlatma, tahliye, ilk yardım ve psikososyal riskleri uygun olduğunda hatırlat",
    );
  }

  return `Tehlike sınıfı odağı: ${labels}. ${
    guidance.join("; ")
  }. Profil puanlamayı yumuşatmaz; görselde kritik risk varsa kritik puanla.`;
}

function sectorContext(values: string[]): string {
  if (values.length === 0) {
    return "Sektör: Belirtilmedi. Görselde baskın sektör neyse ona göre risk ailelerini seç.";
  }

  const guidance = values.slice(0, 2).map((value) => {
    switch (value) {
      case "construction":
        return "İnşaat: yüksekten düşme, açık kenar, iskele, kazı, vinç, düşen cisim ve saha düzeni";
      case "manufacturing":
        return "İmalat: makine koruyucuları, acil stop, LOTO, CE, gürültü, titreşim, toz ve kimyasal maruziyet";
      case "energy":
        return "Enerji: LOTO, elektrik yaklaşma mesafesi, ark riski, topraklama, kapalı alan ve patlayıcı ortam";
      case "mining":
        return "Maden: göçük, havalandırma, toz, patlayıcı atmosfer, hareketli ekipman ve acil kaçış";
      case "office":
        return "Ofis/hizmet: ergonomi, aydınlatma, iç hava kalitesi, tahliye, yangın ekipmanı ve psikososyal riskler";
      case "other":
        return "Diğer: görsel/metin kanıtına göre lojistik, sağlık, tarım veya perakende risklerini dikkatle ayır";
      default:
        return value;
    }
  });

  return `Sektör odağı: ${
    guidance.join(" | ")
  }. Sektör profili filtre değildir; fotoğraftaki baskın gerçeklik önceliklidir.`;
}

function frequencyContext(value: string | null): string {
  switch (value) {
    case "1":
      return "Denetim sıklığı: Tek odak/az denetim. Aksiyonları biraz daha açıklayıcı ve adım odaklı yaz.";
    case "2-5":
      return "Denetim sıklığı: Standart yoğunluk. Dengeli teknik dil ve kısa açıklayıcı notlar kullan.";
    case "6-15":
      return "Denetim sıklığı: Yüksek tempo. Doğrudan, taranabilir ve net saha komutu dili kullan.";
    case "15+":
      return "Denetim sıklığı: Çok yoğun saha. Jenerik açıklamayı azalt; aksiyonları kısa, net ve öncelik odaklı yaz.";
    default:
      return "Denetim sıklığı: Belirtilmedi. Dengeli teknik dil kullan.";
  }
}

function buildOnboardingContext(
  row: OnboardingAnswersRow | null,
  hasActiveSector: boolean,
): OnboardingContext {
  const certificateClass = typeof row?.certificate_class === "string"
    ? row.certificate_class
    : null;
  const hazardClasses = safeStringArray(row?.hazard_classes);
  const sectors = safeStringArray(row?.sectors);
  const auditFrequency = typeof row?.audit_frequency === "string"
    ? row.audit_frequency
    : null;
  const applied = Boolean(
    certificateClass || hazardClasses.length > 0 || sectors.length > 0 ||
      auditFrequency,
  );
  const sectorLine = hasActiveSector
    ? `Onboarding sektörleri (${sectors.length}): ${
      sectors.length > 0 ? sectors.join(", ") : "belirtilmedi"
    }. ${onboardingSectorProfileRule(true)}`
    : sectorContext(sectors);

  const block = `<kullanici_profili applied="${applied ? "true" : "false"}">
Bu profil çıktının tonunu ve önceliklerini şekillendirir; tarama prosedürünü veya görsel/metin kanıtını asla atlatmaz.
- ${certificateContext(certificateClass)}
- ${onboardingHazardContext(hazardClasses)}
- ${sectorLine}
- ${frequencyContext(auditFrequency)}
</kullanici_profili>`;

  return {
    block,
    applied,
    certificateClass,
    hazardClasses,
    sectors,
    auditFrequency,
  };
}

function buildAnalysisContext(params: {
  canvases: string[];
  tier: PlanTier;
  onboardingContext: OnboardingContext;
  companyContext: string | null;
  activeSector: AnalysisSectorId | null;
  findingPolicy?: AnalysisFindingPolicy;
}): string {
  const focusLines = params.canvases
    .filter((c) => c !== "general")
    .map((c) => CANVAS_FOCUS[c])
    .filter(Boolean)
    .join(" ") ||
    CANVAS_FOCUS["general"];
  const activeSectorBlock = buildActiveSectorPromptBlock({
    sector: params.activeSector,
    outputLanguage: "tr",
  });

  return `<analiz_baglami prompt_version="${PROMPT_VERSION}" personalization_version="${PERSONALIZATION_VERSION}">
<odak>${focusLines}</odak>
	${buildSubscriptionContext(params.tier, params.findingPolicy)}
${activeSectorBlock}
${params.onboardingContext.block}
${params.companyContext ?? ""}
KRİTİK ÇELİŞKİ KURALLARI:
- Abonelik kapsamı çıktı alanlarını belirler.
- Profil veya firma "ofis/az tehlikeli" dese bile görselde inşaat, elektrik, yüksekte çalışma veya ölümcül risk varsa onu raporla.
- Emin olmadığın mevzuat maddesini, RG tarihini, ölçüm değerini veya standart numarasını uydurma.
</analiz_baglami>`;
}

function hazardClassLabel(value: unknown): string {
  switch (value) {
    case "low":
      return "Az Tehlikeli";
    case "high":
      return "Çok Tehlikeli";
    case "medium":
    default:
      return "Tehlikeli";
  }
}

function companyPromptContext(company: CompanyRow | null): string | null {
  if (!company) return null;
  return `FİRMA BAĞLAMI: Analiz "${company.name}" firması için yapılıyor. Firma tehlike sınıfı: ${
    hazardClassLabel(company.hazard_class)
  }. Bu bağlamı risk önceliklendirmede kullan; ancak görsel/metin kanıtı olmayan bulgu veya mevzuat detayı uydurma.`;
}

async function callGemini(
  apiKey: string,
  model: string,
  systemPrompt: string,
  analysisContext: string,
  userText: string | null,
  imageBase64Parts: AIImagePart[],
  pool: "free" | "paid",
  tier: PlanTier,
  simulation?: AISimulationConfig,
  coveragePolicy?: MultiPhotoCoveragePolicy | null,
  options: AIRequestOptions = {},
) {
  void userText;
  maybeSimulateAIError(simulation);

  const parts: unknown[] = [];
  parts.push({ text: analysisContext });
  for (const img of imageBase64Parts) {
    parts.push({ text: imagePartMarkerText(img) });
    parts.push({ inlineData: { mimeType: img.mimeType, data: img.data } });
  }
  if (imageBase64Parts.length === 0) {
    throw new Error("En az bir fotoğraf gerekli.");
  }

  const url = `${GEMINI_API_BASE}/${model}:generateContent?key=${apiKey}`;
  const isRepairPass = options.isRepairPass === true;
  const thinkingConfig = geminiThinkingConfig(model, pool, isRepairPass);
  const baseMaxOutputTokens = maxOutputTokensFor(imageBase64Parts.length, tier);
  let jsonParseRetryCount = 0;
  let maxOutputTokens = baseMaxOutputTokens;

  for (let attempt = 0; attempt < 2; attempt += 1) {
    const body = {
      system_instruction: { parts: [{ text: systemPrompt }] },
      contents: [{ role: "user", parts }],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: responseSchema(tier, coveragePolicy),
        temperature: 0.2,
        maxOutputTokens,
        ...(thinkingConfig ? { thinkingConfig } : {}),
      },
    };

    const res = await fetchWithTimeout(
      url,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      },
      isRepairPass ? REPAIR_AI_TIMEOUT_MS : MAIN_AI_TIMEOUT_MS,
      "Gemini",
    );

    if (!res.ok) {
      const errText = await res.text();
      throw new GeminiAPIError(res.status, errText);
    }

    const json = await res.json();
    const candidate = json.candidates?.[0];
    if (!candidate) throw new Error("Gemini yanıt boş.");
    const finishReason = String(candidate.finishReason ?? "");
    if (finishReason === "MAX_TOKENS") {
      if (attempt === 0 && maxOutputTokens < 48_000) {
        jsonParseRetryCount += 1;
        maxOutputTokens = Math.min(48_000, maxOutputTokens + 8_000);
        continue;
      }
      throw new AITruncatedResponseError(finishReason);
    }
    if (
      finishReason &&
      !["STOP", "FINISH_REASON_UNSPECIFIED"].includes(finishReason)
    ) {
      throw new Error(`Gemini finishReason=${finishReason}`);
    }

    const text = candidate.content?.parts?.[0]?.text;
    if (!text) throw new Error("Gemini yanıtında metin yok.");

    return {
      result: JSON.parse(text),
      inputTokens: json.usageMetadata?.promptTokenCount ?? 0,
      outputTokens: json.usageMetadata?.candidatesTokenCount ?? 0,
      cachedTokens: json.usageMetadata?.cachedContentTokenCount ?? null,
      thoughtsTokens: json.usageMetadata?.thoughtsTokenCount ?? null,
      totalTokens: json.usageMetadata?.totalTokenCount ?? null,
      finishReason: finishReason || "STOP",
      jsonParseRetryCount,
      thinkingBudget: model === MODEL_FLASH_LITE
        ? null
        : thinkingBudgetFor(isRepairPass),
      maxOutputTokens,
    };
  }

  throw new AITruncatedResponseError("MAX_TOKENS");
}

function decodedBase64ByteLength(base64: string): number {
  const normalized = base64.replace(/\s/g, "");
  const padding = normalized.endsWith("==")
    ? 2
    : normalized.endsWith("=")
    ? 1
    : 0;
  return Math.max(0, Math.floor((normalized.length * 3) / 4) - padding);
}

function isValidStandardBase64(value: string): boolean {
  const normalized = value.replace(/\s/g, "");
  return normalized.length > 0 &&
    normalized.length % 4 !== 1 &&
    /^[A-Za-z0-9+/]*={0,2}$/.test(normalized);
}

function validateInlinePhotoInput(
  inlinePhotoParts: unknown,
  requestedPhotoPaths: string[],
): { ok: true } | { ok: false; code: string; message: string } {
  const parts = Array.isArray(inlinePhotoParts) ? inlinePhotoParts : [];
  const totalImageParts = requestedPhotoPaths.length + parts.length;
  if (totalImageParts > MAX_ANALYSIS_IMAGE_PARTS) {
    return {
      ok: false,
      code: "too_many_photos",
      message:
        `Analiz için en fazla ${MAX_ANALYSIS_IMAGE_PARTS} fotoğraf gönderebilirsin.`,
    };
  }

  let totalEncodedBytes = 0;
  for (const part of parts) {
    const source = part as {
      data?: unknown;
      mime_type?: unknown;
      mimeType?: unknown;
    };
    const data = typeof source?.data === "string"
      ? source.data.replace(/\s/g, "")
      : "";
    if (!isValidStandardBase64(data)) {
      return {
        ok: false,
        code: "invalid_photo_payload",
        message: "Fotoğraf verisi geçersiz.",
      };
    }

    const rawMime = String(source.mime_type ?? source.mimeType ?? "")
      .toLowerCase();
    if (
      rawMime.length > 0 &&
      !rawMime.includes("jpeg") &&
      !rawMime.includes("jpg") &&
      !rawMime.includes("png")
    ) {
      return {
        ok: false,
        code: "unsupported_photo_type",
        message: "Fotoğraf formatı JPEG veya PNG olmalı.",
      };
    }

    if (data.length > MAX_INLINE_PHOTO_BASE64_BYTES) {
      return {
        ok: false,
        code: "photo_too_large",
        message: "Fotoğraf dosyası analiz için çok büyük.",
      };
    }

    const decodedBytes = decodedBase64ByteLength(data);
    if (decodedBytes > MAX_INLINE_PHOTO_DECODED_BYTES) {
      return {
        ok: false,
        code: "photo_too_large",
        message: "Fotoğraf dosyası analiz için çok büyük.",
      };
    }

    totalEncodedBytes += data.length;
    if (totalEncodedBytes > MAX_INLINE_PHOTO_TOTAL_BASE64_BYTES) {
      return {
        ok: false,
        code: "photo_package_too_large",
        message: "Fotoğraf paketi çok büyük.",
      };
    }
  }

  return { ok: true };
}

async function callGroq(
  apiKey: string,
  model: string,
  systemPrompt: string,
  analysisContext: string,
  userText: string | null,
  imageBase64Parts: AIImagePart[],
  tier: PlanTier,
  simulation?: AISimulationConfig,
  coveragePolicy?: MultiPhotoCoveragePolicy | null,
  options: AIRequestOptions = {},
) {
  void userText;
  maybeSimulateAIError(simulation);

  if (imageBase64Parts.length === 0) {
    throw new Error("En az bir fotoğraf gerekli.");
  }
  if (imageBase64Parts.length > GROQ_MAX_BASE64_IMAGES) {
    throw new Error(
      `Groq fallback en fazla ${GROQ_MAX_BASE64_IMAGES} fotoğraf destekler.`,
    );
  }

  const content: unknown[] = [
    {
      type: "text",
      text: [
        groqResponseSchemaInstruction(tier, coveragePolicy),
        analysisContext,
      ].filter(Boolean).join("\n\n"),
    },
  ];

  for (const img of imageBase64Parts) {
    const byteLength = decodedBase64ByteLength(img.data);
    if (byteLength > GROQ_MAX_BASE64_IMAGE_BYTES) {
      throw new Error(
        "Groq fallback fotoğraf boyutu limitini aşıyor.",
      );
    }
    content.push({
      type: "text",
      text: imagePartMarkerText(img),
    });
    content.push({
      type: "image_url",
      image_url: {
        url: `data:${img.mimeType};base64,${img.data}`,
      },
    });
  }

  const isRepairPass = options.isRepairPass === true;
  const maxCompletionTokens = coveragePolicy?.enabled
    ? Math.min(16_000, maxOutputTokensFor(imageBase64Parts.length, tier))
    : 8_000;
  const body = {
    model,
    messages: [
      { role: "system", content: systemPrompt },
      { role: "user", content },
    ],
    response_format: { type: "json_object" },
    temperature: 0.2,
    max_completion_tokens: maxCompletionTokens,
  };

  const res = await fetchWithTimeout(
    GROQ_API_URL,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    },
    isRepairPass ? REPAIR_AI_TIMEOUT_MS : MAIN_AI_TIMEOUT_MS,
    "Groq",
  );

  if (!res.ok) {
    const errText = await res.text();
    throw new GroqAPIError(res.status, errText);
  }

  const json = await res.json();
  const text = json.choices?.[0]?.message?.content;
  if (!text) throw new Error("Groq yanıtında metin yok.");

  return {
    result: JSON.parse(text),
    inputTokens: json.usage?.prompt_tokens ?? 0,
    outputTokens: json.usage?.completion_tokens ?? 0,
    cachedTokens: null,
    thoughtsTokens: null,
    totalTokens: json.usage?.total_tokens ??
      ((json.usage?.prompt_tokens ?? 0) + (json.usage?.completion_tokens ?? 0)),
    finishReason: String(json.choices?.[0]?.finish_reason ?? "stop"),
    jsonParseRetryCount: 0,
    thinkingBudget: null,
    maxOutputTokens: maxCompletionTokens,
  };
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMs: number,
  provider: string,
): Promise<Response> {
  const controller = new AbortController();
  const timeoutID = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new AIRequestTimeoutError(provider, timeoutMs);
    }
    throw error;
  } finally {
    clearTimeout(timeoutID);
  }
}

function orderGeminiKeys(
  keys: GeminiKeyConfig[],
  preferredAlias: string | undefined,
): GeminiKeyConfig[] {
  if (!preferredAlias) return keys;

  const preferredIndex = keys.findIndex((item) =>
    item.alias === preferredAlias
  );
  if (preferredIndex < 0) return keys;

  const preferred = keys[preferredIndex];
  return [
    preferred,
    ...keys.filter((_, index) => index !== preferredIndex),
  ];
}

function freeGeminiKeyPool(): GeminiKeyConfig[] {
  const primary = Deno.env.get("GEMINI_API_KEY_PRIMARY") ??
    Deno.env.get("GEMINI_API_KEY");
  const secondary = Deno.env.get("GEMINI_API_KEY_SECONDARY");
  const tertiary = Deno.env.get("GEMINI_API_KEY_TERTIARY");

  const rawKeys: Array<GeminiKeyConfig | null> = [
    primary
      ? {
        alias: "gemini_primary" as const,
        key: primary,
        pool: "free" as const,
      }
      : null,
    secondary
      ? {
        alias: "gemini_secondary" as const,
        key: secondary,
        pool: "free" as const,
      }
      : null,
    tertiary
      ? {
        alias: "gemini_tertiary" as const,
        key: tertiary,
        pool: "free" as const,
      }
      : null,
  ];
  const keys = rawKeys.filter((item): item is GeminiKeyConfig => item !== null);

  return orderGeminiKeys(
    keys,
    Deno.env.get("GEMINI_FREE_PREFERRED_KEY_ALIAS")?.trim() ||
      Deno.env.get("GEMINI_PREFERRED_KEY_ALIAS")?.trim(),
  );
}

function paidGeminiKeyPool(): GeminiKeyConfig[] {
  const primary = Deno.env.get("GEMINI_API_KEY_PAID") ??
    Deno.env.get("GEMINI_PAID_API_KEY");
  const secondary = Deno.env.get("GEMINI_API_KEY_PAID_SECONDARY");

  const rawKeys: Array<GeminiKeyConfig | null> = [
    primary
      ? {
        alias: "gemini_paid_primary" as const,
        key: primary,
        pool: "paid" as const,
      }
      : null,
    secondary
      ? {
        alias: "gemini_paid_secondary" as const,
        key: secondary,
        pool: "paid" as const,
      }
      : null,
  ];
  const keys = rawKeys.filter((item): item is GeminiKeyConfig => item !== null);

  return orderGeminiKeys(
    keys,
    Deno.env.get("GEMINI_PAID_PREFERRED_KEY_ALIAS")?.trim(),
  );
}

function freeGroqKeyConfig(): GroqKeyConfig | null {
  const key = Deno.env.get("GROQ_API_KEY_FREE") ?? Deno.env.get("GROQ_API_KEY");
  return key
    ? {
      alias: "groq_free_primary",
      key,
    }
    : null;
}

function freeGroqModel(): string {
  return Deno.env.get("GROQ_FREE_MODEL")?.trim() || MODEL_GROQ_FREE_DEFAULT;
}

function plusProGroqKeyConfig(): GroqKeyConfig | null {
  const key = Deno.env.get("GROQ_API_KEY_PLUS_PRO") ??
    Deno.env.get("GROQ_API_KEY_PAID");
  return key
    ? {
      alias: "groq_plus_pro_primary",
      key,
    }
    : null;
}

function plusProGroqModel(): string {
  return Deno.env.get("GROQ_PLUS_PRO_MODEL")?.trim() ||
    Deno.env.get("GROQ_PAID_MODEL")?.trim() ||
    MODEL_GROQ_PLUS_PRO_DEFAULT;
}

function freeStandardAnalysisRouteFlag(): "paid_trial" | "free_legacy" {
  const rawValue = Deno.env.get("FREE_STANDARD_ANALYSIS_AI_ROUTE")?.trim()
    .toLowerCase();
  return rawValue === "free_legacy" ? "free_legacy" : "paid_trial";
}

async function loadCancelledPlusTrialRoutingFlag(
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<CancelledPlusTrialRoutingFlag> {
  try {
    const { data, error } = await supabase
      .from("app_feature_flags")
      .select("value")
      .eq("key", CANCELLED_PLUS_TRIAL_ROUTING_FLAG_KEY)
      .maybeSingle();
    if (error) return normalizeCancelledPlusTrialRoutingFlag(null);
    return normalizeCancelledPlusTrialRoutingFlag(data?.value);
  } catch {
    return normalizeCancelledPlusTrialRoutingFlag(null);
  }
}

function resolveAIExecutionRoute(
  planTier: PlanTier,
  analysisMode: AnalysisMode,
  cancelledTrialRoutingEnabled = false,
): AIExecutionRoute {
  if (planTier === "plus" && cancelledTrialRoutingEnabled) {
    return CANCELLED_PLUS_TRIAL_ROUTE;
  }
  if (planTier !== "free") return "paid_plan";
  if (
    analysisMode === "standard" &&
    freeStandardAnalysisRouteFlag() === "paid_trial"
  ) {
    return "free_paid_trial";
  }
  return "free_legacy";
}

function usesFreeGeminiProviderPool(
  aiExecutionRoute: AIExecutionRoute,
): boolean {
  return aiExecutionRoute === "free_legacy" ||
    aiExecutionRoute === CANCELLED_PLUS_TRIAL_ROUTE;
}

function resolveQualityTier(
  planTier: PlanTier,
  aiExecutionRoute: AIExecutionRoute,
): PlanTier {
  return aiExecutionRoute === "free_paid_trial" ? "plus" : planTier;
}

function geminiKeyPoolForRoute(
  aiExecutionRoute: AIExecutionRoute,
): GeminiKeyConfig[] {
  return usesFreeGeminiProviderPool(aiExecutionRoute)
    ? freeGeminiKeyPool()
    : paidGeminiKeyPool();
}

function expectedGeminiPoolForRoute(
  aiExecutionRoute: AIExecutionRoute,
): GeminiPoolName {
  return usesFreeGeminiProviderPool(aiExecutionRoute) ? "free" : "paid";
}

function geminiRequiredSecretNameForRoute(
  aiExecutionRoute: AIExecutionRoute,
): string {
  return usesFreeGeminiProviderPool(aiExecutionRoute)
    ? "GEMINI_API_KEY_PRIMARY veya GEMINI_API_KEY"
    : "GEMINI_API_KEY_PAID";
}

function primaryModelForRoute(aiExecutionRoute: AIExecutionRoute): string {
  return usesFreeGeminiProviderPool(aiExecutionRoute)
    ? MODEL_FREE
    : MODEL_PAID_FAST;
}

function userFacingAIError(
  err: unknown,
): { status: number; code: string; message: string } {
  if (err instanceof AIRequestTimeoutError) {
    return {
      status: 503,
      code: "ai_timeout",
      message: "AI modeli zamanında yanıt veremedi. Lütfen tekrar dene.",
    };
  }
  if (err instanceof AITruncatedResponseError) {
    return {
      status: 502,
      code: "ai_truncated_response",
      message: "AI yanıtı tamamlanmadan kesildi. Lütfen tekrar dene.",
    };
  }
  if (err instanceof GeminiAPIError) {
    if (err.status === 429) {
      return {
        status: 429,
        code: "ai_rate_limited",
        message:
          "Gemini kotası doldu. Google AI kullanım limitini veya faturalandırma planını kontrol etmek gerekiyor.",
      };
    }
    if (err.status === 503) {
      return {
        status: 503,
        code: "ai_unavailable",
        message: "Gemini modeli şu anda yoğun. Biraz sonra tekrar dene.",
      };
    }
    return {
      status: 502,
      code: "ai_provider_error",
      message: `Gemini servis hatası (${err.status}).`,
    };
  }

  if (err instanceof GroqAPIError) {
    if (err.status === 429) {
      return {
        status: 429,
        code: "ai_rate_limited",
        message:
          "AI modeli şu anda yoğun veya kota limitine takıldı. Biraz sonra tekrar dene.",
      };
    }
    if ([500, 502, 503, 504].includes(err.status)) {
      return {
        status: 503,
        code: "ai_unavailable",
        message: "AI modeli şu anda yoğun. Biraz sonra tekrar dene.",
      };
    }
    return {
      status: 502,
      code: "ai_provider_error",
      message: `AI servis hatası (${err.status}).`,
    };
  }

  if (err instanceof SyntaxError) {
    return {
      status: 502,
      code: "ai_invalid_response",
      message: "AI yanıtı işlenemedi. Lütfen aynı analizi tekrar dene.",
    };
  }

  return {
    status: 502,
    code: "ai_failed",
    message: "AI analizi tamamlanamadı. Lütfen tekrar dene.",
  };
}

function isRetryableAIError(err: unknown): boolean {
  if (
    err instanceof AIRequestTimeoutError ||
    err instanceof AITruncatedResponseError
  ) {
    return true;
  }
  if (err instanceof SyntaxError) return true;
  if (err instanceof GeminiAPIError || err instanceof GroqAPIError) {
    return [429, 500, 502, 503, 504].includes(err.status);
  }
  return false;
}

function uniqueModels(models: string[]): string[] {
  return [...new Set(models)];
}

function geminiAttemptSequence(
  keyPool: GeminiKeyConfig[],
  preferredModel: string,
): Array<{ keyConfig: GeminiKeyConfig; model: string }> {
  const attempts: Array<{ keyConfig: GeminiKeyConfig; model: string }> = [];
  const pushAttempts = (keyConfig: GeminiKeyConfig, models: string[]) => {
    for (const model of uniqueModels(models)) {
      attempts.push({ keyConfig, model });
    }
  };

  const isPaidPool = keyPool.some((item) => item.pool === "paid");
  if (isPaidPool) {
    const primary = keyPool.find((item) =>
      item.alias === "gemini_paid_primary"
    );
    const secondary = keyPool.find((item) =>
      item.alias === "gemini_paid_secondary"
    );

    if (primary) {
      pushAttempts(primary, [MODEL_PAID_FAST, MODEL_PRO, MODEL_FLASH_LITE]);
    }
    if (secondary) {
      pushAttempts(secondary, [MODEL_PAID_FAST, MODEL_PRO]);
    }

    const knownPaidAliases = new Set([
      "gemini_paid_primary",
      "gemini_paid_secondary",
    ]);
    for (const keyConfig of keyPool) {
      if (!knownPaidAliases.has(keyConfig.alias)) {
        pushAttempts(keyConfig, [MODEL_PAID_FAST, MODEL_PRO]);
      }
    }

    return attempts;
  }

  if (preferredModel !== MODEL_FREE) {
    for (const keyConfig of keyPool) {
      pushAttempts(keyConfig, [preferredModel]);
    }
    return attempts;
  }

  const orderedFreeKeys = keyPool.filter((item) => item.pool === "free");

  for (const keyConfig of orderedFreeKeys) {
    pushAttempts(keyConfig, [MODEL_FREE]);
  }
  for (const keyConfig of orderedFreeKeys) {
    pushAttempts(keyConfig, [MODEL_FREE_FALLBACK]);
  }

  return attempts;
}

function freePaidTrialPaidGeminiAttemptSequence(
  keyPool: GeminiKeyConfig[],
): Array<{ keyConfig: GeminiKeyConfig; model: string }> {
  const attempts: Array<{ keyConfig: GeminiKeyConfig; model: string }> = [];
  const paidKeys = keyPool.filter((item) => item.pool === "paid");
  const primary = paidKeys.find((item) => item.alias === "gemini_paid_primary");
  const secondary = paidKeys.find((item) =>
    item.alias === "gemini_paid_secondary"
  );
  const knownPaidAliases = new Set([
    "gemini_paid_primary",
    "gemini_paid_secondary",
  ]);
  const orderedKeys = [
    primary,
    secondary,
    ...paidKeys.filter((item) => !knownPaidAliases.has(item.alias)),
  ].filter((item): item is GeminiKeyConfig => Boolean(item));

  for (const keyConfig of orderedKeys) {
    attempts.push({ keyConfig, model: MODEL_PAID_FAST });
    attempts.push({ keyConfig, model: MODEL_PAID_FAST });
  }
  for (const keyConfig of orderedKeys) {
    attempts.push({ keyConfig, model: MODEL_FLASH_LITE });
  }

  return attempts;
}

async function callGeminiWithFallback(
  keyPool: GeminiKeyConfig[],
  preferredModel: string,
  systemPrompt: string,
  analysisContext: string,
  userText: string | null,
  imageBase64Parts: AIImagePart[],
  tier: PlanTier,
  simulation?: AISimulationConfig,
  trace?: TraceMeta,
  attemptSequence?: Array<{ keyConfig: GeminiKeyConfig; model: string }>,
  coveragePolicy?: MultiPhotoCoveragePolicy | null,
  options: AIRequestOptions = {},
) {
  let lastError: unknown = null;
  let attempt = 0;
  const attemptFailures: GeminiAttemptFailure[] = [];
  for (
    const { keyConfig, model } of attemptSequence ?? geminiAttemptSequence(
      keyPool,
      preferredModel,
    )
  ) {
    attempt += 1;
    try {
      const out = await callGemini(
        keyConfig.key,
        model,
        systemPrompt,
        analysisContext,
        userText,
        imageBase64Parts,
        keyConfig.pool,
        tier,
        simulation,
        coveragePolicy,
        options,
      );
      return {
        ...out,
        modelUsed: model,
        apiKeyAlias: keyConfig.alias,
        attempt,
        geminiAttemptFailures: attemptFailures,
      };
    } catch (err) {
      lastError = err;
      const retryable = isRetryableAIError(err);
      const failure: GeminiAttemptFailure = {
        apiKeyAlias: keyConfig.alias,
        model,
        attempt,
        retryable,
        error: safeLogError(err),
      };
      attemptFailures.push(failure);
      console.error(
        "Gemini attempt failed",
        JSON.stringify({
          request_id: trace?.requestID ?? null,
          support_id: trace?.supportID ?? null,
          ...failure,
        }),
      );
      if (!retryable) throw err;
      await delay(500);
    }
  }

  throw lastError ?? new Error("Gemini analizi başarısız.");
}

async function callAIWithFreeProviderPool(
  geminiKeyPool: GeminiKeyConfig[],
  preferredModel: string,
  systemPrompt: string,
  analysisContext: string,
  userText: string | null,
  imageBase64Parts: AIImagePart[],
  outputTier: PlanTier,
  simulation?: AISimulationConfig,
  trace?: TraceMeta,
  coveragePolicy?: MultiPhotoCoveragePolicy | null,
  options: AIRequestOptions = {},
) {
  try {
    const out = await callGeminiWithFallback(
      geminiKeyPool,
      preferredModel,
      systemPrompt,
      analysisContext,
      userText,
      imageBase64Parts,
      outputTier,
      simulation,
      trace,
      undefined,
      coveragePolicy,
      options,
    );
    return {
      ...out,
      providerUsed: "gemini" as AIProvider,
      fallbackSource: [
        out.modelUsed !== preferredModel ? out.modelUsed : null,
        out.apiKeyAlias && out.apiKeyAlias !== geminiKeyPool[0]?.alias
          ? out.apiKeyAlias
          : null,
      ].filter(Boolean).join(" -> ") || null,
    };
  } catch (err) {
    if (!isRetryableAIError(err)) throw err;

    const groqKey = freeGroqKeyConfig();
    if (!groqKey) throw err;

    console.warn(
      "Free Gemini pool exhausted; trying Groq fallback",
      JSON.stringify({
        apiKeyAlias: groqKey.alias,
        model: freeGroqModel(),
        gemini_error: safeLogError(err),
      }),
    );

    const out = await callGroq(
      groqKey.key,
      freeGroqModel(),
      systemPrompt,
      analysisContext,
      userText,
      imageBase64Parts,
      outputTier,
      simulation,
      coveragePolicy,
      options,
    );
    return {
      ...out,
      providerUsed: "groq" as AIProvider,
      modelUsed: freeGroqModel(),
      apiKeyAlias: groqKey.alias,
      attempt: null,
      fallbackSource: `gemini_free_pool -> ${groqKey.alias}`,
    };
  }
}

async function callPaidAIWithFallback(
  geminiKeyPool: GeminiKeyConfig[],
  preferredModel: string,
  systemPrompt: string,
  analysisContext: string,
  userText: string | null,
  imageBase64Parts: AIImagePart[],
  tier: PlanTier,
  simulation?: AISimulationConfig,
  trace?: TraceMeta,
  coveragePolicy?: MultiPhotoCoveragePolicy | null,
  options: AIRequestOptions = {},
) {
  try {
    const out = await callGeminiWithFallback(
      geminiKeyPool,
      preferredModel,
      systemPrompt,
      analysisContext,
      userText,
      imageBase64Parts,
      tier,
      simulation,
      trace,
      undefined,
      coveragePolicy,
      options,
    );
    return {
      ...out,
      providerUsed: "gemini" as AIProvider,
      fallbackSource: [
        out.modelUsed !== preferredModel ? out.modelUsed : null,
        out.apiKeyAlias && out.apiKeyAlias !== geminiKeyPool[0]?.alias
          ? out.apiKeyAlias
          : null,
      ].filter(Boolean).join(" -> ") || null,
    };
  } catch (err) {
    if (!isRetryableAIError(err)) throw err;

    const groqKey = plusProGroqKeyConfig();
    if (!groqKey) throw err;

    console.warn(
      "Paid Gemini pool exhausted; trying Plus/Pro Groq continuity fallback",
      JSON.stringify({
        apiKeyAlias: groqKey.alias,
        model: plusProGroqModel(),
        gemini_error: safeLogError(err),
      }),
    );

    const out = await callGroq(
      groqKey.key,
      plusProGroqModel(),
      systemPrompt,
      analysisContext,
      userText,
      imageBase64Parts,
      tier,
      simulation,
      coveragePolicy,
      options,
    );
    return {
      ...out,
      providerUsed: "groq" as AIProvider,
      modelUsed: plusProGroqModel(),
      apiKeyAlias: groqKey.alias,
      attempt: null,
      fallbackSource: `gemini_paid_pool -> ${groqKey.alias}`,
    };
  }
}

async function callFreePaidTrialAIWithFallback(
  paidGeminiKeyPool: GeminiKeyConfig[],
  freeGeminiKeyPool: GeminiKeyConfig[],
  preferredModel: string,
  systemPrompt: string,
  analysisContext: string,
  userText: string | null,
  imageBase64Parts: AIImagePart[],
  outputTier: PlanTier,
  simulation?: AISimulationConfig,
  trace?: TraceMeta,
  coveragePolicy?: MultiPhotoCoveragePolicy | null,
  options: AIRequestOptions = {},
) {
  try {
    const out = await callGeminiWithFallback(
      paidGeminiKeyPool,
      preferredModel,
      systemPrompt,
      analysisContext,
      userText,
      imageBase64Parts,
      outputTier,
      simulation,
      trace,
      freePaidTrialPaidGeminiAttemptSequence(paidGeminiKeyPool),
      coveragePolicy,
      options,
    );
    return {
      ...out,
      providerUsed: "gemini" as AIProvider,
      fallbackSource: [
        out.modelUsed !== preferredModel ? out.modelUsed : null,
        out.apiKeyAlias && out.apiKeyAlias !== paidGeminiKeyPool[0]?.alias
          ? out.apiKeyAlias
          : null,
      ].filter(Boolean).join(" -> ") || null,
    };
  } catch (paidErr) {
    if (!isRetryableAIError(paidErr) || freeGeminiKeyPool.length === 0) {
      throw paidErr;
    }

    console.warn(
      "Free paid trial Gemini pool exhausted; trying free Gemini continuity fallback",
      JSON.stringify({
        free_aliases: freeGeminiKeyPool.map((item) => item.alias),
        paid_error: safeLogError(paidErr),
      }),
    );

    try {
      const out = await callGeminiWithFallback(
        freeGeminiKeyPool,
        MODEL_FREE,
        systemPrompt,
        analysisContext,
        userText,
        imageBase64Parts,
        outputTier,
        simulation,
        trace,
        undefined,
        coveragePolicy,
        options,
      );
      const fallbackDetails = [
        out.modelUsed !== MODEL_FREE ? out.modelUsed : null,
        out.apiKeyAlias && out.apiKeyAlias !== freeGeminiKeyPool[0]?.alias
          ? out.apiKeyAlias
          : null,
      ].filter(Boolean);
      return {
        ...out,
        providerUsed: "gemini" as AIProvider,
        fallbackSource: [
          "gemini_paid_pool",
          "gemini_free_pool",
          ...fallbackDetails,
        ].join(" -> "),
      };
    } catch (freeErr) {
      if (!isRetryableAIError(freeErr)) throw freeErr;

      const groqKey = freeGroqKeyConfig();
      if (!groqKey) throw freeErr;

      console.warn(
        "Free Gemini continuity fallback exhausted; trying free Groq fallback",
        JSON.stringify({
          apiKeyAlias: groqKey.alias,
          model: freeGroqModel(),
          free_gemini_error: safeLogError(freeErr),
        }),
      );

      const out = await callGroq(
        groqKey.key,
        freeGroqModel(),
        systemPrompt,
        analysisContext,
        userText,
        imageBase64Parts,
        outputTier,
        simulation,
        coveragePolicy,
        options,
      );
      return {
        ...out,
        providerUsed: "groq" as AIProvider,
        modelUsed: freeGroqModel(),
        apiKeyAlias: groqKey.alias,
        attempt: null,
        fallbackSource:
          `gemini_paid_pool -> gemini_free_pool -> ${groqKey.alias}`,
      };
    }
  }
}

function newSupportID(): string {
  return `RD-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
}

function providerDisplayName(provider: AIProvider): string {
  return provider === "groq" ? "Groq" : "Gemini";
}

function safeLogError(error: unknown): Record<string, unknown> {
  if (error instanceof GeminiAPIError) {
    return { name: "GeminiAPIError", status: error.status };
  }
  if (error instanceof GroqAPIError) {
    return { name: "GroqAPIError", status: error.status };
  }
  if (error instanceof SyntaxError) {
    return { name: "SyntaxError" };
  }
  if (error instanceof Error) {
    return {
      name: error.name || "Error",
      message: error.message.replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
        .slice(0, 160),
    };
  }
  if (error && typeof error === "object") {
    const source = error as Record<string, unknown>;
    return {
      name: typeof source.name === "string" ? source.name : "object",
      code: typeof source.code === "string" ? source.code : undefined,
      message: typeof source.message === "string"
        ? source.message.replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
          .slice(0, 160)
        : undefined,
      details: typeof source.details === "string"
        ? source.details.slice(0, 240)
        : undefined,
      hint: typeof source.hint === "string"
        ? source.hint.slice(0, 160)
        : undefined,
    };
  }
  return { name: typeof error };
}

function safeLogText(value: unknown, maxLength = 220): string {
  if (typeof value !== "string") return "";
  return value.replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]").slice(
    0,
    maxLength,
  );
}

function storageObjectURL(
  supabaseUrl: string,
  bucket: string,
  path: string,
): string {
  const cleanUrl = supabaseUrl.replace(/\/$/, "");
  const encodedPath = path.split("/").map(encodeURIComponent).join("/");
  return `${cleanUrl}/storage/v1/object/${
    encodeURIComponent(bucket)
  }/${encodedPath}`;
}

async function uploadStorageObject(params: {
  supabaseUrl: string;
  serviceRoleKey: string;
  bucket: string;
  path: string;
  body: Uint8Array;
  mimeType: string;
}): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  const res = await fetch(
    storageObjectURL(params.supabaseUrl, params.bucket, params.path),
    {
      method: "POST",
      headers: {
        apikey: params.serviceRoleKey,
        Authorization: `Bearer ${params.serviceRoleKey}`,
        "Content-Type": params.mimeType,
        "cache-control": "3600",
        "x-upsert": "true",
      },
      body: params.body,
    },
  );

  if (res.ok) return { ok: true };
  return {
    ok: false,
    status: res.status,
    error: safeLogText(await res.text().catch(() => ""), 500),
  };
}

async function hashedID(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest.slice(0, 6)))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function normalizedTraceValue(value: unknown, fallback: string): string {
  if (typeof value !== "string") return fallback;
  const clean = value.trim().replace(/[^a-zA-Z0-9._:-]/g, "").slice(0, 80);
  return clean.length > 0 ? clean : fallback;
}

function errorResponse(status: number, message: string, meta?: {
  code?: string;
  requestID?: string;
  supportID?: string;
  tier?: string;
  limit?: number;
  used?: number;
  feature?: string;
  max_photos_per_analysis?: number;
  requested_photo_count?: number;
  upgrade_target?: string | null;
  paywall_context?: string | null;
}): Response {
  const supportID = meta?.supportID ?? newSupportID();
  return new Response(
    JSON.stringify({
      error: message,
      message,
      code: meta?.code ?? "unknown",
      request_id: meta?.requestID ?? null,
      support_id: supportID,
      tier: meta?.tier ?? null,
      limit: meta?.limit ?? null,
      used: meta?.used ?? null,
      feature: meta?.feature ?? null,
      max_photos_per_analysis: meta?.max_photos_per_analysis ?? null,
      requested_photo_count: meta?.requested_photo_count ?? null,
      upgrade_target: meta?.upgrade_target ?? null,
      paywall_context: meta?.paywall_context ?? null,
    }),
    {
      status,
      headers: { "Content-Type": "application/json" },
    },
  );
}

function base64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

function stripJPEGMetadata(bytes: Uint8Array): Uint8Array {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return bytes;

  const chunks: Uint8Array[] = [bytes.subarray(0, 2)];
  let offset = 2;

  while (offset + 4 <= bytes.length) {
    if (bytes[offset] !== 0xff) return bytes;

    let markerOffset = offset;
    while (markerOffset < bytes.length && bytes[markerOffset] === 0xff) {
      markerOffset++;
    }
    if (markerOffset >= bytes.length) return bytes;

    const marker = bytes[markerOffset];
    offset = markerOffset + 1;

    // Start of Scan: compressed image data follows; copy the rest as-is.
    if (marker === 0xda) {
      chunks.push(bytes.subarray(markerOffset - 1));
      return concatBytes(chunks);
    }

    // Standalone markers without payload length.
    if (
      marker === 0xd9 || (marker >= 0xd0 && marker <= 0xd7) || marker === 0x01
    ) {
      chunks.push(bytes.subarray(markerOffset - 1, offset));
      continue;
    }

    if (offset + 2 > bytes.length) return bytes;
    const length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) return bytes;

    const segmentStart = markerOffset - 1;
    const segmentEnd = offset + length;
    const isAppSegment = marker >= 0xe0 && marker <= 0xef;
    const isComment = marker === 0xfe;

    // APPn segments commonly carry EXIF/GPS/XMP/JFIF metadata; COM carries comments.
    if (!isAppSegment && !isComment) {
      chunks.push(bytes.subarray(segmentStart, segmentEnd));
    }

    offset = segmentEnd;
  }

  return concatBytes(chunks);
}

function stripPNGMetadata(bytes: Uint8Array): Uint8Array {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (
    bytes.length < signature.length ||
    !signature.every((b, i) => bytes[i] === b)
  ) return bytes;

  const chunks: Uint8Array[] = [bytes.subarray(0, 8)];
  let offset = 8;
  const metadataChunkTypes = new Set(["eXIf", "tEXt", "zTXt", "iTXt", "tIME"]);

  while (offset + 12 <= bytes.length) {
    const length = (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
    if (length < 0) return bytes;

    const chunkEnd = offset + 12 + length;
    if (chunkEnd > bytes.length) return bytes;

    const type = String.fromCharCode(
      bytes[offset + 4],
      bytes[offset + 5],
      bytes[offset + 6],
      bytes[offset + 7],
    );

    if (!metadataChunkTypes.has(type)) {
      chunks.push(bytes.subarray(offset, chunkEnd));
    }

    offset = chunkEnd;
    if (type === "IEND") break;
  }

  return concatBytes(chunks);
}

function concatBytes(parts: Uint8Array[]): Uint8Array {
  const total = parts.reduce((sum, part) => sum + part.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

function normalizedImageMimeType(value: unknown): "image/jpeg" | "image/png" {
  const raw = typeof value === "string" ? value.toLowerCase() : "";
  return raw.includes("png") ? "image/png" : "image/jpeg";
}

function stripImageMetadata(bytes: Uint8Array, mimeType: string): Uint8Array {
  if (mimeType === "image/png") return stripPNGMetadata(bytes);
  return stripJPEGMetadata(bytes);
}

function sanitizedDimension(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? Math.round(value)
    : 0;
}

async function persistInlinePhotosForQueue(params: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  supabaseUrl: string;
  serviceRoleKey: string;
  userID: string;
  analysisID: string;
  // deno-lint-ignore no-explicit-any
  inlinePhotoParts: any[];
}): Promise<string[]> {
  const persistedPhotoPaths: string[] = [];
  const inlinePhotoParts = Array.isArray(params.inlinePhotoParts)
    ? params.inlinePhotoParts
    : [];
  if (inlinePhotoParts.length === 0) return persistedPhotoPaths;
  const uploadedPhotoPaths: string[] = [];

  try {
    const { error: deletePhotoErr } = await params.supabase.from("photos")
      .delete()
      .eq("analysis_id", params.analysisID)
      .eq("user_id", params.userID);
    if (deletePhotoErr) {
      throw new Error(
        `photo_cleanup_failed:${safeLogText(JSON.stringify(deletePhotoErr))}`,
      );
    }

    for (let i = 0; i < inlinePhotoParts.length; i++) {
      const part = inlinePhotoParts[i];
      if (!part?.data) continue;
      const mimeType = normalizedImageMimeType(part.mime_type ?? part.mimeType);
      const rawBytes = base64ToBytes(part.data);
      const bytes = stripImageMetadata(rawBytes, mimeType);
      const ext = mimeType.includes("png") ? "png" : "jpg";
      const storagePath = `${params.userID}/${params.analysisID}/p${
        i + 1
      }.${ext}`;
      const uploadBody = bytes.byteOffset === 0 &&
          bytes.byteLength === bytes.buffer.byteLength
        ? bytes
        : bytes.slice();

      const uploadResult = await uploadStorageObject({
        supabaseUrl: params.supabaseUrl,
        serviceRoleKey: params.serviceRoleKey,
        bucket: "photos",
        path: storagePath,
        body: uploadBody,
        mimeType,
      });

      if (!uploadResult.ok) {
        throw new Error(
          `photo_upload_failed:${uploadResult.status}:${
            safeLogText(uploadResult.error)
          }`,
        );
      }
      uploadedPhotoPaths.push(storagePath);

      const { error: photoErr } = await params.supabase.from("photos").insert({
        analysis_id: params.analysisID,
        user_id: params.userID,
        storage_path: storagePath,
        width: sanitizedDimension(part.width),
        height: sanitizedDimension(part.height),
        size_bytes: bytes.byteLength,
        byte_size: bytes.byteLength,
        mime_type: mimeType,
        sequence_index: i + 1,
        client_photo_id:
          safeText(part.client_photo_id ?? part.clientPhotoID).slice(0, 80) ||
          null,
        is_primary: i === 0,
        upload_payload_version: inlinePhotoParts.length > 1
          ? "photo-batch-v2"
          : "photo-single-v1",
      });

      if (photoErr) {
        throw new Error(
          `photo_metadata_failed:${safeLogText(JSON.stringify(photoErr))}`,
        );
      }

      persistedPhotoPaths.push(storagePath);
    }
  } catch (error) {
    if (uploadedPhotoPaths.length > 0) {
      await params.supabase.storage.from("photos").remove(uploadedPhotoPaths);
    }
    await params.supabase.from("photos")
      .delete()
      .eq("analysis_id", params.analysisID)
      .eq("user_id", params.userID);
    throw error;
  }

  return persistedPhotoPaths;
}

async function enqueueAnalysisJob(params: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  supabaseUrl: string;
  serviceRoleKey: string;
  // deno-lint-ignore no-explicit-any
  body: any;
  userID: string;
  analysisID: string;
  requestID: string;
  supportID: string;
}): Promise<{ queuedPhotoPaths: string[] }> {
  const requestedPhotoPaths = Array.isArray(params.body.photo_paths)
    ? params.body.photo_paths
      .map((path: unknown) => typeof path === "string" ? path.trim() : "")
      .filter((path: string) => path.length > 0)
    : [];

  const persistedPhotoPaths = await persistInlinePhotosForQueue({
    supabase: params.supabase,
    supabaseUrl: params.supabaseUrl,
    serviceRoleKey: params.serviceRoleKey,
    userID: params.userID,
    analysisID: params.analysisID,
    inlinePhotoParts: Array.isArray(params.body.photo_base64_parts)
      ? params.body.photo_base64_parts
      : [],
  });

  const queuedPhotoPaths = [
    ...new Set([
      ...requestedPhotoPaths,
      ...persistedPhotoPaths,
    ]),
  ];
  const jobBody = {
    ...params.body,
    __worker: true,
    job_mode: "analysis",
    user_id: params.userID,
    request_id: params.requestID,
    support_id: params.supportID,
    photo_paths: queuedPhotoPaths,
    photo_base64_parts: [],
  };

  const { error: updateErr } = await params.supabase
    .from("analyses")
    .update({
      status: "queued",
      queued_at: new Date().toISOString(),
      status_message: `Analiz kuyruğa alındı. Destek kodu: ${params.supportID}`,
      last_worker_error: null,
    })
    .eq("id", params.analysisID)
    .eq("user_id", params.userID);

  if (updateErr) {
    throw new Error(`analysis_queue_update_failed:${safeLogError(updateErr)}`);
  }

  const { error: queueErr } = await params.supabase.rpc(
    "enqueue_analysis_job_message",
    { p_message: jobBody },
  );

  if (queueErr) {
    await params.supabase
      .from("analyses")
      .update({
        status: "failed",
        status_message:
          `Analiz kuyruğa alınamadı. Destek kodu: ${params.supportID}`,
        last_worker_error: safeLogText(JSON.stringify(queueErr)),
      })
      .eq("id", params.analysisID)
      .eq("user_id", params.userID);
    throw new Error(`analysis_queue_send_failed:${safeLogError(queueErr)}`);
  }

  return { queuedPhotoPaths };
}

async function enqueueCoverageRepairJob(params: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  // deno-lint-ignore no-explicit-any
  body: any;
  userID: string;
  analysisID: string;
  requestID: string;
  supportID: string;
  repairPhotoIndices: number[];
}) {
  const jobBody = {
    ...params.body,
    __worker: true,
    job_mode: "repair",
    user_id: params.userID,
    analysis_id: params.analysisID,
    request_id: params.requestID,
    support_id: params.supportID,
    repair_photo_indices: params.repairPhotoIndices,
    photo_base64_parts: [],
  };

  const { error: updateErr } = await params.supabase
    .from("analyses")
    .update({
      status: "queued",
      status_message:
        `Analiz kapsamı ikinci taramaya alındı. Destek kodu: ${params.supportID}`,
      last_worker_error: null,
    })
    .eq("id", params.analysisID)
    .eq("user_id", params.userID);

  if (updateErr) {
    throw new Error(`coverage_repair_update_failed:${safeLogError(updateErr)}`);
  }

  const { error: queueErr } = await params.supabase.rpc(
    "enqueue_analysis_job_message",
    { p_message: jobBody },
  );

  if (queueErr) {
    throw new Error(`coverage_repair_queue_failed:${safeLogError(queueErr)}`);
  }
}

function triggerAnalysisWorker(params: {
  supabaseUrl: string;
  serviceRoleKey: string;
  requestID: string;
  supportID: string;
}) {
  const run = fetch(
    `${params.supabaseUrl}/functions/v1/${PROCESS_ANALYSIS_FUNCTION_NAME}`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${params.serviceRoleKey}`,
        "Content-Type": "application/json",
        "x-request-id": params.requestID,
        "x-support-id": params.supportID,
      },
      body: JSON.stringify({ source: "analyze_enqueue", limit: 3 }),
    },
  ).catch((error) => {
    console.error(
      "Analysis worker trigger failed",
      JSON.stringify({
        request_id: params.requestID,
        support_id: params.supportID,
        error: safeLogText(error),
      }),
    );
  });

  if (typeof EdgeRuntime !== "undefined") {
    EdgeRuntime.waitUntil(run);
  }
}

async function sendAnalysisCompletePush(params: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  supabaseUrl: string;
  serviceRoleKey: string;
  userID: string;
  analysisID: string;
  requestID: string;
  supportID: string;
}) {
  const { data: analysisRow } = await params.supabase
    .from("analyses")
    .select("completion_push_sent_at")
    .eq("id", params.analysisID)
    .eq("user_id", params.userID)
    .maybeSingle();
  if (analysisRow?.completion_push_sent_at) return;

  const response = await fetch(
    `${params.supabaseUrl}/functions/v1/send-push-notification`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${params.serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        user_id: params.userID,
        kind: "analysis_complete",
        title: "Analiz Hazır !",
        body: "Risk analizin seni bekliyor, hemen incele.",
        data: {
          analysis_id: params.analysisID,
          destination: "history",
          request_id: params.requestID,
          support_id: params.supportID,
        },
      }),
    },
  );

  const responseText = await response.text();
  if (!response.ok) {
    await params.supabase
      .from("analyses")
      .update({ last_worker_error: `push_failed:${response.status}` })
      .eq("id", params.analysisID)
      .eq("user_id", params.userID);
    console.warn(
      "Analysis completion push failed",
      JSON.stringify({
        request_id: params.requestID,
        support_id: params.supportID,
        analysis_id: params.analysisID,
        status: response.status,
        body: safeLogText(responseText),
      }),
    );
    return;
  }
  let pushResult: { status?: string } = {};
  try {
    pushResult = responseText ? JSON.parse(responseText) : {};
  } catch {
    pushResult = {};
  }
  if (pushResult.status !== "sent") {
    console.warn(
      "Analysis completion push not sent",
      JSON.stringify({
        request_id: params.requestID,
        support_id: params.supportID,
        analysis_id: params.analysisID,
        body: safeLogText(responseText),
      }),
    );
    return;
  }

  await params.supabase
    .from("analyses")
    .update({ completion_push_sent_at: new Date().toISOString() })
    .eq("id", params.analysisID)
    .eq("user_id", params.userID)
    .is("completion_push_sent_at", null);
}

// deno-lint-ignore no-explicit-any
async function logUsage(supabase: any, data: any) {
  try {
    await supabase.from("ai_usage_logs").insert(data);
  } catch (e) {
    console.error("Usage log insert failed", JSON.stringify(safeLogError(e)));
  }
}

// deno-lint-ignore no-explicit-any
async function releaseAnalysisQuota(
  supabase: any,
  analysisID: string,
  userID: string,
) {
  try {
    await supabase
      .from("usage_events")
      .delete()
      .eq("user_id", userID)
      .eq("source_id", analysisID)
      .in("feature", ["analysis_standard", "analysis_detailed"])
      .eq("event_type", "reserved");
  } catch (e) {
    console.error(
      "Quota reservation release failed",
      JSON.stringify(safeLogError(e)),
    );
  }
}

// deno-lint-ignore no-explicit-any
async function completeAnalysisQuota(
  supabase: any,
  analysisID: string,
  userID: string,
) {
  try {
    await supabase
      .from("usage_events")
      .update({
        event_type: "completed",
      })
      .eq("user_id", userID)
      .eq("source_id", analysisID)
      .in("feature", ["analysis_standard", "analysis_detailed"])
      .eq("event_type", "reserved");
  } catch (e) {
    console.error(
      "Quota reservation completion failed",
      JSON.stringify(safeLogError(e)),
    );
  }
}

const BAND_RANK: Record<string, number> = {
  low: 0,
  medium: 1,
  high: 2,
  critical: 3,
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers":
          "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  const startMs = Date.now();
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const supabase = createClient(
    supabaseUrl,
    serviceRoleKey,
  );

  const fallbackRequestID = crypto.randomUUID();
  let requestID = normalizedTraceValue(
    req.headers.get("x-request-id"),
    fallbackRequestID,
  );
  let supportID = normalizedTraceValue(
    req.headers.get("x-support-id"),
    newSupportID(),
  );

  // deno-lint-ignore no-explicit-any
  let body: any;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, "Geçersiz JSON body.", {
      code: "invalid_json",
      requestID,
      supportID,
    });
  }

  requestID = normalizedTraceValue(body.request_id, requestID);
  supportID = normalizedTraceValue(body.support_id, supportID);
  const jobMode: "analysis" | "repair" = body.job_mode === "repair"
    ? "repair"
    : "analysis";

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return errorResponse(401, "Authorization header eksik.", {
      code: "auth_required",
      requestID,
      supportID,
    });
  }

  const isWorkerInvocation = authHeader === `Bearer ${serviceRoleKey}` &&
    body.__worker === true &&
    typeof body.user_id === "string" &&
    body.user_id.length > 0;

  let user: { id: string };
  if (isWorkerInvocation) {
    user = { id: body.user_id };
  } else {
    const { data: { user: authUser }, error: authErr } = await supabase.auth
      .getUser(
        authHeader.replace("Bearer ", ""),
      );
    if (authErr || !authUser) {
      return errorResponse(401, "Geçersiz token.", {
        code: "auth_invalid",
        requestID,
        supportID,
      });
    }
    user = { id: authUser.id };
  }

  const {
    analysis_id,
    canvas,
    canvases,
    analysis_mode,
    text_input,
    company_id,
    analysis_sector,
    analysis_sector_source,
    analysis_sector_prompt_version,
    photo_paths = [],
    photo_base64_parts = [],
  } = body;
  const clientRelease = parseClientReleaseContext(
    body as Record<string, unknown>,
  );
  const requestedAnalysisSector = typeof analysis_sector === "string"
    ? analysis_sector.trim()
    : "";
  const requestedSectorPreflight = isWorkerInvocation
    ? null
    : resolveActiveSectorState({
      requestedSector: requestedAnalysisSector,
      persistedSector: null,
    });
  if (requestedSectorPreflight && !requestedSectorPreflight.ok) {
    return errorResponse(
      requestedSectorPreflight.status,
      requestedSectorPreflight.message,
      {
        code: requestedSectorPreflight.code,
        requestID,
        supportID,
      },
    );
  }
  const requestedCompanyID = typeof company_id === "string"
    ? company_id.trim()
    : "";
  if (!analysis_id) {
    return errorResponse(400, "analysis_id zorunlu.", {
      code: "validation_failed",
      requestID,
      supportID,
    });
  }
  const analysisID = String(analysis_id);
  const requestedPhotoPaths = Array.isArray(photo_paths)
    ? photo_paths
      .map((path) => typeof path === "string" ? path.trim() : "")
      .filter((path) => path.length > 0)
    : [];
  const inlinePhotoValidation = validateInlinePhotoInput(
    photo_base64_parts,
    requestedPhotoPaths,
  );
  if (!inlinePhotoValidation.ok) {
    return errorResponse(400, inlinePhotoValidation.message, {
      code: inlinePhotoValidation.code,
      requestID,
      supportID,
    });
  }

  console.log(
    "Analyze request started",
    JSON.stringify({
      request_id: requestID,
      support_id: supportID,
      analysis_id: analysisID,
      user_hash: await hashedID(user.id),
      client_build: clientRelease.appBuild,
      api_contract_version: clientRelease.apiContractVersion,
    }),
  );

  const { data: ownedAnalysis, error: analysisOwnerErr } = await supabase
    .from("analyses")
    .select(
      "id,user_id,status,worker_attempt_count,analysis_sector,analysis_sector_source,analysis_sector_prompt_version,raw_ai_response",
    )
    .eq("id", analysisID)
    .eq("user_id", user.id)
    .maybeSingle();

  if (analysisOwnerErr || !ownedAnalysis) {
    console.warn(
      "Analyze ownership denied",
      JSON.stringify({
        request_id: requestID,
        support_id: supportID,
        analysis_id: analysisID,
        user_hash: await hashedID(user.id),
        error: analysisOwnerErr ? safeLogError(analysisOwnerErr) : null,
      }),
    );
    return errorResponse(
      404,
      "Analiz bulunamadı veya bu işlem için yetki yok.",
      {
        code: "analysis_not_found",
        requestID,
        supportID,
      },
    );
  }

  if (isWorkerInvocation && ownedAnalysis.status === "completed") {
    return new Response(
      JSON.stringify({
        ok: true,
        status: "already_completed",
        analysis_id: analysisID,
        request_id: requestID,
        support_id: supportID,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  // deno-lint-ignore no-explicit-any
  const updateOwnedAnalysis = (patch: Record<string, any>) =>
    supabase.from("analyses")
      .update(patch)
      .eq("id", analysisID)
      .eq("user_id", user.id);

  const requestedPhotoCount = requestedPhotoPaths.length +
    (Array.isArray(photo_base64_parts) ? photo_base64_parts.length : 0);
  const hasLegacyTextInput = typeof text_input === "string"
    ? text_input.trim().length > 0
    : text_input !== null && text_input !== undefined;

  if (hasLegacyTextInput) {
    await updateOwnedAnalysis({
      status: "failed",
      status_message:
        `Metin analizi kaldırıldı. Lütfen uygulamayı güncelle ve fotoğrafla analiz başlat. Destek kodu: ${supportID}`,
      input_payload_version: requestedPhotoCount > 0
        ? "photo-with-text-disabled-v1"
        : "text-disabled-v1",
      photo_count: requestedPhotoCount,
      raw_ai_response: {
        _input_audit: {
          prompt_version: PROMPT_VERSION,
          input_mode: requestedPhotoCount > 0 ? "photo_with_text" : "text",
          text_analysis_removed: true,
          text_input_present: true,
          requested_photo_count: requestedPhotoCount,
          request_id: requestID,
          support_id: supportID,
        },
      },
    });
    return errorResponse(
      410,
      "Metin analizi kaldırıldı. Lütfen uygulamayı güncelle ve fotoğrafla analiz başlat.",
      {
        code: "TEXT_ANALYSIS_REMOVED",
        requestID,
        supportID,
        requested_photo_count: requestedPhotoCount,
      },
    );
  }

  if (requestedPhotoCount <= 0) {
    await updateOwnedAnalysis({
      status: "failed",
      status_message:
        `Analiz için en az bir fotoğraf gerekli. Destek kodu: ${supportID}`,
      input_payload_version: "photo-required-v1",
      photo_count: 0,
      raw_ai_response: {
        _input_audit: {
          prompt_version: PROMPT_VERSION,
          input_mode: "none",
          text_analysis_removed: true,
          text_input_present: false,
          requested_photo_count: 0,
          request_id: requestID,
          support_id: supportID,
        },
      },
    });
    return errorResponse(400, "Analiz için en az bir fotoğraf gerekli.", {
      code: "PHOTO_REQUIRED",
      requestID,
      supportID,
      requested_photo_count: 0,
    });
  }

  const activeSectorState = resolveActiveSectorState({
    requestedSector: requestedAnalysisSector,
    persistedSector: ownedAnalysis?.analysis_sector,
    requestedSource: analysis_sector_source,
    persistedSource: ownedAnalysis?.analysis_sector_source,
    requestedPromptVersion: analysis_sector_prompt_version,
    persistedPromptVersion: ownedAnalysis?.analysis_sector_prompt_version,
    isWorkerInvocation,
  });

  if (!activeSectorState.ok) {
    return errorResponse(activeSectorState.status, activeSectorState.message, {
      code: activeSectorState.code,
      requestID,
      supportID,
    });
  }

  if (activeSectorState.shouldBackfill) {
    const { error: sectorBackfillErr } = await updateOwnedAnalysis(
      activeSectorState.backfillPatch,
    );
    if (sectorBackfillErr) {
      console.error(
        "Active analysis sector backfill failed",
        JSON.stringify({
          request_id: requestID,
          support_id: supportID,
          analysis_id: analysisID,
          error: safeLogError(sectorBackfillErr),
        }),
      );
      await updateOwnedAnalysis({
        status: "failed",
        status_message:
          `Analiz kapsamı kaydedilemedi. Destek kodu: ${supportID}`,
      });
      return errorResponse(500, "Analiz kapsamı kaydedilemedi.", {
        code: "sector_backfill_failed",
        requestID,
        supportID,
      });
    }
  }

  const requestedCanvases = [
    ...new Set(
      (Array.isArray(canvases) && canvases.length > 0 ? canvases : [canvas])
        .map((item) => String(item ?? "").trim())
        .filter((item) => item.length > 0),
    ),
  ];
  const analysisMode = normalizeAnalysisMode(analysis_mode, requestedCanvases);

  // Backend-synced subscription tier is the only source for paid AI routing.
  const { data: subscription, error: subscriptionError } = await supabase
    .from("user_subscriptions")
    .select(
      "tier,status,product_id,current_period_ends_at,trial_started_at,trial_ends_at,trial_product_id,will_renew",
    )
    .eq("user_id", user.id)
    .maybeSingle();
  if (subscriptionError) {
    console.error(
      "Subscription lookup failed",
      JSON.stringify({
        request_id: requestID,
        support_id: supportID,
        error: safeLogError(subscriptionError),
      }),
    );
    await updateOwnedAnalysis({
      status: "failed",
      status_message:
        `Abonelik bilgisi doğrulanamadı. Destek kodu: ${supportID}`,
    });
    return errorResponse(
      500,
      "Abonelik bilgisi doğrulanamadı. Lütfen tekrar dene.",
      {
        code: "subscription_lookup_failed",
        requestID,
        supportID,
      },
    );
  }

  const planTier = resolvePlanTier(subscription);
  const cancelledTrialRoutingFlag = planTier === "plus"
    ? await loadCancelledPlusTrialRoutingFlag(supabase)
    : normalizeCancelledPlusTrialRoutingFlag(null);
  const cancelledTrialRouting: CancelledPlusTrialRoutingDecision =
    cancelledPlusTrialRoutingDecision({
      subscription,
      flag: cancelledTrialRoutingFlag,
      userHash: await hashedID(user.id),
    });
  const photoCapabilities = await resolvePhotoCapabilities(
    supabase,
    planTier,
    clientRelease,
  );
  if (requestedPhotoCount > photoCapabilities.maxPhotosPerAnalysis) {
    await updateOwnedAnalysis({
      status: "failed",
      status_message:
        `Bu plan için fotoğraf limiti aşıldı. Destek kodu: ${supportID}`,
      plan_at_creation: planTier,
      max_photos_allowed_at_creation: photoCapabilities.maxPhotosPerAnalysis,
      photo_count: requestedPhotoCount,
      max_findings_per_photo: photoCapabilities.maxFindingsPerPhoto,
      max_findings_total: photoCapabilities.maxFindingsPerAnalysis,
      capability_snapshot: photoCapabilitiesSnapshot(photoCapabilities),
      rollout_snapshot: photoCapabilities.featureFlags,
    });
    return errorResponse(
      planTier === "free" ? 402 : 400,
      planTier === "free"
        ? "Free planda tek fotoğraf analizi yapılabilir."
        : `Bu planda en fazla ${photoCapabilities.maxPhotosPerAnalysis} fotoğraf analiz edilebilir.`,
      {
        code: "PHOTO_LIMIT_EXCEEDED",
        requestID,
        supportID,
        tier: planTier,
        max_photos_per_analysis: photoCapabilities.maxPhotosPerAnalysis,
        requested_photo_count: requestedPhotoCount,
        upgrade_target: planTier === "free" ? "plus" : null,
        paywall_context: planTier === "free" ? "multi_photo_limit" : null,
      },
    );
  }
  const aiExecutionRoute = resolveAIExecutionRoute(
    planTier,
    analysisMode,
    cancelledTrialRouting.enabled,
  );
  const qualityTier = resolveQualityTier(planTier, aiExecutionRoute);
  const geminiKeys = geminiKeyPoolForRoute(aiExecutionRoute);
  const freeFallbackGeminiKeys = aiExecutionRoute === "free_paid_trial"
    ? freeGeminiKeyPool()
    : [];
  const expectedGeminiPool = expectedGeminiPoolForRoute(aiExecutionRoute);
  let company: CompanyRow | null = null;
  let onboardingAnswers: OnboardingAnswersRow | null = null;

  const { data: onboardingRow, error: onboardingError } = await supabase
    .from("user_onboarding_answers")
    .select(
      "certificate_class,hazard_classes,sectors,audit_frequency,updated_at",
    )
    .eq("user_id", user.id)
    .maybeSingle();
  if (onboardingError) {
    console.warn(
      "Onboarding personalization lookup failed; continuing neutral",
      JSON.stringify({
        request_id: requestID,
        support_id: supportID,
        error: safeLogError(onboardingError),
      }),
    );
  } else {
    onboardingAnswers = onboardingRow as OnboardingAnswersRow | null;
  }

  if (
    isWorkerInvocation &&
    (geminiKeys.length === 0 ||
      geminiKeys.some((item) => item.pool !== expectedGeminiPool))
  ) {
    console.error(
      "Gemini key pool misconfigured",
      JSON.stringify({
        request_id: requestID,
        support_id: supportID,
        user_plan: planTier,
        quality_tier: qualityTier,
        ai_execution_route: aiExecutionRoute,
        expected_pool: expectedGeminiPool,
        available_aliases: geminiKeys.map((item) => item.alias),
        required_secret: geminiRequiredSecretNameForRoute(aiExecutionRoute),
      }),
    );
    await updateOwnedAnalysis({
      status: "failed",
      status_message:
        `AI servis anahtarı yapılandırılmamış. Destek kodu: ${supportID}`,
    });
    return errorResponse(
      500,
      "AI servisi yapılandırılmamış. Lütfen destek ile iletişime geç.",
      {
        code: "missing_ai_secret",
        requestID,
        supportID,
        tier: planTier,
      },
    );
  }

  if (requestedCompanyID.length > 0) {
    if (planTier === "free") {
      await updateOwnedAnalysis({
        status: "failed",
        status_message:
          `Firma bazlı analiz Plus veya Pro üyelik gerektirir. Destek kodu: ${supportID}`,
      });
      return errorResponse(
        403,
        "Firma bazlı analiz Plus veya Pro üyelik gerektirir.",
        {
          code: "plan_required",
          requestID,
          supportID,
          tier: planTier,
          feature: "companies",
        },
      );
    }

    const { data: companyRow, error: companyError } = await supabase
      .from("companies")
      .select("id,user_id,name,hazard_class,logo_path,is_archived")
      .eq("id", requestedCompanyID)
      .eq("user_id", user.id)
      .eq("is_archived", false)
      .maybeSingle();

    if (companyError || !companyRow) {
      await updateOwnedAnalysis({
        status: "failed",
        status_message: `Firma doğrulanamadı. Destek kodu: ${supportID}`,
      });
      return errorResponse(403, "Firma doğrulanamadı.", {
        code: "company_not_authorized",
        requestID,
        supportID,
      });
    }

    company = companyRow as CompanyRow;
    await updateOwnedAnalysis({ company_id: company.id });
  }

  if (planTier === "free" && requestedCanvases.length > 1) {
    await updateOwnedAnalysis({
      status: "failed",
      status_message:
        `Free planda tek analiz odağı seçebilirsin. Destek kodu: ${supportID}`,
    });
    return errorResponse(
      403,
      "Free planda tek analiz odağı seçebilirsin.",
      {
        code: "single_canvas_required",
        requestID,
        supportID,
        tier: planTier,
      },
    );
  }

  if (requestedCanvases.some((id) => !canUseCanvas(planTier, String(id)))) {
    await updateOwnedAnalysis({
      status: "failed",
      status_message:
        `Bu analiz odağı daha yüksek üyelik gerektirir. Destek kodu: ${supportID}`,
    });
    return errorResponse(
      403,
      "Bu analiz odağı daha yüksek üyelik gerektirir.",
      {
        code: "plan_required",
        requestID,
        supportID,
      },
    );
  }

  if (analysisMode === "detailed" && planTier === "free") {
    await updateOwnedAnalysis({
      status: "failed",
      status_message:
        `Detaylı analiz Plus veya Pro üyelik gerektirir. Destek kodu: ${supportID}`,
    });
    return errorResponse(
      403,
      "Detaylı analiz Plus veya Pro üyelik gerektirir.",
      {
        code: "plan_required",
        requestID,
        supportID,
      },
    );
  }

  if (analysisMode === "emergency" && planTier === "free") {
    await updateOwnedAnalysis({
      status: "failed",
      status_message:
        `Acil risk modülü Plus veya Pro üyelik gerektirir. Destek kodu: ${supportID}`,
    });
    return errorResponse(
      403,
      "Acil risk modülü Plus veya Pro üyelik gerektirir.",
      {
        code: "plan_required",
        requestID,
        supportID,
      },
    );
  }

  if (analysisMode === "procedure" && planTier !== "pro") {
    await updateOwnedAnalysis({
      status: "failed",
      status_message:
        `Prosedür uygunluk kontrolü Pro üyelik gerektirir. Destek kodu: ${supportID}`,
    });
    return errorResponse(
      403,
      "Prosedür uygunluk kontrolü Pro üyelik gerektirir.",
      {
        code: "plan_required",
        requestID,
        supportID,
      },
    );
  }

  await updateOwnedAnalysis({
    input_payload_version: requestedPhotoCount > 1
      ? "photo-batch-v2"
      : "photo-single-v1",
    photo_count: requestedPhotoCount,
    max_photos_allowed_at_creation: photoCapabilities.maxPhotosPerAnalysis,
    max_findings_per_photo: photoCapabilities.maxFindingsPerPhoto,
    max_findings_total: requestedPhotoCount > 0
      ? Math.min(
        photoCapabilities.maxFindingsPerAnalysis,
        requestedPhotoCount * photoCapabilities.maxFindingsPerPhoto,
      )
      : null,
    plan_at_creation: planTier,
    capability_snapshot: photoCapabilitiesSnapshot(photoCapabilities),
    rollout_snapshot: photoCapabilities.featureFlags,
  });

  const { data: quotaReservation, error: quotaReservationErr } = await supabase
    .rpc("reserve_analysis_quota", {
      p_user_id: user.id,
      p_analysis_id: analysisID,
      p_analysis_mode: analysisMode,
    });

  if (quotaReservationErr) {
    console.error(
      "Quota reservation failed",
      JSON.stringify({
        request_id: requestID,
        support_id: supportID,
        analysis_id: analysisID,
        error: safeLogError(quotaReservationErr),
      }),
    );
    await updateOwnedAnalysis({
      status: "failed",
      status_message:
        `Analiz kotası kontrol edilemedi. Destek kodu: ${supportID}`,
    });
    return errorResponse(500, "Analiz kotası kontrol edilemedi.", {
      code: "quota_check_failed",
      requestID,
      supportID,
    });
  }

  if (quotaReservation?.ok !== true) {
    await updateOwnedAnalysis({
      status: "failed",
      status_message: `${
        quotaReservation?.message ?? "Analiz kotası doldu."
      } Destek kodu: ${supportID}`,
    });
    return errorResponse(
      quotaReservation?.code === "plan_required" ? 403 : 429,
      quotaReservation?.message ?? "Analiz kotası doldu.",
      {
        code: quotaReservation?.code ?? "quota_exceeded",
        requestID,
        supportID,
        tier: quotaReservation?.tier,
        limit: quotaReservation?.limit,
        used: quotaReservation?.used,
        feature: quotaReservation?.feature,
      },
    );
  }

  if (!isWorkerInvocation) {
    try {
      const { queuedPhotoPaths } = await enqueueAnalysisJob({
        supabase,
        supabaseUrl,
        serviceRoleKey,
        body,
        userID: user.id,
        analysisID,
        requestID,
        supportID,
      });
      triggerAnalysisWorker({
        supabaseUrl,
        serviceRoleKey,
        requestID,
        supportID,
      });
      return new Response(
        JSON.stringify({
          ok: true,
          status: "queued",
          analysis_id: analysisID,
          queued_photo_count: queuedPhotoPaths.length,
          request_id: requestID,
          support_id: supportID,
        }),
        {
          status: 202,
          headers: { "Content-Type": "application/json" },
        },
      );
    } catch (error) {
      await releaseAnalysisQuota(supabase, analysisID, user.id);
      await updateOwnedAnalysis({
        status: "failed",
        status_message:
          `Fotoğraf kaydı tamamlanamadı. Destek kodu: ${supportID}`,
        raw_ai_response: {
          _input_audit: {
            prompt_version: PROMPT_VERSION,
            input_mode: "photo",
            inline_photo_count: Array.isArray(body.photo_base64_parts)
              ? body.photo_base64_parts.length
              : 0,
            storage_photo_count: Array.isArray(body.photo_paths)
              ? body.photo_paths.length
              : 0,
            request_id: requestID,
            support_id: supportID,
            enqueue_error: safeLogError(error),
          },
        },
      });
      console.error(
        "Analyze enqueue failed",
        JSON.stringify({
          request_id: requestID,
          support_id: supportID,
          analysis_id: analysisID,
          error: safeLogError(error),
        }),
      );
      return errorResponse(500, "Analiz kuyruğa alınamadı.", {
        code: "analysis_enqueue_failed",
        requestID,
        supportID,
      });
    }
  }

  // Status → analyzing
  await updateOwnedAnalysis({
    status: "analyzing",
    analysis_mode: analysisMode,
    started_at: new Date().toISOString(),
    worker_started_at: new Date().toISOString(),
    worker_attempt_count: (ownedAnalysis.worker_attempt_count ?? 0) + 1,
    last_worker_error: null,
  });

  const model = primaryModelForRoute(aiExecutionRoute);

  // Storage → base64
  const imageBase64Parts: AIImagePart[] = [];
  const inlinePhotoParts = Array.isArray(photo_base64_parts)
    ? photo_base64_parts
    : [];
  const sanitizedInlinePhotos: {
    mimeType: "image/jpeg" | "image/png";
    bytes: Uint8Array;
    data: string;
    width: number;
    height: number;
    jpegQuality: number | null;
    qualityPolicy: string | null;
    maxDimension: number | null;
  }[] = [];
  const inlinePhotoCount = inlinePhotoParts.length;
  const storagePhotoCount = requestedPhotoPaths.length;

  for (const part of inlinePhotoParts) {
    if (!part?.data) continue;
    const mimeType = normalizedImageMimeType(part.mime_type ?? part.mimeType);
    const rawBytes = base64ToBytes(part.data);
    const bytes = stripImageMetadata(rawBytes, mimeType);
    const data = bytesToBase64(bytes);
    sanitizedInlinePhotos.push({
      mimeType,
      bytes,
      data,
      width: sanitizedDimension(part.width),
      height: sanitizedDimension(part.height),
      jpegQuality: numericMetadata(part.jpeg_quality ?? part.jpegQuality),
      qualityPolicy: safeText(
        part.quality_policy ?? part.qualityPolicy,
        "legacy-client",
      ).slice(0, 80),
      maxDimension: numericMetadata(part.max_dimension ?? part.maxDimension),
    });
    const photoIndex = imageBase64Parts.length + 1;
    imageBase64Parts.push({
      mimeType,
      data,
      photoIndex,
      width: sanitizedDimension(part.width),
      height: sanitizedDimension(part.height),
      decodedByteCount: bytes.byteLength,
      encodedByteCount: data.length,
      jpegQuality: numericMetadata(part.jpeg_quality ?? part.jpegQuality),
      qualityPolicy: safeText(
        part.quality_policy ?? part.qualityPolicy,
        "legacy-client",
      ).slice(0, 80),
      maxDimension: numericMetadata(part.max_dimension ?? part.maxDimension),
      source: "inline",
    });
  }

  // Inline gelen fotoğrafları kalıcı olarak Storage + photos tablosuna yaz.
  // Client tarafında Storage RLS'e takılmamak için bu işi service role ile Edge Function yapıyor.
  const persistedPhotoPaths: string[] = [];
  const photoPersistErrors: Record<string, unknown>[] = [];
  const uploadedInlinePhotoPaths: string[] = [];
  const failPhotoPersistence = async (
    code: string,
    message: string,
    httpStatus = 500,
  ) => {
    if (uploadedInlinePhotoPaths.length > 0) {
      const { error: storageCleanupError } = await supabase.storage.from(
        "photos",
      ).remove(uploadedInlinePhotoPaths);
      if (storageCleanupError) {
        console.error(
          "Persist inline photo storage cleanup error",
          JSON.stringify({
            request_id: requestID,
            support_id: supportID,
            analysis_id: analysisID,
            error: safeLogError(storageCleanupError),
          }),
        );
      }
    }

    const { error: metadataCleanupError } = await supabase.from("photos")
      .delete()
      .eq("analysis_id", analysisID)
      .eq("user_id", user.id);
    if (metadataCleanupError) {
      console.error(
        "Persist inline photo metadata cleanup error",
        JSON.stringify({
          request_id: requestID,
          support_id: supportID,
          analysis_id: analysisID,
          error: safeLogError(metadataCleanupError),
        }),
      );
    }

    await updateOwnedAnalysis({
      status: "failed",
      status_message: `${message} Destek kodu: ${supportID}`,
      raw_ai_response: {
        _input_audit: {
          prompt_version: PROMPT_VERSION,
          input_mode: "photo",
          inline_photo_count: inlinePhotoCount,
          storage_photo_count: storagePhotoCount,
          persisted_photo_count: persistedPhotoPaths.length,
          persisted_photo_paths: persistedPhotoPaths,
          photo_persist_error_count: photoPersistErrors.length,
          photo_persist_errors: photoPersistErrors,
          request_id: requestID,
          support_id: supportID,
        },
      },
    });
    await releaseAnalysisQuota(supabase, analysisID, user.id);
    return errorResponse(httpStatus, message, {
      code,
      requestID,
      supportID,
    });
  };
  if (sanitizedInlinePhotos.length > 0) {
    const { error: deletePhotoErr } = await supabase.from("photos")
      .delete()
      .eq("analysis_id", analysisID)
      .eq("user_id", user.id);

    if (deletePhotoErr) {
      photoPersistErrors.push({
        stage: "delete_existing_metadata",
        error: safeLogError(deletePhotoErr),
      });
      console.error(
        "Persist inline photo cleanup error",
        JSON.stringify({
          request_id: requestID,
          support_id: supportID,
          analysis_id: analysisID,
          error: safeLogError(deletePhotoErr),
        }),
      );
      return await failPhotoPersistence(
        "photo_persist_failed",
        "Fotoğraf kaydı hazırlanamadı.",
      );
    }

    for (let i = 0; i < sanitizedInlinePhotos.length; i++) {
      const part = sanitizedInlinePhotos[i];
      const mimeType = part.mimeType;
      const ext = mimeType.includes("png") ? "png" : "jpg";
      const storagePath = `${user.id}/${analysisID}/p${i + 1}.${ext}`;
      const uploadBody = part.bytes.byteOffset === 0 &&
          part.bytes.byteLength === part.bytes.buffer.byteLength
        ? part.bytes
        : part.bytes.slice();

      const uploadResult = await uploadStorageObject({
        supabaseUrl,
        serviceRoleKey,
        bucket: "photos",
        path: storagePath,
        body: uploadBody,
        mimeType,
      });

      if (!uploadResult.ok) {
        photoPersistErrors.push({
          stage: "storage_upload",
          photo_index: i + 1,
          status: uploadResult.status,
          error: safeLogText(uploadResult.error),
        });
        console.error(
          "Persist inline photo upload error",
          JSON.stringify({
            request_id: requestID,
            support_id: supportID,
            analysis_id: analysisID,
            photo_index: i + 1,
            status: uploadResult.status,
            error: safeLogText(uploadResult.error),
          }),
        );
        return await failPhotoPersistence(
          "photo_persist_failed",
          "Fotoğraf kaydedilemedi.",
        );
      }
      uploadedInlinePhotoPaths.push(storagePath);

      const { error: photoErr } = await supabase.from("photos").insert({
        analysis_id: analysisID,
        user_id: user.id,
        storage_path: storagePath,
        width: part.width,
        height: part.height,
        size_bytes: part.bytes.byteLength,
        byte_size: part.bytes.byteLength,
        mime_type: mimeType,
        sequence_index: i + 1,
        client_photo_id: safeText(
          inlinePhotoParts[i]?.client_photo_id ??
            inlinePhotoParts[i]?.clientPhotoID,
        ).slice(0, 80) || null,
        is_primary: i === 0,
        upload_payload_version: sanitizedInlinePhotos.length > 1
          ? "photo-batch-v2"
          : "photo-single-v1",
      });

      if (photoErr) {
        photoPersistErrors.push({
          stage: "metadata_insert",
          photo_index: i + 1,
          error: safeLogError(photoErr),
        });
        console.error(
          "Persist inline photo metadata error",
          JSON.stringify({
            request_id: requestID,
            support_id: supportID,
            analysis_id: analysisID,
            photo_index: i + 1,
            error: safeLogError(photoErr),
          }),
        );
        return await failPhotoPersistence(
          "photo_persist_failed",
          "Fotoğraf kaydı tamamlanamadı.",
        );
      }

      persistedPhotoPaths.push(storagePath);
    }
  }

  const uniqueRequestedPhotoPaths = [...new Set(requestedPhotoPaths)];
  const requestedPhotoMetaByPath = new Map<
    string,
    {
      width: number;
      height: number;
      sizeBytes: number | null;
      mimeType: string | null;
    }
  >();
  if (uniqueRequestedPhotoPaths.length > 0) {
    const expectedPrefix = `${user.id}/${analysisID}/`;
    const { data: ownedPhotoRows, error: ownedPhotoErr } = await supabase
      .from("photos")
      .select("storage_path,width,height,size_bytes,byte_size,mime_type")
      .eq("analysis_id", analysisID)
      .eq("user_id", user.id)
      .in("storage_path", uniqueRequestedPhotoPaths);

    const ownedPaths = new Set(
      (ownedPhotoRows ?? []).map((row) => String(row.storage_path)),
    );
    for (const row of ownedPhotoRows ?? []) {
      const storagePath = String(row.storage_path ?? "");
      if (!storagePath) continue;
      requestedPhotoMetaByPath.set(storagePath, {
        width: sanitizedDimension(row.width),
        height: sanitizedDimension(row.height),
        sizeBytes: numericMetadata(row.size_bytes ?? row.byte_size),
        mimeType: safeText(row.mime_type) || null,
      });
    }
    const invalidPaths = uniqueRequestedPhotoPaths.filter((path) =>
      !path.startsWith(expectedPrefix) || !ownedPaths.has(path)
    );

    if (ownedPhotoErr || invalidPaths.length > 0) {
      console.warn(
        "Analyze photo ownership denied",
        JSON.stringify({
          request_id: requestID,
          support_id: supportID,
          analysis_id: analysisID,
          user_hash: await hashedID(user.id),
          invalid_path_count: invalidPaths.length,
          error: ownedPhotoErr ? safeLogError(ownedPhotoErr) : null,
        }),
      );
      await updateOwnedAnalysis({
        status: "failed",
        status_message:
          `Fotoğraf bu analiz için doğrulanamadı. Destek kodu: ${supportID}`,
      });
      await releaseAnalysisQuota(supabase, analysisID, user.id);
      return errorResponse(403, "Fotoğraf bu analiz için doğrulanamadı.", {
        code: "photo_not_authorized",
        requestID,
        supportID,
      });
    }
  }

  for (const path of uniqueRequestedPhotoPaths) {
    const { data: fileData, error: storageErr } = await supabase.storage.from(
      "photos",
    ).download(path);
    if (storageErr || !fileData) {
      console.error(
        "Storage download error",
        JSON.stringify({
          request_id: requestID,
          support_id: supportID,
          analysis_id: analysisID,
          error: storageErr
            ? safeLogError(storageErr)
            : { name: "empty_file_data" },
        }),
      );
      await updateOwnedAnalysis({
        status: "failed",
        status_message: `Fotoğraf indirilemedi. Destek kodu: ${supportID}`,
      });
      await releaseAnalysisQuota(supabase, analysisID, user.id);
      return errorResponse(500, "Fotoğraf indirilemedi.", {
        code: "photo_download_failed",
        requestID,
        supportID,
      });
    }
    const buffer = await fileData.arrayBuffer();
    const bytes = new Uint8Array(buffer);
    let binary = "";
    for (let i = 0; i < bytes.length; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    const base64 = btoa(binary);
    const storedMeta = requestedPhotoMetaByPath.get(path);
    const mimeType = normalizedImageMimeType(
      storedMeta?.mimeType ??
        (path.endsWith(".png") ? "image/png" : "image/jpeg"),
    );
    const width = sanitizedDimension(storedMeta?.width);
    const height = sanitizedDimension(storedMeta?.height);
    const maxDimension = Math.max(width, height);
    const photoIndex = imageBase64Parts.length + 1;
    imageBase64Parts.push({
      mimeType,
      data: base64,
      photoIndex,
      width,
      height,
      decodedByteCount: bytes.byteLength,
      encodedByteCount: base64.length,
      jpegQuality: null,
      qualityPolicy: "storage-existing",
      maxDimension: maxDimension > 0 ? maxDimension : null,
      source: "storage",
    });
  }

  const validRequestedCanvases = requestedCanvases.filter((id) =>
    Boolean(CANVAS_FOCUS[id])
  );
  const resolvedCanvases = validRequestedCanvases.length > 0
    ? validRequestedCanvases
    : ["general"];
  const resolvedCanvasPrompts = resolvedCanvases
    .map((id) => ({ id, prompt: CANVAS_FOCUS[id] }))
    .filter((item) => Boolean(item.prompt));
  const systemPrompt = buildSystemPrompt();
  const resolvedActiveSector = activeSectorState.sector;
  const resolvedActiveSectorSource = activeSectorState.source;
  const resolvedActiveSectorPromptVersion = activeSectorState.promptVersion;
  const onboardingContext = buildOnboardingContext(
    onboardingAnswers,
    Boolean(resolvedActiveSector),
  );
  const companyContext = companyPromptContext(company);
  const photoFindingPolicy: AnalysisFindingPolicy | null =
    imageBase64Parts.length > 0
      ? {
        photoCount: imageBase64Parts.length,
        maxFindingsPerPhoto: photoCapabilities.maxFindingsPerPhoto,
        maxFindingsTotal: Math.min(
          photoCapabilities.maxFindingsPerAnalysis,
          imageBase64Parts.length * photoCapabilities.maxFindingsPerPhoto,
        ),
      }
      : null;
  const multiPhotoCoveragePolicy = coveragePolicyFor(
    photoCapabilities,
    imageBase64Parts.length,
  );
  const requestedRepairPhotoIndices = normalizeRepairPhotoIndices(
    body.repair_photo_indices,
    imageBase64Parts.length,
  );
  const previousCoverageRecords =
    jobMode === "repair" && multiPhotoCoveragePolicy
      ? normalizePhotoFindingCoverage(
        ownedAnalysis.raw_ai_response?.photo_findings,
        multiPhotoCoveragePolicy,
      )
      : null;
  const analysisFindingPolicy = multiPhotoCoveragePolicy && photoFindingPolicy
    ? {
      ...photoFindingPolicy,
      maxFindingsPerPhoto: multiPhotoCoveragePolicy.targetMax,
      maxFindingsTotal: multiPhotoCoveragePolicy.totalMax,
      coverageV2Enabled: true,
      targetFindingsPerPhotoMin: multiPhotoCoveragePolicy.targetMin,
      targetFindingsPerPhotoMax: multiPhotoCoveragePolicy.targetMax,
      coverageRepairEnabled: multiPhotoCoveragePolicy.repairEnabled,
    }
    : photoFindingPolicy;
  const analysisContext = buildAnalysisContext({
    canvases: resolvedCanvases,
    tier: planTier,
    onboardingContext,
    companyContext,
    activeSector: resolvedActiveSector,
    findingPolicy: analysisFindingPolicy ?? undefined,
  });
  const contextHash = await hashedID(analysisContext);
  const referenceMode = referenceModeForTier(planTier);
  const aiSimulation = aiSimulationConfig();
  const inputAudit: Record<string, unknown> = {
    prompt_version: PROMPT_VERSION,
    personalization_version: PERSONALIZATION_VERSION,
    personalization_applied: onboardingContext.applied,
    certificate_class: onboardingContext.certificateClass,
    hazard_classes: onboardingContext.hazardClasses,
    sectors: onboardingContext.sectors,
    onboarding_sector_count: onboardingContext.sectors.length,
    audit_frequency: onboardingContext.auditFrequency,
    active_analysis_sector: resolvedActiveSector,
    active_analysis_sector_source: resolvedActiveSectorSource,
    active_analysis_sector_prompt_version: resolvedActiveSectorPromptVersion,
    active_analysis_sector_label: resolvedActiveSector
      ? analysisSectorLabel(resolvedActiveSector, "tr")
      : null,
    sector_context_applied: Boolean(resolvedActiveSector),
    context_hash: contextHash,
    job_mode: jobMode,
    requested_repair_photo_indices: requestedRepairPhotoIndices,
    input_mode: requestedPhotoCount > 0 ? "photo" : "none",
    inline_photo_count: inlinePhotoCount,
    storage_photo_count: storagePhotoCount,
    persisted_photo_count: persistedPhotoPaths.length,
    persisted_photo_paths: persistedPhotoPaths,
    photo_persist_error_count: photoPersistErrors.length,
    photo_persist_errors: photoPersistErrors,
    gemini_image_part_count: imageBase64Parts.length,
    ai_image_part_count: imageBase64Parts.length,
    photo_quality_policy: imageBase64Parts.find((part) => part.qualityPolicy)
      ?.qualityPolicy ??
      null,
    photo_payload_total_base64_bytes: imageBase64Parts.reduce(
      (sum, part) => sum + part.encodedByteCount,
      0,
    ),
    photo_input_audit: imageBase64Parts.map(imagePartAudit),
    text_input_present: Boolean(text_input),
    analysis_mode: analysisMode,
    user_plan: planTier,
    quality_tier: qualityTier,
    ai_execution_route: aiExecutionRoute,
    cancelled_plus_trial_free_candidate: cancelledTrialRouting.eligible,
    cancelled_plus_trial_free_enabled: cancelledTrialRouting.enabled,
    cancelled_plus_trial_routing_mode: cancelledTrialRouting.mode,
    cancelled_plus_trial_routing_reason: cancelledTrialRouting.reason,
    free_standard_analysis_route_flag: freeStandardAnalysisRouteFlag(),
    request_id: requestID,
    support_id: supportID,
    selected_canvas_ids: resolvedCanvases,
    resolved_canvas_prompts: resolvedCanvasPrompts,
    company_id: company?.id ?? null,
    company_name: company?.name ?? null,
    company_hazard_class: company?.hazard_class ?? null,
    company_prompt_context: companyContext,
    onboarding_context_sent: onboardingContext.block,
    analysis_context_sent: analysisContext,
    min_hazards: imageBase64Parts.length > 0
      ? null
      : PLAN_LIMITS[planTier].minHazards ?? null,
    max_hazards: imageBase64Parts.length > 0
      ? analysisFindingPolicy?.maxFindingsTotal ?? null
      : PLAN_LIMITS[planTier].maxHazards ?? null,
    max_findings_per_photo: imageBase64Parts.length > 0
      ? analysisFindingPolicy?.maxFindingsPerPhoto ?? null
      : null,
    max_findings_total: imageBase64Parts.length > 0
      ? analysisFindingPolicy?.maxFindingsTotal ?? null
      : null,
    coverage_v2: Boolean(multiPhotoCoveragePolicy),
    coverage_repair_enabled: multiPhotoCoveragePolicy?.repairEnabled ?? null,
    target_findings_per_photo_min: multiPhotoCoveragePolicy?.targetMin ?? null,
    target_findings_per_photo_max: multiPhotoCoveragePolicy?.targetMax ?? null,
    target_findings_total_max: multiPhotoCoveragePolicy?.totalMax ?? null,
    photo_policy_version: multiPhotoCoveragePolicy?.policyVersion ?? null,
    coverage_policy_version: multiPhotoCoveragePolicy?.policyVersion ?? null,
    repair_job_used: jobMode === "repair",
    repair_photo_indices: jobMode === "repair"
      ? requestedRepairPhotoIndices
      : [],
    reference_mode: referenceMode,
    references_requested: planTier !== "free",
    root_cause_requested: true,
    response_schema_includes_references: planTier !== "free",
    response_schema_includes_root_cause: true,
    response_schema_includes_needs_field_verification: true,
    system_prompt_sent: systemPrompt,
    model,
    gemini_key_pool: expectedGeminiPool,
    gemini_key_aliases_available: geminiKeys.map((item) => item.alias),
    free_gemini_fallback_aliases_available: freeFallbackGeminiKeys.map((item) =>
      item.alias
    ),
    groq_free_fallback_configured: aiExecutionRoute !== "paid_plan"
      ? Boolean(freeGroqKeyConfig())
      : false,
    groq_free_model: aiExecutionRoute !== "paid_plan" && freeGroqKeyConfig()
      ? freeGroqModel()
      : null,
    groq_plus_pro_fallback_configured: aiExecutionRoute === "paid_plan"
      ? Boolean(plusProGroqKeyConfig())
      : false,
    groq_plus_pro_model: aiExecutionRoute === "paid_plan" &&
        plusProGroqKeyConfig()
      ? plusProGroqModel()
      : null,
    test_simulation_enabled: aiSimulation.enabled,
    test_simulation_mode: aiSimulation.enabled ? aiSimulation.mode : null,
  };

  // deno-lint-ignore no-explicit-any
  let geminiResult: any;
  let inputTokens = 0, outputTokens = 0;
  let cachedTokens: number | null = null;
  let thoughtsTokens: number | null = null;
  let totalTokens: number | null = null;
  let aiError: string | null = null;
  let modelUsed = model;
  let providerUsed: AIProvider = "gemini";
  let apiKeyAlias: string | null = null;
  let attemptCount = 0;
  let aiFallbackSource: string | null = null;
  const primaryGeminiAlias = geminiKeys[0]?.alias ?? null;
  const callAIForAnalysis = async (
    context: string,
    parts: AIImagePart[],
    coveragePolicy?: MultiPhotoCoveragePolicy | null,
    options: AIRequestOptions = {},
  ) => {
    if (usesFreeGeminiProviderPool(aiExecutionRoute)) {
      return await callAIWithFreeProviderPool(
        geminiKeys,
        model,
        systemPrompt,
        context,
        null,
        parts,
        aiExecutionRoute === CANCELLED_PLUS_TRIAL_ROUTE ? planTier : "free",
        aiSimulation,
        { requestID, supportID },
        coveragePolicy,
        options,
      );
    }
    if (aiExecutionRoute === "free_paid_trial") {
      return await callFreePaidTrialAIWithFallback(
        geminiKeys,
        freeFallbackGeminiKeys,
        model,
        systemPrompt,
        context,
        null,
        parts,
        planTier,
        aiSimulation,
        { requestID, supportID },
        coveragePolicy,
        options,
      );
    }
    return await callPaidAIWithFallback(
      geminiKeys,
      model,
      systemPrompt,
      context,
      null,
      parts,
      planTier,
      aiSimulation,
      { requestID, supportID },
      coveragePolicy,
      options,
    );
  };

  const effectiveRepairPhotoIndices = jobMode === "repair" &&
      multiPhotoCoveragePolicy
    ? (requestedRepairPhotoIndices.length > 0
      ? requestedRepairPhotoIndices
      : coverageRepairCandidates(
        previousCoverageRecords ?? [],
        multiPhotoCoveragePolicy,
      ))
    : [];
  const aiContext = jobMode === "repair" && multiPhotoCoveragePolicy &&
      previousCoverageRecords && effectiveRepairPhotoIndices.length > 0
    ? buildCoverageRepairContext(
      analysisContext,
      multiPhotoCoveragePolicy,
      previousCoverageRecords,
      effectiveRepairPhotoIndices,
    )
    : analysisContext;
  const aiImageParts =
    jobMode === "repair" && effectiveRepairPhotoIndices.length > 0
      ? imageBase64Parts.filter((part) =>
        effectiveRepairPhotoIndices.includes(part.photoIndex)
      )
      : imageBase64Parts;
  const aiRequestOptions: AIRequestOptions = jobMode === "repair"
    ? { isRepairPass: true }
    : {};
  const repairFallbackOnly = jobMode === "repair" &&
    body.coverage_repair_fallback_only === true &&
    ownedAnalysis.raw_ai_response &&
    typeof ownedAnalysis.raw_ai_response === "object";

  if (repairFallbackOnly) {
    const fallbackReason = safeLogText(
      String(
        body.coverage_repair_fallback_reason ??
          "repair_worker_retries_exhausted",
      ),
    );
    geminiResult = {
      ...(ownedAnalysis.raw_ai_response as Record<string, unknown>),
      _repair_error: {
        message: fallbackReason,
        code: "coverage_repair_worker_fallback",
        support_id: supportID,
        request_id: requestID,
      },
    };
    inputAudit.coverage_repair_fallback_only = true;
    inputAudit.coverage_repair_error = fallbackReason;
    inputAudit.coverage_repair_failed_but_completed = true;
    inputAudit.finish_reason = null;
    inputAudit.json_parse_retry_count = 0;
    inputAudit.thinking_budget = thinkingBudgetFor(true);
    inputAudit.max_output_tokens = maxOutputTokensFor(
      Math.max(1, effectiveRepairPhotoIndices.length),
      planTier,
    );
  } else {
    try {
      const out = await callAIForAnalysis(
        aiContext,
        aiImageParts,
        multiPhotoCoveragePolicy,
        aiRequestOptions,
      );
      geminiResult = out.result;
      inputTokens = out.inputTokens;
      outputTokens = out.outputTokens;
      cachedTokens = out.cachedTokens;
      thoughtsTokens = out.thoughtsTokens;
      totalTokens = out.totalTokens;
      modelUsed = out.modelUsed;
      providerUsed = "providerUsed" in out ? out.providerUsed : "gemini";
      inputAudit.model = out.modelUsed;
      inputAudit.gemini_thinking_config = providerUsed === "gemini"
        ? geminiThinkingConfig(
          out.modelUsed,
          expectedGeminiPool,
          jobMode === "repair",
        )
        : null;
      apiKeyAlias = out.apiKeyAlias;
      attemptCount = out.attempt ?? 0;
      inputAudit.api_key_alias = apiKeyAlias;
      inputAudit.provider = providerUsed;
      inputAudit.finish_reason = out.finishReason;
      inputAudit.json_parse_retry_count = out.jsonParseRetryCount;
      inputAudit.thinking_budget = out.thinkingBudget;
      inputAudit.max_output_tokens = out.maxOutputTokens;
      inputAudit.repair_job_used = jobMode === "repair";
      inputAudit.repair_photo_indices = jobMode === "repair"
        ? requestedRepairPhotoIndices
        : [];
      inputAudit.promptTokenCount = inputTokens;
      inputAudit.candidatesTokenCount = outputTokens;
      inputAudit.cachedContentTokenCount = cachedTokens;
      inputAudit.thoughtsTokenCount = thoughtsTokens;
      inputAudit.totalTokenCount = totalTokens;
      inputAudit.gemini_attempt_failures = "geminiAttemptFailures" in out
        ? out.geminiAttemptFailures
        : [];
      if ("fallbackSource" in out) {
        aiFallbackSource = out.fallbackSource;
        inputAudit.fallback_source = aiFallbackSource;
      }
      if (providerUsed === "gemini") {
        inputAudit.gemini_attempt_count = attemptCount;
      } else {
        inputAudit.groq_fallback_used = true;
      }
    } catch (err) {
      aiError = String(err);
      if (
        jobMode === "repair" &&
        previousCoverageRecords &&
        ownedAnalysis.raw_ai_response &&
        typeof ownedAnalysis.raw_ai_response === "object"
      ) {
        const cleanError = userFacingAIError(err);
        geminiResult = {
          ...(ownedAnalysis.raw_ai_response as Record<string, unknown>),
          _repair_error: {
            message: aiError,
            code: cleanError.code,
            support_id: supportID,
            request_id: requestID,
          },
        };
        inputAudit.coverage_repair_error = safeLogError(err);
        inputAudit.coverage_repair_failed_but_completed = true;
        inputAudit.finish_reason = null;
        inputAudit.json_parse_retry_count = 0;
        inputAudit.thinking_budget = thinkingBudgetFor(true);
        inputAudit.max_output_tokens = maxOutputTokensFor(
          Math.max(1, effectiveRepairPhotoIndices.length),
          planTier,
        );
      } else {
        const cleanError = userFacingAIError(err);
        await releaseAnalysisQuota(supabase, analysisID, user.id);
        await updateOwnedAnalysis({
          status: "failed",
          status_message: `${cleanError.message} Destek kodu: ${supportID}`,
          raw_ai_response: {
            _input_audit: inputAudit,
            _error: {
              message: aiError,
              code: cleanError.code,
              support_id: supportID,
              request_id: requestID,
            },
          },
        });
        await logUsage(supabase, {
          analysis_id: analysisID,
          user_id: user.id,
          provider: providerUsed,
          model,
          tokens_in: 0,
          tokens_out: 0,
          duration_ms: Date.now() - startMs,
          error: aiError,
          user_plan: planTier,
          quality_tier: qualityTier,
          ai_execution_route: aiExecutionRoute,
          request_id: requestID,
          support_id: supportID,
          error_code: cleanError.code,
          http_status: cleanError.status,
          fallback_source: aiFallbackSource ??
            (modelUsed === model ? null : modelUsed),
          api_key_alias: apiKeyAlias,
          attempt_count: attemptCount || null,
          prompt_version: PROMPT_VERSION,
          personalization_version: PERSONALIZATION_VERSION,
          context_hash: contextHash,
          cached_tokens: null,
          thoughts_tokens: null,
          total_tokens: null,
        });
        return errorResponse(cleanError.status, cleanError.message, {
          code: cleanError.code,
          requestID,
          supportID,
        });
      }
    }
  }

  if (multiPhotoCoveragePolicy) {
    let coverageRecords = normalizePhotoFindingCoverage(
      geminiResult.photo_findings,
      multiPhotoCoveragePolicy,
    );
    if (jobMode === "repair" && previousCoverageRecords) {
      const repairRecords = coverageRecords;
      coverageRecords = previousCoverageRecords;
      if (repairRecords) {
        mergeCoverageRepairRecords(
          coverageRecords,
          repairRecords.filter((record) =>
            effectiveRepairPhotoIndices.includes(record.photo_index)
          ),
          multiPhotoCoveragePolicy,
        );
        inputAudit.coverage_repair_used = true;
        inputAudit.coverage_repair_photo_indices = effectiveRepairPhotoIndices;
      } else {
        inputAudit.coverage_repair_fallback_reason = "missing_photo_findings";
      }
    }
    if (!coverageRecords) {
      inputAudit.coverage_v2_fallback_reason = "missing_photo_findings";
    } else {
      const repairCandidates = coverageRepairCandidates(
        coverageRecords,
        multiPhotoCoveragePolicy,
      );
      inputAudit.coverage_repair_candidate_photo_indices = repairCandidates;
      if (
        jobMode === "analysis" &&
        multiPhotoCoveragePolicy.repairEnabled &&
        repairCandidates.length > 0
      ) {
        try {
          for (const record of coverageRecords) {
            record.coverage_gap_reason = normalizeCoverageGapReason(
              record.coverage_status,
              record.coverage_gap_reason,
              record.findings.length,
              multiPhotoCoveragePolicy.targetMin,
              record.record_missing,
            );
          }
          const firstPassShortfalls = coverageRepairCandidates(
            coverageRecords,
            multiPhotoCoveragePolicy,
          );
          const firstPassHazards = mergeDuplicateCoverageHazards(
            coverageRecords.flatMap((record) => record.findings),
            multiPhotoCoveragePolicy.photoCount,
            multiPhotoCoveragePolicy.totalMax,
          );
          const interimResult = {
            ...geminiResult,
            hazards: firstPassHazards,
            photo_summaries: buildPhotoSummariesFromCoverage(
              coverageRecords,
              multiPhotoCoveragePolicy,
            ),
            analysis_quality: {
              photo_policy_version: multiPhotoCoveragePolicy.policyVersion,
              coverage_target_met: firstPassShortfalls.length === 0,
              shortfall_photo_indices: firstPassShortfalls,
              repair_recommended: repairCandidates.length > 0,
            },
            _coverage_v2: {
              enabled: true,
              policy_version: multiPhotoCoveragePolicy.policyVersion,
              target_findings_per_photo_min: multiPhotoCoveragePolicy.targetMin,
              target_findings_per_photo_max: multiPhotoCoveragePolicy.targetMax,
              target_findings_total_max: multiPhotoCoveragePolicy.totalMax,
              repair_enabled: multiPhotoCoveragePolicy.repairEnabled,
              repair_candidate_photo_indices: repairCandidates,
            },
          };
          inputAudit.coverage_repair_job_enqueued = true;
          inputAudit.coverage_repair_used = false;
          inputAudit.repair_job_used = false;
          inputAudit.coverage_target_met = firstPassShortfalls.length === 0;
          inputAudit.shortfall_photo_indices = firstPassShortfalls;
          await updateOwnedAnalysis({
            status: "queued",
            status_message:
              `Analiz kapsamı ikinci taramaya alındı. Destek kodu: ${supportID}`,
            raw_ai_response: {
              ...interimResult,
              _input_audit: inputAudit,
            },
          });
          await enqueueCoverageRepairJob({
            supabase,
            body,
            userID: user.id,
            analysisID,
            requestID,
            supportID,
            repairPhotoIndices: repairCandidates,
          });
          triggerAnalysisWorker({
            supabaseUrl,
            serviceRoleKey,
            requestID,
            supportID,
          });
          return new Response(
            JSON.stringify({
              ok: true,
              status: "repair_queued",
              analysis_id: analysisID,
              repair_photo_indices: repairCandidates,
              request_id: requestID,
              support_id: supportID,
            }),
            {
              status: 202,
              headers: { "Content-Type": "application/json" },
            },
          );
        } catch (repairQueueError) {
          inputAudit.coverage_repair_queue_error = safeLogError(
            repairQueueError,
          );
          console.warn(
            "Coverage repair enqueue failed; completing first pass",
            JSON.stringify({
              request_id: requestID,
              support_id: supportID,
              analysis_id: analysisID,
              error: safeLogError(repairQueueError),
            }),
          );
        }
      } else if (jobMode !== "repair") {
        inputAudit.coverage_repair_used = false;
      }

      for (const record of coverageRecords) {
        record.coverage_gap_reason = normalizeCoverageGapReason(
          record.coverage_status,
          record.coverage_gap_reason,
          record.findings.length,
          multiPhotoCoveragePolicy.targetMin,
          record.record_missing,
        );
      }
      const coverageHazards = mergeDuplicateCoverageHazards(
        coverageRecords.flatMap((record) => record.findings),
        multiPhotoCoveragePolicy.photoCount,
        multiPhotoCoveragePolicy.totalMax,
      );
      const finalShortfalls = coverageRepairCandidates(
        coverageRecords,
        multiPhotoCoveragePolicy,
      );
      geminiResult = {
        ...geminiResult,
        hazards: coverageHazards,
        photo_summaries: buildPhotoSummariesFromCoverage(
          coverageRecords,
          multiPhotoCoveragePolicy,
        ),
        analysis_quality: {
          photo_policy_version: multiPhotoCoveragePolicy.policyVersion,
          coverage_target_met: finalShortfalls.length === 0,
          shortfall_photo_indices: finalShortfalls,
          repair_recommended: repairCandidates.length > 0,
        },
        _coverage_v2: {
          enabled: true,
          policy_version: multiPhotoCoveragePolicy.policyVersion,
          target_findings_per_photo_min: multiPhotoCoveragePolicy.targetMin,
          target_findings_per_photo_max: multiPhotoCoveragePolicy.targetMax,
          target_findings_total_max: multiPhotoCoveragePolicy.totalMax,
          repair_enabled: multiPhotoCoveragePolicy.repairEnabled,
          repair_candidate_photo_indices: repairCandidates,
          post_merge_shortfall_photo_indices: finalShortfalls,
        },
      };
      inputAudit.coverage_target_met = finalShortfalls.length === 0;
      inputAudit.post_merge_shortfall_photo_indices = finalShortfalls;
      inputAudit.shortfall_photo_indices = finalShortfalls;
      inputAudit.coverage_gap_reason = finalShortfalls.length > 0
        ? "coverage_target_shortfall"
        : null;
    }
  }

  const rawHazards = Array.isArray(geminiResult.hazards)
    ? geminiResult.hazards
    : [];
  const reportLanguageSafeHazards = imageBase64Parts.length > 0
    ? rawHazards.map((hazard: unknown) =>
      sanitizePhotoHazardTextFields(
        hazard && typeof hazard === "object"
          ? hazard as Record<string, unknown>
          : {},
      )
    )
    : rawHazards;
  const confidenceFilteredHazards = reportLanguageSafeHazards
    .map((hazard: unknown) =>
      hazard && typeof hazard === "object"
        ? sanitizePhotoHazardTextFields(hazard as Record<string, unknown>)
        : hazard
    )
    .filter((hazard: unknown) => {
      if (!hazard || typeof hazard !== "object") return false;
      return hazardConfidence(hazard as Record<string, unknown>) >= 0.5;
    });
  inputAudit.rejected_low_confidence_findings_count = Math.max(
    0,
    reportLanguageSafeHazards.length - confidenceFilteredHazards.length,
  );

  const maxHazards = analysisFindingPolicy?.maxFindingsTotal ??
    PLAN_LIMITS[planTier].maxHazards;
  const hazards = analysisFindingPolicy
    ? enforceFindingBudget(
      confidenceFilteredHazards,
      analysisFindingPolicy.photoCount,
      analysisFindingPolicy.maxFindingsPerPhoto,
      analysisFindingPolicy.maxFindingsTotal,
    )
    : maxHazards
    ? confidenceFilteredHazards.slice(0, maxHazards) as Array<
      Record<string, unknown>
    >
    : confidenceFilteredHazards as Array<Record<string, unknown>>;
  const hiddenOrRejectedFindingsCount = Math.max(
    0,
    reportLanguageSafeHazards.length - hazards.length,
  );
  let totalScoreFK = 0, totalScoreM5 = 0;
  let highestBandFK: "low" | "medium" | "high" | "critical" = "low";
  let highestBandM5: "low" | "medium" | "high" | "critical" = "low";

  // findings rows — fk_score / m5_score GENERATED, INSERT ETME.
  // user_id REQUIRED, set et.
  // deno-lint-ignore no-explicit-any
  const findingRows = hazards.map((h: any, i: number) => {
    const recommendedMeasures = normalizeRecommendedMeasures(h);
    const sourcePhotoIndices = normalizeSourcePhotoIndices(
      h.source_photo_indices,
      imageBase64Parts.length,
    );
    const perPhotoObservations = normalizePerPhotoObservations(
      h.per_photo_observations,
      sourcePhotoIndices,
    );
    const confidence = hazardConfidence(h);
    const needsFieldVerification = Boolean(h.needs_field_verification) ||
      (confidence >= 0.5 && confidence < 0.7);
    const { fkP, fkF, fkS, m5P, m5S } = calibratedRiskInputs(h);
    const fkSc = fkP * fkF * fkS;
    const fkB = fkBand(fkSc);
    const m5Sc = m5P * m5S;
    const m5B = m5Band(m5Sc);
    totalScoreFK += fkSc;
    totalScoreM5 += m5Sc;
    if (BAND_RANK[fkB] > BAND_RANK[highestBandFK]) highestBandFK = fkB;
    if (BAND_RANK[m5B] > BAND_RANK[highestBandM5]) highestBandM5 = m5B;
    return {
      analysis_id: analysisID,
      user_id: user.id,
      ordinal: i + 1,
      title: h.title,
      category: h.category ?? "",
      description: composeFindingDescription(h),
      recommended_action: recommendedMeasures[0]?.text ?? "",
      recommended_measures: recommendedMeasures,
      references_text: planTier !== "free" ? h.references ?? "" : "",
      root_cause_text: h.root_cause ?? "",
      confidence,
      needs_field_verification: needsFieldVerification,
      origin: "ai",
      ai_original_snapshot: {
        ...h,
        needs_field_verification: needsFieldVerification,
      },
      source_photo_indices: sourcePhotoIndices,
      source_photo_observations: perPhotoObservations,
      finding_budget_policy: analysisFindingPolicy,
      ai_confidence: confidence,
      fk_probability: fkP,
      fk_frequency: fkF,
      fk_severity: fkS,
      fk_band: fkB,
      m5_probability: m5P,
      m5_severity: m5S,
      m5_band: m5B,
      display_order: i + 1,
    };
  });

  if (findingRows.length > 0) {
    const { error: findingsErr } = await supabase.from("findings").insert(
      findingRows,
    );
    if (findingsErr) {
      console.error(
        "Findings insert error",
        JSON.stringify({
          request_id: requestID,
          support_id: supportID,
          analysis_id: analysisID,
          error: safeLogError(findingsErr),
        }),
      );
      await releaseAnalysisQuota(supabase, analysisID, user.id);
      await updateOwnedAnalysis({
        status: "failed",
        status_message: `Findings DB hatası. Destek kodu: ${supportID}`,
      });
      return errorResponse(500, "Bulgular kaydedilemedi.", {
        code: "findings_insert_failed",
        requestID,
        supportID,
      });
    }
  }

  if (imageBase64Parts.length > 0) {
    try {
      const rawPhotoSummaries: unknown[] =
        Array.isArray(geminiResult.photo_summaries)
          ? geminiResult.photo_summaries
          : [];
      const { data: photoRows } = await supabase
        .from("photos")
        .select("id,sequence_index,storage_path")
        .eq("analysis_id", analysisID)
        .eq("user_id", user.id);
      const photosBySequence = new Map<number, { id: string }>();
      for (const row of photoRows ?? []) {
        const sequence = Number(row.sequence_index) ||
          Number(String(row.storage_path ?? "").match(/\/p(\d+)\./)?.[1] ?? 0);
        if (sequence > 0) {
          photosBySequence.set(sequence, { id: String(row.id) });
        }
      }
      const summaries = rawPhotoSummaries
        .slice(0, imageBase64Parts.length)
        .map((item: unknown): Record<string, unknown> | null => {
          if (!item || typeof item !== "object") return null;
          const record = item as Record<string, unknown>;
          const photoIndex = Math.round(Number(record.photo_index));
          if (
            !Number.isFinite(photoIndex) || photoIndex < 1 ||
            photoIndex > imageBase64Parts.length
          ) {
            return null;
          }
          return {
            analysis_id: analysisID,
            user_id: user.id,
            photo_id: photosBySequence.get(photoIndex)?.id ?? null,
            photo_sequence_index: photoIndex,
            scene_summary: stripPhotoMarkerReferences(record.scene_summary)
              .slice(0, 1200),
            candidate_findings_count: Math.max(
              0,
              Math.round(Number(record.candidate_findings_count ?? 0)),
            ),
            generated_findings_count: findingRows.filter((row) =>
              Array.isArray(row.source_photo_indices) &&
              row.source_photo_indices.includes(photoIndex)
            ).length,
            highest_risk_level:
              safeText(record.highest_risk_level).slice(0, 40) ||
              null,
            ai_confidence: typeof record.ai_confidence === "number"
              ? Math.max(0, Math.min(1, record.ai_confidence))
              : null,
            coverage_status: safeText(record.coverage_status).slice(0, 40) ||
              null,
            coverage_gap_reason:
              stripPhotoMarkerReferences(record.coverage_gap_reason).slice(
                0,
                500,
              ) || null,
            target_findings_min: record.target_findings_min == null
              ? null
              : Math.max(
                0,
                Math.round(Number(record.target_findings_min)),
              ),
            target_findings_max: record.target_findings_max == null
              ? null
              : Math.max(
                0,
                Math.round(Number(record.target_findings_max)),
              ),
            raw_summary: record,
          };
        })
        .filter((item): item is Record<string, unknown> => item !== null);
      if (summaries.length > 0) {
        await supabase
          .from("analysis_photo_summaries")
          .upsert(summaries, {
            onConflict: "analysis_id,photo_sequence_index",
          });
      }
    } catch (summaryError) {
      console.warn(
        "Photo summaries persist skipped",
        JSON.stringify({
          request_id: requestID,
          support_id: supportID,
          analysis_id: analysisID,
          error: safeLogError(summaryError),
        }),
      );
    }
  }

  const safeAISummary = imageBase64Parts.length > 0
    ? stripPhotoMarkerReferences(geminiResult.ai_summary)
    : geminiResult.ai_summary;

  await updateOwnedAnalysis({
    status: "completed",
    status_message: `${
      providerDisplayName(providerUsed)
    } ${modelUsed} · ${imageBase64Parts.length} foto · ${supportID}`,
    completed_at: new Date().toISOString(),
    ai_summary: safeAISummary,
    total_score_fk: totalScoreFK,
    total_score_m5: totalScoreM5,
    highest_band_fk: highestBandFK,
    highest_band_m5: highestBandM5,
    finding_count: findingRows.length,
    generated_findings_count: findingRows.length,
    visible_findings_count: findingRows.length,
    hidden_or_rejected_findings_count: hiddenOrRejectedFindingsCount,
    max_findings_per_photo: analysisFindingPolicy?.maxFindingsPerPhoto ??
      photoCapabilities.maxFindingsPerPhoto,
    max_findings_total: analysisFindingPolicy?.maxFindingsTotal ?? maxHazards ??
      null,
    raw_ai_response: {
      ...geminiResult,
      ai_summary: safeAISummary,
      _input_audit: inputAudit,
    },
    ai_models_used: [modelUsed],
  });

  await completeAnalysisQuota(supabase, analysisID, user.id);

  if (isWorkerInvocation) {
    await sendAnalysisCompletePush({
      supabase,
      supabaseUrl,
      serviceRoleKey,
      userID: user.id,
      analysisID,
      requestID,
      supportID,
    });
  }

  await logUsage(supabase, {
    analysis_id: analysisID,
    user_id: user.id,
    provider: providerUsed,
    model: modelUsed,
    tokens_in: inputTokens,
    tokens_out: outputTokens,
    duration_ms: Date.now() - startMs,
    error: null,
    user_plan: planTier,
    quality_tier: qualityTier,
    ai_execution_route: aiExecutionRoute,
    request_id: requestID,
    support_id: supportID,
    error_code: null,
    http_status: 200,
    fallback_source: aiFallbackSource ?? ([
      modelUsed !== model ? modelUsed : null,
      apiKeyAlias && apiKeyAlias !== primaryGeminiAlias ? apiKeyAlias : null,
    ].filter(Boolean).join(" -> ") || null),
    api_key_alias: apiKeyAlias,
    attempt_count: attemptCount || null,
    prompt_version: PROMPT_VERSION,
    personalization_version: PERSONALIZATION_VERSION,
    context_hash: contextHash,
    cached_tokens: cachedTokens,
    thoughts_tokens: thoughtsTokens,
    total_tokens: totalTokens,
  });

  return new Response(
    JSON.stringify({
      ok: true,
      finding_count: findingRows.length,
      request_id: requestID,
      support_id: supportID,
    }),
    { headers: { "Content-Type": "application/json" } },
  );
});
