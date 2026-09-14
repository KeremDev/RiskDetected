# P05 — telefon geri bildirimleri / build 92

13 Eylül ekran görüntülerine göre NOVA pilot arayüzü güncellemesi.

## Uygulanan değişiklikler

- Menüden İşletme Hafızası ve Ziyaretler, hızlı eklemeden Ziyaret Ekle kaldırıldı. Periyodik Kontroller menü başlığı eklendi; modül henüz açılmadı. Eski rota değerleri yalnız uyumluluk amacıyla tutuluyor.
- Ana sayfadan Canlı Akış kaldırıldı. Özet, pilot kapsamındaki aktif firma/personel/işyeri/departman kayıtlarını sunucu üzerinden sayıyor. Dönem etiketi “Güncel”; bu sayılar aylık değil.
- Firma ekleme butonu, kullanıcının son düzeltmesine göre son firma kartının **hemen altında**, boş listede boş durum mesajından sonra. Ekranın altına sabitlenmez.
- Firma/personel/dizin sayfalarında 44 pt dokunma alanlı, 17 pt ikonlu ortak geri düğmesi. “Panele dön” tekrarı kaldırıldı.
- Firma Detayı sabit başlığı; firma adı/ikonu ve tehlike, sektör, personel, uygunsuzluk, evrak, tamamlanma etiketleri. Kompakt iki sütunlu bölüm kartları ve renkli küçük ikonlar.
- Personel detayında doğrudan arşivleme giriş noktası: onay gerekir, fiziksel silme yok, geçmiş/audit korunur. Mevcut dayanıklı mutation ve belirsiz sonuç tekrar deneme akışı yeniden kullanılır.
- Yeni Firma formu NOVA kartları/ikonlarıyla yeniden düzenlendi. Firma adı, tehlike sınıfı, sektör zorunlu; e-posta, beyan edilen çalışan sayısı ve sorumlu personel isteğe bağlı.
- Sorumlu eklenirse adıyla bir personel kaydı da aynı işlemde oluşur. Beyan edilen çalışan sayısı ile kayıtlı aktif personel sayısı birbirine karıştırılmaz.
- Bildirim çanı kart arka planına alındı. Alt gezinme çubuğu içerikle üst üste gelmeyecek biçimde yerleşime dahil edildi.
- `DEBUG && NOVA_PILOT_BUILD` açık temayı uygulamanın kökünde seçer; normal binary'nin kullanıcı tema tercihi korunur.

## Veri ve dağıtım sınırı

- V1 firma oluşturma servisi ve build 91'in bekleyen kayıtları korunur. V2 sektör/ek alanları atomik kaydeder; aynı mutation ile farklı alanlar gönderilirse çakışma hatası döner.
- Yeni özel tablo `private_isg.p05_company_profiles`: RLS açık, istemci tablo yetkileri yok. İki yeni public INVOKER wrapper, private checked DEFINER üzerinden aktif oturum/pilot/şirket sahipliği denetimine gider.
- Eski firma kayıtlarına sektör veya sorumlu tahmin edilerek yazılmaz. Daha önce oluşturulmuş pilot firmada eksik sektör “—” olabilir.
- Hiçbir yeni hesap allowlist'e eklenmez; süre veya global rollout genişletilmez. Şirket kotası ve ücretli plan kuralları değişmez.
- Uygunsuzluk/evrak/tamamlanma kaynakları P05 canlı pilotuna bağlı değil: API `null`, UI “—” gösterir. Bu, sıfır veya %100 değildir. P17'nin açıklanabilir skor politikası yerine form doluluk puanı uydurulmaz.

## Doğrulama

- Native servis testi: 34 Swift kontrolü; V1 dayanıklı retry/oturum izolasyonu ve V2 doğrulama/parametreler.
- 23 Node testi geçti (native servis kontrolü bunun içinde).
- 3 XCUI testi geçti: form zorunluları, firma özeti, personel arşiv onayı, butonun kart altındaki konumu, normal kullanıcının eski root'u.
- Simülatör fixture'ı yalnız `DEBUG && NOVA_PILOT_BUILD && targetEnvironment(simulator)` ve açık test argümanıyla çalışır. SDK, ağ, Keychain, gerçek firma/personel kullanmaz.
- Tam Xcode cihaz build 92 ve imza doğrulaması yapıldı.
- İzole geri yüklenmiş P05 temelinde ek migration provası: eski kayıtlar/kota yardımcıları değişmedi, rollout açılmadı.
- Sentetik Auth + PostgREST testi: **1115 kontrol PASS**, içinde yeni **19 profil senaryosu**; cleanup PASS.
- Swift gerçek navigation corpus: **82 senaryo / 206 geçiş**. Session host: **92 senaryo / 416 geçiş + 6 Binding kontrolü** PASS.
- Başlangıç test hataları: yerel HTTP test istemcisinin endpoint allowlist'i güncellendi; tekrarlanan test kimliği düzeltildi; yeni profil FK'sına indeks eklendi. Policy olmayan özel tablo bilinçli default-deny; bunun dışındaki bulgular otomatik kabul edilmedi.

## Bekleyenler

- Eğitim ekleme/katılım/tamamlama gerçek modül bağlantısı. Çalışmayan kayıt düğmesi tamamlandı diye sunulmaz.
- Uygunsuzluk, evrak, tamamlanma skoru gerçek kaynak entegrasyonu; P06/P07/P09/P11/P17 kapsamları ayrıca doğrulanıp açılmalı.
- Periyodik Kontroller ekranı ve işlem akışı. Yalnız menü başlığı eklemek modül teslimi değildir.
- Önceden yaratılmış pilot firmaların yeni profil alanlarını uygulamadan düzenleme akışı.
- Gerçek telefonda kullanıcının giriş yaparak yeni V2 firma ve isteğe bağlı sorumlu kaydı denemesi. Test için canlı firmalar eklenmedi/silinmedi.

## Son dağıtım sonucu

- Canlı migration: **20260913205739_isg_p05_company_profile_overview**. Birebir audit mirror: `supabase/pilot-release/supabase/migrations/20260913205739_isg_p05_company_profile_overview.sql`.
- Remote ledger ve yerel SQL SHA256 aynı: `2be9935e04d8982dcbf9750d3dbbb79c77d277810bb14ab478df3ca6ecdfe37f`.
- Tek pilot hesap/süre değişmedi. Firma, personel, hesap allowlist ve firma grant satır hash'leri dağıtım öncesi/sonrası aynı. Legacy helper hash: `e61b8d817d8917fdb99d2f44364b8414`.
- Yeni tabloya **0** canlı profil seed edildi. Eski pilot firma ve personel kullanıcının ekran görüntülerinde ve salt-okunur kontrolünde mevcut; yeni form testleri için gerçek kayıt eklenmedi.
- Canlıda mevcut oturumla authenticated SQL-role/rollback kontrolü: **1 firma / 1 personel**, bağlı olmayan metrikler `null`. Bu doğrudan telefon HTTP testi yerine geçmez; kullanıcının V2 form denemesi açık.
- Security advisor delta: **0 yeni WARN/ERROR**, bir yeni INFO (`rls_enabled_no_policy`) — private default-deny tablo, client SELECT/DML yetkileri sıfır. FK indeksleri yerel advisor ile kontrol edildi.
- Son ön-yedek: `backups/isg-p05-predeploy-ZXmxsX/predeploy.dump`, SHA256 `6532b360544ddc3da01a0de15e9089c5e3ddd16b30b768076600c2dca27d7376`. Arşiv okunabilirliği doğrulandı; bu yeni arşivin tam restore'u ve Storage binary yedeği yapılmadı.
- Son sentetik rapor: `output/isg/runs/synthetic-auth-Ng4HoA/REPORT.json` (**1115 PASS**).
- Son P05-only upgrade raporu: `backups/isg-auth-service-restore-20260912-pWF5fj/REPORT.json` (**31 PASS**).
- Son XCUI sonucu: `test_sim_2026-09-13T20-51-12-024Z_pid84322_afa9185d.xcresult` (**3 PASS**). Görseller: `output/isg/pilot/ui-review-92-final/`.
- Telefon: **iPhone Kerem / iPhone 17 Pro Max**, **2.0.3 (92)**, `com.riskdetected.app`, uninstall yapılmadan güncellendi. Build `output/isg/pilot/DeviceBuild92Final.xcresult`, log `device-build-92-final.log`, kurulum kanıtı `device-install-92.json`, açılış kanıtı `device-launch-92.json` aynı `output/isg/pilot/` klasöründe.
- Genel `supabase db push` yapılmadı. Audit mirror artık iki uygulanmış migration içerir; `candidates/` altındaki SQL yeniden uygulanmamalıdır.
