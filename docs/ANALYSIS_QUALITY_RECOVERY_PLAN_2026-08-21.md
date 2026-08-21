# Analiz Kalitesi — Kurtarma ve Yükseltme Planı

**Tarih:** 21 Ağustos 2026
**Bağlam:** `analyze v173` uzmanlık derinliği regresyonu
**Durum:** Faz 0 tamamlandı ve canlıda. Faz 1–4 planlandı, uygulanmadı.

---

## 1. Ne oldu — ölçülmüş kanıt

`analyze v173` yerel saat **22:46:02**'de deploy edildi. İlk analiz **22:48:46**'da çalıştı.
Aynı üç fotoğraf, deploy öncesi iki kez çalıştırılmıştı:

| Saat | Sürüm | Bulgular | En yüksek FK |
|---|---|---|---|
| 21:55 | önceki | korkuluk boşluğu, şev stabilitesi, iş makinesi mesafesi | **360** |
| 22:23 | önceki | korkuluk, istifleme, raf, KKD eksikliği | **540** |
| 22:48 | **v173** | 4× kalıp "saha teyidi" + istifleme + uyarı levhası | **63** |

Fotoğraf bazlı denetim kaydı:

```
foto 1: actionable_layer_count 0   initial_generated_findings_count 0
foto 2: actionable_layer_count 2   initial_generated_findings_count 1
foto 3: actionable_layer_count 0   initial_generated_findings_count 0
```

Fotoğraf 1 ve 3'te model **hiç eyleme dönük katman bulamadı**. Aynı fotoğraflar 40 dakika
önce FK 240 ve 360 üretmişti.

### Kök neden

Tek model çağrısı artık şunların hepsini üretmek zorunda: `scene_elements`, 12
`inspection_layers`, `equipment_depth_scan`, `process_safety_checks` ve `findings`. Çıktı
token'ı 2067'den 1066'ya düşerken **daha fazla yapı** üretildi. Tehlike tespiti bu yarışı
kaybetti.

Bu bir ayar sorunu değil, mimari sorun: **uzmanlık derinliği, uzmanlığın uygulanacağı
tespiti yedi.**

### Yan hasarlar

1. **Doğrulama maddeleri `findings` dizisine yazıldı**, Fine-Kinney puanıyla birlikte.
   Okunamayan bir kontrol sertifikası için `fk_severity 40` ("tek ölüm") atandı. Şiddet
   ekseni, tespit edilmiş bir tehlike olmadan şişirildi.
2. **Metinler kalıp.** Dördü de aynı cümle, ekipman adı değişerek. Ekipman sınıfı
   bilindiğinde bu cümle koddan türetilebilir — sıfır bilgi taşıyor.
3. **`ai_summary` bulgularla tutarsız.** Özet modelden geliyor (`index.ts:11226`),
   doğrulama maddeleri sonradan koda ekleniyor (`index.ts:3133`). Özet onları yapısal
   olarak göremez; 6 bulgudan 1'ini anlatıyor.
4. **Denetim sayacı yanlış.** `periodic_verification_added_count: 0` yazıyor, veritabanında
   4 kayıt var.
5. **Yeni sert hata yolu.** Aynı gün bir analiz `REPAIR_INTEGRITY_FINDING_REMOVED` ile
   tamamen düştü. Bu kod v165 deterministik fallback allowlist'inde değil.

### Süreç bulgusu

Bu çalışmanın tamamı (~3000 satır, 18 değişmiş + 8 yeni dosya) **commit'lenmemiş halde
production'da çalışıyordu**. İki migration bayrağı `on` olmaya zorluyordu; replay edilse
regresyon her taze ortamda geri gelirdi.

---

## 2. Faz 0 — Durdurma (TAMAMLANDI)

- `ai_expert_depth_v1` bayrağı production'da `off` + `kill_switch: true` yapıldı.
- Bu durum migration olarak kayda geçirildi (`20260821200612`), böylece replay yeniden
  açamaz. Bayrağı elle çevirip zincire yazmamak, bugün hafızaya alınan tuzağın aynısıydı.
- pgTAP iddiaları durdurulmuş duruma göre güncellendi, gerekçesi yanına yazıldı.
- Commit'lenmemiş gövde, **deploy edildiği haliyle ve kapalı olarak** commit'lendi
  (`e7fb69fc`) — git ile production yeniden örtüşüyor.
- Kapılar: 461 edge testi, taze replay ile 597 pgTAP, L10N 25/25, `inventory --check`,
  `deno fmt`.

**Sonuç:** kalite v173 öncesi seviyeye döndü. Mobil build gerekmedi.

---

## 3. Tasarım ilkeleri

Kanıttan çıkan ve ihlal edilmemesi gereken dört kural:

**İ1. Tehlike tespiti çağrısına asla yeni çıktı yükümlülüğü eklenmez.**
Bu çağrı kanıtlanmış durumda (FK 540, 3–4 sağlam bulgu). v173 tam olarak bunu ihlal etti.

**İ2. Derinlik ayrı bir çağrıdır.**
Aynı çağrıda dikkat paylaştırmak yerine, tehlike tespiti bittikten sonra seçili
fotoğraflarda ikinci bir çağrı. Bu, `ANALYSIS_QUALITY_ADDENDUM` §4'te önerilen
"ekipman tetiklemeli modül" fikrinin eksik kalan kısmıydı: modül **ayrı çağrı** olmalı.

**İ3. Doğrulama maddeleri bulgu değildir.**
Ayrı dizi, FK/5×5 puanı yok, bulgu bütçesine girmez, risk toplamlarını etkilemez, raporda
ayrı bölüm. Addendum §2'deki tablo.

**İ4. Derinlik gözlem üretmelidir, kalıp değil.**
"Periyodik kontrol doğrulanamıyor" ekipman sınıfından türetilebilir. Değer görsel olarak
denetlenebilir ayrıntıdadır: korozyon, ventil çıkış yönü, hortum çatlağı, kanca mandalı,
halatta kopan tel, kasnak yiv aşınması.

---

## 4. Faz 1 — Doğrulama maddelerini bulgulardan çıkar

**Neden önce bu:** kullanıcının gördüğü en bariz kalite kaybı buydu (6 bulgunun 4'ü kalıp),
ve tek başına, derinlik özelliği kapalıyken bile uygulanabilir.

- `applyPeriodicVerificationFindings` `record.findings` yerine `record.field_verification_items`
  dizisine yazsın.
- Bu maddelerde `fk_*` ve `m5_*` alanları **bulunmasın**. Bunun yerine `priority`
  (`high` / `medium` / `low`) ve `equipment_class`.
- Bulgu bütçesi (`max_findings_total`, `MAX_FIELD_VERIFICATION_FINDINGS`) ayrışsın; doğrulama
  maddeleri bulgu saymasın.
- `candidate_findings_count` bu maddeleri saymasın (Addendum §7A) — yoksa ikinci tarama
  gereksiz tetiklenir.
- `ai_summary` tutarlılığı: özet yalnız bulguları anlatsın; doğrulama maddeleri için ayrı,
  koddan üretilen ve modele bağlı olmayan bir cümle kullanılsın.
- Denetim sayacı doğru noktada yazılsın (`added_count` gerçek ekleme sonrası).

**Kabul:** aynı üç fotoğrafla bulgu listesi 21:55/22:23 çalışmalarının içeriğine dönmeli;
doğrulama maddeleri ayrı dizide görünmeli; en yüksek FK puanı ≥ 240.

---

## 5. Faz 2 — Derinliği ayrı çağrıya taşı

- Çağrı 1 (tehlike tespiti) v173 öncesi haline birebir döner: `equipment_depth_scan` ve
  `process_safety_checks` bu çağrının şemasından çıkar.
- Çağrı 2 (derinlik) yalnız şu koşulda çalışır: bir fotoğrafta **anlamlı görsel kontrol
  listesi olan** bir ekipman sınıfı yüksek tanıma güveniyle tespit edilmiştir.
  - Evet: basınçlı kap, vinç/kaldırma donanımı, güç aktarımı, elektrik panosu
  - Hayır: raf sistemi, genel istif — bunlar mevcut 12 katmanda zaten kapsanıyor
- Çağrı 2'nin promptu **dar** olur: yalnız o ekipman sınıfının görsel kontrol listesi.
  Tehlike tespiti tekrar istenmez.
- Analiz başına en fazla **1** derinlik çağrısı. Toplam sağlayıcı çağrı üst sınırı analiz
  başına **3** (tespit + v164 onarımı + derinlik) — değişmez olarak testle çivilenir.
- Derinlik çağrısındaki her hata **fail-open**: geçerli birinci sonuç aynen tamamlanır.
  `PLAN.md` §3C ile aynı davranış.

**Neden ayrı çağrı:** `analyze v173` tam olarak bunun tersini denedi ve tehlike tespiti
çöktü. Ölçülmüş sonuç, tartışma değil.

---

## 6. Faz 3 — Kalıp yerine gerçek derinlik

Ekipman sınıfı başına iki liste. **Her ikisi de İSG uzmanı onayından geçmelidir.**

**Görsel olarak denetlenebilir → bulgu olabilir**
- Basınçlı kap: gövde korozyonu/deformasyonu, sızıntı izi, emniyet ventili tahliye yönü,
  manometre camı kırık/okunamaz, sekonder muhafaza, esnek hortumda çatlak/ezilme, araç
  çarpma koruması
- Kaldırma donanımı: kanca emniyet mandalı, halatta kopan tel / kuş kafesi deformasyonu,
  zincir uzaması/deformasyonu, sapanda kesik-aşınma, uygunsuz cıvatayla yapılmış bağlantı
- Güç aktarımı: kayış koruyucusu, kasnak yiv aşınması, kaplin muhafazası, açıkta dönen mil,
  pim/segman eksikliği
- Elektrik panosu: kapak açık/kilitsiz, kablo rekoru eksik, IP bütünlüğü bozuk, etiketsiz
  devre

**Görüntüden doğrulanamaz → doğrulama maddesi**
- Basınçlı kap mı, atmosferik depolama mı; içerik sınıfı; tasarım basıncı ve imal yılı;
  son periyodik kontrol; kaynak dikişi muayenesi; ventil ayar sertifikası
- Kaldırma donanımı: kapasite plakası okunamıyorsa, son muayene tarihi
- Statik elektrik / eşpotansiyel ölçüm değeri

Kalıp cümle yasak: doğrulama maddesi metni ekipman sınıfına **özgü** olmalı, sadece isim
değiştirilerek üretilmemeli.

---

## 7. Faz 4 — Yan hasarların kapatılması

- `REPAIR_INTEGRITY_FINDING_REMOVED` sert hata olmaktan çıksın: bütünlük ihlali ilk geçiş
  geçerliyse **fail-open** olmalı, onarım atılmalı, ilk sonuç tamamlanmalı. Bugün kullanıcıya
  hata gidiyor.
- `ai_summary` üretimi bulgu listesiyle tutarlı hale gelsin (Faz 1'de kısmen çözülüyor).
- Denetim alanları gerçek sonuçla eşleşsin.

---

## 8. Ölçüm ve kabul

**Taban (ölçüldü):** analiz başına ortalama 9.121 token, 27 sn worker süresi (maks. 44 sn).
Son 21 günde 32 fotoğraf / 27 analiz — istatistiksel olarak küçük bir örneklem.

**Regresyon fixture'ı:** bu üç fotoğrafın çıktısı sabitlensin. Korkuluk / şev / iş makinesi
bulguları kaybolursa test düşsün. Bu, v173'ün fark edilmeden geçmesini engellerdi.

**Her faz için:**
- 461 edge testi + yeni testler
- 597 pgTAP, **stop-then-start** taze replay ile (`Starting database from backup` doğrulama
  değildir)
- L10N 25/25 **ve** `localization_inventory.mjs --check` — ikisi ayrı kapı
- `deno fmt --check`, `deno check`
- Altı profil prompt golden

**Yayın kuralı:** her faz `shadow` modda önce ölçülür, sonra açılır. v173 iki dakika içinde
%100'e açıldı ve regresyon ilk analizde ortaya çıktı. Bir daha olmamalı.

**Kill switch:** her faz kendi bayrağıyla gelir; kapatıldığında davranış bir önceki faza
döner.

---

## 9. Sıra

1. ✅ Faz 0 — durdurma, kayda geçirme, commit
2. Faz 1 — doğrulama maddeleri bulgulardan çıkar *(derinlik kapalıyken de uygulanabilir)*
3. Regresyon fixture'ı
4. Faz 2 — derinlik ayrı çağrıya
5. İSG uzmanı içerik onayı
6. Faz 3 — gerçek derinlik listeleri, ekipman sınıfı başına kademeli
7. Faz 4 — yan hasarlar

Faz 2 ile Faz 3 **aynı sürümde açılmamalı**; ikisi de tetikleme oranını ve maliyeti
etkiliyor, birlikte açılırsa hangisinin ne yaptığı ayırt edilemez.

---

## 10. Açık kararlar

- Doğrulama maddeleri PDF ve Excel raporunda nasıl görünecek? Ayrı bölüm gerekiyor; rapor
  şablonu değişikliği bu planda ele alınmadı.
- Derinlik çağrısının maliyeti kabul ediliyor mu? Ekipman içeren analizlerin çoğunda +1
  çağrı demek.
- İSG uzmanı onayı hangi aşamada devreye girecek? Faz 3 içeriği onsuz yazılmamalı.
