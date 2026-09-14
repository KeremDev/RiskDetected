# NOVA canlı pilot — Eğitim takibi

14 Eylül 2026. Mevcut firma/personel pilotu üzerine operasyonel eğitim kaydı eklendi. Eski tasarım veya P07 demo ekranı değil, güncel NOVA popup/kart bileşenleri kullanılıyor.

## Kullanılabilir akış

- Sol menü → Eğitimler; alt + → Eğitim Ekle; firma detayı → Eğitimler.
- Firma seçimi, eğitim adı, eğitmen, tarih/saat, dakika cinsinden süre; isteğe bağlı yer/bağlantı, notlar ve kullanıcı tarafından girilen geçerlilik bitişi.
- Firmanın aktif personelinden katılımcı seçimi; kişi bazında katıldı/katılmadı yoklaması.
- Planlanan kaydı düzenleme, bitiş saatinden sonra en az bir katılım ile tamamlama, planı iptal etme.
- Tamamlanan/iptal edilen kayıt değiştirilemez; katılımcı adları kayıt anında saklanır.
- Eğitim/eğitmen araması ve durum filtreleri. Liste sunucudan 50'lik cursor sayfalarıyla yüklenir.
- Firma çalışma alanında en az bir tamamlanan eğitim varsa Eğitimler başlığı tamamlandı olur ve kayıt tamamlama skoruna katılır.
- Ağ sonucu belirsiz kalırsa Keychain'deki aynı mutation tekrar gönderilir; ikinci kayıt oluşmaz.

## Canlı bağlantı ve kapsam

Proje `ppcrzemgiztzcgddbins`. Yalnızca yeni eğitim tabloları ve RPC'leri eklendi; ana migration klasörü topluca push edilmedi. P05 süreli hesap/firma allowlist, oturum ve ücretli yazma kontrolleri aynen kullanılıyor. Genel kullanıcı rollout'u açılmadı.

- Canlı ledger: `20260914115818_isg_pilot_training_register`.
- Geliştirme kaynağı: `supabase/migrations/20260914112522_isg_pilot_training_register.sql`.
- Birebir audit mirror: `supabase/pilot-release/supabase/migrations/20260914115818_isg_pilot_training_register.sql`.
- İki dosyanın SHA256 değeri: `bfd11362c3ad1d802da382539800510c1add94f5354614749bcbf4c8c3e4246d`.
- Önceki canlı head: `20260913205739`; `require_company` tanım MD5 değeri önce/sonra aynı: `f9de5f413afb0d33e022b04b9923c3f5`.
- Public RPC: `isg_pilot_training_read_v1(p_company,p_id?,p_after?)`, `isg_pilot_training_save_v1(p_company,p_mutation,p_payload)`.
- Üç private tablo RLS açık, doğrudan authenticated tablo yazması ve anon RPC çağrısı kapalı. Yetkili RPC kapsam doğrulamasından sonra çalışır.

Audit mirror otomatik deployment projesi değildir. Geliştirme candidate'ını canlıda ikinci kez uygulama; gelecekteki migration zincirini bu ledger ile uzlaştır.

## Doğrulama

- Disposable yerel PostgreSQL: `scripts/isg/pilot_training_fixture.sql` + migration + `scripts/isg/pilot_training_check.sql`.
- Oluşturma, snapshot, idempotent replay/çatışma, yoklama, firma dışı katılımcı reddi, atomiklik, sürüm çakışması, tamamlama/kilit, pilot süre aşımı, gelecek tarih ve iptal kontrolleri geçti.
- Authenticated role üzerinden yerel public RPC okuması geçti.
- Canlı DB'de mevcut geçerli oturum/firma kapsamı ile authenticated role okuma → oluşturma → yoklama → tamamlama probu geçti. Tüm probe transaction'ı ROLLBACK edildi; kalıcı eğitim kaydı sayısı 0 kaldı. Bu SQL rol probudur, gerçek HTTP/JWT veya kullanıcı cihaz kabulü değildir.
- Son iOS Debug build 2.0.3 (99), `NOVA_PILOT_BUILD`, build başarılı. Fiziksel iPhone Kerem'e kurulum başarılı. Kanıtlar `output/isg/pilot/device-build-99-final.log`, `device-install-99.json`, `device-launch-99.json`.
- Geniş UI test koşusu yapılmadı; gerçek kullanıcı eğitim kaydıyla cihaz kabulü bekliyor.

Güvenlik advisor'ı tekrar okundu: önceki public SECURITY DEFINER ve sızmış parola koruması uyarıları sürüyor. Yeni tabloların policy olmadan RLS kullanması doğrudan erişimin kapalı olması nedeniyle kasıtlıdır. [RPC uyarısı](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [parola koruması](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

## Açık sınırlar

Bu dilim operasyonel eğitim/yoklama takibidir; P07 resmi eğitim kataloğu, mevzuat kaynaklı zorunlu saat/süre hesabı, sertifika/PDF üretimi, imza, dosya ekleri veya bildirim dağıtımı değildir. Bunlar hazır ya da mevzuata uygun ilan edilmez. Geçerlilik tarihi kullanıcı girişidir. Eğitim geçerliliği/sertifika uygunluğu ile firma kayıt tamamlama skoru aynı kavram değildir. Personel detayındaki eğitim sayacı bu dilimde bağlanmadı.

Kapatma gerekiyorsa mevcut pilot hesap read/write kapısı uygulanır; bu bütün pilotu etkiler. Eğitim verilerini silen otomatik rollback yoktur.
