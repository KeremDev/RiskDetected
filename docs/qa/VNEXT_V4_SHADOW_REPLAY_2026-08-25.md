# vNext v4 Shadow Replay — 2026-08-25

## Kapsam

- Kaynak: `private.analysis_photo_runs.normalized_output`
- Photo-run: 85
- Analiz: 36
- V3 ham görsel aday: 230
- Kritik/permanent aday: 90
- Yeni provider çağrısı: 0
- Üretim fotoğrafı dışa aktarımı veya eğitim kullanımı: 0

Replay, kayıtlı v3 görsel fact'lerini `v4-shadow-replay-v1` adaptörüyle yeni
kanıt sınıflarına dönüştürüp yalnız `claim-routing-v1` üzerinde çalıştırır.
Provider algı recall'ını değil; router kader bütünlüğünü, sınıf izolasyonunu ve
tekrar birleştirme davranışını ölçer.

## Sonuç

| Metrik | Sonuç |
|---|---:|
| Ham aday | 230 |
| Nihai observed kart | 209 |
| Same-event-path birleşen aday | 21 |
| Kritik aday | 90 |
| Kritik sessiz düşme | 0 |
| Provider çağrısı | 0 |

İlk replay, same-event-path içinde kartı birleşen 9 kritik kardeş adayı yanlış
biçimde “sessiz düşme” sayan bir invariant kusuru yakaladı. Router ledger'ı
her adayın kaderini zaten içeriyordu. Runtime ve atomik finalizer; kart,
hard-reject veya açıklanabilir routing-ledger kaydını geçerli kader kabul edecek
şekilde düzeltildi. İkinci replay sonucu sıfır kritik sessiz düşmedir.

## Yeniden çalıştırma

Replay kodu:

- `supabase/functions/analyze-v4/replay-adapter.ts`
- `scripts/v4-shadow-replay.ts`

Script stdin'den JSON dizi alır; hiçbir ağ veya provider çağrısı yapmaz.
