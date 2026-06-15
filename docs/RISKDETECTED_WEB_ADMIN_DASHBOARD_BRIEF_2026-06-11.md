# RiskDetected Web Admin Dashboard Brief

Hazırlanma tarihi: 2026-06-11
Kullanım amacı: Bu dosyayı GPT 5.5 Pro'ya vererek RiskDetected için iOS uygulamasına dokunmadan ayrı bir web admin/dashboard projesi tasarlatmak.

Bu belge bir uygulama geliştirme planı değildir. Mevcut Supabase şeması ve repo yapısı üzerinden, ayrı bir web dashboard hazırlanırken hangi veri alanlarına, ekranlara, güvenlik sınırlarına ve teknik kararlara ihtiyaç duyulacağını tarif eder.

## GPT 5.5 Pro'ya Verilecek Ana Talimat

RiskDetected iOS uygulamasına bu aşamada hiçbir müdahale yapılmayacak. Amaç, mevcut Supabase veritabanı ve mevcut Edge Function/Storage/Auth verileri üzerinden çalışan, web sitesinden auth ile erişilen, güvenli ve mümkünse ilk sürümü read-only olan bir admin dashboard tasarlamak.

Dashboard müşteri/kullanıcı takibi, analiz detayları, AI kullanım ve token takibi, abonelik/kota, destek, hukuki onaylar, silme talepleri, paywall funnel, rapor arşivi ve sistem sağlığı gibi tüm operasyonel verileri gösterecek şekilde kurgulanmalı.

Önemli güvenlik ilkeleri:

- Service role veya secret key browser'a asla gönderilmemeli.
- Admin verileri doğrudan public Supabase client ile tüm tablolardan okunmamalı.
- Web uygulamasında admin auth ayrı kontrol edilmeli. Sadece giriş yapmış normal kullanıcı olmak admin yetkisi sayılmamalı.
- Auth, profile, analiz, destek mesajları, raw AI response, fotoğraf yolları, şirket bilgileri ve KVKK/onay verileri hassas veri olarak ele alınmalı.
- İlk sürüm mümkünse read-only olmalı; kullanıcı silme, abonelik değiştirme, rapor/fotoğraf silme gibi write action'lar ayrı güvenlik ve audit olmadan açılmamalı.

## Mevcut Proje Bağlamı

Repo: RiskDetected iOS app + Supabase backend
Supabase project_id: `ppcrzemgiztzcgddbins`
Supabase config kaynağı: `supabase/config.toml`

Mevcut auth ayarları:

- Supabase Auth aktif.
- Email signup ve email confirmation aktif.
- Google ve Apple provider aktif.
- JWT expiry: 3600 saniye.
- Refresh token rotation aktif.
- TOTP MFA enroll/verify aktif.
- iOS deep link redirect mevcut: `io.supabase.riskdetected://login-callback`
- Web dashboard için production domain ve redirect URL'leri ayrıca eklenmeli.

Mevcut Edge Function'lar:

- `analyze` - AI analiz üretimi, `verify_jwt = false`, kendi auth doğrulaması yapıyor.
- `process-analysis-jobs` - background queue worker, `verify_jwt = false`, secret header ile korunuyor.
- `register-report` - rapor metadata kaydı.
- `generate-excel-report` - Excel rapor üretimi.
- `send-report-ready-notification`
- `send-welcome-email`
- `support-contact`
- `sync-revenuecat-subscription`
- `revenuecat-webhook`
- `request-account-deletion`
- `account-deletion-complete`
- `retention-cleanup`
- `send-push-notification`

## Dashboard İçin Önerilen Üst Seviye İskelet

Bu iskelet ekran ve özellik envanteridir; sıralı yapılacaklar listesi değildir.

1. **Güvenli Admin Girişi**
   - Website üzerinden Supabase Auth ile giriş.
   - Admin yetkisi için ayrı kontrol: `admin_users` tablosu, `auth.users.app_metadata.role`, veya server-side allowlist.
   - MFA zorunlu veya en azından desteklenmiş admin hesapları.
   - Session timeout, audit log, IP/user-agent kaydı.

2. **Executive Overview**
   - Bugün / 7 gün / 30 gün metrikleri.
   - Yeni kullanıcı sayısı.
   - Aktif kullanıcı tahmini.
   - Tamamlanan analiz sayısı.
   - Başarısız/queued analiz sayısı.
   - Üretilen PDF/XLSX rapor sayısı.
   - Toplam token ve tahmini AI maliyeti.
   - Aktif Plus/Pro abonelikler.
   - Açık destek talepleri.
   - Bekleyen hesap silme talepleri.

3. **Kullanıcılar**
   - Kullanıcı listesi.
   - Kullanıcı 360 detay sayfası.
   - Auth bilgisi: email, provider, created_at, last_sign_in_at, confirmed_at, banned/deleted durumu varsa.
   - Profile bilgisi: isim, telefon, unvan, sertifika no, firma, tier, avatar/logo path, hoş geldin email durumu.
   - Abonelik ve RevenueCat state.
   - Onboarding cevapları.
   - Kullanıcının analizleri, bulguları, raporları, AI token kullanımı, destek talepleri, hukuki onayları, silme talepleri.

4. **Analizler**
   - Analiz listesi ve detay sayfası.
   - Status: `pending`, `queued`, `analyzing`, `completed`, `failed`.
   - Analiz türü: photo/text.
   - Canvas, analysis_mode, company_id, created/completed timestamps.
   - AI summary, risk skorları, en yüksek risk bandı, finding_count.
   - Worker telemetry: queued_at, worker_started_at, worker_attempt_count, last_worker_error.
   - raw_ai_response hassas görüntüleme: varsayılan kapalı, role-gated.

5. **Bulgular ve Risk Görünümü**
   - Risk band dağılımı: critical/high/medium/low/unknown.
   - Fine-Kinney ve 5x5 skorları.
   - Kategori bazlı riskler.
   - En sık görülen risk kategorileri.
   - Responsible/deadline/is_resolved takibi.
   - Root cause ve recommended_measures alanları.
   - Fotoğraf bounding_box bağlantısı varsa görsel ilişkisi.

6. **Rapor Arşivi**
   - PDF/XLSX rapor listesi.
   - document_no, format, kind, method, storage_path, file_name, mime_type, size/page count.
   - request_id/support_id ile hata/destek izleme.
   - company_snapshot ve şirket bağlantısı.
   - Rapor üretim kotası ve usage_events ile ilişki.
   - Private Storage dosyaları için kısa süreli signed URL üretimi sadece server-side.

7. **AI Kullanım, Token ve Maliyet**
   - `ai_usage_logs` ana kaynak.
   - provider, model, tokens_in, tokens_out, cached_tokens, thoughts_tokens, total_tokens.
   - duration_ms, error, error_code, http_status.
   - user_plan, quality_tier, ai_execution_route.
   - prompt_version, personalization_version, context_hash.
   - request_id, support_id, api_key_alias, fallback_source, attempt_count.
   - Model/fallback başarı oranı.
   - Token ve tahmini maliyet grafikleri.
   - Not: Gerçek maliyet için model fiyat katalogu ayrıca tutulmalı; mevcut DB sadece token/route bilgisini tutuyor.

8. **Abonelik, Kota ve Gelir Operasyonu**
   - `user_subscriptions` state.
   - `subscription_events` raw RevenueCat webhook history.
   - `usage_events` kota ledger.
   - `profiles.tier` ve `user_subscriptions.tier/status` tutarlılığı.
   - Free/Plus/Pro kullanıcı dağılımı.
   - Aktif, trialing, grace_period, expired/inactive abonelikler.
   - Monthly report quota ve analysis quota kullanım görünümü.
   - RevenueCat app_user_id ve entitlement bilgileri.

9. **Paywall ve Conversion Funnel**
   - `paywall_events` ana kaynak.
   - Funnel session bazlı view -> cta_tap -> plan_select -> purchase_started -> purchase_succeeded/purchase_failed.
   - onboarding_v2 ve in_app kaynak ayrımı.
   - variant_id, segment_key, selected_tier, billing, product_identifier.
   - Purchase failure metadata analizi.

10. **Onboarding ve Segmentasyon**
    - `user_onboarding_answers` ana kaynak.
    - certificate_class, hazard_classes, sectors, audit_frequency, selected_plan.
    - raw_answers detayı.
    - Kullanıcı segmentleri ve paywall/retention/analysis başarısı ilişkisi.

11. **Şirketler**
    - `companies` ana kaynak.
    - Multi-company Plus/Pro özelliği.
    - name, hazard_class, logo_path, address, contact_person, department, default_responsible, default_due_days.
    - is_archived ayrımı.
    - Analiz ve raporlarda company_id / company_snapshot ilişkisi.

12. **Bildirimler**
    - `push_device_tokens`
    - `notification_preferences`
    - `notification_events`
    - Aktif token sayısı, environment, app_version, device_model.
    - Bildirim başarısızlıkları, last_failure_reason, sent/failed/skipped event'ler.
    - Analysis complete ve report ready push durumları.

13. **Destek ve Hata İzleme**
    - `support_requests` ana kaynak.
    - support_id ile `ai_usage_logs`, `reports`, Edge Function response ve user timeline ilişkisi.
    - sender bilgileri, subject/message, delivery_status, delivery_error.
    - Support request rate limit private tabloları mevcut.
    - Dashboardda support_id global search olmalı.

14. **Hukuki Onay ve KVKK**
    - `consents`
    - `legal_document_acknowledgements`
    - KVKK, kullanım koşulları, açık rıza, privacy version takibi.
    - accepted_at, seen_at, explicit accepted timestamps.
    - Legal storage bucket: `legal-documents`.
    - Hassas/audit amaçlı read-only ekran.

15. **Hesap ve Veri Silme Operasyonu**
    - `account_deletion_requests`
    - status: pending, processing, completed, cancelled, rejected.
    - requested_scope, target_user_id/email/hash.
    - processing_started_at, completed_at, processed_by, completion_error.
    - deleted_photo_objects, deleted_report_objects, deleted_logo_objects, deleted_avatar_objects, auth_user_deleted.
    - İlk dashboard sürümünde sadece takip; destructive action açılacaksa ayrı onay, audit, rate limit ve role gerektirir.

16. **Professional Progress**
    - `professional_progress_profiles`
    - `professional_progress_events`
    - `professional_progress_finding_classifications`
    - `professional_progress_competency_stats`
    - `professional_progress_badges`
    - `professional_progress_messages`
    - `professional_progress_weekly_summaries`
    - MDP, title progression, badges, competency dağılımı, haftalık özetler.

17. **Sistem Sağlığı ve Queue**
    - Queued/analyzing/failed analizler.
    - PGMQ `analysis_jobs` queue backlog gözlemi için admin SQL/RPC gerekebilir.
    - `process-analysis-jobs` worker attempt ve error alanları.
    - `retention-cleanup` sonucu.
    - Edge Function hataları Supabase logs veya log drain entegrasyonu ile okunabilir.

18. **Admin Audit ve Settings**
    - Dashboard içindeki her admin görüntüleme/arama/export/write action loglanmalı.
    - Saved filters, roles, column visibility, export permissions.
    - PII masking ayarları.

## Mevcut Supabase Veri Haritası

| Alan | Tablo/Kaynak | Dashboardda Kullanım |
| --- | --- | --- |
| Auth kullanıcıları | `auth.users` | Yeni üyeler, son giriş, email/provider, hesap durumu. Auth schema API'ye açık değildir; server-side erişim gerekir. |
| Uygulama profili | `public.profiles` | İsim, email, telefon, unvan, sertifika, firma, tier, quota, welcome email, avatar/logo. |
| Analizler | `public.analyses` | Kullanıcı analiz geçmişi, status, canvas, mode, risk summary, worker state, raw AI audit. |
| Fotoğraflar | `public.photos` | Analiz fotoğraf metadata, storage path, boyut, annotation, retention. |
| Bulgular | `public.findings` | Risk bulguları, skorlar, aksiyon, root cause, recommended measures. |
| Raporlar | `public.reports` | PDF/XLSX arşivi, document_no, storage, request/support ID, company snapshot. |
| AI usage | `public.ai_usage_logs` | Token, model, provider, latency, route, error, support_id, fallback, API key alias. |
| Abonelik | `public.user_subscriptions` | RevenueCat source of truth, tier/status/product/entitlement. |
| Abonelik eventleri | `public.subscription_events` | Webhook geçmişi, raw_event, event_type, environment. |
| Kota ledger | `public.usage_events` | Analiz/rapor kullanım hakları ve silinmiş içerik tombstone kayıtları. |
| Paywall funnel | `public.paywall_events` | Conversion eventleri, variant, segment, selected tier/billing. |
| Onboarding | `public.user_onboarding_answers` | Kullanıcı segmentasyonu ve kişiselleştirme bağlamı. |
| Şirketler | `public.companies` | Plus/Pro multi-company, şirket metadata, rapor/analiz ilişkisi. |
| Push tokens | `public.push_device_tokens` | Aktif cihazlar, notification health, app_version/device. |
| Notification prefs | `public.notification_preferences` | Kullanıcı bildirim izinleri ve progress summary tercihleri. |
| Notification events | `public.notification_events` | Gönderilen/başarısız bildirim geçmişi. |
| Destek | `public.support_requests` | Support inbox, support_id arama, mail delivery durumu. |
| Hukuki onaylar | `public.consents` | KVKK/terms/explicit consent kabul geçmişi. |
| Legal acknowledgements | `public.legal_document_acknowledgements` | Legal update notice/explicit consent audit. |
| Silme talepleri | `public.account_deletion_requests` | GDPR/KVKK veri silme takibi ve completion sonucu. |
| Professional progress | `public.professional_progress_*` | MDP, badges, competency stats, weekly summaries. |
| Audit logs | `public.audit_logs` | Uygulama içi önemli aksiyonlar için temel audit altyapısı. Mevcut kullanımı ayrıca doğrulanmalı. |
| Storage | `reports`, `logos`, `avatars`, `legal-documents` buckets | Dosya erişimi, signed URL, private/public ayrımı. |

## Kullanıcı 360 Sayfasında Gösterilecek Veriler

Bir kullanıcı detay ekranı aşağıdaki bloklardan oluşmalı:

- Kimlik: user_id, email, auth provider, created_at, last_sign_in_at, email confirmed status.
- Profile: full_name, initials, title, certificate_number, phone, company_name, company_logo_url, avatar_url, preferred_method.
- Plan: profiles.tier, user_subscriptions.tier/status/source/product_id/entitlement/current_period_ends_at.
- Aktivite özeti: son login, son analiz, son rapor, son AI request, son paywall event, son support request.
- Kullanım: tamamlanan analiz sayısı, failed analiz sayısı, toplam finding_count, toplam rapor, PDF/XLSX ayrımı.
- AI: toplam tokens_in/out/total, ortalama duration_ms, model dağılımı, error_count, fallback_count.
- Risk: critical/high/medium/low bulgu sayıları, en yüksek risk bandı, en sık kategori.
- Onboarding: certificate_class, hazard_classes, sectors, audit_frequency, selected_plan.
- Şirketler: aktif/arşivlenmiş şirketler, hazard_class dağılımı.
- Raporlar: document_no, format, created_at, storage_path, company_snapshot.
- Destek: support_requests ve support_id bağlantılı AI/report hataları.
- Legal: consent version ve legal acknowledgement durumu.
- Data deletion: açık/geçmiş silme talepleri.

## Aktif Kullanıcı Nasıl Hesaplanabilir?

Mevcut verilerle gerçek "uygulama session activity" birebir ölçülmüyor; iOS uygulamasına dokunmadan ancak proxy/tahmin metrikleri çıkarılabilir.

Önerilen aktif kullanıcı metrikleri:

- **Login active users**: `auth.users.last_sign_in_at` son 1/7/30 gün.
- **Product active users**: son 1/7/30 gün içinde şu tablolardan en az birinde event olan benzersiz user_id:
  - `analyses.created_at`
  - `reports.created_at`
  - `ai_usage_logs.created_at`
  - `paywall_events.created_at`
  - `usage_events.created_at`
  - `support_requests.created_at`
  - `push_device_tokens.last_registered_at`
  - `notification_events.created_at`
- **Activated users**: ilk `analyses.status = completed`.
- **Report activated users**: en az bir `reports` kaydı.
- **Paying active users**: aktif/trialing/grace_period Plus/Pro abonelik ve son 30 günde product activity.

Sınırlama: Ekran açma, app foreground, session duration, hangi tablarda gezdiği gibi telemetry mevcut değil. Bu bilgiler istenirse ileride iOS/web event instrumentation gerekir; bu aşamada kapsam dışı.

## Metrik Tanımları

| Metrik | Kaynak | Tanım |
| --- | --- | --- |
| Yeni üye | `auth.users.created_at` veya fallback `profiles.created_at` | Seçili tarih aralığında oluşturulan kullanıcı. |
| Onboarded user | `user_onboarding_answers.completed_at` | Onboarding v2 tamamlayan kullanıcı. |
| Completed analysis | `analyses.status = 'completed'` | Başarıyla tamamlanan analiz. |
| Failed analysis | `analyses.status = 'failed'` | AI veya DB hatası ile tamamlanamayan analiz. |
| Queue backlog | `analyses.status in ('queued','analyzing')` | Worker bekleyen veya çalışan analizler. |
| Avg analysis latency | `completed_at - started_at` veya `ai_usage_logs.duration_ms` | Analiz süresi. |
| Risk distribution | `findings.fk_band` ve `findings.m5_band` | Risk bandlarına göre bulgu sayısı. |
| Report count | `reports.created_at` | PDF/XLSX üretim sayısı. |
| AI token usage | `ai_usage_logs.tokens_in/out/total_tokens` | Kullanıcı/model/route bazlı token kullanımı. |
| AI error rate | `ai_usage_logs.error is not null` veya `http_status >= 400` | AI çağrısı hata oranı. |
| Fallback rate | `fallback_source is not null` | Model/API key fallback kullanım oranı. |
| Active subscription | `user_subscriptions.status in ('active','trialing','grace_period')` ve period geçerli | Ücretli aktiflik. |
| Paywall conversion | `paywall_events` funnel session | View -> purchase_succeeded dönüşümü. |
| Open support | `support_requests.delivery_status` ve iş akışı status yoksa created_at bazlı | Destek gelen kutusu. |
| Pending deletion | `account_deletion_requests.status = 'pending'` | İşlem bekleyen silme talebi. |

## AI Token ve Maliyet Ekranı Detayı

Mevcut `ai_usage_logs` alanları:

- `provider`
- `model`
- `tokens_in`
- `tokens_out`
- `cached_tokens`
- `thoughts_tokens`
- `total_tokens`
- `duration_ms`
- `error`
- `error_code`
- `http_status`
- `user_plan`
- `quality_tier`
- `ai_execution_route`
- `request_id`
- `support_id`
- `fallback_source`
- `api_key_alias`
- `attempt_count`
- `prompt_version`
- `personalization_version`
- `context_hash`
- `created_at`

Dashboard özellikleri:

- Günlük/haftalık/aylık token grafiği.
- Kullanıcı bazlı token toplamı.
- Model bazlı token ve latency.
- quality_tier ve ai_execution_route karşılaştırması.
- Prompt version bazlı başarı/hata oranı.
- API key alias bazlı hata oranı. Raw key asla gösterilmemeli.
- Support ID ile hızlı arama.
- Hata detaylarında PII/raw prompt varsayılan maskelenmeli.
- Tahmini maliyet için `model_pricing_catalog` gibi dashboard tarafında server-only config önerilir.

## Güvenlik ve Erişim Mimarisi

Önerilen yaklaşım:

- Web dashboard ayrı bir web app olsun. Örn. Next.js/Vercel veya mevcut website stack'i.
- Browser tarafında sadece publishable/anon key kullanılmalı.
- Tüm admin data sorguları server route/server action üzerinden dönmeli.
- Server tarafında Supabase secret/service role kullanılabilir ama sadece admin authorization check'ten sonra.
- Admin rol kontrolü müşteri `profiles.tier` alanına bağlı olmamalı.
- Admin yetkileri için önerilen model:
  - `owner`: tüm read/export/action yetkileri.
  - `support`: user lookup, support, analysis status, masked AI diagnostics.
  - `finance`: subscription, paywall, revenue-related exports.
  - `analyst`: aggregate metrics, no PII/raw content.
  - `legal_ops`: consents/deletion requests.
- Her admin sorgusu ve özellikle export/write action audit edilmeli.
- raw_ai_response, text_input, support message, phone/email, storage signed URL ve legal data role-gated olmalı.
- Export limitleri ve rate limit konmalı.

Supabase dokümanlarından doğrulanan önemli noktalar:

- RLS, exposed schema tablolarında etkin olmalı.
- Auth schema otomatik API'ye açık değildir; auth user verisi için server-side veya kendi public profile tablosu gerekir.
- Secret/service role key browser'da kullanılmamalıdır ve RLS'i bypass eder.
- Exposed API için grant + RLS birlikte düşünülmelidir.
- Auth verisiyle view oluşturulacaksa `security_invoker` veya grant kısıtı dikkate alınmalıdır.

Kaynaklar:

- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/auth/managing-user-data
- https://supabase.com/docs/guides/getting-started/api-keys
- https://supabase.com/docs/guides/api/securing-your-api
- https://supabase.com/docs/guides/auth/architecture

## Dashboard İçin Muhtemel Yeni Backend Nesneleri

Bu nesneler iOS app'e dokunmadan, ayrı dashboard backend'i veya Supabase migration'ı olarak düşünülebilir. Bunlar zorunlu değildir; GPT 5.5 Pro ihtiyaç ve güvenlik durumuna göre değerlendirmeli.

1. `admin_users`
   - user_id
   - role
   - is_active
   - allowed_scopes
   - created_at
   - created_by

2. `admin_audit_logs`
   - id
   - admin_user_id
   - action
   - target_type
   - target_id
   - metadata
   - ip_hash
   - user_agent_hash
   - created_at

3. `admin_saved_filters`
   - admin_user_id
   - resource
   - name
   - filter_json

4. `model_pricing_catalog`
   - provider
   - model
   - effective_from
   - input_price_per_million
   - output_price_per_million
   - cached_price_per_million
   - thoughts_price_per_million
   - currency

5. Read-optimized views/materialized views
   - `admin_user_overview`
   - `admin_daily_user_metrics`
   - `admin_daily_analysis_metrics`
   - `admin_daily_ai_usage_metrics`
   - `admin_subscription_overview`
   - `admin_support_inbox`

Güvenlik notu: Bu view'lar public schema altında exposed API'ye açılacaksa RLS/security_invoker/grants çok dikkatli tasarlanmalı. Daha güvenli seçenek, server-only SQL queries veya private/admin schema kullanmaktır.

## Global Search İhtiyacı

Dashboardda tek bir arama alanı olmalı:

- email
- user_id
- support_id
- request_id
- analysis_id
- report document_no
- report storage_path
- RevenueCat app_user_id
- subscription event_id

Arama sonuçları resource type'a göre gruplanmalı. PII aramalar audit edilmeli.

## Filtre ve Segmentler

Standart filtreler:

- Tarih aralığı.
- Tier: free/plus/pro.
- Subscription status.
- Country/timezone yok; mevcut DB'de yok.
- App version: push token veya consent/app_version kayıtlarından kısmi alınabilir.
- Analysis status.
- Analysis kind: photo/text.
- Analysis mode: standard/detailed/emergency/procedure.
- Canvas.
- Company hazard_class.
- Risk band.
- AI provider/model/route.
- Prompt version.
- Paywall variant/segment.
- Onboarding certificate/sectors/hazard_classes.

## Storage ve Dosya Görüntüleme

Mevcut bucket'lar:

- `reports` private: PDF/XLSX rapor dosyaları.
- `logos` private: profil/firma logoları.
- `avatars` private: profil avatarları.
- `legal-documents` public: hukuki doküman markdown/json/plain.
- Photo bucket policy migrations içinde `photos` bucket politikaları var; foto storage path `photos.storage_path` üzerinden takip edilmeli.

Dashboard kuralları:

- Private dosyalar browser'a kalıcı public URL ile açılmamalı.
- Server kısa ömürlü signed URL üretmeli.
- Export/download action audit edilmeli.
- Fotoğraf ve raw AI content role-gated olmalı.

## Veri Gizliliği ve KVKK Notları

Dashboard çok fazla kişisel ve iş güvenliği verisi göstereceği için:

- Email/telefon varsayılan maskeli gösterilebilir.
- Support mesajları ve raw AI response sadece gerekli role açık olmalı.
- Fotoğraflar ve annotations hassas saha görüntüsü sayılmalı.
- `raw_ai_response` içinde prompt, context ve model cevabı bulunabilir; debug için değerli ama privacy açısından riskli.
- Account deletion tamamlanmış kullanıcılar için null/set-null edilmiş ilişkiler ve hash alanları dikkate alınmalı.
- Export dosyalarında PII kolon seçimi role ile sınırlandırılmalı.

## Sınırlamalar ve Bilinmeyenler

Bu belge repo ve migration dosyaları okunarak hazırlandı; canlı production DB satırları sorgulanmadı.

Mevcut verilerle kesin olarak bilinmeyenler:

- Gerçek production row count ve data volume.
- Mevcut website stack'i.
- Admin kullanıcısı olacak kişiler ve role ihtiyacı.
- Dashboardda write action istenip istenmeyeceği.
- AI modellerinin güncel fiyatları.
- Supabase logs/log drains erişimi.
- RevenueCat dashboard/API erişimi.
- Aktif kullanıcıyı session seviyesinde ölçen event yok.
- Ülke/şehir/device analytics gibi bilgiler sınırlı veya yok.

## GPT 5.5 Pro'dan Beklenen Çıktı Şekli

GPT 5.5 Pro bu belgeyi aldıktan sonra:

- iOS app'e dokunmadan ayrı web admin/dashboard mimarisi önermeli.
- Önce read-only ve güvenli data access yaklaşımını netleştirmeli.
- Auth/admin authorization modelini seçmeli.
- Dashboard ekranlarını, route yapısını, data query/view ihtiyacını ve riskleri çıkarmalı.
- Eğer implementation plan istenecekse bunu ayrı bir dosyada yapmalı; bu brief'in kendisini plan gibi kullanmamalı.
- Eksik bilgi gerekiyorsa özellikle website stack, hosting, admin rolleri ve canlı Supabase erişim yöntemini sormalı.

## Repo Kaynakları

Bu brief hazırlanırken incelenen ana dosyalar:

- `supabase/config.toml`
- `supabase/migrations/20260503075849_02_profiles.sql`
- `supabase/migrations/20260503075909_03_analyses_and_photos.sql`
- `supabase/migrations/20260503075933_04_findings.sql`
- `supabase/migrations/20260503075950_05_reports_and_audit.sql`
- `supabase/migrations/20260504063219_ai_usage_logs.sql`
- `supabase/migrations/20260506193000_reports_storage.sql`
- `supabase/migrations/20260506192136_consents.sql`
- `supabase/migrations/20260508022421_account_deletion_requests.sql`
- `supabase/migrations/20260510002500_push_notifications.sql`
- `supabase/migrations/20260513101505_free_plus_pro_subscription_system.sql`
- `supabase/migrations/20260517221931_add_support_requests.sql`
- `supabase/migrations/20260520083317_add_onboarding_answers.sql`
- `supabase/migrations/20260520154818_add_companies.sql`
- `supabase/migrations/20260522085000_add_paywall_events.sql`
- `supabase/migrations/20260526093512_professional_progress_module.sql`
- `supabase/migrations/20260602072506_legal_document_updates.sql`
- `supabase/migrations/20260606120000_global_report_document_counter.sql`
- `supabase/migrations/20260606130000_durable_usage_events_for_deleted_content.sql`
- `supabase/functions/analyze/index.ts`
- `supabase/functions/revenuecat-webhook/index.ts`
- `supabase/functions/support-contact/index.ts`
- `supabase/functions/process-analysis-jobs/index.ts`
- `supabase/functions/register-report/index.ts`
- `supabase/functions/request-account-deletion/index.ts`
- `supabase/functions/send-push-notification/index.ts`
- `supabase/functions/send-report-ready-notification/index.ts`
- `supabase/functions/sync-revenuecat-subscription/index.ts`
- `App/Services/AuthService.swift`
- `App/Services/AnalysisService.swift`
- `App/Services/PaywallEventService.swift`
- `App/Services/SubscriptionManager.swift`
- `App/Services/CompanyService.swift`
- `App/Services/NotificationService.swift`
- `App/Services/SupportService.swift`
- `App/Services/LegalAcceptanceService.swift`
- `App/Services/OnboardingAnswersService.swift`
- `App/Services/RDConfig.swift`
