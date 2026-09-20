# İSGADA OSGB pilot build 118 teslimi — 17 Eylül 2026

## Sonuç

OSGB ürünü, mevcut canlı İSGADA kurulumu ve bireysel kullanıcı verileri
değiştirilmeden staging ortamında ayrı bir pilot olarak hazırlandı. Pilotun iOS
uygulaması `İSGADA OSGB Pilot`, sürüm `2.0.3 (118)` ve bundle kimliği
`com.riskdetected.app.osgbpilot` ile Apple Development kimliği kullanılarak
imzalandı. Bu kimlik canlı `com.riskdetected.app` uygulamasıyla yan yana
kurulmasına izin verir.

## Pilot hesabı

- Workspace: `İSGADA OSGB Pilot`
- Örnek firma: `OSGB Pilot Firması`
- Ortam: staging (`qlymhrrlhklcudveknih`)
- Paket: 30 günlük Pro pilot
- Uzman koltuğu: 20
- Test kredisi: 1.000
- Admin paneli: kapsam dışında ve kapalı

Parola repoya veya uygulama paketine yazılmadı. Geçici hesap bilgileri yalnızca
makinedeki izinleri `0600` olan `/tmp/isgada-osgb-pilot-credentials.json`
dosyasında tutulur. İlk fiziksel cihaz açılışında bilgiler yalnız launch process
environment üzerinden verilir; başarılı oturumdan sonra Supabase oturumu cihazda
saklanır.

## Hesap ve tenant doğrulaması

Pilot kimliğiyle gerçek oturum açıldı. Workspace listesi, firma listesi ve
dashboard geri okuması başarılı oldu. Aşağıdaki workspace servisleri pilot
hesabının kendi workspace ve firma kapsamıyla doğrulandı:

- personel ve ileri personel;
- eğitim ve ileri eğitim;
- risk ve uygunsuzluk;
- checklist;
- acil durum planları;
- ekipman envanteri;
- İSG-KATİP/operasyon;
- dosya alanı.

Doğrulama, production hedefini reddeden staging bağlantısıyla yapıldı ve
production verisine yazılmadı. Makinece okunabilir sonuç
`output/isg/osgb-pilot-2026-09-17/account-domain-smoke.json` dosyasındadır.

## iOS yapılandırması

| Alan | Değer |
|---|---|
| Ürün adı | İSGADA OSGB Pilot |
| Sürüm | 2.0.3 (118) |
| Bundle kimliği | `com.riskdetected.app.osgbpilot` |
| İmza ekibi | `68CU98HAY3` |
| Backend | staging |
| Pilot kök koşulu | yalnız pilot kullanıcı kimliği |

Uygulama paketi kullanıcı parolasını içermez. Debug pilot girişi genel kullanıcı
akışına bağlanmadı; yalnız açık `RD_PILOT_PASSWORD_LOGIN` launch işaretiyle
çalışır.

## Fiziksel cihaz teslimi

Build 118, eşleşmiş `iPhone Kerem` cihazına başarıyla kuruldu ve pilot hesabıyla
ilk oturum açıldı. Uygulama environment değişkenleri olmadan ikinci kez normal
olarak başlatıldı; saklanan oturum geri yüklendi ve `İSGADA OSGB Pilot` dashboard'u
yeniden açıldı. Dashboard bir pilot firma gösterdi ve OSGB sahibi rolünü doğruladı.

Cihazın uygulama envanteri iki kurulumu birlikte doğruladı:

- canlı uygulama: `com.riskdetected.app`, `2.0.3 (117)`;
- OSGB pilot: `com.riskdetected.app.osgbpilot`, `2.0.3 (118)`.

Bu nedenle pilot kurulumu mevcut canlı uygulamayı veya onun cihaz verisini
değiştirmedi.

## Kanıtlar

Hesap makbuzu, domain smoke sonucu, build logu, kurulum/açılış JSON'ları ve cihaz
ekran görüntüleri `output/isg/osgb-pilot-2026-09-17/` dizininde tutulur. Normal
yeniden açılış kanıtı `device-screen-relaunch-118.png` dosyasındadır. Hesap
makbuzunda parola bilinçli olarak maskelidir.

## Canlı kullanıcı koruması

Bu teslim production tenant migration paketini yayınlamaz, mevcut canlı iOS
uygulamasını kaldırmaz ve canlı özellik bayraklarını değiştirmez. OSGB pilotu
yalnız staging projesi, ayrı bundle kimliği ve ayrı kullanıcı hesabıyla çalışır.
