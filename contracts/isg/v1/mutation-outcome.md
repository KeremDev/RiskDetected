# Mutation outcome v1

Additive sözleşme: yeni Deno/Swift/Kotlin parser ve saf state reducer; **eski endpoint'lere, UI'a veya polling loop'una bağlı değil**. V5 §13.2 hata ailesi canonical tutuldu. Geçiş planındaki alternatif adlar yalnız aşağıdaki açık mapping ile yeni handler'da çevrilebilir; eski API biçimleri değişmez.

Her yanıtın ortak alanları: `schema_version=1`, lowercase UUID `operation_id` ve `request_id`, içeriksiz `support_id` (`ISG-` +12 uppercase hex), `outcome`. Bilinmeyen/eksik alan ve tip reddedilir. Support ID sunucuda rastgele üretilip log correlation için kullanılacak; bu parser üretim/benzersizlik garantisi vermez. Serbest hata mesajı, SQL stack, müşteri/şirket adı, `details`, token, user_id veya arbitrary payload kabul edilmez.

| outcome | HTTP | Ek zorunlu alanlar | Anlam |
|---|---|---|---|
| committed | 200 | version:0..9007199254740991, projection:ready/pending/failed | Transaction tamamlandı; projection'ın beklemesi/başarısızlığı yazımı geri almaz |
| pending | 202 | code:JOB_PENDING, retry_after_seconds:1..300 | Mantıksal işlemin tamamlanması bekleniyor; status sorgula |
| indeterminate | 503 | code:RETRYABLE_FAILURE, retry_after_seconds:1..300 | Yazımın sonucu belirsiz; başarısız/rollback olduğu varsayılmaz |
| rejected | Aşağıdaki tablo | code; sadece VERSION_CONFLICT için current_version | Kontrollü ret; yeni işlem için kullanıcı düzeltmesi/yetki çözümü gerekir |

| Canonical code | HTTP | Geçiş planı/prototype alias |
|---|---|---|
| AUTH_REQUIRED | 401 | aynı |
| COMPANY_ACCESS_DENIED | 403 | ACCESS_DENIED |
| CAPABILITY_DISABLED | 403 | — |
| CROSS_COMPANY_REFERENCE | 403 | — |
| VERSION_CONFLICT | 409 | aynı; current_version zorunlu |
| VALIDATION_FAILED | 422 | VALIDATION_ERROR |
| RULE_REVIEW_REQUIRED | 409 | RULE_NEEDS_REVIEW |
| DOCUMENT_NOT_READY | 409 | — |
| QUOTA_EXCEEDED | 409 | CAPACITY_EXCEEDED |
| IDEMPOTENCY_CONFLICT | 409 | aynı; farklı payload/same key |
| SCAN_PENDING | 423 | aynı |
| UNSUPPORTED_FORMAT | 415 | aynı |
| JOB_PENDING | 202 | OPERATION_PENDING; outcome=pending |
| RETRYABLE_FAILURE | 503 | outcome=indeterminate, rejected değil |

Alias'lar şu an parser tarafından kabul edilmez; handler mapping henüz bağlanmadı. Kaynak V5 ve geçiş planı adları sessizce karıştırılmaz. `CROSS_COMPANY_REFERENCE` yalnız sahip olduğu üst bağlam doğrulanmış çağrıya verilebilir; foreign ve bulunmayan kaynakların varlığını açıklamak için kullanılamaz. `current_version` yalnız ilgili kaydı görme yetkisi doğrulanmış kullanıcıya döner; erişim reddi yanıtına eklenemez. Bu server authorization kuralları parser'ın yerine getirdiği kontroller değildir.

## Altı durumlu istemci çekirdeği

```text
prepared --submit_same_key--> submitting
submitting/reconciling --transport loss / pending / indeterminate--> reconciling
submitting/reconciling --committed--> committed
submitting/reconciling --rejected--> blocked
her bağlı durum --account_changed--> detached
```

`sameContext` coordinator tarafından **operation ID + oturum nesli/epoch** eşleşmesiyle hesaplanır. Bu boolean ağdan gelen bir yetki alanı değildir. Yanlış bağlam veya detached durumundaki geç yanıt etkisizdir. committed ve blocked terminaldir; geç gelen pending/error sonucu tersine çeviremez. Düzeltilmiş draft/yeni niyet için ayrı state oluşturulur; eski key'in farklı payload ile reuse edilmesi yasaktır. Auth kaybında yeniden giriş/izin çözümü ve işlem sorgulama coordinator sorumluluğudur.

Reducer yalnız phase/effect döndürür; network request yapmaz. `reconcile_same_operation` yeni mutation/key oluşturmak değildir. Süre alanı status sorgulamasının alt sınırıdır, otomatik yazma retry izni değildir. Polling üst süre/deneme sınırı, jitter, cancellation ve foreground/backoff politikası domain coordinator ile uygulanacak. Bilinmeyen/body'siz/proxy/HTML yanıt parse edilemez; caller bunu `transport_loss` gibi belirsiz saymalı, başarılı veya Free/boş durumuna çevirmemelidir. Her 202 işlemin nihai sonucu yetkili operation-status API'sinden çözülmelidir; bu API henüz yok.

## Testler ve kapsam

`fixtures/mutation-outcome.json`:221 yanıt fixture +6×7×2=84 geçiş.19 olumlu yanıtın her birinde yanlış HTTP, her zorunlu alanın eksikliği ve ham detail enjeksiyonu negatifleri; sayı/tip/sınır, array, object coercion, null, current_version sızıntısı ve retryable/rejected karışıklığı kontrolleri. Aynı corpus Deno, saf Swift ve Android JVM'de yürütülür. Deno ek non-JSON NaN/Infinity ve detached-copy testi içerir.

Yerel sonuç: Deno306/306 (önceki context44 ile350); Swift305/305; Kotlin305 yeni test, bütün core:data456/456 (28 sınıf,0 fail/error/skip). Android ana Debug APK build PASS. Function-test map artık6 kaynak; whole-file/hash+harness gate, tam uygulama AST/coverage değil. Foundation111/111, CI YAML parse PASS, uzak CI NOT_RUN. Yeni corpus henüz iOS XCTest veya Android instrumentation hedeflerine eklenmedi; eski43 context native test sonucu yeni305'e kanıt sayılmaz.

Fixture-only değişikliğinde Gradle eski sonucu UP-TO-DATE sayıyordu. Ortak fixture klasörü artık test task input olarak bildirilir; son turda task gerçekten yürütüldü ve305 yeni vaka XML'e yazıldı. Bu bağ ve fixture hash değişimi için foundation regresyon testi eklendi. [Gradle input takibi](https://docs.gradle.org/current/userguide/incremental_build.html).

İlk Deno ek testi fixture ilk sırasına bağlıydı; yeni negatifler eklenince test yanlış örneği seçti. Sabit `committed_ready` ID'siyle seçim yapılarak düzeltildi. Parser incelemesinde array→String coercion olasılığı kaldırıldı ve ilgili4 negatif eklendi. SQL veya canlı veri değişmedi. [Kaynak ve kanıt](../../../docs/isg/evidence/P01_MUTATION_OUTCOME_2026-09-12.json).

Supabase skill'i gereği [Edge error ayrımları](https://supabase.com/docs/guides/functions/error-handling) kontrol edildi; HTTP hata cevabı ile relay/fetch kaybı birbirine eşit kabul edilmedi. Native UI/presentation coordinator entegrasyonu açık.
