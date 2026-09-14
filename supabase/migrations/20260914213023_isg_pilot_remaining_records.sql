SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.module_registry DROP CONSTRAINT module_registry_module_check;
ALTER TABLE private_isg.module_registry ADD CONSTRAINT module_registry_module_check CHECK(module IN ('emergency_plan','drill','equipment','ppe','appointment','katip_contract','annual_work_plan','board','work_permit','site_visit','contractor'));
INSERT INTO private_isg.module_registry(module) VALUES ('katip_contract'),('annual_work_plan'),('board'),('work_permit'),('site_visit'),('contractor');
CREATE TABLE private_isg.katip_contracts (
  contract_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  counterparty text NOT NULL CHECK(btrim(counterparty)<>'' AND length(counterparty)<=200),
  expert_contact text NOT NULL CHECK(btrim(expert_contact)<>'' AND length(expert_contact)<=200),
  scope text NOT NULL CHECK(btrim(scope)<>'' AND length(scope)<=300),
  starts_on date NOT NULL CHECK(isfinite(starts_on)),
  ends_before date CHECK(ends_before IS NULL OR isfinite(ends_before)),
  -- An open ended contract is its own state, not an unknown end date.
  term_state text GENERATED ALWAYS AS(CASE WHEN ends_before IS NULL THEN 'open_ended' ELSE 'fixed_term' END) STORED,
  asset_id uuid CHECK(asset_id IS NULL),
  state text NOT NULL DEFAULT 'active' CHECK(state IN ('active','archived')),
  official_integration boolean NOT NULL DEFAULT false CHECK(NOT official_integration),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),

  CHECK(ends_before IS NULL OR ends_before>starts_on),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
ALTER TABLE private_isg.katip_contracts ADD COLUMN is_deleted boolean NOT NULL DEFAULT false;
ALTER TABLE private_isg.katip_contracts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.katip_contracts FROM PUBLIC,anon,authenticated,service_role;
CREATE UNIQUE INDEX katip_contracts_active_identity ON private_isg.katip_contracts(company_id,counterparty,scope,starts_on) WHERE NOT is_deleted;
CREATE TABLE private_isg.annual_work_plans (
  plan_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  plan_year integer NOT NULL CHECK(plan_year BETWEEN 2000 AND 2100),
  state text NOT NULL DEFAULT 'active' CHECK(state IN ('active','closed')),
  closed_on date CHECK(closed_on IS NULL OR isfinite(closed_on)),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),

  CHECK((state='closed')=(closed_on IS NOT NULL)),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
ALTER TABLE private_isg.annual_work_plans ADD COLUMN is_deleted boolean NOT NULL DEFAULT false;
ALTER TABLE private_isg.annual_work_plans ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.annual_work_plans FROM PUBLIC,anon,authenticated,service_role;
CREATE UNIQUE INDEX annual_work_plans_active_identity ON private_isg.annual_work_plans(company_id,workplace_id,plan_year) WHERE NOT is_deleted;
CREATE TABLE private_isg.annual_work_plan_items (
  item_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id uuid NOT NULL REFERENCES private_isg.annual_work_plans(plan_id) ON DELETE CASCADE,
  activity text NOT NULL CHECK(btrim(activity)<>'' AND length(activity)<=300),
  responsible_contact text CHECK(responsible_contact IS NULL OR length(responsible_contact)<=200),
  planned_on date NOT NULL CHECK(isfinite(planned_on)),
  performed_on date CHECK(performed_on IS NULL OR isfinite(performed_on)),
  state text NOT NULL DEFAULT 'planned' CHECK(state IN ('planned','performed','carried_over','cancelled')),
  carry_over_reason text CHECK(carry_over_reason IS NULL OR length(carry_over_reason) BETWEEN 10 AND 1000),
  carried_to_plan_id uuid REFERENCES private_isg.annual_work_plans(plan_id),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),

  CHECK((state='performed')=(performed_on IS NOT NULL)),
  CHECK((state='carried_over')=(carry_over_reason IS NOT NULL)),
  CHECK(carried_to_plan_id IS NULL OR state='carried_over')
);
ALTER TABLE private_isg.annual_work_plan_items ADD COLUMN is_deleted boolean NOT NULL DEFAULT false;
ALTER TABLE private_isg.annual_work_plan_items ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.annual_work_plan_items FROM PUBLIC,anon,authenticated,service_role;
CREATE UNIQUE INDEX annual_work_plan_items_active_identity ON private_isg.annual_work_plan_items(plan_id,activity,planned_on) WHERE NOT is_deleted;
CREATE TABLE private_isg.board_meetings (
  meeting_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  applicability text NOT NULL CHECK(applicability IN ('mandatory','voluntary')),
  counts_towards_legal_score boolean NOT NULL,
  planned_on date NOT NULL CHECK(isfinite(planned_on)),
  held_on date CHECK(held_on IS NULL OR isfinite(held_on)),
  agenda jsonb NOT NULL, attendance jsonb,
  minutes_asset_id uuid CHECK(minutes_asset_id IS NULL),
  state text NOT NULL DEFAULT 'planned' CHECK(state IN ('planned','held','cancelled')),
  cancelled_reason text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK(counts_towards_legal_score=(applicability='mandatory')),
  CHECK((state='held')=(held_on IS NOT NULL)),
  CHECK((state='held')=(attendance IS NOT NULL)),
  CHECK((state='cancelled')=(cancelled_reason IS NOT NULL)),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
ALTER TABLE private_isg.board_meetings ADD COLUMN is_deleted boolean NOT NULL DEFAULT false;
ALTER TABLE private_isg.board_meetings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.board_meetings FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE private_isg.board_decisions (
  decision_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id uuid NOT NULL REFERENCES private_isg.board_meetings(meeting_id) ON DELETE CASCADE,
  decision_no integer NOT NULL CHECK(decision_no BETWEEN 1 AND 500),
  decision_text text NOT NULL CHECK(btrim(decision_text)<>'' AND length(decision_text)<=2000),
  responsible_contact text CHECK(responsible_contact IS NULL OR length(responsible_contact)<=200),
  due_on date CHECK(due_on IS NULL OR isfinite(due_on)),
  state text NOT NULL DEFAULT 'open' CHECK(state IN ('open','done','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(meeting_id,decision_no)
);
ALTER TABLE private_isg.board_decisions ADD COLUMN is_deleted boolean NOT NULL DEFAULT false;
ALTER TABLE private_isg.board_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.board_decisions FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE private_isg.work_permit_forms (
  permit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  template_code text NOT NULL CHECK(template_code ~ '^[a-z][a-z0-9_]{2,60}$'),
  template_version integer NOT NULL CHECK(template_version BETWEEN 1 AND 1000),
  job_description text NOT NULL CHECK(btrim(job_description)<>'' AND length(job_description)<=1000),
  parties jsonb NOT NULL,
  planned_on date NOT NULL CHECK(isfinite(planned_on)),
  state text NOT NULL DEFAULT 'draft' CHECK(state IN ('draft','rendered','archived')),
  rendered_asset_id uuid CHECK(rendered_asset_id IS NULL),
  signed_copy boolean NOT NULL DEFAULT false,
  authorises_work boolean NOT NULL DEFAULT false CHECK(NOT authorises_work),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),

  CHECK(NOT signed_copy OR rendered_asset_id IS NOT NULL),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
ALTER TABLE private_isg.work_permit_forms ADD COLUMN is_deleted boolean NOT NULL DEFAULT false;
ALTER TABLE private_isg.work_permit_forms ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.work_permit_forms FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE private_isg.site_visits (
  visit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  visited_on date NOT NULL CHECK(isfinite(visited_on)),
  location_note text CHECK(location_note IS NULL OR length(location_note)<=300),
  expert_note text NOT NULL CHECK(btrim(expert_note)<>'' AND length(expert_note)<=4000),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
ALTER TABLE private_isg.site_visits ADD COLUMN is_deleted boolean NOT NULL DEFAULT false;
ALTER TABLE private_isg.site_visits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.site_visits FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE private_isg.site_visit_observations (
  observation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL REFERENCES private_isg.site_visits(visit_id) ON DELETE CASCADE,
  note text NOT NULL CHECK(btrim(note)<>'' AND length(note)<=2000),
  evidence_asset_id uuid CHECK(evidence_asset_id IS NULL),
  nonconformity_id uuid CHECK(nonconformity_id IS NULL),
  external_ref text, created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(visit_id,external_ref)
);
ALTER TABLE private_isg.site_visit_observations ADD COLUMN is_deleted boolean NOT NULL DEFAULT false;
ALTER TABLE private_isg.site_visit_observations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.site_visit_observations FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE private_isg.katip_contracts ADD COLUMN declared_monthly_minutes integer CHECK(declared_monthly_minutes BETWEEN 1 AND 100000), ADD COLUMN declared_note text, ADD COLUMN contract_location text;
ALTER TABLE private_isg.work_permit_forms ADD COLUMN work_location text, ADD COLUMN starts_at timestamptz, ADD COLUMN ends_at timestamptz, ADD COLUMN risk_precautions text;
ALTER TABLE private_isg.site_visits ADD COLUMN responsible_contact text;
ALTER TABLE private_isg.contractor_organizations ADD COLUMN contact text, ADD COLUMN identifiers text, ADD COLUMN notes text;
ALTER TABLE private_isg.contractor_engagements ADD COLUMN is_deleted boolean NOT NULL DEFAULT false;
CREATE TABLE private_isg.process_record_meta (
 kind text NOT NULL,record_id uuid NOT NULL,company_id uuid NOT NULL,document_id uuid REFERENCES private_isg.document_obligations(obligation_id),
 related_kind text,related_id uuid,export_snapshot jsonb,PRIMARY KEY(kind,record_id));
CREATE TABLE private_isg.process_record_history (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),kind text NOT NULL,record_id uuid NOT NULL,company_id uuid NOT NULL,actor_id uuid NOT NULL,before_snapshot jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE private_isg.process_record_meta ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.process_record_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.process_record_meta,private_isg.process_record_history FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX process_meta_company_idx ON private_isg.process_record_meta(company_id);
CREATE INDEX process_meta_doc_idx ON private_isg.process_record_meta(document_id);
CREATE INDEX process_history_record_idx ON private_isg.process_record_history(kind,record_id);

CREATE FUNCTION private_isg.process_spec(p_kind text) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$ BEGIN
RETURN CASE p_kind
 WHEN 'katip_contract' THEN '{"table":"katip_contracts","id":"contract_id","module":"katip_contract","title":"counterparty","date":"starts_on","fields":["workplace_id","counterparty","expert_contact","scope","starts_on","ends_before","declared_monthly_minutes","declared_note","contract_location"]}'::jsonb
 WHEN 'annual_work_plan' THEN '{"table":"annual_work_plans","id":"plan_id","module":"annual_work_plan","title":"plan_year","date":"created_at","fields":["workplace_id","plan_year"]}'::jsonb
 WHEN 'annual_work_item' THEN '{"table":"annual_work_plan_items","id":"item_id","module":"annual_work_plan","parent":"plan_id","parent_kind":"annual_work_plan","title":"activity","date":"planned_on","fields":["plan_id","activity","responsible_contact","planned_on","performed_on","state","carry_over_reason"]}'::jsonb
 WHEN 'board' THEN '{"table":"board_meetings","id":"meeting_id","module":"board","title":"agenda","date":"planned_on","fields":["workplace_id","applicability","planned_on","held_on","agenda","attendance","state","cancelled_reason"]}'::jsonb
 WHEN 'board_decision' THEN '{"table":"board_decisions","id":"decision_id","module":"board","parent":"meeting_id","parent_kind":"board","title":"decision_text","date":"due_on","fields":["meeting_id","decision_no","decision_text","responsible_contact","due_on","state"]}'::jsonb
 WHEN 'site_visit' THEN '{"table":"site_visits","id":"visit_id","module":"site_visit","title":"expert_note","date":"visited_on","fields":["workplace_id","visited_on","location_note","expert_note","responsible_contact"]}'::jsonb
 WHEN 'site_observation' THEN '{"table":"site_visit_observations","id":"observation_id","module":"site_visit","parent":"visit_id","parent_kind":"site_visit","title":"note","date":"created_at","fields":["visit_id","note","external_ref"]}'::jsonb
 WHEN 'work_permit' THEN '{"table":"work_permit_forms","id":"permit_id","module":"work_permit","title":"job_description","date":"planned_on","fields":["workplace_id","template_code","job_description","parties","planned_on","work_location","starts_at","ends_at","risk_precautions"]}'::jsonb
 WHEN 'contractor' THEN '{"table":"contractor_organizations","id":"id","module":"contractor","title":"name","date":"code","fields":["code","name","relationship","contact","identifiers","notes"]}'::jsonb
 WHEN 'contractor_engagement' THEN '{"table":"contractor_engagements","id":"id","module":"contractor","title":"description","date":"starts_on","fields":["organization_id","workplace_id","starts_on","ends_before","description"]}'::jsonb
 ELSE NULL END;
END $$;
CREATE FUNCTION private_isg.process_guard(p_kind text,p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SET search_path='' AS $$ DECLARE actor uuid:=private_isg.active_actor(); spec jsonb:=private_isg.process_spec(p_kind); BEGIN
IF spec IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
IF NOT private_isg.p05_pilot_account_enabled(actor,p_write) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
PERFORM private_isg.module_gate(spec->>'module',p_write);
IF p_company IS NOT NULL AND NOT private_isg.p05_pilot_can_read(actor,p_company) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
IF p_company IS NOT NULL THEN
 PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND (NOT p_write OR NOT is_archived) FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
END IF;
IF p_write THEN
 IF p_company IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 IF private.user_plan_tier(actor) NOT IN ('plus','pro') OR NOT EXISTS(SELECT 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND status IN ('active','trialing','grace_period') AND (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp())) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
END IF;
RETURN actor; END $$;
CREATE FUNCTION private_isg.process_row(p_kind text,p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$ DECLARE spec jsonb:=private_isg.process_spec(p_kind); row_ jsonb; parent jsonb; company uuid; BEGIN
IF spec IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
EXECUTE format('SELECT to_jsonb(t) FROM private_isg.%I t WHERE %I=$1',spec->>'table',spec->>'id') INTO row_ USING p_id;
IF row_ IS NULL OR coalesce((row_->>'is_deleted')::boolean,false) OR coalesce((row_->>'is_archived')::boolean,false) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
IF spec ? 'parent' THEN parent:=private_isg.process_row(spec->>'parent_kind',(row_->>(spec->>'parent'))::uuid);company:=(parent->>'company_id')::uuid;
ELSE company:=(row_->>'company_id')::uuid; END IF;
PERFORM private_isg.process_guard(p_kind,company,false);
RETURN jsonb_build_object('id',p_id,'company_id',company,'company_name',(SELECT name FROM public.companies WHERE id=company),'title',coalesce(row_->>(spec->>'title'),p_kind),'date',coalesce(row_->>(spec->>'date'),''),'values',row_,'workplace_name',(SELECT name FROM private_isg.workplaces WHERE id=(row_->>'workplace_id')::uuid AND company_id=company),'expected',md5((row_||coalesce((SELECT jsonb_build_object('document_id',m.document_id,'related_kind',m.related_kind,'related_id',m.related_id) FROM private_isg.process_record_meta m WHERE m.kind=p_kind AND m.record_id=p_id),jsonb_build_object('document_id',NULL,'related_kind',NULL,'related_id',NULL)))::text),'document_id',(SELECT document_id FROM private_isg.process_record_meta WHERE kind=p_kind AND record_id=p_id),'related_kind',(SELECT related_kind FROM private_isg.process_record_meta WHERE kind=p_kind AND record_id=p_id),'related_id',(SELECT related_id FROM private_isg.process_record_meta WHERE kind=p_kind AND record_id=p_id));
END $$;
CREATE FUNCTION private_isg.process_read(p_kind text,p_company uuid,p_id uuid,p_parent uuid,p_query text,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ DECLARE actor uuid; spec jsonb:=private_isg.process_spec(p_kind); ids uuid[]; rows_ jsonb:='[]'; id_ uuid; join_ text:=''; where_ text; parent_spec jsonb; BEGIN
actor:=private_isg.process_guard(p_kind,p_company,false);
IF p_id IS NOT NULL THEN RETURN private_isg.process_row(p_kind,p_id); END IF;
IF p_offset IS NULL OR p_offset<0 OR p_offset>100000 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
IF spec ? 'parent' THEN
 parent_spec:=private_isg.process_spec(spec->>'parent_kind');
 join_:=format(' JOIN private_isg.%I p ON p.%I=t.%I ',parent_spec->>'table',parent_spec->>'id',spec->>'parent');
 where_:='p.company_id';
ELSE where_:='t.company_id'; END IF;
EXECUTE format('SELECT array_agg(id) FROM (SELECT t.%I id FROM private_isg.%I t %s JOIN public.companies c ON c.id=%s WHERE c.user_id=$1 AND private_isg.p05_pilot_can_read($1,c.id) AND ($2 IS NULL OR c.id=$2) AND NOT coalesce((to_jsonb(t)->>''is_deleted'')::boolean,false) AND NOT coalesce((to_jsonb(t)->>''is_archived'')::boolean,false) %s AND ($3 IS NULL OR to_jsonb(t)->>%L ILIKE ''%%''||$3||''%%'') %s ORDER BY t.%I DESC OFFSET $4 LIMIT 21) q',spec->>'id',spec->>'table',join_,where_,CASE WHEN spec ? 'parent' THEN 'AND NOT p.is_deleted' ELSE '' END,spec->>'title',CASE WHEN spec ? 'parent' THEN format('AND ($5 IS NULL OR t.%I=$5)',spec->>'parent') WHEN p_kind='contractor_engagement' THEN 'AND ($5 IS NULL OR t.organization_id=$5)' ELSE '' END,spec->>'id') INTO ids USING actor,p_company,nullif(btrim(p_query),''),p_offset,p_parent;
FOREACH id_ IN ARRAY coalesce(ids[1:20],ARRAY[]::uuid[]) LOOP rows_:=rows_||jsonb_build_array(private_isg.process_row(p_kind,id_)); END LOOP;
RETURN jsonb_build_object('rows',rows_,'has_more',coalesce(cardinality(ids)>20,false),
 'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) ORDER BY name),'[]') FROM private_isg.workplaces WHERE company_id=p_company AND NOT is_archived),
 'employees',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',full_name) ORDER BY full_name),'[]') FROM private_isg.employees WHERE company_id=p_company AND NOT is_archived),
 'documents',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',obligation_id,'name',title) ORDER BY title),'[]') FROM private_isg.document_obligations WHERE company_id=p_company AND NOT is_archived),
 'organizations',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) ORDER BY name),'[]') FROM private_isg.contractor_organizations WHERE company_id=p_company AND NOT is_archived));
END $$;
CREATE FUNCTION private_isg.process_mutate(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE kind text:=p_payload->>'kind'; spec jsonb:=private_isg.process_spec(kind); actor uuid; id_ uuid; row_ jsonb; vals jsonb:=p_payload->'values'; old_ jsonb; result jsonb; parent jsonb; cols text; expr text; key_ text; hash_ bytea; receipt private_isg.module_edit_receipts; doc uuid; other jsonb; today date:=(now() AT TIME ZONE 'Europe/Istanbul')::date; document_ private_isg.documents; stored_ private_isg.document_versions; template_ text; serial_ bigint; version_ integer; source_hash_ text; child_kind_ text; child_spec_ jsonb; child_id_ uuid; children_ jsonb:='[]';
BEGIN
actor:=private_isg.process_guard(kind,p_company,true);
IF p_operation IS NULL OR p_mutation IS NULL OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR octet_length(p_payload::text)>32768 OR p_action IS NULL OR p_action NOT IN ('save','delete','export') OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN ('kind','id','expected','values','document_id','related_kind','related_id')) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
hash_:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':process:'||p_mutation::text,0));
SELECT * INTO receipt FROM private_isg.module_edit_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
IF FOUND THEN IF receipt.request_hash<>hash_ THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF; RETURN receipt.response; END IF;
id_:=(p_payload->>'id')::uuid;
IF id_ IS NOT NULL THEN
 EXECUTE format('SELECT to_jsonb(t) FROM private_isg.%I t WHERE %I=$1 FOR UPDATE',spec->>'table',spec->>'id') INTO old_ USING id_;
 row_:=private_isg.process_row(kind,id_);
 IF (row_->>'company_id')::uuid<>p_company THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 IF row_->>'expected' IS DISTINCT FROM p_payload->>'expected' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
ELSE IF p_action<>'save' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF; END IF;
IF p_action='delete' THEN
 IF kind='annual_work_plan' AND EXISTS(SELECT 1 FROM private_isg.annual_work_plan_items WHERE plan_id=id_ AND NOT is_deleted) OR kind='board' AND EXISTS(SELECT 1 FROM private_isg.board_decisions WHERE meeting_id=id_ AND NOT is_deleted) OR kind='site_visit' AND EXISTS(SELECT 1 FROM private_isg.site_visit_observations WHERE visit_id=id_ AND NOT is_deleted) OR kind='contractor' AND (EXISTS(SELECT 1 FROM private_isg.contractor_engagements WHERE organization_id=id_ AND NOT is_deleted) OR EXISTS(SELECT 1 FROM private_isg.employees WHERE employer_org_id=id_ AND NOT is_archived)) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPENDENT_RECORDS'; END IF;
 EXECUTE format('UPDATE private_isg.%I SET %I=true WHERE %I=$1',spec->>'table',CASE WHEN kind='contractor' THEN 'is_archived' ELSE 'is_deleted' END,spec->>'id') USING id_;
 result:=jsonb_build_object('deleted',true);
ELSIF p_action='export' THEN
 child_kind_:=CASE kind WHEN 'annual_work_plan' THEN 'annual_work_item' WHEN 'board' THEN 'board_decision' WHEN 'site_visit' THEN 'site_observation' END;
 IF child_kind_ IS NOT NULL THEN
  child_spec_:=private_isg.process_spec(child_kind_);
  FOR child_id_ IN EXECUTE format('SELECT %I FROM private_isg.%I WHERE %I=$1 AND NOT is_deleted ORDER BY %I FOR SHARE',child_spec_->>'id',child_spec_->>'table',child_spec_->>'parent',child_spec_->>'id') USING id_ LOOP
   children_:=children_||jsonb_build_array(private_isg.process_row(child_kind_,child_id_));
  END LOOP;
 END IF;
 result:=row_||jsonb_build_object('children',children_,'child_kind',child_kind_,'source','expert_record');
 source_hash_:=md5(result::text); template_:='process_'||kind;
 INSERT INTO private_isg.document_templates(template_code,source_domain,title) VALUES(template_,'module',kind) ON CONFLICT DO NOTHING;
 INSERT INTO private_isg.document_template_versions(template_code,version,status,approved_by,approval_note,published_at) VALUES(template_,1,'published',actor,'Expert-requested record export; blank signatures, no regulatory approval claim',now()) ON CONFLICT DO NOTHING;
 INSERT INTO private_isg.documents(company_id,owner_id,workplace_id,source_domain,source_ref,template_code) VALUES(p_company,actor,(row_->'values'->>'workplace_id')::uuid,'module',kind||':'||id_::text,template_) ON CONFLICT(company_id,source_domain,source_ref,template_code) DO NOTHING;
 SELECT * INTO document_ FROM private_isg.documents WHERE company_id=p_company AND source_domain='module' AND source_ref=kind||':'||id_::text AND template_code=template_ FOR UPDATE;
 SELECT * INTO stored_ FROM private_isg.document_versions WHERE document_id=document_.document_id AND version=document_.current_version;
 IF FOUND AND stored_.snapshot->>'source_hash'=source_hash_ THEN result:=stored_.snapshot;
 ELSE
  INSERT INTO private_isg.education_document_counters(scope,year,next_value) VALUES('MOD',extract(year FROM today)::int,1) ON CONFLICT DO NOTHING;
  UPDATE private_isg.education_document_counters SET next_value=next_value+1 WHERE scope='MOD' AND year=extract(year FROM today)::int RETURNING next_value-1 INTO serial_;
  version_:=document_.current_version+1;
  result:=result||jsonb_build_object('document_id',document_.document_id,'number','MOD-'||extract(year FROM today)::int||'-'||serial_,'revision',version_,'source_hash',source_hash_,'exported_on',today);
  INSERT INTO private_isg.document_versions(document_id,version,template_version,document_no,source_kind,snapshot,snapshot_sha256,finalized_by,finalized_at,mutation_id) VALUES(document_.document_id,version_,1,result->>'number','structured',result,sha256(convert_to(result::text,'UTF8')),actor,now(),p_mutation);
  UPDATE private_isg.documents SET current_version=version_ WHERE document_id=document_.document_id;
 END IF;

ELSE
 IF jsonb_typeof(vals) IS DISTINCT FROM 'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(vals) k WHERE NOT (spec->'fields' ? k)) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;
 IF spec ? 'parent' THEN
  parent:=private_isg.process_row(spec->>'parent_kind',(vals->>(spec->>'parent'))::uuid);
  IF (parent->>'company_id')::uuid<>p_company THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 END IF;
 IF vals ? 'workplace_id' THEN
  PERFORM 1 FROM private_isg.workplaces WHERE id=(vals->>'workplace_id')::uuid AND company_id=p_company AND NOT is_archived;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 END IF;
 IF kind='annual_work_item' THEN
  IF extract(year FROM (vals->>'planned_on')::date)<>(parent->'values'->>'plan_year')::integer THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PLAN_YEAR_MISMATCH'; END IF;
  IF parent->'values'->>'state'<>'active' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PLAN_CLOSED'; END IF;
  IF (vals->>'performed_on')::date>today THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FUTURE_DATE'; END IF;
 END IF;
 IF kind='board' THEN
  vals:=vals||jsonb_build_object('counts_towards_legal_score',vals->>'applicability'='mandatory');
  IF (vals->>'held_on')::date>today THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FUTURE_DATE'; END IF;
  IF jsonb_typeof(vals->'agenda')<>'array' OR jsonb_array_length(vals->'agenda')=0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 END IF;
 IF kind='site_visit' AND (vals->>'visited_on')::date>today THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FUTURE_DATE'; END IF;
 IF kind='work_permit' THEN
  IF vals->>'template_code' NOT IN ('general','hot_work','work_at_height','confined_space','electrical') OR (vals->>'ends_at')::timestamptz<=(vals->>'starts_at')::timestamptz THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  vals:=vals||'{"template_version":1}'::jsonb;
 END IF;
 IF kind IN ('board','work_permit') THEN
  key_:=CASE WHEN kind='board' THEN 'attendance' ELSE 'parties' END;
  IF vals->key_ IS NOT NULL AND vals->key_<>'null'::jsonb THEN
   IF jsonb_typeof(vals->key_)<>'array' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(vals->key_) person WHERE NOT EXISTS(SELECT 1 FROM private_isg.employees e WHERE e.id=(person->>'id')::uuid AND e.company_id=p_company AND NOT e.is_archived)) OR (SELECT count(*)<>count(DISTINCT person->>'id') FROM jsonb_array_elements(vals->key_) person) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
   vals:=jsonb_set(vals,ARRAY[key_],(SELECT coalesce(jsonb_agg(jsonb_build_object('id',e.id,'name',e.full_name) ORDER BY ord),'[]') FROM jsonb_array_elements(vals->key_) WITH ORDINALITY x(person,ord) JOIN private_isg.employees e ON e.id=(person->>'id')::uuid));
  END IF;
 END IF;
 IF kind='contractor_engagement' THEN
  PERFORM 1 FROM private_isg.contractor_organizations WHERE id=(vals->>'organization_id')::uuid AND company_id=p_company AND NOT is_archived;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 END IF;
 doc:=(p_payload->>'document_id')::uuid;
 IF doc IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private_isg.document_obligations WHERE obligation_id=doc AND company_id=p_company AND owner_id=actor AND NOT is_archived) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 IF p_payload->>'related_id' IS NOT NULL THEN
  other:=private_isg.process_row(p_payload->>'related_kind',(p_payload->>'related_id')::uuid);
  IF (other->>'company_id')::uuid<>p_company THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 END IF;
 IF id_ IS NULL THEN
  id_:=gen_random_uuid();vals:=vals||jsonb_build_object(spec->>'id',id_);
  IF NOT (spec ? 'parent') THEN vals:=vals||jsonb_build_object('company_id',p_company,'owner_id',actor); END IF;
  SELECT string_agg(format('%I',k),',' ORDER BY k),string_agg(format('r.%I',k),',' ORDER BY k) INTO cols,expr FROM jsonb_object_keys(vals) k;
  EXECUTE format('INSERT INTO private_isg.%I(%s) SELECT %s FROM jsonb_populate_record(NULL::private_isg.%I,$1) r',spec->>'table',cols,expr,spec->>'table') USING vals;
 ELSE
  SELECT string_agg(format('%I=r.%I',k,k),',' ORDER BY k) INTO cols FROM jsonb_object_keys(vals) k;
  IF kind IN ('contractor','contractor_engagement') THEN cols:=cols||',version=t.version+1'; END IF;
  EXECUTE format('UPDATE private_isg.%I t SET %s FROM jsonb_populate_record(NULL::private_isg.%I,$1) r WHERE t.%I=$2',spec->>'table',cols,spec->>'table',spec->>'id') USING vals,id_;
 END IF;
 INSERT INTO private_isg.process_record_meta(kind,record_id,company_id,document_id,related_kind,related_id) VALUES(kind,id_,p_company,doc,p_payload->>'related_kind',(p_payload->>'related_id')::uuid) ON CONFLICT ON CONSTRAINT process_record_meta_pkey DO UPDATE SET document_id=EXCLUDED.document_id,related_kind=EXCLUDED.related_kind,related_id=EXCLUDED.related_id;
 result:=private_isg.process_row(kind,id_);
END IF;
IF old_ IS NOT NULL THEN INSERT INTO private_isg.process_record_history(kind,record_id,company_id,actor_id,before_snapshot) VALUES(kind,id_,p_company,actor,old_); END IF;
INSERT INTO private_isg.module_edit_receipts VALUES(actor,p_mutation,hash_,result);
RETURN result;
END $$;
CREATE FUNCTION public.isg_pilot_process_read_v1(p_kind text,p_company uuid,p_id uuid,p_parent uuid,p_query text,p_offset integer) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.process_read(p_kind,p_company,p_id,p_parent,p_query,p_offset) $$;
CREATE FUNCTION public.isg_pilot_process_mutate_v1(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,p_payload jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.process_mutate(p_company,p_action,p_operation,p_mutation,p_payload) $$;
REVOKE ALL ON FUNCTION private_isg.process_spec(text),private_isg.process_guard(text,uuid,boolean),private_isg.process_row(text,uuid),private_isg.process_read(text,uuid,uuid,uuid,text,integer),private_isg.process_mutate(uuid,text,uuid,uuid,jsonb),public.isg_pilot_process_read_v1(text,uuid,uuid,uuid,text,integer),public.isg_pilot_process_mutate_v1(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.process_read(text,uuid,uuid,uuid,text,integer),private_isg.process_mutate(uuid,text,uuid,uuid,jsonb),public.isg_pilot_process_read_v1(text,uuid,uuid,uuid,text,integer),public.isg_pilot_process_mutate_v1(uuid,text,uuid,uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
CREATE FUNCTION private_isg.process_documents(p_company uuid,p_document uuid,p_version integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ DECLARE actor uuid:=private_isg.active_actor(); d private_isg.documents; result jsonb; BEGIN
IF NOT private_isg.p05_pilot_account_enabled(actor,false) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
IF p_document IS NOT NULL THEN
 SELECT * INTO d FROM private_isg.documents WHERE document_id=p_document AND owner_id=actor AND source_domain='module' AND template_code LIKE 'process_%';
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 PERFORM private_isg.process_guard(split_part(d.source_ref,':',1),d.company_id,false);
 SELECT snapshot INTO result FROM private_isg.document_versions WHERE document_id=d.document_id AND version=coalesce(p_version,d.current_version);
 IF result IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 RETURN result;
END IF;
IF p_offset IS NULL OR p_offset<0 OR p_offset>100000 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
RETURN (SELECT coalesce(jsonb_agg(to_jsonb(q)),'[]') FROM (
 SELECT listed.document_id AS id,v.version,v.document_no,v.finalized_at,c.name AS company_name,split_part(listed.source_ref,':',1) AS kind
 FROM private_isg.documents listed JOIN private_isg.document_versions v ON v.document_id=listed.document_id JOIN public.companies c ON c.id=listed.company_id
 WHERE listed.owner_id=actor AND listed.source_domain='module' AND listed.template_code LIKE 'process_%' AND private_isg.p05_pilot_can_read(actor,listed.company_id) AND (p_company IS NULL OR listed.company_id=p_company)
 ORDER BY v.finalized_at DESC,listed.document_id,v.version DESC OFFSET p_offset LIMIT 20) q);
END $$;
CREATE FUNCTION public.isg_pilot_process_documents_v1(p_company uuid,p_document uuid,p_version integer,p_offset integer) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.process_documents(p_company,p_document,p_version,p_offset) $$;
REVOKE ALL ON FUNCTION private_isg.process_documents(uuid,uuid,integer,integer),public.isg_pilot_process_documents_v1(uuid,uuid,integer,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.process_documents(uuid,uuid,integer,integer),public.isg_pilot_process_documents_v1(uuid,uuid,integer,integer) TO authenticated;
