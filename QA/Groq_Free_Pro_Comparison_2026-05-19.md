# Groq Free / Pro Karşılaştırması - 2026-05-19

Kaynak:
- Yeni QA Edge Function: `supabase/functions/groq-qa-compare`
- Aynı fotoğraf ve aynı promptlar, daha önceki Gemini analizlerinden alındı.
- Production analiz akışı, kota, `findings` ve `analyses` kayıtları değiştirilmedi.

Not:
- API key değerleri rapora yazılmadı.
- QA endpoint `x-qa-secret` ile korunuyor.
- Function deploy edildi ve test başarıyla çalıştı.

## Test Edilen Kayıtlar

| Alan | Free Groq testi | Pro Groq testi |
| --- | --- | --- |
| Kaynak analysis ID | `af3ac756-d4c0-4d2c-b46c-dc7026237490` | `a406ec24-c07f-476e-a2d3-a1ea46983844` |
| Kaynak başlık | `Genel · 19 May 22:25` | `Genel Premium + Sektör + Yüksekte Çalışma · 19 May 22:27` |
| Kaynak plan | `free` | `pro` |
| Canvas | `general` | `general_premium`, `sector`, `working_at_height` |
| Provider | `groq` | `groq` |
| Model | `meta-llama/llama-4-scout-17b-16e-instruct` | `meta-llama/llama-4-scout-17b-16e-instruct` |
| Key alias | `groq_free_primary` | `groq_plus_pro_primary` |
| Fotoğraf | 1 adet, `202536 byte` | 1 adet, `202536 byte` |

## Performans

| Metrik | Free Groq | Pro Groq |
| --- | ---: | ---: |
| Function toplam süresi | \- | `3152 ms` tüm test |
| Model çağrı süresi | `1563 ms` | `1951 ms` |
| Input token | `2998` | `3276` |
| Output token | `564` | `678` |
| Toplam token | `3562` | `3954` |
| Bulgu sayısı | `4` | `4` |
| Toplam Fine-Kinney | `223` | `1005.5` |
| Toplam 5x5 | `41` | `40` |

Performans yorumu:

- Groq çok hızlı döndü.
- Token kullanımı Gemini 3.1 Flash-Lite testlerinden daha yüksek input tarafına sahip.
- Çıktı kısa kaldığı için output token düşük.
- Hız tek başına iyi, fakat kalite/kapsam ürün beklentisinin altında.

## Free Groq Bulguları

### 1. Düşme

- Kanıt: İşçiler yüksekte çalışıyor, güvenlik önlemi görünmüyor.
- Açıklama: İnşaatın üst katında çalışan işçilerin düşme riski.
- Öneri: Emniyet kemeri ve güvenlik ağı kullan.
- Güven: `0.8`
- Fine-Kinney: O `3` × F `2` × Ş `15` = `90`, band `medium`
- 5x5: P `4` × Ş `5` = `20`, band `critical`

### 2. Çarpma

- Kanıt: İşçi omuzunda uzun malzeme taşıyor.
- Açıklama: Taşınan malzeme ile çarpma riski.
- Öneri: Malzemeyi güvenli şekilde taşı.
- Güven: `0.7`
- Fine-Kinney: O `6` × F `1` × Ş `7` = `42`, band `low`
- 5x5: P `3` × Ş `3` = `9`, band `medium`

### 3. Kayma

- Kanıt: Zemin ıslak ve enkazlı.
- Açıklama: Islak ve enkazlı zeminde kayma riski.
- Öneri: Zemin temizliği ve ıslak zemin işaretleme.
- Güven: `0.9`
- Fine-Kinney: O `10` × F `3` × Ş `3` = `90`, band `medium`
- 5x5: P `5` × Ş `2` = `10`, band `high`

### 4. KKD

- Kanıt: Bazı işçilerde KKD eksik.
- Açıklama: KKD eksikliği.
- Öneri: Tüm işçilere KKD sağla.
- Güven: `0.6`
- Fine-Kinney: O `1` × F `1` × Ş `1` = `1`, band `low`
- 5x5: P `2` × Ş `1` = `2`, band `low`

Free Groq özeti:

```text
İnşaat sahasında düşme, çarpma, kayma ve KKD riskleri tespit edildi.
```

## Pro Groq Bulguları

### 1. Düşme Tehlikesi

- Kanıt: İşçiler yüksekte çalışıyor, korkuluk yok.
- Açıklama: İnşaatın üst katında çalışan işçiler var, düşme riski yüksek.
- Öneri: Korkuluk tak.
- Mevzuat: `İşyerinde Güvenlik ve Sağlık Yönetmeliği, Madde 15`
- Güven: `0.9`
- Fine-Kinney: O `6` × F `3` × Ş `40` = `720`, band `critical`
- 5x5: P `4` × Ş `5` = `20`, band `critical`

### 2. Kayma Tehlikesi

- Kanıt: Zemin ıslak ve enkazlı.
- Açıklama: Islak zemin ve enkaz, kayma tehlikesi oluşturuyor.
- Öneri: Temizle ve işaretle.
- Mevzuat: `İşyerinde Güvenlik ve Sağlık Yönetmeliği, Madde 20`
- Güven: `0.8`
- Fine-Kinney: O `3` × F `6` × Ş `15` = `270`, band `high`
- 5x5: P `3` × Ş `4` = `12`, band `high`

### 3. Çarpılma Tehlikesi

- Kanıt: İşçi uzun malzeme taşıyor.
- Açıklama: Uzun malzeme taşıyan işçi, çarpılma riski.
- Öneri: Uygun taşıma ekipmanı kullan.
- Mevzuat: `İşyerinde Güvenlik ve Sağlık Yönetmeliği, Madde 25`
- Güven: `0.7`
- Fine-Kinney: O `1` × F `2` × Ş `7` = `14`, band `low`
- 5x5: P `2` × Ş `3` = `6`, band `medium`

### 4. Gürültü Tehlikesi

- Kanıt: İnşaat çalışması.
- Açıklama: İnşaat çalışması, gürültü riski.
- Öneri: Kulak koruyucu kullan.
- Mevzuat: `İşyerinde Güvenlik ve Sağlık Yönetmeliği, Madde 30`
- Güven: `0.6`
- Fine-Kinney: O `0.5` × F `1` × Ş `3` = `1.5`, band `low`
- 5x5: P `1` × Ş `2` = `2`, band `low`

Pro Groq özeti:

```text
İnşaat sahasında düşme, kayma, çarpılma ve gürültü tehlikesi tespit edildi.
```

## Gemini ile Kalite Karşılaştırması

Önceki Gemini sonuçları:

- Free `gemini-3.1-flash-lite`: 4 bulgu, elektrik riskini yakaladı.
- Pro `gemini-3.1-flash-lite`: 4 bulgu, mevzuatlı çıktı verdi ama elektrik riskini kaçırdı.
- Eski Free `gemini-2.5-flash`: 4 bulgu, daha güçlü ve daha dengeli risk puanları verdi.
- Eski Pro `gemini-2.5-pro`: 7 bulgu, en kapsamlı sonuçtu.

Groq sonucu:

- Hız olarak çok iyi.
- Görselden temel riskleri yakalıyor.
- Fakat açıklamalar çok kısa ve yüzeysel.
- Fine-Kinney puanları özellikle Free koşuda düşük kaldı.
- Pro koşuda mevzuat referansları gerçek Türkiye mevzuat formatı açısından zayıf ve güven vermiyor.
- Elektrik kablosu/su teması gibi daha önce Gemini tarafından yakalanan kritik risk bu Groq testinde yakalanmadı.
- Pro koşuda `Gürültü Tehlikesi` gibi görselde doğrudan kanıtı zayıf bir bulgu döndü; bu bizim "görsel kanıta dayan" kuralımıza tam uymuyor.

## Sonuç

Bu Groq modeli mevcut haliyle ana analiz modeli olmaya uygun görünmüyor.

Kullanılabileceği yer:

- Servis sürekliliği için son fallback.
- Gemini havuzu tamamen hata/limit verirse kullanıcıya boş hata göstermek yerine kısa analiz döndürme.
- Belki ikinci bir "eksik risk ailesi var mı?" doğrulama geçişinde düşük maliyetli kontrol.

Kullanılmaması gereken yer:

- Free kullanıcının ilk ve en etkileyici demo analizi.
- Plus/Pro ana analiz.
- Mevzuatlı Pro rapor üretimi.

Önerilen karar:

```text
Free ana model: gemini-2.5-flash
Free fallback: gemini-2.5-flash-lite
Groq: yalnızca son servis sürekliliği fallback'i

Plus/Pro ana model: gemini-2.5-flash
Plus/Pro kalite kontrol: gerekirse ikinci geçiş
Pro özel yüksek kalite: seçili durumlarda gemini-2.5-pro
Groq Plus/Pro: yalnızca Gemini tamamen hata verirse son fallback
```

Net yorum:

Groq burada hızlı ama "satış yaptıracak ilk analiz" kalitesinde değil. Kullanıcıyı etkilemek istediğimiz Free ilk analizde Groq değil, `gemini-2.5-flash` kullanmak daha doğru.
