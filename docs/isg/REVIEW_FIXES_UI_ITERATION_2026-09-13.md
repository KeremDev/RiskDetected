# İnceleme düzeltmeleri ve UI denemelerine hazırlık

13 Eylül 2026 · `codex/isg-transition-foundation` · temel commit `69a20166`.

## Kapsam

Kullanıcı inceleme sonrasında gerekli düzeltmeleri istedi; UI tarafında çok sayıda deneme/değişiklik yapılacağını belirtti. Bu paket UI tasarımını, navigasyonu, ana uygulama kökünü veya mağaza/canlı ayarları değiştirmez. Ekranların final kabulünü erkenden kapatmaz.

Supabase becerisinin yetki ve doğrulama kontrol listesi uygulandı: fonksiyonlar private ve invoker kaldı, yeni istemci grant'i eklenmedi, rollout açılmadı; gerçek SQL ve advisor kontrolleri izole ortamda çalıştırıldı. İlgili resmi referans: [Database functions](https://supabase.com/docs/guides/database/functions).

P15 migration'ı henüz canlıya uygulanmamış geliştirme adayı olduğundan mevcut aday dosyası düzeltildi. **Önceki adayı uygulamış kalıcı bir geliştirme DB'si bu dosyayı yeniden çalıştırmamalı:** migration CREATE ifadeleri içerir. O ortam için ayrı ileri migration veya disposable fixture yeniden kurulum gerekir. Canlı migration uygulaması yapılmadı.

## Yapılanlar

| İnceleme bulgusu | Bu pakette yapılan |
|---|---|
| R1 kampanya/sürüm bağı | Award öncesi claim–campaign–qualification version doğrulanır; replay bile yanlış sürümü kabul etmez. Qualification sürümü FK ve indeksle tutulur. Başka kampanyanın bütçesi dolu ve ödülleri geçerli olsa da claim'i ödüllendiremez. |
| R2 ödül sınıflandırması | Qualification anındaki tüm production projection'lar, plan dönemi ve ödül kodları snapshot'a alınır. Sonraki plan değişikliği/award parametresi kazanılmış türü değiştirmez. Grace, unknown, review flag ve eksik billing verisi Free sayılmaz. Yıllık/belirsiz claim kalıcı rejected yerine qualified/pending kalır. |
| R3 winback | Contact aşaması ortak `winback_eligibility` kontrolünü yeniden çağırır. Diğer store'daki aktif kayıt, hold/pause, refund/revoke, unknown/review ve sonradan açılan hediye teması engeller. Rıza, zaman ve TTL kontrolleri korunur; gönderildi iddiası üretilmez. |
| R4 kabul kanıtı | Covered için tam case_id + layer + başarılı tekil test + artefaktın aynı senaryo beyanı + güncel kaynak hash'leri aranır. Global API/SECURITY full etiketi başka senaryoya kanıt yerine geçmez. Aynı kısa DEL-01 kimliği iki bölüme ödünç verilemez. |
| R5 katalog writer | Mevcut anahtarlar, insan çevirileri, locale'ler, plural/device variations ve metadata korunur. Yeni üretim yalnız eksik alan/locale/anahtar ekler. Gerçek writer geçici katalog kopyalarında iki kez test edilir; ikinci çalıştırma byte seviyesinde değişiklik üretmemelidir. |

`evaluate_referral_qualification` artık dördüncü, opsiyonel `p_plan_period` parametresi alır; verilmezse `unknown`. Bu private fonksiyonun gelecekteki sunucu adaptörü dönemi doğrulanmış store kataloğundan sağlamalı; istemci beyanı aktarmamalı. Award'taki eski period parametresi çağrı uyumu için kaldı fakat ödül türü seçiminde kullanılmaz.

Katalog güncellemesi mevcut locale içeriğini otomatik değiştirmez. Mevcut metni yeniden çevirmek veya insan çevirisini değiştirmek bilinçli, ayrı bir içerik düzenlemesi olmalıdır. Bu pakette shipping `.xcstrings` veya Swift/Compose UI dosyaları değiştirilmedi.

## Kapanmayan ürün ve entegrasyon işleri

- Yıllık bankalama, davet edilenin hediyesinin bu bekleme durumundan bağımsız çıkarılması ve billing-review çözüm akışı henüz uygulanmadı. Pending kayıt korunur; bu yollar için tamamlandı iddiası yok.
- Store kataloğu/RevenueCat adapter'ı, gerçek Free durumunu doğrulayan kaynak ve store redemption anındaki uygunluk kontrolü açık. Eksik projection artık otomatik Free ödülü üretmez.
- Contact kaydı gerçek provider gönderimi değildir. Worker bağlandığında gönderim sınırında tekrar uygunluk/rıza kontrolü gerekir.
- `scenario-evidence.json` bağlama formatı hazır, bindings henüz boş. Eski kısa-id iddiaları yalnız envanter olarak korunur; 263 senaryo otomatik geçmiş kabul sayılmaz. Yeni koşuların `acceptance_checks` alanı ve kaynak bağımlılıklarıyla adlandırılarak bağlanması gerekir.
- UI denemeleri, Android/iOS paritesi, gerçek modül ekranları, cihaz/store kabulü ve P19–P21 yayın kapıları açık kalır. Bunlar bu altyapı düzeltmesinin ön koşulu yapılmadı.

## Doğrulama

Son doğrulama: **1025/1025 sentetik PASS (1024 tekil), 433/433 foundation, 24/24 NOVA; cleanup PASS**. Kampanya probe'u 55 kontrol içeriyor. Gerçek katalog writer'ının geçici kopyalarda iki çalıştırması dahil 5 katalog testi geçti; `--check` PASS (bekleyen 0). `git diff --check` temiz. Upgrade ve mobil build bu tur yeniden çalıştırılmadı; UI/native kaynakları değiştirilmedi.

[Taşınabilir kanıt özeti](evidence/REVIEW_FIXES_UI_ITERATION_2026-09-13.json); tam yerel rapor `output/isg/runs/synthetic-auth-0i8hMm/REPORT.json`, run_id `1d4574fc-e010-445a-a30a-d18f23b215d1`. Son koşu 18:39:45–18:42:08 UTC. Son koşuda notification-device revoke/read kontrolü de geçti; önceki tekil başarısızlık izleme notu olarak korunur.

Yeniden çalıştırma:

```sh
node scripts/isg/run_suite.mjs foundation
node scripts/isg/run_suite.mjs nova-design
node scripts/isg/run_auth_restore.mjs --synthetic-session
node scripts/isg/acceptance_ledger.mjs
node scripts/migrate_swift_localization_catalogs.mjs --check
```

İlk koşudaki test fixture sözdizimi hatası düzeltildi. İlk SQL koşusu yeni FK indeksinin advisor'ın incelenmiş indeks listesine eklenmesini gerektirdi; indeks kaldırılmadı. Sonraki bir koşu değişmeyen notification-device revoke/read kontrolünde durdu; yazma başarısını ayrı doğrulayan ve tek read snapshot kullanan tanı adımı eklendi. Bu tek başarısızlığın üretim kök nedeni bulunduğu iddia edilmiyor; başarısız koşu kanıtları silinmedi.

## Sonraki çalışma sırası

1. UI denemelerini mevcut izole NOVA host'ları üzerinde sürdür; tasarım değişiklikleriyle birlikte yalnız ilgili görsel/davranış kabullerini güncelle.
2. Paralel bir ürün kapanışı iddiası olmadan, seçilen ekranın gerçek domain→API→native zincirini tamamla; worker/store/catalog bağlantıları için ayrı teknik dilimler aç.
3. Yıllık/review kararları ve gerçek mağaza kanıtı olmadan kampanyaları açma. Release gates'i UI denemesi için gevşetme.

Önceden var olan legacy belge silmeleri ve artifact dizinleri korundu. Commit/push, canlı DB değişikliği ve mağaza gönderimi yapılmadı.
