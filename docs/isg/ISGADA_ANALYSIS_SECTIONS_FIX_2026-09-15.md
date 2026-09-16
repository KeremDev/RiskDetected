# Analiz bölümleri — yanlış sıfır düzeltmesi

15 Eylül 2026.

## Neden

Canlı `analysis_result_hub_v1` bayrağı `build_allowlist` modunda yalnız iOS 87–91'i içeriyordu. Pilot 101–116 bu listede değildi. Edge function böyle bir istemciye `enabled:false, reason:rollout_gate_closed` döndürür. NovaAnalysisWorkspace.detail ise `try?` ile taşıma hatasını da yutarak eksik projection için görüş/eğitim bölümlerini boş diziye çeviriyordu. Kullanıcı gerçek sıfır ile erişilemeyen içeriği ayıramıyordu.

## Düzeltme

- Canlı flag'in yalnız enabled_ios_builds alanına 101–116 eklendi. 87–91 korundu; Android listesi, rollout modu, kill switch ve ücretli/teaser filtreleri değiştirilmedi. SQL güncellemesi mevcut build_allowlist ve kill_switch=false koşuluyla yapıldı; read-back yeni listeyi doğruladı.
- detail artık yükleme hatasını iletir, enabled ve dört bölümün varlığını denetler. Kapalı/eksik cevap sıfır sonuç olarak sunulmaz.
- Ekranda hata sonrası Tekrar dene eylemi eklendi. Yeniden yüklemede eski veri/rapor CTA'sı temizlenir.
- Son pilot analizin görünür kayıtlarında 2 assurance_requirement ve 2 observed_finding bulundu; kişisel içerikler dışa çıkarılmadı. Eğitim kartları metadata'dan Edge tarafından oluşturulur; canlı HTTP/telefon ekranı bu turda doğrulanmadı.

## Doğrulama

- `deno test supabase/functions/_shared/analysis-result-hub_test.ts`: 5 PASS. Eski build listesinde 110 reddi, yeni pilot listesi kabulü, 117 reddi, capability/kill switch ve Android sınırı; mevcut ücretli/teaser kontrolleri korunur.
- Değişen iki Swift dosyası `swiftc -frontend -parse` ile geçti. Bu syntax kontrolüdür, tam iOS build veya cihaz kabulü değildir.
- Sunucu ayarı mevcut kurulu pilotta analiz yeniden açılınca etki eder. Yeni hata/tekrar-dene yüzeyi sonraki build ile telefona gelir.

## Tekrarlamayı önleme

Yeni pilot build dağıtılmadan önce gerçek app build değeriyle result-hub gate kontrolü release listesine dahil edilmeli. 117 ve sonrası otomatik açık değildir; yalnız bilinen uyumlu build'ler eklenmeli. Gelecekte build listesini atlayarak tüm hesaplara açılmamalı.
