# RiskDetected English Legal Set — Counsel Review Packet

Tarih: 2026-07-31  
Durum: **human review approved / publication verification pending**  
Document set: `en-global-v1`

Bu paket hukuk görüşü yerine geçmez. Amacı, hukuk incelemesinin ürünün gerçek
çalışma biçimine ve tam olarak hangi dosya sürümüne uygulandığını
kanıtlanabilir hale getirmektir.

## İncelenecek exact dosyalar

| Belge | Sürüm | SHA-256 |
| --- | --- | --- |
| Terms of Use | `terms-en-2026-07-30-draft.1` | `948d41501aa654e56ce97730decc2f70b0ea4ee0e70b357f867ad6f4dcc68d5b` |
| Privacy Policy | `privacy-en-2026-07-30-draft.1` | `d5e4f6def1860fe5642b8fd8fde5d2ac8b3bcaa3cc6d99b8add4f6f5496082e9` |
| AI and Data Processing Notice | `ai-data-en-2026-07-30-draft.1` | `61f91a4e0ceaf7d983d9a6441c7095be69ce131beef75898a2c615d63ced6be6` |
| Pre-approval set manifest | reviewed snapshot | `d1e566dd06f7175d310ba25253609304619f253b773e4a1cc97e149aefd17306` |
| Current set manifest | approval metadata added | `4269d478a669f0c7ab463e4cd25f74fee797faebe1ee00b19efc7879e7b4e5d7` |

Dosyalar:

- `App/LegalDocuments/en/Terms-of-Use.md`
- `App/LegalDocuments/en/Privacy-Policy.md`
- `App/LegalDocuments/en/AI-and-Data-Processing-Notice.md`
- `App/LegalDocuments/en/manifest.json`

Belge metni değişirse hash değişir ve önceki onay geçersiz sayılır. Onay,
manifest'e sonradan eklenen onay/yayın metadatasına değil, yukarıdaki üç exact
belge SHA-256 değerine bağlanmıştır.

## Ürün ve pazar kapsamı

- Uygulama: RiskDetected iOS
- Bundle ID: `com.riskdetected.app`
- Model: Free, Plus ve Pro App Store abonelikleri
- İlk English pazarları:
  - United Kingdom
  - United States
  - Australia
  - Canada
- Kullanım: workplace photograph üzerinden AI destekli safety finding,
  control suggestion, risk prioritisation ve PDF/XLSX report
- Ürün resmi denetim, profesyonel görüş veya mevzuata uygunluk sertifikası
  vermez.
- AI çıktısı competent-person ve saha doğrulamasının yerine geçmez.

## Mevcut hizmet sağlayıcı ve veri akışı özeti

| Sistem | Amaç |
| --- | --- |
| Supabase | Auth, PostgreSQL, Storage, Edge Functions, cron ve queue |
| Google Gemini / Google AI | Ana görsel analiz sağlayıcısı |
| Groq | Provider pool süreklilik/fallback |
| Apple App Store | Satın alma ve abonelik işlemleri |
| RevenueCat | Entitlement ve subscription doğrulaması |
| APNs | Push notification |
| Resend | Transactional/support e-posta |
| Apple Sign-In / Google Sign-In | Kullanıcı seçerse identity provider |

AI sağlayıcıya gönderilen içerik, kullanıcının istediği analizi üretmek için
gerekli fotoğraf ve yapılandırılmış analysis context ile sınırlıdır.
Uygulama yüz tanıma veya biyometrik kimlik tespiti ürünü değildir.

## Ürün verisi ve mevcut retention davranışı

| Veri | Runtime politika |
| --- | --- |
| Free analiz fotoğrafı | 7 gün |
| Plus analiz fotoğrafı | 30 gün |
| Pro analiz fotoğrafı | Kullanıcı silene veya hesap kapanana kadar; teknik/yasal istisnalar saklı |
| Raw AI response | 30 gün |
| Analiz sonucu ve finding | Kullanıcı veya hesap silme akışına kadar |
| Rapor | Kullanıcı silene kadar |
| Consent/legal acceptance audit | İspat ve denetim gereksinimine göre |
| Subscription/transaction kayıtları | Mali, hukuki ve App Store uyuşmazlık sürelerine göre |

Hesap silme uygulama içinden başlatılır. Backend storage objelerini ve uygulama
verisini temizler, ardından Supabase Auth kullanıcısını siler. Apple tarafından
yönetilen aktif abonelik ayrıca Apple account ayarlarından yönetilir.

## Counsel tarafından açıkça karara bağlanacak konular

1. Veri sorumlusu/controller tam ticari kimliği, kayıt numarası ve posta
   adresi.
2. Her launch market için governing law, mandatory consumer rights,
   jurisdiction ve liability metni.
3. Fotoğraf/AI işlemenin lawful basis'i; consent gerekiyorsa ayrı, özgür ve
   geri çekilebilir consent tasarımı.
4. Özel nitelikli/sensitive data içerebilecek workplace images için izin,
   minimisation ve kullanıcı sorumluluğu.
5. International transfer mekanizmaları, provider sözleşmeleri ve gerekli
   disclosure.
6. Provider/controller/processor rolleri ve public provider listesinde
   gösterilecek exact adlar.
7. Retention tablosunun launch marketlerinde yeterliliği ve yasal
   istisnaları.
8. Data-subject request kanalı, kimlik doğrulama, yanıt süresi ve supervisory
   authority açıklaması.
9. Children/minors, workplace monitoring ve üçüncü kişi görüntüleri için
   gerekli yasaklar veya ek metin.
10. App Store subscription, trial, renewal, cancellation ve refund metinleri.
11. AI limitation, human review ve “no compliance certification” metninin
    yeterliliği.
12. Terms, Privacy ve AI/Data Processing Notice'ın ayrı belgeler olarak
    sunulmasının yeterliliği; ayrıca explicit consent gerekip gerekmediği.

## Public URL yayın planı

Website source repository:
`/Users/keremkayalar/Documents/Kerem-APPler/WebRiskDetected`

İnsan onayı tamamlandı; ancak English legal içerik henüz public klasöre veya
production'a yazılmadı. Önerilen final yollar:

- `https://riskdetected.com/en/terms-of-use`
- `https://riskdetected.com/en/privacy-policy`
- `https://riskdetected.com/en/ai-and-data-processing-notice`

Bu yollar şu anda gerçek English legal sayfa değildir. 2026-07-31 salt-okunur
kontrolünde aday yollar `200` dönmesine rağmen Türkçe SPA fallback'i
göstermiştir; dolayısıyla Faz 5 gate'ini geçmez.

Yayın sonrasında otomatik gate:

- HTTPS ve `riskdetected.com` hostunu,
- redirect sonrası aynı hostta kalmayı,
- HTTP 200 ve uygun content type'ı,
- English document marker'ını,
- Türkçe HTML/content fallback bulunmamasını

doğrular.

## Onay kaydı

- Decision: `approved`
- Reviewer: `Kerem`
- Reviewer qualification:
  `Hukuk belgelerini inceleme ve onaylama yetkinliğine sahip.`
- Reviewed at: `2026-07-31T06:40:30Z`
- Reviewed pre-approval manifest SHA-256:
  `d1e566dd06f7175d310ba25253609304619f253b773e4a1cc97e149aefd17306`
- Immutable approval record:
  `docs/localization/phase-5/LEGAL_COUNSEL_APPROVAL_2026-07-31.json`
- Approval record SHA-256:
  `d76536fac72cff9d3f00888de79515557aac68d9201444a8ba05dc96a5310605`

Release gate onayı yalnız approval record içindeki üç belge yolu ve SHA-256
değeri current manifest ve bundle dosyalarıyla birebir eşleştiğinde kabul
eder. İnsan onayı tamamlanmış olsa da gerçek English public URL'ler
yayımlanıp canlı doğrulanana kadar manifest `blocked_pending_publication`
kalır; English auth ve purchase açılmaz.
