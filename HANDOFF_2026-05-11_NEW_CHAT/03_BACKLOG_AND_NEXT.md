# 03 - Yapılacaklar ve Sonraki İşler

## En Yakın İşler

1. Manual simulator QA tamamlanmalı.
2. Rapor oluştur sheet Excel seçimi ve ardından Reports XLSX preview akışı tamamlanmalı.
3. Onboarding ekranları geliştirilmeli.
4. AI canvas promptları kullanıcıdan alınmalı ve backend prompt routing'e net işlenmeli.
5. KVKK / Kullanım koşulları / AI veri işleme uzun resmi metinleri eklenmeli.

## Manual QA Başlıkları

Öncelikli kontrol listesi:

- Orta `Tara` butonu:
  - Ana sayfadayken.
  - Analizler sayfasındayken.
  - Raporlar sayfasındayken.
  - Profil sayfasındayken.
  - Free limit doluyken uyarı veriyor mu? `Geçti`
  - Kamera/Galeri seçiminden sonra doğru akışa gidiyor mu?
- Foto kaynak sheet:
  - `Kamera ile çek` çalışıyor mu?
  - Simülatörde kamera yoksa galeriye düşüyor mu?
  - `Galeriden seç` label/accessibility ile çalışıyor mu?
  - X kapatma çalışıyor mu?
- Canvas sheet:
  - X kapatma çalışıyor mu? `Geçti`
  - Max 2 seçim çalışıyor mu? `Geçti`
  - Free kullanıcı Pro canvas seçemiyor mu? `Düzeltme sonrası geçti`
  - Pro kullanıcı Pro canvas seçebiliyor mu?
- Analiz bekleme ekranı:
  - Animasyonlar taşmıyor mu?
  - Dark/light modda okunuyor mu?
- Result ekranı:
  - Rapor Oluştur sheet açılıyor mu?
  - Free kullanıcı Risk Analizi Tablosu seçemiyor mu?
  - Pro kullanıcı PDF/Excel seçebiliyor mu?
  - İndir/Paylaş ikonları doğru çalışıyor mu? `Düzeltme sonrası geçti`
- Reports:
  - PDF önizleme ve indirme. `Geçti`
  - XLSX önizleme ve indirme. `Excel üretim QA sonrası test edilecek`
  - Ana sayfa rapor kartından preview.
- Dark mode:
  - Home
  - Result
  - Report settings
  - Profile
  - Analyses
  - Reports
- Profil:
  - Profil bilgileri kaydetme.
  - Logo seçimi.
  - Geçmiş analizler/Raporlarım routing.

## Onboarding

Kullanıcının istediği:

- Uygulama ilk defa indirildiğinde Auth ekranından önce onboarding gelsin.
- Tanıtım, kullanım ve eğitim amaçlı birkaç ekran olsun.
- Uygulama görselleri + kısa metinler içersin.
- Kullanıcı `İlerle` ile adım adım geçsin.
- Bittiğinde mevcut login ekranı açılsın.
- Tamamlandı bilgisi local saklansın, tekrar gösterilmesin.

## AI Canvas Promptları

Frontend canvas listesi hazır. Kullanıcı daha sonra sabit promptları verecek.

Pro canvaslar:

- Genel Premium
- Makine
- Ortam Ölçümü
- Mevzuat
- Sektör

Not: Her 6'lı görünümde 2 Pro kart olması istenmişti; UI buna göre sıralandı.

## Legal İçerikler

Altyapı hazır:

- KVKK
- Kullanım koşulları
- AI veri işleme

Kullanıcı uzun içerikleri daha sonra verecek.

## Push Notification

Yapılacak dış ayarlar:

- Apple Developer'da APNs `.p8` key oluştur.
- Supabase secrets:
  - `APNS_KEY_ID`
  - `APNS_TEAM_ID`
  - `APNS_BUNDLE_ID`
  - `APNS_PRIVATE_KEY`
  - `APNS_ENV`

## Auth Prod Readiness

Hâlâ yapılacak:

- Supabase custom SMTP.
- OTP email template gerçek mailbox testi.
- Apple provider gerçek hesap testi.
- Google OAuth callback testi.

## RevenueCat / Gerçek Pro

Şimdilik gerçek subscription yok.

Yapılacak:

- RevenueCat entegrasyonu.
- Webhook ile Supabase profile entitlement güncelleme.
- Local `app.isPro` yerine verified entitlement.
