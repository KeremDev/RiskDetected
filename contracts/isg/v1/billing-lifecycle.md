# billing-lifecycle — kanonik abonelik yaşam döngüsü, hediye/indirim ayrımı ve settlement

Bu sözleşme P14'ün sunucu tarafı ilk dilimidir. `private_isg.rollout('billing_lifecycle')` kapalıdır, istemciye GRANT yoktur ve projeksiyon `access_authority='legacy'` kilidindedir: bu defter hiçbir kullanıcının ne yapabileceğine karar vermez. Mevcut RevenueCat yapılandırması, mağaza kataloğu, fiyatlar, legacy paid helper'ları ve kazanılmış haklar değişmemiştir.

## Ne garanti edilir?

- **Kanıt bir kere yazılır.** `billing_lifecycle_evidence` üzerinde `UNIQUE(store,environment,purchase_ref,event_kind,sequence_no)`; duplicate webhook ikinci satın alma değildir. Aynı `purchase_ref`'i başka hesap iddia ederse `PURCHASE_OWNED_ELSEWHERE`.
- **Sıra dışı olay geri yazmaz.** Projeksiyon yalnız `(store_event_at,sequence_no)` çifti ilerlediğinde güncellenir; aksi hâlde `applied=false, reason='out_of_order'` döner ve mevcut durum korunur.
- **Bilinmeyen ≠ Free.** `CHECK(lifecycle_state<>'unknown' OR needs_review)`; okunamayan lifecycle incelemeye düşer, ücretsiz kullanıcı sayılıp kampanya hediyesi üretilmez.
- **Sandbox üretim hakkı vermez.** `environment` hem kanıt hem projeksiyon anahtarındadır; `effective_billing_access` yalnız `production` satırlarını okur.
- **Hediye ile indirim yapısal olarak ayrıdır.** `benefit_definitions` CHECK'leri bir indirim kuponunun capability/tier/süre taşımasını, bir hediyenin ise kotayı sıfırlamasını (`CHECK(NOT resets_quota)`) veya mağaza trial'ı olmasını (`CHECK(NOT is_store_trial)`) imkânsız kılar. Rapor ayrıca `discount_grants_access=false` döner.
- **Hediye sunucu saatiyle çalışır.** `activate_gift` açık eylemle çağrılır, `duration_hours` kadar sürer, ikinci cihaz çağrısı replay'dir ve hiçbir kota rezervasyonu üretmez.
- **Fiyat otoritesi mağazadır.** `store_offer_mappings.price_authority='store'`, imza materyali saklanamaz (`CHECK(NOT signature_material_stored)`) ve teklif varsayılan offering'e giremez (`CHECK(excluded_from_default_offering)`). Bu etiket sunucu yetkilendirmesinin yerine geçmez.
- **Avantaz yoksa teklif yoktur.** `issue_discount_quote` gerçek gözlenmiş iki fiyat ister; teklif ucuz değilse quote `state='rejected', rejection_code='NO_ADVANTAGE'` olarak **yazılır** ve hak `available` kalır. Eski fiyat 100 / liste 150 / teklif 120 durumu böyle görünür olur.
- **Bir quote'tan iki checkout çıkmaz.** `checkout_intents` üzerinde `state='awaiting_store'` için partial unique index; ikinci deneme `INTENT_ALREADY_OPEN`. Timeout iptal değildir: intent ve hak `review`'a gider (`benefit_returned=false`).
- **Ödeme kimliği mağaza kanıtından okunur.** `settle_benefit` environment/store/purchase_ref değerlerini çağırandan almaz; `purchase`/`renewal` dışındaki olay `NO_PAYMENT_EVIDENCE`, başka hesabın kanıtı `ACCESS_DENIED` verir.
- **Tek ödeme tek ekonomik settlement.** `UNIQUE(environment,store,purchase_ref,billing_period)`; anahtarda **family yoktur**, bu yüzden aynı ödemeye referral ve winback iki kez bağlanamaz (`SETTLEMENT_CONFLICT`). İade `adjusted` üretir ve dönemi serbest bırakmaz.
- **Geçişler veri olarak durur.** `benefit_state_edges` 18 satırdır; listede olmayan geçiş `BENEFIT_STATE_INVALID`.

## Ne garanti edilmez?

Gerçek mağaza kabulü yapılmamıştır: Apple promotional offer imzası, Google offer token/replacement mode davranışı, sandbox/production satın alma provası ve eski binary katalog testi açıktır. Katalogdaki 7×24 saat ve %20 onaylı ticari sayı değildir (`value_source='unapproved_fixture'`, `content_approved=false`, `limit_approved=false`). RevenueCat/webhook adaptörü, admin yüzeyi ve native akış bu dilimde yoktur.
