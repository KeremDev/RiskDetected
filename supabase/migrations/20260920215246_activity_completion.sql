-- Transactional row journal for the canonical shared expert modules.
-- Raw rows are used only inside the trigger, never persisted in the journal.
ALTER TABLE private_isg.business_activity_events ADD COLUMN transaction_id bigint;
ALTER TABLE private_isg.business_activity_events ADD COLUMN stages jsonb NOT NULL DEFAULT '[]';
CREATE INDEX business_activity_transaction ON private_isg.business_activity_events(transaction_id,actor_user_id);

CREATE OR REPLACE FUNCTION private_isg.activity_safe_changes(p_before jsonb,p_after jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('field',k,'before',p_before->k,'after',p_after->k) ORDER BY k),'[]')
 FROM unnest(ARRAY['status','state','hazard_class','role','is_primary','starts_on','ends_on','ends_before',
 'due_on','valid_until','completed_at','employee_count','declared_employee_count','duration_minutes',
 'planned_on','performed_on','held_on','visited_on','quantity','is_archived','is_deleted','severity']) k
 WHERE p_before->k IS DISTINCT FROM p_after->k
 AND (p_before->k IS NULL OR jsonb_typeof(p_before->k) IN ('string','number','boolean','null'))
 AND (p_after->k IS NULL OR jsonb_typeof(p_after->k) IN ('string','number','boolean','null'))
 AND coalesce(length(p_before->>k),0)<=64 AND coalesce(length(p_after->>k),0)<=64;
$$;

CREATE FUNCTION private_isg.activity_business_row() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE b jsonb; a jsonb; r jsonb; actor uuid:=auth.uid(); company uuid; workspace uuid;
 entity uuid; event_key text; delta jsonb; verb text; normalized text:=TG_ARGV[0];
 technical text[]:=ARRAY['updated_at','version','record_version','edit_revision','updated_by_user_id',
 'last_worker_error','worker_attempt_count','completion_push_sent_at','report_ready_push_sent_at'];
BEGIN
 IF TG_OP<>'INSERT' THEN b:=to_jsonb(OLD); END IF;
 IF TG_OP<>'DELETE' THEN a:=to_jsonb(NEW); END IF;
 r:=coalesce(a,b);
 -- Anonymous maintenance is not an expert operation.
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM auth.users WHERE id=actor) THEN RETURN coalesce(NEW,OLD); END IF;
 -- Draft editing, automatic timestamps and retries are not business events.
 IF a IS NOT NULL AND coalesce(a->>'state','') IN ('draft','editing') THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' AND (b-technical) IS NOT DISTINCT FROM (a-technical) THEN RETURN NEW; END IF;
 entity:=nullif(r->>TG_ARGV[1],'')::uuid;
 company:=CASE WHEN normalized='company' THEN entity ELSE nullif(r->>'company_id','')::uuid END;
 workspace:=coalesce(nullif(r->>'workspace_id','')::uuid,nullif(current_setting('private_isg.expert_workspace',true),'')::uuid);
 IF company IS NULL AND TG_TABLE_NAME='document_versions' THEN
   SELECT d.company_id INTO company FROM private_isg.documents d WHERE d.document_id=entity;
 END IF;
 IF workspace IS NULL AND company IS NOT NULL THEN
   SELECT c.workspace_id INTO workspace FROM private_isg.workspace_companies c WHERE c.id=company OR c.legacy_company_id=company LIMIT 1;
 END IF;
 delta:=private_isg.activity_safe_changes(b,a);
 -- For edited free-text fields expose only that protected details changed, never their values.
 IF delta='[]' AND TG_OP='UPDATE' THEN delta:='[{"field":"protected_details","before":"•••","after":"•••"}]'; END IF;
 verb:=CASE WHEN TG_OP='INSERT' THEN 'create' WHEN TG_OP='DELETE' THEN 'delete'
   WHEN a->>'is_archived'='true' AND b->>'is_archived' IS DISTINCT FROM 'true' THEN 'archive'
   WHEN a->>'is_deleted'='true' AND b->>'is_deleted' IS DISTINCT FROM 'true' THEN 'delete'
   ELSE 'update' END;
 -- Multiple writes to one record in the same accepted transaction are one operation.
 event_key:='row:'||txid_current()||':'||actor||':'||normalized||':'||coalesce(entity::text,company::text,TG_TABLE_NAME);
 INSERT INTO private_isg.business_activity_events(source_key,actor_user_id,workspace_id,company_id,
 action,entity_type,entity_id,correlation_id,changes,transaction_id)
 VALUES(event_key,actor,workspace,company,normalized||'.'||verb,normalized,entity,NULL,delta,txid_current())
 ON CONFLICT(source_key) DO UPDATE SET changes=(
   SELECT coalesce(jsonb_agg(jsonb_build_object('field',field,'before',first_value,'after',last_value)),'[]')
   FROM (SELECT DISTINCT ON (x->>'field') x->>'field' field,
      coalesce((SELECT o->'before' FROM jsonb_array_elements(private_isg.business_activity_events.changes) o WHERE o->>'field'=x->>'field'),x->'before') first_value,
      x->'after' last_value
     FROM jsonb_array_elements(excluded.changes||private_isg.business_activity_events.changes) WITH ORDINALITY d(x,n)
     ORDER BY x->>'field',n) fields);
 RETURN coalesce(NEW,OLD);
END $$;
REVOKE ALL ON FUNCTION private_isg.activity_business_row() FROM PUBLIC,anon,authenticated,service_role;

-- Explicit registry, intentionally not inferred from every table in the database.
CREATE TABLE private_isg.business_activity_sources(table_schema text NOT NULL,table_name text NOT NULL,entity_type text NOT NULL,id_field text NOT NULL,PRIMARY KEY(table_schema,table_name));
ALTER TABLE private_isg.business_activity_sources ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.business_activity_sources FROM PUBLIC,anon,authenticated;
INSERT INTO private_isg.business_activity_sources VALUES
 ('public','companies','company','id'),
 ('private_isg','employees','personnel','id'),
 ('private_isg','workplaces','workplace','id'),
 ('private_isg','departments','department','id'),
 ('private_isg','job_roles','job_role','id'),
 ('private_isg','employee_assignments','assignment','id'),
 ('private_isg','appointments','assignment','appointment_id'),
 ('private_isg','checklist_runs','checklist','run_id'),
 ('private_isg','documents','document','document_id'),
 ('private_isg','document_versions','document','document_id'),
 ('private_isg','drill_records','drill','drill_id'),
 ('private_isg','emergency_plan_versions','emergency','plan_id'),
 ('private_isg','equipment_items','equipment','equipment_id'),
 ('private_isg','equipment_inspections','inspection','inspection_id'),
 ('private_isg','file_library_entries','file','entry_id'),
 ('private_isg','nonconformities','nonconformity','nonconformity_id'),
 ('private_isg','ppe_handovers','ppe','handover_id'),
 ('private_isg','ppe_returns','ppe','return_id'),
 ('private_isg','risk_assessment_versions','risk','assessment_id'),
 ('private_isg','site_visits','visit','visit_id'),
 ('private_isg','annual_work_plans','plan','plan_id'),
 ('private_isg','board_meetings','board','meeting_id'),
 ('private_isg','katip_contracts','contract','contract_id'),
 ('private_isg','work_permit_forms','permit','permit_id'),
 ('private_isg','contractor_organizations','contractor','id'),
 ('private_isg','contractor_engagements','contract','id'),
 ('private_isg','pilot_training_records','training','id'),
 ('private_isg','pilot_training_sessions','training_session','id');
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT * FROM private_isg.business_activity_sources LOOP
   EXECUTE format('CREATE TRIGGER business_activity_row AFTER INSERT OR UPDATE OR DELETE ON %I.%I FOR EACH ROW EXECUTE FUNCTION private_isg.activity_business_row(%L,%L)',r.table_schema,r.table_name,r.entity_type,r.id_field);
 END LOOP;
 -- Receipts remain a fallback for modules whose storage is not a canonical row.
 -- Row-backed operations suppress their receipt at transaction time below.
END $$;

CREATE OR REPLACE FUNCTION private_isg.activity_from_receipt() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r jsonb:=to_jsonb(NEW); answer jsonb:=r->'response'; actor uuid;
 company uuid; workspace uuid; action text; entity uuid; payload jsonb;
BEGIN
 actor:=coalesce(r->>'actor_id',r->>'owner_id')::uuid;
 IF actor IS NULL THEN RETURN NEW; END IF;
 IF EXISTS(SELECT 1 FROM private_isg.business_activity_events WHERE transaction_id=txid_current() AND actor_user_id=actor) THEN RETURN NEW; END IF;
 action:=coalesce(answer->>'action',answer->>'state','save');
 IF action ~ '(draft|autosave|read|search|filter|conflict)' OR coalesce((answer->>'replayed')::boolean,false) THEN RETURN NEW; END IF;
 payload:=coalesce(answer->'row',answer->'answer',answer->'result',answer);
 company:=coalesce(r->>'company_id',answer->>'company_id',payload->>'company_id')::uuid;
 workspace:=nullif(current_setting('private_isg.expert_workspace',true),'')::uuid;
 IF workspace IS NULL AND company IS NOT NULL THEN
   SELECT workspace_id INTO workspace FROM private_isg.workspace_companies WHERE legacy_company_id=company OR id=company LIMIT 1;
 END IF;
 entity:=coalesce(payload->>TG_ARGV[1],payload->>'id',answer->>TG_ARGV[1])::uuid;
 INSERT INTO private_isg.business_activity_events(source_key,actor_user_id,workspace_id,company_id,action,entity_type,entity_id,correlation_id,changes,transaction_id)
 VALUES(TG_TABLE_NAME||':'||encode(sha256(convert_to(actor::text||':'||(r->>'mutation_id'),'UTF8')),'hex'),actor,workspace,company,
 TG_ARGV[0]||'.'||action,TG_ARGV[0],entity,coalesce(r->>'operation_id',r->>'mutation_id')::uuid,
 private_isg.activity_safe_changes(NULL,payload),txid_current()) ON CONFLICT(source_key) DO NOTHING;
 RETURN NEW;
END $$;

-- Workspace audit remains authoritative for invitations, membership and old workspace-only modules.
CREATE OR REPLACE FUNCTION private_isg.activity_from_workspace_audit() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NEW.action ~ '(^|[._])(read|search|filter|autosave|draft)([._]|$)' OR NEW.action LIKE 'notice.mark%' THEN RETURN NEW; END IF;
 IF NEW.entity_type IN ('ai_job','export_job') OR NEW.action IN ('ai.submit','analysis.commit','export.create','export.complete') THEN RETURN NEW; END IF;
 IF EXISTS(SELECT 1 FROM private_isg.business_activity_events WHERE transaction_id=txid_current() AND actor_user_id=NEW.actor_user_id
    AND (entity_id=NEW.entity_id OR entity_type=NEW.entity_type)) THEN RETURN NEW; END IF;
 INSERT INTO private_isg.business_activity_events(source_key,actor_user_id,workspace_id,company_id,action,entity_type,entity_id,correlation_id,changes,created_at,transaction_id)
 VALUES('workspace_audit:'||NEW.id,NEW.actor_user_id,NEW.workspace_id,
 CASE WHEN NEW.entity_type='company' THEN NEW.entity_id ELSE nullif(NEW.after_state->>'company_id','')::uuid END,
 NEW.action,NEW.entity_type,NEW.entity_id,NEW.correlation_id,
 private_isg.activity_safe_changes(NEW.before_state,NEW.after_state),NEW.created_at,txid_current())
 ON CONFLICT(source_key) DO NOTHING;
 RETURN NEW;
END $$;

-- Async request and completion are one timeline item with a safe lifecycle.
CREATE FUNCTION private_isg.activity_async_job() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a jsonb:=to_jsonb(NEW); b jsonb; actor uuid; phase text; domain text:=TG_ARGV[0]; entity uuid; workspace uuid;
BEGIN
 IF TG_OP='UPDATE' THEN b:=to_jsonb(OLD); END IF;
 phase:=coalesce(a->>'status','succeeded');
 IF TG_OP='UPDATE' AND b->>'status' IS NOT DISTINCT FROM a->>'status' THEN RETURN NEW; END IF;
 actor:=coalesce(a->>'actor_user_id',a->>'user_id')::uuid;
 IF actor IS NULL THEN RETURN NEW; END IF;
 entity:=(a->>'id')::uuid; workspace:=nullif(a->>'workspace_id','')::uuid;
 INSERT INTO private_isg.business_activity_events(source_key,actor_user_id,workspace_id,company_id,action,entity_type,entity_id,correlation_id,changes,stages,transaction_id)
 VALUES('job:'||TG_TABLE_NAME||':'||entity,actor,workspace,nullif(a->>'company_id','')::uuid,domain||'.'||phase,domain,entity,entity,
 private_isg.activity_safe_changes(NULL,jsonb_build_object('status',phase)),
 jsonb_build_array(jsonb_build_object('status',phase,'at',clock_timestamp())),txid_current())
 ON CONFLICT(source_key) DO UPDATE SET action=excluded.action,changes=private_isg.activity_safe_changes(b,a),
 stages=private_isg.business_activity_events.stages||excluded.stages;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private_isg.activity_async_job() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER business_activity_async AFTER INSERT OR UPDATE ON private_isg.workspace_ai_jobs FOR EACH ROW EXECUTE FUNCTION private_isg.activity_async_job('analysis');
CREATE TRIGGER business_activity_async AFTER INSERT OR UPDATE ON private_isg.workspace_export_jobs FOR EACH ROW EXECUTE FUNCTION private_isg.activity_async_job('report');
CREATE TRIGGER business_activity_async AFTER INSERT OR UPDATE ON public.analyses FOR EACH ROW EXECUTE FUNCTION private_isg.activity_async_job('analysis');
CREATE TRIGGER business_activity_async AFTER INSERT OR UPDATE ON public.reports FOR EACH ROW EXECUTE FUNCTION private_isg.activity_async_job('report');

CREATE OR REPLACE FUNCTION private_isg.prune_expert_activity() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 DELETE FROM private_isg.usage_intervals WHERE ends_at<clock_timestamp()-interval '24 months';
 DELETE FROM private_isg.business_activity_events WHERE created_at<clock_timestamp()-interval '5 years';
 DELETE FROM private_isg.workspace_audit WHERE created_at<clock_timestamp()-interval '5 years';
 DELETE FROM private_isg.notebook_deliveries WHERE finished_at<clock_timestamp()-interval '24 months';
END $$;

-- Deployment is staging-only. Vault values never appear in migration output or client responses.
SELECT cron.schedule('isg-notebook-reminders-staging','* * * * *',$job$
 SELECT net.http_post(
   url:=(SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='project_url')||'/functions/v1/process-notebook-reminders',
   headers:=jsonb_build_object('Content-Type','application/json','x-isg-worker-secret',
     (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='isg_workspace_jobs_secret')),
   body:='{}'::jsonb,timeout_milliseconds:=50000);
$job$);
SELECT cron.schedule('isg-expert-activity-retention','35 2 * * *','SELECT private_isg.prune_expert_activity()');
