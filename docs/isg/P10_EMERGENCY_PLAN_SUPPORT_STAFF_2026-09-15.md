# P10 · Atama listesinden destek elemanı önerisi (Acil Durum Planı) + personel arama

Tarih: 2026-09-15 · Dal: `codex/isg-transition-foundation`

## Ne istendi

1. Çalışan temsilcisi / destek elemanı atarken (Atama ve Temsilciler), firma
   seçildikten sonra o firmanın personeli içinde **arayarak** seçim
   yapılabilmeli.
2. Acil durum planı oluştururken, firmada zaten destek elemanı ataması varsa
   (Atama ve Temsilciler'de kind=`support_staff`), bu kişiler **otomatik
   görünmeli** ve ekipten seçilip eklenebilmeli.

## Ne yapıldı

### 1 — Personel arama (Atama ve Temsilciler)

`App/DesignSystem/ISG/NovaAppointmentSheets.swift`: personel seçici artık tüm
listeyi göstermek yerine `NovaAnalysisSearchField` ile yerel arama yapıyor
(`localizedCaseInsensitiveContains`). Sunucuya ayrı bir istek atılmıyor —
katalog zaten seçili firmanın tüm personelini döndürüyor; arama yalnız o
listeyi süzüyor. Eşleşme yoksa "Eşleşen personel yok" gösteriliyor.

### 2 — Destek elemanı önerisi (Acil Durum Planı)

`supabase/migrations/20260915250000_isg_emergency_plan_support_staff.sql` —
`private_isg.read_emergency_plans`'ın `catalog` dalına `support_staff` alanı
eklendi: firmanın hâlâ yürürlükte olan (`ends_before IS NULL OR
ends_before>=today`) `kind='support_staff'` atamalarının adı, atama kimliği ve
işyeri adı.

İki şey sabit tutuldu:

1. **Bu bir öneri, bağ değil.** Bir isme dokunmak yalnız ekip formundaki ad
   alanını doldurur; ekip anlık görüntüsü (`team_snapshot`) hâlâ düz
   `full_name/role/contact` — atamaya işaret eden hiçbir alan yok, atama
   sona erse bile yayınlanmış bir planın ekibi değişmez.
2. **Kapalı Atama modülü boş liste döndürür, hata değil.** Acil durum planı
   kataloğu başka bir modülün anahtarı kapalı diye çökmemeli.

**Dev/canlı şema farkı (üçüncü örneği bu oturumda):** canlı
`private_isg.appointments` tablosunda `is_deleted` sütunu var, dev zincirinin
kendi atama migrasyonu bunu hiç eklememiş. Dev migration bu farkı başlıkta
belgeliyor ve `is_deleted` filtresi kullanmıyor; canlıya açılırsa pilot
aynasına `AND NOT a.is_deleted` eklenmeli.

`App/DesignSystem/ISG/NovaEmergencyPlanSheets.swift`: ekip formunda, firmanın
destek elemanı varsa, isimler yatay çip listesi olarak beliriyor
("Destek elemanlarından seç"); dokununca ad alanı dolup rol `other` oluyor,
kullanıcı rolü değiştirebilir.

## Doğrulama

| Ne | Sonuç |
|---|---|
| `scripts/isg/emergency_plans_check.sql` (mevcut, regresyon) | **43/43 geçti** |
| `scripts/isg/emergency_plan_support_staff_check.sql` (yeni, tek kullanımlık PG17) | **15/15 geçti** |
| `scripts/isg/emergency_plan_support_staff_guard.test.mjs` | **8/8 geçti** |
| `nova_appointments.test.mjs` + `nova_emergency_plans.test.mjs` + ilgili guard'lar | **52/53** — 1 kırmızı önceden var (`publish_plan` artık serviste bulunamıyor; başka bir oturumun eşzamanlı değişikliği, bu işten önce de kırmızıydı) |
| iOS derlemesi | **YAPILAMADI** — host'ta CoreSimulator/Xcode uyumsuzluğu: `CoreSimulator is out of date (1051.55.0 vs 1171.7.0)`, ayrıca RevenueCat SPM paketi (`PaywallColor.swift`) "invalid redeclaration" hatası veriyor. Bu ortam sorunu, benim değişikliklerimden bağımsız — bu oturumda daha önce aynı komutla başarıyla derlenmişti. Dokunduğum dosyalar `swift -frontend -parse` ile ayrı ayrı sözdizimi kontrolünden geçti, ama tam tip kontrolü yapılamadı. |

## Bekleyenler

- iOS derlemesi doğrulanamadı (host ortam sorunu — Xcode/CoreSimulator
  uyumsuzluğu; `sudo` ile araç zinciri onarımı gerekebilir).
- Canlı pilota uygulanmadı — bu bir dağıtım kararı, ayrı onay gerektirir.
  Canlıya açılırsa pilot aynasında `AND NOT a.is_deleted` eklenmesi şart.
- Destek elemanı önerisi yalnız `kind='support_staff'` içindir; `fire_team`/
  `first_aid` atamalarının kendi acil durum rolleriyle eşleştirilmesi
  istenmedi, bu yüzden yapılmadı.
