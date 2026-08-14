# RiskDetected Faz 4 — AI-001…AI-025 Gereksinim Matrisi

Tarih: 2026-07-29  
Kapsam: Global localization uygulama planı §20.8  
Yerel sözleşme durumu: **25/25 uygulandı ve otomatik kanıta bağlandı.**  
Faz durumu: **completed_with_operator_waiver**

Bu matris yerel/unit/static sözleşme kapsamını kapatır. Native English
workplace-safety review `approved`, canlı smoke 12/12'dir. Full canary 81/84
sonuçlanmış; proje sahibinin API tüketimini durdurma talimatıyla kalan üç çift
operasyonel istisna olarak Faz 5/rollout risk kaydına devredilmiştir.

| ID | Gereksinim | Yerel durum | Doğrudan kanıt |
|---|---|---|---|
| AI-001 | `tr/TR` mevcut behavior parity | Geçti | `localization_phase4_static_test.ts` — “AI-001 Turkish baseline…”; `localization-context-resolver_test.ts` — legacy Turkish defaults; altı profil golden snapshot |
| AI-002 | `en/INTL` English only | Geçti | `ai-localization-validation_test.ts` — six-profile matrix ve Turkish leakage rejection |
| AI-003 | `en/GB` UK terminology | Geçti | Six-profile validator matrix; country cross-terminology rejection; profile golden snapshot |
| AI-004 | `en/US` US terminology | Geçti | Six-profile validator matrix; country cross-terminology rejection; profile golden snapshot |
| AI-005 | `en/AU` AU terminology | Geçti | Six-profile validator matrix; country cross-terminology rejection; profile golden snapshot |
| AI-006 | `en/CA` CA terminology | Geçti | Six-profile validator matrix; country cross-terminology rejection; profile golden snapshot |
| AI-007 | Non-TR references empty | Geçti | Prompt test “non-TR prompt disables structured regulatory references”; validator “non-TR structured references…”; static persistence gate |
| AI-008 | No 6331 non-TR | Geçti | Promptte non-TR `6331` yokluk kontrolü; validator “non-TR output rejects 6331…” |
| AI-009 | No cross-country regulator | Geçti | Cross-profile terminology validator; non-TR regulatory claim validator |
| AI-010 | No legal compliance claim | Geçti | Validator “non-TR structured references and compliance claims fail closed” |
| AI-011 | Evidence-only | Geçti | Photo-evidence prompt; unsupported certainty testi; unseen training/record claim rejection |
| AI-012 | Measurement requires verification | Geçti | Prompt measurement contract; numeric measurement claim reject/accept testi |
| AI-013 | Contributing factor, not definitive cause | Geçti | `Likely contributing factors` prompt contract; definitive root-cause rejection |
| AI-014 | Hierarchy of controls ordering | Geçti | Altı profil promptunda generated hierarchy sırası doğrudan doğrulanır |
| AI-015 | JSON keys unchanged | Geçti | Canonical English key prompt testi; schema required-field validator; golden snapshots |
| AI-016 | Finding limits unchanged | Geçti | Static test “AI-016 and AI-017…”; Türkçe/İngilizce scope aynı `PLAN_LIMITS` ve coverage policy değerlerini kullanır |
| AI-017 | Exact photo coverage unchanged | Geçti | Aynı Faz 4 static testi; `exact_multi_photo_coverage_static_test.ts` sözleşme testleri |
| AI-018 | Repair same locale | Geçti | Repair instruction immutable snapshot testi; same-provider repair options locale override etmez |
| AI-019 | Retry same locale | Geçti | Static test “AI-019 retries preserve…”; persisted snapshot retry/repair authority testi |
| AI-020 | Provider fallback same locale | Geçti | Static test “AI-020 provider fallbacks preserve…”; prompt/context/options aynı aktarılır |
| AI-021 | Cancelled trial no paid alias | Geçti | `cancelled_trial_ai_routing_static_test.ts`; Faz 4 cancelled-trial route isolation testi |
| AI-022 | Prompt injection resisted | Geçti | Untrusted value serialization/escaping testi; photo-evidence contract visible texti instruction saymaz |
| AI-023 | One language retry max | Geçti | `validateAIOutputWithSingleRepair` başarı ve ikinci hata testleri; direct repair provider call |
| AI-024 | Wrong language fail closed | Geçti | Stable `OUTPUT_LANGUAGE_CONTRACT_FAILED` testi; iOS generic 502 retry öncesi stable-code guard |
| AI-025 | No user quota on language repair | Geçti | Repair bloğunda reserve/complete/release quota çağrısı yok; physical provider request telemetry ayrı |

## Kaynak dosyalar

- `supabase/functions/_shared/ai-localization-prompt.ts`
- `supabase/functions/_shared/ai-localization-prompt_test.ts`
- `supabase/functions/_shared/ai-localization-validation.ts`
- `supabase/functions/_shared/ai-localization-validation_test.ts`
- `supabase/functions/_shared/localization-context-resolver_test.ts`
- `supabase/functions/analyze/localization_phase4_static_test.ts`
- `supabase/functions/analyze/exact_multi_photo_coverage_static_test.ts`
- `supabase/functions/analyze/cancelled_trial_ai_routing_static_test.ts`

## Kapanış ayrımı

- AI-001…AI-025: **25/25**
- Native review: **approved — Kerem**
- Canlı smoke: **12/12**
- Canlı full: **81/84**
- Faz 4 kapanışı: **completed_with_operator_waiver**
- Ayrıntılı karar ve residual risk:
  `docs/localization/phase-4/PHASE_4_EXECUTION_AUDIT_2026-07-28.md`
