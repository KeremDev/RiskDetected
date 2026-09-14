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

---

## İkinci dilim — detay, risk skoru ve kayıt türü

14 Eylül 2026. Migration: [20260914190000_isg_nonconformity_detail.sql](../../../supabase/migrations/20260914190000_isg_nonconformity_detail.sql). Rollout hâlâ kapalı.

### Kayıt türü

`record_kind` iki değer alır: `nonconformity` (varsayılan) ve `improvement`. Bir geliştirme önerisi aynı yaşam döngüsünü kullanır ama **uygunsuzluk sayılmaz**. Anahtar yalnız `open_detailed` ve `open_from_expert_item` payload'larında bulunur; eski iki açma yolu bir öneri açamaz.

### Detay ve skor

`nonconformity_details` kayıt başına en fazla bir satırdır. `risk_score` ve `risk_band` **generated column**'dır: istemci de sunucu kodu da bu iki sütuna yazamaz.

| Metot | Girdiler | Skor | Bantlar |
|---|---|---|---|
| `fine_kinney` | O ∈ {0.2, 0.5, 1, 3, 6, 10}, F ∈ {0.5, 1, 2, 3, 6, 10}, Ş ∈ {1, 3, 7, 15, 40, 100} | O × F × Ş | ≤70 düşük · ≤200 orta · ≤400 yüksek · üzeri kritik |
| `matrix_5x5` | O ∈ 1–5, Ş ∈ 1–5 | O × Ş | ≤4 düşük · ≤9 orta · ≤19 yüksek · üzeri kritik |

Yarım skor yoktur: metotsuz girdi, girdisiz metot ve iki metodun girdilerinin karışması `RISK_INPUT_INCOMPLETE` verir. Ölçek dışı bir değer CHECK ile reddedilir.

### Uzman görüşü maddesi

`source_kind` değerine `legacy_expert_item` eklendi. Uzman görüşü maddeleri **skorsuz** gelir; bu yüzden `open_from_expert_item` allowlist'inde `risk_band` anahtarı **hiç yoktur**. Önem derecesini kişi seçer. Madde referans olarak taşınır, kopyalanmaz.

### Detay düzenleme

`set_detail` kısmi güncelleme değildir: ekranın gösterdiği detayın tamamını gönderir, temizlenen alan gerçekten temizlenir. Detayın kendi sürüm alanı yoktur; son yazan kazanır. Kaydın `version` alanı yalnız durum geçişlerini korumaya devam eder.
