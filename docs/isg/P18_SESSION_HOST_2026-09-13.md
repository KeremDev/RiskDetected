# P18 / P02 — oturum kapsamlı native host

13 Eylül 2026. Beş ekran tasarımının ardından yeni NOVA kabuğunun hesap/oturum sahibine bağlanabilmesi için ilk runtime dilimi uygulandı. Tasarım ve mevcut uygulama kimlikleri değiştirilmedi.

## Uygulanan

- Swift `NovaSessionHost.swift` ve Kotlin `NovaSessionHost.kt`: signedOut/resolving/ready/failed, kullanıcı+session kimliği, yerel epoch, tek kullanımlı istek bileti, erişim listesi ile uygulanmış hedeflerin kesişimi.
- Aynı session/token-refresh event'inde gezinme korunur; farklı session/hesap, çıkış ve açık izin yenilemesinde eski path/popup ve scoped değer görünmez olur.
- Geç gelen başarı/hata, tekrar teslim, yanlış owner, A→B→A ve aynı kullanıcıya yeni session ile dönüş korumaları.
- İki ayrı offline QA host'u artık doğrudan serbest navigation state yerine bu owner'ı kullanır. SwiftUI Binding ve Compose callback en güncel host'a, render anında yakalanmış epoch ile uygulanır. Bildirim fixture'ı opaque scoped value'dan okunur.
- iOS UI testine gerçek pencerede resolving sırasında kabuğu gizleme ve hesap B açıldıktan sonra gecikmiş A yanıtını reddetme eklendi.

Kesin kurallar ve akış: [sözleşme](../../contracts/isg/v1/nova-session-host.md). Eski tasarım QA raporunun görsel kabul kapsamı korunur; bu değişiklik yeni görsel tasarım değildir.

## Tekrar çalıştırma

```sh
swiftc App/DesignSystem/ISG/NovaNavigation.swift App/DesignSystem/ISG/NovaSessionHost.swift scripts/isg/NovaSessionHostCorpus.swift scripts/isg/NovaSessionHostCheck.swift -o /tmp/isg-nova-host-check
/tmp/isg-nova-host-check contracts/isg/v1/fixtures/nova-session-host.json
node scripts/isg/run_suite.mjs nova-design
# android/ içinde JDK17 ile:
./gradlew :core:designsystem:testDebugUnitTest :core:designsystem:lintDebug :isg-design-preview:assembleDebug :app:assembleDebug --offline --console=plain
```

## Kapsam sınırı

Bu model gerçek Auth SDK'sı veya yeni backend capability API'si değildir. Mevcut iOS MainTabView/Android MainShell canlı kökleri korunur. Hazır olmayan şirket/uygunsuzluk/eğitim modülleri gerçek kullanıcılara açılmadı. Şirket içi query/request yarışları, domain veri adaptörleri, P02 parola/signup/recovery, presentation öncelikleri ve P18 canlı root/rollout hâlâ açık. Bu dilim P02/P18 veya bütün master planı kapatmaz.

Son test ve build sonuçları [kanıt kaydında](evidence/P18_SESSION_HOST_2026-09-13.json) tutulur. Kaynak/fixture test sayıları bütün domain kabul senaryolarının başarı sayısı değildir. Production Auth/DB/Storage/abonelik/mağaza üzerinde yazma, deploy veya push yoktur.
