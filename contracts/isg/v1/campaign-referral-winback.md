# campaign-referral-winback — davet, geri kazanım, anti-abuse ve bütçe

P15'in sunucu tarafı ilk dilimi. `private_isg.rollout('campaigns')` kapalıdır, istemciye GRANT yoktur. Ödüller doğrudan üretilmez: hepsi P14'ün `grant_benefit` defterinden geçer ve o defter de `access_authority='legacy'` kilidindedir. Hiçbir kampanya burada paid capability açmaz, mağaza teklifi oluşturmaz veya pazarlama mesajı göndermez.

## Ne garanti edilir?

- **Yayın insan kararıdır.** `CHECK(status<>'published' OR (approved_by IS NOT NULL AND approval_note IS NOT NULL AND published_at IS NOT NULL))`; kendi kendini yayınlayan bir sürüm yazılamaz. Yayınlanan sürüm bile `value_source='unapproved_fixture'`, `content_approved=false` taşır ve ürettiği her ödül `needs_review` olur.
- **Anti-abuse yalnız kanonik hesap üzerindendir.** Self-referral, cycle (A→B iken B→A) ve tekrar (`UNIQUE(campaign_id,invitee_owner_id)`) engellenir. Adres, IP, cihaz veya relay alias saklanacak bir sütun **yoktur**; bu yüzden "aynı ağdan" bir kötüye kullanım kanıtı üretilemez.
- **Yalnız gerçek sunucu işi qualify eder.** `qualification_events.event_kind` yedi tamamlanmış mutation ile sınırlıdır; heartbeat, ekran görüntüleme, kişisel not ve başarısız analiz listede değildir ve satır şekli yoktur. `proof_source` yalnız `server_mutation` olabilir. Aynı `operation_id` ikinci kez sayılmaz; qualification **farklı gün** sayısına bakar. Pazarlama rızası ödül koşulu değildir (`marketing_consent_required=false`).
- **Yıllık veya okunamayan davetçi hiçbir dala girmez.** Paid/not-paid gerçeği P14 projeksiyonundan okunur, plan dönemi çağıranın mağaza kataloğundan gelir. `paid_annual` ve `unknown` → `UNSUPPORTED_BRANCH`; otomatik aylığa çevirme yoktur (`auto_plan_conversion=false`) ve bilinmeyen kullanıcı Free sayılmaz (`treated_as_free=false`). Ret, suppression kaydıyla yazılır.
- **Bütçe önce rezerve edilir.** `reserve → commit/release`; kapasite dolduğunda `BUDGET_EXHAUSTED`. `cap_approved` yapısal olarak false.
- **Winback yalnız gerçekten biten aylık ve gerçekten ödeme yapmış hesap içindir.** Ret sebepleri ayrı ayrı kaydedilir: `NEVER_SUBSCRIBED`, `UNKNOWN_LIFECYCLE`, `OTHER_STORE_ACTIVE`, `HOLD_OR_PAUSE`, `REFUNDED_OR_REVOKED`, `NOT_EXPIRED`, `TRIAL_OR_GIFT_ONLY`, `ANNUAL_PLAN`, `UNKNOWN_PLAN_PERIOD`, `GIFT_ACTIVE`.
- **Aile ömür boyu tek episode.** `UNIQUE(campaign_id,owner_id)`; ikinci episode `EPISODE_EXISTS` ve saat yeniden başlamaz.
- **Gönderim anında her şey yeniden okunur:** bekleme süresi, kabul penceresi, temas bütçesi, ikinci temas aralığı, o kanalın pazarlama rızası ve güncel lifecycle. Gönderim sırasında yeniden abone olan kullanıcı `resubscribed` ile susturulur, `accept_until` **değişmez** (`CHECK(NOT ttl_reset)`). Eksik rıza episode'u kapatmaz; kanalın bugünkü cevabıdır.
- **Temas bir deneme kaydıdır.** `CHECK(NOT delivery_claimed)`; teslim iddiası taşıyamaz.
- **Duraklatma yalnız yeni üretimi durdurur.** Kazanılmış benefit ve kabul edilmiş settlement'a dokunulmaz; migration'da hiçbir `DELETE`/`UPDATE` P14 tablolarını hedeflemez.

## Ne garanti edilmez?

Ticari kararlar alınmamıştır: iki gün/30 gün qualification, 72 saat/14 gün/iki temas takvimi, Plus7 ve %20 değerleri hep aday fixture'dır (§19, K06–K10). Gerçek kampanya içeriği, e-posta/push şablonları, gönderim işçisi, admin yüzeyi, fraud operasyon akışı ve P16 izlemesi bu dilimde yoktur. Mağaza teklifinin gerçek uygulanabilirliği P14'ün açık store spike'ına bağlıdır.
