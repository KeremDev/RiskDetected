# RiskDetected Faz 5 — External Release Gates

Tarih: 2026-07-30  
Durum: **passed**

## LEGAL-EN

Durum: **passed**

Mevcut durum:

- Final bundle ve SHA-256 değerleri hazır.
- Final publication kararı `approved`: reviewer Kerem; nitelik
  `Hukuk belgelerini inceleme ve onaylama yetkinliğine sahip.`
- Karar üç exact belge hash'ine bağlandı:
  `docs/localization/phase-5/LEGAL_COUNSEL_APPROVAL_2026-07-31_V2.json`.
- Approval record SHA-256:
  `54ade7d6aae5615bcd5a1ce2f3191c1fecb77d9080ff61edf88b948afe129161`.
- Manifest `approved`; public URLs ve verification timestamp kayıtlı.
- Üç `https://riskdetected.com/legal-documents/en/...` route HTTP 200,
  `text/markdown`, sıfır redirect ve exact hash eşleşmesiyle canlı
  doğrulandı.
- Deployment önce source-production commit eşitliği ve isolated
  `--skip-domain` adayıyla doğrulandı, sonra atomik promote edildi.
- Production verification:
  `docs/localization/phase-5/ENGLISH_LEGAL_PRODUCTION_VERIFICATION_2026-07-31.json`

## AUTH-EMAIL-HOOK

Durum: **passed**

- `auth-send-email-hook` production version `7`, `ACTIVE`,
  `verify_jwt=false`.
- HTTPS Send Email Hook production'da `ENABLED`.
- `SEND_EMAIL_HOOK_SECRET` ve mevcut Resend secret adları doğrulandı; secret
  değeri veya digest'i kanıta alınmadı.
- Türkçe/İngilizce signup ve recovery ile Secure Email Change smoke
  testlerinin tamamı HTTP 200 geçti.
- Geçersiz imza `401 invalid_webhook_signature` ile fail closed oldu.
- Testlerde production kullanıcı kaydı oluşturulmadı.
- Production verification:
  `docs/localization/phase-5/AUTH_EMAIL_HOOK_PRODUCTION_VERIFICATION_2026-07-31.json`

## NOTIFICATION-COPY

Durum: **passed**

- Decision: `approved`
- Reviewer: Kerem
- Nitelik:
  `İngilizce iş güvenliği metinlerini değerlendirme niteliğine sahip.`
- Reviewed at: `2026-07-31T06:31:04Z`
- Reviewed pack SHA-256:
  `5660f3a69595a0d8b80057fe2a5a0fb97c9393a003ff2bd72ad8208646955c87`
- Approval record SHA-256:
  `abfbf34bbfcd59e72ac06658ab84970d0429cc1d2020102d866ae48544921158`

Mevcut durum:

- Immutable approval record:
  `docs/localization/phase-5/NOTIFICATION_COPY_APPROVAL_2026-07-31.json`
- Migration, iki automation template × beş exact locale olmak üzere **10**
  İngilizce child satırını `approved` seed eder.
- Her satır reviewer adı/niteliği, reviewed-copy hash'i ve approval-record
  hash'i taşır.
- pgTAP: **25/25 geçti**.
- Eksik veya sonradan `draft/rejected` yapılan exact locale yine fail closed
  olur ve telemetry üretir; cross-locale fallback açılmadı.
- Production migration uygulandı; production'daki 10 approved exact-locale
  satır checksum, reviewer ve approval-record bağlarıyla read-after-write
  doğrulandı.
- İki automation rule ve üç job yalnız `shadow`; aktif rule `0`, pending
  delivery `0`. Yeni gönderim davranışı etkinleştirilmedi.
- Production verification:
  `docs/localization/phase-5/NOTIFICATION_COPY_PRODUCTION_VERIFICATION_2026-07-31.json`

## Çalıştırılabilir dış gate

- Machine-readable evidence:
  `docs/localization/phase-5/PHASE_5_EXTERNAL_GATE_EVIDENCE_2026-07-31.json`
- Production read-only snapshot:
  `docs/localization/phase-5/PHASE_5_PRODUCTION_READONLY_2026-07-31.json`
- Current-state integrity check:
  `node scripts/verify_phase5_external_gates.mjs --mode=current`
- Final release check:
  `node scripts/verify_phase5_external_gates.mjs --mode=release --live`

Final gate, hukuk kararını üç exact belge hash'ine ve blue/green production
publication kanıtına; notification onayını review pack ve production verification
hash'lerine; auth hook aktivasyonunu deployment/smoke kanıtına bağlar. Secret
değeri evidence dosyasına yazılamaz.

## Canlı aktivasyon koruması

- `RD_GLOBAL_LOCALIZATION_WAVE1` current Release configuration'da tanımlı
  değildir.
- Flag kapalıyken yeni localization runtime'ı fail-closed biçimde mevcut
  Türkçe davranışa döner.
- Production legal yayın additive route olarak tamamlandı; mevcut kök site
  source içeriği değişmedi.
- App Store metadata mutation veya localization iOS runtime aktivasyonu
  yapılmadı; canlı build 77 etkilenmedi.
- Localization aktivasyonu yalnız yeni build review/onaydan geçtikten ve
  build-number/remote rollout kapısı açıldıktan sonra yapılabilir.

## Sonuç

İnsan onayları, auth e-posta, notification ve public legal production
doğrulamaları tamamlandı. Faz 5 çıkış kriterindeki dil matrisi,
counsel-reviewed erişilebilir English legal URL ve abonelik davranışı
şartları sağlandı. Faz 6'ya geçilebilir.
