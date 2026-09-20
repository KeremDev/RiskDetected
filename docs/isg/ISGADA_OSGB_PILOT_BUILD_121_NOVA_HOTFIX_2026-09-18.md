# İSGADA OSGB Pilot Build 121 — Nova Açılış Düzeltmesi

Tarih: 18 Eylül 2026

## Sorun

Build 120 staging OSGB ortamına bağlıydı ancak `NOVA_PILOT_BUILD` derleme koşulu verilmediği için `NovaPilotMainGate` eski `MainTabView` rotasına düşüyordu. Önceki kullanıcı kontrolü de Nova girişini yalnızca tek bir pilot kullanıcı kimliğiyle sınırlandırdığı için OSGB yöneticisine bağlı uzmanlar Nova kabuğuna giremeyecekti.

## Düzeltme

- Build 121, `DEBUG NOVA_PILOT_BUILD` koşullarıyla üretildi.
- Ayrı OSGB pilot bundle'ında oturum açmış yönetici ve uzmanlar ortak Nova girişini kullanıyor.
- Veri yetkisi istemcideki bu sunum seçiminden alınmıyor; workspace RPC'leri üyelik, rol ve tenant kapsamını doğrulamaya devam ediyor.
- Kişisel pilot ve normal Debug/Release rotaları korunuyor.
- Uygulama aynı `com.riskdetected.app.osgbpilot` bundle kimliğiyle build 120'nin üzerine kuruldu.

## Paket doğrulaması

- Uygulama: İSGADA
- Bundle: `com.riskdetected.app.osgbpilot`
- Sürüm: `2.0.3 (121)`
- Ortam: `https://qlymhrrlhklcudveknih.supabase.co` staging
- İmza ekibi: `68CU98HAY3`
- Nova koşulu: `DEBUG NOVA_PILOT_BUILD`

## Doğrulama

- `node --test scripts/isg/pilot_native.test.mjs`: 4/4 geçti.
- `node --test scripts/isg/*.test.mjs`: 997/997 geçti.
- Fiziksel iPhone kurulumu başarılı.
- Build 121 cihazda aynı bundle kimliğiyle başlatıldı.
