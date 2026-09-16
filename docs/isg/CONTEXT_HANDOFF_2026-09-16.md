# İSGADA — 16 Eylül devam bağlamı

Bu not, `01a0a035-df87-78b0-9097-a3fbeda92d0a` numaralı **Projeyi ve sohbeti incele** görevi, güncel kaynaklar, git farkları ve teslim kayıtları okunarak hazırlandı. Bu devralma sırasında ürün kodu/canlı sistem değiştirilmedi; test, derleme veya dağıtım yeniden yapılmadı. Önceki test sonuçları mevcut loglardan ve tarihli teslimlerden ayrıştırıldı.

## Ürün ve sınırlar

- Kullanıcıya görünen isim **İSGADA**. RiskDetected depo/teknik kimlik, Nova ise mevcut iç bileşen adıdır.
- Ürün: iş güvenliği uzmanının firma, işyeri, personel, eğitim, risk, uygunsuzluk, ekipman, belge ve süreç takibi. Fotoğraf analizi mevcut motorla devam eden bir modüldür.
- iOS SwiftUI; Android Kotlin/Compose; Supabase Auth/PostgreSQL/Storage/Edge Functions; mevcut abonelik altyapısı RevenueCat. Bundle `com.riskdetected.app` ve mevcut kullanıcı/ürün kimlikleri korunur.
- Güncel çalışma özel iOS pilotudur. `NovaPilotMainGate`, DEBUG + NOVA_PILOT_BUILD ve pilot sahibi eşleşmesinde yeni kökü açar; diğer derlemeler mevcut `MainTabView` yolunu kullanır. Bu istemci seçimi sunucu yetkisi değildir.
- Pilot aynı Supabase üretim projesinde dar hesap/firma/oturum kontrolleriyle çalışır. Yeni pilot teslimi genel yayına açılmış ürün anlamına gelmez.
- Kullanıcının son kararları eski V5 kapsamının önündedir. Eğitimde sınav/yoklama/toplu çıktı/imzalı arşiv, KKD'de stok/miktar/iade kapsam dışıdır. Tatbikatta öncelik gerçekleşmiş kayıt; Onaylı Defter firma içinde görsel arşivdir. Sağlık takibi ve resmî KATİP otomasyonu kapsamda değildir.

## Çalışma ağacı ve son cihaz durumu

- Dal: `codex/isg-transition-foundation`; HEAD: `989f859e`.
- Devralma başlangıcında 69 takip edilen dosya değişmiş, 70 untracked durum girdisi vardı (dizin girdileri birden fazla dosya içerebilir). Son çalışmaların büyük bölümü henüz commit edilmemiştir; bunlar mevcut kullanıcı/Claude/Codex çalışmasıdır.
- Son görev kaydı: **2.0.3 (116)** pilot iPhone Kerem'e kurulup açıldı. Son işlem uygulama genelinde klavye kapatmadır.
- `/tmp/isgada-keyboard-device-build.log`: BUILD SUCCEEDED; `/tmp/isgada-keyboard-tests.log`: iki XCTest, sıfır hata; `/tmp/isgada-keyboard-device-install.log`: kurulum başarılı. Açılış başarısı önceki görevin son teslim mesajında kayıtlıdır.
- Xcode proje dosyasında temel build numarası hâlâ 91; fiziksel pilot build 116 komut satırı geçersiz kılmasıyla üretilmiş. Sadece pbxproj okuyarak telefondaki sürüm çıkarılmamalı.
- Analiz result-hub erişimi build izin listesine bağlıdır. 117 ve sonrası kendiliğinden açık değildir; yeni buildde uzman görüşü/eğitim önerisi bölümleri için gate tekrar kontrol edilmelidir.

## Son dönemde yapılanlar

1. Firma/işyeri/personel ve firma içinden doğrudan kayıt girişleri; tek işyerini otomatik seçme, personel arayarak atama, sorumlu telefon/e-posta kaydı.
2. Risk sürümleme/taslak düzenleme/iptal; ekipman ve kontrol kaydı, acil plan, İSG-KATİP, atama, KKD zimmeti, kontrol listeleri, çalışma planı, kurul, ziyaret ve diğer süreç bağlantıları.
3. Eğitim tam sayfa akordiyon akışı, konu/personel/eğitici ve süre dağılımı, kişisel belge/PDF. Personel detayında kapsam bazlı öğrenim birikimi ve eksik konu/süre özeti; ayrı ilk yardım/MYK/diğer kişisel sertifika takibi.
4. Gerçekleşmiş tatbikat, tür/haberli-BEKRA alanları, süre/senaryo/not, fotoğraf ve opsiyonel PDF. Takip tarihi ve kullanıcı değişikliği ayrı saklanır.
5. Evrak Takibi modüllerden türeyen birleşik liste oldu. Dosyalarım modül dosyalarını, bağımsız firma ve firmasız kişisel dosyaları içerir; not/etiket/arama ve kaynak kayda dönüş eklendi.
6. Firma içinde Onaylı Defter görselleri; ziyaret süresi/görüşülen kişi/fotoğraf ve istatistikleri; kurulda numaralı gündem ve toplantıyla atomik kararlar.
7. Analiz bulgusundan uygunsuzluk aktarımında sunucuda sahiplik/kaynak doğrulaması, değişmez kaynak snapshot'ı ve tekrar kayıt koruması. Uzman görüşü gibi diğer kaynak türlerini bu bulgu yoluyla otomatik eşdeğer sayma.
8. Çan bildirimi, okunma/silme ve kaynak kayda yönlendirme; firma/istatistik/liste yenilemeleri. Bu uygulama içi feed, yeni P12 push altyapısının tamamlandığı anlamına gelmez.
9. Ortak header, font, beyaz geri düğmesi, liste sayaçları, aramalı kaydırılabilir filtreler, merkez popup ve doğrulanmış kayıt sonrasında başarı mesajları.
10. Son düzeltme: `RDKeyboardDismissBehavior`, pencereye tek gesture recognizer bağlayarak sayfa/popup boş alanında klavyeyi kapatır; metin girişi korunur, buton dokunuşu tüketilmez.

16 Eylül işlev teslimleri için önce `ISGADA_REMAINING_FEATURES_DELIVERY_2026-09-16.md`, sonra `ISGADA_USABILITY_AUDIT_2026-09-16.md` okunmalı. `ISGADA_USABILITY_PILOT_DELIVERY_2026-09-16.md` ilk dilimdir; onun kalan işler listesindeki birçok madde devam tesliminde tamamlanmıştır.

## Devralınan tasarım tercihleri

- Menü + İSGADA + çan + profil header'ı; altında ortak fontla başlık ve beyaz yuvarlatılmış geri düğmesi.
- Çizgi ikonlar, kompakt kartlar, gereksiz tekrar ve teknik açıklamalar yok. Kısa ampul ipucu kullanılabilir.
- Formlar içerik boyutuna uyumlu merkez popup, X kapatma ve taşınca kaydırma. Eğitim gibi uzun adımlı akışlar tam sayfa akordiyon; kamera/dosya/paylaşım sistem sunumları kendi davranışında.
- Son popup kararı: beyaz ana zemin, açık gri iç kartlar. Ortak değerler: material 0.60, dim 0.18, kaynak blur 4 pt. Önceki daha düşük değerler artık geçerli değil.
- Filtreye basınca altında arama + sabit yüksekliği sınırlı kaydırılabilir liste; yazdıkça arama, seçince anında uygulama.
- **Kullanıcı istemedikçe düzeltmelerden sonra ekran görüntüsü üretip açarak görsel kontrol yapma.** Gerekli kod/test/derleme kontrolleri kullanılır.

## Açık veya ayrıca doğrulanacak işler

- Bütün modüller için tek sürümlü süre/kural motoru; mevcut modül kuralları ile aynı şey değildir.
- Sıfır aktif işyerli eski firmaların kontrollü kurtarılması. Son pilot kontrolde böyle firma yok; genel çözüm hâlâ açık.
- Fiziksel cihazda modül bazlı kayıt/düzenleme/silme, gerçek Storage yükle/indir, PDF paylaş/yazdır ve erişilebilirlik kabulü. Kurulum/açılış bu zincirlerin geçtiği anlamına gelmez.
- Kaynakta tekrar görülen somut borç: uygunsuzluk istemcisi `p_after: null` gönderiyor; eski SQL sayfayı 200 satırla sınırlıyor ve cursor yerine yalnız kimliği dışlıyor. Canlı fonksiyon bu devralmada yeniden sorgulanmadı.
- Birçok gate hâlâ `canWrite: ready` kullanıyor; erişilebilirlik ile yazma yetkisinin UI'da ayrımı yeniden ele alınmalı. Bu tek başına sunucuda yetki atlama kanıtı değildir.
- Ana sayfada `openCount`/`activity` hâlâ nil, asistan eylemi `unavailable`.
- Eski gap raporundaki tarih doğrulamaları, çıktılardaki kaynak ilişkileri, marka kalıntıları gibi maddeler güncel kaynak/servis bazında yeniden doğrulanmalı; raporun bütün maddeleri açık kabul edilmemeli.
- Master düzeyinde Android tam parite, yeni bildirim worker'ları, genel kural/skor altyapısı, import/rapor merkezi, yeni billing/kampanya/admin, hesap silme/retention/restore ve mağaza kabulü kapanmış değildir. P00–P21 planının tamamen bittiği iddia edilmez.

## Kod haritası ve çalışma disiplini

- Başlangıç/oturum: `App/RiskDetectedApp.swift`, `App/RootView.swift`, `App/Views/Components/NovaPilotMainGate.swift`.
- Ortak UI: `App/DesignSystem/ISG/NovaStyleConsistency.swift`, `NovaComponents.swift`, `NovaPopup.swift`, `NovaPopupFormComponents.swift`, `NovaListComponents.swift`, `NovaSuccessPresentation.swift`.
- Modül bağlantıları: `App/Views/Components/NovaPilot*Gate.swift`; firma ekranı `NovaCompanyManagementGate.swift`.
- Servisler: `App/Services/Company/`; kalıcı tekrar gönderim `NovaModuleMutationJournal.swift`. Mutasyon yanıtı çözülüp oturum doğrulanmadan pending receipt silinmemeli veya başarı gösterilmemeli.
- Sözleşmeler: `contracts/isg/v1/`; sunucu adayları `supabase/migrations/` ve `supabase/pilot-release/candidates/`; uygulanmış SQL aynaları `supabase/pilot-release/supabase/migrations/`.
- **Kökten genel `supabase db push` çalıştırma.** Adaylar ile canlıya dar paketlenmiş migration zinciri farklıdır; önce ledger ve exact SQL karşılaştırılır. Pilot-release README'sindeki iki migration sayısı tarihsel olup güncel toplam değildir.
- Testler: `scripts/isg/`, `scripts/modules/run_pilot.mjs`, `scripts/education/`, `RiskDetectedUITests/`. Önceki 56/48 kontrol sayıları ayrı teslim turlarına aittir; toplam uçtan uca kapsam gibi sunulmaz.
- Eski `PROJECT_HANDOFF.md` Mayıs tarihli, `EXECUTION_STATUS.md` çok sayıda tarihsel ek içeriyor. Son kullanıcı kararları → güncel kod → 16 Eylül teslimleri → eski faz belgeleri sırası esas alınmalı.
