# RiskDetected Android — Owner Karar Defteri

**Tarih:** 6 Ağustos 2026
**Kaynak:** Master plan §36 (DEC-01…15) + inceleme belgesi §12 (DEC-16…24)
**Durum:** DEC-01…13 owner tarafından karara bağlandı (bu belge). DEC-14…24 zaten inceleme belgesinde kesinleşmişti, burada tekrar edilmiyor — bkz. `RISKDETECTED_ANDROID_PLAN_INCELEME_VE_FINAL_KARAR_2026-08-06.md` §8/§12.

| ID | Karar | Son karar | Not |
|---|---|---|---|
| DEC-01 | Production package ID | **`com.riskdetectedan.app`** | iOS bundle ID'den (`com.riskdetected.app`) bilinçli olarak farklı. Play product ID'lerin iOS ile birebir aynı olması gerekliliğini (DEC-14) etkilemez — o ayrı bir namespace. |
| DEC-02 | Android launch versionName | **`1.5.0`** | versionCode (build no) bundan bağımsız, 1'den başlar; F3 platform-aware düzeltmesi sonrası iOS build numaralarıyla namespace çakışması yok. |
| DEC-03 | Play developer account type | **Kişisel (personal)** | GATE-11'i tetikler: 12 opt-in tester × kesintisiz 14 gün closed testing şartı **Faz 0'da**, geliştirmeyle paralel başlatılmalı. |
| DEC-04 | Plus yearly trial | **7 gün, iki store'da devam, tarih eşgüdümlü** | Mevcut iOS trial süresiyle aynı. |
| DEC-05 | Google Play territory seti | **Evet — mevcut destek profilleriyle uyumlu, China hariç** | Master planın varsayılan önerisi onaylandı. |
| DEC-06 | Crashlytics | PII'siz, Data Safety güncel | İnceleme belgesinde zaten cevaplı (Faz 7). |
| DEC-07 | Pinning | v1'de yok, post-launch + runbook | İnceleme Ç1 ile cevaplı. |
| DEC-08 | Play Integrity | v1'de launch'ta shadow değil — **v1'de hiç yok**, post-launch shadow | İnceleme Ç2 ile cevaplı. |
| DEC-09 | Android PDF | Cihaz içi (`PdfDocument`) | İnceleme §8 final tablo ile cevaplı. |
| DEC-10 | App target audience | **Professional** | Legal/Play formuyla netleşecek. **Ek karar:** Android legal metinleri (Privacy Policy/Terms/vb.) iOS metinlerinin birebir kopyası olmayacak, **Android'e özgü ayrı metin** yazılacak — Faz 3/8 legal iş kalemine girdi. |
| DEC-11 | Closed beta katılımcıları | **İç ekip + dış katılımcılar** | Master planın "yalnız iç ekip + saha uzmanı" varsayılan önerisinin ötesinde — dış katılımcılar dahil. GATE-11'in 12 tester şartıyla zaten örtüşüyor/besleniyor. |
| DEC-12 | Staging Supabase | **Ayrı, izole staging projesi açılacak** | GATE-03 ile tam uyumlu, sapma yok. Production (`ppcrzemgiztzcgddbins`) hiçbir Faz 2-7 test/migration denemesine maruz kalmaz. **Açık iş:** staging projesinin oluşturulması (Supabase org erişimi/billing onayı owner'dan gerekiyor). |
| DEC-13 | Apple identity recovery companion iOS build | **Koşullu varsayılan korunuyor** | Yalnız GATE-04 cross-platform kimlik testi başarısız olursa devreye girer; zorunlu değil. |

## Açık kalan, henüz karara bağlanmamış iş

- **GATE-00 (build 81 reproducibility) netleşmedi.** Repoda çok sayıda birbirinden ayrışmış branch var (`codex/app-review-build-57/60/61`, `codex/worktree-cleanup` origin'den 15 ileri, `codex/geri-donus-*`, `main` origin/main'den 12 ileri — origin/main 29 Mayıs'tan donmuş). Hangi branch'in gerçek build-81 kaynağı olduğu doğrulanmadan Android işi `main`'den dallanmamalı. Bu belge bunu **çözmüyor**, yalnız işaretliyor.
- **DEC-12'nin uygulanması:** ayrı staging Supabase projesinin fiilen açılması bekleniyor.
