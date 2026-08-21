import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { applyContextualFindingGuard } from "./contextual-finding-guard.ts";

Deno.test("enclosed excavator cab rejects unsupported hard-hat and vest claim", () => {
  const finding = {
    title: "Ekskavatör operatöründe KKD eksikliği",
    observed_evidence:
      "Ekskavatör kabini içinde operatörün baret ve reflektörlü yelek kullanmadığı görülmektedir.",
    inspection_layer_keys: ["ppe"],
  };
  const result = applyContextualFindingGuard([finding], {
    scene_elements: ["Ekskavatör", "Operatör kabini"],
    scene_summary: "Ekskavatör çalışma sırasında görülmektedir.",
  });
  assertEquals(result.findings, []);
  assertEquals(result.rejected_enclosed_cab_ppe_count, 1);
});

Deno.test("cab guard keeps external worker PPE and visible seat-belt findings", () => {
  const externalWorker = {
    title: "Ekskavatör yanındaki çalışanda baret yok",
    observed_evidence: "Çalışan kabin dışında ve baş koruması görünmüyor.",
    inspection_layer_keys: ["ppe"],
  };
  const seatBelt = {
    title: "Operatör emniyet kemeri takmıyor",
    observed_evidence: "Kabin içinde kemerin takılı olmadığı net görülüyor.",
    inspection_layer_keys: ["machinery_equipment"],
  };
  const result = applyContextualFindingGuard([externalWorker, seatBelt], {
    scene_elements: ["Ekskavatör", "Operatör kabini"],
  });
  assertEquals(result.findings, [externalWorker, seatBelt]);
  assertEquals(result.rejected_enclosed_cab_ppe_count, 0);
});

Deno.test("hard-hat finding remains when no enclosed cab context exists", () => {
  const finding = {
    title: "Çalışanda baret eksikliği",
    observed_evidence: "Çalışan açık alanda baret kullanmıyor.",
    inspection_layer_keys: ["ppe"],
  };
  const result = applyContextualFindingGuard([finding], {
    scene_elements: ["Açık çalışma alanı"],
  });
  assertEquals(result.findings, [finding]);
});
