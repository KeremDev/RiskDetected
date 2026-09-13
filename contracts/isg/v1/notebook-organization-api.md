# P13 — checklist, etiket ve native ekran sözleşmesi

13 Eylül 2026. Sunucu migration'ı `20260913154113_isg_notebook_organization_api.sql` Supabase CLI ile üretildi. Mevcut not migration'ları ileri tarihli olduğu için yeni PL/pgSQL fonksiyonları tablo tipleri yerine RECORD kullanır; tablo bağlantıları ilk çağrıda çözülür. Sıralı tam migration replay'i ayrı legacy-kopya yükseltme testinde geçti. Tam migration seti yüklenmeden özellik açılmaz.

## API

- `isg_notebook_organization_v1(p_note uuid)` aktif oturum sahibinin not sürümünü, checklist ve etiketlerini okur. Tombstone için iki liste de boş döner.
- `isg_notebook_organize_v1(p_mutation uuid,p_note uuid,p_expected bigint,p_items jsonb,p_tags jsonb)` checklist ve etiket bağlantılarını atomik değiştirir; not sürümünü bir artırır. Not başlığı/gövdesine dokunmaz.
- `p_items`: en fazla 500 adet `{item_id,text,done}`; sıra dizideki konumdur. Kimlikler tekil, metin boş değil ve ≤1000 karakter. Bilinmeyen JSON alanları reddedilir. Toplam JSON metni ≤1 MB.
- `p_tags`: en fazla 30 etiket, her biri ≤60 karakter; trim/lower anahtarı ile kullanıcı kapsamında tekillik. Toplam JSON metni ≤10 KB. Etiket başka nottan/firma kaydından kopyalanmaz; yalnız aynı kullanıcının etiketi tekrar kullanılabilir.
- Güncel olmayan sürüm `VERSION_CONFLICT`; silinmiş not `NOTE_TOMBSTONED`; yabancı kaynak `ACCESS_DENIED`. Başarısız işlem checklist'i kısmen değiştirmez.
- Aynı mutation ve aynı içerik tarihi receipt'i döndürür. Aynı mutation/farklı içerik `IDEMPOTENCY_CONFLICT`. Yazma receipt'inde kullanıcı metni yoktur.
- Fonksiyonlar aktif gerçek oturum ve rollout kontrolü yapar; doğrudan tablo yetkileri verilmez. Paid/firma bağımlılığı yoktur.

## Native bağlantı

iOS ve Android'de not/list/edit, kaydedilmiş taslak, iki metinli çakışma inceleme, checklist ve etiket editörleri eklendi. Profile girişleri `NotebookUIRelease.enabled=false` altında; sunucu rollout da kapalı. Bu yerel bayrak, sunucu yetkilendirmesinin yerine geçmez.

Organizasyon isteği de aynı kullanıcıya ayrılmış şifreli kuyruğa ağdan önce kaydedilir. Sürüm çatışması halinde iki checklist gösterilir; kullanıcı yeniden düzenleyip onaylayana kadar yeni mutation oluşturulmaz. Kuyruktaki önceki kayıt ile onaylanan yeni istek atomik değiştirilir. Notun silinmesi eski taslağı otomatik silmez. Not metni ve checklist için istemci sınırları ile depo sınırı ayrıca uygulanır.

Henüz sunucudan okunmamış checklist çevrimdışıyken düzenlemeye açılmaz. Kalıcı olan taslak kuyruğudur; sunucu okuma modeli yalnız oturum belleğindedir. Kaydedilmemiş editörden çıkış onay gerektirir. Bu paket gerçek cihazda UI/erişilebilirlik/kilitlenme sonrası kalıcılık kabulü değildir.

## Doğrulama ve sınır

- İzole Auth/PostgREST/SQL: 838 PASS; organizasyon için 21 yeni kontrol, oturum iptali için 1 ek kontrol. `output/isg/runs/synthetic-auth-JmSdcy/REPORT.json`.
- Sıralı 21 migration ile legacy-kopya yükseltmesi: 32 PASS; kaynak satırlar/helper tanımları korunuyor. `backups/isg-auth-service-restore-20260912-xYaVTB/REPORT.json`.
- İlgili advisor bulgularında ERROR/WARN yok. Her iki geçici ortamın temizliği PASS.
- Native derlemeler ve bellek depolu/fake RPC testleri, gerçek cihazda push veya uçtan uca UI kabulü olarak sayılmaz.

## Hatırlatıcı kararı

Kullanıcı 13 Eylül'de varsayılan olarak **server_push** seçti. Aynı hatırlatıcı için yerel alarm/fallback kurulmayacak. Provider kabulü, cihaz teslimi ve kullanıcı okuması ayrı durumlardır; internet/izin yokken kesin teslim vaadi verilmez.

Aktif-oturumlu reminder API ve iki native UI, occurrence producer → P12 job/claim bağlantısı, seçili kurulumun tek teslim sahipliği ve gönderim anındaki iptal/sürüm/zaman/izin doğrulaması artık [ayrı reminder sözleşmesinde](notebook-reminder-api.md) uygulanmıştır. P13 yine bütünüyle açık: production worker/credential/scheduler, gerçek APNs/FCM cihaz kabulü, reminder deep-link/teslim gözlemi, çevrimdışı reminder mutation kuyruğu, retention ve redaksiyon kanıtı bekler. P14'e geçiş veya P13 faz kapanışı bu belgeyle ilan edilmiyor; üretime migration/rollout/mağaza yayını yapılmadı.
