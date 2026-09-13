# P12 — devir kontrolü ve güvenli gönderim hakkı

Doğrulama tarihi: **13 Eylül 2026**. İncelenen devir kaydı `HANDOVER_CODEX_2026-09-14.md`, kaynak başlangıcı `ce4b74fc`. Belge adındaki 14 Eylül, koşu tarihi değildir.

**Sonuç: bu güvenlik dilimi yerel olarak tamamlandı. P12'nin tamamı kapanmadı; canlıya uygulanmadı.** Claude'un P01/P03–P13 sunucu dilimleri mevcut ve toplu izole kabulde çalışıyor; bunlar tamamlanmış iOS/Android modülleri anlamına gelmiyor. P05'in önceki yerel kapanışı korunuyor.

İnceleme derinliği: devir/commit envanteri ve toplu regresyon yeni sunucu dilimlerinin tamamını kapsar; ayrıntılı gönderim davranışı ve eşzamanlılık incelemesi bu tur P12'ye odaklandı. Bütün fazların her fonksiyonunun bağımsız güvenlik denetiminden geçtiği iddia edilmez.

## İncelemede bulunanlar ve yapılan düzeltmeler

İlk dört sorun, yalnız kaynak okumayla değil, yeni migration uygulanmadan **önce eski fonksiyonları çalıştırarak** yeniden üretildi:

| Eski davranış | Yeni davranış |
|---|---|
| Geleceğe planlanmış iş erkenden gönderilebilir görünüyordu | `scheduled_for` ve retry zamanı gelmeden `NOT_DUE`; durum beklemede kalır |
| Gece işlenen gündüz işi, sessiz saati planlama saatinden hesaplıyordu | Gerçek kontrol zamanı ve işin timezone'u kullanılır; 21:00 dahil, 08:00 hariç aday sınırları doğrulandı |
| Dört paralel işçi aynı işe `allowed=true` alabiliyordu | Satır kilidi + tekil UUID hakkı; sekiz paralel işçiden yalnız biri gönderim hakkı alır |
| İlk hatadan sonra rıza geri alınsa da tokensız ikinci sonuç `sent` olabiliyordu | Eski endpoint kapalı; kesin geçici ret sonrası her deneme yeni token ve güncel izin kontrolü ister |

Ek olarak:

- Push için OS izni, e-posta için ayrı kanal rızası ve `caps_approved` kapısı zorunlu; onaysız aday değerler canlı politika sayılmaz.
- Aynı hesapta farklı işlerin kapasite rezervasyonu sıralanır: iki paralel iş, günlük tek slot için yarışınca yalnız biri kazanır.
- `accepted` sonucu aynı tokenla tekrar kaydedilirse aynı receipt döner; başka token veya çelişen sonuç kabul edilmez. Eski denemenin geç gelen aynı yanıtı yeni denemeyi geri alamaz.
- Kesin geçici ret: 30 saniyeden başlayan, 3600 saniyeyle sınırlı üstel bekleme; en çok 10 deneme. Kalıcı ret `dead` olur.
- Ağ sonucu belirsizse ya da hakkın süresi dolarsa `uncertain`: otomatik tekrar gönderim yok. Süresi dolan hakkın henüz receipt'i yoksa aynı tokenın kesinleşmiş sonucu yeniden gönderim yapmadan kaydedilebilir.
- İlk rıza yazımı da sahip kilidini alır; eski zaman damgası opt-in yapamaz, eşit zaman damgasında opt-out kazanır.
- Firma/sahip composite FK ve indeks eklendi; hem bulunmayan hem gerçekten başka hesaba ait firma reddedildi.
- Devam eden/belirsiz gönderim varken üretici devri reddedilir; güvenli devirde önceki üreticinin bekleyen ve retry bekleyen işleri iptal edilir.
- Üretici henüz kayıtlı değilken satır kilidi alınamayacağı için ilk sahiplik yazımı da amaç/tür anahtarlı transaction kilidiyle sıralanır. Paralel ilk kayıt + devir, uçuşta olan işin sahibini değiştiremez.
- Eski build fallback'i, kategori/cihaz sahibi kontrolü, shadow ve açık kişisel alarm davranışları **son migration üzerinde** de doğrulandı.

[Güncel API ve durum akışı](../../contracts/isg/v1/notification-backbone.md) · [Migration](../../supabase/migrations/20260914070001_isg_notification_dispatch_safety.sql) · [Çalıştırılabilir kabul](../../scripts/isg/notification_dispatch_probe.mjs) · [Makine kanıtı](evidence/P12_DISPATCH_SAFETY_2026-09-13.json)

## Toplu test sonucu

| Koşu | Sonuç | Kanıt |
|---|---|---|
| Son sentetik Auth/DB/regresyon | **754 PASS**, 0 FAIL; **753 tekil kontrol kimliği** | `output/isg/runs/synthetic-auth-vpJUDe/REPORT.json` |
| Bu pakete ait kontroller | **38 PASS**: dört eski-kod karşı örneği + 34 son-durum kontrolü | Aynı raporda `notification_dispatch_*` |
| Tam legacy kopyada upgrade | **31/31 PASS**, **17 migration**, 107 RLS tablosu, istemci tablo GRANT sayısı 0 | `backups/isg-auth-service-restore-20260912-R4vwFi/REPORT.json` |
| Offline foundation | **245/245 PASS** | `node scripts/isg/run_suite.mjs foundation` |
| Supabase advisor | İSG kapsamındaki 203 bulgunun tamamı INFO; kapsamda WARN/ERROR yok | Son sentetik raporun `personnel_advisors` alanı |

`local_smtp_code_received` mevcut runner'da iki farklı mail kontrolünde aynı kimliği kullanır; toplam kontrol sayısı farklı varyasyon sayısıyla aynı değildir. Önceki başarılı koşular 745 ve 753 kontroldü. İlk foundation koşusunda yeni guard'ın boşluğa duyarlı `stage=` araması başarısız oldu; whitespace bağımsız aramayla düzeltildi. İlk-kayıt yarışı kabulü eklenince test fixture'ındaki `safety.first-registration`, episode türünün izin verdiği karakter kümesine uymadığı için koşu durdu (667 tamamlanmış kontrol, cleanup PASS); fixture `safety.first_registration` olarak düzeltildi. Başarısız koşu da kanıtta saklanır. Upgrade koşuları başarılıydı.

Bir sonraki koşu 12 kontrol sonrası mevcut `session-guard` aşamasında `AUTH_RESTORE_LOCAL_TOKEN_INVALID_CLAIMS` ile durdu; yeni migration'a ulaşmadı, cleanup PASS. Bu kayıttan hangi claim'in sebep olduğu belirlenemedi. Auth doğrulaması değiştirilmedi/gevşetilmedi; aynı kodla yeniden koşuldu. Bu tekil yerel altyapı arızası, çözüldüğü iddia edilen bir uygulama Auth hatası değildir.

İki restore modu da geçici container temizliğini PASS olarak doğruladı. Legacy satır ve mevcut helper fingerprint'leri değişmedi. Sentetik test müşteri verisi kullanmadı; upgrade kaynak restore'a değil, ağsız geçici kopyasına uygulandı. Ham backup raporu repoya taşınmadı.

Advisor'daki INFO kayıtları özel şemada bilinçli default-deny/RLS ve küçük sentetik örnekte kullanılmamış indeks bildirimleridir. Yeni composite FK indeksi açıkça incelenerek listeye eklendi. Bu sonuç genel canlı veritabanında sıfır bulgu veya üretim performans kabulü anlamına gelmez. Supabase becerisinin güvenlik kontrolü doğrultusunda istemci yetkileri açılmadı, `SECURITY INVOKER` ve boş `search_path` korundu.

## Migration sırası

Dosya Supabase CLI `migration new` ile üretildi. CLI'nin gerçek tarihli `20260913131235` sürümü depodaki P12/P13 dosyalarından önceye düşüyordu. Yeni dosyanın sürümü, mevcut son bağımlılık `20260914070000` sonrasındaki **`20260914070001`** olarak sıralandı. Önceki migration'lar değiştirilmedi; bu numara canlı uygulama zamanı değildir. Tam kopyada zincir sırası test edildi.

## Açık kalanlar — bitmiş sayılmayacak işler

1. APNs/FCM/e-posta adaptörleri, sağlayıcı hata eşlemesi, doğrulanmış cihaz/token/izin kaynağı, en az yetkili işçi rolü ve gerçek P01 tüketicisi.
2. Onboarding/profil rıza ekranları, native token yaşam döngüsü, iOS/Android izin ve hedef kayıt erişim kabulleri.
3. Domain schedule sürüm güncelliği, baskılanmış işi yeniden planlama, belirsiz receipt için incelemeli mutabakat ve işçi çöküşü operasyon aracı.
4. Onaylı sıklık/sessiz saat politikası, simulate/canary, legacy watermark eşlemesi ve gerçek cutover.
5. DB kontrolü ile dış sağlayıcı çağrısı atomik değildir. Hakkın alınması ağ çağrısına bitişik olmalı; sonradan rıza iptalinin uçuşta olan çağrıyı geri alabildiği veya exactly-once teslim garanti edildiği iddia edilemez.

Bu tur mobil kod, bundle/package kimlikleri, mağaza sürümü, abonelik otoritesi ve canlı müşteri kayıtları değişmedi. Native testler tekrar çalıştırılmadı; bu paket sunucu değişikliğidir. Canlı rollout kapalı kaldı.
