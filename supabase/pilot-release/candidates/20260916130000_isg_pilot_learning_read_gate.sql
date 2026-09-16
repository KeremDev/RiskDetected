-- Pilot education is independent of P07 attendance/exam rollout. This read projection
-- retains the process/session/pilot/company/employee gates and never opens P07 writes.
SET LOCAL lock_timeout='1s';
DO $fix$
DECLARE definition text; old_clause text:=' IF NOT coalesce((SELECT read_enabled FROM private_isg.rollout WHERE feature=''training''),false) THEN RAISE EXCEPTION ''FEATURE_UNAVAILABLE''; END IF;';
BEGIN
 definition:=pg_get_functiondef('private_isg.pilot_employee_learning(uuid,uuid)'::regprocedure);
 IF strpos(definition,old_clause)=0 THEN RAISE EXCEPTION 'LEARNING_BASELINE_CHANGED'; END IF;
 EXECUTE replace(definition,old_clause,' -- Scope is gated by process_guard and the employee ownership check.');
 definition:=pg_get_functiondef('private_isg.notice_kind_available(text)'::regprocedure);
 old_clause:='WHEN p_kind=''training'' THEN coalesce((SELECT read_enabled FROM private_isg.rollout WHERE feature=''training''),false)';
 IF strpos(definition,old_clause)=0 THEN RAISE EXCEPTION 'NOTICE_BASELINE_CHANGED'; END IF;
 EXECUTE replace(definition,old_clause,'WHEN p_kind=''training'' THEN coalesce((SELECT enabled FROM private_isg.education_controls WHERE key=''catalog_v1''),false)');
END $fix$;
NOTIFY pgrst,'reload schema';
