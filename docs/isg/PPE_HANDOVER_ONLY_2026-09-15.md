# KKD — yalnız zimmet ve indirilebilir form

Kullanıcının 15 Eylül kararı önceki KKD kapsamını değiştirir. Aktif iOS pilotunda firma, personel, KKD adları ve teslim tarihiyle zimmet kaydedilir. Kayıttan A4 PDF zimmet formu indirilir; iOS paylaşım menüsünde Dosyalara Kaydet kullanılabilir.

Miktar/birim, iade, kayıp, stok/durum sayaçları, imzalı nüsha konumu ve genel düzenle/sil/evrak bağla akışları KKD için pasiftir. Eski kayıtlar silinmez. Eski miktar kolonları yalnız şema uyumluluğu için yeni kayıtta sabit 1/piece alır; UI ve formda miktar yoktur. Önceki ekranlar kaynakta uyumluluk için tutulur ama pilot rotası bunları kullanmaz. Diğer modüllerin yönetim işlemleri değişmez.

Yeni form bilgileri insert transaction'ında snapshot olarak saklanır. Eski kayıtlarda ilk form isteğinde mevcut firma/personel bilgileri sabitlenir ve formda bu durum açıklanır. İmzalar boş bırakılır, indirme imzalanmış kayıt üretmez. PDF geçici cihaz dosyasıdır; bulut dosya yükleme/arşivi yoktur.

## Doğrulama

- `scripts/modules/run_pilot.mjs`: önceki modül testleri ve yeni `ppe_form_check.sql` geçti. Yeni kontroller: tekrar gönderim, personel değişince snapshot korunması, iade oluşmaması, eski üç yazma eyleminin reddi, miktar payload reddi, KKD düzenle/sil/bağla reddi, yanlış firma personeli ve başka hesap form erişiminin reddi.
- Canlı pilot hesabıyla create_form → form okuma geçti; test kaydı transaction rollback ile geri alındı.
- Canlı legacy fonksiyon authenticated EXECUTE kapalı, form RPC açık.
- iOS 2.0.3 (109) device build başarılı. Fiziksel telefon üzerinden form paylaşımı ayrıca kullanıcı kabulü gerektirir; tüm ekranların görsel kabulü yapılmış sayılmadı.
- Migration: `20260914212248_isg_ppe_handover_only`; SHA256 `e308f32880a652803d5137b47330be1ee78c06938a18ddcf9a3b8e9c1b0bbd71`. Pilot mirror birebir eşleşir.
- Supabase advisor yeni form SECURITY DEFINER RPC'sini raporlar: bu bilinçli yetkili giriş noktasıdır, her istekte oturum/pilot/firma yetkisi denetlenir; anonim execute kapalı. [Advisor açıklaması](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable). Mevcut private tablo policy bilgilendirmeleri ve mevcut leaked-password uyarısı bu değişiklikten bağımsızdır.

Android için yeni ekran teslim edilmedi; sunucu eski KKD yazma eylemlerini tüm istemcilerde reddeder.
