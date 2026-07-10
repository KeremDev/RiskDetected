import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  areLikelyDuplicateCoverageFindings,
  preferredCoverageFinding,
  tokenJaccardSimilarity,
} from "./photo-finding-quality.ts";

Deno.test("merges the reported title suffix variation with identical evidence", () => {
  const first = {
    title: "Elektrikli Cihazın Dış Hasarlara Karşı Korunması",
    observed_evidence:
      "Asansör interkom ünitesi dış etkenlere karşı belirgin bir korumaya sahip değildir.",
    corrective_action: "Koruyucu muhafaza tak.",
    root_cause: "Fiziksel koruma eksikliği.",
  };
  const second = {
    ...first,
    title: "Elektrikli Cihazın Dış Hasarlara Karşı Koruması",
  };

  assert(areLikelyDuplicateCoverageFindings(first, second));
});

Deno.test("does not merge distinct findings that share generic evidence and category", () => {
  const traffic = {
    title: "Yaya ve forklift trafiği ayrımı eksikliği",
    category: "Çevre, Acil Durum, İşaretleme ve Yetkinlik",
    observed_evidence: "Saha gözlemiyle doğrulanması gereken risk göstergesi.",
    corrective_action: "Yaya yollarını fiziksel bariyerlerle ayır.",
    root_cause: "Saha trafik planlamasının yetersizliği.",
  };
  const competence = {
    title: "Forklift operatörü yetkinlik belgesi eksikliği",
    category: "Çevre, Acil Durum, İşaretleme ve Yetkinlik",
    observed_evidence: "Saha gözlemiyle doğrulanması gereken risk göstergesi.",
    corrective_action: "Operatör yetkinlik belgelerini kontrol et.",
    root_cause: "Yetkinlik doğrulama sürecinin eksikliği.",
  };

  assertFalse(areLikelyDuplicateCoverageFindings(traffic, competence));
});

Deno.test("balanced evidence similarity preserves a finding with additional evidence", () => {
  const exposedCable = {
    title: "Açık kabloya temas riski",
    observed_evidence:
      "Pano kapağı açık ve enerji kabloları çalışanların erişimine açıktır.",
    corrective_action: "Panoyu kapat ve erişimi sınırla.",
    root_cause: "Pano erişim kontrolü eksikliği.",
  };
  const grounding = {
    title: "Topraklama bağlantısı eksikliği",
    observed_evidence:
      "Pano kapağı açık ve enerji kabloları çalışanların erişimine açıktır; ayrıca topraklama bağlantısı görünmemektedir.",
    corrective_action: "Topraklama sürekliliğini ölç ve bağlantıyı tamamla.",
    root_cause: "Elektrik tesisatı kontrolü eksikliği.",
  };

  assert(
    tokenJaccardSimilarity(
      exposedCable.observed_evidence,
      grounding.observed_evidence,
    ) < 0.8,
  );
  assertFalse(areLikelyDuplicateCoverageFindings(exposedCable, grounding));
});

Deno.test("strong evidence action and root cause agreement can merge different titles", () => {
  const first = {
    title: "Geçici kabloda izolasyon hasarı",
    observed_evidence:
      "Geçici enerji kablosunun dış izolasyonunda yırtılma ve iletken açığa çıkma görülmektedir.",
    corrective_action: "Hasarlı kabloyu enerjisiz bırak ve yenisiyle değiştir.",
    root_cause: "Geçici kabloların periyodik kontrolünün yapılmaması.",
  };
  const second = {
    title: "Elektrik hattında fiziksel yıpranma",
    observed_evidence:
      "Geçici enerji kablosunun dış izolasyonunda yırtılma ve iletken açığa çıkma görülmüştür.",
    corrective_action: "Hasarlı kabloyu enerjisiz bırak ve yenisiyle değiştir.",
    root_cause: "Geçici kabloların periyodik kontrolünün yapılmaması.",
  };

  assert(areLikelyDuplicateCoverageFindings(first, second));
});

Deno.test("keeps the higher-confidence and more complete duplicate", () => {
  const brief = {
    title: "Hasarlı kablo",
    observed_evidence: "Kablo izolasyonu hasarlıdır.",
    corrective_action: "Kabloyu değiştir.",
    root_cause: "Kontrol eksikliği.",
    confidence: 0.72,
  };
  const detailed = {
    title: "Hasarlı kablo izolasyonu",
    observed_evidence:
      "Enerji kablosunun dış izolasyonunda yırtılma görülmektedir.",
    description: "Açık iletkene temas elektrik çarpmasına neden olabilir.",
    corrective_action: "Hattı enerjisiz bırak ve kabloyu yenisiyle değiştir.",
    preventive_control: "Kabloları haftalık fiziksel kontrol listesine ekle.",
    root_cause: "Geçici kablo kontrolünün yapılmaması.",
    confidence: 0.91,
  };

  assertEquals(preferredCoverageFinding(brief, detailed), detailed);
  assertEquals(preferredCoverageFinding(detailed, brief), detailed);
});
