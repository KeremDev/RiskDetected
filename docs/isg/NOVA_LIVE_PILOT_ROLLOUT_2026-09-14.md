# NOVA canlı pilot ilerleme ve teslim yöntemi

Tarih: **14 Eylül 2026**
Dal: `codex/isg-transition-foundation`

## İzlediğimiz sıra

Canlı pilotu doğrudan genişletmek yerine firma akışını ilk doğrulama yüzeyi olarak seçtik:

1. NOVA firma çalışma alanını ve pilot kapısını yerelde hazırladık.
2. `NOVA_PILOT_BUILD` ile imzalı iOS Debug paketini ürettik.
3. Paketi fiziksel **iPhone Kerem** üzerine kurup başlattık; build 98 cihazda çalışıyor.
4. Pilot erişimini tek hesap/sahip ve süreli allowlist ile sınırladık. Mevcut firmalar taşınmadı ve canlı kayıtlar değiştirilmedi.
5. Cihazdaki **Firmalar** yüzeyinde pilot firma listesi, firma özeti, akordeon başlıkları ve firma/personel akışının ilk kabulünü bu dar kapsamda ilerletiyoruz.
6. Yeni firma oluşturma veya mevcut veriyi değiştiren mutation, kullanıcı cihaz kabulü ve canlı kapsam kontrolü tamamlanmadan genelleştirilmiyor.

Bu sıra, önce gerçek iOS cihazındaki firma deneyimini ve pilot izolasyonunu görmemizi; daha sonra personel, belge ve diğer modülleri aynı kapıdan ilerletmemizi sağlar.

## Bugünkü kanıtlı durum

- iOS fiziksel cihaz kurulumu: [NOVA build 98](NOVA_DEVICE_BUILD_98_2026-09-14.md)
- Pilot canlı açılışı ve süreli kapsam: [P05 canlı aktivasyon](P05_LIVE_ACTIVATION_2026-09-13.md)
- Firma workspace kaynakları, skor/accordion ve popup arayüzü commit’lendi.
- Firma akışının cihaz üzerindeki görünür/pilot yüzeyi hazır; gerçek yeni firma mutation kabulü ayrı kullanıcı denemesi olarak tutuluyor.

## İlerleme kapıları

Her sonraki canlı adım şu sırayla kayda alınır: cihaz build ve imza → pilot owner/scope kontrolü → dar firma işlemi → bağımsız read-back/kanıt → gerekiyorsa bir sonraki modül. Bu kayıt zinciri tamamlanmadan canlı kapsam genişletilmez.

Bu belge bir rollout yöntemi ve durum kaydıdır; tek başına canlı veriye yazma, migration çalıştırma veya genel kullanıcı rollout’u anlamına gelmez.
