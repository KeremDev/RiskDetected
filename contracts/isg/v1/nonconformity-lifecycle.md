# Uygunsuzluk yaşam döngüsü ve checklist — v1 sunucu sözleşmesi

13 Eylül 2026. P09'un ilk dilimi. Mevcut `findings` tablosu yetki kaynağı olarak okunmaz ve yazılmaz; eski `is_resolved` işareti buradaki hiçbir kaydı kapatmaz.

Migration: [20260913210000_isg_nonconformity_core.sql](../../../supabase/migrations/20260913210000_isg_nonconformity_core.sql).

## Durum makinesi

Geçiş matrisi **veritabanında bir tablodur** (`nonconformity_state_edges`), dağınık IF dalları değil. Sekiz durum, **on altı izinli kenar**; geri kalan kırk sekiz kombinasyon `TRANSITION_NOT_ALLOWED` verir.

~~~text
draft ──▶ open ──▶ assigned ──▶ in_progress ──▶ pending_verification ──▶ closed ──▶ reopened
  │         │          │  ▲            │  ▲               │                            │
  └─────────┴──────────┴──┴────────────┴──┴───────────────┘                            │
                         cancelled (gerekçeli)                  reopened ──▶ assigned / in_progress / cancelled
~~~

| Kural | Davranış |
|---|---|
| Sürüm | Her geçiş `expected_version` ister; eski sürüm `VERSION_CONFLICT` |
| Gerekçe | İptal, geri alma, yeniden açma ve yeniden atama gerekçesiz olmaz |
| Atama | `assigned` için bir iletişim kişisi zorunlu (`ASSIGNEE_REQUIRED`) |
| Kapanış | Yalnız **bu döngüye ait kabul edilmiş** uzman doğrulaması ile (`VERIFICATION_REQUIRED`); reddedilmiş doğrulama kapatmaz |
| Yeniden açma | `closed_on` temizlenir ve yeni bir doğrulama döngüsü başlar |
| Audit | Her geçiş kendi sürüm numarasıyla ayrı satır yazar |

**Atanan kişi uygulama kullanıcısı değildir:** `assignee_contact` serbest metindir, `profiles`/`auth` tablolarına FK'si yoktur. Doğrulayan ise uzmandır ve `profiles`'a bağlıdır.

## Kaynak ve tekillik

Bir kaynak referansı (checklist maddesi, risk sürümü, eski bulgu) için **tek** uygunsuzluk açılır; aynı yere tekrar tıklamak var olan kaydı döndürür. Eski bulgu yalnız referans olarak taşınır: yanıt `legacy_finding_written=false` der.

## Checklist

Şablon sürümü insan onayıyla yayımlanır (maddesiz sürüm yayımlanamaz, kod başına tek `published`). Saha run'ı **doldurulduğu sürümü sabitler**: sonradan yeni sürüm yayımlamak eski run'ın sürümünü veya cevaplarını değiştirmez. Madde sonucu `not_applicable` ancak şablon izin veriyorsa kabul edilir. `nonconform` bir madde istenirse tek bir uygunsuzluk açar; tekrar kaydetmek ikinci kayıt üretmez. Eksik run gönderilemez; gönderilmiş run düzenlenemez.

## Henüz olmayanlar

Saha ekranları, fotoğraf/kanıt akışı, DÖF bildirimi (P12), skor katkısı (P17), belge/PDF üretimi ve risk sürümünden otomatik uygunsuzluk türetme bu dilimde yoktur. `nonconformity` rollout satırı kapalıdır ve istemciye GRANT verilmemiştir.
