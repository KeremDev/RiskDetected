# OSGB Faz A — başlangıç doğrulaması

> Bu belge değişiklik öncesi başlangıç fotoğrafıdır. Yerel uygulama sonrası güncel kanıt için [OSGB uygulama durumuna](OSGB_IMPLEMENTATION_STATUS_2026-09-17.md) bakın.

17 Eylül 2026 · HEAD `6eebab8946c627f42d13415cff1b8dc5007cc1ce` · branch `codex/isg-transition-foundation`.

Testler ürün kodu değiştirilmeden çalıştırıldı. Bu teslimin dosyaları dört OSGB belgesi ve çevrimdışı envanter aracıdır. Yeni tenant şeması henüz yok; aşağıdaki sonuçlar OSGB izolasyonu test edilmiş anlamına gelmez.

## Çalıştırılan kontroller

| Komut | Sonuç | Gerçekte doğruladığı |
|---|---|---|
| `node scripts/isg/run_suite.mjs foundation` | **655 geçti, 4 başarısız / 659** | Mevcut foundation source/contract/guard testleri. Yeşil baseline yok. |
| `node scripts/isg/run_suite.mjs nova-design` | **181 geçti, 13 başarısız / 194** | Mevcut tasarım/routing/kopya guard testleri. Görsel cihaz kabulü değil. |
| `node scripts/modules/run_pilot.mjs --completed-records` | **PASS**, exit 0 | İzole PostgreSQL container'ında mevcut operasyon modülü regresyonu; kişisel dosya, finding source, shared filing, ownership/pilot gates dahil. |
| `node --test scripts/isg/pilot_native.test.mjs` | **4/4 geçti**, exit 0 | Swift kaynakları derlenip şirket skoru (11), scene lifecycle (27), retry/owner/session (44) kontrolleri çalıştı; dördüncü test statik pilot giriş kontrolü. |
| `deno test --deny-net --allow-read=contracts/isg/v1/fixtures supabase/functions/_shared/isg/mutation-context_test.ts supabase/functions/_shared/isg/mutation-outcome_test.ts` | **350 geçti, 0 başarısız**, exit 0 | Ortak mutation envelope/outcome fixture'ları. |
| `node scripts/isg/osgb_repo_inventory.mjs` | JSON üretildi ve parse edildi | 458 SQL dosyası, 466 table declaration, 301 farklı tablo ismi, 223 literal client callsite, 25 Edge entrypoint. Canlı şema sayımı değil. |

Suite'lerde ortak kontroller bulunabileceğinden bu sayılar tek bir benzersiz test toplamı olarak toplanmaz. Foundation/design çalıştırmalarının sonuna log göstermek için eklenen `tail` shell exit kodunu maskeleyebildiği için başarı değerlendirmesi runner'ın **fail** sayılarından yapıldı; ikisi de başarısız kaydedildi.

Ortam: macOS arm64, Node `v26.7.0`, Deno `2.7.14`, Swift `6.4`, Docker server `29.2.1`. CI workflow Node 24 kullanıyor; sürüm farkı CI karşılaştırmasında kaydedilmeli.

Tam iOS app archive/build, simülatör UI testleri, fiziksel iPhone kurulumu, Android Gradle build, store sandbox satın alma, canlı tenant/RLS, staging restore veya production migration çalıştırılmadı. Yerel Swift harness derlemesi tam uygulama build'i değildir. DB testi sentetik baseline/stub helper kullanır; gerçek deployment ledger'ın replay'i veya canlı RLS kanıtı değildir.

## Başarısız testlerin tam listesi

Aşağıdaki kontroller inceleme borcudur. Metin/simge arayan testin başarısızlığı tek başına runtime hatası kanıtı değildir; fakat özellikle yerelleştirme ve yetki/ürün metinleri otomatik olarak “eski test” denilerek yok sayılmamalı. Bu keşifte test beklentileri değiştirilmedi.

| Suite | Test dosyası/satırı | Başarısız beklenti / inceleme konusu |
|---|---|---|
| foundation | `scripts/isg/emergency_plan_support_staff_guard.test.mjs:54` | Team editor'da `supportStaffPicker` beklentisi; roster/manuel isim gönderme davranışı. |
| foundation | `scripts/isg/notice_feed_guard.test.mjs:137` | Okundu olayı ile navigate çağrısının beklenen kaynak sırası. |
| foundation | `scripts/isg/nova_localization.test.mjs:107` | Bütün NOVA localization key'lerinin tr/en catalog karşılığı. |
| foundation | `scripts/isg/nova_localization.test.mjs:137` | Ekranlarda raw literal metinler; company/personnel/analysis vb. |
| nova-design | `scripts/isg/nova_appointments.test.mjs:27` | `noQualificationNote` kullanım beklentisi. |
| nova-design | `scripts/isg/nova_appointments.test.mjs:34` | `noRequiredCountNote` kullanım beklentisi. |
| nova-design | `scripts/isg/nova_appointments.test.mjs:53` | Atama asset referansı beklentisi. |
| nova-design | `scripts/isg/nova_checklists.test.mjs:43` | Ürün checklist listesi bulunmadığında açıklama beklentisi. |
| nova-design | `scripts/isg/nova_document_tracking.test.mjs:146` | Firma başlığının portfolio tracker üzerinden okunma beklentisi. |
| nova-design | `scripts/isg/nova_drills.test.mjs:28` | Planlama/gerçekleşme ayrımı metni. |
| nova-design | `scripts/isg/nova_drills.test.mjs:85` | Plansız tatbikat empty-state localization key'i. |
| nova-design | `scripts/isg/nova_equipment_add_discoverability.test.mjs:14` | Header Ekipman Ekle metni/key'i. |
| nova-design | `scripts/isg/nova_equipment_add_discoverability.test.mjs:23` | Firma detayından add sheet açma kaynağı. |
| nova-design | `scripts/isg/nova_equipment_add_discoverability.test.mjs:41` | Dismiss sonrası equipmentAdding sıfırlama kaynağı. |
| nova-design | `scripts/isg/nova_ppe_handovers.test.mjs:29` | Signed copy notu beklentisi. |
| nova-design | `scripts/isg/nova_ppe_handovers.test.mjs:102` | NovaPPEScreen route wiring kaynak beklentisi. |
| nova-design | `scripts/isg/nova_risk_assessments.test.mjs:62` | Uzmanın belirlediği periyodun attribution metni. |

## Kanıt ve kaynak kaydı

Girdi dosyaları kullanıcı tarafından Downloads'tan sağlandı; içerikleri repo içine topluca kopyalanmadı. Sürüm eşlemesi için SHA256:

| Girdi | SHA256 |
|---|---|
| `ISGADA_OSGB_MULTI_TENANT_INTEGRATION_PLAN_2026-09-16.md` | `2e8d44197cb43dc4d5089f8500ec1c2348f0ba02fbe10f6aaf377fd902829e3f` |
| `deep-research-report-2.md` | `08a513fef50c993794d68aacb94d20b1c02049bec9046d2980e1750ba7f07d82` |

Ham test logları bu makinede geçici `/tmp/isgada-osgb-{foundation,design,modules,native,transport}.log` dosyalarında. Repoya ham log/credential/receipt/production veri eklenmedi. Logların kalıcı arşivlendiği iddia edilmez; komutlar yukarıda tekrar çalıştırılabilir. Bu koşunun SHA256 kayıtları:

| Log | SHA256 |
|---|---|
| foundation | `27017fc50050d23cceabfb7278e892c26bf0c06a2277345356292b134335b853` |
| design | `1632f08facd1f0cfe86a3e25f73ee22f4f93e7807167da6721f5da5106518da3` |
| modules | `f84866c88cdeb73fcc520575ddb51e4dd8eabb3871ee7fcbc89840612fa0fce1` |
| native | `efe9706a0f328f4ee6e1f863a410cf2b7299f6f964938846386dec29d0f2a404` |
| transport | `0e42c5c17c1252088e9f0ebc9f064102a0f6e95feb00333c26e28f0c3be75d75` |

## Doğrulanmamış noktalar ve sonraki kapılar

| Konu | Durum / ne zaman gerekli |
|---|---|
| Canlı migration/RLS/grant/flag durumu | Bu çalışmada remote sorgu yapılmadı. B0 deployment manifest + rehearsal öncesi alınmalı. Root/mirror varlığı tek başına canlı kanıtı değil. |
| Mevcut admin frontend | Bu checkout'ta bulunamadı; backend tabloları mevcut. F başlamadan repo/route konumu gerekir. |
| Firma/aktör owner ilişkisi | Kaynak FK'lerinde doğrulandı; gerçek veri anomali sayısı bilinmiyor. B/C dry-run raporu gerekli. |
| Kişisel satın alma/usage bakiyesi | RevenueCat/legacy code yolu bulundu; gerçek kullanıcı bakiye ve store binding uzlaştırması yapılmadı. G/H öncesi doğrulanmalı. |
| Store güncel API ve katalog | Bu faz SDK/store API implementasyonu yapmadı. H sırasında resmi doküman ve gerçek ürün konfigürasyonuyla doğrulanmalı. Fiyat veya limitsiz hak uydurulmadı. |
| Storage fiziksel object/metadata uyumu | Kaynak yolları bulundu; bucket envanteri ve gerçek byte reconciliation yapılmadı. G/K işi. |
| Realtime/arama/worker effective izinleri | Statik indeks tamamlayıcıdır; dinamik sorgu ve runtime subscription garantisi vermez. Her D domain'inde negatif kabul gerekli. |
| Tam app/ci parity | Yerel suite sonuçları yukarıda. iOS/Android tam build ve CI Node24 parity sonraki kod PR'ında gerekli. |

Faz A çıktıları hazırdır. Faz B sırası [uygulama planında](OSGB_PHASE_B_PLAN.md) tanımlıdır; tamamlanmamış tenant, billing, admin, devir ve storage işleri bu raporda uygulanmış gösterilmez.
