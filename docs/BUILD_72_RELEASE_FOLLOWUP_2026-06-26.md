# Build 72 (1.2.0) — Release Follow-up Plan (Ertelenmiş Adımlar)

Son güncelleme: 2026-06-28
Durum: **Tüm planlanmış adımlar tamamlandı** (Adım 9 `min_build` gelecekte).

Kalıcı rollout sistemi: [BUILD_GATED_IOS_ROLLOUT_RUNBOOK.md](BUILD_GATED_IOS_ROLLOUT_RUNBOOK.md)

---

## Tamamlanan adımlar

| # | Adım | Tarih | Kanıt |
|---|------|-------|-------|
| 1 | Canlı flag doğrulama (değiştirme yok) | 2026-06-26 | `kill_switch=false`, `"72"` allowlist'te |
| 2 | App Store Connect manuel release | 2026-06-26 | 1.2.0 build 72 yayında |
| 3 | App Store propagation | 2026-06-26 | Güncelleme App Store'da görünür |
| 4 | Fiziksel cihaz smoke test (App Store build) | 2026-06-26 | 5 foto, raporlar, bulgu düzenleme OK |
| 5 | DB kabul sorguları | 2026-06-26 | `9d414bd3-…` — 29 bulgu, `coverage_v2=true` |
| 6 | 24–48 saat izleme | 2026-06-28 | Flag değişmedi; 48h failed=0; release sonrası 4/4 completed |
| 7 | Onay dokümantasyonu | 2026-06-28 | [APP_STORE_APPROVAL_1.2.0_BUILD_72_2026-06-26.md](APP_STORE_APPROVAL_1.2.0_BUILD_72_2026-06-26.md) + git tag/branch |
| 8 | Kozmetik flag / fallback | 2026-06-28 | `policy_version=build-72-appstore`, fallback `latest_build=72`, static test OK |

---

## Ertelenmiş adımlar

### ~~Adım 8 — Kozmetik flag / fallback güncellemeleri~~ ✅ (2026-06-28)

- [x] `ios_release_policy.policy_version`: `build-72-testflight` → `build-72-appstore` (canlı DB)
- [x] Migration: `20260628203000_ios_release_policy_build_72_appstore.sql`
- [x] `app-release-policy/index.ts` fallback `latest_build: 72`
- [x] `index_static_test.ts` expectation güncellendi (test geçti)
- [x] Edge function deploy (`app-release-policy`)

---

### Adım 9 — Gelecek genişleme: `min_build` modu (şimdilik yapma)

**Ne zaman:** Kullanıcıların büyük çoğunluğu build 72+ olduğunda (haftalar/aylar).

**Ön koşul:**
- [ ] `analyze`, `register-report`, `generate-excel-report`, `mutate-analysis-finding` static test'leri geçiyor
- [ ] App Store analytics: aktif build dağılımı incelendi

**Migration:**
- `rollout_mode = min_build`
- `min_ios_build = 72`
- **`rollout_mode = all` kullanma**

Detay: [BUILD_GATED_IOS_ROLLOUT_RUNBOOK.md](BUILD_GATED_IOS_ROLLOUT_RUNBOOK.md) → Gelecek genişleme.

---

## Hızlı referans: mevcut canlı flag durumu

Adım 8 sonrası (2026-06-28):

```json
{
  "rollout_mode": "build_allowlist",
  "enabled_ios_builds": ["63","64","65","66","67","68","69","70","71","72"],
  "kill_switch": false,
  "ios_release_policy": {
    "latest_build": 72,
    "policy_version": "build-72-appstore",
    "hard_update_enabled": false,
    "soft_update_enabled": true,
    "minimum_supported_build": 62
  }
}
```
