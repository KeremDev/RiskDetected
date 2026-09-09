# RiskDetected Android 2.0.0 (10) — Production Runbook

Bu belge yalnız RiskDetected Android'in ilk Google Play Production sürümü içindir. Genel
framework, Wear/TV/Automotive/XR ve örnek uygulama adımları kapsam dışıdır.

## Değişmez yayın koordinatları

- Paket: `com.riskdetectedan.app`
- Sürüm: `2.0.0 (10)`
- Track: Production
- Ülke: yalnız Türkiye
- Yayın: Google onayından sonra otomatik
- Kaynak: temiz ve push edilmiş tek commit SHA

## 1. Kaynak ve backend kapısı

- Çalışma ağacında commitlenmemiş dosya bırakma.
- Uzakta uygulanmış eğitim kartı ve Onaylı Defter migration'larının repoda bulunduğunu doğrula.
- Build 10'u `analysis_engine_v4` ve `analysis_result_hub_v1` Android allowlist'lerine ekleyen
  forward-only migration'ı uygula; `android_release_policy.latest_build` değerini değiştirme.
- Migration ledger farkları nedeniyle `supabase db push --include-all`, toplu history repair veya
  eski local-only migration'ları çalıştırma.
- `analyze-v4`, `analyze-vnext`, `analysis-result-sections` ve Onaylı Defter worker'larının test ve
  production sürümlerini karşılaştır; yalnız farklı olanları deploy et.

Çıkış: build 10 runtime gate'leri açık, Android 7/8/9 ve iOS 87/88 allowlist'leri korunmuş,
`latest_build < 10`.

## 2. CI ve artifact kapısı

GitHub Actions'ta `android-release-candidate` workflow'unu `expected_version_code=10` ile tam
commit SHA üzerinde çalıştır.

Zorunlu çıktılar:

- imzalı ve minify edilmiş `app-release.aab`;
- `bundletool validate` ve signature/16 KB/ELF/asset/secret doğrulama kaydı;
- `mapping.txt`, R8 configuration ve native debug symbols;
- Android test, lint, golden ve backend test raporları.

Artifact SHA-256, workflow URL'si ve commit SHA release kaydına yazılmadan Play'e yükleme yapma.

## 3. Kabul testi

- API 26 küçük, API 33 Play/standart ve API 37 büyük cihazlarda açık/koyu tema ile smoke test.
- Free, Plus ve Pro kullanıcılar; Türkçe/İngilizce ve en az 1.3x font.
- Google giriş, oturum geri yükleme, kamera, gerçek production analiz, sonuç merkezi, bulgu
  düzenle/sil/like/unlike, premium kilitler, Onaylı Defter, PDF/Excel ve bildirim deep link'leri.
- RevenueCat aylık/yıllık ürün, entitlement, satın alma ve restore kontrolü.
- Build 9'dan 10'a veri kaybetmeden güncelleme.
- Play App Bundle Explorer ve Pre-launch Report'ta yeni fatal crash, ANR, login, kamera veya billing
  engeli bulunmaması.

## 4. Owner kontrollü mağaza kapısı

- Türkçe ve İngilizce uygulama adı, kısa açıklama ve uzun açıklama kullanıcıdan gelmeden metadata
  yazma veya tahmin etme.
- Kullanıcının yeni ekran görüntülerini yüklemesini ve nihai onayını bekle; görselleri oluşturma,
  düzenleme veya yükleme.
- Mevcut ikon ve feature graphic, ayrıca talep edilmedikçe korunur.
- Release notes locale başına 500 karakteri aşmaz ve promosyon çağrısı içermez.
- Data Safety, App Access, içerik derecelendirmesi, reklam kimliği, abonelikler, destek/gizlilik/
  kullanım koşulları/hesap silme bağlantıları yeniden doğrulanır.

Bu kapı tamamlanmadan **İncelemeye gönder** seçilmez.

## 5. Production ve canlı sonrası

1. Release adı `2.0.0 (10) — İlk Üretim Sürümü` olacak şekilde yeni AAB'yi Production taslağına
   yükle; yalnız Türkiye'yi seç.
2. Tüm teknik ve owner kapıları yeşilse incelemeye gönder. İlk Production sürümünde staged rollout
   olmadığını ve Google onayının otomatik yayına dönüşeceğini dikkate al.
3. Canlı mağaza erişimi sonrası temiz kurulum ve kritik akış smoke testlerini tekrarla.
4. Ardından ayrı forward-only migration ile `android_release_policy.latest_build=10` yap;
   `soft_update_enabled=false` ve `hard_update_enabled=false` bırak.
5. İlk 2 saat yoğun; 24 ve 72 saatte crash/ANR, API hata oranı, analiz/rapor tamamlama,
   RevenueCat ve kullanıcı geri bildirimi kontrolü yap.
6. Kritik durumda downgrade yapma; backend kill switch veya daha yüksek versionCode'lu hotfix kullan.
