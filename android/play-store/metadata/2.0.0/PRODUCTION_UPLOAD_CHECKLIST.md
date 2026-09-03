# Google Play Production — RiskDetected 2.0.0 (10)

- Paket: `com.riskdetectedan.app`
- Kanal: Production
- Ülke: yalnız Türkiye
- Yayın modu: Google incelemesi sonrasında otomatik yayın
- Sürüm adı: `2.0.0 (10) — İlk Üretim Sürümü`
- Artifact: minify edilmiş, upload key ile imzalanmış yeni `app-release.aab`
- Release notes: bu klasördeki Türkçe ve İngilizce metinler
- Native debug symbols, `mapping.txt`, doğrulama çıktısı ve commit SHA saklanacak

## İnceleme öncesi zorunlu kapılar

- [ ] Build 10 test matrisi ve gerçek production API E2E tamamlandı.
- [ ] Play App Bundle Explorer özeti ve Pre-launch Report engel içermiyor.
- [ ] Data Safety, App Access, içerik derecelendirmesi ve yasal URL'ler doğrulandı.
- [ ] RevenueCat Plus/Pro ürünleri, entitlement'lar ve restore akışı doğrulandı.
- [ ] Kullanıcının ilettiği Türkçe ve İngilizce metadata kaydedildi ve onaylandı.
- [ ] Yeni ekran görüntüleri kullanıcı tarafından yüklendi ve nihai olarak onaylandı.
- [ ] Türkçe ve İngilizce yayın notları kullanıcı tarafından onaylandı.
- [ ] Publishing Overview'da çakışan taslak veya bekleyen değişiklik yok.

Bu maddelerin tamamı işaretlenmeden **İncelemeye gönder** seçilmez.

## AAB yükleme doğrulaması

1. Artifact özetinde `versionCode=10`, `versionName=2.0.0`, `targetSdk=37` değerlerini doğrula.
2. Paket adının `com.riskdetectedan.app` ve upload sertifikasının onaylı fingerprint olduğunu doğrula.
3. AAB SHA-256, CI run URL'si, commit SHA, mapping ve native symbol paketini release kaydına ekle.
4. Türkiye dışındaki Production ülkelerinin seçili olmadığını doğrula.
5. Metadata ve screenshot kapıları tamamlanıncaya kadar release'i yalnız taslak olarak tut.

## Canlı sonrası

1. Play Store üzerinden temiz kurulum ve build 9 → 10 güncellemesini doğrula.
2. Google girişi, kamera, analiz, dört sonuç bölümü, geri bildirim, rapor ve satın alma akışını smoke test et.
3. Canlı erişim kanıtlandıktan sonra ayrı forward-only migration ile `android_release_policy.latest_build=10` yap; soft/hard update kapalı kalsın.
4. İlk 2 saat yoğun, ardından 24 ve 72 saat crash/ANR, API, analiz, rapor, RevenueCat ve geri bildirim sinyallerini izle.
