# Android NOVA paritesi — envanter ve uygulama planı

Tarih: 2026-09-22. Referans: iOS `codex/isg-transition-foundation` @ `1c942f20`.

## 1. Neredeyiz

| | iOS | Android |
|---|---|---|
| NOVA kodu (tasarım sistemi + servis + pilot kapıları + NOVA onboarding) | ~60.100 satır, ~190 dosya | ~5.000 satır |
| Uzman kabuğu gerçek uygulamada | `NovaPilotMainGate` → `NovaIntegratedWorkspaceGate` → `NovaPilotRoot` | **Yok.** `NovaExpertShell` yalnızca `isg-design-preview` önizleme uygulamasında |
| Erişilebilen İSG yüzeyi | 35 hedefin tamamı, her biri özel ekran | Profil → `OsgbWorkspaceScreen`: ham JSON liste + detay sayfası, salt okunur |
| Backend RPC | 123 | 72 (**75 RPC eksik**) |
| Pilot build | `com.riskdetected.app.osgbpilot` (staging) + kişisel pilot (canlı, sahip UUID) | `osgbPilot` build type (staging) |

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
- `BuildConfig.NOVA_PILOT = true`; paket şimdilik staging debug paketiyle aynı (`com.riskdetectedan.app.debug`), bkz. bilinen konular.
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

| Faz | Durum | Commit |
|---|---|---|
| F1 Temel + kabuk + navigasyon kataloğu | Tamam; 408 tasarım sistemi testi + iOS/Node navigasyon sözleşmesi geçiyor | `3651e480` |
| F0 Pilot build + transport + çalışma alanı + kök | Tamam; `osgbPilot` APK emülatörde açılıyor | (bu commit) |
| F2 Ana sayfa + bildirim merkezi | Ana sayfa canlı özet, zil, bildirim merkezi tamam | `5c38a6db` |
| F5 Uygunsuzluk panosu + kayıt + manuel bulgu | Tamam | `7cc1029b` |
| F7 Risk değerlendirmesi (modül günlüğü + dosya alanı) | Tamam | `c105c38e` |
| F12 Periyodik kontroller | Tamam | `44521e30` |
| F9 Acil durum planları + tatbikatlar | Tamam | `2d06488b` |
| F10 Atama, KKD zimmet, İSG-KATİP | Tamam; menüdeki İSG-KATİP iOS gibi süreç kaydına gider (`NovaKatipScreen` kullanılmıyor) | `da07d5ac` |
| F14 Süreç kayıtları (ziyaret sihirbazı, yıllık plan, kurul, izin, taşeron) + PDF/XLSX | Tamam | `a7e0b733` |
| F11 Dosya arşivi + evrak takibi | Tamam | `5133718f` |
| F8 Kontrol listeleri (çevrimdışı kuyruk dahil) | Tamam | `4a955fad` |
| F13 Eğitimler + kişisel sertifika | Tamam; firmasız yeni kayıtta takvim adımı kilidi Android'de açıldı (iOS'ta hâlâ var) | `d8e94e0b` |
| F2 İstatistik + süreç takibi kartı | Tamam | `8e1bde4a` |
| Rapor Merkezi + Rapor Arşivi | Tamam; Excel çıktısı gerçek XLSX (iOS CSV yazıyor) | `2cb242d6` |
| F15 Not defteri | iOS sayfasına getirildi | `d0a7c1d4` |
| F15 Aktivite + aktif süre (presence) | Tamam | `12f0b171` |
| F3 Firma sayfası + oluşturma sihirbazı | Tamam | `68f8451c`, `2146e96e` |
| F4 Personel sayfaları | Tamam | `00eab389` |
| F16 OSGB yönetici kökü (firma, ekip, atama, kayıt komutları, personel, analizler) | Tamam | `e7dafc3d`…`d7f4b69d` |
| F6 NOVA analizleri (liste, detay, raporlar, foto alımı, dosyalama, dosyalanmış bulgu) | Tamam | `cacd6217`, `4e2b273d` |
| F17 NOVA onboarding + giriş yüzeyi (yalnız pilot build) | Tamam | `3ffc1edb` |
| Firma rehberi Nova görünümü (arama, arşiv, boş durum, "Bilgi geçmişi") | Tamam | `962c21bc` |
| Çalışma alanı seçici: "OSGB oluştur" / "Davete katıl" | Tamam | `b9e4d949` |
| Takipte "Önceki Evrak Kayıtları" (salt okunur evrak takibi) | Tamam | `89f6062e` |
| Profil "Firmalarım" → Nova firma sayfası (kişisel hesap) | Tamam | `d9d3c351` |
| Kayıt düzenleme/silme (atama, acil durum planı, tatbikat) | Tamam | `3b00ecba` |
| OSGB uzmanı firma listesi (`isg_expert_companies_v1`) | Tamam | `5720042d` |
| Not defteri sunucu rollout'una bağlandı (yalnız pilot kökü) | Tamam | `f8b972ce` |
| Zil bildirimi kayda açılır; kabukta "Firma ekle" | Tamam | `3ea366e7` |
| Menü/ana sayfa sayaçları ekipman sayfasından | Tamam | `deaf3b94` |
| Personel yazma yetkisi + personel detayı yeni düzen + sertifika/belge sayfası | Tamam | `d23d0925`, `760a5117` |
| Ana sayfa yeni görünüm, firma satırlarında logo + profil ilerlemesi | Tamam | `46177c05`, `ed7856c8`, `994057b2` |
| Eğitim editörü 7 adım (firma → tür → konu → gün → eğitici → katılımcı → kontrol) + sertifika ekranı yeni akış | Tamam | `fa006e03` |
| Profil "Arkadaşını davet et" (referral kodu, paylaşım, ödül başlatma, kod kullanma, davet bağlantısı) | Tamam | `025d7e95` |

iOS'ta erişilemeyen (ölü) olduğu için taşınmayanlar: `NovaPPEFormPDF` (KKD form PDF'i),
`IsgWorkspaceTrainingAdvancedScreen`, analiz bölüm başlığı/risk özet kartı/madde çubuğu/defter paneli,
`NovaCompanyWorkspace.sectionView` akordeonu ve içindeki personel bölümü, dosya kütüphanesi firma filtresi
popup'ı, ekipman ipucu/süre satırı, uzman kabuğu "Canlı Akış" bloğu, `NovaChecklistWords.explain`,
onboarding "Bilgilerini düzenle" ekranı (yalnız QA ortam değişkeniyle açılıyor), `IsgWorkspaceDomainCreateEditor`
içindeki eğitim/risk/acil durum formları.

Bilinçli olarak açık bırakılanlar:
- Üretim (pilot olmayan) `CompanyListScreen` Nova dalı hâlâ basit buton listesi; iOS aynı yerde tam firma sayfasını
  açıyor. `feature:nova` → `feature:profile` bağımlılığı yüzünden doğrudan kullanılamıyor ve dal rollout arkasında.
- Üretim profilindeki not defteri kapısı (`NotebookUIRelease.enabled=false`) değiştirilmedi; iOS sunucu rollout'u okuyor.
- iOS'ta başka oturumda süren işler (KKD örnek formu, iş izni kütüphanesi, firma sayfası "Örnek formlar")
  Android'de de o oturum tarafından taşınıyor.
- Eğitim editörünün işyerisiz firma ve tek tehlike sınıfı kuralları `supabase/pilot-release/candidates` altındaki
  henüz dağıtılmamış backend adaylarına dayanıyor; iOS ile aynı durumda.

Doğrulama önizleme uygulamasında ve birim testlerle yapıldı; canlı staging doğrulaması kullanıcı girişini bekliyor.

Bilinen dışsal konular:
- `isg-contract-tests` modülü `core/data` kaynaklarını bağımlılıksız derlediği için HEAD'de de kırık (bu işten önce).
- `osgbPilot` staging debug paketini (`com.riskdetectedan.app.debug`) kullanıyor; ayrı paket için Firebase'de `com.riskdetectedan.app.osgbpilot` istemcisi kaydedilmeli.
- Canlı veri doğrulaması için staging hesabıyla girişi kullanıcı yapar.
