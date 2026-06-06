import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  containsForbiddenTextReportLanguage,
  sanitizeTextAnalysisHazardForReportLanguage,
  sanitizeTextReportLanguage,
} from "./text-report-language.ts";

Deno.test("text report language removes quoted user text and metinde phrasing", () => {
  const userText = "cam fabrikasında bir sürü ekipman var";
  const value =
    "Metinde 'bir sürü ekipman var' ifadesi geçmektedir. Makine koruyucuları sahada doğrulanmalıdır.";

  assertEquals(
    sanitizeTextReportLanguage(value, userText),
    "Makine koruyucuları sahada doğrulanmalıdır.",
  );
});

Deno.test("text report language rejects direct user n-grams", () => {
  const userText = "cam fabrikasında bir sürü ekipman var";

  assert(
    containsForbiddenTextReportLanguage(
      "Cam fabrikasında bir sürü ekipman var; hareketli parçalar incelenmelidir.",
      userText,
    ),
  );
});

Deno.test("text report language removes user attribution around worker counts", () => {
  const userText = "40 çalışan var";
  const value =
    "Metinde 40 çalışan olduğu belirtilmiştir. Kalabalık çalışma alanında yaya-araç ayrımı sahada doğrulanmalıdır.";

  assertEquals(
    sanitizeTextReportLanguage(value, userText),
    "Kalabalık çalışma alanında yaya-araç ayrımı sahada doğrulanmalıdır.",
  );
  assertEquals(
    sanitizeTextReportLanguage(
      "40 çalışan olduğu durumda yaya yolları sahada doğrulanmalıdır.",
      userText,
    ),
    "Saha gözlemiyle doğrulanması gereken risk göstergesi.",
  );
});

Deno.test("text hazard sanitizer cleans all report fields", () => {
  const hazard = sanitizeTextAnalysisHazardForReportLanguage(
    {
      title: "Metinde geçen makine riski",
      observed_evidence: "Metinde 'bir sürü ekipman var' ifadesi geçmektedir.",
      description:
        "Cam fabrikasında hareketli parçalı ekipmanlar için koruyucu yeterliliği sahada doğrulanmalıdır.",
      corrective_action:
        "Kullanıcının yazdığı ekipmanlar için tüm koruyucuları kontrol et.",
      preventive_control:
        "Makine koruyucularının periyodik kontrolünü iş ekipmanları kontrol listesine ekle.",
      root_cause: "Metinde bakım kontrol eksikliği ima edilmiştir.",
      references:
        "İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği.",
    },
    "cam fabrikasında bir sürü ekipman var",
  );

  const combined = Object.values(hazard).join(" ").toLocaleLowerCase("tr-TR");
  assert(!combined.includes("metinde"));
  assert(!combined.includes("kullanıcı"));
  assert(!combined.includes("bir sürü ekipman var"));
  assert(combined.includes("hareketli parçalı ekipmanlar"));
});
