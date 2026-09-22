# Android NOVA paritesi — envanter ve uygulama planı

Tarih: 2026-09-22. Referans: iOS `codex/isg-transition-foundation` @ `1c942f20`.

## 1. Neredeyiz

| | iOS | Android |
|---|---|---|
| NOVA kodu (tasarım sistemi + servis + pilot kapıları + NOVA onboarding) | ~60.100 satır, ~190 dosya | ~5.000 satır |
| Uzman kabuğu gerçek uygulamada | `NovaPilotMainGate` → `NovaIntegratedWorkspaceGate` → `NovaPilotRoot` | **Yok.** `NovaExpertShell` yalnızca `isg-design-preview` önizleme uygulamasında |
| Erişilebilen İSG yüzeyi | 35 hedefin tamamı, her biri özel ekran | Profil → `OsgbWorkspaceScreen`: ham JSON liste + detay sayfası, salt okunur |
| Backend RPC | 123 | 72 (**75 RPC eksik**) |
| Pilot build | `com.riskdetected.app.osgbpilot` (staging) + kişisel pilot (canlı, sahip UUID) | Yok |

Baseline `./gradlew :app:assembleDebug` başarılı (JDK: `/opt/homebrew/opt/openjdk@17`).

## 2. Mimari sözleşme (iOS'tan aynen alınır)

`docs/isg/shared-expert-panel-status.md`: **tek uzman arayüzü var**, `NovaPilotRoot`.
Kişisel uzman ve OSGB uzmanı aynı ekranları kullanır; fark yalnızca
`NovaExpertTransport` + `NovaExpertAccess` içindedir:

- Kişisel: RPC doğrudan çağrılır.
- OSGB uzmanı: `isg_expert_rpc_v1(p_workspace, p_function, p_arguments)` zarfı;
  yanıttaki `_expert_workspace_id` seçili çalışma alanıyla eşleşmezse reddedilir.
- Organizasyon isteği başarısız olursa **asla** kişisel RPC'ye düşülmez.
- Her servis bir bilet (ticket) yakalar; çalışma alanı/oturum değişince eski yanıt kabul edilmez.

OSGB yönetici/sahip ekranları (`IsgOSGBWorkspaceRoot`, üye yönetimi, firma editörü) ayrıdır.

Android bu sözleşmeyi Kotlin'de birebir kurar; modül ekranları rol kopyası olarak yazılmaz.

## 3. Pilot build kararı

iOS OSGB pilotunun eşi: yeni `osgbPilot` build type.

- `initWith(debug)` → **staging** backend (`qlymhrrlhklcudveknih`). Paylaşılan uzman
  paneli backend'i yalnızca staging'e deploy edildi; canlıya dokunulmadı.
- `applicationIdSuffix = ".osgbpilot"`, `BuildConfig.NOVA_PILOT = true`.
- Diğer tüm build tiplerinde `NOVA_PILOT = false` → mevcut `MainShell` aynen çalışır.
  Canlı (release) uygulama davranışı değişmez.
- Kişisel canlı pilot (production + sahip UUID) bu planın dışında; canlıya açmak
  deploy işidir (bkz. hafıza: live-project-runs-on-pilot-bundles).

## 4. Modül envanteri

`*` = Android veri katmanında yok.

| # | Modül | iOS satır | Android durumu | RPC |
|---|---|---|---|---|
| F1 | Kabuk / temel bileşenler (motion, popup, form, liste, görev akışı, başarı sunumu, klasör sekmeleri) | 4.299 | Kabuk + token + temel bileşen var; motion, popup, form, liste, görev akışı, başarı yok | — |
| F0 | Ana kapı + çalışma alanı seçici + transport | 2.791 + 3.738 | Yok (gateway'in 41/59'u var) | `isg_expert_rpc_v1*`, `isg_workspace_list/context_v1` |
| F2 | Ana sayfa (dashboard), bildirim merkezi, istatistik | ~1.600 | Önizlemede statik | `isg_pilot_overview_v2*`, `isg_pilot_notice_feed/mark_v1*`, `isg_statistics_v1*` |
| F3 | Firmalar: liste, oluşturma sihirbazı, firma çalışma alanı, ilerleme, modül takibi, ziyaret periyodu | 3.370 | Liste durumu + hedef var | `isg_pilot_company_create_v3*`, `isg_pilot_module_tracking_v2*`, `isg_pilot_module_editor/mutate_v1*` |
| F4 | Rehber / personel | 1.344 | Kısmen var | mevcut |
| F5 | Uygunsuzluk + takip + manuel bulgu | 2.524 | Yok | `isg_nonconformity_read/mutate_v1*`, `isg_pilot_followup_v1*`, `isg_pilot_finding_file_v1*`, `isg_analysis_filing_workplace_v1*` |
| F6 | Analiz (foto alımı, liste, detay, bölümler, raporlar, dosyalama) | 5.646 | Eski RiskDetected analiz akışı var; NOVA analiz yok | `isg_expert_analysis_v1*`, `isg_workspace_photo_analysis_*` |
| F7 | Risk değerlendirmesi | 1.981 | Yok | `isg_risk_versions_read/mutate_v1*` |
| F8 | Kontrol listeleri | 4.229 | Yok | `isg_checklists_read/mutate_v1*` |
| F9 | Acil durum planları + tatbikatlar | 2.822 | Yok | `isg_emergency_plans_*`, `isg_drills_*` |
| F10 | KKD zimmet + atama/temsilci + İSG-KATİP | 3.778 | Yok | `isg_ppe_*`, `isg_appointments_*`, `isg_katip_*` |
| F11 | Evrak takibi + dosya kütüphanesi | 4.002 | Yok | `isg_document_*`, `isg_pilot_file_library_*_v2`, `isg_pilot_file_sources_v1` |
| F12 | Periyodik kontroller (ekipman) | 3.006 | Yok | `isg_equipment_checks_read/mutate_v1*` |
| F13 | Eğitim ve takip | 2.611 | `EducationScreen` eski | `isg_pilot_training_*` |
| F14 | Süreç kayıtları (yıllık plan, kurul, çalışma izni, taşeron, ziyaret) | 1.457 | Yok | `isg_pilot_process_*`, `isg_pilot_visit_summary_v1*` |
| F15 | Not defteri / aktivite / varlık | ~500 | Not defteri veri katmanı var | `isg_activity_*`, `isg_usage_presence_v1*` |
| F16 | OSGB yönetici kökü (firma editörü, üye/davet yönetimi, atamalar) | ~3.500 | Ham liste | `isg_workspace_company_*`, `isg_workspace_member_*`, `isg_workspace_invitation_*`, `isg_workspace_invite_v1` |
| F17 | NOVA onboarding (splash, marquee, sorular, profil kartı, kayıt, deneme) | 4.162 | Eski RiskDetected onboarding | — |

## 5. Sıra ve bağımlılık

F0 → F1 önce (her ekran bunlara dayanır). Sonra kullanıcı değerine göre:
F2 → F3 → F5 → F6 → F12 → F13 → F7 → F8 → F9 → F10 → F11 → F14 → F4 → F15 → F16 → F17.

Her faz: veri katmanı (DTO + repository, transport üzerinden) → ekranlar → build →
emülatörde çalıştırma → commit. iOS dosyası referans alınır: aynı metin, aynı alan
sırası, aynı durum geçişleri, aynı boş/hata/yükleniyor durumları, aynı hareket değerleri
(`NovaMotion` süreleri ve eğrileri Compose karşılıklarıyla).

## 6. Doğrulama

- Her faz: `./gradlew :app:assembleOsgbPilot` + ilgili birim testleri.
- Emülatör: `RiskDetected_API33_Standard`. Tasarım doğrulaması önizleme modunda
  (canlı veri kullanmayan, iOS `RD_UI_TEST_NOVA_PILOT` eşi) ekran görüntüsüyle.
- Canlı veri doğrulaması staging hesabıyla girişi gerektirir; parola girişini
  kullanıcı kendisi yapar.

## 7. İlerleme günlüğü

(Her faz tamamlandıkça commit hash'iyle eklenir.)
