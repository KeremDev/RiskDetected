# OSGB sahiplik ve erişim matrisi

17 Eylül 2026 · Referans: `6eebab8946c627f42d13415cff1b8dc5007cc1ce`.

Bu matris [A–L tam entegrasyon ana planının](OSGB_FULL_INTEGRATION_PLAN.md) domain erişim ekidir. Özellik bazlı kabul takibi [gereksinim matrisindedir](OSGB_REQUIREMENTS_TRACEABILITY.md).

Bu belge hedef izinleri ve mevcut kod farkını ayırır. Mevcut erişimin cross-tenant olduğu iddia edilmez: bugün sınır çoğunlukla `owner_id/user_id + company_id + active session + pilot/paid gate`. Hedef workspace üyeliği henüz uygulanmadı. Kaynak ve dağıtım durumu için [envanter](OSGB_REPO_INVENTORY.md).

## Kimliklerin ayrılması

| Kavram | Bugün | Hedef |
|---|---|---|
| Giriş yapan kişi | Supabase auth user/session | Aynen korunur; workspace değişince auth hesabı değişmez. |
| Firma sahibi | `public.companies.user_id` | Firma `workspace_id` ile kiracıya aittir; eski sahip bilgisi tarihsel/compatibility amaçlı korunur. |
| Üye | Tenant üyeliği yok | `(workspace_id, user_id)` üyelik; rol, durum, revision; kişi birden fazla workspace'e üye olabilir. |
| Yazarlık | Çoğu modülde owner veya owner'a bağlı actor | Doğrulanmış gerçek user/actor; devirde değişmez. Sistem işi ayrı aktör türüdür. |
| Firma sorumlusu | Personel atama kayıtlarıyla aynı şey değil | Workspace içindeki expert membership → company, dönem ve primary rolü; çoktan çoğa. |
| Yetki | Company owner kontrolü | Aktif workspace + aktif membership + rol + gerekiyorsa aktif firma assignment + domain hakkı. |

## Domain envanteri ve taşınacak sınırlar

Tablo isimlerinde aksi belirtilmedikçe şema `private_isg`. Root DDL ile pilot override'lar birlikte incelenmelidir. İlgili tüm receipt/audit/outbox/child tabloları domain'in parçasıdır; yalnız ana tabloya kolon eklemek tamamlanma değildir.

| Domain / gerçek tablolar | İstemci / sunucu bağlantısı | Hedef scope ve özel kontrol | Faz |
|---|---|---|---|
| Firma: `public.companies`, pilot company profiles | `CompanyService`, `NovaPilotCompanyService`, `NovaCompanyServiceAdapter`; `isg_pilot_company_create_v1`, `isg_pilot_overview_v2` | Workspace firması; personal legacy path yalnız personal verisi. Name/limit trigger, FK cascade, owner DTO guard birlikte değişir. | C |
| Personel: `workplaces`, `departments`, `employees` | `NovaPersonnelService`; `isg_personnel_read_v1/mutate_v1` | Company/workspace composite ilişki; aynı workspace'in başka firmasından employee ID de reddedilir. | D |
| Dizin: `job_roles`, `contractor_organizations`, `contractor_engagements`, `workplace_context_versions`, `employee_assignments` | `NovaDirectoryService`, `IsgAssignmentMove` | Personel assignment semantiği korunur; OSGB expert assignment için tekrar kullanılmaz. Snapshot/history yazarını koru. | C/D |
| Eğitim: `training_sessions`, `training_enrolments`, `attendance_intervals`, `training_completions`; pilot `pilot_training_records/participants` | `NovaTrainingService`, `NovaTrainingSessionService`, `NovaEducationService` | Eğitim/katılımcı/firma/asset aynı scope; saat ve kişi istatistiklerinde workspace filtrelemesi. Aday curriculum ile pilot gerçekleşmiş eğitim ayrılır. | D |
| Risk: `risk_assessments`, `risk_assessment_versions`, `risk_source_links`, `risk_file_variants` | `NovaRiskAssessmentService` | Firma, sürüm ve kaynak dosya; eski author/current responsible ayrımı. Liste kadar detail/version/export da doğrulanır. | D |
| Uygunsuzluk: `nonconformities`, `nonconformity_actions/transitions`, `verification_records` | `NovaNonconformityService`, `NovaAnalysisWorkspaceService` | Kaynak finding'in workspace'i ve hedef firma erişimi sunucuda doğrulanır. Kullanıcı talebi olmadan personal analiz OSGB'ye otomatik taşınmaz. | D |
| Denetim: `checklist_templates`, `checklist_runs`, `checklist_run_items` | `NovaChecklistService` | Template erişim sınıfı ile company run ayrılır; risk/uygunsuzluk linkleri aynı tenant. | D |
| Acil durum/tatbikat: `emergency_plan_versions`, `drill_records` | `NovaEmergencyPlanService`, `NovaDrillService` | Plan/team/employee/asset linkleri; kişisel author koruma. | D |
| Ekipman/kontrol: `equipment_items`, `equipment_inspection_rules`, `equipment_inspections` | `NovaEquipmentCheckService` | Ekipman firma scope, rapor tenant + firma erişimi; global tür kataloğu müşteri verisinden ayrı. | D |
| Atama/KKD: `appointments`, `ppe_handovers`, `ppe_returns` | `NovaAppointmentService`, `NovaPPEService` | Employee/company/asset aynı scope; bu atama uygulama kullanıcısına yetki vermez. | D |
| Sözleşme/plan/kurul: `katip_contracts`, `annual_work_plans/items`, `annual_training_plans`, `board_meetings/decisions` | `NovaKatipService`; `App/DesignSystem/ISG/NovaModuleEditor.swift`, `NovaModuleTracking.swift` ve `NovaPilotProcessGate` | Company/workspace; dosya ve sorumlu bağlantıları. KATİP kayıtları resmi API doğrulaması değildir. | D |
| İzin/ziyaret/defter: `work_permit_forms`, `site_visits`, `site_visit_observations`, `notebook_archive_entries` | `NovaModuleEditor`, `NovaPilotProcessGate`; `isg_pilot_module_mutate_v1` | Geçmiş ziyaret yazarı değişmez; devir gelecekteki sorumluluğa uygulanır. | D/J |
| Dosya: `upload_intents`, `file_assets/derivatives`, `file_library_entries`, personal filing | `NovaFileLibraryService/LiveAdapter`, `isg-file-inspect`; Storage API | Metadata + fiziksel object + parent filing birlikte. Nullable company, global erişim anlamına gelmez. Cross-workspace dedup paylaşımı açılmaz. | D/G |
| Analiz/finding/photo: `public.analyses/findings/photos` | `AnalysisService`, `AnalysisResultHubService`, Android `AnalysisRepository`, analiz Edge Function'ları | Personal analizler personal kalır; yeni OSGB job workspace+actor+company+reservation ile bağlanır. Okuma/mutation/worker yetkisi yeniden kontrol edilir. | D/G |
| Rapor/import/export: `public.reports`; `documents/versions`, `export_jobs`, `import_batches/rows/checkpoints` adayları | `register-report`, `generate-excel-report`, `AnalysisResultHubPDFService` | Giriş seçimleri, queued job, snapshot, output asset, download ve retry aynı kapsam. Worker'ın service role kullanması müşteri yetkisinin yerine geçmez. | D/G |
| Özet/arama/bildirim: `score_snapshots`, `portfolio_projections/entries`, `notification_jobs/episodes` adayları ve pilot tracking | `NovaStatisticsService`, `NovaDocumentTrackingService`, `NovaNoticeService` | Aggregate, cursor, count, search, deep-link, event payload scope. Sonuçları client'ta gizlemek yetmez. | D/E |
| Kişisel not: `personal_notes`, `note_items`, `personal_reminders` | Notebook/sync RPC adayları | Kişisel içerik OSGB'ye paylaşılmaz; yönetici private notu arama/brief'te uzmana sızmaz. | D/J |
| Kota/billing: `quota_reservations/settlements`, `billing_lifecycle_*`, `public.user_subscriptions` | RevenueCat / sync / webhook / legacy quota RPC | Personal hak ve workspace hakkı ayrı otorite; shadow kayıt purchased wallet değildir. Tek store transaction tek grant. | G/H/I |
| Audit/dispatch | `personnel_audit/receipts/outbox`, `directory_events/outbox`, `event_deliveries`, `consumer_receipts` | Mevcut dispatcher/receipt framework | Workspace, actor, company ayrı; ledger/audit güncelleme yerine yeni olay. Workspace kuruluşu için company zorunlu altyapıya sahte firma yazılmaz. | B/D |
| Admin | `public.admin_users/admin_audit_logs`, `private_isg.admin_*` adayları | Mevcut backend; panel frontend konumu doğrulanmadı | Global grant + güncel yetki + MFA/reason + hedef workspace + audit. Workspace owner global admin değildir. | F |
| Silme/retention | Auth/profile/company FK zinciri; file assets | `account-deletion-complete`, `retention-cleanup`, deletion queue | Uzman ayrıldı diye OSGB firmasını/geçmişini/blob'larını silme; kişisel silme ve kurumsal retention ayrı. | C/D/K |

## Hedef rol matrisi

Bu tablo henüz çalışan bir permission implementasyonu değil; test sözleşmesidir.

| İşlem | Personal owner | OSGB owner/admin | Atanmış aktif expert | Atanmamış/suspended expert | Platform destek/admin |
|---|---|---|---|---|---|
| Personal firma/dosya | Kendi scope'u | OSGB rolü erişim vermez | OSGB rolü erişim vermez | Yok | Yalnız ayrı yetkili destek komutu |
| OSGB firma listesi/detay | Üyelik yoksa yok | Workspace portföyü | Yalnız aktif atandığı firmalar | Yok | Global grant'e bağlı dar endpoint |
| Firma operasyonu | Legacy hakları | Domain izni kapsamında kendi aktörüyle | Atanmış firma + domain izni | Yok | Reason/MFA/audit'li whitelist komutu |
| Davet/rol/askıya alma | Personal tek owner | Yetkili yönetici; son owner korunur | Yok | Yok | Ayrı global komut |
| Satın alma/kredi | Kendi store binding'i | Yetkili purchaser | Workspace kredi kotası kadar kullanım | Yok | Finansal kayıt düzenleme yok; audit'li karşı hareket |
| Uzman devir | Uygulanmaz | Aynı OSGB, preview/version kontrolü | Yönetim hakkı yok | Yok | Ayrı auditable komut |

Admin rolünün owner değiştirme, yönetici davet etme ve billing yapma alt izinleri Faz B/H sözleşmesinde açık whitelist ile tanımlanır; genel `role != expert` kontrolü kullanılmaz.

## UI ve asenkron erişim sözleşmesi

- Cache key: user + workspace + membership/permission revision + company + query/version. Auth session freshness ayrı doğrulanır.
- Workspace switch: önce eski scoped görünümü kapat; task/subscription'ları iptal et, epoch artır; geç gelen eski cevabı reddet. Aynı kullanıcı olduğu için eski cevabı kabul etme.
- Mevcut records-changed sinyali user bazlı; workspace scope eklenmeli. Keychain mutation journal'da workspace'ler çakışmamalı, eski personal retry anahtarları güvenli compatibility ile okunmalı.
- Mevcut realtime subscription bulunduğu/eklendiği her noktada kanal ve payload yetkisi gözden geçirilir. Kaynakta literal aramada sonuç bulunmaması sistemde realtime yok kanıtı değildir.
- İzin iptalinde yeni RPC/export/download/job yetkilendirmesi reddedilir. Daha önce verilmiş signed URL'nin anında iptal edildiği vaat edilmez; kısa TTL veya yetkilendiren proxy kararı G/K'dadır.

## Zorunlu negatif fixture seti

A/B OSGB, personal P, her OSGB'de owner/admin/iki expert, çoklu-workspace kullanıcı, suspended üye, atanmamış firma ve ayrı platform admin. Aynı user iki workspace'teyken özellikle test et.

Her domain için: başka workspace ID'siyle read/write/detail/export/search/count; aynı workspace başka company child ID'si; role/actor spoofing; revoked membership + eski cursor/job/cache; legacy workspace'siz çağrı; audit insert failure ile atomik rollback. Gerçek authenticated/anon rolleriyle RLS ve tüm permissive policy bileşimi test edilir. Service role başarı testi izolasyon kanıtı sayılmaz.
