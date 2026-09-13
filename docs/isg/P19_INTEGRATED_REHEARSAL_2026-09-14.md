# P19 — kabul defteri ve bütünleşik kill switch provası

14 Eylül 2026 · dal `codex/isg-transition-foundation`

P19'un kapısı şu: **203 kaynak + 60 geçiş kabulünün tam eşlemesi ve koşumu, açık kritik hata olmaması.** Bu dilim o kapının kendisini kuruyor — ve kapının bugün ne dediğini açıkça yazıyor.

## 1. Kabul defteri: 263 senaryonun gerçek durumu

`scripts/isg/acceptance_ledger.mjs` üç kaynağı birleştirir:

- `build_test_manifest.mjs`'in envanteri — 203 kaynak + 60 geçiş senaryosu
- `V5_ACCEPTANCE_TEST_REGISTRY.csv` — her satırın gerektirdiği katmanlar
- `docs/isg/acceptance/layer-evidence.json` — her katmanın **bugün ne gösterebildiği**

Bir senaryo ancak **gerektirdiği her katman `full` ise ve bir kanıt dosyası onu adıyla talep ediyorsa** `covered` sayılır. Talep, kanıt dosyalarının kendi `acceptance_ids_covered` alanlarından okunur; yani artefakt olmadan talep olamaz.

| Durum | Sayı | Anlamı |
|---|---|---|
| covered | **0** | Uçtan uca kanıtlanmış senaryo yok |
| partial | 20 | Bir faz talep etti ama gereken bir katman henüz `full` değil |
| blocked | 166 | Gereken bir katman **hiçbir şey** üretmemiş |
| unclaimed | 77 | Katmanların kanıtı var ama hiçbir faz bu senaryoyu adlandırılmış bir kontrole bağlamamış |

`release_ready: false`. Hiçbir yuvarlama yok: 263'ün 263'ü `covered` olmadan kapı açılmaz.

### Hiçbir şey üretmemiş altı katman

`ADMIN`, `COMPATIBILITY`, `CROSS_LAYER_ACCEPTANCE`, `DELETION`, `OPERATIONS`, `STORE_QA`. Bunlar 166 senaryoyu tek başına kilitliyor. Her biri `layer-evidence.json` içinde neyin eksik olduğunu yazıyor; "kod var" bir katmanı asla `full` yapmaz.

### 26 katmanın dağılımı

6 `full` (DB, DOMAIN, SECURITY, API, CONCURRENCY, FAULT_INJECTION), 14 `partial`, 6 `none`.

## 2. Bütünleşik prova: tam kill switch altında legacy ayakta mı?

`scripts/isg/integrated_rehearsal_probe.mjs` sentetik koşuda **bütün faz probe'larından sonra** çalışır ve tek bir soruyu cevaplar: her yeni özellik kapatıldığında eski ürün çalışmaya devam ediyor mu?

| Kontrol | Ne kanıtlıyor |
|---|---|
| 16 kapı + 17 rollout satırı | Her yeni özellik kapalıyken `FEATURE_UNAVAILABLE` veriyor |
| Faz anahtarı vs modül anahtarı | Modül anahtarı **açık** kalsa bile faz anahtarı reddediyor; ikisi bağımsız |
| `private.user_plan_tier` / `company_limit_for_user` | Eski plan otoritesi hâlâ doğru cevap veriyor |
| Eski firma kuralı | Limiti dolmuş Free hesabın yeni firma yazması hâlâ reddediliyor |
| Legacy parmak izi | `companies` + `profiles` + `user_subscriptions` satırları ve `private` şemasındaki **bütün** fonksiyon gövdeleri, P01–P17'nin tamamı koştuktan **sonra** değişmemiş |
| Şema duruşu | 154 tablo, RLS'siz 0, istemci GRANT'i 0, `search_path` set etmeyen fonksiyon 0, açık rollout 0 |
| SECURITY DEFINER | Tam olarak 15 bilinen istemci RPC sınırı; hiçbiri `_gate` değil |
| Tek anahtar açmak | Bir özelliği açmak **yalnız** onu açıyor; kapatmak anında etkili |

Bu, X58'in (chaos: kill switch / eski DB + yeni binary) **sunucu tarafını** karşılıyor. Cihaz ve binary tarafı açık.

## 3. Test kanıtı

| Koşu | Sonuç |
|---|---|
| `run_auth_restore.mjs --synthetic-session` | **1007 PASS** (1006 tekil; 10'u yeni prova kontrolü), cleanup PASS |
| `run_auth_restore.mjs --isolated-copy --p05-upgrade` | **32 PASS**, cleanup PASS |
| `run_suite.mjs foundation` | **424 PASS** (önce 412; +12 defter ve prova guard'ı) |
| `acceptance_ledger.mjs` | 263 senaryo, `release_ready=false`, tutarsızlık 0 |

## 4. Bu dilimde çıkan hatalar ve düzeltmeleri

| Belirti | Kök neden | Düzeltme |
|---|---|---|
| Defter 262 senaryo sayıyordu, 263 değil | **`DEL-01` planın iki ayrı bölümünde geçiyor**; kısa kimliğe indirgemek gerçek bir kabul satırını yutuyordu | Her senaryo tam manifest kimliğiyle anahtarlanıyor; registry eşlemesi bölüm + test kimliği ile yapılıyor |
| Prova SQL'i `AUTH_RESTORE_SQL_FAILED` veriyordu | `module_gate(p_module text, p_write boolean)` iki parametre alıyor; tek parametreyle çağrı 42883 üretiyor ve dispatcher yalnız P0001 yakalıyordu | Modül dalı gerçek bir modül anahtarı geçiyor; dispatcher artık diğer SQLSTATE'leri de rapor ediyor |
| `no_new_function_runs_as_a_definer` kırmızıydı | `private_isg` içinde 15 SECURITY DEFINER fonksiyon var — hepsi P05/P12/P13'ün **kasıtlı** istemci RPC sınırı | İddia düzeltildi: tam olarak bu 15 isim beklenir ve hiçbiri `_gate` olamaz |
| `every_module_switch_is_closed_too` kırmızıydı | Faz anahtarını kapatmak modül anahtarlarını kapatmıyor | Bu bağımsızlık **test edilmeye değer** bir özellik: önce faz anahtarının modül açıkken bile reddettiği, sonra ikisinin de kapandığı kanıtlanıyor |

Üretim davranışını etkileyen defect çıkmadı. Prova, hata ayıklama için her SQL adımını adlandırıyor; bir sonraki başarısızlık hangi adımda olduğunu söyleyecek.

## 5. Yeniden çalıştırma

~~~bash
node scripts/isg/acceptance_ledger.mjs            # defteri doğrula ve özeti yazdır
node scripts/isg/acceptance_ledger.mjs --write    # registry ve coverage-report.json güncelle
node scripts/isg/run_suite.mjs foundation
node scripts/isg/run_auth_restore.mjs --synthetic-session
~~~

## 6. Açık kalanlar — P19 kapanmadı

Kapıyı kapalı tutan işler, defterin kendi çıktısıyla aynı:

1. **CROSS_LAYER_ACCEPTANCE** — hiçbir senaryo gerçek istemciden sunucuya, oradan görünür bir kullanıcı sonucuna tek koşuda yürütülmedi. 48 `V5` satırı yalnız bunu bekliyor.
2. **STORE_QA** — iki mağazada tek bir satın alma, teklif imzası veya offer token denenmedi. 67 senaryo buna bağlı.
3. **COMPATIBILITY (X03)** — 16 eski binary × yeni backend kombinasyonu hiç koşulmadı.
4. **DELETION (X56)** — yeni domain'ler genelinde hesap silme tasarlanmadı bile.
5. **OPERATIONS / ADMIN** — destek zincirinin istemci üreticisi ve panel yüzeyi yok.
6. **X57 restore drill** — P00'da bir restore provası var ama RPO/RTO ölçülmedi; bu dilimde tekrarlanmadı.
7. **Güvenlik ve yük koşusu** yapılmadı.
8. **77 `unclaimed` senaryo** — katmanları hazır; her birini adlandırılmış bir kontrole bağlamak mekanik ama yapılmadı iş.

Bu defterin değeri "ne kadar bittiğini" göstermesi değil, **bitmemiş olanı saklayamaz hâle getirmesidir**. `release_ready` yalnız 263/263 `covered` olduğunda `true` olur ve guard testi bunu her koşuda doğrular.
