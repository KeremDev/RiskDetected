# NOVA özel iPhone build’i — 13 Eylül 2026

> **Sonraki adım tamamlandı:** Kullanıcının ayrı onayıyla [canlı P05 pilotu açıldı](P05_LIVE_ACTIVATION_2026-09-13.md). Aşağıdaki backend kapalı/onay bekliyor ifadeleri telefon build’inin teslim anını anlatır. Mevcut build yenilenmeden yeni erişimi foreground/tekrar kontrol ile alabilir.

## Sonuç

**RiskDetected 2.0.3 (91), Debug / özel NOVA pilot build’i**, bağlı **iPhone Kerem (iPhone 17 Pro Max)** cihazına mevcut bundle ID (`com.riskdetected.app`) ile güncelleme olarak kuruldu ve açıldı. Uygulama kaldırılmadı. Cihaz kurulum ve process launch komutları başarıyla tamamlandı; telefonda kullanıcının giriş yapması ve yeni ekranı görmesi ayrıca kullanıcı tarafından doğrulanacak.

**Canlı backend deploy, SQL/allowlist/flag değişikliği yapılmadı.** Son canlı incelemede P05 şeması/RPC’leri bulunmuyordu. Yeni UI görülebilir; gerçek firma/personel işlemleri pilot sunucusu kurulup hesabın erişimi açılana kadar kullanılamaz. Bu build canlı uçtan uca kabul veya yayın onayı değildir.

## Bağlanan akış

- Normal onboarding, giriş, hukuk/onay, offline ve minimum sürüm kapıları korundu. `RootView` ana akışında yalnız özel `DEBUG && NOVA_PILOT_BUILD` derlemesi ve build’e verilen Auth UUID eşleşmesi yeni NOVA root’unu seçer. Normal Debug/Release veya başka hesap eski `MainTabView` kullanır. E-posta/metadata yetki kaynağı değildir; gerçek UUID kaynak koda eklenmedi, yalnız yerel build ayarına verildi.
- Yeni NOVA ana ekranı, alt menü, çekmece, profil ve firma geçişi bağlandı. Bağlı olmayan özetlerde sahte sayılar yerine `—` ve açık durum mesajları kullanılır. Diğer modüller kapalıdır; fotoğraf/AI gibi henüz bağlanmamış düğmeler işlem yapmak yerine açıklama gösterir.
- Hesap veya Auth session değişince root kimliği değişir, görüntülenen liste/form/navigasyon sıfırlanır. Foreground’da izin tekrar kontrol edilir. Yerel tasarım seçimi sunucu yazma yetkisi vermez.
- Pilot firma listesi mevcut owned-list servisini **yalnız okuma** için kullanır; her adayın sunucu availability/origin/grant kontrolü yapılmadan hiçbir firma yayınlanmaz. Kısmi hata tüm listeyi kapatır; istek öncesi/sonrası session doğrulanır. Eski firma edit/archive/logo/analiz/ödeme ekranına kaçış yoktur.
- Yeni firma formu **firma adı + tehlike sınıfı** alır ve yalnız `isg_pilot_company_create_v1` çağırır. Liste/form için firma isimleri önceden istenmez. Sunucu yazma izni/abonelik/kota kararını yeniden verir; istemci capability’si tek başına izin değildir.
- Create isteği ağdan **önce**, cihazda kalan Keychain servisine (`com.riskdetected.pilot.company.pending.v1`) owner+mutation+payload olarak kaydedilir. Timeout, belirsiz cevap, decode/scope hatası veya oturum değişimi bu kaydı silmez. Yeni bir intent başlatılmaz; aynı sahibi yeniden giriş yaptıktan sonra aynı mutation ile açıkça tekrar dener. Başka hesap bu intent’i göremez. Başarılı ve doğrulanmış receipt kaydı temizler. Token/şifre/analytics’e payload yazılmaz.
- Pilot şirket seçilince mevcut gerçek P05 personel/işyeri/bölüm/görev/taşeron ekranları scoped client’larla açılır. Canlı RPC erişimi olmadan gösterilmez.
- Sentetik tasarım seçeneği yalnız Debug + özel flag + **simülatör** ile derlenir; telefonda fixture hesabıyla oturum atlama yolu yoktur.

## Doğrulama ve bulunan düzeltmeler

- Native servis: **23 kontrol PASS** — payload doğrulama, journal-before-network, aynı mutation retry, yeniden açılış, başka owner, yeni session, geç cevap, bozuk/büyük/başka owner receipt, disk yazma hatası ve başarıda temizleme.
- İlgili native/NOVA test grubu: **22 Node testi PASS** (23 Swift kontrolünü çalıştıran test dahil; sayılar toplanmaz). Log: `output/isg/pilot/native-tests.log`.
- Gerçek ana target’ta **2 XCUI testi PASS, 0 skipped**: pilot tasarım + açıklama + erişim yokken firma akışının kapanması + profil; pilot dışı hesapta legacy root. Sentetik UI fixture kullanıldı, canlı kullanıcıyla create testi yapılmadı.
- XCUI sonucu: `/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/result-bundles/test_sim_2026-09-13T20-01-36-304Z_pid84322_38727104.xcresult`.
- Simülatör build/run ve fiziksel cihaz imzalı Debug build PASS. `codesign --verify --deep --strict` PASS; provisioning profile bağlı cihazı içeriyor.
- İlk derlemede CLI ile bütün Swift koşullarını değiştirmek bağımlılık modüllerini düşürdü; `$(inherited)` korunarak tam Xcode build’iyle düzeltildi. Formdaki catch değişkeni gölgelemesi düzeltildi.
- XCUI, root’a verilen erişilebilirlik kimliğinin alt menü kimliklerini ezdiğini yakaladı; bağımsız görünmez QA işaretine taşındı. Testin 128 karakterlik identifier sınırına takılan uzun metin sorgusu predicate’e çevrildi. Son iki test yeniden geçti.
- Eski `PaywallDesignKit.swift:631–641` içindeki 11 actor-isolation uyarısı devam ediyor; bu tur değiştirilmedi. Release build/App Store/TestFlight yayını yapılmadı.

## Yerel cihaz kanıtları

- Son build: `output/isg/pilot/DeviceBuildFinal.xcresult`, `device-build-final.log`.
- İmzalı app: `output/isg/pilot/DeviceDerivedData/Build/Products/Debug-iphoneos/RiskDetected.app`.
- Kurulum/başlatma: `output/isg/pilot/device-install.json`, `device-launch.json` — ikisi de success.
- Executable SHA256: `f9959ee03a436b585a93bf5541daa675cafb1f7eeb3b61f6b5b93962be7e3e48`.
- Debug uygulama kodu dylib SHA256: `05f1f964e244c192a65af6a1ec3cf4e22075ef29f11a80f4a5f14907790c23af`.
- Kurulum development imzalıdır; App Store güncellemesi bu build’i değiştirebilir. Geri dönüş uygulamayı silerek değil, uygun imzalı eski build/App Store güncellemesiyle ayrıca planlanmalı; yerel verilerin korunacağı kontrol edilmeden kaldırma yapılmamalı.

## Kalan işler / canlıya geçiş sırası

1. Kullanıcı telefonda normal hesabıyla giriş yapıp NOVA tasarımını doğrular; UI denemeleri ve değişiklikleri devam eder.
2. **Ayrı canlı uygulama onayı**, güncel deploy checkpoint’i, altı kaynaklı dar paketin migration ledger/geri dönüş stratejisi ve pilot başlangıç/bitiş penceresi. Genel `supabase db push` çalıştırma; önceki hazırlık belgesindeki global backfill/hook sınırları korunacak.
3. Onaylı ve doğrulanmış kapalı kurulumdan sonra yalnız seçilen hesabın read/write açılışı; mevcut firmaları otomatik enroll etme. Hesap firmalarını uygulama içinden oluşturacak.
4. Canlı gateway üzerinden normal login → create → liste → personel/işyeri → yeniden giriş/retry/iptal testleri. Pilot/legacy writer eşzamanlı firma kotası yarışı ve fault testleri hâlâ açık.
5. Pilot liste adaptörü şu an her firma için bir availability çağrısı yapar ve mevcut legacy liste RLS’sine bağımlıdır. Çok sayıda arşiv/abonelik düşüşü için dedicated pilot-list RPC ve pagination tamamlanmadan genel dağıtım yapılmayacak.
6. Forma ek alanlar, firma düzenleme/arşivleme ürün sözleşmesi; yeni pilot-only metinlerin EN kataloğu, formun fiziksel cihaz klavye/erişilebilirlik kabulü; diğer faz modüllerinin gerçek UI/servis bağlantıları açık.

Önceki backend kanıtları bu tur yeniden koşturulmadı; SQL adayları değiştirilmedi. 1096 sentetik/33 full upgrade/27 P05-only sonuçları önceki backend checkpoint’ine aittir. `release_ready=false`; bu UI teslimi P19 kabul defterinde yeni covered senaryo iddiası oluşturmaz.
