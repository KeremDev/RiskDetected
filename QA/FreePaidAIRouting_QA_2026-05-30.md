# Free Paid AI Routing QA

Tarih: 2026-05-30T00:16:30.203Z
Supabase project: ppcrzemgiztzcgddbins
Live E2E: denendi

## Özet

- PASS: 41
- WARN: 0
- FAIL: 0

## Kontroller

- PASS: Route enum kontratı
- PASS: Env flag ve kill switch kontratı
- PASS: Free standard paid route çözümü
- PASS: Free paid trial kalite seviyesi Plus
- PASS: Yetki kontrolleri planTier ile kalıyor
- PASS: Prompt/schema qualityTier ile çalışıyor
- PASS: Free paid trial fallback sırası
- PASS: Free paid trial Pro model kullanmıyor
- PASS: Telemetry alanları function içinde loglanıyor
- PASS: Telemetry migration kontratı
- PASS: Hybrid QA route dağılımını raporluyor
- PASS: Deno check analyze
- PASS: Node syntax qa_hybrid_runner
- PASS: Git whitespace check
- PASS: Remote migration list contains AI route migration — Local          | Remote         | Time (UTC)             ----------------|----------------|---------------------    20260503075828 | 20260503075828 | 2026-05-03 07:58:28     20260503075849 | 20260503075849 | 2026-05-03 07:58:49     20260503075909 | 20260503075909 | 2026-05-03 07:59:09     20260503075933 | 20260503075933 | 2026-05-03 07:59:33     20260503075950 | 20260503075950 | 2026-05-03 07:59:50     20260503080015 | 20260503080015 | 2026-05-03 08:00:15     20260503080033 | 20260503080033 | 2026-05-03 08:00:33     20260503080049 | 20260503080049 | 2026-05-03 08:00:49     20260503080126 | 20260503080126 | 2026-05-03 08:01:26     20260504063219 | 20260504063219 | 2026-05-04 06:32:19     20260506192136 | 20260506192136 | 2026-05-06 19:21:36     20260506193000 | 20260506193000 | 2026-05-06 19:30:00     20260507221522 | 20260507221522 | 2026-05-07 22:15:22     20260508021838 | 20260508021838 | 2026-05-08 02:18:38     20260508022421 | 20260508022421 | 2026-05-08 02:24:21     20260508185954 | 20260508185954 | 2026-05-08 18:59:54     20260508192153 | 20260508192153 | 2026-05-08 19:21:53     20260509001429 | 20260509001429 | 2026-05-09 00:14:29     20260509230500 | 20260509230500 | 2026-0
- PASS: Remote AI route migration applied — 20260529110948_add_ai_execution_route_telemetry.sql
- PASS: Remote secret list readable — NAME                             | DIGEST                                                              ----------------------------------|------------------------------------------------------------------    AI_QA_SECRET                     | 26c677e2f06e8948777c15cee3353371dc4b4cc59b4d0cd0e4d1136945e5d8a8     APNS_BUNDLE_ID                   | 87a38440416339117f7e685412bfd9bf2ae31bee05ff5ca716e6db704b135d4e     APNS_ENV                         | ab8e18ef4ebebeddc0b3152ce9c9006e14fc05242e3fc9ce32246ea6a9543074     APNS_KEY_ID                      | 739cf539d39e8be585f6df6810ad6d0242e2a40b43930aae746132938d042003     APNS_PRIVATE_KEY                 | b1cb9b307b86d43f72efaa25907501c12c97b58a4db219444c6befae1b32c9d2     APNS_TEAM_ID                     | 4c7f6ad7eb99d9a97b557b4a6f75168f30b86693b52579417599077257590c2f     FIREBASE_PROJECT_ID              | 2e061b1005858f407c9b01d2ad8051169cf74003b9ead8e0e64c5dfa82616326     FREE_STANDARD_ANALYSIS_AI_ROUTE  | 908902b3978bca5d14aa3e98df284a72afa91323b360d7b0223e0268ba931cb6     GEMINI_API_KEY                   | 80192ccefc8779a69b4c6056e168126c31999d76c7b86585f2b7427668b4b0ea     GEMINI_API_KEY_PAID              | ef34bb079b5b7b4c832b2
- PASS: Remote secret GEMINI_API_KEY_PAID
- PASS: Remote secret GEMINI_API_KEY
- PASS: Remote secret FREE_STANDARD_ANALYSIS_AI_ROUTE
- PASS: Remote fallback key present — Free Gemini secondary veya Groq fallback beklenir.
- PASS: Remote analyze function active — ID                                   | NAME                           | SLUG                           | STATUS | VERSION | UPDATED_AT (UTC)       --------------------------------------|--------------------------------|--------------------------------|--------|---------|---------------------    2cbd70f3-4e37-4167-b610-d2d7a306a04b | analyze                        | analyze                        | ACTIVE | 90      | 2026-05-29 23:29:21     dbdbe072-e76c-4f2c-b77a-3b94df100596 | retention-cleanup              | retention-cleanup              | ACTIVE | 29      | 2026-05-16 15:59:30     f8ac9266-ea68-4292-a382-4b4dc5d83545 | send-push-notification         | send-push-notification         | ACTIVE | 27      | 2026-05-29 23:29:11     30c9a44f-cdb8-4b94-90b9-1210e8aa8e73 | generate-excel-report          | generate-excel-report          | ACTIVE | 41      | 2026-05-29 23:29:16     cfd3fbfb-b804-4847-8de5-5ed3bbe79a54 | revenuecat-webhook             | revenuecat-webhook             | ACTIVE | 25      | 2026-05-22 05:25:45     e8d696b5-d5bd-4383-b6d2-689e7623c3d6 | support-contact                | support-contact                | ACTIVE | 20      | 2026-05-17 22:21:25     ba3c073c-6149-49
- PASS: Analyze function ACTIVE — 2cbd70f3-4e37-4167-b610-d2d7a306a04b | analyze                        | analyze                        | ACTIVE | 90      | 2026-05-29 23:29:21
- PASS: Remote ai_usage_logs telemetry columns — 2 row
- PASS: Remote telemetry check constraints — 2 row
- PASS: Recent AI usage route distribution — 1 row
- PASS: Recent AI errors — 1 row
- PASS: Remote analyze no-verify-jwt gateway bypass — {"error":"Geçersiz token.","message":"Geçersiz token.","code":"auth_invalid","request_id":"e153bf2b-9142-417e-9f91-5c0246a912ec","support_id":"RD-06598533","tier":null,"limit":null,"used":null,"feature":null}
- PASS: Canlı E2E temp kullanıcı email doğrulama — 0 row
- PASS: Canlı E2E auth session — temp user 0c81041e...
- PASS: Canlı E2E analiz kaydı — 9b183f1c-9684-4b11-8fe4-fcff26900c68
- PASS: Canlı E2E analyze invoke — queued
- PASS: Canlı E2E worker manuel tetikleme — 1 row
- PASS: Canlı E2E analiz tamamlanma — 4 bulgu
- PASS: Canlı E2E free paid trial telemetry — {"user_plan":"free","quality_tier":"plus","ai_execution_route":"free_paid_trial","provider":"gemini","model":"gemini-2.5-flash","api_key_alias":"gemini_paid_primary","fallback_source":null,"total_tokens":4515,"http_status":200,"error":null,"error_code":null}
- PASS: Canlı E2E free paid trial Pro model kullanmadı — {"model":"gemini-2.5-flash","api_key_alias":"gemini_paid_primary"}
- PASS: Canlı E2E Plus tadı audit — {"model":"gemini-2.5-flash","sectors":[],"provider":"gemini","user_plan":"free","company_id":null,"input_mode":"text","request_id":"qa-free-paid-routing-1780100168040","support_id":"QA-FREE-PAID-1780100168040","max_hazards":14,"min_hazards":11,"company_name":null,"context_hash":"9937a70e9fdf","quality_tier":"plus","analysis_mode":"standard","api_key_alias":"gemini_paid_primary","hazard_classes":[],"prompt_version":"isg-photo-personalized-v2026-05-20","reference_mode":"short","audit_frequency":null,"fallback_source":null,"gemini_key_pool":"paid","groq_free_model":"meta-llama/llama-4-scout-17b-16e-instruct","totalTokenCount":4515,"promptTokenCount":2368,"certificate_class":null,"ai_execution_route":"free_paid_trial","inline_photo_count":0,"system_prompt_sent":"Sen Türkiye'de 20 yıllık saha deneyimi olan kıdemli bir İSG uzmanısın (A sınıfı). İnşaat, üretim, depo/lojistik, enerji, fabrika ve
- PASS: Canlı E2E ikinci free analiz kuyruğu — 202: {"ok":true,"status":"queued","analysis_id":"7f4e7260-66e0-472f-96ba-c0083e22abbd","queued_photo_count":0,"request_id":"qa-free-paid-routing-second-1780100168040","support_id":"QA-FREE-PAID-SECOND-1780100168040"}
- PASS: Canlı E2E ikinci analiz kota koruması — {"secondFinal":{"status":"failed","status_message":"Günde 1 ücretsiz analiz hakkın doldu. Destek kodu: QA-FREE-PAID-SECOND-1780100168040"},"secondUsageRows":[]}
- PASS: Canlı E2E temp queue cleanup — 0 row
- PASS: Canlı E2E temp kullanıcı cleanup — 0 row

## Notlar

- Temp cleanup email: qa-free-paid-routing-1780100168040@example.com; cleanup rows payload: []

