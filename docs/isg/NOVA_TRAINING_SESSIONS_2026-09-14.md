# NOVA eğitim v2 — gerçekleşmiş, çok firmalı kayıt

14 Eylül 2026. Kullanıcı build 99 sonrası planlama/yoklama adımlarını istemedi; personel seçilip kayıt yapıldığında eğitim gerçekleşmiş kabul edilecek. Resmî Ek-2 şablonunu daha sonra kendisinin vereceğini belirtti. Sertifika şablonu kapsamı bu yanıtla ertelendi.

## Yeni akış

- Tüm firmalar varsayılanı; kompakt firma menüsü, eğitim/eğitmen araması.
- Kayıtlı eğitim seçimi: Temel İSG, temel eğitimin tekrarı (Yenileme), İşe Başlama.
- Kullanıcıya özel tekrar kullanılabilir eğitim başlığı; dakika ve geçerlilik ayı ile saklanır. 0 ay, son tarih tanımlı değil anlamındadır; sınırsız hukuki geçerlilik iddiası değildir.
- Hesap profilindeki uzman adı eğitmen alanına otomatik gelir, değiştirilebilir.
- Yüz yüze, online ve karma yöntemler. Tehlikeli/çok tehlikeli temel/tekrar eğitiminin tamamını online seçmek sunucuda reddedilir; işe özgü bölüm yüz yüze olmalıdır. İşe başlama sadece yüz yüzedir.
- Bir eğitimde en fazla 30 yetkili pilot firma, firma başına 1–500 personel; bunlar teknik istek sınırlarıdır, abonelik ürünü limiti değildir.
- Kaydet, seçili kişilerin katıldığına dair kullanıcının gerçekleşmiş eğitim beyanını yazar. Gelecek tarih reddedilir. Ayrı plan, yoklama veya bitiş saatini bekleme adımı yoktur.
- Her firmanın süre ve tekrar tarihi sunucuda kendi tehlike sınıfına göre hesaplanır; istemcinin süre/son tarih iddiası kullanılmaz.
- Düzenleme version kontrolü ve önceki snapshot ile; silme soft-delete ve kayıt geçmişini koruma ile çalışır. Bütün firmalar tek SQL transaction'ında güncellenir.
- Eski plan/iptal kayıtları korunur, kendiliğinden gerçekleşmişe çevrilmez. Kullanıcı düzenleyip katalog seçerek kaydedebilir.
- Firma skorunun eğitim katkısı mevcut v1 per-company projeksiyonlarından devam eder.
- Son kaydedilen sürümden kişi bazlı PDF eğitim kayıt belgesi dışa aktarımı eklendi. Bu PDF Ek-2 sertifikası değildir; açıkça imzasız kayıt çıktısı olarak işaretlidir.

## Resmî kaynaklar ve sınırlar

14 Eylül 2026'da [Bakanlık SSS](https://www.csgb.gov.tr/tr/sikca-sorulan-sorular/is-sagligi-ve-guvenligi-genel-mudurlugu/) ile [Bakanlık yüksekte çalışma açıklaması](https://guvenliinsaat.csgb.gov.tr/haberler/yuksekte-calismaya-yonelik-temel-egitime-dair-bilinmesi-gerekenler/) kontrol edildi. 2 Nisan 2026 düzenlemesindeki 13/14. madde süre ve tekrar kuralları Bakanlık açıklamasında yer alıyor:

| Katalog | Az tehlikeli | Tehlikeli | Çok tehlikeli |
|---|---|---|---|
| İlk temel eğitim | 8 ders saati / 36 ay | 12 ders saati / 24 ay | 16 ders saati / 12 ay |
| Temel eğitimin tekrarı | 8 ders saati / 36 ay | 8 ders saati / 24 ay | 8 ders saati / 12 ay |
| İşe başlama | En az 2 saat | En az 2 saat | En az 2 saat |

Temel eğitimde ders saati 45 dakika ders + 15 dakika ara olarak ele alınır; kayıt süresi bu toplam zaman dilimini gösterir. İşe başlama için bu katalogda periyodik son tarih tanımlanmaz. İş/risk değişiklikleri daha erken eğitim gerektirebilir; hesaplanan periyot tek başına uygunluk garantisi değildir. Yenileme etiketi temel eğitimin periyodik tekrarını ifade eder; uzun işten uzak kalma sonrası bilgi yenileme eğitimi ile eşitlenmez.

Hazır kurallar 2 Nisan 2026 öncesi tarihlere otomatik uygulanmaz. Karma gruplarda ortak ders verilmesi, her firmanın işe özgü içerik gereğini ortadan kaldırmaz. Bir hesabın adı otomatik gelmesi eğitmenin her konu için yetkili olduğunu doğrulamaz.

Resmî Gazete HTML/Ek-2 erişimi başarısız oldu. Kullanıcı şablonu daha sonra verecek. Katalog `content_approved=false`; bu yalnızca parametreleri doğrulanmış kayıt kolaylığıdır, tüm eğitim müfredatının uzman onayı değildir. Sınav, imzalı katılım kanıtı, LMS/online izleme, eğitmen yetkilendirme doğrulaması, Ek-2 resmî sertifika ve P07/P06 yükümlülük otomatik kapatma bu tur açılmadı. Kullanıcı kaydı, P07'nin kanıta dayalı completion sözleşmesini taklit etmez.

## Canlı migration

- Önceki head `20260914115818` → yeni ledger `20260914130700_isg_pilot_training_sessions`.
- Candidate `supabase/migrations/20260914122517_isg_pilot_training_sessions.sql`.
- Audit mirror `supabase/pilot-release/supabase/migrations/20260914130700_isg_pilot_training_sessions.sql`.
- İki SQL SHA256: `e88067dbf6d16e2262dd10b03e6da135d6f7a4d0d9c8d81d153a48dee157a729`.
- Mevcut 1 eğitim ve katılımcıları backfill sırasında değişmedi. Eski alanların önce/sonra MD5 değeri `0f2e7a6aceba380a3ee5d724c5779d14`; katılımcılar `9b40ee12be94fc072115b7ab9622be22`.
- Dört yeni private RLS tablo: katalog, oturum, revizyon, receipt. Mevcut per-company kayıtlar `session_id` ve firma snapshot'ı ile bağlandı. Doğrudan tablo erişimi kapalıdır; public invoker RPC private kontrollü helper çağırır.
- V2 read: `isg_pilot_training_sessions_v2(p_company?,p_after?)`. Yetkili tüm firma kayıtlarını 30'luk cursor sayfalarıyla verir, katalog ve `writable_companies` içerir.
- V2 write: `isg_pilot_training_record_v2(p_mutation,p_payload)`; save/delete/catalog eylemleri. Durable owner-scoped Keychain mutation ağ belirsizliğinde aynı istekle devam eder.
- Tüm eski/yeni firma kapsamları her yazma ve replay öncesi doğrulanır. Hesap/süre/abonelik gate değişmedi, genel rollout yok.
- V1 write artık yalnızca önceden commit edilmiş receipt replay'ine izin verir; yeni yazma `UPGRADE_REQUIRED`. Yeni v2 firmalı projeksiyonlar v1 read üzerinden skora görünür.

## Kanıtlar

- Yerel temiz DB sırası: `pilot_training_fixture.sql`, v1 migration, `pilot_training_sessions_fixture.sql`, v2 migration, `pilot_training_sessions_check.sql`.
- Çok firma; 8/16 saat ve 1/3 yıl; 8 saat yenileme; anında completed; tekrar gönderim/çatışma; firma filtresi; online sınırlaması; gelecek tarih; kullanıcı beyanı; yabancı katılımcı; rollback atomikliği; edit/sürüm/geçmiş; özel başlık/izolasyon; silme/replay; süre aşımı ve yetkiler geçti.
- Canlı authenticated SQL rol probu: tüm-firma/katalog oku → kaydet → düzenle → sil geçti; tamamı ROLLBACK. Var olan 1 kayıt kaldı; kalıcı test kaydı oluşturulmadı. Bu test gerçek HTTP/JWT veya cihaz kullanıcı kabulü değildir.
- Güvenlik advisor tekrar okundu: önceki 8 public SECURITY DEFINER uyarısı değişmedi; yeni eğitim public definer yok. RLS/no-policy INFO 93, eğitim tabloları 7; kapalı tablo+kontrollü private RPC modeli nedeniyle kasıtlı. Önceki sızmış parola koruması WARN sürüyor. [RPC uyarısı](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [parola koruması](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
- NOVA iOS 2.0.3 (100) `NOVA_PILOT_BUILD` build başarılı ve iPhone Kerem'e kuruldu. Build path mevcut `DeviceDerivedData99` önbelleği; gerçek Info.plist build değeri **100**. Son etiket/filtre düzeltmeleri için kanıtlar `output/isg/pilot/device-build-100-final.log`, `device-install-100-final.json`, `device-launch-100-final.json`.
- Geniş UI test turu yapılmadı. PDF dışa aktarımı derlendi; cihazdaki gerçek PDF görünüm/ibraz kabulü henüz yapılmadı.

Eğitim v1 ve v2 geliştirme candidate'larını canlıda tekrar uygulama. Canlı mirror ayrı ledger tarihlidir; ana migration klasörünü topluca prod'a push etme.
