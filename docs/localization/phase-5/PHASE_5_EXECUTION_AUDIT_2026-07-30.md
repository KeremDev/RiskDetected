# RiskDetected Global Localization — Faz 5 Execution Audit

Tarih: 2026-07-30  
Son güncelleme: 2026-07-31  
Durum: **completed**  
Teknik kapsam: **completed**  
Sonraki faz: **Faz 6 başlatılabilir.**

## Kapanış özeti

Faz 5'in repository içindeki teknik uygulaması ve otomatik doğrulaması
tamamlandı. PDF/XLSX, notification, transactional push, e-posta, support,
legal runtime gate ve paywall/abonelik kapsamları plana uygun olarak
uygulandı.

Auth e-posta, notification ve LEGAL-EN production doğrulama kapıları
tamamlandı. Final English legal set güncel Türkçe hukuk seti ve doğrulanmış
ürün davranışıyla eşlendi; owner/reviewer yayın talimatı yeni exact hash'lere
bağlandı. Üç belge blue/green Vercel doğrulamasından sonra additive route
olarak `riskdetected.com` üzerinde yayımlandı ve canlı HTTP/hash kontrolü
geçti.

Auth e-posta Edge Function deploy'u, Send Email Hook aktivasyonu ve dört
additive production migration uygulanmıştır. Notification'ın 10 onaylı
exact-locale satırı production'da doğrulanmıştır; automation rule/job'ları
yalnız `shadow` durumundadır, aktif rule ve pending delivery yoktur. Legal
site yayını mevcut kök site içeriğini değiştirmemiştir. Localization iOS
runtime aktivasyonu veya App Store Connect metadata mutation Faz 5 kapsamında
yapılmadı; canlı build 77 davranışı değişmedi.

Dış kapılar artık yalnız doküman checklist'i değildir. Machine-readable
evidence ve çalıştırılabilir release verifier eklendi:

- current-state integrity:
  `node scripts/verify_phase5_external_gates.mjs --mode=current`
- final release:
  `node scripts/verify_phase5_external_gates.mjs --mode=release --live`
- evidence:
  `docs/localization/phase-5/PHASE_5_EXTERNAL_GATE_EVIDENCE_2026-07-31.json`
- production read-only snapshot:
  `docs/localization/phase-5/PHASE_5_PRODUCTION_READONLY_2026-07-31.json`

Verifier hukuk kararını üç exact belge hash'ine ve blue/green production
publication kanıtına, notification kararını review pack ve production
read-after-write kanıtına, e-posta hook aktivasyonunu production
deployment/smoke kanıtına bağlar. Secret değeri evidence içine yazılamaz.

## Canlı sistem koruması ve build flag

- `RD_GLOBAL_LOCALIZATION_WAVE1` compile condition yoksa uygulama fail-closed
  biçimde mevcut Türkçe davranışta kalır.
- Güncel Release configuration bu condition'ı içermez; dolayısıyla yeni
  localization runtime'ı canlı build'e derlenmiş değildir.
- Persisted/runtime `UserDefaults` bypass bulunmaz.
- LEGAL-EN kapısı kapandı. Yeni localization runtime yalnız yeni build
  review'dan geçtikten ve build-number/remote rollout kapısı açıldıktan sonra
  canlı kullanıcılara etkinleşebilir.
- Runbook:
  `docs/localization/phase-5/GLOBAL_LOCALIZATION_BUILD_FLAG_RUNBOOK_2026-07-31.md`

## 5.1 PDF ve XLSX

- Rapor dili istemci seçiminden değil analiz localization snapshot'ından
  türetilir.
- İstemcinin gönderdiği `report_language` snapshot ile uyuşmazsa backend
  isteği reddeder.
- `reports.localization_snapshot` yazılır ve kayıt akışında doğrulanır.
- PDF ve XLSX başlık, tablo, footer, disclaimer, tarih, sayı ve dosya adı
  locale'e göre üretilir.
- Non-TR raporda mevzuat, Türkiye hazard class, OSGB ve compliance iddiası
  gösterilmez.
- Türkçe rapor davranışı korunur.
- İngilizce PDF için PDFKit text extraction; XLSX için parser tabanlı leak
  testi bulunur.

Doğrulama:

- English PDF extraction UI testi: **1/1 geçti**
- Deno XLSX/parser ve report-localization testleri: **geçti**
- UI test logu:
  `/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/logs/test_sim_2026-07-30T20-48-38-914Z_pid36679_85ab92a9.log`

## 5.2 Notification Operations Center

- Mevcut `private.notification_templates` yapısı korunur.
- Additive `private.notification_template_localizations` child tablosu
  eklenir.
- Child kayıt locale, title, body, review status ve checksum taşır.
- Job üretiminde exact locale çözülür ve immutable template snapshot job'a
  yazılır.
- Aynı locale template eksik veya onaysızsa fallback yapılmaz; job fail
  closed olur ve telemetry yazılır.
- İngilizce automation copy, Kerem tarafından 2026-07-31 tarihinde
  `approved` kararıyla onaylandı.
- Reviewer niteliği:
  `İngilizce iş güvenliği metinlerini değerlendirme niteliğine sahip.`
- Migration iki template × beş exact locale olmak üzere **10** child satırı
  `approved` seed eder.
- Her onaylı satır reviewer adı/niteliği, reviewed-copy SHA-256 ve ayrı
  approval-record SHA-256 taşır.
- Production'da 10/10 approved exact-locale satır checksum ve reviewer
  bağlarıyla read-after-write doğrulandı.
- Automation güvenliği: iki rule ve üç job yalnız `shadow`; aktif rule `0`,
  pending delivery `0`.

Review paketi:
`docs/localization/phase-5/NOTIFICATION_COPY_REVIEW_PACK_2026-07-30.md`

Immutable approval record:
`docs/localization/phase-5/NOTIFICATION_COPY_APPROVAL_2026-07-31.json`

Production verification:
`docs/localization/phase-5/NOTIFICATION_COPY_PRODUCTION_VERIFICATION_2026-07-31.json`

## 5.3 Transactional push

- Stable event key + exact locale template sözleşmesi kuruldu.
- Katalogda analiz, rapor, trial, progress ve account update akışlarını
  kapsayan **10** event bulunur.
- Serbest title/body yalnız kontrollü admin/manual job akışında kalır.
- Runtime gönderim profile locale'ini çözer; başka locale'e fallback yapmaz.

## 5.4 E-posta

- Welcome e-postası Türkçe ve İngilizce exact-locale template kullanır.
- `AuthService` auth metadata içine `app_language` ve `content_locale`
  snapshot'ı gönderir.
- `auth-send-email-hook` Standard Webhooks imzasını doğrular, exact locale
  seçer ve unsupported locale'de fail closed olur.
- Signup, OTP/magic link, recovery, invite, reauthentication ve Secure Email
  Change akışları kapsanır.
- Token, e-posta içeriği ve hook secret loglanmaz.
- Secret repo içine yazılmaz.

Production durumu:

- Kod ve otomatik testler hazırdır; güncel Supabase Auth e-posta action
  sözleşmesi Türkçe/İngilizce exact-locale katalogda kapsanır.
- `auth-send-email-hook` production version `7` olarak
  `2026-07-31T07:15:06.815Z` tarihinde `ACTIVE` doğrulandı;
  `verify_jwt=false` ve Standard Webhooks imzası zorunludur.
- HTTPS Send Email Hook production'da `ENABLED`.
- `SEND_EMAIL_HOOK_SECRET`, `RESEND_API_KEY` ve `RESEND_FROM_EMAIL` secret
  adları doğrulandı; değer veya digest kanıta alınmadı.
- Türkçe/İngilizce signup ve recovery ile Secure Email Change smoke
  senaryolarının tamamı HTTP 200 geçti.
- Geçersiz imza testi `401 invalid_webhook_signature` ile fail closed geçti.
- Testlerde Resend provider test alıcısı kullanıldı; production kullanıcı
  kaydı oluşturulmadı.
- Aktivasyon runbook'u:
  `docs/localization/phase-5/AUTH_EMAIL_HOOK_ACTIVATION_RUNBOOK_2026-07-30.md`
- Production verification:
  `docs/localization/phase-5/AUTH_EMAIL_HOOK_PRODUCTION_VERIFICATION_2026-07-31.json`

## 5.5 Support

- Ticket ile `app_language`, `content_locale`, `user_message_language` ve
  `preferred_response_language` saklanır.
- Profil locale'iyle request snapshot'ı doğrulanır.
- Kullanıcı subject/message metni aynen korunur; otomatik çevrilmez.
- Destek iç e-postasında tercih edilen cevap dili görünür.
- API acknowledgement aynı dil template'inden gelir ve iOS tarafından
  gösterilir.

## 5.6 Legal

Final English bundle:

- Terms of Use  
  SHA-256:
  `49a9b3f164b9dc8048453be930509aa334a854834c2abfa0cd8b11fd67ef6efa`
- Privacy Policy  
  SHA-256:
  `ef3d7e01b2b3c09603ff79c7f14bac631493feece7c1a0d6b0bd9a5f0e76ece4`
- AI and Data Processing Notice  
  SHA-256:
  `a8c9873f57228a36a4ede597e33648ff9251f9c814f1d1afc3e912c82ae08e1b`
- English set manifest  
  SHA-256:
  `008108dcb03fcc6db4955dbdc97c4e8f2091d78c8807832713de3ca9c051ad07`

Final yayın kararı Kerem tarafından `2026-07-31T08:02:40Z` tarihinde
`approved` olarak exact belge hash'lerine bağlandı.
Reviewer niteliği:
`Hukuk belgelerini inceleme ve onaylama yetkinliğine sahip.`

Final approval record:
`docs/localization/phase-5/LEGAL_COUNSEL_APPROVAL_2026-07-31_V2.json`

Approval record SHA-256:
`54ade7d6aae5615bcd5a1ce2f3191c1fecb77d9080ff61edf88b948afe129161`

URL gate'i yalnız HTTPS, `riskdetected.com` hostu, üç exact document kind,
doğrulanmış timestamp ve bundle hash eşleşmesiyle açılır. Türkçe SPA fallback
veren veya uydurma URL kabul etmez. Final canlı URL'ler:

- `https://riskdetected.com/legal-documents/en/Terms-of-Use.md`
- `https://riskdetected.com/legal-documents/en/Privacy-Policy.md`
- `https://riskdetected.com/legal-documents/en/AI-and-Data-Processing-Notice.md`

Üç route HTTP 200, `text/markdown`, sıfır redirect ve exact approved SHA-256
eşleşmesiyle doğrulandı. Deployment:
`dpl_9HvH32vh8YTTmmLFdJY9d9SSaxqS`.

Production verification:
`docs/localization/phase-5/ENGLISH_LEGAL_PRODUCTION_VERIFICATION_2026-07-31.json`

Yayın için önce source commit'in önceki production commit'iyle exact eşleştiği
doğrulandı. Yalnız final English legal dosyaları ve hash-guarded export script'i
izole build'e alındı; `--skip-domain` adayı doğrulandıktan sonra promote
edildi. Kök Vite HTML/assets değişmedi; Cloudflare'ın dinamik challenge
enjeksiyonu kaynak regresyonu sayılmadı.

Legal acceptance audit'i document set, locale, document checksum ve set
manifest checksum alanlarıyla genişletildi.

İlk preview ve draft approval kayıtları tarihsel kanıt olarak korunur. Final
release için yalnız V2 approval record ve final manifest otoritedir.
Counsel review packet:
`docs/localization/phase-5/LEGAL_COUNSEL_REVIEW_PACKET_2026-07-31.md`

İlk salt-okunur production snapshot'ında `auth-send-email-hook` function'ı ve
`SEND_EMAIL_HOOK_SECRET` adı bulunmuyordu. Sonraki açık e-posta onayıyla
function deploy, secret kurulumu, Dashboard hook aktivasyonu ve production
smoke testleri tamamlandı. İlk snapshot tarihsel/immutable kanıt olarak
korundu; güncel durum ayrı production verification kaydına bağlandı.

## 5.7 Paywall ve abonelik

- Dört production product ID değişmedi:
  - `riskdetected_plus_monthly`
  - `riskdetected_plus_yearly`
  - `riskdetected_pro_monthly`
  - `riskdetected_pro_yearly`
- Plan fiyatı ve limit davranışı değiştirilmedi.
- StoreKit/RevenueCat localized fiyat gösterimi korunur.
- Non-TR paywall/onboarding metnindeki mevzuat iddiası çıkarıldı.
- `en-GB`, `en-US`, `en-AU`, `en-CA` subscription group ve dört ürün
  metadata draftları hazırlandı; App Store Connect'e uygulanmadı.
- 2026-07-30 salt-okunur canlı kontrolünde yalnız Plus Yearly için 175
  territory'de 2026-05-30–2026-09-30 aralığında bir haftalık free trial
  vardır. AU, CA, GB ve US kapsamdadır. Diğer üç ürünün offer sayısı sıfırdır.

Kanıtlar:

- `docs/localization/phase-5/ASC_SUBSCRIPTION_METADATA_DRAFTS_2026-07-30.json`
- `docs/localization/phase-5/ASC_INTRODUCTORY_OFFER_READONLY_2026-07-30.json`

## Migration ve PostgreSQL doğrulaması

- Faz 5 migration:
  `supabase/migrations/20260730213000_global_localization_delivery_wave1.sql`
- SHA-256:
  `064322087cc97d709e59cdd5ae2ad0edc654fbac0b2723e30f8e4b0a2c03c324`
- Repository migration doğrulaması:
  **114 active = 110 canonical + 4 forward**
- Intentional production/local ledger ayrışması “repair” edilmedi.
- Dört forward migration production'a additive olarak uygulandı; ledger
  **114** ve migration hash'leri exact doğrulandı.
- Notification approval değişikliği sonrasında Phase 1 prerequisite, Faz 5
  migration ve pgTAP local DB'de tek transaction içinde çalıştırıldı.
- pgTAP: **25/25 geçti**
- Test dosyasının `ROLLBACK` işlemi bütün DDL/data değişikliğini geri aldı.
- Rollback sonrasında child tablo, localization kolon/flag'ı veya geçici
  validation database kalmadığı ayrıca doğrulandı.
- Production notification localization verisi ayrıca read-after-write ile
  doğrulandı. Canlı güvenlik talimatından sonra yeni production yazımı
  yapılmadı.

## Toplu doğrulama

- Supabase Edge Function testleri: **267 geçti, 0 başarısız**
- Faz 5 static/contract testleri: **12/12 geçti**
- Faz 5 external gate verifier testleri: **5/5 geçti**
- External gate current-state integrity: **geçti; 0 integrity error**
- External gate final release mode:
  **live URL kontrolüyle geçti; 3/3 dış kapı passed**
- Localization catalog: **16/16 geçti**
- Safety profile contract: **17/17 geçti**
- Hardcoded localization gate:
  **1852 current / 1852 baseline / 0 yeni ihlal**
- Content inventory:
  **1852 kayıt / 0 sahipsiz P0-P1**
- pgTAP delivery migration: **25/25 geçti**
- English PDF extraction UI testi: **1/1 geçti**
- Son iOS simulator build:
  **geçti, 0 warning, 0 error**
- Build logu:
  `/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/logs/build_sim_2026-07-31T07-33-50-088Z_pid88054_85244790.log`
- Son Release simulator build ve localization build gate:
  **geçti, global localization compiled-in değil, 0 warning, 0 error**
- Release build logu:
  `/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/logs/build_sim_2026-07-31T07-39-18-080Z_pid88054_ef3f8036.log`

Release build sırasında Xcode user-script sandbox'ın yeni
`auth-send-email-hook` ve shared localization dosyalarını input olarak
tanımadığı doğrulandı. Project build phase ve
`Config/LocalizationReleaseGateInputs.xcfilelist` eksikleri tamamlandı;
ardından gerçek Release build başarıyla tekrarlandı.

## Dış kapı durumu

### LEGAL-EN — PASSED

- Final insan/onay sahibi kararı üç exact hash'e bağlandı.
- Draft/release-blocker metinleri final setten çıkarıldı.
- Üç gerçek İngilizce HTTPS production URL yayımlandı.
- HTTP 200, `text/markdown`, sıfır redirect, English marker ve exact hash
  canlı doğrulaması tamamlandı.
- Blue/green production-safety kanıtı tamamlandı.

### AUTH-EMAIL-HOOK — PASSED

- Function production deploy: tamamlandı.
- Dashboard Send Email Hook aktivasyonu: tamamlandı.
- `SEND_EMAIL_HOOK_SECRET` kurulumu: tamamlandı; değer kaydedilmedi.
- Türkçe/İngilizce signup, recovery ve Secure Email Change smoke testleri:
  tamamlandı.
- Geçersiz imza fail-closed testi: tamamlandı.

### NOTIFICATION-COPY — PASSED

- İnsan onayı ve production migration tamamlandı.
- Production'da 10 approved exact-locale satır için read-after-write
  verification ve evidence digest tamamlandı.
- Automation shadow durumda; aktif gönderim açılmadı.

Tam dış kapı kaydı:
`docs/localization/phase-5/EXTERNAL_RELEASE_GATES_2026-07-30.md`

## Faz kararı

Repository içi teknik kapsam ile LEGAL-EN, auth e-posta ve notification
production kapılarının tamamı kapandı. Faz 5 çıkış kriterleri sağlandı. Canlı
build 77 localization flag kapalı davranışını korur; site legal yayını iOS
runtime aktivasyonu değildir. Plandaki sıralı ilerleme kuralına göre Faz 6
başlatılabilir.
