# Web hesap silme sözleşmesi v1

Bu sözleşme `https://riskdetected.com/hesap-silme` sayfası ile Supabase
`request-account-deletion` fonksiyonu arasındaki Android/Google Play uyumlu akışı tanımlar.
Web sitesi bu repository'de değildir; web repository'sindeki uygulama bu sözleşme ve kabul
testleri tamamlanmadan Android release üretilemez.

## Değişmez güvenlik kuralları

- OTP başlatma çağrısında `shouldCreateUser=false` kullanılır.
- OTP başlatıldıktan sonra hesap var/yok ayrımı yapılmadan aynı Türkçe mesaj gösterilir.
- Silme isteği yalnız OTP ile oluşmuş geçerli Supabase session sonrasında gönderilir.
- Browser hiçbir zaman `service_role`, queue worker secret'ı veya Resend secret'ı almaz.
- Production CORS varsayılanı yalnız `https://riskdetected.com` olur. Staging origin'i
  `ACCOUNT_DELETION_ALLOWED_ORIGINS` secret'ına açıkça eklenir; localhost production
  varsayılanında bulunmaz.
- Sayfa, aktif Google Play aboneliğinin Play üzerinden ayrıca yönetileceğini ve veri silmenin
  geri alınamayacağını açıkça gösterir.

## İstemci akışı

1. Kullanıcı e-posta adresini girer.
2. Web istemcisi Supabase OTP çağrısını `shouldCreateUser=false` ile yapar.
3. Sonuçtan bağımsız ortak mesaj gösterilir: “E-posta adresi bir hesapla eşleşiyorsa doğrulama
   bağlantısı gönderildi.”
4. OTP doğrulanıp session alındığında silinecek veri türleri listelenir: hesap/profil, yüklenen
   fotoğraflar, analizler, raporlar, şirketler ve uygulama içi tercihler.
5. Kullanıcı geri döndürülemezlik onay kutusunu işaretler ve isteği gönderir.
6. Web aşağıdaki body ile authenticated Edge Function çağrısı yapar:

```json
{
  "email": "optional",
  "request_id": "browser-generated-uuid",
  "support_id": "optional-client-trace",
  "client_platform": "web",
  "completion_mode": "request_only"
}
```

7. HTTP `202` yanıtındaki `support_id` ve `estimated_completion_at` kullanıcıya gösterilir.
8. Session temizlenir; aynı browser state'i tekrar gönderim yapamaz.

## Başarı yanıtı

```json
{
  "ok": true,
  "completed": false,
  "status": "pending",
  "request_id": "server-request-uuid",
  "support_id": "RD-XXXXXXXX",
  "estimated_completion_at": "ISO-8601",
  "message": "Hesap ve veri silme talebin alındı. İşlem en geç 24 saat içinde tamamlanacaktır."
}
```

Tekrarlanan istek açık `pending/processing` kaydını yeniden kullanır ve son istek sözleşmesine
göre platform/completion metadata'sını hizalar. `due_at`, talebin en geç tamamlanacağı 24 saatlik
SLA sonudur; worker bu zamanı beklemeden ilk saatlik koşuda işlemi dener. E-posta gönderim hatası
kuyruk kaydını geri almaz. Saatlik worker yalnız `web + request_only + pending/processing`
kayıtlarını işler; maksimum 10 deneme, 15 dakika sonra stale claim recovery, idempotent claim ve
PII içermeyen hata kodu/destek kodu alarmı kullanır.

## Web kabul testleri

- Bilinen ve bilinmeyen e-posta OTP başlatma ekranında aynı sonucu verir.
- Yeni kullanıcı oluşturulmaz.
- OTP/session olmadan fonksiyon `401` döndürür ve queue kaydı oluşmaz.
- Onay kutusu olmadan istemci istek göndermez.
- Geçerli web isteği `202` döner; worker senkron çağrılmaz.
- Aynı kullanıcıdaki tekrar gönderim yeni açık kayıt üretmez.
- Resend hatası `202` yanıtını ve kuyruğu bozmaz.
- Worker tekrarında Auth kullanıcısı daha önce silinmişse işlem başarılı/idempotent tamamlanır.
- Tamamlanan kayıtta e-posta ve ham kullanıcı ID'si temizlenir; yalnız hash/audit alanları kalır.
- Talep en geç 24 saat içinde Auth, Storage ve kullanıcıya ait DB verilerini temizler.
