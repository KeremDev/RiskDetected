import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/testing/asserts.ts";
import { lintControlText } from "./control-linter.ts";
import {
  V4_GEMINI3_RESPONSE_SCHEMA,
  V4_PROVIDER_RESPONSE_SCHEMA,
} from "./contracts.ts";
import type { NormalizedCandidate } from "./contracts.ts";

function candidate(
  overrides: Partial<NormalizedCandidate> = {},
): NormalizedCandidate {
  return {
    candidate_key: "c1",
    module_id: "work_at_height",
    raw_label: "Döşeme kenarında koruma eksikliği",
    affirmative_cues: [],
    counter_cues: [],
    occlusion: "none",
    event_path: {
      source: "Döşeme kenarı",
      contact_or_failure: "Dengesini kaybederek düşme",
      consequence: "Yüksekten düşme",
    },
    potential_consequence: "fatal",
    visually_resolvable: true,
    requires_document_or_measurement: false,
    confidence: { visibility: 0.8, localization: 0.8, mechanism: 0.8 },
    id: "id-1",
    photo_index: 1,
    evidence_level: "E5",
    criticality: "fatal",
    condition_code: "visible_structural_absence",
    normalized_label: "kenar koruması",
    accessible_event_path: true,
    ...overrides,
  } as NormalizedCandidate;
}

function reason(raw: unknown, c = candidate()): string {
  const result = lintControlText(raw, c);
  return result.ok ? "ok" : result.reason;
}

Deno.test("yerel ve emir kipindeki önlem yayımlanır", () => {
  const result = lintControlText(
    "Sol bloktaki döşeme kenarında çalışmayı durdurun ve kenarı üst korkuluk, ara korkuluk ve etek tahtasıyla kesintisiz kapatın",
    candidate(),
  );
  assertEquals(result.ok, true);
  // Noktalama tamamlanır.
  if (result.ok) assertStringIncludes(result.text, "kapatın.");
});

Deno.test("mevzuat, standart ve skor atıfları reddedilir", () => {
  for (
    const text of [
      "6331 sayılı kanun gereği kenar korumasını tamamlayın ve alanı kapatın",
      "TS EN 13374 uyarınca korkuluk sistemini kurun ve erişimi sınırlandırın",
      "Fine-Kinney skoru yüksek olduğundan kenardaki çalışmayı derhal durdurun",
      "Yönetmeliğin ilgili maddesine göre toplu korumayı tamamlayın ve doğrulayın",
    ]
  ) {
    const result = lintControlText(text, candidate());
    assertEquals(result.ok, false, text);
  }
});

Deno.test("görünmeyen kayıt hakkında yokluk iddiası reddedilir, öneri serbesttir", () => {
  assertEquals(
    lintControlText(
      "Çalışanların yüksekte çalışma eğitimi yok, kenardaki işi durdurun",
      candidate(),
    ).ok,
    false,
  );
  assertEquals(
    lintControlText(
      "Kenardaki çalışmayı yazılı izin sistemine bağlayın ve izin alınmadan girişi fiziksel olarak kapatın",
      candidate(),
    ).ok,
    true,
  );
});

Deno.test("gözlem cümlesi önlem yerine geçemez", () => {
  assertEquals(
    lintControlText(
      "Döşeme kenarında herhangi bir korkuluk bulunmamakta ve düşme riski mevcuttur",
      candidate(),
    ).ok,
    false,
  );
});

Deno.test("boş, kısa, işaretlemeli ve diakritiksiz metin reddedilir", () => {
  assertEquals(reason(undefined), "absent");
  assertEquals(reason("Kenarı kapatın"), "too_short");
  assertEquals(
    reason(
      "Kenardaki calismayi durdurun ve korkulugu bir bir tamamlayin bu alan icin",
    ),
    "diacritics_stripped",
  );
  assertEquals(
    reason("<b>Kenardaki çalışmayı durdurun</b> ve korkuluğu tamamlayın"),
    "not_prose",
  );
});

Deno.test("başlığı tekrar eden cümle reddedilir", () => {
  assertEquals(
    reason("Döşeme kenarında koruma eksikliği giderilmeli ve alan kapatılmalı"),
    "echoes_label",
  );
});

Deno.test("Gemini 3 şeması yalnız recommended_control ile ayrışır", () => {
  const base = V4_PROVIDER_RESPONSE_SCHEMA as unknown as Record<string, any>;
  const g3 = V4_GEMINI3_RESPONSE_SCHEMA as Record<string, any>;
  const baseProps = base.properties.candidates.items.properties;
  const g3Props = g3.properties.candidates.items.properties;
  assertEquals("recommended_control" in baseProps, false);
  assertEquals(g3Props.recommended_control, { type: "string" });
  // Zorunlu değil: alanı gelmeyen aday hâlâ geçerli bir adaydır.
  assertEquals(
    (g3.properties.candidates.items.required as string[]).includes(
      "recommended_control",
    ),
    false,
  );
  // Klon, referans paylaşımı değil.
  assertEquals(
    Object.keys(g3Props).length,
    Object.keys(baseProps).length + 1,
  );
});
