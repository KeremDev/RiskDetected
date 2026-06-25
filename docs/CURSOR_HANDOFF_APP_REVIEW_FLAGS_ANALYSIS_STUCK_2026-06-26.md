# Cursor Handoff: App Review/TestFlight Flag Sistemi ve 5 Foto Analiz Takılma Analizi

Son güncelleme: 2026-06-26
Repo: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected`

Bu dosya Cursor'a verilecek teknik bağlamdır. Amaç, App Review süresince canlı sürümü kırmadan TestFlight/build bazlı özellik açma sistemini, ilgili migration sırasını ve 5 foto analizde "backend tamamlandı ama uygulama analiz ekranında kaldı" problemini eksiksiz aktarmaktır.

## 1. Mevcut Canlı Durum

Canlı Supabase `public.app_feature_flags` durumu 2026-06-26 itibarıyla:

```json
{
  "ios_release_policy": {
    "minimum_supported_build": 62,
    "latest_build": 72,
    "hard_update_enabled": false,
    "soft_update_enabled": true,
    "policy_version": "build-72-testflight"
  },
  "multi_photo_analysis": {
    "kill_switch": false,
    "rollout_mode": "build_allowlist",
    "enabled_ios_builds": ["63", "64", "65", "66", "67", "68", "69", "70", "71", "72"],
    "features": {
      "multi_photo_analysis": true,
      "multi_photo_coverage_v2": true,
      "photo_limit_locked_slots_for_free": true,
      "plus_pro_5_photo_limit": true,
      "editable_findings": true,
      "manual_finding_add": false,
      "report_snapshot_v2": true
    },
    "enable_multi_photo_analysis": false,
    "enable_multi_photo_coverage_v2": false,
    "enable_photo_limit_locked_slots_for_free": false,
    "enable_plus_pro_5_photo_limit": false,
    "enable_editable_findings": false,
    "enable_manual_finding_add": false,
    "enable_report_snapshot_v2": false,
    "max_photo_count_free": 1,
    "max_photo_count_plus": 5,
    "max_photo_count_pro": 5,
    "target_findings_per_photo_min": 5,
    "target_findings_per_photo_max": 8,
    "target_findings_total_max": 40,
    "coverage_repair_enabled": true
  }
}
```

iOS tarafı build numarası:

- `RiskDetected.xcodeproj/project.pbxproj`: `CURRENT_PROJECT_VERSION = 72`
- `MARKETING_VERSION = 1.2.0`
- `App/AppState.swift` fallback `AppReleasePolicy.latestBuild = 72`

Önemli not: Ayrım environment bazlı değil, build-number allowlist bazlıdır. Canlı backend aynı Supabase projesidir. `enabled_ios_builds` içinde olan build bu özellikleri alır; listede olmayan build almaz. App Review'deki build listede ise o da bu özellikleri alır. Bu yüzden yeni TestFlight build eklerken sadece yeni build numarası append edilmeli; `rollout_mode`, `kill_switch`, `minimum_supported_build` ve eski build listesi kontrolsüz değiştirilmemeli.

## 2. Flag Sisteminin Amacı

Bu sistem App Review/canlı stabilitesini koruyarak yeni TestFlight build'lerine kontrollü özellik açmak için kuruldu.

Kontrol katmanları:

1. `kill_switch`
   - `true` olursa multi-photo ve ilişkili yeni özellikler build listesine bakmadan kapanır.
   - Acil geri alma düğmesidir.

2. `rollout_mode`
   - Şu an `build_allowlist`.
   - Sadece `enabled_ios_builds` içindeki `CFBundleVersion` değerleri feature alır.

3. `enabled_ios_builds`
   - iOS build numaraları string olarak tutulur.
   - Şu an `63` ile `72` arası listede.
   - Yeni build için sadece yeni sayı append edilmeli.

4. `features`
   - Yeni kodun gerçek feature set'i buradan okunur.
   - `multi_photo_analysis`, `plus_pro_5_photo_limit`, `multi_photo_coverage_v2` gibi alanlar burada `true`.

5. Legacy flat `enable_*` alanları
   - Bilerek `false` tutuluyor.
   - Neden: Eski/pre-gate backend kodu deploy penceresinde bu flat alanları okuyup yanlışlıkla canlı/App Review build'lerine özellik açmasın.
   - Yeni kod `features + build gate` kombinasyonunu kullanır.

6. Plan capability rules
   - `public.plan_capability_rules`
   - `free`: `max_photos_per_analysis=1`, `can_use_multi_photo_analysis=false`
   - `plus/pro`: `max_photos_per_analysis=5`, `can_use_multi_photo_analysis=true`

## 3. Migration Sırası

İlgili migration'lar kronolojik olarak:

1. `20260622195418_multi_photo_editable_findings.sql`
   - `plan_capability_rules` tablosunu oluşturdu.
   - `app_feature_flags` tablosunu oluşturdu.
   - `multi_photo_analysis` flag kaydını seed etti.
   - Başlangıçta `kill_switch=true`, `rollout_mode=build_allowlist`, `enabled_ios_builds=["63","64","65","66"]`.
   - Legacy flat `enable_*` alanlarını `false` bıraktı.
   - `ios_release_policy` kaydını seed etti: `minimum_supported_build=62`, `latest_build=66`.
   - `analyses`, `photos`, `analysis_photo_summaries`, edit/report snapshot alanları gibi multi-photo altyapısını genişletti.

2. `20260625105240_allow_multi_photo_build_67.sql`
   - `enabled_ios_builds` içine `67` eklendi.

3. `20260625111151_grant_authenticated_analyses_write.sql`
   - `public.analyses` için `authenticated` role'a `insert, update` grant edildi.
   - Bu, client tarafında analiz kaydı oluşturma/failed işaretleme gibi akışlar için gerekliydi.

4. `20260625112128_allow_multi_photo_build_68.sql`
   - `enabled_ios_builds` içine `68` eklendi.
   - `ios_release_policy.latest_build=68`, `policy_version=build-68-testflight`.

5. `20260625122643_allow_multi_photo_build_69.sql`
   - `enabled_ios_builds` içine `69` eklendi.
   - `ios_release_policy.latest_build=69`, `policy_version=build-69-testflight`.

6. `20260625141400_allow_multi_photo_build_70.sql`
   - `enabled_ios_builds` içine `70` eklendi.
   - `ios_release_policy.latest_build=70`, `policy_version=build-70-testflight`.

7. `20260625191650_multi_photo_coverage_v2.sql`
   - `analysis_photo_summaries` içine coverage kolonları eklendi:
     - `coverage_status`
     - `coverage_gap_reason`
     - `target_findings_min`
     - `target_findings_max`
   - `multi_photo_analysis.features.multi_photo_coverage_v2=true`
   - `enable_multi_photo_coverage_v2=false` bilerek legacy flat kapalı kaldı.
   - `target_findings_per_photo_min=5`, `target_findings_per_photo_max=8`, `target_findings_total_max=40`.
   - `coverage_repair_enabled=true`.
   - Rollout notu: `Requires client_capabilities.multi_photo_coverage_v2=true; legacy builds stay on hazards[] flow.`

8. `20260625195630_allow_multi_photo_build_71.sql`
   - `enabled_ios_builds` içine `71` eklendi.
   - `ios_release_policy.latest_build=71`, `policy_version=build-71-testflight`.

9. `20260625212844_allow_multi_photo_build_72.sql`
   - `enabled_ios_builds` içine `72` eklendi.
   - `ios_release_policy.latest_build=72`, `policy_version=build-72-testflight`.

Yeni build ekleme pattern'i:

```bash
SUPABASE_TELEMETRY_DISABLED=1 node scripts/rd_ops_env.mjs supabase migration new allow_multi_photo_build_73
```

Migration SQL pattern'i:

```sql
update public.app_feature_flags
set value = jsonb_set(
    value,
    '{enabled_ios_builds}',
    (
      select jsonb_agg(distinct build order by build)
      from jsonb_array_elements_text(
        coalesce(value->'enabled_ios_builds', '[]'::jsonb) || '["73"]'::jsonb
      ) as build
    ),
    true
  ),
  updated_at = now()
where key = 'multi_photo_analysis';

update public.app_feature_flags
set value = jsonb_set(
    jsonb_set(value, '{latest_build}', '73'::jsonb, true),
    '{policy_version}',
    to_jsonb('build-73-testflight'::text),
    true
  ),
  updated_at = now()
where key = 'ios_release_policy';
```

Sonra canlıya uygulama:

```bash
SUPABASE_TELEMETRY_DISABLED=1 node scripts/rd_ops_env.mjs supabase db query --linked --file supabase/migrations/<migration>.sql --output json
```

## 4. Client Feature Gate Akışı

İlgili dosyalar:

- `App/AppState.swift`
- `App/Services/AnalysisService.swift`
- `supabase/functions/analyze/index.ts`
- `supabase/functions/register-report/index.ts`
- `supabase/functions/generate-excel-report/index.ts`
- `supabase/functions/mutate-analysis-finding/index.ts`

iOS client metadata:

- `AppClientMetadata.appBuild`: `CFBundleVersion`
- `AppClientMetadata.capabilities`:
  - `multi_photo_analysis=true`
  - `multi_photo_coverage_v2=true`
  - `editable_findings=true`
  - `report_snapshot_v2=true`

App tarafında remote capability hesaplama:

- `AppState.loadRemotePlanCapabilities(for:)`
- `plan_capability_rules` + `app_feature_flags.multi_photo_analysis` birlikte okunur.
- Paid user olsa bile build gate kapalıysa multi-photo açılmaz.
- Paid user + build allowlist + feature true ise 5 foto slotu açılır.

Backend tarafında:

- `analyze/index.ts` build gate'i `kill_switch`, `rollout_mode`, `enabled_ios_builds`, `min_ios_build`, client capabilities ve plan capability ile birlikte değerlendirir.
- `coverage_v2` sadece multi-photo + paid capability + build gate + client capability olduğunda aktif olur.
- Legacy build'ler `hazards[]` akışında kalır.

## 5. 5 Foto Analizde Yaşanan Problemler ve Kök Nedenler

### Problem A: 5 foto tek JSON/base64 request olarak gönderiliyordu

İlk kök problem mobil istemcinin 5 fotoğrafı base64 JSON içinde tek Edge Function request'ine gömmesiydi. Bu büyük payload, mobil ağ/gateway/timeout seviyesinde kopabiliyordu.

Semptomlar:

- Analiz ekranı erken fazda kalıyordu.
- `Bağlantı tekrar deneniyor` mesajı görülebiliyordu.
- `analyses` kaydı açılmış olsa bile Edge Function çağrısı client tarafında hata gibi algılanabiliyordu.

Kalıcı çözüm:

- `runPhotoAnalysis` artık fotoğrafları önce private Supabase Storage'a yüklüyor.
- Path formatı: `photos/{user_id}/{analysis_id}/p{index}.jpg`
- `public.photos` metadata satırları yazılıyor.
- Edge Function'a inline base64 yerine `photo_paths` gönderiliyor.
- `photoBase64Parts: []` ile inline payload kapatılıyor.
- Hata durumunda upload edilmiş objeler ve metadata temizleniyor; analiz `failed` işaretleniyor.

Kod referansı:

- `App/Services/AnalysisService.swift`
  - `runPhotoAnalysis`: analiz kaydı, upload, invoke, poll akışı
  - `uploadPhotosForAnalysis`
  - `cleanupUploadedPhotos`
  - `recoverPhotoSubmissionIfServerAccepted`

### Problem B: Backend tamamlandı ama uygulama %61 analiz ekranında kaldı

Bu en kritik problemdi. Sonradan canlı DB kanıtı şunu gösterdi:

- Backend/AI işi tamamlamıştı.
- `analyses.status=completed`
- `photo_count=5`
- `photos=5`
- `findings >= 25`
- Queue boş veya aktif worker beklemiyordu.
- Buna rağmen iOS ekranı `%61` civarında "Analiz kuyruğa alındı..." / "KKD ve çevresel kontroller" fazında kalabiliyordu.

Kök neden tek bir yer değildi; client tarafında birkaç zayıf noktanın birleşimiydi:

1. Polling status-first değildi.
   - Eski mantık bazı noktalarda sonucu/hidrasyonu öne alabiliyordu.
   - `photos` veya `analysis_photo_summaries` gibi opsiyonel verilerde decode/RLS/timeout olursa sonuç ekranı bloklanabiliyordu.

2. `AnalyzingView` lifecycle cancellation fazla agresifti.
   - `onDisappear` koşulsuz veya çok geniş şekilde `workTask?.cancel()` yapabiliyordu.
   - Kullanıcı Control Center açtığında, başka uygulamaya geçtiğinde, scene geçişi olduğunda veya SwiftUI sheet lifecycle yeniden kurulduğunda iş task'i iptal olabiliyordu.
   - Backend analiz tamamlanmış olsa bile app tarafındaki closure sonuca ulaşmadan iptal edildiği için ekran eski progress state'inde kalabiliyordu.

3. Push notification ana garanti gibi düşünülüyordu.
   - Gerçek cihazda token yoksa veya bildirim izni/token sync yoksa `analysis_complete` event `skipped/no_active_device_tokens` olabiliyor.
   - Bu yüzden sonucu göstermenin ana garantisi push değil, in-app resume/polling olmalıydı.

4. Tamamlanan analizde bulgular anlık boş okunursa kullanıcı sonsuz loading'de kalmamalıydı.
   - `finding_count > 0` iken `findings` boş dönerse kısa retry yapılmalı.
   - Hala boşsa net hata verilmeli veya geçmişten tekrar açılabilmeli; `%61` ekranında sessiz bekleme olmamalı.

## 6. %61 Takılma İçin Yapılan Kalıcı iOS Fix'leri

### 6.1 Status-first polling

Yeni yapı:

- Önce sadece `analyses` status snapshot okunur.
- Snapshot alanları:
  - `status`
  - `finding_count`
  - `photo_count`
  - `status_message`
  - `queued_at`
  - `worker_started_at`
  - `completed_at`
  - `updated_at`

Kod:

- `AnalysisService.fetchAnalysisStatusSnapshot`
- `AnalysisService.waitForCompletedResult`

Akış:

- `pending/queued` -> progress `.queued`
- `analyzing` -> progress `.analyzing`
- `completed` -> progress `.finalizingResult`, sonra result hydration
- `failed` -> görünür hata

### 6.2 Result hydration split edildi

Yeni yapı:

- `fetchResultCore`: zorunlu `analysis + findings`
- `fetchOptionalPhotos`: opsiyonel
- `fetchOptionalPhotoSummaries`: opsiyonel

Opsiyonel fetch hata verirse sonuç ekranı bloklanmaz; boş listeyle devam edilir. Bu, "analiz tamamlandı ama foto özet decode/RLS hatası yüzünden loading ekranında kalma" riskini azaltır.

### 6.3 Completed + findings boş ise kısa retry

Kod:

- `AnalysisService.fetchResultCore`

Mantık:

- `analysis.status == completed`
- `expectedFindingCount > 0`
- `findings.isEmpty`

Bu durumda 3 kısa retry yapılır. Hala boşsa net hata:

```text
Analiz sonucu hazır ama bulgular yüklenemedi. Lütfen Geçmiş analizlerden tekrar açmayı dene.
```

### 6.4 In-flight resume store

Yeni yapı:

- `InFlightAnalysisStore`
- UserDefaults key: `rd.analysis.inFlight.v1`
- TTL: 30 dakika
- Analiz kaydı oluşur oluşmaz saklanır:
  - `analysisID`
  - `userID`
  - `photoCount`
  - `startedAt`
  - `title`
  - `kind`

Tamamlanınca/failed olunca/TTL aşınca temizlenir.

Resume:

- `AnalysisService.resumeAnalysis(analysisID:onProgress:)`
- Upload yapmaz.
- Edge Function çağırmaz.
- Sadece status-first polling + result hydration yapar.

Home foreground resume:

- `HomeView.resumeInFlightAnalysisIfNeeded`
- `scenePhase == .active` olduğunda in-flight varsa aynı `analysisID` ile AnalyzingView açar.
- Yeni analiz oluşturmaz.
- Fotoğraf tekrar upload etmez.

### 6.5 Notification routing sonucu doğrudan açıyor

Önceki davranış:

- Push gelince sadece Analizler/Geçmiş sekmesine gitme eğilimi vardı.

Yeni davranış:

- `AppState.pendingAnalysisResultID`
- `routePendingNotificationIfReady` ilgili `analysisID` için Home'a route eder.
- `HomeView.openPendingAnalysisResultIfNeeded` sonucu direkt açar.

Push artık yardımcı sinyal. Ana garanti in-app resume.

### 6.6 `finalizingResult` progress fazı

Yeni faz:

- `AnalysisProgressPhase.finalizingResult`

UI etkisi:

- `%94-98` bandında "Sonuç hazırlanıyor"
- `100%` sadece sonuç gerçekten geldiğinde kısa kapanış animasyonu olarak gösterilir.

Bu, backend tamamlandıktan sonra hydration sırasında kullanıcının "takıldı mı?" kaygısını azaltır.

## 7. Multi-photo Coverage v2 ve Foto Başına Bulgu Hedefi

Başka bir problem: 5 foto analizde toplam bulgu sayısı tek foto analiz kadar kalabiliyordu. Bu kullanıcı değeri açısından yetersizdi.

Yeni hedef:

- Aksiyonlanabilir risk kanıtı olan her fotoğrafta en az 5 bulgu.
- Temiz/kalitesiz/risk kanıtı zayıf fotoğrafta bulgu uydurulmaz; `coverage_gap_reason` ile açıklanır.

Canlı ayarlar:

- `target_findings_per_photo_min=5`
- `target_findings_per_photo_max=8`
- `target_findings_total_max=40`
- `coverage_repair_enabled=true`
- `features.multi_photo_coverage_v2=true`

Son başarılı E2E kanıtı:

- `analysis_id=d0be18d9-c5c0-48e3-8e30-b3875d9c0b50`
- `status=completed`
- `photo_count=5`
- `photos_count=5`
- `summaries_count=5`
- `finding_count=29`
- `audit_storage_photo_count=5`
- `audit_inline_photo_count=0`
- `audit_coverage_v2=true`
- `last_worker_error=null`
- Timestamp:
  - `queued_at=2026-06-25 21:21:58.138+00`
  - `worker_started_at=2026-06-25 21:21:58.787+00`
  - `completed_at=2026-06-25 21:23:05.713+00`

Fotoğraf başı son dağılım daha önce doğrulandı:

- Foto 1: 5 bulgu
- Foto 2: 6 bulgu
- Foto 3: 6 bulgu
- Foto 4: 6 bulgu
- Foto 5: 6 bulgu

## 8. Push Notification Bulgusu

E2E sırasında notification event:

- `kind=analysis_complete`
- `status=skipped`
- `last_error=no_active_device_tokens`

Bu simülatör/QA hesabı için beklenen durumdu çünkü `push_device_tokens` boştu.

Sonuç:

- Push, sonuç gösteriminin garantisi değildir.
- Gerçek garanti: in-app `InFlightAnalysisStore` + status-first resume.
- Gerçek cihazda push testi için `push_device_tokens` aktif olmalı ve bildirim izni verilmiş olmalı.

NotificationService tarafında token sync logları eklendi:

- `reason=no_user`
- `reason=not_authorized`
- `Push token sync requested`
- token save environment log

## 9. E2E ve Build Doğrulama

Gerçek 5 foto E2E testi:

- Test: `RiskDetectedUITests.testE2ERealFivePhotoAnalysisCompletes`
- Dosya: `RiskDetectedUITests/RiskDetectedUITests.swift`
- Beklentiler:
  - `analysis.loading`
  - `analysis.progress.percent`
  - `5 fotoğraf`
  - başlangıçta `100` görünmez
  - en geç 420 saniye içinde `Analiz Sonucu`

Önemli: `xcodebuild` shell env'lerini XCTest test process'e direkt taşımadığı için bare `RD_E2E_*` env ile test skip edebilir. Çalışan pattern:

```bash
rm -rf /tmp/rd_e2e_5photo_latest.xcresult
LOG=/tmp/rd_e2e_5photo_latest.log
: > "$LOG"
EMAIL="$(security find-generic-password -a "$USER" -s riskdetected_e2e_email -w)"
PASSWORD="$(security find-generic-password -a "$USER" -s riskdetected_e2e_password -w)"

TEST_RUNNER_RD_E2E_REAL_5_PHOTO_ANALYSIS=1 \
TEST_RUNNER_RD_E2E_EMAIL="$EMAIL" \
TEST_RUNNER_RD_E2E_PASSWORD="$PASSWORD" \
xcodebuild \
  -project RiskDetected.xcodeproj \
  -scheme RiskDetected \
  -destination 'id=D961FE19-785D-4CF8-A0CB-3F5B3CD5F979' \
  -only-testing:RiskDetectedUITests/RiskDetectedUITests/testE2ERealFivePhotoAnalysisCompletes \
  -resultBundlePath /tmp/rd_e2e_5photo_latest.xcresult \
  -quiet test > "$LOG" 2>&1
```

Başarılı koşu:

- `testE2ERealFivePhotoAnalysisCompletes() Success`
- Süre: yaklaşık `86.2s`
- `testsCount=1`
- skip/failure yok

Release build doğrulama:

```bash
xcodebuild \
  -project RiskDetected.xcodeproj \
  -scheme RiskDetected \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -quiet build
```

Build 72 için doğrulama sonucu:

- `RD_RELEASE_BUILD_72_STATUS=0`

## 10. Supabase Sorgu Komutları

Keychain kontrol:

```bash
node scripts/rd_ops_env.mjs status
```

Canlı flag kontrol:

```bash
SUPABASE_TELEMETRY_DISABLED=1 node scripts/rd_ops_env.mjs supabase db query --linked --output json "
select key, value
from public.app_feature_flags
where key in ('multi_photo_analysis','ios_release_policy')
order by key;
"
```

Son E2E analiz kontrol:

```bash
SUPABASE_TELEMETRY_DISABLED=1 node scripts/rd_ops_env.mjs supabase db query --linked --output json "
select id, title, status, photo_count, finding_count,
       queued_at, worker_started_at, completed_at, last_worker_error,
       (select count(*) from public.photos p where p.analysis_id = a.id)::int as photos_count,
       (select count(*) from public.analysis_photo_summaries aps where aps.analysis_id = a.id)::int as summaries_count,
       coalesce((a.raw_ai_response->'_input_audit'->>'storage_photo_count')::int, 0)::int as audit_storage_photo_count,
       coalesce((a.raw_ai_response->'_input_audit'->>'inline_photo_count')::int, -1)::int as audit_inline_photo_count,
       coalesce((a.raw_ai_response->'_input_audit'->>'coverage_v2')::boolean, false) as audit_coverage_v2,
       created_at
from public.analyses a
where title like 'E2E 5 Fotoğraf Storage %'
order by created_at desc
limit 3;
"
```

Fotoğraf başı coverage kontrol:

```bash
SUPABASE_TELEMETRY_DISABLED=1 node scripts/rd_ops_env.mjs supabase db query --linked --output json "
select photo_sequence_index, coverage_status, candidate_findings_count,
       generated_findings_count, target_findings_min, target_findings_max,
       coverage_gap_reason
from public.analysis_photo_summaries
where analysis_id = '<analysis_id>'
order by photo_sequence_index;
"
```

Kaynak foto dağılımı:

```bash
SUPABASE_TELEMETRY_DISABLED=1 node scripts/rd_ops_env.mjs supabase db query --linked --output json "
select source_photo_indices::text as source_photo_indices, count(*)::int
from public.findings
where analysis_id = '<analysis_id>'
group by source_photo_indices
order by source_photo_indices::text;
"
```

Push event kontrol:

```bash
SUPABASE_TELEMETRY_DISABLED=1 node scripts/rd_ops_env.mjs supabase db query --linked --output json "
select id, kind, status, sent_count, failure_count, last_error,
       sent_at, created_at, data->>'analysis_id' as event_analysis_id
from public.notification_events
where data->>'analysis_id' = '<analysis_id>'
order by created_at desc;
"
```

Supabase CLI notu:

- CLI paralel çalıştırıldığında bazen `~/.supabase/telemetry.json.tmp... rename` hatası verebiliyor.
- Bu yüzden DB sorgularında `SUPABASE_TELEMETRY_DISABLED=1` kullanmak ve Supabase CLI komutlarını paralel koşturmamak daha güvenli.

## 11. Gizli Bilgiler ve Keychain

Bu repo/dokümanda secret yazılmamalı.

Kullanılan Keychain service isimleri:

- `riskdetected_supabase_access_token`
- `riskdetected_supabase_db_password`
- `riskdetected_revenuecat_rest_api_key`
- `riskdetected_e2e_email`
- `riskdetected_e2e_password`

E2E email/password chat'e veya dokümana yazılmamalı; komutlarda Keychain'den okunmalı.

## 12. Cursor İçin Kritik Kurallar

1. Eski canlı/App Review build'lerini korumak için:
   - `minimum_supported_build` değiştirme.
   - `hard_update_enabled` açma.
   - `rollout_mode=all` yapma.
   - `kill_switch` değerini bilmeden değiştirme.
   - `enabled_ios_builds` listesinden eski build silme.

2. Yeni build açarken:
   - Xcode `CURRENT_PROJECT_VERSION` güncelle.
   - `AppReleasePolicy.fallback.latestBuild` güncelle.
   - `supabase migration new allow_multi_photo_build_<build>` ile migration oluştur.
   - `enabled_ios_builds` içine sadece yeni build'i append et.
   - `ios_release_policy.latest_build` ve `policy_version` güncelle.
   - Canlı DB'ye migration SQL'ini uygula.
   - Canlı flag sorgusuyla doğrula.
   - Release build al.

3. 5 foto analiz akışında:
   - Inline base64 fallback kaldırılmamalı ama yeni multi-photo akışında `photo_paths` kullanılmalı.
   - `photoBase64Parts` yeni multi-photo storage akışında boş kalmalı.
   - Upload failure durumunda storage/metadata cleanup korunmalı.
   - `recoverPhotoSubmissionIfServerAccepted` korunmalı; client invoke error alsa bile server DB status ilerlediyse aynı analize devam etmeli.

4. `%61 takıldı` regresyonunu önlemek için:
   - `waitForCompletedResult` status-first kalmalı.
   - `fetchResultCore` zorunlu, photos/summaries opsiyonel kalmalı.
   - `InFlightAnalysisStore` kaldırılmamalı.
   - `resumeAnalysis` yeni upload/invoke yapmamalı.
   - `AnalyzingView.onDisappear` eski agresif cancel davranışına döndürülmemeli.
   - `finalizingResult` fazı korunmalı.

5. Push için:
   - Push sonucu göstermenin ana garantisi yapılmamalı.
   - Deep link/pending analysis ID direkt sonucu açmalı.
   - Token yoksa `no_active_device_tokens` beklenen teşhistir; analiz başarısızlığı değildir.

## 13. Bilinen Dikkat Noktaları

- `supabase/functions/app-release-policy/index.ts` içinde source-level `DEFAULT_POLICY.latest_build` bazı yerlerde `71` görünebilir. Canlı DB `ios_release_policy.latest_build=72` olduğu için normal akışta DB değeri belirleyicidir. Yine de ileride bu function source'u deploy edilecekse fallback default da yeni build'e güncellenmeli.
- `supabase/functions/app-release-policy/index_static_test.ts` source default'ları assert ediyor olabilir; build default güncellenirse test expectation da güncellenmeli.
- `enabled_ios_builds` string array olarak tutuluyor. Bazı migration'larda string order, bazılarında integer order kullanıldı. Bugünkü canlı sonuç doğru: `63`-`72`.
- `kill_switch` başlangıç migration'ında `true` seed edilmişti; canlıda şu an `false`. Bu değer operasyonel flag'dir, yeni build migration'ında elle değiştirilmemeli.
- App Review ve TestFlight ayrımı sadece allowlist ile yapılır. Aynı canlı backend'i kullandıkları için listede olan build'ler aynı remote özellikleri alır.

## 14. Son Sağlam Kabul Kriteri

Yeni build/TestFlight öncesi "tamam" demek için minimum:

1. Xcode build no doğru:
   - `CURRENT_PROJECT_VERSION=<build>`

2. Canlı flag doğru:
   - `enabled_ios_builds` yeni build'i içeriyor.
   - `kill_switch=false` veya bilinçli operasyonel karar.
   - `rollout_mode=build_allowlist`.
   - `ios_release_policy.latest_build=<build>`.

3. Release build geçiyor:
   - `xcodebuild ... -configuration Release -destination 'generic/platform=iOS' build`

4. Gerçek 5 foto E2E geçiyor:
   - XCTest `testE2ERealFivePhotoAnalysisCompletes` success.
   - DB `status=completed`.
   - `photo_count=5`.
   - `photos=5`.
   - `summaries=5`.
   - `finding_count >= 25`.
   - `audit_storage_photo_count=5`.
   - `audit_inline_photo_count=0`.
   - `audit_coverage_v2=true`.
   - `last_worker_error is null`.
   - App `Analiz Sonucu` ekranına geçiyor; `%61` veya düşük yüzde loading'de kalmıyor.

