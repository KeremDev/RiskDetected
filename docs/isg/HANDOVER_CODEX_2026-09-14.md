# Devir notu — İSG geçişinde sunucu dilimlerini sürdürmek

> **Güncel native dilim:** [Menü ayrımı ve pano](P09_MENU_AND_BOARD_2026-09-14.md) — Uygunsuzluklar / Analizlerim / Analiz Yap / Uygunsuzluk Ekle dört ayrı destination, her biri tek sayfa; açılır filtreli fotoğraflı pano, popup kayıt detayı, klasör sekmeli analiz detayı, fotoğrafla başlayan elle giriş. **P18 dil taşımasının kırdığı dört izole `swiftc` sözleşme testi onarıldı** (test stub'ı ile; üretim kodu değişmedi) ve `newCompany`/`quickAdd` navigasyon kayması giderildi. Rollout **açılmadı**.

> **Güncel native dilim:** [Uygunsuzluk panosu ve analiz detayı](P09_RECORD_BOARD_2026-09-14.md) — çok firmalı filtreli pano, kayıt ekranı ve durum geçişleri (migration'ın kenar tablosuyla iki yönlü test edilmiş), resimle başlayan fotoğraf akışı + popup'lu firma/sektör/odak, ikon menülü analiz detayı ve bulgu popup'ı. Elle girişte fotoğraf adımı **kayda eklenmiyor**: `promote_clean_upload` temiz tarama sonucu istiyor, tarayıcı yok. Rollout **açılmadı**.

> **Güncel native dilim:** [Fotoğraf analizi akışı](P09_ANALYSIS_FLOW_2026-09-14.md) — fotoğraf → firma (firmasız seçenekli) → sektör (firmadan otomatik) → odak; NOVA analiz detayı (dört bölüm, bulgu düzenleme, rapor, seçileni firmaya aktarma); firmasız analiz ve sonradan atama; akordiyonlu elle giriş. Sunucu tarafı [P09 ikinci dilim](P09_NONCONFORMITY_DETAIL_2026-09-14.md) (`20260914190000`): detay alanları, generated skor/bant, `record_kind` ve `legacy_expert_item`. Rollout **açılmadı**. Elle girişte kanıt fotoğrafı adımı yok (P04 dosya sınırı kapalı).

> **Canlı pilot ilerleme yöntemi:** [NOVA firma akışı rollout kaydı](NOVA_LIVE_PILOT_ROLLOUT_2026-09-14.md). İlk doğrulama fiziksel iOS cihazındaki dar pilot firma yüzeyinde; cihaz/scope/read-back kanıtı olmadan canlı mutation veya genel rollout yapılmıyor.

> **Güncel cihaz teslimi:** [NOVA 2.0.3 (98)](NOVA_DEVICE_BUILD_98_2026-09-14.md) yeni akordeon/popup düzeltmeleriyle iPhone Kerem’e kuruldu ve açıldı. Test koşusu kullanıcı isteğiyle çalıştırılmadı; canlı veriler değişmedi.

> **Güncel cihaz teslimi:** [NOVA 2.0.3 (97)](NOVA_DEVICE_BUILD_97_2026-09-14.md) yeni tasarım düzeltmeleriyle iPhone Kerem'e kuruldu ve açıldı. Test koşusu kullanıcı isteğiyle çalıştırılmadı; canlı veriler değişmedi.

> **Güncel cihaz teslimi:** [NOVA 2.0.3 (96)](NOVA_DEVICE_BUILD_96_2026-09-14.md) iPhone Kerem'e kuruldu ve başarıyla açıldı. Build `NOVA_PILOT_BUILD` ile üretildi; yeni tasarım ve açık tema zorlaması aktif. Canlı mevcut veriler değiştirilmedi.

> **Son cihaz teslimi:** [NOVA 2.0.3 (95)](NOVA_DEVICE_BUILD_95_2026-09-14.md) iPhone Kerem'e 94 üzerine kuruldu ve açıldı. Son UI revizyonu cihazda; canlı backend ve izinler değişmedi.

> **Son telefon kurulumu:** [2.0.3 (94)](NOVA_DEVICE_BUILD_94_2026-09-14.md) iPhone Kerem'e 93 üzerine kuruldu ve açıldı. Görsel accordion/popup/görev alanı revizyonu cihazda. Canlı backend ve izinler değişmedi.

> **Son görsel talep uygulandı:** [Kapalı accordion / görsel formlar](UI_VISUAL_FORMS_2026-09-14.md). Durumlar okun solunda renkli rozet; açık kart renkli, başlangıçta tümü kapalı. İçerik ölçümlü popup. Görev giriş alanı, firma Güncelle/Sil önizlemeleri eklendi; kullanıcı isteğiyle yeni alanların sunucu bağlantısı sonraya bırakıldı. 7 XCUI senaryosu geçti. Telefon 93 değişmedi.

> **Build 93 sonrası yerel UI revizyonu:** [Merkez popup / firma kartı](UI_REFINEMENT_2026-09-14.md). Temsilci/destek bağımsız başlık, sağda iki durum, siyah başlık ikonları, firma kartında küçük skor halkası, kompakt dizinler ve merkez popup uygulandı. Personel görevi ve firma güncelle/sil hâlâ açık; mevcut pilot API'yi genişletmek gerekiyor. Yeni telefon kurulumu yok; telefon 93. Kullanıcı tekrar aynı gereksinimleri açıklamak zorunda bırakılmamalı.

> **Son telefon teslimi:** [2.0.3 (93)](NOVA_DEVICE_BUILD_93_2026-09-14.md) iPhone Kerem'e mevcut uygulama silinmeden kuruldu ve açıldı. Açık tema/özel pilot; canlı backend ve izinler değişmedi. Yeni modüllerin eksik servisleri hâlâ eksik. Aşağıdaki “telefon 92 / kurulmadı” ifadeleri önceki yerel turun tarihsel durumudur.

> **14 Eylül son yerel ilerleme — firma workspace:** [Güncel uygulama sınırları](COMPANY_WORKSPACE_SPEC_2026-09-14.md#mevcut-durumla-fark). 12 başlık için saf eşit-ağırlıklı skor, dinamik halka, accordion, personel liste/doğrudan ekleme ve dizin sheet girişleri uygulandı. 25 Node PASS (11 saf skor kontrolü dahil). Dosya/Evrak düğmeleri henüz devre dışı; diğer modül başlıkları veri bekliyor. Canlı toplam skor hesaplanamıyor, — gösteriliyor. Önceki form/logo/import açıkları sürüyor; tüm talep tamamlanmadı. Canlı DDL ve telefon kurulumu yapılmadı; telefon 92.

> **Son kullanıcı ek kapsamı:** [Tek sayfa firma çalışma alanı / skor / accordion sözleşmesi](COMPANY_WORKSPACE_SPEC_2026-09-14.md). Dosya/Evrak Ekle, dinamik skor, yerinde düzenleme ve sheet akışları, temsilci/destek ataması, risk/acil durum belgeleri, periyodik kontroller, kazalar, kurul/eğitim/diğer dosya/zimmet istendi. **Dört kategori / 25 puan reddedildi:** skor tamamlanan takip başlığı / toplam takip başlığı × 100 olacak; logo da dahil. Kapsayıcı ana başlıklar iki kez sayılmaz. Bu dosya uygulanmış özellik değil, yeni hedef ve bağımlılık kaydıdır.

> **ÖNCE 14 Eylül son UI notunu oku:** [Kompakt UI ilk paketi / tamamlanmayanlar](UI_ITERATION_2026-09-14.md), [NOVA tasarım ilkeleri](NOVA_UI_PRINCIPLES.md). Yerel 24 Node / 5 XCUI PASS; telefon hâlâ 92. Son talebin firma düzenleme, opsiyonel sorumlu iletişimi, logo/kırpma, personel görevi ve şablonlu toplu yükleme bölümleri açık. Gerçek arka plan dönüşünde taslak koruma da açık; yalnız geçici inactive/active sıfırlaması düzeltildi. Yeni deployment yok. Önceki notları güncel durum gibi okuma.

> **ÖNCE build 92 notunu oku:** [13 Eylül son UI/pilot teslimi](P05_UI_REVIEW_BUILD_92_2026-09-13.md). Son kullanıcı isteği: yeşil Yeni firma ekle butonu ekranın dibinde değil, son firma kartının hemen altında. V2 firma alanları + gerçek firma/personel/işyeri/departman sayıları canlıda; migration zinciri artık `20260913201043` + `20260913205739`. Tek pilot/süre değişmedi, eski kayıtlar korunuyor, telefon 2.0.3 (92). 1115 sentetik, 31 upgrade, 23 Node ve 3 XCUI PASS. Eğitim/uygunsuzluk/evrak/skor bağlantıları ve önceki pilot firmanın profil düzenleme akışı açık. Aşağıdaki build 91/tek migration açıklamaları tarihsel.

> **ÖNCE BUNU OKU — canlı pilot artık AÇIK:** [13 Eylül canlı açılış](P05_LIVE_ACTIVATION_2026-09-13.md). Kullanıcı ayrı canlı onay verdi. Migration `20260913201043`, 18 private RLS tablo, tek hesap read/write, bitiş 20 Eylül 23:11 TR. Mevcut firmalar değişmedi/taşınmadı; yeni şirketi kullanıcı telefondan girecek. Telefon build’i kurulu; gerçek create kabulü henüz yapılmadı. Tek birleşik migration’ın birebir SQL’i `supabase/pilot-release` audit mirror’da; **ana migration klasörünü canlıya db push etme veya altı candidate’ı uygulanmış diye işaretleme.** Yeni production DDL öncesi canlı baseline zinciri uzlaştırılmalı. Geri kapatma dosyası hazır ama çalıştırılmadı. Önceki “canlı kapalı” notları tarihsel checkpoint’tir.

> **En son aktif devam — NOVA telefon build’i kuruldu:** [Önce cihaz teslimini oku](P05_NOVA_DEVICE_BUILD_2026-09-13.md). Özel Debug 2.0.3 (91) iPhone Kerem’de kurulu/açıldı. Yeni root + firma create RPC/form + account-scoped Keychain retry bağlandı; 23 native kontrol, ilgili 22 script, 2 XCUI PASS. Canlı backend/allowlist/flag **değişmedi**; gerçek firma denemesi öncesi ayrı canlı onay, güncel checkpoint/ledger ve gateway kabulleri gerekiyor. Telefonda tasarımın kullanıcı tarafından görülmesi teyit bekliyor. Firma adı veya e-posta tekrar isteme; mevcut firmaları enroll etme. Aşağıdaki önceki native/build eksikleri tarihsel checkpoint’tir.

> **Aktif devam — hesap bazlı firma oluşturma pilotu:** [Önce son paketi oku](P05_ACCOUNT_PILOT_CREATION_2026-09-13.md). Kullanıcı firmaları uygulamadan oluşturacak; tekrar firma adları isteme. Hesap doğrulandı, canlıda izin açılmadı. Yeni create RPC/provenance/write gate ve P05-only klon paketi hazır: 1096 sentetik, 33 full upgrade, 27 pilot-only, 451 foundation, 497 script PASS. Native pilot root/create servis bağlantısı, fiziksel cihaz/legacy-writer yarış kabulü, migration ledger/deploy onayı açık. Eski app'in normal şirket insert'i pilot üyeliği vermez. Genel `db push` veya canlı activation yapma.

> **Aktif iş — P05 salt-okunur canlı pilot hazırlığı:** [Önce pilot hazırlık dokümanını oku](P05_LIVE_PILOT_PREPARATION_2026-09-13.md). Yerel allowlist/session/owner/TTL/write-deny kapısı tamamlandı; 1071 sentetik, 33 upgrade, 442 foundation, 488 script PASS. Canlıda yalnız metadata/toplam okundu; İSG şeması yok. **Deploy ve telefon kurulumu yapılmadı.** Hesap/firma seçimi, global backfill/trigger yerine scoped bootstrap, P05-only transaction provası ve native read-only route bekliyor. Genel migration push yapma; canlı uygulama için ayrıca onay al.

> **Önce bunu oku — P00'dan güncele son denetim:** [Faz matrisi, A01–A10 düzeltmeleri ve yapılacaklar](PHASE_ZERO_AUDIT_2026-09-13.md). 1046 tekil sentetik / 33 upgrade / 135 DB / 436 foundation / 482 script / 24 NOVA PASS; kümeler örtüşür, cleanup PASS. P01 kanıt/izolasyon, P04 TTL, P07 eşzamanlılık/tarih, P11 import/export ve P16 NULL scope düzeltildi. Candidate migration'lar değişti; önceden yüklenmiş yerel DB'ye CREATE dosyalarını yeniden uygulama. UI iterasyonu açık; P05 yerel kabulü korunur; gerçek provider/store/domain bağlantıları ve P19 yayın kabulleri tamamlanmadı. Aşağıdaki önceki devam notları tarihsel kayıttır.

> **En güncel devam:** [İnceleme düzeltmeleri / UI iterasyonu](REVIEW_FIXES_UI_ITERATION_2026-09-13.md). R1–R5 altyapı düzeltmeleri uygulandı: 1025 sentetik, 433 foundation, 24 NOVA PASS. UI denemeleri sürecek; ekranları final kabul etme veya rollout açma. Yıllık/review çözümü ve gerçek adapter/store bağlantıları hâlâ açık. Aşağıdaki inceleme ve writer uyarıları tarihsel kayıttır.

> **Önce son incelemeyi oku:** [Claude sonrası kod/plan incelemesi](CLAUDE_REVIEW_2026-09-13.md), `69a20166` üzerinden. 1007 sentetik / 424 foundation / 24 NOVA yeniden geçti; fakat kampanya ödülü ve winback için üç yüksek öncelikli açık var. Kabul defteri senaryo bazlı kanıtı henüz yeterince doğrulamıyor; “her zaman güncel cevap” ifadesi kaynak hash'i ve koşum doğrulaması garantisi değildir. Yeni faz eklemeden önce rapordaki düzeltme ve entegrasyon sırasını esas al.

> **Güncel devam:** [P19 kabul defteri ve bütünleşik prova](P19_INTEGRATED_REHEARSAL_2026-09-14.md): 263 kabulün fail-closed defteri (`covered 0, partial 20, blocked 166, unclaimed 77`, `release_ready=false`), 1007 sentetik PASS, 424 foundation PASS. **Yayın kapısı burada.** `node scripts/isg/acceptance_ledger.mjs` her zaman güncel cevabı verir.

> **Önceki devam:** [P18 NOVA dil ve erişilebilirlik kataloğu](P18_NOVA_LOCALIZATION_2026-09-14.md): 261 anahtar TR/EN, iOS Debug build PASS, foundation 412/412. **Uyarı:** `migrate_swift_localization_catalogs.mjs --apply` katalogları yeniden yazıp mevcut çevirileri siliyor — o dokümandaki yöntemi okumadan çalıştırma.

> **Önceki devam:** [P17 skor ve portföy çekirdeği](P17_SCORE_PORTFOLIO_2026-09-14.md): 997 sentetik PASS / 996 tekil, 32 upgrade PASS / 26 migration, 408 foundation PASS. `private_isg` 154 tablo, skor rollout'u kapalı, ağırlıklar onaysız, oracle elle hesaplanmış.

> **Önceki devam:** [P16 izleme ve admin çekirdeği](P16_OBSERVABILITY_ADMIN_2026-09-14.md): 966 sentetik PASS / 965 tekil, 32 upgrade PASS / 25 migration, 397 foundation PASS. `private_isg` 144 tablo, izleme rollout'u kapalı, ayrı repodaki operasyon paneli değiştirilmedi.

> **Önceki devam:** [P15 davet ve geri kazanım çekirdeği](P15_CAMPAIGN_CORE_2026-09-14.md): 932 sentetik PASS / 931 tekil, 32 upgrade PASS / 24 migration, 386 foundation PASS. `private_isg` 131 tablo, kampanya rollout'u kapalı, hiçbir mesaj gönderilmedi, ödüller P14 defterinden geçiyor.

> **Önceki devam:** [P14 abonelik lifecycle çekirdeği](P14_BILLING_LIFECYCLE_2026-09-14.md): 894 sentetik PASS / 893 tekil, 32 upgrade PASS / 23 migration, 375 foundation PASS. `private_isg` 120 tablo, projeksiyon `access_authority='legacy'`, rollout kapalı, mağaza/RC yapılandırması değişmedi.

> **Önceki devam:** [P12 SQL repository ve kalıcı bekleme](P12_REPOSITORY_WAIT_2026-09-13.md): 768 sentetik PASS / 767 tekil, 32 upgrade PASS / 18 migration, 331 foundation PASS. Gerçek izole PostgreSQL kullanıldı; sağlayıcı ve cihaz kaynağı sentetik, canlı kapalıdır.

> **Sonraki paket:** [P12 tek istekli işçi/APNs-FCM adaptörleri](P12_WORKER_TRANSPORT_2026-09-13.md) eklendi; foundation 298 PASS, 53 yeni davranış testi. Gerçek DB/credential bağlaması ve canlı aktivasyon yapılmadı. Aşağıdaki devir sonuçları tarihsel test turlarıdır.

> **Codex devralma sonucu (gerçek koşu: 13 Eylül 2026):** aşağıdaki envanter tarihsel devirdir. Bildirim kodundaki dört açık yeniden üretildi ve `20260914070001` ile düzeltildi. Son durum: 754 sentetik PASS (753 tekil ID), 31 upgrade PASS / 17 migration, 245 foundation PASS. [Güncel teslim, API değişikliği ve bekleyenler](P12_DISPATCH_SAFETY_2026-09-13.md). P12 gerçek sağlayıcıya bağlanmış veya kapanmış değildir.

14 Eylül 2026. Bu belge, bu depoda İSG geçişini **devralacak bir sonraki geliştirici veya ajan** içindir. Neyin bittiğini, neyin açık olduğunu, hangi kalıbın izlendiğini ve hangi tuzaklara düşüldüğünü tek yerde toplar.

## 1. Nerede duruyoruz?

P05 (firma/işyeri/personel) daha önce kapanmıştı. 13–14 Eylül'de eklenen sunucu dilimleri:

| Faz | Dilim | Migration | Faz dokümanı |
|---|---|---|---|
| P01/P03 | Olay dağıtım defteri + gölge kota defteri | `20260913110000`, `20260913113000` | [P01_P03](P01_P03_DISPATCH_AND_QUOTA_2026-09-13.md) |
| P04 | Dosya kabul matrisi, karantina, anti-TOCTOU promotion | `20260913130000` | [P04](P04_FILE_CORE_2026-09-13.md) |
| P06 | Mevzuat kaynağı, sürümlü kural, tarihli yükümlülük | `20260913150000` | [P06](P06_RULE_CORE_2026-09-13.md) |
| P07 | Eğitim kataloğu, yoklama birleşimi, değişmez tamamlanma | `20260913170000` | [P07](P07_TRAINING_CORE_2026-09-13.md) |
| P08 | Risk sürümleme ve tarih disiplini | `20260913190000` | [P08](P08_RISK_VERSIONING_2026-09-13.md) |
| P09 | Uygunsuzluk durum makinesi ve checklist | `20260913210000` | [P09](P09_NONCONFORMITY_CORE_2026-09-13.md) |
| P10 | §7.5 modülleri, iki paket hâlinde 12 başlık | `20260913230000`, `20260914010000` | [P10-1](P10_MODULE_CORE_2026-09-13.md), [P10-2](P10_MODULE_SECOND_2026-09-14.md) |
| P11 | Belge numarası/snapshot/export + import zinciri | `20260914030000` | [P11](P11_DOCUMENT_IMPORT_CORE_2026-09-14.md) |
| P12 | Bildirim omurgası, rıza kökeni, sahiplik/shadow, gönderim-anı kapısı | `20260914050000` | [P12](P12_NOTIFICATION_CORE_2026-09-14.md) |
| P13 | Kişisel not defteri, çakışma/tombstone, occurrence, teslim sahibi | `20260914070000` | [P13](P13_PERSONAL_NOTES_2026-09-14.md) |
| P14 | Kanonik lifecycle, hediye/indirim ayrımı, quote/intent/settlement, mutabakat | `20260914090000` | [P14](P14_BILLING_LIFECYCLE_2026-09-14.md) |
| P15 | Davet/winback, anti-abuse, qualification, bütçe, suppression | `20260914110000` | [P15](P15_CAMPAIGN_CORE_2026-09-14.md) |
| P16 | Teknik olay zarfı, teşhis zinciri, MFA/scope'lu admin ve audit | `20260914130000` | [P16](P16_OBSERVABILITY_ADMIN_2026-09-14.md) |
| P17 | Sürümlü skor politikası, açıklanabilir katkı, elle hesaplanmış oracle, portföy | `20260914150000` | [P17](P17_SCORE_PORTFOLIO_2026-09-14.md) |
| P18 | NOVA yüzeyinin TR/EN kataloğu ve erişilebilir kontrol adları | — (native, migration yok) | [P18](P18_NOVA_LOCALIZATION_2026-09-14.md) |
| P19 | Kabul defteri (263 senaryo) ve bütünleşik kill switch provası | — (probe, migration yok) | [P19](P19_INTEGRATED_REHEARSAL_2026-09-14.md) |

Toplam: `private_isg` şemasında **154 tablo**, hepsinde RLS açık, istemciye **sıfır** GRANT. Sentetik kabul koşusu **997/997 PASS** (996 tekil), tam legacy kopya upgrade **32/32 PASS** (26 migration), offline foundation **408 PASS**. Bu tablo yalnız sunucu dilimlerini sayar; araya giren P12 sertleştirme ve P13 sync/reminder API paketleri kendi dokümanlarındadır.

**Canlıya hiçbir şey uygulanmadı.** Bütün yeni `private_isg.rollout` satırları ve on iki modül anahtarı kapalı; mağaza, canlı DB, legacy kota otoritesi ve mevcut istemci sözleşmeleri değişmedi.

## 2. Değişmez kurallar

1. **Rollout kapalı doğar.** Migration hiçbir yerde `UPDATE private_isg.rollout SET ...` yapmaz; açma işi ayrı ve insan kararıdır.
2. **İstemciye GRANT yok.** Yeni fonksiyonlar `anon`/`authenticated`/`service_role` için EXECUTE almaz; sadece P05'in mevcut altı istemci RPC'si granted kalır. Yeni tablo eklerken `REVOKE ALL ON ALL TABLES IN SCHEMA private_isg ...` satırını tekrarla.
3. **Her tabloda RLS.** `CREATE TABLE` sayısı ile `ENABLE ROW LEVEL SECURITY` sayısı eşit olmalı; guard testleri bunu sayar.
4. **Her fonksiyonda `SET search_path=''`** ve tam nitelikli isimler.
5. **Onaylanmamış sayı, onaylanmış gibi durmaz.** V5'ten gelen limit/süre/eşik değerleri `*_needs_review` veya `content_approved=false` / `period_source='unapproved_fixture'` gibi açık bir işaretle saklanır.
6. **"İddia edilmeyecek" şeyler CHECK ile imkânsız yapılır**, varsayılan değerle bırakılmaz. Örnek: `CHECK(NOT official_integration)`, `CHECK(NOT authorises_work)`, `CHECK(NOT ai_text_is_official_record)`, `CHECK(authority='shadow')`, `CHECK(access_authority='legacy')`, `CHECK(NOT signature_material_stored)`.
7. **Legacy'ye yazılmaz.** `public.findings`, `public.analyses`, `public.reports` ve legacy kota helper'ları okunmaz/yazılmaz; yalnız referans taşınır.
8. **Takvim aritmetiği.** Yıl 365 güne, ay 30 güne çevrilmez; `private_isg.next_due_on` ve `make_interval` kullanılır.
9. **Bilinmeyen ≠ hayır.** Eksik kanıt `needs_review`/`review` üretir, sessizce "gerekli değil" olmaz.
10. **Test oracle'ı üretim fonksiyonunun ikinci çağrısı olamaz.** Beklenen değer elle hesaplanır, sabit olarak yazılır ve `CHECK(hand_computed)` / `CHECK(NOT computed_by_production_function)` ile işaretlenir.

## 3. Yeni bir dilim nasıl eklenir? (sırayla)

1. `supabase/migrations/<YYYYMMDDHHMMSS>_isg_<konu>.sql` — tablolar, indeksler, RLS, fonksiyonlar, `REVOKE`, `NOTIFY pgrst`. Yeni rollout özelliği ekliyorsan `rollout_feature_check` kısıtını **drop/add** et.
2. `scripts/isg/<konu>_probe.mjs` — `begin<Konu>Probe({synthetic,sql,concurrentSql,companyID,ownerID,pass})`, `synthetic!==true` ve eksik scope'ta **SQL'e dokunmadan** hata fırlatır. İçeride `CREATE SCHEMA isg_<x>_test` + sabit dağıtımlı `observe(kind,args)` fonksiyonu (dinamik SQL yok), sonra `mark(...)` kontrolleri.
3. `scripts/isg/<konu>_guard.test.mjs` — offline: mod reddi, rollout'un migration'da açılmaması, GRANT olmaması, tablo/RLS sayısı, domain kuralının kaynakta durması, runner bağı.
4. `scripts/isg/run_suite.mjs` — guard testini `foundation` paketine `push` et.
5. `scripts/isg/run_auth_restore.mjs` — import, `let <x>Probe;`, `stage='...'` ile çağrı (**`personnel-advisors` aşamasından önce**), `report.<x> = ...afterLogout()`, `source_sha256` listesine `.concat(mode.synthetic ? <x>Files : [])`.
6. `scripts/isg/p05_upgrade_probe.mjs` — migration'ı `p05UpgradeFiles` sonuna ekle, tablo sayısı ve rollout sayısı beklentilerini güncelle, yeni defterlerin boş replay edildiğini doğrula.
7. `.github/workflows/isg-foundation.yml` — migration yolunu **iki** `paths` bloğuna da ekle.
8. `scripts/isg/personnel_advisor_probe.mjs` — yeni tabloları `denyTables`'a, koşudan sonra rapor edilen `unused_index` anahtarlarını `reviewedFKIndexes`'e ekle.
9. Koş: sentetik → upgrade → foundation. Sonra `contracts/isg/v1/<konu>.md`, `docs/isg/<FAZ>_....md`, `docs/isg/evidence/<FAZ>_....json`, `EXECUTION_STATUS.md`, `GUNCEL_DURUM_2026-09-13.md`, ana plan satırı; en sonda commit.

## 4. Tekrar eden tuzaklar (hepsi bu turda gerçekten yaşandı)

| Belirti | Kök neden | Çözüm |
|---|---|---|
| `column reference X is ambiguous` veya sessiz yanlış eşleşme | plpgsql değişken adı sütun adıyla aynı (`scope`, `activity`, `version`, `row`, `state`, `position`, `local`) | Değişkeni yeniden adlandır (`contract_scope`, `label`, `revision`, `entry`, `next_state`, `ordinal`) |
| SQLSTATE **2201B** (invalid_regular_expression) | PostgreSQL regex tekrar sayısını **255** ile sınırlar; `{5,500}` geçersiz | Uzunluğu ayrı `length(...) BETWEEN` kontrolüne al |
| JSON `null` gönderilen alan "dolu" sayılıyor | `a->'field'` jsonb `null` döner, SQL NULL değil | Observe'da `nullif(a->'field','null'::jsonb)` kullan |
| SQLSTATE **42883** (undefined_function) | `date + bigint` operatörü yok | Sayıyı `integer` yap |
| Beklenmedik **CHECK_VIOLATION** | Hata kodu regex'i rakam kabul etmiyordu (`EXCEL_1900_LEAP_BUG`) | `^[A-Z][A-Z0-9_]{2,n}$` |
| `record "x" is not assigned yet` | Record değişkenine yalnız bir koşul dalında `SELECT INTO` yapılmış | Skaler değişken kullan veya koşulsuz ata |
| btree index satır boyutu riski | Uzun `text` sütunu UNIQUE anahtarında | `md5(sütun)` üzerinde unique index |
| Advisor aşaması kırmızı | Yeni tablolar/indeksler review listelerinde yok | `personnel_advisor_probe.mjs`'deki iki listeyi güncelle; gerçek FK indeks eksiğini **düzelt**, listeye ekleme |
| Python `str.replace` ile kod düzenlerken sayı bozulması | `"count(*)=3"` deseni `"count(*)=30"` içinde de eşleşti | Daha uzun/benzersiz desen seç, sonra `grep` ile doğrula |
| Kapı sırası varsayımı | Faz kapısı modül anahtarından **önce** cevap verir | Önce `FEATURE_UNAVAILABLE`, sonra `MODULE_UNAVAILABLE` bekle |
| Ham SQL ile CHECK denemesi hep "kabul edildi" görünüyor | Runner psql'i `VERBOSITY=sqlstate` ile çalıştırır; kısıt adı ve mesaj kaybolur, hata yalnız `AUTH_RESTORE_SQL_FAILED` olur | Denemeyi `observe` dispatcher'ına sabit bir `force_*` dalı olarak yaz; 23514 → `CHECK_VIOLATION` |
| "İmkânsız" iddia testi sessizce geçiyor | `UPDATE` hedef satır yokken 0 satır etkiliyor, CHECK hiç çalışmıyor | Kontrolü satır oluştuktan sonraya al ve ayrıca `bool_and(...)` ile doğrula |
| Sürüm beklentisi bir eksik | Her `advance_*`/`activate_*` çağrısı sürümü ayrı ayrı artırır | Zinciri say: grant(1) → advance(2) → activate(3) |
| Zaman bağlı sayaç 0 geliyor | Mutabakat/expiry kontrolü ilgili `timeout_at`/`expires_at` anından önce çalıştırılmış | Sentetik saati eşiğin ötesine taşı |
| `public.profiles`'a satır eklenemiyor | `id` → `auth.users(id)` FK'si var; uydurma UUID geçmez | İkinci hesabı sentetik fixture'dan oku, üçüncüyü `auth.users` + `profiles` olarak açıkça oluştur |
| Yazılan ret/suppression kaydı ortadan kayboluyor | Fonksiyon kaydı yazıp ardından `RAISE` ediyor; exception subtransaction'ı geri alıyor | Reddi `RAISE` yerine `{opened:false, reason_code}` gibi bir sonuç olarak **döndür** |
| Probe başka bir probe'un bıraktığı veriye takılıyor | `SELECT ... ORDER BY id LIMIT 1` gibi seçimler önceki dilim yeni hesap eklediğinde başka satır döndürür | Probe kendi hesaplarını açsın; aradığı özel durumu (`lifecycle_state='unknown'` gibi) açıkça sorgulasın |
| `unindexed_foreign_keys` bulgusu | Composite indeksin **baştaki** sütunu başka; FK'yi kapsamaz | FK sütunu için ayrı indeks aç; advisor listesine ekleyip susturma |
| `--apply` sonrası kataloglar küçülüyor, çeviriler kayboluyor | `migrate_swift_localization_catalogs.mjs` katalogları yalnız güncel envanterden **yeniden yazıyor**; zaten taşınmış anahtarlar envanterde olmadığı için siliniyor | Yeni anahtarları yakala, katalogları `git checkout` ile geri al, yalnız yeni anahtarları **eklemeli** birleştir; `nova_localization.test.mjs` küçülmeyi yakalar |
| Yerelleştirme envanteri "temiz" diyor ama ekranda Türkçe kalıyor | Tarayıcı ternary dallarını, `??` varsayılanlarını, `self.error =` atamalarını ve interpolasyon içindeki literalleri görmüyor; Türkçeyi yalnız diakritikle tanıyor | Yüzeyi doğrudan tara; "Aktif", "Kaydet" gibi diakritiksiz kelimeleri elle ara |
| İzole `swiftc` sözleşme testi aniden kırılıyor | Otomatik taşıma bağımsız bir modele `RDLocalization` yazdı; ana uygulama derlense de tek dosya derlemesi kırılır | Sunum metnini modelden görünüm katmanına taşı |
| Yalnız **bir kod yolunda** patlayan gölgeleme | Değişken adı sütun adıyla aynı ama o satıra sadece bazı dallarda ulaşılıyor (`route`) | `route`, `state`, `version`, `purpose`, `scope`, `position` gibi adları baştan kullanma |

## 5. Komutlar

~~~bash
node scripts/isg/run_auth_restore.mjs --synthetic-session          # tam sentetik kabul (Docker gerekir)
node scripts/isg/run_auth_restore.mjs --isolated-copy --p05-upgrade # tam legacy kopyada migration replay
node scripts/isg/run_suite.mjs foundation                          # offline guard/contract testleri
node scripts/isg/run_suite.mjs capacity-shadow|nova-design|password-auth
deno test --allow-read=contracts/isg/v1/fixtures supabase/functions/_shared/isg/mutation-context_test.ts supabase/functions/_shared/isg/mutation-outcome_test.ts
~~~

`--isolated-copy --p05-upgrade` modu `isg_restore_20260912_db` etiketli, ağsız restore container'ının **kopyasını** kullanır; kaynak container'a yazmaz. Sentetik mod müşteri verisine hiç dokunmaz. Her iki mod da geçici container'ları temizler; cleanup başarısızsa koşu yeşil sayılmaz.

## 6. Sıradaki işler

1. **P12'nin ikinci dilimi:** gerçek APNs/FCM/e-posta adaptörleri, onboarding rıza ekranı ve izin durumları, simulate/shadow/canary, gerçek cutover. P01'in dağıtım defteri hâlâ gerçek bir tüketici bekliyor.
2. **P04'ün ikinci dilimi:** gerçek AV/parser sandbox'ı, DOC/XLS pozitif güvenlik fixture'ları, bucket/storage policy, signed URL. Teknoloji ve maliyet kararı gerekiyor.
3. **P11'in render worker'ı:** PDF/XLSX üretimi ve görsel kabuller.
4. **P15'in ikinci dilimi:** qualification olaylarını gerçek P05/P06/P07 mutation'larından besleyen köprü, kampanya zamanlayıcısı, gerçek push/e-posta gönderimi ve ticari onaylar (K06–K10). Şu an olayları yalnız test yazıyor.
5. **P14'ün ikinci dilimi:** gerçek Apple promotional offer imzası ve Google offer token/replacement provası (iki store spike), RevenueCat/webhook → `record_billing_evidence` adaptörü, onaylı plan/fiyat katalogu ve `access_authority` cutover'ı. Sunucu çekirdeği hazır, hiçbir üretici henüz kanıt yazmıyor.
6. **P16'nın ikinci dilimi:** iOS/Android telemetri üreticisi ve ATT ekranı, ayrı repodaki operasyon paneli sayfaları ve Playwright kabulleri (K22 — panelin kendi AGENTS.md sınırları ve kullanıcı değişiklikleri korunarak ayrı görevde), domain mutation'larının teknik olay yazması, retention/silme kararı (K16).
7. **P17'nin ikinci dilimi:** ağırlık/tavan onayı (K15), P06–P10 üreticilerinin `score_subject_states` yazması, kritik uyarı üreticisi, firma/portföy ekranları ve gerçek veri üzerinde shadow projection.
8. **P18'in kalanı:** Android `strings.xml` TR/EN kabulü, 261 anahtarın dil incelemesi, gerçek cihazda İngilizce tur + VoiceOver/Dynamic Type, ana uygulamanın yeni köke geçişi, modüllerin gerçek servisleri, final marka/asset. Ayrıca migration aracının yıkıcı `--apply` davranışı düzeltilmeli.
9. **P19'un kalanı:** defterin `covered` sayısını sıfırdan yukarı taşımak. Sırayla en çok senaryoyu açan katmanlar: CROSS_LAYER_ACCEPTANCE (48), STORE_QA (67 ile örtüşüyor), COMPATIBILITY/X03 (16 kombinasyon), DELETION/X56, OPERATIONS+ADMIN, X57 RPO/RTO ölçümü, güvenlik ve yük koşusu. Ardından 77 `unclaimed` senaryoyu adlandırılmış kontrollere bağla.
10. **P20/P21:** mağaza güncellemesi ve stabilizasyon. İnsan onayı ve gerçek cihaz kanıtı isteyen kapılar.

Her fazın kendi dokümanında "Açık kalanlar" bölümü vardır; bir fazı kapatmadan önce oradaki maddeleri kontrol et. Hiçbir faz, kendi dokümanı "kapandı" demeden kapalı sayılmaz.
