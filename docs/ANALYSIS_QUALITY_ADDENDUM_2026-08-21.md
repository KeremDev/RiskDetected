# Analiz Kalitesi — Uzmanlık Derinliği Eki

**Tarih:** 21 Ağustos 2026
**Kapsam:** `PLAN.md` (Bulgu Kapsamı ve Analiz Kalitesi İyileştirme Planı) üzerine ek
**Durum:** Öneri. Sistemde hiçbir değişiklik yapılmadı.

`PLAN.md` "aynı derinlikte daha çok bulgu" problemini çözüyor: bir fotoğraftaki bağımsız
koşulların tek bulguda birleşmesini engelliyor ve eksik bulgu şüphesi olan fotoğrafı ikinci
kez inceletiyor. Bu belge farklı bir problemi ele alıyor: **bulgunun kendi derinliği.**

Ürün hedefi şu şekilde ifade edildi: fotoğraftaki sivri ucun tehlikesini herkes görebilir;
asıl değer makine/ekipman bağlantıları (pim, halat, kayış), basınçlı kap ve proses güvenliği
gibi herkesin göremediği risklerde. Analiz sırasında kullanıcıya soru sorulmayacak.

---

## 1. Merkezi çelişki: istenen çıktı şu an kasten engelleniyor

Tank örneği — *"basınç göstergesi var mı, etiketi var mı, kaynak kontrolleri yapıldı mı"* —
mevcut sistemde üretilemez. İki yerden engelleniyor:

**a) Prompt kuralı** (`supabase/functions/analyze/index.ts:3486`):

> "Eğitim, güvenlik kültürü, prosedür, yetkinlik, periyodik kontrol, gürültü seviyesi,
> havalandırma performansı veya kapalı alan sınıflandırması için doğrudan görünür belge,
> ölçüm, etiket, fiziksel belirti ya da saha koşulu yoksa bulgu üretme. Bir ekipman veya
> işaretin yokluğunu ancak bulunması gereken ilgili alan bütünüyle ve yeterli netlikte
> görünüyorsa bulgu yap."

**b) v164 doğrulayıcısı** — `PHOTO_EVIDENCE_UNSEEN_FACT`, bakım kaydı / periyodik kontrol /
prosedür yokluğu iddialarını reddediyor (`_shared/ai-localization-validation.ts`).

Bu kısıt kasıtlıydı ve uydurma bulguları kesmek için kondu. Ama aynı kural uzmanlığın
yaşadığı yeri de kesiyor: bir İSG uzmanının tanktaki katma değeri "sivri uç var" demek
değil, "bu basınçlı kap mı, emniyet ventili nerede, son periyodik kontrol ne zaman" diye
sormasıdır.

**Kapıyı gevşetmek çözüm değil** — halüsinasyon geri gelir, v164'ün varlık sebebi budur.
Çözüm çıktı sınıfını ayırmaktır.

---

## 2. Öneri 1 — "bulgu" ile "uzman doğrulama maddesi"ni ayır

Sistem şu an iki farklı epistemik iddiayı tek kutuya sokuyor:

| | Bulgu (finding) | Uzman doğrulama maddesi |
|---|---|---|
| İddia | "Bu tehlike **var**" | "Bu ekipman sınıfı **X gerektirir**, fotoğraftan doğrulanamıyor" |
| Kanıt gereksinimi | Görsel kanıt zorunlu | Yalnız ekipman sınıfının doğru tanınması |
| Risk puanı | Fine-Kinney / 5×5 | Yok — bunun yerine öncelik derecesi |
| v164 kanıt kapısı | Geçmek zorunda | İhlal etmiyor: yokluk iddiası değil, görünürlük beyanı |
| Rapordaki yeri | Bulgu listesi | Ayrı "Saha doğrulama listesi" bölümü |

"Basınçlı kapta emniyet ventili ve periyodik kontrol etiketi bu görüntüden doğrulanamıyor;
saha doğrulaması gerekir" cümlesi bir **yokluk iddiası değildir**. Dürüst, denetlenebilir ve
tam olarak istenen uzman derinliğini verir.

Bu ayrım yeni bir doğrulama katmanı gerektirmiyor; zaten var olan iki mekanizmaya oturuyor:
katman durumu `uncertain` ve `needs_field_verification=true`.

Ayrıca ürün hedefindeki "kullanıcıya soru sorma" kısıtını da karşılıyor: kullanıcıya analiz
sırasında soru sormuyoruz, rapor çıktısında bir doğrulama listesi veriyoruz.

---

## 3. Öneri 2 — Kanıt kuralı yeniden yazılmalı

Yukarıdaki (§1a) prompt kuralı **olduğu gibi kalamaz**; ayrılmalı. Bugünkü hâli tek bir
kuralla hem bulguyu hem doğrulama maddesini yasaklıyor.

### Değiştirilecek metin

`supabase/functions/analyze/index.ts:3486` içindeki iki cümle.

### Önerilen yeni hâli (taslak — İSG uzmanı onayından geçmeli)

> Eğitim, güvenlik kültürü, prosedür, yetkinlik, periyodik kontrol, gürültü seviyesi,
> havalandırma performansı veya kapalı alan sınıflandırması için doğrudan görünür belge,
> ölçüm, etiket, fiziksel belirti ya da saha koşulu yoksa **bulgu** üretme. Bir ekipman veya
> işaretin **yokluğunu** ancak bulunması gereken ilgili alan bütünüyle ve yeterli netlikte
> görünüyorsa bulgu yap.
>
> Ekipman sınıfı görüntüden güvenle tanınıyorsa, o sınıf için zorunlu olan ancak bu
> görüntüden doğrulanamayan kontrolleri **bulgu olarak değil**, `field_verification_items`
> içinde doğrulama maddesi olarak yaz. Doğrulama maddesi bir eksikliği iddia etmez; yalnız
> hangi kontrolün bu görüntüden doğrulanamadığını belirtir. "Yok", "eksik", "yapılmamış"
> ifadelerini kullanma; "bu görüntüden doğrulanamıyor" biçiminde yaz. Ekipman sınıfından
> emin değilsen doğrulama maddesi de üretme.

### Neden bu biçim güvenli

- Bulgu tarafındaki yasak **aynen duruyor** — uydurma bulgu yolu kapalı kalıyor.
- Doğrulama maddesi bir yokluk iddiası içermediği için `PHOTO_EVIDENCE_UNSEEN_FACT`
  desenine takılmaz.
- "Yok/eksik/yapılmamış" kelimelerinin açıkça yasaklanması, modelin doğrulama maddesini
  gizli bir bulguya çevirmesini engeller. Bu yasak **doğrulayıcı tarafında da** test
  edilmeli, yalnız prompta güvenilmemeli.
- Ekipman sınıfından emin olma şartı, rastgele kontrol listesi üretilmesini engeller.

### L10N maliyeti — ölçüldü

`3486` **çok satırlı bir template literal**. `scripts/localization_inventory.mjs` yalnız
aynı satırda kapanan tırnaklı metinleri sayıyor, dolayısıyla bu blok kilitli backend
tabanında (L10N-005, 248 girdi) **yer almıyor**. Bu kuralı değiştirmek L10N-005'i kırmaz.

Dikkat: hemen üstündeki `3484` **tek satırlık** bir string ve sayılıyor. Oraya dokunulursa
taban parmak izi değişir ve L10N-005 düşer. Ayrıca satır sayısı değişeceği için
`app-content.csv` yeniden üretilmeli — `make localization-inventory`, ardından
`make localization-check`.

---

## 4. Öneri 3 — Derinliği katman ekleyerek değil, ekipman tetiklemeli modülle ver

13–20. katman **eklenmemeli**. Gerekçeler:

- `INSPECTION_LAYER_KEYS` (`analyze/inspection-layer-audit.ts:1`) 12 elemanlı sabit bir
  tuple; kapsam kayıtları, `representedActionableInspectionLayerCount`,
  `mutate-analysis-finding` ve `LAYER_AUDIT_POLICY_VERSION` buna bağlı. Liste büyütmek
  geçmiş kayıtları ve kapsam metriklerini etkiler.
- Her fotoğraf her katmanın prompt maliyetini öder. Ofis fotoğrafına proses güvenliği
  katmanı yazmak boşa token.

Kodda zaten `scene_elements` var (`analyze/index.ts:378`) — model sahnedeki nesneleri
çıkarıyor. Derinlik modülleri buna bağlanmalı:

| Tetikleyici `scene_elements` | Modül |
|---|---|
| tank, basınçlı kap, silo, boru hattı, kompresör | Proses güvenliği |
| vinç, sapan, halat, kanca, zincir, mapa | Kaldırma donanımı |
| konveyör, kayış, kasnak, zincir dişli, pim, kaplin | Güç aktarımı |
| pano, trafo, jeneratör, kablo kanalı | Elektrik derinliği |

12 katman **kapsam** (breadth) olarak kalır; modüller **derinlik** (depth) ekler ve yalnız
ilgili olduğunda devreye girer.

---

## 5. Öneri 4 — Proses güvenliği gerçek bir kapsam boşluğu

12 katmanda kimyasal (7) ve yangın/patlama (8) var; **basınçlı ekipman ve proses güvenliği
yok**. Tank örneği tam bu boşluğa düşüyor. Bu bir derinlik eksiği değil, kapsam eksiğidir.

Proses güvenliği modülünün bakacakları (taslak — İSG uzmanı onayı şart):

**Görsel olarak tespit edilebilir → bulgu olabilir**
- Gövde korozyonu, deformasyon, şişme, sızıntı izi, boya altı kabarma
- Emniyet ventili tahliye hattının güvensiz yöne bakması
- Manometre camının kırık/okunamaz olması
- Sekonder muhafaza (bariyer havuzu) yokluğu — alan tamamen görünüyorsa
- Esnek hortumda çatlak, ezilme, uygunsuz kelepçe
- Araç çarpma korumasının olmaması — alan tamamen görünüyorsa
- Yanıcı içerik işaretine rağmen topraklama kablosunun bağlı olmaması (görünürse)

**Görüntüden doğrulanamaz → doğrulama maddesi**
- Basınçlı kap mı, atmosferik depolama mı (gövde biçimi belirsizse)
- İçeriğin sınıfı — su, yakıt, kimyasal
- Tasarım basıncı, hacim, imal yılı (imalat plakası okunamıyorsa)
- Son periyodik kontrol tarihi ve kap kontrol raporu
- Kaynak dikişi muayene kayıtları (tahribatsız muayene)
- Emniyet ventili ayar basıncı ve son ayar sertifikası
- Statik elektrik / eşpotansiyel ölçüm değeri

Aynı mantık pim/halat/kayış derinliği için: mevcut 5. ve 6. katman bunları tek satırda
geçiyor ("sapan/halat durumu"). Modül hâlinde: sapan etiketi ve kapasite plakası, kanca
emniyet mandalı, halatta kopan tel / kuş kafesi deformasyonu, kasnak yiv aşınması, kayış
gerginliği ve koruyucusu, zincir uzaması, uygun olmayan cıvata ile yapılmış bağlantı.

---

## 6. Öneri 5 — Risk puanı "barizlik" ile oynatılmamalı

Ürün hedefinde *"sivri ucu düşük skorla analizin altlarında gösterelim"* dendi. Bu maddeye
katılmıyorum.

Fırlamış bir inşaat demiri ölümcüldür (delinme). Bariz olması riskini düşürmez. Bariz
olduğu için puanını düşürmek Fine-Kinney'i kalibrasyonundan koparır ve raporun hukuki
savunulabilirliğini zayıflatır: ölümcül bir tehlikeyi "düşük" diye raporlamış oluruz.

**Bariz olmak ile düşük riskli olmak farklı eksenlerdir.** Önerilen:

```
risk_score      → sıralama ve mevzuat için, değişmez
expert_insight  → ayrı eksen: "uzman gözü gerektiren"
```

Raporda "Uzman değerlendirmesi" adıyla ayrı bir bölüm; oradaki maddeler öne çıkar. Ölümcül
ama bariz bir madde risk sıralamasındaki yerini korur. İstenen vurgu elde edilir, güvenlik
sıralaması bozulmaz.

---

## 7. `PLAN.md` üzerine ek maddeler

Önceki incelemedeki sekiz maddeye ek olarak:

**A.** §2A'daki "aday bulgu" tanımına **doğrulama maddeleri dahil edilmemeli**. Aksi hâlde
`candidate_findings_count` şişer ve §2C-2 kuralı ikinci taramayı gereksiz tetikler. Aday
sayısı yalnız bağımsız fiziksel koşulları saymalı.

**B.** Derinlik modülleri `_shared/ai-localization-prompt.ts` içine eklenirse altı profilin
prompt golden'ı (`fixtures/ai-localization-prompt-golden.json`) birden geçersiz olur ve
"reviewed" fixture yeniden kaydedilmelidir. `analyze/index.ts` tarafındaki analiz bağlamına
eklenirse golden'a dokunulmaz. Bu tercih bilinçli yapılmalı.

**C.** Doğrulama maddelerinin sabit metinleri TR/EN üretilecekse `_shared/user-facing-copy.ts`
içine konmalı; `analyze/index.ts` içine Türkçe diakritikli tek satırlık string eklemek
L10N-005'i kırar.

**D.** Derinlik modülleri `uncertain` katman sayısını artıracak. `PLAN.md` §2C-3 ve §2C-4
tetikleme kuralları katman temsiline bakıyor, dolayısıyla **modüller ikinci taramayı
sistematik olarak tetikleyebilir**. Ölçülen taban tetikleme oranı (son 21 gün, 32 fotoğraf)
§2C-1 ve §2C-2 için **%34,4**; modüller bunun üstüne biner ve planın kendi %50 tavanını
zorlar. Tetikleme kuralları modül farkındalıklı olmalı.

**E.** Maliyet ölçülmeli. Bugünkü taban: analiz başına ortalama **9.121 token**, ortalama
**27 sn** worker süresi (maks. 44 sn). Derinlik modülleri çıktıyı büyütür, ikinci tarama
zaten +%34 çağrı ekler. Bileşik etki `shadow` modda önce yalnız modüller açılarak
ölçülebilir.

**F.** Proses güvenliği ve kaldırma donanımı madde listeleri **İSG uzmanı onayından
geçmelidir**. Mevzuat ve teknik doğruluk gerektiren içerik; Claude veya Codex tek başına
yazmamalı. `docs/android/ANDROID_RELEASE_KALAN_ISLER_2026-08-10.md` dosyasında zaten açık
olan "ISG uzman kalite onayı" kalemiyle birleştirilmeli.

---

## 8. Uygulama sırası önerisi

1. Bulgu / doğrulama maddesi ayrımının şema ve doğrulayıcı tarafında tanımlanması
2. Kanıt kuralının (§3) yeniden yazılması + doğrulayıcıda "yok/eksik/yapılmamış" yasağının
   test edilmesi
3. Tek bir derinlik modülüyle başlanması (proses güvenliği) — kapsam boşluğu en büyük orada
4. `shadow` modda token/gecikme/tetikleme ölçümü
5. İSG uzmanı içerik onayı
6. Kalan modüller
7. `PLAN.md` §2 ikinci tarama mekanizmasıyla birleştirme

Derinlik modülleri ile `PLAN.md`'nin ikinci taraması **aynı sürümde açılmamalı**; ikisi de
tetikleme oranını ve maliyeti etkiliyor, birlikte açılırsa hangisinin ne yaptığı ayırt
edilemez.

---

## 9. Açık kararlar

- Risk puanı / barizlik ayrımı (§6) kabul ediliyor mu?
- Derinlik modülleri prompt sözleşmesine mi, analiz bağlamına mı? (§7B)
- Doğrulama maddeleri PDF ve Excel raporlarında nasıl görünecek? Rapor şablonları bu belgede
  ele alınmadı ve ayrı bir tasarım kararı gerektiriyor.
- İSG uzmanı onayı hangi aşamada devreye girecek?
