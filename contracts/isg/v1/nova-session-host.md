# NOVA oturum sahibi — yerel sunum sözleşmesi v1

P02/P18 entegrasyon önkoşulu, 13 Eylül 2026. Bu bir HTTP/JWT veya yeni yetkilendirme sözleşmesi değildir. Auth SDK, sunucu capability yanıtı ve gerçek domain adaptörleri henüz bu modele bağlanmamıştır.

## Tek otorite

`NovaSessionHost` gezinme, kullanılabilir hedeflerin sunum listesi, geçerli yerel epoch ve tek bekleyen erişim isteğinin sahibidir. Swift value state UI sahibinde/MainActor üzerinde, Kotlin immutable state ana UI thread'inde seri uygulanır. İşlem sonucunu her zaman **en güncel host** üzerinde uygula. Eski host kopyasından üretilen state'i geri atama.

`NovaSessionIdentity(userID, sessionID)` yalnız mevcut Auth sahibinin doğrulanmış oturum gözleminden gelir. user_metadata, deep link, bildirim payload'ı, kullanıcı tercihi veya tier etiketi kimlik/yetki kaynağı değildir. UUID'ler token değildir ancak log/telemetry'ye yazılmaz. Bu yapı JWT doğrulamaz veya oturum iptalini sunucuda denetlemez. Hassas servis çağrıları mevcut server session/RLS/RPC kontrollerinden geçmelidir.

Auth sahibi oturum olaylarını sıralı işler ve SDK'nın **güncel** oturumunu kontrol eder. Gecikmiş bir ağ yanıtı `adopt` çağıramaz. SDK adaptörü bağlanmadan bu gerekliliğin sağlandığı iddia edilmez. Same-user parola ekleme/token yenilenmesi gerçek sessionID'yi koruyorsa no-op; çıkıştan sonra aynı UUID ile yeni oturum açmak yeni kapsamdır.

## Durum makinesi

```text
signedOut ── adopt(session) ──► resolving
  ▲                               │ beginAvailabilityRefresh → yeni epoch + ticket
  │                               ├─ güncel ticket / doğru owner → ready
  │                               └─ güncel failure / yanlış owner → failed
  │                                                               │
  └──── adopt(nil) ◄── her durum       retry / refresh ◄────────────┘

ready ── açık revalidation ──► resolving (eski ekranlar ve scope gizli)
her durum ── farklı user veya session ──► resolving (tam kapsam reset)
aynı user + session gözlemi ──► no-op (path ve bekleyen ticket korunur)
```

- Epoch yerelde rastgele UUID olarak üretilir; kullanıcı/session ID epoch yerine kullanılmaz. A→B→A veya logout→aynı session dönüşü eski epoch'u geri kullanmaz.
- `adopt(nil)` signed-out başlangıçta tekrarlanırsa no-op. Signed-out durumda istek başlatma/menü gezinmesi/payload yayınlama kabul edilmez.
- `beginAvailabilityRefresh` önceki isteği, path'leri, popup'ı ve eski scoped değerleri geçersiz kılar. Yeni istek bileti hazırdır; hazır UI gösterilmez.
- Sadece güncel phase+ticket+epoch+identity dörtlüsü eşleşen sonuç işlenir. Swift opaque UUID bileti, Kotlin opaque nesne kimliği kullanır. Bilet tek kullanımlıktır; başarıdan sonra hata veya aynı bileti yeniden oynatma no-op.
- Yanıt yanlış owner'a aitse güncel istek failed olur ve tüketilir; daha sonra aynı biletle başarı kabul edilmez. Retry yeni bilet gerektirir. Başka hesabın varlığına ilişkin özel hata metni oluşturulmaz.
- Kullanılabilir hedefler `server/host enabled ∩ locally implemented` kesişimidir. `home/profile` mevcut gezinme sözleşmesinin zorunlu sunum kökleridir; gerçek host bu kökler için de güvenli içerik sağlamalıdır. Alt hedefin açık olması bağlı sekme kökü kapalıysa yeterli değildir.
- `ready` dışındaki durumlarda **kabuğu mount etme**; eski `home/profile` kökleri hâlâ veri gösteriyor sanılmamalı. Test host'ları açık QA durum etiketi gösterir; bu üretim loading/error tasarımı değildir.
- Açık yeniden doğrulama yerel child state'i sıfırlar. Kalıcı taslaklar silinmez; gerçek domain/offline taslak saklama ve geri yükleme sözleşmesi ayrı entegrasyon işidir.

## UI ve veri sınırı

SwiftUI Binding getter en güncel `sessionHost.navigation` değerini okur. Setter render anındaki epoch ile `acceptNavigation` çağırır; başka epoch veya farklı availability taşıyan snapshot reddedilir. Child callback'ler de render epoch'unu yakalar; çağrıldığı andaki yeni epoch'u sonradan okuyarak eski işlemi “güncel” göstermemelidir. Compose `host = host.apply(event, capturedEpoch)` kullanır, yakalanmış eski host üzerinden hesaplama yapmaz.

`scope(value, from: capturedEpoch)` yalnız ready/güncel durumda opaque `NovaScopedValue` üretir. `value(snapshot)` her render'da **güncel host** üzerinden okunur; hesap değişimi/refresh/logout sonrası nil döner. Örnek bildirim listeleri her iki QA host'unda bu yolla okunur. Etiket, dashboard ve şirket ekranı için gerçek yükleyiciler de aynı sınırı kullanmalıdır.

Bu helper tek epoch içindeki şirket A/B, arama sorgusu veya ardışık sayfalama yanıtlarının sırasını denetlemez. Her feature ayrıca typed company/entity scope ve kendi latest-request ID kontrolünü sağlamalıdır. Bu yüzden bu dilim “tüm eski hesap/veri sızıntıları çözüldü” veya “gerçek domain hazır” olarak raporlanamaz.

## Test korpusu

`fixtures/nova-session-host.json`: 88 senaryo / 399 adım. 17 hedef × açık / yerelde uygulanmamış / kapalı / stale = 68; kalan 20 yaşam döngüsü senaryosu. Her adım phase, current, overlay, available, pending, görünür scoped value ve epoch değişimini açık oracle olarak taşır. Swift veya Kotlin reducer çıktısından oracle üretilmez.

Swift `NovaSessionHostCorpus.swift`, Kotlin `NovaSessionHostTest.kt` aynı JSON'u çalıştırır. Gradle input tracking ve CI Swift koşusu vardır. Node testleri hedef/yaşam döngüsü kapsamını ve kaynak izolasyonunu denetler; bu metinsel kontroller native testlerin yerine geçmez.

## Canlı köke geçmeden kalanlar

1. Gerçek Auth gözlemcisine SDK current-session doğrulaması ve sıralı lifecycle adaptörü.
2. Mevcut paid/server erişim kurallarından yetkili, owner kapsamlı feature availability servisi; profile tier'dan grant üretme yok.
3. Şirket/entity ID taşıyan typed route ve her feature'ın query/request/result state'i; hesap/şirket değişimi ve offline taslak testleri.
4. Tek presentation coordinator ile legal/update/auth/paywall/bildirim önceliği.
5. Hazır handler'lara dayalı kontrollü root seçimi; legacy fallback ve kaldırmadan update testleri. Bu dilimde canlı root veya rollout flag açılmaz.
