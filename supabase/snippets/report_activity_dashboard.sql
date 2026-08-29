-- Supabase SQL Editor: son 30 gündeki kullanıcı bazlı rapor hareketleri.
select *
from public.admin_report_activity_v1(
  p_days => 30,
  p_limit => 500,
  p_offset => 0,
  p_user_id => null,
  p_event_name => null,
  p_report_scope => null
);

-- Örnek filtreler:
-- p_event_name: 'report_created' | 'report_downloaded' | 'report_download_failed'
-- p_report_scope: 'standard' | 'risk_analysis' |
--                 'expert_recommendations' | 'approved_notebook'
