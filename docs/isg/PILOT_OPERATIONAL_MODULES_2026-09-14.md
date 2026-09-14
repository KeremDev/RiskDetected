# Dört operasyon modülünün canlı pilot teslimi

Kullanıcı talebi: diğer modülleri tamamlayıp aktif hale getirmek. Bu teslim dört modülün kayıt/okuma/düzenleme servislerini açar; bütün master planın tamamlandığı anlamına gelmez.

| Modül | Aktif işlem |
|---|---|
| Acil Durum Planları | Firma/işyeri, ekip bilgisi, hazırlık/geçerlilik tarihi, dayanak ve yeni plan sürümü |
| Tatbikatlar | Etkin planla ilişkilendirme, planlama, gerçekleşme/katılımcılar, gözlem/iyileştirme, iptal |
| KKD Zimmetleri | Personel teslimi, miktar/birim, kısmi/tam iade, iade düzeltmesi ve kalan miktar |
| Atama ve Temsilciler | Personel/görev/işyeri, seçim-atama dayanağı, başlangıç-bitiş; çakışan görevin reddi |

## Canlı paket

- Proje: `ppcrzemgiztzcgddbins`.
- Önceki migration başı: `20260914193516_isg_pilot_document_tracking`.
- Uygulanan migration: `20260914205319_isg_pilot_operational_modules`.
- Remote ledger ile dosya SHA-256 eşleşti: `66f13e09d5833d3922a9814f3634c51decf8f7f7a740fe3ef2eeb1d4b9abde71`.
- Birebir aynası: `supabase/pilot-release/supabase/migrations/20260914205319_isg_pilot_operational_modules.sql`.
- Kaynak üretici: `scripts/modules/build_pilot.py`; CLI ile oluşturulmuş geliştirme adayı `20260914204842_isg_pilot_operational_modules.sql`.
- Kaynak adayı tekrar uygulanmaz; ana migration klasörü topluca push edilmez.

Modül anahtarları ayrı DML ile açıldı. Dört require-company işlevi hesap pilot iznini ve firma pilot kapsamını kontrol eder. Portföy sorguları yalnız pilot kapsamındaki firmaları döndürür. Yeni tablolar RLS açık, istemci doğrudan tablo grant sayısı sıfırdır. Halihazırdaki tek pilot hesabın kapsamı genişletilmedi; yeni hesap yetkisi verilmedi.

## İstemci ve doğrulama

- NOVA menüsüne dört hedef eklendi. Hesap düzeyindeki sayfalarda firma henüz seçilmemişken formların gizlenmesi düzeltildi; gerçek yazma yetkisi sunucuya ait.
- Dört serviste kalıcı, hesap + işlem gövdesi bazlı mutation kimliği kullanılıyor. Ağ hatasında aynı gövdeyle tekrar deneme aynı operation/mutation kimliğini korur; oturum kontrolü ve yanıt çözümlemesi sonrasında kayıt temizlenir.
- `node scripts/modules/run_pilot.mjs`: 167 kontrol geçti. Ekipman pilot baseline'ı + yeni paket, bağımlılık fixture'larıyla izole PostgreSQL 17 üzerinde denendi. Dosya tablosu fixture'dan kaldırıldı; paket dosya çekirdeği varmış gibi davranmaz.
- `scripts/modules/MutationCheck.swift`: gerçek mutation günlüğü kaynağıyla 8 davranış kontrolü geçti.
- Canlıda dört liste RPC'si ve plan → tatbikat gerçekleşme, KKD teslim → iade, atama → sonlandırma yazma zincirleri doğrulandı. Kontrol kayıtları iç transaction geri alınarak temizlendi; dört ana tablo sayısı sonrasında sıfırdı.
- `authenticated` rolüyle canlı liste okuma ayrıca doğrulandı.
- iOS pilot 2.0.3 (106) fiziksel cihaz hedefinde derlendi; log `/tmp/nova-device-106.log`. iPhone Kerem cihazına kurulum başarılı.
- Security advisor çalıştırıldı. Yeni private tabloların politikasız RLS bilgileri, doğrudan erişimi kapatıp kontrol edilen RPC kullanma mimarisiyle uyumludur. Projedeki eski Auth/public işlev uyarıları bu modül paketinin tamamlandığı iddiasına dahil değildir.

## Açık kalan kapsam

Bu pilotta dosya çekirdeği bulunmadığı için belge UUID alanları NULL ile sınırlı. Dosya yükleme/imzalı nüsha arşivi varmış gibi gösterilmez. Belge üretimi, ortak dosya arşivi, hatırlatma teslimi ve Android paritesi hâlâ açık. Bu dört modülün ana kayıt işlemleri aktiftir; tam master kabulü değildir.

Sonraki bağımsız modüller: yıllık çalışma planı, toplantı/kurul, saha ziyaretleri, çalışma izni formları, taşeron akışları. Risk değerlendirmesi/kontrol listeleri ve İSG-KATİP için de ayrı pilot servis paketleri gerekiyor. Eğitimde daha sonraki kullanıcı kararları (planlama/yoklama/sınav olmaması) aynen korunur.
