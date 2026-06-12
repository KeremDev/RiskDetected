# RiskDetected — Codex Handoff: Aktif Analiz Sektörü & Proje Durumu

**Tarih:** 2026-06-12 (son güncelleme: push sonrası)  
**Branch:** `codex/worktree-cleanup`  
**Remote:** `origin/codex/worktree-cleanup` — **push edildi** (`b04c2ef` → `7a87f84`)  
**PR:** https://github.com/KeremDev/RiskDetected/pull/1 (OPEN, 2 sektör commit’i dahil)  
**HEAD:** `7a87f84`  
**Hazırlayan:** Cursor agent oturumu (Kerem kaydı)

Bu belge, Codex’in projeyi hızlıca değerlendirmesi için yazıldı. Önce **ne yapıldı**, sonra **proje hangi aşamada**, en sonda **sıradaki işler** özetlenir.

### Codex için hızlı checkout
```bash
git fetch origin
git checkout codex/worktree-cleanup
git pull origin codex/worktree-cleanup
# Bu handoff dosyası:
# docs/CODEX_HANDOFF_ACTIVE_ANALYSIS_SECTOR_AND_PROJECT_STATUS_2026-06-12.md
```

---

## 1. Yönetici özeti (Codex için)

RiskDetected, iOS üzerinde çalışan bir **İSG (iş sağlığı ve güvenliği) risk analizi** uygulamasıdır. Kullanıcı fotoğraf veya metin ile saha riski taratır; sonuç PDF/XLSX ve uygulama içi rapor olarak sunulur. Backend **Supabase** (Postgres + Edge Functions); abonelik **RevenueCat**.

**Bu oturumda tamamlanan ana özellik:** Her analiz için **zorunlu tek aktif sektör seçimi** — onboarding’deki çoklu sektör profili ile karıştırılmamalı.

| Alan | Durum |
|------|--------|
| Aktif sektör — iOS UI & akış | ✅ Tamamlandı |
| Aktif sektör — backend prompt & persist | ✅ Tamamlandı (`sector-context.ts`, `active-sector-v1`) |
| Prod Supabase migration + edge deploy | ✅ Uygulandı (2026-06-12) |
| UI testleri (sektör akışı) | ✅ 3/3 geçiyor |
| Git remote sync | ✅ `origin/codex/worktree-cleanup` güncel (`7a87f84`) |
| PR #1 | 🟡 Açık, merge bekliyor |
| UI polish (tüm sektörler grid, boşluk) | ✅ `7a87f84` — remote’ta |
| Gerçek cihaz smoke (analiz → PDF) | ⏳ Yapılmadı |
| Rapor arşivi sektör filtresi | ⏳ Planlı, yapılmadı |
| İngilizce lokalizasyon | ⏳ Ayrı iş paketi |
| Admin web dashboard (DB migration’ları) | ⏳ Ayrı iş paketi, repoda untracked |

**Proje aşaması değerlendirmesi:** Ürün **App Store’da onaylı build 60** sonrası geliştirme aşamasında. Aktif sektör özelliği **feature-complete + prod-deployed**; release için PR merge + kısa manuel QA yeterli. Paralel olarak admin dashboard ve EN lokalizasyon taslakları repoda var ama bu PR kapsamı dışında.

---

## 2. Ürün mantığı: İki farklı “sektör” kavramı

Codex’in en sık karıştırabileceği nokta budur:

### A) Onboarding sektörleri (profil sinyali)
- **Çoklu seçim** — kullanıcı hangi sektörlerde çalıştığını işaretler.
- **Max limit kaldırıldı** (önceden max 2 vardı).
- Katalog genişletildi (15 sektör + `general` analiz-only).
- Dosyalar: `OnboardingV2State.swift`, `OBSectorView.swift`.

### B) Aktif analiz sektörü (bu özellik)
- **Her analiz için tam 1 sektör** — kullanıcı seçmeden canvas’a geçilemez.
- `general` her zaman listede; **otomatik seçim yok**.
- Son kullanılan sektör sadece **“Son” rozeti** ile gösterilir, auto-select değil.
- Backend’e `analysis_sector`, `analysis_sector_source`, `analysis_sector_prompt_version` gider.
- Feature flag: `RDConfig.Features.activeAnalysisSectorEnabled = true`.

---

## 3. Kullanıcı akışı (güncel)

```
Ana ekran (foto veya metin hazır)
    → "Taramayı başlat" / start_scan
    → AnalysisSectorPickerView (sheet, .large detent)
        → 15 sektör, 3 sütunlu chip grid
        → "Devam et" (siyah RDButton primary)
    → CanvasSheet (analiz kapsamı / canvas seçimi)
    → Analiz (Edge Function analyze)
    → ResultView (+ PDF/XLSX metadata)
```

**Önemli sıra düzeltmesi:** Sektör seçimi **canvas’tan önce** gelir (önceki taslakta tersiydi).

---

## 4. Commit geçmişi (bu özellik)

### Commit 1: `b04c2ef` — Ana özellik (PR #1’de)
**Mesaj:** `Add mandatory active analysis sector flow end-to-end.`

Kapsam (~28 dosya, +1361 satır):
- `AnalysisSector.swift` model + katalog + picker item sıralaması
- `AnalysisSectorPickerView.swift` (ilk sürüm)
- `HomeView.swift` akış entegrasyonu
- `AnalysisService.swift` — createAnalysis + invokeAnalyze alanları
- `sector-context.ts` + `analyze/index.ts` prompt/validation
- Migration `20260612120000_add_active_analysis_sector.sql`
- Result/PDF/XLSX sektör metadata
- UI test bypass’ları (launch hang), `run_ui_tests.sh`
- Onboarding max-2 kaldırma

**Prod deploy (oturumda yapıldı):**
- Migration: `ppcrzemgiztzcgddbins` projesine uygulandı
- Edge: `analyze` v106, `generate-excel-report` v58
- Deno testleri: `sector-context_test.ts` 6/6

### Commit 2: `7a87f84` — UI polish, handoff doc & katalog sadeleştirme
**Mesaj:** `Show all analysis sectors inline and tighten picker layout.`  
**Remote:** ✅ push edildi (2026-06-12)

Değişiklikler:
- 8 chip + “Tüm sektörleri göster” kaldırıldı → **15 sektör tek grid**
- `HomeView` arama kataloğu sheet’i (`showSectorCatalogSheet`) kaldırıldı
- `inlineVisibleItems(limit: 8)` helper silindi
- Chip: 3 kolon, daha kompakt padding, `minHeight` kaldırıldı
- Rozet: dar chip için `compactLabel` (“Son”, “Önerilen”)
- Grid–buton arası boşluk: `ViewThatFits` + `scrollBounceBehavior(.basedOnSize)` (iOS 16.4+)
- UI test: `testActiveAnalysisSectorFullGridShowsLogisticsWarehouseChip`

**Not:** `AnalysisSectorPickerSheet` struct hâlâ dosyada duruyor ama ana akışta kullanılmıyor (dead code — temizlenebilir).

---

## 5. Dosya envanteri (aktif sektör)

| Dosya | Rol |
|-------|-----|
| `App/Models/AnalysisSector.swift` | 15 sektör enum, badge, picker sıralama |
| `App/Views/Analysis/AnalysisSectorPickerView.swift` | Picker UI + kullanılmayan catalog sheet |
| `App/Views/Home/HomeView.swift` | Sheet tetikleme, `sectorPickerItems`, akış |
| `App/Services/AnalysisService.swift` | API body + DB insert alanları |
| `App/Services/RDConfig.swift` | `activeAnalysisSectorEnabled` flag |
| `App/Views/Result/ResultView.swift` | Sonuç ekranında sektör gösterimi |
| `App/Services/PDFReportService.swift` | PDF metadata |
| `supabase/functions/analyze/sector-context.ts` | Prompt bağlamı, allowlist |
| `supabase/functions/analyze/index.ts` | Validation, queue, audit |
| `supabase/functions/generate-excel-report/index.ts` | XLSX sektör alanı |
| `supabase/migrations/20260612120000_add_active_analysis_sector.sql` | DB kolonları |
| `supabase/functions/analyze/sector-context_test.ts` | Deno unit testler |
| `RiskDetectedUITests/RiskDetectedUITests.swift` | 3 sektör UI testi |
| `scripts/run_ui_tests.sh` | UI test runner (120s timeout) |
| `RiskDetectedSnapshotTests/` | Picker preview snapshot |

---

## 6. Backend sözleşmesi

### `invokeAnalyze` ek alanlar (client → edge)
```json
{
  "analysis_sector": "construction",
  "analysis_sector_source": "user_selected",
  "analysis_sector_prompt_version": "active-sector-v1"
}
```

### DB (`public.analyses`)
- `analysis_sector` (text, nullable — legacy analizler)
- `analysis_sector_source` (text)
- `analysis_sector_prompt_version` (text)
- Index: `analyses_user_sector_created_idx`

### Sektör allowlist (15)
`general`, `construction`, `manufacturing`, `mining`, `energy`, `office`, `logistics_warehouse`, `chemical_laboratory`, `healthcare`, `food_production`, `agriculture_livestock`, `retail`, `municipal_field_services`, `education`, `hospitality`

Swift `AnalysisSectorCatalog.validateSyncWithBackend()` DEBUG’da senkron kontrol eder.

---

## 6b. Prompt güncellemeleri (Codex — önemli)

**Evet, prompt’lar güncellendi** — `b04c2ef` commit’inde. `7a87f84` yalnızca iOS UI’dır; prompt’a dokunmaz.

### Yeni modül: `supabase/functions/analyze/sector-context.ts`
- **Prompt versiyonu:** `ACTIVE_ANALYSIS_SECTOR_PROMPT_VERSION = "active-sector-v1"`
- **14 sektör için** Türkçe `SEKTÖR REHBERİ` blokları (`general` hariç)
- **`buildActiveSectorPromptBlock()`** — seçilen sektöre göre `<aktif_analiz_sektoru>` XML bloğu üretir
- **`onboardingSectorProfileRule(hasActiveSector)`** — aktif sektör varken onboarding’in sadece profil sinyali olduğunu modele söyler

### Ana prompt entegrasyonu (`analyze/index.ts`)
`buildAnalysisContext()` içinde sıra:
1. Canvas odak (`<odak>`)
2. Abonelik bağlamı
3. **`${activeSectorBlock}`** ← yeni
4. Onboarding profil bloğu
5. Firma bağlamı

### Üç prompt senaryosu
| `analysis_sector` | Model davranışı |
|-------------------|-----------------|
| Spesifik sektör (ör. `logistics_warehouse`) | Sektör etiketi + sektör rehberi + önceliklendirme kuralları |
| `general` | Sektöre özel varsayım yapma; genel İSG taraması |
| Boş / eski client | Legacy fallback; onboarding yalnızca zayıf sinyal |

### Örnek rehber (depo/lojistik)
Forklift, yaya yolları, raf istifi, rampa zeminleri, araç-yaya ayrımı vb. — `SECTOR_GUIDANCE_TR.logistics_warehouse` içinde.

### Prod deploy
- Edge function `analyze` **v106** (prompt değişiklikleri prod’da)
- `generate-excel-report` **v58** (sektör metadata)
- Deno: `sector-context_test.ts` — **6/6 passed**

### Audit alanları (`_input_audit`)
`active_analysis_sector`, `active_analysis_sector_source`, `active_analysis_sector_prompt_version`, `active_analysis_sector_label`, `sector_context_applied`

---

## 7. Test & QA durumu

### UI testleri (simülatör: `RD QA iPhone 16 Pro`)
```bash
./scripts/run_ui_tests.sh \
  testActiveAnalysisSectorPickerRequiresSelectionBeforeCanvas \
  testActiveAnalysisSectorSingleSelectionReplacesPreviousChoice \
  testActiveAnalysisSectorFullGridShowsLogisticsWarehouseChip
```
Son koşum: **3/3 passed** (~16–27 sn).

### Snapshot
```bash
./scripts/run_snapshot_previews.sh \
  /Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/sector-picker-preview
```
Çıktı: `output/sector-picker-preview/RiskDetected_AnalysisSectorPickerView.swift_Aktif_Sektör_Seçimi.png`  
(`output/` gitignore’da — commit edilmez)

### Deno
```bash
cd supabase/functions/analyze && deno test sector-context_test.ts
```

### Yapılmayan QA
- [ ] Gerçek cihazda tam analiz döngüsü (sektör → sonuç → PDF indir → sektör metni doğrula)
- [ ] Eski client (sektör göndermeyen) ile backward compat smoke
- [ ] App Store build ile prod edge uyumu

---

## 8. UI test altyapı notları (önemli)

UI testlerde `app.launch()` idle beklemeden takılıyordu. Uygulanan bypass’lar:
- Scheme: TestAction debugger kapalı, `parallelizable = NO`
- `AuthService`, `NotificationService`, `RootView`, `RevenueCat`, `RiskDetectedApp` UI-test kısayolları
- Erişilebilirlik: sheet içi ID yerine görünür Türkçe label’lar (`Analiz kapsamını seç`, `Devam et`)

Codex yeni UI test yazarken sheet accessibility ID’lerine güvenmemeli; chip ID’leri (`analysis_sector_chip_logistics_warehouse`) çalışıyor.

---

## 9. Repoda olan ama bu PR’a dahil OLMAYAN işler

Aşağıdakiler **untracked veya unstaged** — aktif sektör commit’ine dahil edilmedi:

| Path | Açıklama |
|------|----------|
| `supabase/migrations/20260611120000_*.sql` … `20260611121400_*.sql` | Admin dashboard DB şeması (15 migration) |
| `docs/RISKDETECTED_WEB_ADMIN_DASHBOARD_BRIEF_2026-06-11.md` | Admin dashboard brief |
| `docs/RISKDETECTED_PROJECT_DEEP_DIVE_FOR_ENGLISH_LOCALIZATION_2026-06-12.md` | EN lokalizasyon deep dive |
| `Config/RiskDetectedInfo.plist` | İlgisiz sıra değişikliği (staged değil) |
| `supabase/config.toml` | Admin redirect URL değişiklikleri |
| `output/` | Snapshot/build artefact’ları |

Codex bu dosyaları **ayrı epic** olarak ele almalı.

---

## 10. Bilinçli olarak ertelenen follow-up’lar

1. **Rapor arşivinde sektör filtresi** — `ReportView` / sorgu katmanı
2. **`reports.analysis_sector` snapshot kolonu** — rapor tablosuna denormalize
3. **`AnalysisSectorPickerSheet` dead code temizliği**
4. **Sheet detent’i içeriğe göre** — `.large` altında buton altı boşluk (kozmetik)
5. **İngilizce lokalizasyon** — `AnalysisSectorID.label(language:)` altyapısı var, EN string’ler yok
6. **Admin dashboard** — migration + web brief hazır, implementasyon yok

---

## 11. Codex için önerilen sonraki adımlar (öncelik sırası)

### P0 — Release kapatma
1. ~~PR #1 branch push~~ ✅ `origin/codex/worktree-cleanup` @ `7a87f84`
2. PR #1 review + merge onayı
3. Gerçek cihaz smoke: metin analizi → sektör seç → sonuç → PDF (sektör metni + prompt etkisi doğrula)
4. PR merge → TestFlight / store build planı

### P1 — Ürün tamamlama
4. Rapor arşivine sektör filtresi
5. Dead `AnalysisSectorPickerSheet` kaldır veya arşivle
6. Legacy client davranışını dokümante et (`analysis_sector` null)

### P2 — Paralel epic’ler
7. Admin dashboard (15 migration + brief)
8. English localization (mevcut deep dive doc’u kaynak al)

---

## 12. Hızlı doğrulama komutları

```bash
# Branch & PR (remote güncel)
git fetch origin && git checkout codex/worktree-cleanup && git pull
git log -2 --oneline   # b04c2ef, 7a87f84 beklenir
gh pr view 1

# UI testler
./scripts/run_ui_tests.sh testActiveAnalysisSectorFullGridShowsLogisticsWarehouseChip

# Backend test
cd supabase/functions/analyze && deno test sector-context_test.ts

# Xcode build (Debug)
xcodebuild -project RiskDetected.xcodeproj -scheme RiskDetected \
  -destination 'platform=iOS Simulator,name=RD QA iPhone 16 Pro' build
```

---

## 13. Erişilebilirlik kimlikleri (picker)

| Element | ID / Label |
|---------|------------|
| Picker container | `analysis_sector_picker` |
| Başlık | `analysis_sector_picker_title` / "Analiz kapsamını seç" |
| Devam butonu | `analysis_sector_continue_button` / "Devam et" |
| Chip (örnek) | `analysis_sector_chip_construction` |
| Canvas (sonraki adım) | `canvas_sheet` |

---

## 14. Proje bağlamı (Codex stage assessment)

| Boyut | Not |
|-------|-----|
| **Maturity** | Production app (build 60 App Review onaylı); aktif feature geliştirme |
| **Architecture** | SwiftUI iOS client + Supabase BaaS; edge functions iş mantığı |
| **Test coverage** | Sektör akışı UI testli; geniş E2E/integration sınırlı |
| **Deploy hygiene** | Migration + edge prod’da; iOS branch remote’ta güncel; PR merge bekliyor |
| **Tech debt** | Kullanılmayan `AnalysisSectorPickerSheet`; sheet `.large` alt boşluğu; admin migrations repoda dağınık |
| **Risk** | Manuel smoke eksik; PR #1 geniş commit geçmişi içeriyor (sadece sektör diff’ine odaklan) |

**Sonuç:** Aktif analiz sektörü özelliği **implementasyon, prompt ve prod altyapı açısından bitti**. Remote push tamamlandı. Codex sıradaki iş: PR review → manuel QA → merge.

---

## 15. PR #1 commit özeti (sektör ile ilgili)

| SHA | Mesaj | Kapsam |
|-----|-------|--------|
| `b04c2ef` | Add mandatory active analysis sector flow end-to-end. | Model, akış, backend prompt, migration, UI test, prod deploy |
| `7a87f84` | Show all analysis sectors inline and tighten picker layout. | 15-chip grid, boşluk, katalog kaldırma, handoff doc |

PR branch’i `main`’den birçok önceki commit de içerir; Codex review yaparken **yalnızca bu iki commit’in diff’ine** odaklanması önerilir:
```bash
git diff main...7a87f84 -- App/ supabase/functions/analyze/sector-context.ts supabase/migrations/20260612120000_add_active_analysis_sector.sql RiskDetectedUITests/ scripts/run_ui_tests.sh docs/CODEX_HANDOFF_ACTIVE_ANALYSIS_SECTOR_AND_PROJECT_STATUS_2026-06-12.md
```

---

*Bu dosya Codex handoff amaçlıdır. Son güncelleme: 2026-06-12 — remote push (`7a87f84`) + prompt bölümü eklendi.*
