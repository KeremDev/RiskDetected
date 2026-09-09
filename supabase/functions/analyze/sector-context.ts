export type AnalysisSectorId =
  | "general"
  | "construction"
  | "manufacturing"
  | "mining"
  | "energy"
  | "office"
  | "logistics_warehouse"
  | "chemical_laboratory"
  | "healthcare"
  | "food_production"
  | "agriculture_livestock"
  | "retail"
  | "municipal_field_services"
  | "education"
  | "hospitality";

export const ACTIVE_ANALYSIS_SECTOR_PROMPT_VERSION = "sector-profile-v2";

export const ANALYSIS_SECTOR_ALLOWLIST: readonly AnalysisSectorId[] = [
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

export type ActiveSectorResolution =
  | {
    ok: true;
    sector: AnalysisSectorId | null;
    source: string | null;
    promptVersion: string | null;
    shouldBackfill: boolean;
    backfillPatch: {
      analysis_sector?: AnalysisSectorId;
      analysis_sector_source?: string;
      analysis_sector_prompt_version?: string;
    };
  }
  | {
    ok: false;
    status: 400 | 409;
    code: "invalid_analysis_sector" | "sector_mismatch";
    message: string;
    requestedSector: string | null;
    persistedSector: AnalysisSectorId | null;
  };

type ActiveSectorBackfillPatch = Extract<
  ActiveSectorResolution,
  { ok: true }
>["backfillPatch"];

const SECTOR_LABELS_TR: Record<AnalysisSectorId, string> = {
  general: "Genel İSG",
  construction: "İnşaat",
  manufacturing: "İmalat / Fabrika",
  mining: "Maden",
  energy: "Enerji",
  office: "Ofis",
  logistics_warehouse: "Depo / Lojistik",
  chemical_laboratory: "Kimya / Laboratuvar",
  healthcare: "Sağlık / Hastane",
  food_production: "Gıda Üretimi",
  agriculture_livestock: "Tarım / Hayvancılık",
  retail: "Perakende / Mağaza",
  municipal_field_services: "Belediye / Kamu Saha İşleri",
  education: "Eğitim Kurumu",
  hospitality: "Otel / Konaklama",
};

const SECTOR_GUIDANCE_TR: Partial<Record<AnalysisSectorId, string>> = {
  construction: `SEKTÖR REHBERİ — İNŞAAT

Bu analizde özellikle şu risk ailelerini sektör bağlamında değerlendir:
- Yüksekte çalışma, iskele, merdiven, platform ve kenar koruma.
- Düşen cisim, malzeme istifleme, saha trafiği ve geçiş yolları.
- Kazı, geçici elektrik, kaldırma operasyonları ve iş ekipmanı kullanımı.
- KKD uygunluğu: baret, emniyet kemeri, reflektif yelek, iş ayakkabısı, göz/yüz koruma.
- Kontrol önerilerini şantiye uygulanabilirliğiyle yaz: toplu koruma, bariyerleme, işaretleme, yetkilendirme, günlük kontrol ve saha amiri sorumluluğu.`,
  manufacturing: `SEKTÖR REHBERİ — İMALAT / FABRİKA

Bu analizde özellikle şu risk ailelerini sektör bağlamında değerlendir:
- Makine koruyucuları, hareketli parçalar, sıkışma/ezilme/nokta operasyon riskleri.
- Enerji izolasyonu, bakım-onarım, LOTO ihtiyacı ve yetkisiz müdahale.
- Forklift/yaya ayrımı, malzeme istifleme, üretim hattı düzeni.
- Gürültü, ergonomi, kimyasal temas, yangın yükü ve acil çıkış erişimi.
- Önerileri üretim sürekliliğini bozmayacak ama riski azaltacak mühendislik ve idari kontrollerle yaz.`,
  mining: `SEKTÖR REHBERİ — MADEN

Bu analizde özellikle şu risk ailelerini sektör bağlamında değerlendir:
- Göçük, kaya düşmesi, tahkimat, havalandırma ve gaz/toz maruziyeti.
- Patlayıcı ortam, ekipman trafiği, yeraltı/yerüstü çalışma ayrımı.
- Acil kaçış, iletişim, aydınlatma, kurtarma ve yetkilendirme.
- Ağır ekipman etkileşimi, görüş alanı, geri manevra ve yaya ayrımı.
- Yüksek sonuç şiddeti potansiyelini dikkatle değerlendir; ancak görünmeyen riskleri kesin varmış gibi yazma.`,
  energy: `SEKTÖR REHBERİ — ENERJİ

Bu analizde özellikle şu risk ailelerini sektör bağlamında değerlendir:
- Elektrik arkı, yüksek gerilim, pano/trafo/jeneratör çevresi ve enerji izolasyonu.
- Yetkisiz erişim, kilitleme/etiketleme, topraklama, uyarı işaretleri.
- Yüksekte çalışma, bakım operasyonları, yangın ve acil müdahale hazırlığı.
- Enerji kesme, doğrulama, bariyerleme, izinli çalışma ve yetkin personel vurgusu yap.`,
  office: `SEKTÖR REHBERİ — OFİS

Bu analizde özellikle şu risk ailelerini sektör bağlamında değerlendir:
- Ergonomi, ekranlı araçlarla çalışma, kablo/zemin kaynaklı takılma-düşme riskleri.
- Elektrik prizleri, yangın söndürücü erişimi, acil çıkış ve yönlendirme.
- Raf/dolap sabitleme, temizlik-düzen, aydınlatma ve psikososyal risk belirtileri.
- Önerileri düşük maliyetli, hızlı uygulanabilir ve ofis operasyonuna uygun yaz.`,
  logistics_warehouse: `SEKTÖR REHBERİ — DEPO / LOJİSTİK

Bu analizde özellikle şu risk ailelerini sektör bağlamında değerlendir:
- Forklift, transpalet, yaya yolları, kör noktalar ve araç-yaya ayrımı.
- Raf sistemleri, yük istif yüksekliği, düşen cisim ve devrilme riski.
- Yükleme-boşaltma rampaları, kapılar, zemin durumu ve işaretleme.
- Trafik planı, hız sınırı, bariyer, ayna, zemin çizgisi, yük sabitleme ve operatör yetkinliği.
- Önerileri depo operasyonunu aksatmadan uygulanabilir kontrol tedbirleriyle yaz.`,
  chemical_laboratory: `SEKTÖR REHBERİ — KİMYA / LABORATUVAR

Bu analizde özellikle şu risk ailelerini sektör bağlamında değerlendir:
- Kimyasal etiketleme, SDS erişimi, uyumsuz depolama ve dökülme kontrolü.
- Havalandırma, göz duşu/acil duş, yangın/patlama ve kişisel koruyucu donanım.
- Atık yönetimi, kapalı kap kullanımı ve maruziyet kontrolü.
- Görsel kanıt yoksa kimyasal türü, konsantrasyon veya maruziyet seviyesini uydurma.`,
  healthcare: `SEKTÖR REHBERİ — SAĞLIK / HASTANE

Bu analizde özellikle şu risk ailelerini sektör bağlamında değerlendir:
- Biyolojik risk, kesici-delici alet, atık ayrımı ve enfeksiyon kontrolü.
- Ergonomi, hasta taşıma, kayma-düşme, kimyasal dezenfektan maruziyeti.
- Acil müdahale, yangın güvenliği, işaretleme ve yetkisiz erişim.
- Önerileri klinik iş akışını aksatmadan uygulanabilir kontrol tedbirleriyle yaz.`,
  food_production: `SEKTÖR REHBERİ — GIDA ÜRETİMİ

Bu analizde özellikle şu risk ailelerini sektör bağlamında değerlendir:
- Kaygan zemin, sıcak yüzey/sıvı, kesici ekipman, makine koruyucuları ve hijyen alan ayrımı.
- Kimyasal temizlik maddeleri, soğuk ortam, ergonomi ve elle taşıma.
- Yangın, acil çıkış erişimi, gıda güvenliğiyle çelişmeyecek iş güvenliği kontrolleri.
- Önerileri üretim hijyeni ve iş güvenliği dengesini koruyarak yaz.`,
  agriculture_livestock: `SEKTÖR REHBERİ — TARIM / HAYVANCILIK

Bu analizde özellikle şu risk ailelerini sektör bağlamında değerlendir:
- Traktör/ekipman devrilmesi, hareketli parçalar, hayvan kaynaklı riskler ve açık alan koşulları.
- Pestisit/kimyasal maruziyet, güneş/ısı stresi, biyolojik risk ve uygun KKD.
- Depolama, yakıt, yangın, bakım-onarım ve yalnız çalışma riskleri.
- Görünmeyen kimyasal veya biyolojik maruziyetleri kesin varmış gibi yazma.`,
  retail: `SEKTÖR REHBERİ — PERAKENDE / MAĞAZA

Bu analizde özellikle şu risk ailelerini sektör bağlamında değerlendir:
- Müşteri ve çalışan dolaşımı, kayma-takılma-düşme, raf/ürün devrilmesi.
- Depo arkası istifleme, manuel taşıma, merdiven kullanımı ve acil çıkış erişimi.
- Elektrik prizleri, yangın söndürücü erişimi ve kalabalık yönetimi.
- Önerileri düşük maliyetli, hızlı uygulanabilir mağaza kontrolleriyle yaz.`,
  municipal_field_services: `SEKTÖR REHBERİ — BELEDİYE / KAMU SAHA İŞLERİ

Bu analizde özellikle şu risk ailelerini sektör bağlamında değerlendir:
- Yol/saha çalışması, trafik etkileşimi, bariyerleme, işaretleme ve görünürlük.
- Açık alan hava koşulları, kazı, bakım-onarım, temizlik ve atık toplama riskleri.
- Kamu erişimi olan alanlarda üçüncü kişi güvenliği ve geçici çalışma alanı kontrolü.
- Önerileri saha ekibi, trafik güvenliği ve kamu alanı düzeniyle uyumlu yaz.`,
  education: `SEKTÖR REHBERİ — EĞİTİM KURUMU

Bu analizde özellikle şu risk ailelerini sektör bağlamında değerlendir:
- Öğrenci/ziyaretçi yoğunluğu, merdiven-koridor güvenliği, düşme ve çarpma riskleri.
- Laboratuvar/atölye alanlarında kimyasal, makine, elektrik ve KKD kontrolleri.
- Acil çıkış, yangın güvenliği, yönlendirme ve sabitleme kontrolleri.
- Önerileri çocuk/genç kullanıcı varlığını dikkate alarak uygulanabilir şekilde yaz.`,
  hospitality: `SEKTÖR REHBERİ — OTEL / KONAKLAMA

Bu analizde özellikle şu risk ailelerini sektör bağlamında değerlendir:
- Misafir alanları, kayma-takılma-düşme, yangın kaçış yolları ve acil yönlendirme.
- Mutfak, çamaşırhane, teknik servis ve temizlik kimyasalları.
- Ergonomi, sıcak yüzeyler, elektrik ve bakım-onarım riskleri.
- Önerileri misafir güvenliği ve operasyon sürekliliğini birlikte koruyacak şekilde yaz.`,
};

export function isAnalysisSectorId(value: string): value is AnalysisSectorId {
  return (ANALYSIS_SECTOR_ALLOWLIST as readonly string[]).includes(value);
}

export function normalizeAnalysisSector(
  input: unknown,
): AnalysisSectorId | null {
  if (typeof input !== "string") return null;
  const trimmed = input.trim();
  return isAnalysisSectorId(trimmed) ? trimmed : null;
}

function cleanOptionalString(input: unknown): string | null {
  if (typeof input !== "string") return null;
  const trimmed = input.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export function resolveActiveSectorState(args: {
  requestedSector: unknown;
  persistedSector: unknown;
  requestedSource?: unknown;
  persistedSource?: unknown;
  requestedPromptVersion?: unknown;
  persistedPromptVersion?: unknown;
  isWorkerInvocation?: boolean;
}): ActiveSectorResolution {
  const requestedRaw = cleanOptionalString(args.requestedSector);
  const persistedSector = normalizeAnalysisSector(args.persistedSector);
  const requestedSector = requestedRaw
    ? normalizeAnalysisSector(requestedRaw)
    : null;
  if (requestedRaw && !requestedSector) {
    if (args.isWorkerInvocation === true && persistedSector) {
      const source = cleanOptionalString(args.persistedSource) ??
        "legacy_missing";
      const promptVersion = cleanOptionalString(args.persistedPromptVersion) ??
        ACTIVE_ANALYSIS_SECTOR_PROMPT_VERSION;
      const backfillPatch: ActiveSectorBackfillPatch = {};

      if (!cleanOptionalString(args.persistedSource)) {
        backfillPatch.analysis_sector_source = source;
      }
      if (!cleanOptionalString(args.persistedPromptVersion)) {
        backfillPatch.analysis_sector_prompt_version = promptVersion;
      }

      return {
        ok: true,
        sector: persistedSector,
        source,
        promptVersion,
        shouldBackfill: Object.keys(backfillPatch).length > 0,
        backfillPatch,
      };
    }

    return {
      ok: false,
      status: 400,
      code: "invalid_analysis_sector",
      message:
        "Analiz kapsamı geçerli değil. Lütfen sektör seçimini yenileyip tekrar deneyin.",
      requestedSector: requestedRaw,
      persistedSector: normalizeAnalysisSector(args.persistedSector),
    };
  }

  const requestedSource = cleanOptionalString(args.requestedSource);
  const persistedSource = cleanOptionalString(args.persistedSource);
  const requestedPromptVersion = cleanOptionalString(
    args.requestedPromptVersion,
  );
  const persistedPromptVersion = cleanOptionalString(
    args.persistedPromptVersion,
  );

  if (persistedSector) {
    if (
      requestedSector &&
      requestedSector !== persistedSector &&
      args.isWorkerInvocation !== true
    ) {
      return {
        ok: false,
        status: 409,
        code: "sector_mismatch",
        message:
          "Analiz kapsamı kayıtlı analiz verisiyle eşleşmiyor. Lütfen analizi yeniden başlatın.",
        requestedSector,
        persistedSector,
      };
    }

    const source = persistedSource ??
      (requestedSector ? requestedSource : null) ??
      "legacy_missing";
    const promptVersion = persistedPromptVersion ??
      (requestedSector ? requestedPromptVersion : null) ??
      ACTIVE_ANALYSIS_SECTOR_PROMPT_VERSION;
    const backfillPatch: ActiveSectorBackfillPatch = {};

    if (!persistedSource) {
      backfillPatch.analysis_sector_source = source;
    }
    if (!persistedPromptVersion) {
      backfillPatch.analysis_sector_prompt_version = promptVersion;
    }

    return {
      ok: true,
      sector: persistedSector,
      source,
      promptVersion,
      shouldBackfill: Object.keys(backfillPatch).length > 0,
      backfillPatch,
    };
  }

  if (requestedSector) {
    const source = requestedSource ?? "user_selected";
    const promptVersion = requestedPromptVersion ??
      ACTIVE_ANALYSIS_SECTOR_PROMPT_VERSION;
    return {
      ok: true,
      sector: requestedSector,
      source,
      promptVersion,
      shouldBackfill: true,
      backfillPatch: {
        analysis_sector: requestedSector,
        analysis_sector_source: source,
        analysis_sector_prompt_version: promptVersion,
      },
    };
  }

  return {
    ok: true,
    sector: null,
    source: null,
    promptVersion: null,
    shouldBackfill: false,
    backfillPatch: {},
  };
}

export function analysisSectorLabel(
  sector: AnalysisSectorId,
  outputLanguage: "tr" | "en" = "tr",
): string {
  if (outputLanguage === "en") {
    switch (sector) {
      case "general":
        return "General OHS";
      case "construction":
        return "Construction";
      case "manufacturing":
        return "Manufacturing / Factory";
      case "mining":
        return "Mining";
      case "energy":
        return "Energy";
      case "office":
        return "Office";
      case "logistics_warehouse":
        return "Warehouse / Logistics";
      case "chemical_laboratory":
        return "Chemical / Laboratory";
      case "healthcare":
        return "Healthcare / Hospital";
      case "food_production":
        return "Food Production";
      case "agriculture_livestock":
        return "Agriculture / Livestock";
      case "retail":
        return "Retail / Store";
      case "municipal_field_services":
        return "Municipal / Public Field Services";
      case "education":
        return "Education Facility";
      case "hospitality":
        return "Hospitality / Hotel";
    }
  }
  return SECTOR_LABELS_TR[sector];
}

export function buildActiveSectorPromptBlock(args: {
  sector: AnalysisSectorId | null;
  outputLanguage?: "tr" | "en";
  selectedCanvasLabels?: string[];
}): string {
  const outputLanguage = args.outputLanguage ?? "tr";

  if (!args.sector) {
    return `<aktif_analiz_sektoru version="${ACTIVE_ANALYSIS_SECTOR_PROMPT_VERSION}">
AKTİF ANALİZ SEKTÖRÜ

Bu istek eski istemciden gelmiş olabilir ve aktif analiz sektörü belirtilmemiştir. Mevcut genel İSG analiz prosedürünü koru. Onboarding sektörlerini yalnızca zayıf profil sinyali olarak kullan; görünmeyen sektör-tipik tehlikeleri uydurma.
</aktif_analiz_sektoru>`;
  }

  if (args.sector === "general") {
    return `<aktif_analiz_sektoru version="${ACTIVE_ANALYSIS_SECTOR_PROMPT_VERSION}">
AKTİF ANALİZ SEKTÖRÜ

Kullanıcı bu analizi genel İSG kapsamında başlatmıştır. Sektöre özel varsayımlar yapma. Görsel veya metin kanıtına dayalı genel saha güvenliği taraması uygula.
</aktif_analiz_sektoru>`;
  }

  const label = analysisSectorLabel(args.sector, outputLanguage);
  const guidance = SECTOR_GUIDANCE_TR[args.sector] ?? "";

  return `<aktif_analiz_sektoru version="${ACTIVE_ANALYSIS_SECTOR_PROMPT_VERSION}">
AKTİF ANALİZ SEKTÖRÜ

Kullanıcı bu analizi "${label}" sektörü kapsamında başlatmıştır.

Bu sektör bilgisini analizde aktif bağlam olarak kullan:
- Tehlikeleri sektörün saha gerçekliğine göre önceliklendir.
- Terminolojiyi seçilen sektöre uygun kullan.
- Düzeltici önlem ve önleyici kontrolleri seçilen sektörde uygulanabilir olacak şekilde yaz.
- Mevzuat, iyi uygulama ve saha kontrol önerilerini seçilen sektörle uyumlu kur.
- Aynı görsel farklı sektörlerde farklı risk önceliklerine sahip olabileceğinden, bu analizi özellikle "${label}" kapsamına göre değerlendir.

Ancak:
- Görselde veya kullanıcı metninde kanıtı olmayan sektör-tipik tehlikeleri uydurma.
- Seçilen sektör ile görüntüdeki saha unsurları çelişirse görsel kanıtı üstün kabul et.
- Çelişki varsa bunu kısa ve profesyonel şekilde limitations alanında belirt.
- Kullanıcının onboarding'de seçtiği diğer sektörleri bu analiz için ek tehlike üretmek amacıyla kullanma.
- Fine-Kinney ve 5x5 için yalnızca ham girdileri ver; skoru sistem hesaplayacaktır.

${guidance}
</aktif_analiz_sektoru>`;
}

export function onboardingSectorProfileRule(hasActiveSector: boolean): string {
  if (!hasActiveSector) {
    return "Onboarding sektörleri genel profil sinyalidir; görünmeyen sektör-tipik tehlikeleri uydurma.";
  }
  return "Kullanıcının onboarding profilinde birden fazla çalışma sektörü bulunabilir. Bunlar genel uzmanlık/profil sinyalidir. Bu analiz için esas alınacak sektör, kullanıcı tarafından seçilen aktif analiz sektörüdür. Onboarding sektörlerini bu analizde görünmeyen ek tehlikeler üretmek için kullanma.";
}
