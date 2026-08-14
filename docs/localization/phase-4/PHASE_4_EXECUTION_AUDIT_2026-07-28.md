# RiskDetected Global Localization — Faz 4 Execution Audit

Tarih: 2026-07-28  
Son güncelleme: 2026-07-30  
Durum: **completed_with_operator_waiver**  
Sonraki faz: **Faz 5 başlatılabilir.**

## Kapanış özeti

Faz 4 uygulaması, yerel doğrulamaları, native review kapısı ve canlı smoke
canary tamamlandı. Tam canlı matrisin son koşusu 81/84 sonuçlandı. Kalan üç
çiftin yeniden çalıştırılması ilave Gemini tüketimi gerektirdiğinden, proje
sahibi 2026-07-30 tarihinde “API’de bir sürü param gitti; en kısa yoldan Faz
4’ü kapat” talimatıyla canlı 84/84 kapısı için operasyonel istisnayı açıkça
onayladı.

Bu istisna sonucu değiştirmez veya başarısız çiftleri geçmiş saymaz:

- kanonik smoke: **12/12**
- son full denemesi: **81/84**
- full kapanış şekli: **operator waiver**
- yeni canlı Gemini çağrısı: **durduruldu**
- production deploy/migration/DB mutation: **yapılmadı**

Kalan üç çift Faz 5 regresyon ve kontrollü rollout gözlemlenebilirlik risk
kaydına devredildi:

1. `tr-tr-current-v1 / single_forklift_pedestrian`  
   `OUTPUT_LANGUAGE_CONTRACT_FAILED` /
   `PHOTO_EVIDENCE_UNSUPPORTED_CERTAINTY`
2. `en-gb-generic-v1 / single_clean`  
   `CANARY_UNSUPPORTED_ACTIONABLE_FINDING`
3. `en-ca-generic-v1 / single_clean`  
   `CANARY_UNSUPPORTED_ACTIONABLE_FINDING`

## Uygulanan AI sözleşmesi

- Prompt altı bağımsız katmana ayrıldı:
  - schema contract
  - language contract
  - safety profile contract
  - regulatory reference contract
  - risk method contract
  - photo evidence contract
- JSON anahtarları kanonik İngilizce olarak sabit tutuldu.
- Altı safety profile terminolojisi generated manifestten alınır.
- Non-TR profillerde structured regulatory references kapalıdır.
- `root_cause` JSON anahtarı değişmez; İngilizce sunum etiketi
  `Likely contributing factors` olarak tanımlıdır.
- İngilizce analiz context, canvas, onboarding, company ve foto marker
  katmanları Türkçe prompt tabanından ayrıldı.
- Kullanıcı ve firma değerleri instruction değil, kaçışlanmış untrusted data
  olarak serialize edilir.
- Çıktı validator sırası:
  1. JSON/schema
  2. output language
  3. safety-profile terminology
  4. forbidden claim
  5. regulatory reference
  6. visible-photo evidence
- İlk validator hatasında en fazla bir `language_contract_repair` yapılır.
- Repair aynı provider, model, API key alias ve execution route üzerinde
  doğrudan çalışır; ikinci kullanıcı kotası tüketmez.
- Başarısız repair `OUTPUT_LANGUAGE_CONTRACT_FAILED` ile fail closed olur.
- Fotoğraf kanıtı sözleşmesi:
  - sayısal/ölçüm iddiasında saha doğrulaması ister,
  - görünmeyen eğitim, yetkinlik, prosedür ve bakım kaydı iddialarını reddeder,
  - kesin kök neden ve desteklenmeyen kesinlik dilini reddeder,
  - salt makine/raf/elektrik ekipmanı/endüstriyel ortam varlığını uygunsuzluk
    saymaz,
  - objektif eyleme geçirilebilir tehlike yoksa boş bulgu dizisini geçerli
    kabul eder.
- Prompt, analysis context, provider response ve kullanıcı içeriği telemetry
  içine yazılmaz.

## Mevcut AI servisiyle ortaklaştırma

Canary, kota/kuyruk/veritabanı/bildirim yan etkileri taşıyan bütün
`/analyze` orkestrasyonunu çağırmaz. Bunun yerine üretim analiz hattının
yan etkisiz parçalarını doğrudan ortak kullanır:

- Gemini HTTP taşıması:
  `supabase/functions/_shared/gemini-provider-client.ts`
- timeout/fetch davranışı:
  `supabase/functions/_shared/provider-fetch.ts`
- source photo index normalizasyonu:
  `supabase/functions/_shared/photo-source-indices.ts`
- confidence ve field-verification normalizasyonu:
  `supabase/functions/_shared/finding-confidence.ts`
- localization prompt ve repair sözleşmesi:
  `supabase/functions/_shared/ai-localization-prompt.ts`
- output validator:
  `supabase/functions/_shared/ai-localization-validation.ts`

API anahtarı URL query parametresinde taşınmaz; ortak istemci
`x-goog-api-key` header kullanır.

## Otomatik doğrulama

- Faz 4 özel test matrisi: **60/60 geçti**
- `AI-001…AI-025` gereksinim matrisi: **25/25 kanıtlı**
- Tüm Supabase Edge Function testleri: **248/248 geçti**
- Safety profile sözleşmeleri: **17/17 geçti**
- Localization catalog gate: **16/16 geçti**
- Type check:
  - `supabase/functions/analyze/index.ts`: **geçti**
  - `scripts/run_ai_localization_canary.mjs`: **geçti**
- Canary corpus:
  - sentetik runtime asset: **13/13 checksum geçti**
  - zorunlu scenario: **14/14 mevcut**
  - profile: **6**
  - native review: **approved**
  - reviewer: **Kerem**
  - reviewer niteliği: **native English workplace-safety reviewer**
  - manifest SHA-256:
    `d4f00de59138939a53d3af70c6427b7572267e7a7bb9aa44e5096ac2c22dd3fa`
- Retry bütçesi:
  - ilk provider cevabı için en fazla üç transient retry
  - bundan bağımsız en fazla bir validator repair
  - çift başına en fazla beş fiziksel istek
  - smoke plan üst sınırı: **60**
  - full plan üst sınırı: **420**

## Canlı canary kanıtı

### Smoke

- Dosya:
  `docs/localization/phase-4/canary/results/smoke-result.json`
- Sonuç: **12/12**
- Fiziksel provider isteği: **12**
- Transient retry: **0**
- Validation attempt: **12**
- Bağımsız verifier: **geçti**
- Content logging: **kapalı**

### Full

- Son ve kapanışta kullanılan deneme:
  `docs/localization/phase-4/canary/results/full-attempt-failed-2026-07-30T20-16-50.181Z.json`
- Sonuç: **81/84**
- Fiziksel provider isteği: **89**
- Transient retry: **2**
- Validation attempt: **87**
- Kanonik `full-result.json`: **üretilmedi**
- 84/84 kapısı: **proje sahibi tarafından maliyet gerekçeli operasyonel
  istisna ile kapatıldı**

Başarısız önceki denemeler silinmedi; tarihli metadata-only kanıtlar olarak
`docs/localization/phase-4/canary/results/` altında tutulur.

## Secret ve gizlilik

- Bağlı Supabase projesi: `ppcrzemgiztzcgddbins`
- Production secret adları salt okunur envanterde doğrulandı:
  - `GEMINI_API_KEY`
  - `GEMINI_API_KEY_PAID`
  - `GEMINI_API_KEY_SECONDARY`
- Secret değerleri okunmadı veya repository'ye yazılmadı.
- Ayrı canary anahtarı macOS Keychain servisinde tutulur:
  `riskdetected_gemini_api_key_canary`
- Güvenli wrapper:
  `scripts/run_ai_localization_canary_from_keychain.sh`
- Prompt, görsel/base64, model yanıtı, kullanıcı metni ve API anahtarı sonuç
  dosyalarına yazılmaz.

## Build kanıtları

- Debug: geçti, 0 warning, 0 error  
  `/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/logs/build_sim_2026-07-28T22-02-37-886Z_pid73592_86f91890.log`
- Release: geçti, 0 warning, 0 error  
  `/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/logs/build_run_sim_2026-07-28T22-26-52-569Z_pid73592_06094a0e.log`

## Faz 5'e devredilen kontroller

- `single_clean` yanlış-pozitif oranı profile göre ayrı ölçülür.
- `PHOTO_EVIDENCE_UNSUPPORTED_CERTAINTY` sayacı izlenir.
- Non-TR rollout başlangıçta kontrollü tutulur; kill switch ve fail-closed
  davranış korunur.
- 84/84 canlı full koşusu yeniden zorunlu değildir; ancak yeni prompt/model,
  corpus veya safety-profile sürümünde normal değişiklik yönetimi kapsamında
  tekrar değerlendirilebilir.
