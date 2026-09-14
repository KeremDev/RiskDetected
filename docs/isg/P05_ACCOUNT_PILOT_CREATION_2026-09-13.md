# P05 hesap pilotu — firmaları uygulamadan oluşturma

> **Devam teslimi:** [Yeni NOVA iPhone build’i kuruldu](P05_NOVA_DEVICE_BUILD_2026-09-13.md). Native root/create servis/form/pending bağlantısı ve özel cihaz build’i sonraki adımda tamamlandı. Bu belgenin build/kurulum yapılmadı ve native eksikler ifadeleri aşağıdaki backend hazırlık anını anlatır. Canlı deploy ve allowlist hâlâ yapılmadı.

13 Eylül 2026. Kullanıcı önceden firma adı vermek istemiyor; firmaları telefonda kendisi oluşturacak. **Bu karar, önceki yalnız-okuma + önceden firma seçimi önerisinin yerini alır.** Canlı deploy/activation/telefon kurulumu henüz yapılmadı.

## Hesap ve kapsam

Kullanıcının belirttiği e-posta, canlı Auth'ta yalnız okunarak tek hesaba eşlendi: e-posta onaylı, anonim değil, silinmemiş ve banlı değil. Erişimde e-posta veya metadata değil Auth UUID kullanılacak. Gerçek UUID/e-posta SQL adaylarına, fixture'lara veya kataloglara gömülmedi; canlı allowlist'e kayıt eklenmedi.

Mevcut haklar aynı read-only kontrol anında: **Plus, 5 aktif firma sınırı, 2 aktif firma**, P05'in beklediği geçerli paid subscription mevcut. Dolayısıyla o an 3 yeni aktif firma için yer var; bu sayı yeni işlem/abonelik değişikliğiyle değişebilir. Pilot ücretsiz ek kapasite veya abonelik override'ı değildir.

## Uygulanan sunucu değişikliği

Candidate: `20260913193231_isg_p05_account_pilot_creation.sql`.

- Süreli ve iptal edilebilir `p05_pilot_accounts`: account read/write izni ayrı; varsayılan kapalı ve tablo boş. Global `personnel` anahtarı ayrıca zorunlu.
- Yeni `isg_pilot_company_create_v1(p_mutation,p_name,p_hazard_class)` RPC: firma adını ve tehlike sınıfını uygulama gönderir; owner veya mevcut company ID gönderemez. Auth session yeniden doğrulanır, owner sunucuda belirlenir.
- Yeni firma + pilot kaynak kaydı + firma izni + varsayılan işyeri **aynı transaction** içinde oluşur. İlk aşamadaki API adı/tehlike sınıfını kapsar; diğer firma form alanları ve edit/archive uçları için native ürün sözleşmesi ayrıca tamamlanmalı.
- `p05_pilot_company_origins` yalnız bu özel oluşturma yolunun ürettiği firmaları tanımlar. Eski firmaya yalnız manuel firma grant'i eklemek pilot yazma hakkı vermez. Global ekran erişimi ilk firma henüz yokken account izniyle mümkündür.
- Mutation ID + istek hash'i tekrarları aynı firmaya bağlar; farklı istek aynı ID'yi kullanamaz. Firma silinse bile opaque receipt saklanır, aynı isteğin tekrarından yeni firma üretilemez. Hesap silme origin kayıtlarını temizler.
- Sadece yeni pilot firmanın P05 personel/rehber/context yolları açılır; mevcut session, owner, arşiv, ücretli plan ve sürüm/audit/receipt kontrolleri korunur. Salt-okunur account modu, firma veya account iptali, süre dolması ve global kapatma yeniden denetlenir.
- Yeni şirket oluşturma yolu mevcut `company_limit_for_user`, plan helper'ı ve şirket yazma trigger'ını değiştirmez. Pilot create istekleri hesap satırı kilidiyle seri hâle gelir. **Eski REST writer ile eşzamanlı kota yarışı bu turda uçtan uca kabul edilmedi**; legacy korumaların korunması böyle bir yarışın olmadığı anlamına gelmez.
- P05'in yeni global company insert hook'u kaldırılır; legacy `companies_enforce_write_rules` korunur. Normal eski şirket oluşturma yolu pilot üyeliği veya yeni işyeri üretmez. Native pilot build **özel RPC'yi kullanmalı**; mevcut App Store uygulamasında firma oluşturmak otomatik pilot kayıt oluşturmaz.
- Public wrapper INVOKER, private oluşturucu mevcut P05 mimarisindeki gibi checked DEFINER'dır. Bunun RLS bypass yetkisi owner/session/paid/quota kontrolleriyle sınırlanır; client/service-role private tablo yazma yetkisi yoktur. Operasyonel denetim ve gerçek gateway/native kabulü hâlâ gerekir.

Yeni P06+ bildirim/ödeme/kampanya worker'ları açılmadı. Yeni firma gerçek `public.companies` satırı olduğundan mevcut uygulamadaki listeye de girebilir ve mevcut kotayı tüketir; “görünmez test verisi” değildir. Yeni pilot UI'nin eski analiz/ödeme/logo-upload gibi yan etkilere çıkışı ayrıca sınanmalı.

## Dar, tek transaction kurulum paketi

`scripts/isg/p05_pilot_bundle.mjs` sadece altı incelenen P05 kaynağını birleştirir:

1. Personnel owner RPC — **yalnız tek global backfill satırı açıkça çıkarılır**.
2. Workplace/context/directory.
3. Workspace availability.
4. Personnel reactivation.
5. Önceki salt-okunur pilot tabanı.
6. Hesap + yeni firma oluşturma pilotu.

Her kaynağın transaction sınırı doğrulanıp kaldırılır; bütün paket tek `BEGIN/COMMIT` altında, hesaplar ve flag'ler kapalı kurulur. Son kaynak yeni global company insert hook'unu commit'ten önce kaldırır. Kaynak/boundary değişirse derleyici hata verir; sessiz geniş kapsamlı dönüşüm yoktur. Kaynak ve çıktı SHA256'ları manifest'tedir. Derleyici SQL çalıştırmaz, credentials/ağ erişimi veya otomatik deployment içermez.

Yerel inceleme çıktıları: `output/isg/pilot/P05_REVIEW_BUNDLE.sql` ve `output/isg/pilot/P05_REVIEW_MANIFEST.json`. Bunlar genel migration push veya canlı uygulama yetkisi değildir. Altı kaynakta ilk hâli korunan global backfill, yalnız bu incelenmiş paket derlemesinde dışlanır; ham migration klasörünü canlıya push etme.

İzole kopya modu: `node scripts/isg/run_auth_restore.mjs --isolated-copy --p05-pilot-upgrade`. Yalnız mevcut güvenlik kontrollerinden geçen yeni, ağsız disposable klonda çalışır. Başlangıç yedeği ve canlı kaynak değişmez.

## Doğrulama

- **1096/1096 tekil sentetik PASS**; yeni hesap/firma oluşturma dilimine ait **25** kontrol. Önceki salt-okunur pilot regresyonu da önce çalışır.
- **33/33 tam legacy upgrade PASS**; 28 candidate migration, 157 private RLS tablo.
- **27/27 yalnız P05 paketli legacy klon PASS**; altı kaynak/18 private RLS tablo, eski satırlar ve legacy plan/kota helper'ları değişmedi, mevcut firmalara sıfır yeni başlangıç kaydı, yeni global şirket insert hook'u yok. Paket çalışması bu klonda **213 ms**; canlı lock zamanı veya RPO/RTO ölçümü değildir.
- **451/451 foundation**, **497/497 tüm İSG script testleri PASS**; kümeler örtüşür. İlk paket testinde rakam içeren `p05_*` tablo adlarını eksik sayan envanter regex'i yakalandı, düzeltildi ve yeniden geçti.
- Advisor İSG kapsamında **0 ERROR / 0 WARN / 293 INFO**; geçici konteyner cleanup PASS. Kaynak ve rapor hash'leri son kontrolde eşleşir.

[Kanıt, koşular ve paket hash'i](evidence/P05_ACCOUNT_PILOT_CREATION_2026-09-13.json). Bu tur yeni iOS build/native kabulü yok; `deployment_ready=false`, `release_ready=false`.

## Telefona kurmadan önce kalanlar

1. NOVA pilot root'u ve bu yeni create RPC'sinin iOS servis/form bağlantısı; isim+tehlike sınıfı dışındaki alanların kapsamı.
2. Pilot dışı hesapta eski root; pilotta yalnız izinli yeni firma listesi; izin iptali/logout/account switch'te cache ve pending işlem temizliği. Başarısız pilot çağrısından legacy create'e sessiz fallback olmayacak.
3. Firma create retry/pending durumunun native kalıcılığı; eski firma edit/archive ve eski servis çıkışlarının pilot arayüzünde sınırlandırılması.
4. Fiziksel cihaz/gateway doğrulaması, gerçek legacy writer ile yarış ve fault testleri, pilot aksiyonlarının operasyonel izleme/limitleri.
5. Güncel deploy checkpoint'i, paket için migration ledger kayıt/geri dönüş planı, imzalı build ve yalnız bu hesap için başlangıç/bitiş penceresi ile read/write açılış sırası. **Canlıya uygulama ve allowlist açılması için ayrıca onay.** İnceleme bundle'ı tek başına canlı migration ledger stratejisi değildir.

Kullanıcıdan firma isimleri tekrar istenmeyecek. Mevcut 2 firma otomatik pilota alınmayacak. Canlıdaki diğer kullanıcıların ortak DB/DDL/yükten mutlak sıfır etkilenmesi garantisi verilemez; kapalı kurulum ve küçük pilot bu riski sınırlar.
