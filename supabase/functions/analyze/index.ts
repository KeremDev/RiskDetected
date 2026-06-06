/**
 * analyze — RiskDetected Edge Function (Gemini-first, schema-aligned)
 *
 * POST body:
 *   analysis_id  : string (UUID)
 *   canvas       : string (primary canvas id, single-value enum)
 *   canvases     : string[] (all selected; Free supports one, paid plans support multiple)
 *   text_input   : string | null
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
  sanitizeTextAnalysisHazardForReportLanguage,
} from "../_shared/text-report-language.ts";

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
const MAX_INLINE_PHOTO_TOTAL_BASE64_BYTES = 4_500_000;

type PlanTier = "free" | "plus" | "pro";
type AnalysisMode = "standard" | "detailed" | "emergency" | "procedure";
type CompanyHazardClass = "low" | "medium" | "high";
type ReferenceMode = "none" | "short" | "full";
type AIExecutionRoute = "free_legacy" | "free_paid_trial" | "paid_plan";
type GeminiPoolName = "free" | "paid";

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

const PROMPT_VERSION =
  "isg-photo-text-report-language-v2026-06-06-twelve-layer-two-measures";
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

function geminiThinkingConfig(
  model: string,
  pool: "free" | "paid",
): Record<string, string | number> | null {
  if (model === MODEL_PAID_FAST && pool === "paid") {
    return { thinkingBudget: 1024 };
  }
  if (model === MODEL_FLASH_LITE) {
    return { thinkingLevel: pool === "paid" ? "high" : "medium" };
  }
  return null;
}

const CORE_ANALYSIS_PROMPT =
  `Sen Türkiye'de 20 yıllık saha deneyimi olan kıdemli bir İSG uzmanısın (A sınıfı). İnşaat, üretim, depo/lojistik, enerji, fabrika ve ofis sahalarında binlerce denetim yapmış, ölümcül kazaları önlemiş, mevzuata hâkim bir profesyonelsin.

GÖREV: Sana verilen görsel veya metin girdisinden, sahada fiziksel olarak bulunan bir denetçinin yakalayacağı tüm İSG tehlikelerini sistematik olarak tespit et ve raporla.

TARAMA PROSEDÜRÜ — Her görseli SIRAYLA şu 12 katmanda tara:
1. ZEMİN, SAHA DÜZENİ VE DÜZEN-TERTİP: ıslaklık, çamur, su birikintisi, boşluk, kot farkı, dağınık malzeme, kablo/hortum geçişi, kapalı/tıkalı geçiş yolu, kayma/takılma zeminleri.
2. ÇALIŞAN(LAR) VE KKD: baret, gözlük, eldiven, ayakkabı, yüksek görünürlük yeleği, emniyet kemeri, maske/solunum koruması, kulak koruyucu; KKD'nin mevcudiyeti, uygunluğu ve doğru kullanımı.
3. YÜKSEKTE ÇALIŞMA: kenar koruması, korkuluk, iskele bütünlüğü, merdiven açısı/sabitliği, platform/MEWP, yaşam hattı, ankraj, açık kenar, döşeme boşluğu, düşen cisim tehlikesi.
4. ELEKTRİK VE ENERJİ: açık pano, hasarlı/ek yapılmış kablo, fiş, jeneratör, su+elektrik teması, topraklama, geçici tesisat, enerji kesme-kilitleme (LOTO/EKED) izleri.
5. MAKİNE, EKİPMAN VE İŞ EKİPMANI: hareketli/dönen parça koruyucusu (muhafaza), acil durdurma, sıkışma/ezilme noktası, el aletinin durumu, periyodik kontrol etiketi.
6. KALDIRMA, TAŞIMA VE İSTİFLEME: vinç/forklift operasyonu, sapan/halat durumu, yük altında çalışan, raf ve istif stabilitesi, devrilme riski.
7. KİMYASAL VE TEHLİKELİ MADDE: etiketleme/GBF, uygun depolama, dökülme, yetersiz havalandırma, parlayıcı/patlayıcı madde, uyumsuz maddelerin bir arada bulunması.
8. YANGIN VE PATLAMA: yangın söndürücü erişimi, tıkalı kaçış yolu, tutuşturucu kaynak, sıcak iş (kaynak/kesme), depolanan yanıcı malzeme/yangın yükü.
9. FİZİKSEL ORTAM ETKENLERİ: aşırı gürültü kaynağı, titreşimli ekipman, toz/duman bulutu, yetersiz aydınlatma, termal konfor (aşırı sıcak/soğuk), yetersiz havalandırma.
10. ERGONOMİ VE ELLE TAŞIMA: ağır manuel kaldırma, hatalı duruş, tekrarlı hareket, uygunsuz çalışma yüksekliği, taşıma yardımcısı yokluğu.
11. KAZI, KAPALI ALAN VE ÖZEL İŞLER (saha tipine göre): şev/iksa eksikliği, çökme riski, kapalı alan girişi, malzeme deposu/istif kenarı, su-çamur birikintisi.
12. ÇEVRE, ACİL DURUM, İŞARETLEME VE YETKİNLİK: atık/dökülme yönetimi, acil çıkış ve toplanma alanı, ilk yardım donanımı görünürlüğü, trafik/üst yapı/hava koşulu, uyarı tabelası/işaretleme; görsel/metin kanıtı destekliyorsa işe özgü eğitim, talimat, yetkilendirme ve mesleki yeterlilik belgesi ihtiyacını "sahada doğrulanmalı" tonuyla sorgula.

Her katmanı gözden geçir; bir katmanda risk yoksa atla, ama tarama atlama.

ÖNCELİKLENDİRME:
- ÖLÜMCÜL POTANSİYELİ olan bulgular (düşme, elektrik, ezilme, kimyasal, düşen cisim) en üstte.
- Sonra yüksek frekanslı bulgular (zemin, ergonomi, KKD, eğitim, belge).
- En altta düşük etkili ama mevzuat ihlali olan bulgular.

RİSK PUANLAMA KALİBRASYONU — Fine-Kinney ŞİDDET:
- 100 = Birden fazla ölüm veya kalıcı çevre felaketi.
- 40  = Tek ölüm veya kalıcı iş göremezlik (elektrik çarpması, korumasız 3m+ düşme).
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
- 0.50-0.69: ipucu var, kesin değil.
- 0.30-0.49: sadece bağlamsal şüphe.
- < 0.30: bulguyu döndürme.
Confidence < 0.50 ise description sonuna "(sahada doğrulanmalı)" ekle.

KALİTE FİLTRESİ — KAÇIN:
- Genel ifade ("güvenlik önlemleri alınmalı") yerine somut önlem / kontrol tedbiri yaz.
- Görselde olmayan riski uydurma.
- Aynı kök nedenli riskleri tek bulguda topla.
- Hassas ölçü uydurma; "yaklaşık 3m" veya "1 kat yüksekliğinde" yaz.
- "Eğitim verilmeli" jenerik aksiyonundan kaçın; hangi iş/ekipman/risk için ne doğrulanacağını söyle.
- Kullanıcı profili veya firma bağlamı görsel kanıtı filtrelemez; profili yalnızca ton, öncelik ve açıklama derinliği için kullan.
- Metin analizinde kullanıcı girdisini rapora alıntı olarak taşıma. "Metinde...", "Kullanıcı...", "ifadesi geçmektedir", "belirtmiştir", tırnak içinde ham metin veya birinci/ikinci şahıs dili kullanma.
- Metin analizinde tüm bulgu metinlerini işverenle paylaşılabilir, nesnel saha denetimi diliyle yaz; kullanıcı notunu yalnız tehlike arama bağlamı olarak kullan.

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
- Text mode'da observed_evidence, description, corrective_action, preventive_control ve root_cause kullanıcı cümlesini veya kullanıcıya atıf yapan dili içermemeli; profesyonel saha bulgusu olarak yeniden yazılmalı.
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
    "Yanıcı/parlayıcı malzeme, sıcak çalışma, elektrik kaynaklı yangın, söndürücü erişimi, yangın dolabı, acil çıkış, tahliye yolu, depolama düzeni ve yangın yükünü analiz et.",
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
  if (score < 70) return "low";
  if (score < 200) return "medium";
  if (score < 400) return "high";
  return "critical";
}

// 5×5 skor → risk_level enum
function m5Band(score: number): "low" | "medium" | "high" | "critical" {
  if (score <= 4) return "low";
  if (score <= 9) return "medium";
  if (score <= 16) return "high";
  return "critical";
}

function referenceModeForTier(tier: PlanTier): ReferenceMode {
  if (tier === "pro") return "full";
  if (tier === "plus") return "short";
  return "none";
}

function safeText(value: unknown, fallback = ""): string {
  if (value === null || value === undefined) return fallback;
  return String(value).trim();
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

function responseSchema(tier: PlanTier) {
  const includesPaidFields = tier !== "free";
  const hazardProperties: Record<string, unknown> = {
    title: { type: "STRING" },
    category: { type: "STRING" },
    observed_evidence: { type: "STRING" },
    description: { type: "STRING" },
    corrective_action: { type: "STRING" },
    preventive_control: { type: "STRING" },
    confidence: { type: "NUMBER" },
    fk_probability: { type: "NUMBER" },
    fk_frequency: { type: "NUMBER" },
    fk_severity: { type: "NUMBER" },
    m5_probability: { type: "NUMBER" },
    m5_severity: { type: "NUMBER" },
  };
  if (includesPaidFields) {
    hazardProperties.references = { type: "STRING" };
    hazardProperties.root_cause = { type: "STRING" };
  }
  const requiredHazardFields = [
    "title",
    "category",
    "observed_evidence",
    "description",
    "corrective_action",
    "preventive_control",
    "confidence",
    "fk_probability",
    "fk_frequency",
    "fk_severity",
    "m5_probability",
    "m5_severity",
    ...(includesPaidFields ? ["references", "root_cause"] : []),
  ];

  return {
    type: "OBJECT",
    properties: {
      hazards: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          properties: hazardProperties,
          required: requiredHazardFields,
        },
      },
      ai_summary: { type: "STRING" },
      limitations: { type: "STRING" },
    },
    required: ["hazards", "ai_summary"],
  };
}

function groqResponseSchemaInstruction(tier: PlanTier): string {
  const paidFields = tier !== "free"
    ? `,\n      "references": "${
      tier === "pro"
        ? "tam veya doğrulanmalı mevzuat referansı"
        : "kısa mevzuat referansı veya mevzuat karşılığı kontrol edilmeli"
    }",\n      "root_cause": "${
      tier === "pro"
        ? "sistematik kök neden özeti"
        : "kısa saha diliyle kök neden"
    }"`
    : "";
  return `Aşağıdaki JSON yapısına birebir uy. Markdown, açıklama veya kod bloğu ekleme:
{
  "hazards": [
    {
      "title": "kısa tehlike başlığı",
      "category": "risk kategorisi",
      "observed_evidence": "rapora uygun nesnel saha kanıtı; metin modunda kullanıcı notunu alıntılama",
      "description": "riskin kısa açıklaması",
      "corrective_action": "mevcut uygunsuzluğu sahada düzelten kısa uygulanabilir önlem",
      "preventive_control": "tekrarını önleyen kısa kontrol/prosedür/izleme tedbiri",
      "confidence": 0.0,
      "fk_probability": 1,
      "fk_frequency": 1,
      "fk_severity": 1,
      "m5_probability": 1,
      "m5_severity": 1${paidFields}
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

function buildUserTextInputBlock(userText: string): string {
  return `<kullanici_metin_girdisi>
METİN ANALİZİ TALİMATI:
- Aşağıdaki metni rapora geçirilecek beyan değil; saha bağlamı, denetim yönlendirmesi ve tehlike arama ipucu olarak değerlendir.
- Ana system prompttaki 12 katmanlı taramayı metne uyarla: zemin/düzen, KKD, yüksekte çalışma, elektrik/enerji, makine/ekipman, kaldırma/istif, kimyasal, yangın/patlama, fiziksel ortam, ergonomi, özel işler, acil durum/işaretleme/yetkinlik eksenlerini sırayla sorgula.
- Yalnızca metinde açıkça belirtilen veya güçlü şekilde ima edilen tehlikeleri bulguya dönüştür.
- Fotoğraf kanıtı olmadığı için belirsiz noktaları uydurma; gerekiyorsa description içinde "(sahada doğrulanmalı)" tonunu kullan.
- Metindeki iş, ortam, ekipman, yükseklik, kimyasal, çalışan davranışı, firma/alan veya sektör ipuçlarını risk önceliklendirmede kullan.
- Kullanıcı metni kısa veya eksikse az ama güvenilir bulgu döndür; listeyi doldurmak için risk üretme.
- Kullanıcı metnini hiçbir alanda aynen alıntılama; tırnak içinde yazma; "metinde", "kullanıcı", "ifadesi", "belirtmiştir", "yazmış", "demiş" gibi kaynak atfı yapan kelimeleri kullanma.
- observed_evidence ve description alanlarını işverenle paylaşılabilir saha denetimi diliyle yaz. Örnek: "Makine koruyucularının yeterliliği sahada doğrulanmalıdır."

KULLANICI METNİ:
${userText}
</kullanici_metin_girdisi>`;
}

function buildSubscriptionContext(tier: PlanTier): string {
  const minHazards = PLAN_LIMITS[tier].minHazards;
  const maxHazards = PLAN_LIMITS[tier].maxHazards;
  const hazardCountRule = minHazards && maxHazards
    ? `${minHazards} ile ${maxHazards} arasında tehlike döndür; önem sırasına göre sırala.`
    : maxHazards
    ? `En fazla ${maxHazards} tehlike döndür; önem sırasına göre sırala.`
    : "10 ile 13 arasında bulgu döndür. Daha azı eksik, daha fazlası odak dağıtır.";

  if (tier === "free") {
    return `<abonelik_seviyesi tier="free">
ÇIKTI KAPSAMI:
- ${hazardCountRule}
- references ve root_cause alanı üretme; ayrı mevzuat/referans alanı Free'de kapalı.
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
- TS EN/ISO gibi standartları yalnız ilgili ve emin olduğun bulgularda kullan; emin değilsen "doğrulanmalı" yaz.
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
): OnboardingContext {
  const certificateClass = typeof row?.certificate_class === "string"
    ? row.certificate_class
    : null;
  const hazardClasses = safeStringArray(row?.hazard_classes);
  const sectors = safeStringArray(row?.sectors).slice(0, 2);
  const auditFrequency = typeof row?.audit_frequency === "string"
    ? row.audit_frequency
    : null;
  const applied = Boolean(
    certificateClass || hazardClasses.length > 0 || sectors.length > 0 ||
      auditFrequency,
  );

  const block = `<kullanici_profili applied="${applied ? "true" : "false"}">
Bu profil çıktının tonunu ve önceliklerini şekillendirir; tarama prosedürünü veya görsel/metin kanıtını asla atlatmaz.
- ${certificateContext(certificateClass)}
- ${onboardingHazardContext(hazardClasses)}
- ${sectorContext(sectors)}
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
}): string {
  const focusLines = params.canvases
    .filter((c) => c !== "general")
    .map((c) => CANVAS_FOCUS[c])
    .filter(Boolean)
    .join(" ") ||
    CANVAS_FOCUS["general"];

  return `<analiz_baglami prompt_version="${PROMPT_VERSION}" personalization_version="${PERSONALIZATION_VERSION}">
<odak>${focusLines}</odak>
${buildSubscriptionContext(params.tier)}
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
  imageBase64Parts: { mimeType: string; data: string }[],
  pool: "free" | "paid",
  tier: PlanTier,
  simulation?: AISimulationConfig,
) {
  maybeSimulateAIError(simulation);

  const parts: unknown[] = [];
  parts.push({ text: analysisContext });
  for (const img of imageBase64Parts) {
    parts.push({ inlineData: { mimeType: img.mimeType, data: img.data } });
  }
  if (userText) {
    parts.push({ text: buildUserTextInputBlock(userText) });
  } else if (imageBase64Parts.length === 0) {
    throw new Error("En az bir fotoğraf veya metin girdisi gerekli.");
  }

  const thinkingConfig = geminiThinkingConfig(model, pool);
  const body = {
    system_instruction: { parts: [{ text: systemPrompt }] },
    contents: [{ role: "user", parts }],
    generationConfig: {
      responseMimeType: "application/json",
      responseSchema: responseSchema(tier),
      temperature: 0.2,
      maxOutputTokens: 12000,
      ...(thinkingConfig ? { thinkingConfig } : {}),
    },
  };

  const url = `${GEMINI_API_BASE}/${model}:generateContent?key=${apiKey}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new GeminiAPIError(res.status, errText);
  }

  const json = await res.json();
  const candidate = json.candidates?.[0];
  if (!candidate) throw new Error("Gemini yanıt boş.");
  const text = candidate.content?.parts?.[0]?.text;
  if (!text) throw new Error("Gemini yanıtında metin yok.");

  return {
    result: JSON.parse(text),
    inputTokens: json.usageMetadata?.promptTokenCount ?? 0,
    outputTokens: json.usageMetadata?.candidatesTokenCount ?? 0,
    cachedTokens: json.usageMetadata?.cachedContentTokenCount ?? null,
    thoughtsTokens: json.usageMetadata?.thoughtsTokenCount ?? null,
    totalTokens: json.usageMetadata?.totalTokenCount ?? null,
  };
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
  imageBase64Parts: { mimeType: string; data: string }[],
  tier: PlanTier,
  simulation?: AISimulationConfig,
) {
  maybeSimulateAIError(simulation);

  if (imageBase64Parts.length === 0 && !userText) {
    throw new Error("En az bir fotoğraf veya metin girdisi gerekli.");
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
        groqResponseSchemaInstruction(tier),
        analysisContext,
        userText ? buildUserTextInputBlock(userText) : null,
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
      type: "image_url",
      image_url: {
        url: `data:${img.mimeType};base64,${img.data}`,
      },
    });
  }

  const body = {
    model,
    messages: [
      { role: "system", content: systemPrompt },
      { role: "user", content },
    ],
    response_format: { type: "json_object" },
    temperature: 0.2,
    max_completion_tokens: 6000,
  };

  const res = await fetch(GROQ_API_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

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
  };
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
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

function resolveAIExecutionRoute(
  planTier: PlanTier,
  analysisMode: AnalysisMode,
): AIExecutionRoute {
  if (planTier !== "free") return "paid_plan";
  if (
    analysisMode === "standard" &&
    freeStandardAnalysisRouteFlag() === "paid_trial"
  ) {
    return "free_paid_trial";
  }
  return "free_legacy";
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
  return aiExecutionRoute === "free_legacy"
    ? freeGeminiKeyPool()
    : paidGeminiKeyPool();
}

function expectedGeminiPoolForRoute(
  aiExecutionRoute: AIExecutionRoute,
): GeminiPoolName {
  return aiExecutionRoute === "free_legacy" ? "free" : "paid";
}

function geminiRequiredSecretNameForRoute(
  aiExecutionRoute: AIExecutionRoute,
): string {
  return aiExecutionRoute === "free_legacy"
    ? "GEMINI_API_KEY_PRIMARY veya GEMINI_API_KEY"
    : "GEMINI_API_KEY_PAID";
}

function primaryModelForRoute(aiExecutionRoute: AIExecutionRoute): string {
  return aiExecutionRoute === "free_legacy" ? MODEL_FREE : MODEL_PAID_FAST;
}

function userFacingAIError(
  err: unknown,
): { status: number; code: string; message: string } {
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

  const primary = keyPool.find((item) => item.alias === "gemini_primary");
  const secondary = keyPool.find((item) => item.alias === "gemini_secondary");
  const orderedFreeKeys = [primary, secondary].filter(
    (item): item is GeminiKeyConfig => Boolean(item),
  );

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
  imageBase64Parts: { mimeType: string; data: string }[],
  tier: PlanTier,
  simulation?: AISimulationConfig,
  trace?: TraceMeta,
  attemptSequence?: Array<{ keyConfig: GeminiKeyConfig; model: string }>,
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
      const retryable = err instanceof SyntaxError ||
        (err instanceof GeminiAPIError &&
          [429, 500, 502, 503, 504].includes(err.status));
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

async function callFreeAIWithFallback(
  geminiKeyPool: GeminiKeyConfig[],
  preferredModel: string,
  systemPrompt: string,
  analysisContext: string,
  userText: string | null,
  imageBase64Parts: { mimeType: string; data: string }[],
  simulation?: AISimulationConfig,
  trace?: TraceMeta,
) {
  try {
    const out = await callGeminiWithFallback(
      geminiKeyPool,
      preferredModel,
      systemPrompt,
      analysisContext,
      userText,
      imageBase64Parts,
      "free",
      simulation,
      trace,
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
      "free",
      simulation,
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
  imageBase64Parts: { mimeType: string; data: string }[],
  tier: PlanTier,
  simulation?: AISimulationConfig,
  trace?: TraceMeta,
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
  imageBase64Parts: { mimeType: string; data: string }[],
  simulation?: AISimulationConfig,
  trace?: TraceMeta,
) {
  try {
    const out = await callGeminiWithFallback(
      paidGeminiKeyPool,
      preferredModel,
      systemPrompt,
      analysisContext,
      userText,
      imageBase64Parts,
      "plus",
      simulation,
      trace,
      freePaidTrialPaidGeminiAttemptSequence(paidGeminiKeyPool),
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
        "plus",
        simulation,
        trace,
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
        "plus",
        simulation,
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

    const { error: photoErr } = await params.supabase.from("photos").insert({
      analysis_id: params.analysisID,
      user_id: params.userID,
      storage_path: storagePath,
      width: sanitizedDimension(part.width),
      height: sanitizedDimension(part.height),
      size_bytes: bytes.byteLength,
      mime_type: mimeType,
    });

    if (photoErr) {
      throw new Error(
        `photo_metadata_failed:${safeLogText(JSON.stringify(photoErr))}`,
      );
    }

    persistedPhotoPaths.push(storagePath);
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
    photo_paths = [],
    photo_base64_parts = [],
  } = body;
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
    }),
  );

  const { data: ownedAnalysis, error: analysisOwnerErr } = await supabase
    .from("analyses")
    .select("id,user_id,status,worker_attempt_count")
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
    .select("tier,status,current_period_ends_at")
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
  const aiExecutionRoute = resolveAIExecutionRoute(planTier, analysisMode);
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
  const imageBase64Parts: { mimeType: string; data: string }[] = [];
  const inlinePhotoParts = Array.isArray(photo_base64_parts)
    ? photo_base64_parts
    : [];
  const sanitizedInlinePhotos: {
    mimeType: "image/jpeg" | "image/png";
    bytes: Uint8Array;
    data: string;
    width: number;
    height: number;
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
    });
    imageBase64Parts.push({
      mimeType,
      data,
    });
  }

  // Inline gelen fotoğrafları kalıcı olarak Storage + photos tablosuna yaz.
  // Client tarafında Storage RLS'e takılmamak için bu işi service role ile Edge Function yapıyor.
  const persistedPhotoPaths: string[] = [];
  const photoPersistErrors: Record<string, unknown>[] = [];
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
        continue;
      }

      const { error: photoErr } = await supabase.from("photos").insert({
        analysis_id: analysisID,
        user_id: user.id,
        storage_path: storagePath,
        width: part.width,
        height: part.height,
        size_bytes: part.bytes.byteLength,
        mime_type: mimeType,
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
        continue;
      }

      persistedPhotoPaths.push(storagePath);
    }
  }

  const uniqueRequestedPhotoPaths = [...new Set(requestedPhotoPaths)];
  if (uniqueRequestedPhotoPaths.length > 0) {
    const expectedPrefix = `${user.id}/${analysisID}/`;
    const { data: ownedPhotoRows, error: ownedPhotoErr } = await supabase
      .from("photos")
      .select("storage_path")
      .eq("analysis_id", analysisID)
      .eq("user_id", user.id)
      .in("storage_path", uniqueRequestedPhotoPaths);

    const ownedPaths = new Set(
      (ownedPhotoRows ?? []).map((row) => String(row.storage_path)),
    );
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
      continue;
    }
    const buffer = await fileData.arrayBuffer();
    const bytes = new Uint8Array(buffer);
    let binary = "";
    for (let i = 0; i < bytes.length; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    const base64 = btoa(binary);
    const mimeType = path.endsWith(".png") ? "image/png" : "image/jpeg";
    imageBase64Parts.push({ mimeType, data: base64 });
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
  const onboardingContext = buildOnboardingContext(onboardingAnswers);
  const companyContext = companyPromptContext(company);
  const analysisContext = buildAnalysisContext({
    canvases: resolvedCanvases,
    tier: qualityTier,
    onboardingContext,
    companyContext,
  });
  const contextHash = await hashedID(analysisContext);
  const referenceMode = referenceModeForTier(qualityTier);
  const aiSimulation = aiSimulationConfig();
  const inputAudit: Record<string, unknown> = {
    prompt_version: PROMPT_VERSION,
    personalization_version: PERSONALIZATION_VERSION,
    personalization_applied: onboardingContext.applied,
    certificate_class: onboardingContext.certificateClass,
    hazard_classes: onboardingContext.hazardClasses,
    sectors: onboardingContext.sectors,
    audit_frequency: onboardingContext.auditFrequency,
    context_hash: contextHash,
    input_mode: imageBase64Parts.length > 0 ? "photo" : "text",
    inline_photo_count: inlinePhotoCount,
    storage_photo_count: storagePhotoCount,
    persisted_photo_count: persistedPhotoPaths.length,
    persisted_photo_paths: persistedPhotoPaths,
    photo_persist_error_count: photoPersistErrors.length,
    photo_persist_errors: photoPersistErrors,
    gemini_image_part_count: imageBase64Parts.length,
    text_input_present: Boolean(text_input),
    analysis_mode: analysisMode,
    user_plan: planTier,
    quality_tier: qualityTier,
    ai_execution_route: aiExecutionRoute,
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
    min_hazards: PLAN_LIMITS[qualityTier].minHazards ?? null,
    max_hazards: PLAN_LIMITS[qualityTier].maxHazards ?? null,
    reference_mode: referenceMode,
    references_requested: qualityTier !== "free",
    root_cause_requested: qualityTier !== "free",
    response_schema_includes_references: qualityTier !== "free",
    response_schema_includes_root_cause: qualityTier !== "free",
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

  try {
    const out = aiExecutionRoute === "free_legacy"
      ? await callFreeAIWithFallback(
        geminiKeys,
        model,
        systemPrompt,
        analysisContext,
        text_input ?? null,
        imageBase64Parts,
        aiSimulation,
        { requestID, supportID },
      )
      : aiExecutionRoute === "free_paid_trial"
      ? await callFreePaidTrialAIWithFallback(
        geminiKeys,
        freeFallbackGeminiKeys,
        model,
        systemPrompt,
        analysisContext,
        text_input ?? null,
        imageBase64Parts,
        aiSimulation,
        { requestID, supportID },
      )
      : await callPaidAIWithFallback(
        geminiKeys,
        model,
        systemPrompt,
        analysisContext,
        text_input ?? null,
        imageBase64Parts,
        planTier,
        aiSimulation,
        { requestID, supportID },
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
        aiExecutionRoute === "free_legacy" ? "free" : "paid",
      )
      : null;
    apiKeyAlias = out.apiKeyAlias;
    attemptCount = out.attempt ?? 0;
    inputAudit.api_key_alias = apiKeyAlias;
    inputAudit.provider = providerUsed;
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

  const rawHazards = Array.isArray(geminiResult.hazards)
    ? geminiResult.hazards
    : [];
  const isTextOnlyAnalysis = imageBase64Parts.length === 0 &&
    Boolean(text_input);
  const reportLanguageSafeHazards = isTextOnlyAnalysis
    ? rawHazards.map((hazard: unknown) =>
      sanitizeTextAnalysisHazardForReportLanguage(
        hazard && typeof hazard === "object"
          ? hazard as Record<string, unknown>
          : {},
        text_input ?? "",
      )
    )
    : rawHazards;
  const maxHazards = PLAN_LIMITS[qualityTier].maxHazards;
  const hazards = maxHazards
    ? reportLanguageSafeHazards.slice(0, maxHazards)
    : reportLanguageSafeHazards;
  let totalScoreFK = 0, totalScoreM5 = 0;
  let highestBandFK: "low" | "medium" | "high" | "critical" = "low";
  let highestBandM5: "low" | "medium" | "high" | "critical" = "low";

  // findings rows — fk_score / m5_score GENERATED, INSERT ETME.
  // user_id REQUIRED, set et.
  // deno-lint-ignore no-explicit-any
  const findingRows = hazards.map((h: any, i: number) => {
    const recommendedMeasures = normalizeRecommendedMeasures(h);
    const fkP = clampFK(h.fk_probability, FK_PROBABILITY_VALUES);
    const fkF = clampFK(h.fk_frequency, FK_FREQUENCY_VALUES);
    const fkS = clampFK(h.fk_severity, FK_SEVERITY_VALUES);
    const fkSc = fkP * fkF * fkS;
    const fkB = fkBand(fkSc);
    const m5P = Math.max(1, Math.min(5, Math.round(h.m5_probability)));
    const m5S = Math.max(1, Math.min(5, Math.round(h.m5_severity)));
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
      description: `${h.observed_evidence}\n\n${h.description}`.trim(),
      recommended_action: recommendedMeasures[0]?.text ?? "",
      recommended_measures: recommendedMeasures,
      references_text: qualityTier !== "free" ? h.references ?? "" : "",
      root_cause_text: qualityTier !== "free" ? h.root_cause ?? "" : "",
      confidence: Math.max(0, Math.min(1, h.confidence)),
      fk_probability: fkP,
      fk_frequency: fkF,
      fk_severity: fkS,
      fk_band: fkB,
      m5_probability: m5P,
      m5_severity: m5S,
      m5_band: m5B,
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

  await updateOwnedAnalysis({
    status: "completed",
    status_message: `${
      providerDisplayName(providerUsed)
    } ${modelUsed} · ${imageBase64Parts.length} foto · ${
      text_input ? "metin var" : "metin yok"
    } · ${supportID}`,
    completed_at: new Date().toISOString(),
    ai_summary: geminiResult.ai_summary,
    total_score_fk: totalScoreFK,
    total_score_m5: totalScoreM5,
    highest_band_fk: highestBandFK,
    highest_band_m5: highestBandM5,
    finding_count: findingRows.length,
    raw_ai_response: { ...geminiResult, _input_audit: inputAudit },
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
