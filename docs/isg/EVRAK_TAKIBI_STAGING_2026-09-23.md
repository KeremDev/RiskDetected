# Evrak Takibi v2 — staging uygulama kaydı

- Hedef: OSGB pilot staging `qlymhrrlhklcudveknih`. Production'a bu işlemde dokunulmadı.
- SQL: `supabase/pilot-release/candidates/20260923190000_isg_followup_documents_v2.sql`.
- Migration kaydı: `20260923190000_isg_followup_documents_v2`.
- SQL MD5: `3d60fa29eec8e1ff3f93f6da121b63f2`; staging migration kaydındaki `statements[1]` aynı özeti verdi.
- Önce `BEGIN ... ROLLBACK` ile fonksiyon ve OSGB erişim listesi denendi. Kalıcı uygulama, SQL ve migration kaydını aynı işlemde tamamladı.
- Son kontrol: RPC mevcut; `authenticated` çalıştırabilir, `anon` çalıştıramaz; OSGB expert RPC erişim listesinde v2 bulunuyor.
- İstemci kontrolleri: iOS simülatör derlemesi ve Android `:feature:nova:compileDebugKotlin` geçti. Gerçek staging oturumuyla ekran akışı ayrıca denenmedi.

Repo kökündeki migration zinciri ile pilot release adayları ayrı tutulur. Bu uygulama için genel `supabase db push` kullanılmadı.
