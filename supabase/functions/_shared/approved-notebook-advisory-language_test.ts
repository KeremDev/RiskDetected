import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  isStrictTurkishNotebookAdvisory,
  notebookAdvisoryFallback,
  strictTurkishNotebookAdvisoryOrFallback,
} from "./approved-notebook-advisory-language.ts";

Deno.test("strict notebook language accepts employer-facing advice", () => {
  assert(
    isStrictTurkishNotebookAdvisory(
      "İşçinin güvenli bir çalışma platformuna indirilmesi ve çalışma alanının emniyete alınması önerilmektedir.",
    ),
  );
  assert(
    isStrictTurkishNotebookAdvisory(
      "Açık kenara uygun bir toplu koruma sistemi kurulması tavsiye edilmektedir.",
    ),
  );
  assert(
    isStrictTurkishNotebookAdvisory(
      "Kabloların korumalı kablo kanallarından geçirilmesi önerilmektedir.",
    ),
  );
});

Deno.test("strict notebook language rejects commands and obligation register", () => {
  assertEquals(
    isStrictTurkishNotebookAdvisory(
      "İşçiyi derhal tank üzerinden indirin ve önlem alın.",
    ),
    false,
  );
  assertEquals(
    isStrictTurkishNotebookAdvisory(
      "Kenar koruması kurulmalıdır.",
    ),
    false,
  );
  assertEquals(
    isStrictTurkishNotebookAdvisory(
      "Öneri: Kenar koruması kurulması önerilmektedir.",
    ),
    false,
  );
  assertEquals(
    isStrictTurkishNotebookAdvisory(
      "Erişimi kapatın; kenar koruması kurulması önerilmektedir.",
    ),
    false,
  );
});

Deno.test("invalid provider prose falls back by notebook item class", () => {
  const result = strictTurkishNotebookAdvisoryOrFallback(
    "Panoyu kapatın.",
    "observed_finding",
  );
  assert(result.usedFallback);
  assertEquals(
    result.text,
    notebookAdvisoryFallback("observed_finding"),
  );
  assert(isStrictTurkishNotebookAdvisory(result.text));
});
