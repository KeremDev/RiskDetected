# İSGADA — "Senin İçin" akıllı ana sayfa alanı: uygulama planı

Güncelleme: **24.09.2026** (iki inceleme turunun düzeltmeleri işlendi)  
Kaynak: `ISGADA_Senin_Icin_Akilli_Ana_Sayfa_Plani.md` (ürün planı)  
Durum: Plan onaylandı. Sunucu staging'de iki migration ile çalışıyor: `20260924183727_isg_home_feed` ve kart sayılarını açılan listelerle birebir eşleyen `20260924195143_isg_home_feed_lists`. Yerel veritabanında 14 senaryo geçiyor; staging'de kart ve liste sayılarının eşitliği gerçek hesapla ölçüldü. iOS bağlantısı, hedef eşlemesi ve liste filtreleri tamam; derleme ve sözleşme testi yeşil. Android bağlantısı da tamam: kayıt ve liste hedefleri iOS'takiyle aynı kart filtresiyle açılıyor (derleme ve birim testleri yeşil). Telefonda uçtan uca kontrol henüz yapılmadı.

Bu belge ürün planının mevcut sisteme nasıl oturduğunu, hangi verinin nereden geldiğini ve hangi sırayla yapılacağını takip etmek içindir. Ürün planıyla çelişen veya bugünkü veriyle doğru çalışmayacak maddeler 6. bölümde gerekçesiyle düzeltildi.

## 1. Kesin kararlar

- [x] Ana sayfadaki **Özet** şeridi kişisel hesapta ve OSGB uzmanında kaldırılır; yerine **Senin İçin** gelir.
- [x] OSGB yöneticisinin ana sayfası bu aşamada değişmez. Yöneticinin "sonraki adımı" ekibin işidir ve ayrı tasarlanır (Aşama 3).
- [x] Hangi kartın gösterileceğine **sunucu karar verir**. iOS ve Android aynı sırayı gösterir; kurallar uygulama güncellemesi beklemeden değiştirilebilir.
- [x] Sunucu **cümle döndürmez**. Kart anahtarı, sayı, tarih, kayıt/firma adı ve hedef döndürür. Bütün metinler uygulama kataloglarındadır.
- [x] **Süresi geçmiş ve termini geçmiş durumlar ana kartı alır.** Sıra: süresi/termini geçmiş → yarım kalan iş → yaklaşan → ilk adım (yeni hesap) → ilerleme → keşif → motivasyon.
- [x] Kapatılan ve gösterilen kartlar ile özellik kullanımı **hesapta** tutulur. Kart durumu oturum kapsamına bağlıdır (kişisel veya OSGB çalışma alanı); özellik önerileri hesap geneli bir tercihtir.
- [x] **Süresi Geçenler / Yaklaşan** panosu ayrıntılı liste olarak kalır. Kart, pano ve Evrak Takibi aynı kaynağı ve aynı sınıflandırmayı kullanır: kartta görülen sayı, dokununca açılan listede de aynıdır.
- [x] Haftalık sayılar **"son 7 gün"** olarak hesaplanır: bugün ve önceki 6 gün, İstanbul saatiyle. Zaman damgalı kayıtlar yalnız **şu ana kadar** sayılır; bugünün ilerleyen saatine damgalanmış kayıt sayılmaz.
- [x] Karşılaştırma **yalnız artış varsa** gösterilir. Düşüş, sıfır veya boş sayaç hiçbir kartta görünmez.
- [x] **Kritik kartlar kapatılamaz.** Kayıt düzeltildiğinde kendiliğinden kalkar. Yarım kalan iş tamamlandığında kartı da kalkar.
- [x] Kart, oturumun **açabileceği ve yetkisi olduğu** bir hedefe götürmüyorsa hiç üretilmez: modül kapalıysa, kayıt oluşturan/tamamlayan kartta hesap **veya ilgili modül** yazmaya kapalıysa, ya da uygulama o hedefi açamıyorsa.
- [x] **Kartta görülen sayı, kartın açtığı listede görülen sayıdır.** Hedef, sayılan kayıtların filtresini taşır: tarih aralığı, durum ve OSGB'de "yalnız benim kayıtlarım". Filtrelenmiş bir listesi olmayan sayı için kart üretilmez.
- [x] Kart olayları (gösterildi, kapatıldı, açıldı, geri alındı) cihazda kuyruklanabilir; her olay kendi kimliğini ve gerçekleştiği anı taşır. Tekrar gelen olay etkisizdir, eski olay yeni kararı ezmez.
- [x] Çalışma izni ve KKD kartları **takip vaadi içermez**; ikisi de indirilebilir örnek form kütüphanesine yönlendirir.
- [x] Firması olmayan kullanıcı da gerçek kullanıcıdır. Grup kullanım geçmişinden belirlenir; firma eklemek ayrı bir öneridir.
- [x] Sayılar kayıtların kendi tarihlerinden hesaplanır. Aktivite günlüğü (`business_activity_events`) kullanılmaz: staging'de 17.09.2026'dan önce yoktur, canlıda hiç yoktur.
- [x] Kart metinleri "sen" diliyle, kısa, olumlu ve eyleme dönüktür.

## 2. Ekranın yeni hali

```text
ÜST ALAN      Merhaba, Kerem
              2 işlem dikkat bekliyor            ← mevcut sayaç, katalog metnine alınır

SENİN İÇİN                               Tümü    ← ilk üçün dışında kart varsa
[ ANA KART ]
[ DESTEK KARTI ]   [ DESTEK KARTI ]              ← büyük yazı boyutunda alt alta

YENİ KAYIT        (mevcut Hızlı İşlemler)
SON ANALİZLER     (mevcut)
SÜRESİ GEÇENLER / YAKLAŞAN (mevcut pano)
```

Kart yapısı: tür etiketi ve ikon, başlık, tek satır açıklama, eylem. Kapatılabilen kartlarda sağ üstte kapatma düğmesi bulunur (44 pt dokunma alanı). Kapatılan kart hemen kaybolur, sıradaki kart yerine geçer.

Renkler Nova tasarım sisteminin durum tonlarıyla eşleşir (ürün planı 17. bölüm):

| Ton | Nova rengi | Kart türü |
|---|---|---|
| `brand` | `statusInfo` (lacivert/çivit) | Devam, İlk adım, Motivasyon |
| `feature` | `statusWarning` (amber) | Keşif |
| `danger` | `statusDanger` (kırmızı) | Süresi/termini geçmiş |
| `warning` | `statusWarning` (amber) | Yaklaşan |
| `success` | `statusSuccess` (yeşil) | İlerleme |

Yüzeyler nötr kalır: beyaz zemin, ince kenarlık. Renk ikon, küçük etiket ve eylem metninde; kritik kartta kenarlıkta da kullanılır.

Yükleme sırasında sabit yükseklikte iskelet gösterilir; sayfa zıplamaz. Hata olursa bölüm tek satırlık "Öneriler yüklenemedi · Tekrar dene" satırına döner.

## 3. Mimari

```text
Uygulama ──(kişisel)─────────────▶ isg_home_feed_v1(p_local, p_client)
        └─(OSGB)──▶ isg_expert_rpc_v1 ─┘        │
                                                ▼
            kapsam → yetki → sinyaller → aday kartlar → sözleşme/rota süzgeci → sıralama
                                                │
Uygulama ◀── {segment, signals, cards ≤3, more ≤30, more_total, has_more}
   │  katalogdan metin, kendi rota eşlemesiyle ekran
   │  (her olay önce cihazdaki kuyruğa yazılır: olay kimliği + gerçekleştiği an)
   ├── ekranda gerçekten gösterilen kartlar ─▶ isg_home_card_action_v1('shown', [...], olay, an)
   ├── kapatma / tıklama / geri alma ─▶ isg_home_card_action_v1('dismiss'|'act'|'restore', [kart], olay, an)
   └── sihirbaz, örnek form, istatistik, Evrak Takibi açıldı ─▶ isg_feature_usage_v1(özellik, an)
```

### 3.1 Sunucu (`supabase/migrations/20260924183727_isg_home_feed.sql`, `20260924195143_isg_home_feed_lists.sql`)

İkinci migration yalnız fonksiyon gövdelerini değiştirir: her kartın saydığı kayıtlar, açtığı listenin gösterdiği kayıtlarla aynı olsun diye sayımlar listelerin kurallarına çekilir (3.3) ve uygunsuzluk listesi satırlarına `created_at` ile `created_by_user_id` eklenir. Yetkiler, izin listesi ve kart sözleşmesi değişmez.

| Nesne | Görev |
|---|---|
| `private_isg.home_card_states` | Kullanıcı + kapsam + kart başına durum: `dismissed_until`, `shown_on`, `acted_at` ve son uygulanan kararın anı/kimliği (`decided_at`, `decision_event`). Kapsam `personal`, çalışma alanı kimliği veya (keşif kartları için) `account`. 180 günden eski ve artık bir şey gizlemeyen satırlar silinir. |
| `private_isg.feature_usage` | Kayıt bırakmayan özelliklerin ilk/son kullanımı: `risk_wizard`, `emergency_wizard`, `work_permit_forms`, `ppe_form`, `statistics`, `followup`. İçerik tutulmaz. Tekrar gönderim zararsızdır. |
| `public.isg_home_feed_v1(p_local, p_client)` | Tek okuma: kapsam, yetki, sinyaller, aday kartlar, sıralama. Hiçbir şey yazmaz. |
| `public.isg_home_card_action_v1(p_action, p_cards, p_event, p_occurred_at)` | `shown` (en çok 5 kart; yalnız keşif, ilerleme ve motivasyon kartları hatırlanır), `dismiss` (devam 3 gün, diğerleri 7 gün), `act` (keşif kartı 30 gün dinlenir), `restore`. Kritik kart kapatılamaz. Kurallar 3.2'de. |
| `public.isg_feature_usage_v1(p_feature, p_occurred_at)` | Özellik kullanımı: ilk ve son kullanım anı. Sayaç yoktur; tekrar gelen olay yalnız bu iki anı genişletebilir. |

Güvenlik ve çalışma kuralları:

- Fonksiyonlar `SECURITY DEFINER`, `search_path=''`, `VOLATILE`. Pilot kontrolü `FOR SHARE` kilidi aldığı için `STABLE` olamaz.
- `anon` ve `service_role` çalıştıramaz; tablolar RLS açık ve hiçbir role doğrudan açık değil.
- OSGB oturumu üç uç noktaya `expert_rpc` izin listesi üzerinden ulaşır. Liste, mevcut gövde korunarak yalnız bu üç adla genişletilir; ikinci çalıştırmada bir şey eklemez.
- Yanıtta Türkçe metin yoktur (L10N-005 kapsamı dışında). Kayıt ve firma adları kullanıcı verisidir.
- Kapsam, diğer pilot okumalarla aynıdır: kişisel oturum kendi izinli firmalarını; OSGB oturumu üyeye görünen firmaları okur. "Benim yaptığım" sayılar OSGB'de yalnız üyenin oluşturduğu satırları sayar (`created_by_user_id`). Kişisel firmalarda bütün satırlar zaten kullanıcınındır.
- Yazma yetkisi oturum başına bir kez hesaplanır (`p05_pilot_account_enabled(actor, true)`; OSGB'de yazma reddedilirse salt okunur sayılır). Kayıt oluşturan/tamamlayan kart ayrıca modülün yazma iznini ister: uygunsuzluk, risk ve personel için `rollout.write_enabled`; ekipman, acil durum ve tatbikat için sunucunun kendi `module_gate` kuralı (`modules` rollout'u + modül satırı); eğitim için `education_controls.catalog_v1`.

Performans: bütün sorgular firma kimliği listesiyle ve mevcut `(company_id, …)` / `(user_id, created_at)` indeksleriyle sınırlıdır. Ana sayfa bugün Özet için 3 ayrı istek yapıyor; yeni bölüm tek istek yapar.

Staging ölçümü (24.09.2026, geri alınan işlem içinde pilot hesabın oturumuyla; hiçbir şey yazılmadı):

| Çağrı | Süre |
|---|---|
| Kişisel akış, bağlantıdaki ilk çağrı (fonksiyon derlemesi dahil) | 333 ms |
| Kişisel akış, sonraki çağrılar | 86 ms, 28 ms |
| Karşılaştırma: pano "Süresi Geçenler" isteği (`isg_pilot_followup_v2`) | 29 ms |
| OSGB (`isg_expert_rpc_v1` üzerinden), ilk çağrı | 131 ms |

Hesapta 4 firma, 153 analiz, son 30 günde 84 kayıt vardı. Sonuç sıralaması beklendiği gibi: süresi geçen periyodik kontrol ana kartta, ardından açık kontrol listesi ve taslak uygunsuzluk.

Listeyle eşleşme migration'ından sonra aynı ölçüm (24.09.2026, yine geri alınan işlem içinde):

| Çağrı | Önce | Sonra |
|---|---|---|
| Kişisel akış, ilk çağrı (fonksiyon derlemesi dahil) | 751 ms | 111 ms |
| Kişisel akış, sonraki çağrılar | 24 ms, 20 ms | 23 ms, 21 ms |
| OSGB sahibi (`isg_expert_rpc_v1` üzerinden), ilk / sonraki | — | 319 ms / 30 ms, 28 ms |
| Kartın açtığı listeler (eğitim kaydı, kontrol listesi, 4 firmanın uygunsuzluk listesi) | — | 9 ms, 12 ms, 7 ms |

Kart ile açtığı listenin gösterdiği sayı, kişisel pilot hesapta listelerin kendi RPC'leriyle okunarak karşılaştırıldı:

| Sayı | Kart | Liste |
|---|---|---|
| Tamamlanmış fotoğraf analizi (toplam / son 7 gün) | 153 / 0 | 153 / 0 |
| Eğitim oturumu ve eğitilen kişi, son 7 gün | 1 oturum, 2 kişi | 1 oturum, 2 kişi |
| Açık kontrol listesi | 1 | 1 ("Devam eden" sekmesi) |
| Taslak / termini geçen / son 7 günde kaydedilen uygunsuzluk | 1 / 0 / 0 | 1 / 0 / 0 |

Eğitimin "son tarih" değeri artık oturumun düzenlendiği günü gösteriyor (22.09; önceki kural başlangıç saatini okuyordu). OSGB çalışma alanında uygunsuzluk ve analiz liste satırlarının tamamı `created_by_user_id` taşıyor (uygunsuzlukta `created_at` da); "benim" filtresi bu alanlarla çalışır. Kendi kaydı olmayan OSGB sahibinde kart ve liste sayılarının hepsi 0. Kaydı olan uzmanın aktif oturumu olmadığı için onun adına ölçüm yapılmadı; bu yol yerel testlerle (10. ve 13. senaryo) doğrulanıyor.

### 3.2 İstemci sözleşmesi (`p_client`)

```json
{"contract": 1, "routes": ["followup_record", "followup", "nonconformity", "..."]}
```

- `contract`: uygulamanın tanıdığı kart kümesinin sürümü. Bugünkü bütün kartlar sözleşme 1'dir. Sonradan eklenen kart `since` alanı taşır; eski sözleşmeli uygulamaya hiç gönderilmez.
- `routes`: uygulamanın **bu oturumda** açabildiği hedefler (rol ve menüde görünür modüllere göre). Açılamayan hedefi olan kart sıralamadan önce çıkarılır; bölümde boşluk kalmaz, sıradaki kart yerine geçer. `routes` gönderilmezse sözleşmenin bütün hedefleri varsayılır.
- Uygulama ayrıca tanımadığı bir anahtarı sessizce atlar (emniyet kemeri). Atlama olursa `cards` ve `more` sırası korunarak ilk üç uygun kart gösterilir; keşif kartı en fazla bir tane olur.

**Kart olayları.** Uygulama her olayı `{event: uuid, occurred_at: cihaz anı, action, cards}` olarak üretir, önce cihazdaki kuyruğa yazar, sonra gönderir; sunucu onayladığında kuyruktan siler. Sunucu kuralları:

| Durum | Sonuç |
|---|---|
| Aynı olay ikinci kez gelir | Hiçbir şey değişmez (kapatma süresi uzamaz) |
| Kapatma → geri alma → eski kapatma geç gelir | Kart görünür kalır: kapatma, geri almadan önce olmuştur |
| Dünkü gösterim bugün ulaşır | Gösterim günü dün olarak kalır; gün yalnız ileri gider |
| Olay 30 günden eski | Onaylanır, etkisi yoktur (kuyruk temizlenir) |
| Cihaz saati ileride | An sunucu zamanına çekilir |

Kapatma süresi olayın gerçekleştiği andan sayılır. `restore` da aynı kuyruktan gider. Karar sırası `(occurred_at, event)` ile belirlenir; gösterim ve karar birbirinden bağımsızdır.

### 3.3 Sinyaller ve kaynakları

| Sinyal | Kaynak | Kapsam |
|---|---|---|
| Hesap yaşı | `profiles.created_at` | Kullanıcı |
| Firma, işyeri, personel sayısı | `companies`, `workplaces`, `employees` | Görünen firmalar |
| Analiz (toplam, fotoğraf, son 7, önceki 7, son 30, bugün, son tarih) | Analiz listesiyle aynı: kişisel hesapta hesabın bütün tamamlanmış fotoğraf analizleri (firmalı, firmasız veya arşivlenmiş firmaya ait), oluşturulma anına göre. OSGB: `workspace_analyses` (hazır), üyeye görünen firmalar | Benim |
| Eğitim oturumu ve eğitilen kişi (son 7, önceki 7, son 30) | Eğitim kayıt listesiyle aynı: görünen, silinmemiş, bütün firmaları okunabilen oturumlar, düzenlendiği güne (`held_on`) göre; kişi tamamlanan firma kayıtlarında katıldı işaretli, tekil | Benim |
| Uygunsuzluk (toplam, son 7, önceki 7, taslak) | `nonconformities` | Benim |
| Termini geçmiş uygunsuzluk | `nonconformities` (açık durumlar, `due_on < bugün`) | Görünen firmalar |
| Risk değerlendirmesi (kesinleşen, taslak) | `risk_assessment_versions` | Benim |
| Açık kontrol listesi | `checklist_runs` (`open`): kapsamdaki firmaların kontrolleri ve kullanıcının firmasız kontrolleri (kontrol listesiyle aynı) | Benim |
| Tarihi geçmiş planlı tatbikat | `drill_records` (`planned`, `planned_on < bugün`) | Görünen firmalar |
| Süresi geçen / yaklaşan | `pilot_followup_rows` (pano ve Evrak Takibi ile aynı kaynak; "yaklaşan" kaydın kendi bildirim penceresi) | Görünen firmalar |
| Son 30 günde kayıt, aktif gün, kullanılan modül | Analiz, eğitim, uygunsuzluk, risk, kontrol listesi, ekipman/kontrol, acil durum planı, tatbikat, KKD, evrak, firma kayıtları. Personel kayıtları toplu içe aktarımla yüzlerce satır olabildiği için kayıt sayısına katılmaz; aktif gün ve modül çeşitliliğine katılır. | Benim |
| Kullanılan özellik | `feature_usage` + ilgili modülde kayıt varlığı | Hesap |
| Yazma yetkisi, açık modüller | Pilot hesap/üyelik, `rollout`, `module_registry`, `education_controls` | Oturum |
| Cihazdaki taslaklar | İstemcinin gönderdiği `p_local` (3.6) | Cihaz + kapsam |

### 3.4 Kullanıcı grupları

Grup gerçek kayıtlara göre belirlenir; firma sayısı koşul değildir:

| Grup | Koşul |
|---|---|
| `new` | Toplam anlamlı kayıt < 5 |
| `active` | Son 30 günde ≥ 20 kayıt **ve** ≥ 3 farklı modül **ve** ≥ 6 farklı gün |
| `growing` | Diğerleri |

- `new`: ilk adım kartları öne çıkar; ilerleme kartı yalnız "ilk analizin hazır" kilometre taşıdır.
- Firma eklememiş ama analiz yapan kullanıcı `growing`/`active` olur; "İlk firmanı ekle" kartı ona düşük öncelikle önerilir.
- Eşikler tek yerde, sunucu fonksiyonunda durur ve pilot verisine göre ayarlanır.

### 3.5 Kart kataloğu

Metinler Türkçe katalog değeridir; İngilizce karşılıkları kataloğa birlikte eklenir. `{n}` sayı, `{d}` artış, `{firma}`/`{kayıt}` sunucudan gelen adlardır. "Yetki" sütunu: **Y** = oturumun yazma yetkisi gerekir.

**1. Süresi/termini geçmiş (öncelik 5–6, kırmızı, kapatılamaz)**

| Anahtar | Koşul | Başlık | Açıklama | Eylem → hedef |
|---|---|---|---|---|
| `critical.expired` | Süresi geçen ≥ 1 | {n} kaydın süresi geçti | {tür} · {firma} (+ "ve {n-1} kayıt daha") | İncele → tek kayıtsa kayıt, değilse Evrak Takibi "Süresi doldu" |
| `critical.nonconformity_overdue` | Termini geçmiş açık uygunsuzluk ≥ 1 (uygunsuzluk modülü açık) | {n} uygunsuzluğun termini geçti | {kayıt} · {firma} | İncele → tek kayıtsa kayıt, değilse Uygunsuzluklar "termini geçen" |

Termini geçmiş uygunsuzluk panoda yoktur; bu kart yeni ve gerçek bir sinyal ekler.

**2. Yarım kalan iş (öncelik 10; her kaynaktan en yeni üç kayıt + kalanlar için tek kart (11); lacivert; kapatılırsa 3 gün)**

"N tane daha" kartı ilgili listeyi **bütün** taslaklarla açar (kartta gösterilen üçü dahil); kartın açıklaması bu toplamı söyler.

| Anahtar | Koşul | Yetki | Başlık | Açıklama | Hedef |
|---|---|---|---|---|---|
| `continue.nonconformity_draft` | Benim taslak uygunsuzluğum | Y | Taslak uygunsuzluk kaydın seni bekliyor | {kayıt} · {firma} | kayıt |
| `continue.nonconformity_drafts` | 3'ten fazla taslak | Y | {n} taslak uygunsuzluk daha | Listede {toplam} taslağın tamamı açılır. | Uygunsuzluklar: taslaklar, OSGB'de benim |
| `continue.risk_draft` / `continue.risk_drafts` | Benim taslak risk sürümüm | Y | Taslak risk değerlendirmene devam et / {n} taslak risk değerlendirmesi daha | {işyeri} · {firma} / Listede {toplam} taslağın tamamı açılır. | kayıt / Risk listesi: taslaklar, OSGB'de benim |
| `continue.checklist_open` / `continue.checklists_open` | Benim açık kontrol listem | Y | Kontrol listesini tamamla / {n} açık kontrol listesi daha | {alan} · {firma} / Listede {toplam} açık listenin tamamı açılır. | liste / Kontrol listeleri: açık, OSGB'de benim |
| `continue.drill_result` / `continue.drill_results` | Tarihi geçmiş planlı tatbikat (tatbikat modülü yazılabilir) | Y | Tatbikat sonucunu kaydet / {n} tatbikat sonucu daha bekliyor | {firma} · {tarih} için planlanmıştı / Listede {toplam} tatbikatın tamamı açılır. | tatbikat / Tatbikatlar: sonucu beklenenler |
| `continue.training_draft` | Cihazda yeni eğitim taslağı (eğitim modülü açık) | Y | Başladığın eğitim kaydını tamamla | {firma} · Son düzenleme: {ne zaman} | eğitim düzenleyici (taslak geri yüklenir) |
| `continue.company_create` | Cihazda yarım kalan firma kaydı (yalnız kişisel) | Y | Firma eklemeye devam et | Başladığın firma kaydı tamamlanmadı. | firma ekleme |
| `continue.risk_wizard`, `continue.emergency_wizard`, `continue.emergency_plan_draft` | Aşama 2 | — | — | — | — |

**3. Yaklaşan (öncelik 15, amber, kapatılamaz)**

| Anahtar | Koşul | Başlık | Açıklama | Eylem → hedef |
|---|---|---|---|---|
| `critical.soon` | Yaklaşan ≥ 1 **ve** en yakını 7 gün içinde | {n} kaydın süresi yaklaşıyor | {tür} · {firma} · {tarih} (en yakını) | Gör → tek kayıtsa kayıt, değilse Evrak Takibi "Yaklaşıyor" |

`{n}` panodaki "Yaklaşan" sayısıdır ve açılan liste tam olarak bu kayıtları gösterir. 7 gün yalnız kartın ne zaman öne çıkacağını belirler; sayıyı değiştirmez.

**4. İlerleme (öncelik 30–32, yeşil, kapatılırsa 7 gün)**

| Anahtar | Koşul | Başlık | Açıklama | Eylem |
|---|---|---|---|---|
| `performance.analyses_7d` | Son 7 günde analiz ≥ 1 | Son 7 günde {n} analiz yaptın | Önceki 7 güne göre {d} daha fazla. / Çalışmalarına devam ediyorsun. | Analizleri gör |
| `performance.trained_people_7d` | Son 7 günde eğitilen ≥ 1 | Son 7 günde {n} kişiye eğitim verdin | Artış / {s} eğitim oturumu | Eğitimleri gör |
| `performance.nonconformities_7d` | Son 7 günde uygunsuzluk ≥ 1 | Son 7 günde {n} uygunsuzluk kaydettin | Artış / Takibini tek yerden yapabilirsin. | Uygunsuzlukları gör |
| `performance.analyses_30d` (31) | 7 gün boş, 30 günde ≥ 2 analiz | Son 30 günde {n} analiz yaptın | Son 30 günün analizleri listede açılır. | Analizleri gör |
| `performance.trained_people_30d` (31) | 7 gün boş, 30 günde ≥ 5 kişi | Son 30 günde {n} kişiye eğitim verdin | {s} eğitim oturumu | Eğitimleri gör |
| `performance.first_analysis` | Tek analiz, son 7 günde | İlk analizin hazır | Bulguları inceleyip rapor alabilirsin. | Analizi gör (kaydın kendisi) |

Her ilerleme kartının hedefi, saydığı kayıtların listesidir: analizler/eğitimler/uygunsuzluklar, aynı tarih aralığıyla (`from`–`to`, İstanbul günleri, bugün dahil), tamamlanmış/kaydedilmiş durumla ve OSGB'de `mine`. Eğitim kartında listede görülen sayı oturum sayısıdır ve kartın açıklama satırında da oturum sayısı yazar. Bütün modüllerdeki kayıtları tek listede gösteren bir ekran olmadığı için "N kayıt oluşturdun" kartı yoktur; bu toplam yalnız grup belirlemede kullanılır.

**5. Keşif (öncelik 40, amber; bölümde en fazla bir tane; kapatılırsa 7 gün, açılırsa 30 gün; kullanılan özellik bir daha önerilmez; hesap geneli)**

| Anahtar | Koşul | Yetki | Başlık | Açıklama | Eylem |
|---|---|---|---|---|---|
| `discover.photo_analysis` | Hiç fotoğraf analizi yok (yeni olmayan hesap) | Y | Fotoğraftan analizi keşfet | Bir fotoğraf yükle, riskleri hızlıca tespit et. | Dene |
| `discover.risk_wizard` | Risk modülü açık, sihirbaz kullanılmadı | — | Risk Analizi Sihirbazını denedin mi? | Adım adım ilerle, taslak risk değerlendirmeni hazırla. | Hemen dene |
| `discover.nonconformity` | Firma var, uygunsuzluk kaydı yok | Y | Uygunsuzluk takibini dene | Sahada gördüğün eksikleri termin ve sorumluyla takip et. | Kayıt oluştur |
| `discover.training` | Eğitim modülü açık, firma var, eğitim kaydı yok | Y | İlk eğitim kaydını ekle | Katılımcıları ve geçerlilik tarihlerini tek yerden yönet. | Eğitim ekle |
| `discover.equipment` | Ekipman modülü açık, firma var, ekipman yok | Y | Periyodik kontrolleri takip et | Ekipmanlarını ekle, kontrol tarihleri yaklaşınca gör. | Ekipman ekle |
| `discover.emergency_wizard` | Acil durum modülü açık, plan ve sihirbaz kullanımı yok | — | Acil durum planını sihirbazla hazırla | Birkaç soruyla düzenlenebilir bir taslak oluştur. | Dene |
| `discover.checklist` | Firma var, kontrol listesi yok | Y | Kontrol listelerini dene | Hazır listelerle saha denetimini hızlandır. | Listeleri aç |
| `discover.work_permit_forms` | Kütüphane açık, açılmadı | — | Hazır çalışma izni formları | Düzenlenebilir örnek formları incele ve indir. | Formlara göz at |
| `discover.ppe_form` | KKD modülü açık, form kullanılmadı | — | KKD zimmet formu hazır | Düzenlenebilir Word örneğini indir. | Formu aç |
| `discover.statistics` | ≥ 3 analiz veya 30 günde ≥ 10 kayıt, ekran açılmadı | — | İstatistiklerini gör | Analiz ve eğitim sayılarını aylık grafikte gör. | Aç |
| `discover.followup` | Süreli kayıt var, Evrak Takibi açılmadı | — | Evrak Takibi ile süreleri kaçırma | Bütün belgelerin geçerlilik tarihleri tek listede. | Aç |

Günde bir keşif kartı: uygulamanın gerçekten gösterdiği ve `shown` ile bildirdiği kart gün boyu aynı kalır; ertesi gün en uzun süredir gösterilmeyen (veya hiç gösterilmemiş) aday gelir.

**6. İlk adım ve motivasyon (lacivert, kapatılırsa 7 gün)**

"Y" sütunu hesabın ve ilgili modülün yazma iznini birlikte ifade eder (personel kartında `rollout.personnel.write_enabled`).

| Anahtar | Öncelik | Koşul | Yetki | Başlık | Açıklama | Eylem |
|---|---|---|---|---|---|---|
| `motivation.first_company` | yeni: 25, diğer: 45 | Kişisel hesapta firma yok ve yarım firma kaydı yok | Y | İlk firmanı ekleyerek başla | Firma bilgilerini eklediğinde diğer modülleri daha verimli kullanabilirsin. | Firma ekle |
| `motivation.first_personnel` | yeni: 26, diğer: 46 | Personel modülü açık, firma var, personel yok | Y | Personel listeni oluştur | Eğitim kayıtları ve katılımcı listeleri personel üzerinden ilerler. | Personel ekle |
| `motivation.first_analysis` | 27 | Yeni hesap, hiç analiz yok | Y | İlk analizini yap | Bir fotoğraf yükleyerek risk tespit etmeye başla. | Başla |
| `motivation.today_analysis` | 60 | Analiz geçmişi var, bugün yok | Y | Yeni bir saha analiziyle devam et | Fotoğraftan analizle hızlıca başlayabilirsin. | Başla |
| `motivation.statistics` | 61 | Analiz veya son 30 günde kayıt var | — | Gelişimini takip et | İstatistikler ekranında çalışmalarının güncel görünümünü gör. | Aç |
| `motivation.photo_analysis` | 90 | Her zaman (bölüm boş kalmasın) | Y | Yeni bir analizle başla | Fotoğraf yükle, bulguları hızlıca gör. | Başla |

### 3.6 Cihazdaki taslaklar (`p_local`)

Cihazda duran taslakları sunucu göremez. İstemci yalnız şu özeti gönderir; içerik cihazdan çıkmaz:

```json
[{"kind": "training_draft", "ref": "4d0f…-uuid", "company_id": null, "updated_at": "2026-09-24T09:12:00Z"}]
```

- `ref` taslağın **kendi benzersiz kimliğidir** (taslak ilk kaydedildiğinde üretilir, taslak silinince kaybolur). Böylece iki cihazdaki veya iki çalışma alanındaki taslaklar karışmaz; birini kapatmak diğerini gizlemez.
- Taslaklar oturum kapsamında okunur (kullanıcı + çalışma alanı; iOS'ta `storageNamespace`, Android'de aynı ad alanı).
- Türler: `company_create`, `training_draft`, `emergency_plan_draft`, `risk_wizard`, `emergency_wizard`. En çok 20 öğe, 8 KB.
- Geçersiz öğe sessizce atlanır; 30 günden eski taslak, tekrar eden öğe, oturumun göremediği firmaya ait taslak ve bu oturumda tamamlanamayacak taslak (yetki, modül, OSGB uzmanının firma taslağı) gösterilmez. Gelecek tarih şimdiye çekilir.
- Aşama 1'de gönderilen gerçek taslaklar:
  - `training_draft`: yeni eğitim kaydının otomatik taslağı; yalnız anlamlı içerik varsa (başlık, eğitici veya en az bir firma kapsamı). Taslakla birlikte kimlik ve son düzenleme zamanı da saklanır.
  - `company_create`: gönderim sırasında yarıda kalan firma kaydı (bugün yalnız gönderim yarıda kalırsa oluşur).

### 3.7 Sıralama ve "Tümü"

1. Adaylar üretilir (3.5); modül, yetki ve istemci sözleşmesi/rota süzgeci uygulanır.
2. Kapatma süresi dolmamış kartlar çıkarılır (kritik hariç).
3. Öncelik, sonra kartın kendi sırası (yarım işte en yeni, ilerlemede en güçlü, keşifte rotasyon).
4. **Bölüm (`cards`)**: ilk üç kart; aynı türden en fazla iki, keşiften en fazla bir.
5. **Tümü (`more`)**: kalan bütün kritik, yarım iş ve ilerleme kartları + sıradaki üç keşif + sıradaki iki motivasyon kartı; en çok 30. Yarım işte her kaynak en fazla dört kart üretir (üç kayıt + "N tane daha" kartı), bu yüzden liste pratikte sınırlanmaz. `more_total` ve `has_more` yine döner; `has_more` doğruysa "Tümü" sayfasının sonunda "Diğer kayıtlar ilgili modül listelerinde" satırı gösterilir.
6. Uygulama gösterdiği kartları `shown` ile bildirir (günde bir kez, kart başına). Sunucu okuma sırasında hiçbir şey yazmaz.

### 3.8 İstemci entegrasyonu

Ortak parçalar (iOS ve Android aynı adlarla):

| Parça | iOS | Android |
|---|---|---|
| Model ve metinler | `App/DesignSystem/ISG/NovaForYouSection.swift`: çözücü, `NovaForYouCopy` (anahtar → katalog metni; bilinmeyen anahtar → kart atlanır), görünüm | `feature/nova/.../NovaForYouSection.kt` (tasarım sistemi `core/data`'ya bağlı olmadığı için modeller `core/data`'da, görünüm `feature/nova`'da) |
| Servis | `App/Services/ISG/NovaForYouService.swift`: üç RPC, mevcut `NovaExpertTransport` ile (OSGB'de otomatik `isg_expert_rpc_v1`) | `core/data/.../nova/NovaForYou.kt`, `NovaExpertTransport.execute` |
| Olay kuyruğu | Her olay (`shown`, `dismiss`, `act`, `restore`, özellik kullanımı) kimliği ve anıyla önce kullanıcı + kapsam başına kalıcı kuyruğa yazılır (en çok 50 olay; 30 günden eskiler düşer), gönderilir ve sunucu onaylayınca silinir. Yükleme öncesi kuyruk boşaltılır; böylece yanıt son kararları yansıtır | Aynı |
| Önbellek | Son yanıt kullanıcı + çalışma alanı anahtarıyla bellekte; sekme geçişinde iskelet tekrar görünmez | Aynı |
| Bağlantı | `NovaDashboardScreen`'e `forYou: AnyView?` alanı; `NovaPilotRoot` besler (pano ile aynı desen) | `NovaDashboardScreen(forYou = …)` yuvası |
| Yerel taslak özeti | `NovaLocalDraftDigest`: eğitim ve firma taslakları | Aynı |

Yenileme: ana sayfa görünür olduğunda, sekme değişince, `isgada.records.changed` bildiriminde, uygulama öne gelince ve kart hedefinden geri dönülünce.

Hedef eşlemesi (`target.route` → ekran). `routes` listesine yalnız bu oturumda açılabilenler **ve hedefin bütün filtrelerini uygulayabilenler** yazılır. Filtresi henüz uygulanmayan hedef listeye yazılmaz; sunucu o kartı hiç göndermez:

| Hedef | Kişisel / OSGB uzmanı | Not |
|---|---|---|
| `followup_record` (`kind`, `id`, `status`) | `NovaFollowupDestination` (panonun açtığı ekran) | Satır dokununca `isg_pilot_followup_v2(status)` ile alınır; zenginleştirme tek yerde kalır |
| `followup` (`status`) | Evrak Takibi, durum filtresi seçili | Yeni: başlangıç filtresi |
| `nonconformity` (`id`, `company_id`) | Uygunsuzluk kaydı panonun üstünde açılır | iOS tamam: `NovaPilotFindingsGate(initialRecord:)` |
| `nonconformities` (`status`: `overdue`, `draft`, `recorded`; `from`/`to` = kayıt günü; `mine`) | Uygunsuzluklar, kartın filtresi seçili | iOS tamam: `NovaListPreset`; `recorded` ve `mine` ikinci migration'daki satır alanlarını kullanır |
| `risk_assessment` (`id`) / `risk_assessments` (`status: draft`, `mine`) | `NovaPilotRiskGate(initialRecordID:)` / Risk listesi | Kayıt açılıyor. Liste henüz beyan edilmiyor: sunucu listesi `draft` durumunu kabul etmiyor; en yeni üç taslak tek tek kart olarak geliyor |
| `checklist_run` (`id`) / `checklists` (`status: open`, `mine`) | Kontrol, kendi ekranında / "Devam eden" sekmesi | iOS tamam. `checklists` yalnız kişisel oturumda beyan edilir: OSGB listesi bütün üyelerin kontrollerini gösteriyor, "benim" filtresi yok |
| `drill` (`id`) / `drills` (`status: result_due`) | Tatbikat kaydı / planlanan günü geçmiş tatbikatlar | Henüz beyan edilmiyor: planlı tatbikatlar yalnız eski, salt okunur ekranda |
| `analysis` (`id`) | Analiz kaydı | Mevcut (`pendingDashboardAnalysisID`) |
| `analyses` (`status: completed`, `from`/`to` = analiz günü, `mine`) | Analizler, kartın filtresi seçili | iOS tamam: liste en yeniden eskiye okunur ve `from` gününden eski satıra ulaşana kadar sayfa çekilir |
| `trainings` (`status: completed`, `from`/`to` = eğitim günü, `mine`) | Eğitimler, kartın filtresi seçili | iOS tamam: üstteki eğitilen kişi ve süre toplamları da filtreye uyar |
| `training_create` (`ref`) | `.newTraining` | Düzenleyici taslağı geri yükler |
| `company_create` (`ref`) | firma ekleme | Yalnız kişisel |
| `statistics`, `equipment`, `personnel` | Mevcut rotalar | |
| `photo_analysis` | `.newAnalysis` | |
| `nonconformity_create` | `.newFinding` | |
| `risk_wizard`, `emergency_wizard` | Risk / Acil Durum ekranı, sihirbaz açık | Yeni: `startWithWizard` |
| `work_permit_forms`, `ppe_form` | `.workPermits`, `.ppeHandovers` | |

Liste filtrelerinin uyması gereken iki kural:

- `from`/`to` İstanbul günleridir; liste filtreyi cihazın saat dilimiyle değil İstanbul saatiyle uygular.
- Liste, kartın saydığı kayıtların aynısını gösterir. Eşitlik sayımın listeye uyarlanmasıyla sağlanır (3.3): liste neyi gösteriyorsa kart onu sayar. `mine` yalnız üyenin oluşturduklarıdır.
- Kartın filtresi listede kartın kendi cümlesiyle, kaldırılabilir bir etiket olarak görünür (`NovaListPreset`, `NovaListPresetChip`); kaldırılınca liste her zamanki görünümüne döner. Listenin diğer filtreleri bu etiketle birlikte çalışır.

Özellik kullanımı çağrıları: sihirbaz taslak ürettiğinde (`risk_wizard`, `emergency_wizard`), çalışma izni kütüphanesi açıldığında (`work_permit_forms`), KKD örnek formu açıldığında (`ppe_form`), İstatistik ekranı açıldığında (`statistics`), Evrak Takibi açıldığında (`followup`). Başarısız çağrı kuyruğa girer.

Aynı motoru kullanan diğer yerler:

- **Menüdeki "Sıradaki işin" kartı** sabit kural yerine Senin İçin'in ilk devam/ilk adım kartını gösterir. İlerleme çubuğu kalkar (8 adımlık sayaç gerçek bir ölçüye dayanmıyor).
- **Üst alandaki sayaç** ("Bugün N işlem bekliyor", bugün kodda sabit Türkçe) katalog metnine alınır: "{n} işlem dikkat bekliyor" / "Bekleyen işlem yok". Kaynak aynı kalır.

Kaldırılanlar: kişisel ve uzman ana sayfasındaki Özet şeridi (`NovaMetricItem` listesi, ekipman özet isteği). Yönetici ana sayfası Aşama 3'e kadar olduğu gibi kalır.

## 4. Veri doğruluğu kuralları

- Gün sınırları İstanbul saatine göredir; sunucu tarafında hesaplanır, cihaz saati kullanılmaz.
- Zaman damgalı kayıtlar sunucunun **şu anki** zamanına kadar sayılır. Gelecek tarihli, iptal edilmiş ve taslak kayıt "yapılan iş" sayılmaz.
- Başarısız veya süren analiz sayılmaz. Arşivlenmiş firma ve pilot izni kalkmış firma kapsam dışıdır; tek istisna analizlerdir: analiz listesi hesabın bütün tamamlanmış fotoğraf analizlerini gösterdiği için kart da hepsini sayar.
- Çok firmalı eğitim oturumu bir kez, düzenlendiği güne göre sayılır; eğitilen kişi tekil sayılır; katılmadı işaretli kişi sayılmaz. Firmalarından biri okunamayan oturum listede görünmediği için sayılmaz.
- Taslak uygunsuzluk termini geçmiş sayılmaz (sunucu, pano ve uygunsuzluk listesinin "Termini geçen" filtresi aynı kuralı uygular).
- OSGB'de "benim" sayıları başka uzmanın kaydını içermez. Süre ve termin durumları kapsamdaki bütün kayıtları içerir: uzmanın atandığı firmada kim açmış olursa olsun gecikme uzmanı ilgilendirir.
- Modül kapalıysa ilgili sayı `null` döner, `0` değil ("bilinmiyor" ile "yok" karışmaz).
- Kartta görülen sayı, kartın açtığı listede görülen sayıyla aynıdır.

## 5. Test kapsamı (sunucu)

`node scripts/home/run_database.mjs` (yerel PostgreSQL veya Docker; sahte tablolarla 14 senaryo; iki migration sırayla uygulanır). Sıralama, olay sırası ve modül yazma kuralı kasıtlı bozulduğunda testin düştüğü doğrulandı:

1. Kişisel hesap: süresi geçen ana kartta, sonra taslak, sonra yaklaşan; yaklaşan kartın sayısı ve hedefi listeyle aynı; ilerleme kartlarının hedefi aynı tarih aralığı, durum ve "benim" filtresini taşıyor; listesi olmayan "kayıt" kartı yok.
2. Bugünün ilerleyen saatine damgalı kayıt sayılmıyor; 7 günlük pencerenin sınırı saniyesiyle doğru.
3. Kapatma: devam 3 gün, kritik kapatılamaz, toplu kapatma reddedilir, geri alma çalışır, durum kişisel kapsamda.
4. Çok taslak: en yeni üç kayıt + "N tane daha" kartı (toplamı ve listenin filtresiyle); hiçbir şey sessizce kesilmiyor.
5. İstemci sözleşmesi: açılamayan hedefli kart çıkar, sıradaki yerine geçer; hatalı sözleşme reddedilir.
6. Salt okunur oturum: kayıt oluşturan/tamamlayan kart yok, cihazda çalışan sihirbaz önerisi var.
7. Yeni hesap ve cihaz taslakları: geçersiz, eski, yabancı firmaya ait, tekrarlı ve gelecek tarihli öğeler.
8. Keşif rotasyonu yalnız istemcinin bildirdiği gösterimle ilerliyor; okuma bir şey yazmıyor; öneriler hesap geneli.
9. Firmasız ama aktif kullanıcı `new` sayılmıyor; firma önerisi alt sırada.
10. OSGB uzmanı ve yöneticisi: kapsam, "benim" ayrımı, termini geçen uygunsuzluk önde, durum çalışma alanı kapsamında, yazma reddi salt okunur sayılıyor.
11. Olay kuyruğu: aynı olay ikinci kez etkisiz; geri almadan önceki kapatma kartı yeniden gizlemiyor; geç gelen gösterim kendi gününde kalıyor; 30 günden eski olay yok sayılıyor; ileri cihaz saati sınırlanıyor; olay kimliği zorunlu.
12. Modül yalnız okumaya açıkken o modülde kayıt oluşturan/tamamlayan kart yok; kritik ve ilerleme kartları duruyor.
13. Listeyle eşleşme: firmasız kendi kontrolü sayılır, başkasınınki ve kurum kontrolü sayılmaz; eğitim düzenlendiği güne göre sayılır, okunamayan firmalı oturum sayılmaz; uygunsuzluk listesi satırı oluşturulma anını ve oluşturanı taşır.
14. Kapılar, yetkiler, izin listesinin tek sefer genişlemesi ve ikinci çalıştırmada değişmemesi.

## 6. Ürün planında düzeltilen noktalar

| Plan maddesi | Durum | Karar |
|---|---|---|
| Öncelik: yarım iş → kritik | Taslaklar gecikmeleri ana karttan itebiliyordu | Süresi/termini geçmiş → yarım iş → yaklaşan. |
| "Çalışma izinlerini tek yerden takip edin" | Ürün kararıyla çelişiyor | Örnek form kütüphanesine yönlendiren kart. |
| "Eğitim ve KKD kayıtları personel üzerinden…" | KKD artık indirilebilir örnek form | "Eğitim kayıtları ve katılımcı listeleri personel üzerinden ilerler." |
| "Bugün henüz analiz yapmadın" | Suçlayıcı okunabiliyor | "Yeni bir saha analiziyle devam et". |
| "Sihirbazdaki son çalışmanı tamamla" | Sihirbaz bugün hiçbir şey saklamıyor | Aşama 2: iki sihirbaz için ortak, sürümlü taslak modeli (7. bölüm). |
| "Firma eklemeye devam et" | Firma formu taslak tutmuyor | Aşama 1'de yarım gönderim; Aşama 2'de form taslağı. |
| "Risk Analizi Sihirbazını denediniz mi?" | Kullanım görünmüyordu | `feature_usage` (Aşama 1). |
| "Bu hafta … / Geçen haftaya göre %20" | Takvim haftası yanıltıcı; yüzde küçük sayılarda abartılı | "Son 7 gün" ve adet olarak artış. |
| "1 süresi yaklaşan kontrol var" | 7 günlük sayı ile listedeki pencere farklıydı | Sayı panonun "Yaklaşan" sayısı; 7 gün yalnız kartın öne çıkma koşulu. |
| Yeni kullanıcı segmenti "firma eklememiş" | Firmasız çalışan aktif kullanıcı sürekli "yeni" kalırdı | Grup kayıtlardan; firma ayrı öneri. |
| Kritik kart ile pano | Aynı gecikme iki yerde | Kart özetler ve panoya/kayda götürür; sayılar aynı kaynaktan. |
| Yönetici | Plan yalnız uzmanı tarif ediyor | Aşama 3. |

## 7. Aşamalar

### Aşama 1 — Senin İçin (kişisel + OSGB uzmanı)

- [x] Sunucu: tablolar, üç fonksiyon, istemci sözleşmesi, `expert_rpc` izin listesi
- [x] Sunucu testi: `scripts/home/` (14 senaryo; bozulan sıralama, olay sırası ve modül yazma kuralını yakaladığı doğrulandı)
- [x] Staging'e uygulama (`20260924183727`) ve gerçek hesapla ölçüm (kişisel ve OSGB yolu)
- [x] Listeyle eşleşme migration'ı (`20260924195143_isg_home_feed_lists.sql`), yerel test
- [x] Listeyle eşleşme migration'ının staging'e uygulanması (`20260924195143`), yetki kontrolü ve ölçümün tekrarı
- [x] iOS: kart bileşeni, servis, olay kuyruğu, bağlantı, "Tümü" sayfası
- [x] iOS: hedef eşlemesi ve liste filtreleri (`nonconformity`, `nonconformities`, `checklist_run`, `checklists` kişisel, `analyses`, `trainings`); derleme ve sözleşme testi yeşil
- [x] iOS: yerel taslak özeti (eğitim taslağı kimliği ve zamanı, yarım firma kaydı)
- [x] iOS: özellik kullanımı çağrıları; menü kartı; üst alan sayacı metni; L10N-018 kilidi
- [x] Android: servis, olay kuyruğu, son yanıtın bellekte tutulması, yükleme öncesi kuyruk gönderimi, ana sayfa yuvası, menü kartı, üst alan metni, özellik kullanımı çağrıları, temel hedefler (`followup_record`, `followup`, `analysis`, `risk_assessment`, sihirbazlar, oluşturma ve modül hedefleri). HEAD üzerinde derleme; `core:designsystem` 520 ve `core:data` 674 birim testi geçiyor (JDK 17)
- [x] Android: `nonconformity`, `checklist_run` ve liste hedefleri (`nonconformities`, `analyses`, `trainings`, `checklists` yalnız kişisel oturumda); liste kartın filtresiyle ve kartın cümlesiyle açılır (`NovaListPreset`, `NovaListPresetChip`). `NovaListPresetTest` 6 test; `core:data` 680, `core:designsystem` 520 test geçiyor
- [x] Sözleşme testi iOS ve Android'i birlikte denetliyor (`node --test scripts/home/contract.test.mjs`, 6 test)
- [ ] Testler: iOS birim + kabuk UI testi, Android Robolectric, L10N kapıları, Android İngilizce kontrolü
- [ ] Emülatör ve simülatörde uçtan uca kontrol (yeni hesap, orta hesap, firmasız hesap, OSGB uzmanı)

### Aşama 2 — Yarım kalan her işin geri gelmesi

Risk ve acil durum sihirbazları aynı ekran yapısını ve aynı taslak ihtiyacını paylaşır. İkisi için tek, sürümlü bir taslak modeli yazılır:

```text
NovaWizardDraft { schema: 1, id, domain: "risk" | "emergency", engine_version, catalog_version,
                  company_id?, workplace_id?, step, answers, updated_at }
```

- Acil durum sihirbazında seçimler ekran durumunda (`selections`, `states`, `method`, `preset`, `step`) duruyor; doğrudan `answers` olur.
- Risk sihirbazında seçimler Swift durumunda değil, JavaScript köprüsünün içinde (`RDBridge.act`) duruyor. Taslak için köprüye durum dışa/içe aktarma eklenir; olmazsa `act` adımları sırasıyla kaydedilip açılışta yeniden oynatılır (motor deterministik).
- Katalog sürekli genişleyeceği için (yeni sektör, ekipman, iş) **katalog güncellemesi taslağı geçersiz kılmaz.** Cevaplar soru ve seçenek kimlikleriyle saklanır; açılışta:
  - kimliği hâlâ var olan cevaplar olduğu gibi korunur,
  - kaldırılan seçenek düşer, anlamı değişen veya kaldırılan soru "yeniden cevapla" olarak işaretlenir ve kullanıcı yalnız o adımlara götürülür,
  - yeni eklenen sorular boş gelir (cevapsız soru "yok" sayılmaz; mevcut kural),
  - risk sihirbazında adım kaydı yeniden oynatılırken artık bulunmayan seçimler atlanır ve aynı işaretleme yapılır.
- Baştan başlatma yalnız son çare: taslak şeması dönüştürülemiyorsa (ör. motorun büyük sürüm değişikliği). Bu durumda da taslak silinmeden önce kullanıcıya özeti gösterilir.
- [ ] Ortak taslak modeli ve saklama (kullanıcı + çalışma alanı kapsamında, cihazda)
- [ ] Açılışta "Devam et / Baştan başla"
- [ ] Firma ekleme formu taslağı; kişisel acil durum planı taslağı (bugün yalnız bellekte)
- [ ] Bu taslaklar `p_local` ile gönderilir; devam kartları açılır

### Aşama 3 — OSGB yöneticisi

- [ ] "Ekibin için" varyantı: atanmamış firma, uzman bazında geciken işler, bekleyen davet, son 7 günde ekip performansı
- [ ] Yönetici ana sayfasında Özet'in yerini alır

### Aşama 4 — Canlı

- [ ] Kişisel yolu içeren kırpılmış paket: OSGB dalları ve `created_by_user_id` filtresi çıkarılır (canlıda bu sütunlar ve `expert_*` fonksiyonları yok)
- [ ] `supabase/pilot-release/supabase/migrations/<canlı sürüm>_isg_home_feed.sql`
- [ ] Eski canlı uygulama bu fonksiyonları çağırmaz; yeni tablo ve fonksiyonlar eklenir. Değişen tek mevcut nesne `read_nonconformities`: liste satırlarına iki alan eklenir, eski sürümler bilinmeyen alanı yok sayar (iOS `JSONDecoder`, Android `ignoreUnknownKeys = true`). Canlıdaki kişisel sürüm (`owner_id = actor`) aynı iki alanla yamalanır, OSGB sürümü taşınmaz

## 8. Açık konular

- Başka bir oturum liste ekranlarının görünümünü yeniledi (`NovaListHint`, `NovaListSectionHeading`, `NovaListActionButton`, 9f52156b); aynı dosyalara (uygunsuzluk, analiz, eğitim listeleri) bu işin küçük eklemeleri de girdi. O işin kataloğa alınmamış metinleri L10N-004, L10N-013 (`localizable.nova.document.filter.all`) ve envanter kontrolünü kırmızıya çevirmişti; 2026-09-25'te metinler kataloğa taşındı (18 yeni birim, `localizable.nova.file.add.short` "Dosya Ekle" oldu) ve bütün yerelleştirme kapıları yeniden yeşil.
- Uygunsuzluk listesi sunucuda firma başına en yeni 200 kaydı döndürüyor. 200'den fazla kaydı olan firmada eski tarihli geciken kayıt listede görünmeyebilir; pilot ölçeğinde sorun değil, büyüyünce sunucu tarafında `overdue` filtresi eklenecek.
- `risk_assessments` (taslak listesi) ve `drills` hedefleri henüz beyan edilmiyor (3.8); OSGB oturumunda `checklists` beyan edilmiyor. Bu hedefler beyan edilene kadar sunucu ilgili kartları göndermiyor.
- Staging migration geçmişinde kayıtsız uygulanmış dört migration var (20260922123500, 20260922124000, 20260924235900, 20260924235930). Bu migration MCP ile tek başına uygulanacak; toplu `db push` yapılmayacak.
- Eşikler (yeni/aktif grup, 30 günlük yedek kartlar) pilot verisi biriktikçe gözden geçirilecek.
