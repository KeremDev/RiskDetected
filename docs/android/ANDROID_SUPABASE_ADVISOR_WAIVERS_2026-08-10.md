# Android Supabase advisor değerlendirmesi

Tarih: 10 Ağustos 2026  
Proje: `riskdetected-android-staging` (`qlymhrrlhklcudveknih`)

Bu kayıt Supabase advisor uyarılarını sessizce bastırmaz; her uyarının neden düzeltildiğini, kabul edildiğini veya açık bırakıldığını gösterir.

## Security advisor

Sonuç: `25 INFO`, `6 WARN`, kritik/yüksek bulgu yok.

### Test kanıtlı kabul: authenticated SECURITY DEFINER RPC'ler

Aşağıdaki beş RPC mobil istemcinin kendi satırına ait işlemi atomik ve kontrollü yapabilmesi için bilinçli olarak `authenticated` rolüne açıktır:

- `acknowledge_legal_document_v1`
- `record_first_seen_device_region_v1`
- `record_notification_open_v1`
- `record_user_engagement_state_v1`
- `set_notification_master_preference_v1`

Ortak güvenlik sözleşmesi `supabase/tests/mobile_security_definer_contract_test.sql` içinde 25 assertion ile sabitlenmiştir:

- `SECURITY DEFINER` bilinçli kullanım.
- `search_path=""`.
- Sahiplik kimliğinin `auth.uid()` üzerinden türetilmesi.
- Yalnız `authenticated` execute.
- `anon` execute reddi.

Input ve çapraz kullanıcı negatif senaryoları ayrıca `first_seen_device_region_test.sql`, `notification_automation_test.sql` ve `global_localization_delivery_test.sql` içinde test edilir. Temiz local replay sonrası bütün pgTAP paketi `478/478` geçmiştir. Bu nedenle [advisor 0029](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) kayıtları tasarım gereği, test kanıtlı waiver'dır.

### Bilinçli INFO: RLS açık, policy yok

25 INFO kaydı private, admin, audit, queue veya service-role tablolarına aittir. Bu tablolara Data API üzerinden mobil kullanıcı erişimi istenmez. Policy eklemek erişim yüzeyini genişleteceğinden [advisor 0008](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) kayıtları deny-by-default kanıtı olarak korunur.

### Açık WARN: leaked-password protection

Staging'de leaked-password protection kapalıdır. [Supabase önerisi](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) uygulanacaktır; ancak önce OTP/Google auth regresyonu ve review hesabı akışı geçmelidir. Bu madde waiver değildir ve release öncesi açıktır.

## Performance advisor

Sonuç: `117 INFO`:

- 21 unindexed foreign key.
- 96 unused index.

`unused_index` kayıtları staging kullanım hacmi düşükken güvenilir silme sinyali değildir; production sorgu istatistiği ve gerçek plan analizi olmadan index silinmeyecektir. Unindexed foreign key'ler de sorgu yolu/ölçüm olmadan topluca eklenmeyecek; notification queue ve silme worker E2E sırasında gerçek `EXPLAIN` kanıtı oluşursa hedefli migration hazırlanacaktır. Release blocker seviyesinde performance uyarısı yoktur.

