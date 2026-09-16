# İSGADA pilot kullanılabilirlik teslimi — 16 Eylül 2026

Başlangıç commit: `989f859e`. Önceden var olan Claude/Codex çalışma ağacı korunmuştur; bu teslimde commit oluşturulmadı.

## Uygulananlar

- Pilot ortak header bağlamı, daha hafif ortak başlık/beyaz geri düğmesi, merkez popup sunumları, kısa yardım metinleri ve oturum kapsamlı başarı mesajı.
- Firma sorumlusu için telefon/e-posta: birlikte zorunlu; atomik create_v3, normalizasyon, aynı isteği tekrar gönderme koruması, eski kalıcı v1/v2 isteklerin desteği ve detayda gösterim.
- Ziyaret: tarih/not zorunlu; görüşülen kişi, dakika, fotoğraf opsiyonel. Düzenleme/silme, dosyayı açma; sayfalama sınırından bağımsız toplam ziyaret/süre özeti. Süresiz kayıt sıfır dakika varsayılmıyor.
- Kurul gündemi: madde ekle/sil ve numaralandırma; toplantı dosyası ekle/aç. Kararlar mevcut ayrı maddeler yolunda; ilk toplantı oluştururken toplu atomik karar girişi henüz yok.
- Firma detayında Onaylı Defter kartı: yalnız görsel arşivleme, başlık/not, liste/aç/indir/düzenle/sil, değişiklik tarihi geçmişi. Geçerlilik, imza teyidi, belge uygunluğu veya şirket skoruna katkı yok.
- Bulgu detayından firma seçerek uygunsuzluk ekleme; belirsiz önem derecesi ve çok işyeri seçimleri daha açık. Sunucuda kaynak bulgu snapshot eşlemesi sonraki iştir.

## Pilot sunucu paketleri

Üç paket transaction içinde, beklenen fonksiyon hash'leri ve migration başı kontrol edilerek uygulandı. Aynı transaction içinde gerçek SQL metniyle migration ledger kaydı eklendi. Genel migration klasörü push edilmedi. Mevcut rollout bayrakları, eski şirket servisleri, kullanıcı/firma kayıtları değiştirilmedi. Yeni defter modül anahtarı açık; erişim mevcut pilot + oturum + sahiplik denetimi üzerinden.

| Ledger sürümü | Paket | SHA256 |
|---|---|---|
| 20260916072930 | Sorumlu iletişim | `4c8ef6ad45b42f2c62f03862f06640434ab9f2eee110059088b6f893bea65d4c` |
| 20260916074000 | Ziyaret/toplantı dosyaları | `4c48c978d1af222d01579b62e455543caddab7a1ae5a4c5ed64b7d58779dfc8b` |
| 20260916075100 | Defter görselleri | `438195d90cb2608b31ad15fbf6a463dc3b0517029dc8775e9149a055db513dea` |

Canlı read-back ledger hash'lerini, yeni RPC'leri, tablo istemci yetkisi kapalılığını, toplantı dosyası FK'sını ve eski create_v2 fonksiyonunun korunduğunu doğruladı. Canlı hesapta test amaçlı iş kaydı oluşturulmadı.

## Doğrulama ve cihaz

- `node --test scripts/isg/pilot_native.test.mjs scripts/isg/nova_analysis_flow.test.mjs scripts/isg/nova_notices.test.mjs scripts/isg/nova_tokens.test.mjs`: **41/41 PASS**. Firma native testi kendi içinde 44 senaryo denetler.
- `node scripts/isg/pilot_contacts_check.mjs`: **10/10 PASS**, ağsız disposable PostgreSQL, gerçek P05 fonksiyonları; platform abonelik yardımcıları fixture.
- `node scripts/modules/run_pilot.mjs --visit-details`: **PASS**, önceki modüller ve yeni dosya/ziyaret/defter CRUD, replay, eski istemci alan koruma, optimistic lock, dosya türü/sahiplik, pilot kapısı ve istatistikler.
- Süreç kayıt cevabı JSON ve firma kapsamı doğrulanmadan kalıcı retry silinmez/başarı mesajı üretilmez. Bu son iyileştirme fiziksel cihaz buildinde de derlendi.
- Son simülatör ve fiziksel cihaz Debug build: **BUILD SUCCEEDED**.
- İSGADA **2.0.3 (116)**, `com.riskdetected.app`, `NOVA_PILOT_BUILD` ve doğru `NOVAPilotOwnerID` ile **iPhone Kerem'e kuruldu**. Analiz result-hub mevcut iOS izin listesinde 116 zaten vardı; flag listesi değiştirilmedi.
- İlk cihaz launch denemesi iOS ekran kilidi nedeniyle reddedildi. Başarılı kurulum, uygulamanın açıldığı veya gerçek kayıt kabulünün geçtiği anlamına gelmez. Kullanıcıdan kilit açması istendi.
- Simülatörün sentetik prova ekranında ortak header ve son firma popup yerleşimi görsel incelendi; fotoğraf/PDF gerçek Storage uçtan uca cihaz kabulü henüz yapılmadı.

Kanıtlar: `output/isg/usability-2026-09-16/`.

## Kalan iş ve geri dönüş

Açık işlerin tamamı `ISGADA_USABILITY_AUDIT_2026-09-16.md` içindedir. Başlıcaları birleşik Evrak Takibi/Dosyalarım, gerçekleşmiş tatbikat, personel eğitim açığı ve kişisel sertifika takibidir. Onaylı Defter dosyaları Dosyalarım'da “Diğer” kategorisinde görünür; ters kaynak linki henüz yoktur.

Geri dönüş gerektiğinde yeni pilot build dağıtımı durdurulur; defter yeni yazma anahtarı kapatılabilir. Kayıt/snapshot/tablo silmek gerekmez. Eski şirket v1/v2 yolları korunmuştur; eski süreç düzenlemelerinde yeni süre/fotoğraf alanları gönderilmediğinde mevcut değerler korunur.
