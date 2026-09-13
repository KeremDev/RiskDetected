# P09 ilk dilim — uygunsuzluk durum makinesi ve checklist

13 Eylül 2026 · Durum: **yerel geliştirme ve izole kabul tamamlandı; rollout kapalı, canlıya uygulanmadı.**

Migration: [20260913210000_isg_nonconformity_core.sql](../../supabase/migrations/20260913210000_isg_nonconformity_core.sql) · Sözleşme: [uygunsuzluk yaşam döngüsü](../../contracts/isg/v1/nonconformity-lifecycle.md) · [Kanıt](evidence/P09_NONCONFORMITY_CORE_2026-09-13.json).

## Ne eklendi?

- **Durum makinesi veritabanında:** sekiz durum, **on altı izinli kenar** bir tablo olarak tanımlı; kalan kırk sekiz kombinasyon reddediliyor. Her geçiş `expected_version` ister ve kendi audit satırını yazar.
- **Kapanış uzman doğrulamasına bağlı:** yalnız **o döngüye ait kabul edilmiş** doğrulama kapatabilir; reddedilmiş doğrulama kapatmaz, yeniden açma yeni bir doğrulama döngüsü başlatır ve `closed_on` temizlenir.
- **Atanan kişi uygulama kullanıcısı değil:** `assignee_contact` serbest metin, `profiles`/`auth`'a FK yok. Doğrulayan uzman ise `profiles`'a bağlı.
- **Kaynak başına tek kayıt:** checklist maddesi, risk sürümü veya eski bulgu referansı için ikinci kayıt açılmıyor; eski bulgu yalnız referanslanıyor, `findings` tablosuna yazılmıyor.
- **Checklist sürümü sabitleniyor:** run doldurulduğu şablon sürümünü tutar; sonradan yeni sürüm yayımlamak eski run'ı değiştirmez. Eksik run gönderilemez, gönderilmiş run düzenlenemez.

## Test kanıtı

`--synthetic-session` → **555/555 PASS** (28'i bu dilimin yeni kontrolü), cleanup PASS. Geçiş matrisi tek kontrolde **64 kombinasyonun tamamını** dener: 16 izinli kenar gerçekten ilerliyor, 48'i `TRANSITION_NOT_ALLOWED` alıyor. `--isolated-copy --p05-upgrade` → **28/28 PASS**: tam legacy kopyada **on bir** migration replay, 65 tablo, hepsinde RLS; legacy satır ve fonksiyon gövdeleri değişmedi. Offline foundation **203 PASS**.

Ayrıca: eski sürümle geçiş reddi; atamasız `assigned` reddi; gerekçesiz iptal reddi; doğrulamasız ve reddedilmiş doğrulamayla kapanış reddi; döngü başına tek doğrulama ve çelişen sonucun `IDEMPOTENCY_CONFLICT` alması; kirli/bilinmeyen kanıt dosyasının reddi; yeniden açmanın yeni döngü başlatması; aksiyonun dış referansla tekilliği ve kapalı kayda aksiyon eklenememesi; eski bulguya iki kez tıklamanın tek kayıt üretmesi; kaynak referansı zorunluluğu; maddesiz şablonun yayımlanamaması; bilinmeyen madde ve izinsiz `not_applicable` reddi; başarısız maddenin tek uygunsuzluk açması; eksik run'ın gönderilememesi; gönderilmiş run'ın kilitlenmesi; yeni şablon sürümünün eski run'ı değiştirmemesi; mutabakat sayıları ve gün başına tek satır; kill switch.

## Açık kalanlar

1. Saha ekranları, fotoğraf/kanıt akışı ve native yüzey.
2. DÖF bildirimi (P12), skor katkısı (P17), PDF/XLSX tutanak üretimi (P04 belge dilimi + P11).
3. Risk sürümünden otomatik uygunsuzluk türetme ve P08 etki listesiyle bağlantı.
4. Uygunsuzluk olayları henüz outbox'a yazılmıyor.
5. Canlı migration ve rollout.
