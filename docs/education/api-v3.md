# Eğitim servis sözleşmesi

Bütün RPC'ler etkin Auth oturumu, hesap ve firma pilot kapsamını sunucuda kontrol eder. Yazma için mevcut abonelik ve firma yazma yetkisi gerekir. RLS tablolarına istemci erişimi yoktur.

| RPC | Girdi | Çıktı |
|---|---|---|
| isg_pilot_training_sessions_v3 | p_company?, p_after? | schema_version=3, owner_id, rows, next_id, catalog, writable_companies |
| isg_pilot_training_detail_v3 | p_id?, p_company? | row, package, package_checksum, workplaces, curricula, certificates, catalog_enabled, certificate_enabled |
| isg_pilot_training_record_v3 | p_mutation UUID, p_payload | schema_version=3, owner_id, mutation_id, row veya curriculum_saved |
| isg_pilot_training_certificate_v1 | p_payload | schema_version=1, owner_id, ready, issues, snapshot; sabitlenmiş çıktıda document_id, revision, snapshot_hash |

Kayıt payload: action=save/delete/curriculum; id?, expected_version, title, provider_name, notes, trainers[], scopes[]. Her kapsam: id, company_id, workplace_id, group_name, cycle, topics[], lessons[], participants[], context_note, employer_name, employer_capacity, legal_name, location ve özel eğitim için renewal_months.

- Topic: code, group, title, instruction_minutes (tam sayı), method=face_to_face/online, trainer_ids[], parent_code? Resmî ad sunucudan gelir; alt konunun legal_title alanı korunur. Parent ile child aynı anda gönderilemez.
- Lesson: id, starts_at (offset içeren ISO tarih), instruction_minutes, break_minutes, allocations[{topic_code,minutes}]. Ara öğretim toplamına eklenmez.
- Person: id, belgeye özel job_title. Ad ve departman sunucudan snapshot edilir. Güncel personel görevi değiştirilmez.
- Scope çıktısı: canonical topic/person/workplace bilgileri, net/ara/G4 toplamları, starts_at/ends_at/held_on/valid_until, issues[]. Kaydetme sınav/yoklama üretmez.
- Firma varsayılanı company + workplace + cycle + group_name + hazard_class bağlamında sürümlenir; olaylar ve eski belgeler değişmez.
- Sertifika preview/issue: session_id, scope_id, person_id, expected_version, issued_on?; issue için kalıcı mutation_id. Opsiyonel küçük PNG logo, mevcut firma logosundan alınır ve snapshot'a sabitlenir.
- Sertifika read: document_id, revision?. Yeniden açma aynı içerik/numarayı döndürür. Üretim kapalı olsa da güncel okuma yetkisi olan kişi eski revizyonu açabilir.
- Başarılı preview var olan güncel belgeyi döndürebilir; numarasız preview ready=false ve is_draft=true'dur. issues boşsa numara tahsis edilebilir.
- Hata düzeltme önce eğitim revizyonunu artırır; sertifika yeniden hazırlanırsa eski belge revizyonu korunur.

V2 okuma devam eder. education alanı dolu kayda v2 yazma UPGRADE_REQUIRED verir. Legacy planned kayıtlar kendiliğinden gerçekleşmişe veya yeni müfredata dönüştürülmez. basic/renewal adları yeni kullanıcı seçiminde initial/periodic_repeat olarak temsil edilir. low/medium/high ↔ low/hazardous/very_hazardous eşlemesi katalog profili seçiminde açıktır.

PDF sunucu snapshot'ından yerelde üretilir. Buluta PDF dosyası veya imzalı nüsha gönderilmez. Paylaşma, görülme veya imza olayı oluşturmaz. Numara EG-yıl-sıra biçimindedir; yeni eğitim sayacı tüm firmalar için aynı kapsam/yıl transaction kilidini kullanır.
