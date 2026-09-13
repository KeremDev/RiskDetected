# score-portfolio — sürümlü skor politikası, açıklanabilir katkı ve portföy

P17'nin sunucu tarafı ilk dilimi. `private_isg.rollout('score')` kapalıdır, istemciye GRANT yoktur. Skor **resmî uygunluk sertifikası değildir** ve bu dilimde hiçbir ağırlık onaylanmamıştır.

## Ne garanti edilir?

- **Yayın insan kararıdır, ağırlıklar yine de onaysızdır.** `CHECK(status<>'published' OR (approved_by IS NOT NULL AND approval_note IS NOT NULL AND published_at IS NOT NULL))`; ayrıca `CHECK(NOT weights_approved)`, `CHECK(NOT cap_approved)` ve `CHECK(NOT is_official_compliance_certificate)`. Tek bir süreci bile olmayan politika yayımlanamaz (`POLICY_INCOMPLETE`).
- **Her sürecin kendi katkı tavanı vardır.** `CHECK(contribution_cap<=weight)` ve `CHECK(capped_points<=contribution_cap)`; bin çalışanlı bir firma bir modülün ağırlığını sınırsız büyütemez.
- **Bilinmeyen kendi durumudur.** Kaydı olmayan süreç `needs_review` sayılır, "zorunlu değil"e düşmez; paydada kalır, katkısı sıfırdır ve cevabı `provisional` yapar (`CHECK(needs_review_count=0 OR provisional)`).
- **Muafiyet doğrulanmış gerekçe ister.** `not_required` için gerekçe, doğrulayan kişi ve tarih zorunludur; ancak o zaman paydadan çıkar.
- **Gönüllü kayıt nötrdür.** Ne paya ne paydaya girer; `CHECK(exclusion_reason IS DISTINCT FROM 'voluntary' OR capped_points=0)`.
- **Veri yoksa sayı yoktur.** `CHECK(has_any_data OR main_score IS NULL)` ve `CHECK(total_weight>0 OR main_score IS NULL)`; boş firmada 100 gösterilemez.
- **Kritik uyarı sayının yanında durur.** `CHECK(NOT hidden_by_total_score)`; yüksek toplam onu gizleyemez.
- **Her sayı bir kurala kadar izlenir.** `score_contributions` süreç başına ağırlık, tavan, ham oran, uygulanan tavan ve dışlanma gerekçesini taşır.
- **Oracle elle hesaplanmıştır.** `CHECK(hand_computed)` ve `CHECK(NOT computed_by_production_function)`; üretim fonksiyonunu ikinci kez çağırıp aynı sonucu beklemek kanıt sayılmaz.
- **Geçmiş yeniden yazılmaz.** Snapshot `UNIQUE(company_id,policy_version_id,computed_for)` ile eklenir; yeni politika yeni satır üretir, eskisine dokunmaz. Simülasyon hiçbir snapshot yazmaz (`'snapshots_written',0`, `CHECK(NOT history_rewritten)`).
- **Portföyde her firma bir kez sayılır.** `CHECK(weighting='equal_per_company')`, `CHECK(portfolio_weight=1)`, `CHECK(NOT headcount_used_as_weight)`; çalışan sayısı raporlanır, ağırlık olarak kullanılmaz. Hiçbir firma skorlanmadıysa ortalama NULL'dır.

## Ne garanti edilmez?

Aday ağırlıklar (25/25/15/15/10/10) ve tavanlar onaylı ticari/uzman kararı değildir (K15). Domain üreticileri — P06 yükümlülükleri, P07 tamamlanmaları, P08 risk sürümleri, P09 uygunsuzlukları, P10 modülleri — henüz `score_subject_states` yazmıyor; durumlar dışarıdan besleniyor. Firma/portföy ekranı, skor açıklama yüzeyi ve admin explainability sayfası bu dilimde yoktur.
