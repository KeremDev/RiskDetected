# P18 — OSGBTakip iOS uzman paneli tasarım referansı

12 Eylül 2026. Kullanıcı yeni tasarım kaynağı olarak **OSGBTakip iOS uzman panelinin aynısını** seçti. Kaynağa erişildi; Figma zorunlu değil. Bu karar tasarım yönünü belirler, tüm yeni domain ekranlarının piksel kabulü veya OSGB iş kurallarını taşıma izni değildir.

## Kaynak ve sabitleme

Devam kaydı: [Native tasarım katmanı ve test kapsamı](P18_NATIVE_DESIGN_FOUNDATION.md). Aşağıdaki envanter ilk capture anını anlatır; font ve ilk bileşen aktarımı artık ayrı native dilimde mevcuttur.

- Kök: `/Users/keremkayalar/Documents/Kerem-APPler/OSGBTakip/apps/mobile`.
- Git HEAD: `ccb8aa733d6ba744f669e54b5338dcd343635ed8`; **çalışma ağacı dirty**. Özellikle MobileShell/NewFindingScreen gibi ilgili dosyalarda commit dışı değişiklik var. Referans yalnız HEAD değil, mevcut dosya içerikleridir.
- [Kaynak ve token manifesti](../../contracts/isg/v1/design/osgb-nova-reference.json): 113 theme/component/screen/router dosyasının SHA256 ve boyutu;12 literal token grubu. Tokenlar TypeScript AST literal okumasıyla çıkarıldı; kaynak uygulama/React Native kodu çalıştırılmadı. Manifestte tüm rol renkleri envanter amaçlı bulunur; uygulanacak rol **expert**.
- Kaynak proje değiştirilmedi, commit/push/build/login yapılmadı. Ortam dosyaları, müşteri verisi, oturum veya API anahtarları kopyalanmadı.
- 113 UI dosyasının mevcut içeriği `backups/isg-osgb-design-20260912-PNKQxM/osgb-mobile-design-source.tar.gz` içinde ayrıca sabitlendi:221.443byte, her dosya hash'i doğrulandı, kaynak değişmedi. [Arşiv kanıtı](evidence/P18_OSGB_DESIGN_CAPTURE_2026-09-12.json). Bu yerel/şifresiz yalnız UI kaynak arşividir;113 dosya dışındaki HTML/font/backend/DB veya tam OSGB yedeği değildir. Dizin700/arşiv600.
- Orijinal HTML referanslar: `/Users/keremkayalar/Downloads/İphone Uygunsuzluk Yönetimi Tasarımı/` (filesystem Unicode normalizasyonu nedeniyle isim terminalde birleşik karakterli görünebilir). Uygunsuzluklar, Uygunsuzluk Ekle, Uygunsuzluk Detay, Uygunsuzluk Takip ve Evrak Takibi `.dc.html` dosyaları bulundu. Bu dosyalardaki script/örnek veri iş kuralı otoritesi değildir; henüz çalıştırılmadı.

## Teknoloji ayrımı

Referans mobil uygulama Expo `~57.0.21`, React Native `0.86.3`, React `19.2.3`, Expo Router kullanır (yerel package.json gözlemi). RiskDetected'ın SwiftUI ve Kotlin/Compose omurgası korunur. TSX doğrudan Swift dosyasına kopyalanamaz; aynı token, ölçü, görsel hiyerarşi ve etkileşimler iki native bileşen kütüphanesine taşınacaktır. OSGB tenant/role switch, atama yetkisi, firma/sorumlu girişleri, endpoint'ler ve entitlement modeli taşınmayacak. İSG V5'in yalnız uzman hesabı ve owner/capability kuralları geçerlidir.

## Görsel omurga

| Parça | Kaynak değeri / davranış |
|---|---|
| Uzman aksanı | Açık/koyu `#2ed256`; koyu okunur ink `#0f7a34`; soft `#eafbef` / `#153a24` |
| Açık yüzey | Zemin `#f0f0f0`, sheet `#f7f7f8`, kart `#ffffff`, metin `#111111` |
| Koyu yüzey | Zemin `#111114`, sheet `#17171b`, kart `#1c1c21`, metin `#f5f5f7` |
| Font | Plus Jakarta Sans400/500/600/700/800, ayrı font dosyaları; SIL OFL1.1 lisansı mevcut |
| Başlık | 22pt/800, tracking−0.5, line height28; sheet19/800/25; marka18/800/23 |
| Kart/gövde | Kart başlığı14/700/17.5; gövde13/500/18; buton15/700/20 |
| Köşeler | Kart22, alan16, kontrol14, popover26, dialog28, sheet32, tab bar34, pill999 |
| Boşluk | Yatay ekran20; ölçek4/7/10/14/18/24 |
| Alt çubuk | Yükseklik66, yatay inset14; bottom=`max(safeBottom,10)+26−10`; scroll alt boşluk122 |
| Sekmeler | Ana Sayfa → Uygunsuzluk → ortada Ekle → Firmalar → Profil |
| Ekle davranışı | Doğrudan tek forma atlamaz; hızlı eylem popup'ını açar |
| Cam çubuk | Blur intensity38, tema tint + yarı saydam dolgu; iOS/Android uygulanması farklı |
| Popup | Merkezde, genişlik%92/max520, ekran safe-area'ya göre max yükseklik; köşe28, klavyeye uyum |
| Animasyon | Sheet280ms, drawer300ms, fade160ms; sheet/drawer cubic-bezier(0.32,0.72,0,1) |
| Durum tonları | Başarı/uyarı/tehlike/bilgi/nötr için ayrı bg/ink/dot; manifestte light/dark tüm değerler |

Nova theme'deki402×874 ölçüsü tasarım referansıdır; gerçek cihaz sabit ölçüye zorlanmayacak. Kaynak eğitim görüntüsü1320×2868px, normalize440×956pt; farklı cihazlar için safe area, metin sarması ve Dynamic Type ayrıca test edilir. Mevcut tenant rengi override özelliği İSG'ye otomatik taşınmaz. Kaynaktaki kontrast/erişilebilirlik sorunlarının bulunması halinde görsel eşitlik ve erişilebilirlik farkı açık kaydedilir; sessiz tasarım değişikliği yapılmaz.

## Ekran ve modül eşlemesi

| Kaynak ekranlar | Yeni plana bağlantı | Korunacak görsel örüntü |
|---|---|---|
| HomeScreen | P17/P18 ana sayfa | Üst marka/menü/bildirim/avatar, selamlama, özet, fotoğrafla ekle, son kayıtlar, onay bölümü, firma kartları, canlı akış |
| ExpertCompanies / ExpertCompanyDetail | P05 firma | Avatar/degrade, arama, firma kartı, firma çalışma alanı; yeni işyeri/departman/personel aynı dilde |
| ActionList / ActionDetail / NewFinding / Annotation | P09; P08 AI bağlantısı ayrı | Durum chip'leri, fotoğraflı kayıt, detay/aksiyon/onay, kamera/galeri, çizim araçları |
| TrainingHub / Overview / Screen / Personnel / SessionEditor / Settings | P07 | Firma seçici, özet kartları, eğitim/personel eylemleri, filtreler, form popup'ı |
| DocumentChecklist / DocumentCenter / CompanyDocuments | P04/P06/P11 | Arama, durum/süre rozeti, dosya listesi, seçim ve export; güvenli file pipeline V5'e göre |
| ExpertReports / ExpertReportArchive | P11 | Rapor ayarları, format seçimi, arşiv; eski AI reports ayrı adapter ile |
| VisitList | P10 | Firma seçimi, kayıt listesi, tarih/form ve kayıt sonrası durum |
| ExpertBusinessMemory | P16/P17 uygun kısım | Firma filtresi ve zaman çizgisi; hassas içerik/audit yetkisi yeni backend'de |
| ExpertStatistics | P17 | Özet/kart/grafik dili; kaynak puan ve hesap formülü kopyalanmaz |
| OperationalNotifications / MobileShell popover | P12 | Okunmamış rozet, liste, tümünü oku/sil görseli; consent/delivery V5'e göre |
| shared/profile | P02/P18 | Header, avatar, hesap alanları, tema ve bildirim ayarı; çoklu rol seçimi yok |
| Login / KVKK | P02 | NOVA form/kart/renk ailesi; RiskDetected Auth UUID/callback/provider sürekliliği korunur |

Kaynak uzman menüsü13 eylem içerir (Eğitim ve Takip modül koşullu). Referansta olmayan kişisel notlar, referral/winback/paywall, yeni İSG alt modülleri ve revizyon akışları için aynı tasarım sistemiyle detay yerleşim üretilip kabul edilecek; referansta bu ekranlar varmış gibi sayılmayacak.

## Bileşen envanteri

`primitives.tsx`: NovaText, Card, Pill, Overline, Chip, Avatar, IconButton, Button, Checkbox, SearchField, Field, TextField, Divider, EmptyCard, StatStrip, ListRow.

`shell.tsx`: NovaTopBar, NovaHeading, NovaPillButton, NovaTabBar, NovaScrollBody, NovaRefreshControl, NovaScreen, NovaSegmented, NovaChipRow.

`overlays.tsx`: Popup, ActionPopup, Sheet, ConfirmDialog, Toast, Drawer, Popover, NoticeCard. `fields.tsx`: SelectField/FormSection. `loading.tsx`: NovaLoader/LoadingCard. Icon.tsx vektör path'leri ve PhotoBackdrop ayrıca referans. Mevcut font dosyaları kaynak node_modules altında bulunuyor; native resource kopyası/lisans ekleme henüz yapılmadı.

## Görsel kanıt ve kalan kabul

`Downloads/IMG_1389.PNG` yerel dosyası açılıp görüldü: eğitim işlemleri, firma seçimi,6 özet kartı, yeşil eğitim ekle, beyaz ikincil eylemler, segmented liste ve floating tab bar. Bu eski referans görüntüsüdür; yeni uygulama ekran görüntüsü değildir. Aynı konumda IMG1390/1391 bulundu, bu tur açılmadı. Eski QA belgesindeki IMG1382 ve IMG1384 yolları yok. Müşteri/personel verisi bulunabilecek screenshot'lar Git'e kopyalanmadı.

113 dosya hash envanteri **113 ekranın incelendiği veya tüm etkileşimlerin çalıştırıldığı** anlamına gelmez. Tam görsel port kabulü henüz yapılmadı. Kaynak QA belgesinin bazı alanları runtime screenshot eksikliği bildirir; bu eski PASS/FAIL kayıtları yeni portun sonucu sayılmaz.

Uygulama sırası: token/font/icon kaynağı → native ortak bileşenler → shell/navigation → firma/uygunsuzluk/eğitim/evrak ekranları → yeni modül adaptasyonları → aynı sentetik verilerle light/dark/small/large/large-text/keyboard/modal/empty/loading/error görüntüleri → iOS/Android karşılaştırma. Teknik bundle/package, mağaza ürünleri ve callback aynı kalacak. P18 görsel yön kapısı bu seçimle çözüldü; pixel parity, işlev ve erişilebilirlik kabulü açık.
