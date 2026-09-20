# İSGADA OSGB Pilot — Build 120 Teslim Notu

Tarih: 18 Eylül 2026

Ortam: OSGB staging (`qlymhrrlhklcudveknih`)

Uygulama kimliği: `com.riskdetected.app.osgbpilot`
Build: `120`

## Kişisel pilot ile ürün eşitliği

- Acil durum planı ekranı ortak Nova başlık, arama, tam genişlik boş durum ve dört istatistik kartını kullanıyor. Plan formu kompakt tarihleri, firma personelinden çoklu ekip seçimini ve kişi bazlı koordinatör/yangın/ilk yardım/tahliye görevini kaydediyor.
- Atamalar ile destek elemanları aynı personel görev kaynağını kullanıyor. Personel aranıp tek kişi seçiliyor; çalışan temsilcisi, destek elemanı, ekip üyesi, ilk yardım ve yangın ekibi görevleri başlangıç ve isteğe bağlı bitiş tarihiyle kaydediliyor.
- Kurul toplantısı formu yalnız gerçekleşmiş veya iptal edilmiş toplantı kaydediyor. Gündem, firma personelinden katılımcılar ve ilk kararlar tek akışta oluşturuluyor. Açık kararlar detay ekranından tamamlanabiliyor veya iptal edilebiliyor.
- Risk değerlendirmesi ilk tam değerlendirme ile sonraki revizyonu ayırıyor. İlk kayıt taslak açılıyor, detay ekranından uzman tarafından süre seçilerek kesinleştiriliyor. Süresi dolan, takipsiz, yürürlükte ve yaklaşan kayıtlar ayrı kartlarda gösteriliyor.
- Eğitimde müfredat/yıllık plan yönetimine giden ürün yüzeyi kaldırıldı. Yeni eğitim kaydı gerçekleşen tarih, süre ve katılımcı beyanıyla tek kullanıcı işleminde tamamlanıyor; ara planlama durumu kullanıcıya gösterilmiyor.
- Tüm bu sayfalarda kayıt kartı, detay popup'ı, değer adları, başarı bildirimi ve işlem düğmeleri aynı tasarım sistemini kullanıyor.

## OSGB yöneticisi ve bağlı uzman

- Yönetici ve uzman ayrı ekran kopyaları kullanmıyor; aynı bileşenler ve aynı workspace servisleri çalışıyor.
- OSGB sahibi/yöneticisi çalışma alanındaki firmaları ve uzman atamalarını yönetebiliyor.
- Uzman yalnız sunucuda aktif olarak atandığı firmaları okuyup işleyebiliyor. Ekleme ve kayıt yaşam döngüsü işlemleri `canOperate` yetkisiyle kapanıyor; yetkisiz istemci işlemi sunucu katmanında da reddediliyor.
- Kişisel kullanıcı servislerine geri dönüş eklenmedi. OSGB verileri tenant, firma ve üyelik atamasıyla sınırlandırıldı.

## Staging veri ve kabul kaydı

- `20260918013000_osgb_operational_surface_parity.sql` yalnız staging'e uygulandı.
- Acil durum planı, atama, risk değerlendirmesi ve kurul toplantısı istatistik yanıtlarına mevcut anahtarları bozmayan ek durum grupları eklendi.
- OSGB Pilot Firması için bir yürürlükte acil durum planı, çalışan temsilcisi ataması, destek elemanı ataması, kesinleşmiş risk değerlendirmesi ve bir kararlı gerçekleşmiş kurul toplantısı gerçek RPC akışıyla oluşturuldu.
- Önceki geleceğe planlı eğitim pilot kaydı iptal edildi; bir katılımlı gerçekleşmiş eğitim kaydı oluşturuldu. Eğitim metriklerinde `planned=0`, `completed=1` doğrulandı.
- Pilot metrikleri: plan `valid=1`, atama `active=2`, risk `valid=1`, kurul `held=1`, açık karar `1`.

## Doğrulama ve cihaz teslimi

- `node --test scripts/isg/*.test.mjs`: **997/997 geçti**.
- Workspace API/store, uzman firma kapsamı, aday manifesti ve ürün eşitliği odak testleri: **23/23 geçti**.
- `git diff --check`, function-map ve aday manifest doğrulamaları geçti.
- Fiziksel iPhone Debug derlemesi, staging yapılandırması, kod imzası ve kurulum geçti.
- Telefonda `İSGADA`, bundle `com.riskdetected.app.osgbpilot`, build `120` doğrulandı ve uygulama açıldı.
- Üretim projesinin migration seviyesi değişmedi; son sürümü `20260916090922` olarak kaldı.
