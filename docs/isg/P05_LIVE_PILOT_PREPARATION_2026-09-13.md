# P05 / NOVA — dar kapsamlı canlı pilot hazırlığı

> **Güncel karar:** Kullanıcı firmaları uygulamadan oluşturacak; firma adlarını önceden istemiyoruz. [Hesap bazlı oluşturma pilotu ve dar kurulum provası](P05_ACCOUNT_PILOT_CREATION_2026-09-13.md) bu belgedeki yalnız-okuma/önceden firma seçimi önerisinin yerini alır. Altı kaynaklı paket global backfill'i dışlayarak klonda doğrulandı; canlı deploy ve native bağlantı hâlâ bekliyor. Aşağıdaki içerik ilk hazırlık checkpoint'idir.

13 Eylül 2026. Yetki: pilotun hazırlık kontrolleri ve eksik sunucu korumaları. **Deploy, hesap/firma açma, veri yazma, mağaza yayını veya telefon kurulumu yetkisi bu teslimde kullanılmadı.**

## Karar

İlk pilot **yalnız okuma** olacak. Gerçek Auth oturumu ve mevcut firma verisi kullanılacak; yeni İSG ekranlarının yazma işlemleri sunucuda reddedilecek. Kullanıcı ve firma UUID'si birlikte izinli olmalı; istemcideki flag, uygulama sürümü veya JWT user metadata'sı izin yerine geçmez. Salt okunur pilotun bitmesi tüm P05 yazma yollarını otomatik açmaz.

Telefon için mevcut mağaza kimliği korunacak; ayrı tasarım uygulaması değil gerçek uygulamanın kontrollü geliştirme build'i hedefleniyor. Bu build telefondaki aynı uygulamanın yerini alabilir ve mevcut oturumu kullanabilir. Kurulum/onay öncesinde uygulama veri ve oturum davranışı ayrıca doğrulanmalı. Mağazaya gönderim yok.

## Canlıdan doğrulananlar — yalnız okuma

Supabase projesi `ppcrzemgiztzcgddbins` / `riskdetected`, durumu `ACTIVE_HEALTHY`, PostgreSQL `17.6.1.111`. `BEGIN READ ONLY` + 5 saniye statement timeout ile yalnız metadata ve toplamlar okundu; kullanıcı satırları, parola, token veya firma içerikleri çekilmedi.

- `private_isg` şeması yok; `isg_workspace_availability_v1` yok; `companies_isg_default` trigger'ı yok.
- Legacy `private.user_plan_tier(uuid)` var; toplam 8 firma var. Bu toplam pilot kapsamı değildir; tümünü allowlist'e alma yetkisi verilmedi.
- Son migration `20260908134026 / client_flow_diagnostics`. Yereldeki İSG adayları canlıda uygulanmış değil.
- `public` içinde adında `person`, `employee`, `workplace`, `department` geçen base table bulunmadı. Bu isim taraması farklı isim/JSON içinde veri olmadığının tam kanıtı değildir; yine de yeni P05 personel tablolarının canlıda dolu olduğu varsayılamaz.

## Bu tur eklenen sunucu koruması

Candidate: `supabase/migrations/20260913191226_isg_p05_readonly_pilot.sql` (CLI ile oluşturuldu).

- Private, RLS açık ve istemci/service-role tablo yetkisi olmayan `p05_pilot_grants`.
- Kesin `(actor_id, company_id)` anahtarı; wildcard/NULL firma yok; onay referansı, en fazla 30 günlük süre ve iptal tarihi.
- Mevcut `personnel` global anahtarı + güncel allowlist + güncel firma sahipliği birlikte denetlenir. Başlangıç anahtarı kapalı ve allowlist boştur.
- `active_actor()` ile gerçek, süresi geçmemiş ve iptal edilmemiş Auth session kontrolü korunur.
- P05'in ortak `require_company` sınırı tüm personel/directory/context yollarında kullanılır. Pilot v1'de genel `write_enabled=true` bile yazmayı açamaz.
- Global availability yalnız izinli firma varsa yeni çalışma alanını gösterir. Firma availability'si ayrıca tekrar kapsam kontrolü yapar; izinsiz firmanın adı/arşiv bilgisi dönmez. Cevap her zaman `can_write=false`.
- Grant/rollout okuma kilitleri, iptalin devam eden izinli okuma işlemini beklemesini sağlar. İptal commit olduktan sonraki istekte aynı token reddedilir. Daha önce telefona inmiş veriyi geri çekme garantisi yok; native cache temizliği ayrı kapıdır.
- Yeni public endpoint veya client DML yetkisi eklenmedi. Mevcut checked DEFINER availability girişi korunur; yeni yardımcı INVOKER ve istemciye kapalıdır.

Bu kontrol sadece **yeni P05 yolları** içindir. Eski uygulamanın firma/analiz/ödeme yollarını salt okunur hâle getirmez. Pilot UI bu eski yazma yollarına geçit vermeyecek şekilde ayrıca doğrulanmalıdır.

## Neden mevcut migration klasörünü doğrudan canlıya uygulamıyoruz?

1. İlk P05 adayı tüm firmaları `ensure_default` ile backfill ediyor ve `public.companies` üzerine yeni insert trigger'ı koyuyor. Flag kapalıyken de bu kurulum etkileri olur. Pilot öncesinde **yalnız seçili firma için bootstrap** ve pilot dışı insert yoluna etkisiz tasarım hazırlanmalı; global backfill/trigger mevcut hâliyle onay paketine giremez.
2. Aynı klasörde P06–P17 ve diğer adaylar var. Genel `db push` bu dar pilotun kapsamını aşar. Son dağıtım paketi yalnız incelenmiş P05 DDL/guard bağımlılıkları, açık sıra, hash ve transaction sınırlarıyla hazırlanmalı.
3. P05 dört temel adayının ve pilot guard'ın aynı onaylı kurulum transaction'ında kapalı başlaması gerekir. Ara aşamada tüm kullanıcılara açık P05 endpoint bırakılmamalı. DDL/lock süresi, yeni trigger ve FK etkisi klonda ölçülmeden uygulanmaz.
4. Deploy sonrası flag kapalıyken eski binary smoke + veri/fonksiyon fingerprint karşılaştırması yapılmalı. Kill switch yeni istekleri kapatır; DDL'yi veya yapılmış veri değişikliğini geri almaz. Acil durumda yeni şemayı DROP etme; erişimi kapat, incele.

## Yerel doğrulama

- **1071/1071 tekil sentetik PASS**, bunun 25'i yeni pilot kontrolü: boş allowlist, global flag bypass reddi, izinli okuma, bütün personel yazma türleri/directory write reddi, yanlış firma/sahiplik, süre/iptal/kill-switch, anonim ve iptal edilmiş oturum, client grant/RLS ve veri korunumu.
- **33/33 legacy-copy upgrade PASS**, 27 migration, 155 private RLS tablo; eski satır/helper koruma geçti. Bu geniş regression koşusu P05-only canlı kurulum provasının yerine geçmez.
- **442/442 foundation**, **488/488 tüm İSG script testleri PASS**; kümeler örtüşür.
- Advisor: İSG kapsamında **0 ERROR / 0 WARN / 291 INFO**. Private allowlist'in politika yokluğu varsayılan ret tasarımıdır; istemci tablo yetkisi ayrıca test edildi. Sentetik DB index bilgisi üretim yük kanıtı değildir.
- Geçici konteyner temizliği PASS; koşu kaynak hash'leri mevcut kodla eşleşir. İlk turdaki test aracı hatası (aynı advisor rolünün iki kez oluşturulması) giderildi; denetim tüm şema kurulduktan sonra bir kez çalışır.

[Hash'li kanıt özeti](evidence/P05_LIVE_PILOT_PREPARATION_2026-09-13.json). Bu kanıt `deployment_ready=false`, `release_ready=false`, `acceptance_ids_covered=[]` taşır. Native/build veya gerçek pilot hesabı kabulü yapılmış sayılmaz.

## Açılabilecek kapsam — henüz onaylanmadı

| Konu | Hazırlanan sınır | Onaydan önce eksik |
|---|---|---|
| Hesap | Gerçek Auth UUID | Kullanıcının belirteceği hesap doğrulanacak; token/parola istenmez. |
| Firmalar | Hesaba ait tek tek şirket UUID'leri | Firma adları/ID'leri, sahiplik ve amaç doğrulanacak; tüm firmalar otomatik seçilmez. |
| İşlemler | Firma availability, personel/rehber/context okuma | UI'nin eski yazma/ödeme/bildirim yollarına kaçmadığı kabul edilecek. |
| Yasaklar | P05 create/edit/archive/restore ve directory mutation | Yazma için ayrı action bazlı pilot v2 tasarımı/onayı gerekir. |
| Süre | En fazla 30 gün, önerilen ilk pencere 24 saat | Başlangıç/bitiş ve kapatma sorumlusu belirlenecek. |
| Diğer modüller | P06+ dağıtım dışı; yeni bildirim/ödeme/kampanya işi açılmaz | Mevcut canlı servis ayarlarına dokunulmayacak. |
| Build | Kendi telefonda kurulan kontrollü iOS build | NOVA gerçek root/service bağlantısı, ortam etiketi, cache/logout/erişim kaybı ve fiziksel cihaz kontrolü. |

## Sıralı yapılacaklar

**Dağıtım adayı bağımlılık listesi (deploy manifest'i değildir):**

- `20260913074153_isg_personnel_owner_rpc.sql` — global bootstrap/trigger nedeniyle mevcut hâliyle **bloklu**.
- `20260913081536_isg_workplace_context_assignments.sql` — P05 rehber/context genişlemesi.
- `20260913084736_isg_workspace_availability.sql` — mevcut availability sözleşmesi.
- `20260913092642_isg_personnel_reactivation.sql` — mevcut mutation sözleşmesi; pilot guard tüm yazmaları kapatır.
- `20260913191226_isg_p05_readonly_pilot.sql` — bu teslimdeki boş allowlist ve zorunlu salt-okunur kapı.

Diğer aday migration'lar bu pilotun kapsamı değildir. Tüm-faz test runner'ı geriye uyumluluk için 27 migration çalıştırır; bu listeyi canlı deployment listesi olarak kullanma. Salt-okunur pilot migration'ı temel adayların doğrudan client grant'lerini tek başına güvenli rollout'a dönüştürmez; transaction paketi ve scoped bootstrap kapısı ayrıca kapanmalıdır.

1. Hesap/firma seçimini kullanıcıdan al; UUID ve sahipliği yalnız gerekli alanlarla doğrula. Henüz grant yazma.
2. Global backfill/trigger'ı içermeyen P05 pilot kurulum paketini hazırla; yalnız seçili firmayı bootstrap et. Hash'li manifest ve canlı başlangıç checkpoint'ini onay paketine ekle.
3. P05-only kurulumu izole tam legacy klonunda çalıştır; kurulum/lock süresini ölç, eski yollar ve pilot dışı hesapla olumsuz kabulü tamamla. Tüm-faz upgrade bunun yerine geçmez.
4. Native pilot route'u, salt-okunur ekranlar, ortam etiketi, pilot dışı root fallback ve cache iptalini tamamla; cihazda staging/izole hedefle doğrula. Mevcut P05 native yazma kabulü bu yeni salt-okunur pilot build'inin kabulü değildir.
5. Kullanıcıya kesin hesap/firma/işlem/süre, migration diff, snapshot, kapatma ve izleme planını sun; **ayrı canlı uygulama onayı al**.
6. Onay sonrası kapalı deploy → eski akış smoke → tek hesap/tek firma okuma → kendi telefonda deneme. Write/provider/store erişimi açma.

Mevcut kullanıcıların “hiçbir şekilde etkilenmemesi” garanti edilmez: ortak DB, DDL kilitleri, connection pool ve sorgu yükü paylaşılır. Bu yüzden küçük kapsam, kısa timeout, ölçüm, eski binary kontrolü ve kapatma koşulları zorunludur.
