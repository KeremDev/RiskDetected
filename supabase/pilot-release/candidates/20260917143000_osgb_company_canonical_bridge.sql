-- Canonical company identity bridge. NOT DEPLOYED; all OSGB writes remain rollout-gated.
-- Legacy rows retain user_id and their existing RLS behavior. OSGB rows have no
-- personal owner and are reachable only through checked workspace RPCs.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

ALTER TABLE public.companies ADD COLUMN workspace_id uuid;
ALTER TABLE public.companies ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE public.companies ADD CONSTRAINT companies_workspace_fk
  FOREIGN KEY(workspace_id) REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT;
ALTER TABLE public.companies ADD CONSTRAINT companies_scope_present
  CHECK(user_id IS NOT NULL OR workspace_id IS NOT NULL);
ALTER TABLE public.companies ADD CONSTRAINT companies_workspace_identity_unique UNIQUE(workspace_id,id);
CREATE INDEX companies_workspace_active_created_idx
  ON public.companies(workspace_id,is_archived,created_at DESC,id) WHERE workspace_id IS NOT NULL;

ALTER TABLE private_isg.workspace_companies ADD CONSTRAINT workspace_company_legacy_fk
  FOREIGN KEY(legacy_company_id) REFERENCES public.companies(id) ON DELETE SET NULL
  DEFERRABLE INITIALLY DEFERRED;

CREATE OR REPLACE FUNCTION private.enforce_company_write_rules() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_limit integer; v_active_count integer; personal_workspace uuid;
BEGIN
  -- A scope-only server backfill is not a paid user edit. Preserve legacy
  -- business fields/timestamps and do not reject an expired owner's old rows.
  IF TG_OP='UPDATE' AND NEW.user_id IS NOT NULL AND OLD.workspace_id IS NULL AND NEW.workspace_id IS NOT NULL
    AND (to_jsonb(NEW)-'workspace_id')=(to_jsonb(OLD)-'workspace_id') AND EXISTS(
      SELECT 1 FROM private_isg.workspaces w WHERE w.id=NEW.workspace_id AND w.kind='personal'
        AND w.personal_owner_user_id=NEW.user_id) THEN RETURN NEW; END IF;
  NEW.name:=btrim(NEW.name);
  NEW.logo_path:=nullif(btrim(coalesce(NEW.logo_path,'')),'');
  NEW.address:=nullif(btrim(coalesce(NEW.address,'')),'');
  NEW.contact_person:=nullif(btrim(coalesce(NEW.contact_person,'')),'');
  NEW.department:=nullif(btrim(coalesce(NEW.department,'')),'');
  NEW.default_responsible:=nullif(btrim(coalesce(NEW.default_responsible,'')),'');
  IF NEW.name='' THEN RAISE EXCEPTION 'company_name_required'; END IF;
  IF NEW.default_due_days IS NOT NULL AND NEW.default_due_days NOT BETWEEN 1 AND 365 THEN
    RAISE EXCEPTION 'company_default_due_days_invalid'; END IF;
  IF NEW.user_id IS NULL THEN
    IF NEW.workspace_id IS NULL OR NOT EXISTS(
      SELECT 1 FROM private_isg.workspace_companies c JOIN private_isg.workspaces w ON w.id=c.workspace_id
      WHERE c.id=NEW.id AND c.workspace_id=NEW.workspace_id AND w.kind='osgb') THEN
      RAISE EXCEPTION 'workspace_company_required'; END IF;
  ELSE
    IF NEW.workspace_id IS NULL THEN
      SELECT id INTO personal_workspace FROM private_isg.workspaces
        WHERE kind='personal' AND personal_owner_user_id=NEW.user_id;
      NEW.workspace_id:=personal_workspace;
    ELSIF NOT EXISTS(SELECT 1 FROM private_isg.workspaces w
      WHERE w.id=NEW.workspace_id AND w.kind='personal' AND w.personal_owner_user_id=NEW.user_id) THEN
      RAISE EXCEPTION 'company_workspace_mismatch';
    END IF;
    v_limit:=coalesce(private.company_limit_for_user(NEW.user_id),0);
    IF v_limit<=0 THEN RAISE EXCEPTION 'company_feature_requires_paid_plan'; END IF;
    IF NOT NEW.is_archived THEN
      SELECT count(*) INTO v_active_count FROM public.companies c
        WHERE c.user_id=NEW.user_id AND NOT c.is_archived AND (TG_OP<>'UPDATE' OR c.id<>NEW.id);
      IF v_active_count>=v_limit THEN RAISE EXCEPTION 'company_limit_exceeded'; END IF;
    END IF;
  END IF;
  NEW.updated_at:=clock_timestamp(); RETURN NEW;
END $$;

CREATE FUNCTION private_isg.workspace_company_canonical_sync() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE workspace private_isg.workspaces; actor uuid;
BEGIN
  IF NEW.workspace_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO workspace FROM private_isg.workspaces WHERE id=NEW.workspace_id FOR SHARE;
  IF workspace.id IS NULL OR (workspace.kind='personal' AND NEW.user_id IS DISTINCT FROM workspace.personal_owner_user_id) OR
     (workspace.kind='osgb' AND NEW.user_id IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='COMPANY_SCOPE_CONFLICT'; END IF;
  actor:=coalesce(NEW.user_id,workspace.created_by_user_id);
  INSERT INTO private_isg.workspace_companies(id,workspace_id,legacy_company_id,name,hazard_class,
    logo_path,status,created_by_user_id,updated_by_user_id,created_at,updated_at,archived_at)
    VALUES(NEW.id,NEW.workspace_id,NEW.id,NEW.name,NEW.hazard_class,NEW.logo_path,
      CASE WHEN NEW.is_archived THEN 'archived' ELSE 'active' END,actor,actor,NEW.created_at,NEW.updated_at,
      CASE WHEN NEW.is_archived THEN NEW.updated_at ELSE NULL END)
  ON CONFLICT(id) DO UPDATE SET
    legacy_company_id=EXCLUDED.legacy_company_id,name=EXCLUDED.name,hazard_class=EXCLUDED.hazard_class,
    logo_path=EXCLUDED.logo_path,status=EXCLUDED.status,
    version=CASE WHEN ROW(private_isg.workspace_companies.name,private_isg.workspace_companies.hazard_class,
      private_isg.workspace_companies.logo_path,private_isg.workspace_companies.status)
      IS DISTINCT FROM ROW(EXCLUDED.name,EXCLUDED.hazard_class,EXCLUDED.logo_path,EXCLUDED.status)
      THEN private_isg.workspace_companies.version+1 ELSE private_isg.workspace_companies.version END,
    updated_by_user_id=CASE WHEN NEW.user_id IS NULL THEN private_isg.workspace_companies.updated_by_user_id ELSE EXCLUDED.updated_by_user_id END,updated_at=EXCLUDED.updated_at,
    archived_at=EXCLUDED.archived_at
    WHERE private_isg.workspace_companies.workspace_id=EXCLUDED.workspace_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='COMPANY_SCOPE_CONFLICT'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER companies_workspace_canonical_sync_after
AFTER INSERT OR UPDATE OF workspace_id,name,hazard_class,logo_path,is_archived ON public.companies
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_company_canonical_sync();

-- Preserve the old personal delete operation without cascading away OSGB
-- history. Its mirror becomes archived and the optional legacy link is cleared.
CREATE FUNCTION private_isg.workspace_company_legacy_delete() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF OLD.user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='OSGB_COMPANY_ARCHIVE_REQUIRED'; END IF;
  UPDATE private_isg.workspace_companies SET status='archived',archived_at=clock_timestamp(),
    version=version+1,updated_by_user_id=OLD.user_id,updated_at=clock_timestamp()
    WHERE legacy_company_id=OLD.id AND status='active';
  RETURN OLD;
END $$;
REVOKE ALL ON FUNCTION private_isg.workspace_company_legacy_delete() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER companies_workspace_legacy_delete_before BEFORE DELETE ON public.companies
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_company_legacy_delete();

CREATE TABLE private_isg.workspace_company_backfill_checkpoints(
  run_id uuid PRIMARY KEY,
  source_fingerprint text NOT NULL CHECK(source_fingerprint ~ '^[0-9a-f]{64}$'),
  last_company_id uuid,
  scanned_count bigint NOT NULL DEFAULT 0,
  mapped_count bigint NOT NULL DEFAULT 0,
  blocked_count bigint NOT NULL DEFAULT 0,
  completed boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE private_isg.workspace_company_backfill_checkpoints ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_company_backfill_checkpoints FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.workspace_company_backfill_batch(p_run uuid,p_source_fingerprint text,
  p_after uuid DEFAULT NULL,p_limit integer DEFAULT 250,p_apply boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE row_ record; last_id uuid:=p_after; scanned integer:=0; mapped integer:=0; blocked integer:=0;
  has_more boolean; checkpoint private_isg.workspace_company_backfill_checkpoints;
BEGIN
  IF p_run IS NULL OR p_source_fingerprint !~ '^[0-9a-f]{64}$' OR p_limit NOT BETWEEN 1 AND 1000 OR p_apply IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO checkpoint FROM private_isg.workspace_company_backfill_checkpoints WHERE run_id=p_run FOR UPDATE;
  IF checkpoint.run_id IS NOT NULL AND checkpoint.source_fingerprint<>p_source_fingerprint THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SOURCE_FINGERPRINT_CONFLICT'; END IF;
  IF checkpoint.run_id IS NOT NULL THEN
    IF checkpoint.completed THEN
      RETURN jsonb_build_object('schema_version',1,'run_id',p_run,'apply',p_apply,
        'last_company_id',checkpoint.last_company_id,'scanned',0,'mapped',0,'blocked',0,'has_more',false,'completed',true);
    END IF;
    IF p_after IS DISTINCT FROM checkpoint.last_company_id THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='BACKFILL_CURSOR_CONFLICT'; END IF;
  END IF;
  FOR row_ IN SELECT c.id,c.user_id,w.id workspace_id FROM public.companies c
    LEFT JOIN private_isg.workspaces w ON w.kind='personal' AND w.personal_owner_user_id=c.user_id
    WHERE c.user_id IS NOT NULL AND (p_after IS NULL OR c.id>p_after) ORDER BY c.id LIMIT p_limit LOOP
    scanned:=scanned+1; last_id:=row_.id;
    IF row_.workspace_id IS NULL THEN blocked:=blocked+1;
    ELSE
      mapped:=mapped+1;
      IF p_apply THEN UPDATE public.companies SET workspace_id=row_.workspace_id WHERE id=row_.id AND workspace_id IS DISTINCT FROM row_.workspace_id; END IF;
    END IF;
  END LOOP;
  SELECT EXISTS(SELECT 1 FROM public.companies c WHERE c.user_id IS NOT NULL AND last_id IS NOT NULL AND c.id>last_id) INTO has_more;
  IF p_apply THEN
    INSERT INTO private_isg.workspace_company_backfill_checkpoints(run_id,source_fingerprint,last_company_id,
      scanned_count,mapped_count,blocked_count,completed)
      VALUES(p_run,p_source_fingerprint,last_id,scanned,mapped,blocked,NOT has_more AND blocked=0)
    ON CONFLICT(run_id) DO UPDATE SET last_company_id=EXCLUDED.last_company_id,
      scanned_count=private_isg.workspace_company_backfill_checkpoints.scanned_count+EXCLUDED.scanned_count,
      mapped_count=private_isg.workspace_company_backfill_checkpoints.mapped_count+EXCLUDED.mapped_count,
      blocked_count=private_isg.workspace_company_backfill_checkpoints.blocked_count+EXCLUDED.blocked_count,
      completed=EXCLUDED.completed,updated_at=clock_timestamp();
  END IF;
  RETURN jsonb_build_object('schema_version',1,'run_id',p_run,'apply',p_apply,'last_company_id',last_id,
    'scanned',scanned,'mapped',mapped,'blocked',blocked,'has_more',has_more,
    'completed',NOT has_more AND blocked=0);
END $$;

CREATE OR REPLACE FUNCTION private_isg.workspace_company_create(p_mutation uuid,p_workspace uuid,p_name text,p_hazard text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); manager private_isg.workspace_memberships;
  clean_name text; fingerprint bytea; replay jsonb; company private_isg.workspace_companies; result jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_companies',true);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],true);
  clean_name:=private_isg.workspace_text(p_name,200);
  IF p_hazard NOT IN ('low','medium','high') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,clean_name,p_hazard)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'company.create',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  INSERT INTO private_isg.workspace_companies(workspace_id,name,hazard_class,created_by_user_id,updated_by_user_id)
    VALUES(p_workspace,clean_name,p_hazard,actor,actor) RETURNING * INTO company;
  INSERT INTO public.companies(id,user_id,workspace_id,name,hazard_class)
    VALUES(company.id,NULL,p_workspace,company.name,company.hazard_class);
  UPDATE private_isg.workspace_companies SET legacy_company_id=id WHERE id=company.id RETURNING * INTO company;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',company.id,
    'legacy_company_id',company.legacy_company_id,'name',company.name,'hazard_class',company.hazard_class,
    'status',company.status,'version',company.version);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'company.create',fingerprint,p_workspace,
    'company',company.id,company.version,NULL,result,NULL,result);
END $$;

CREATE OR REPLACE FUNCTION private_isg.workspace_company_update(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_expected bigint,p_name text,p_hazard text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); manager private_isg.workspace_memberships;
  company private_isg.workspace_companies; clean_name text; fingerprint bytea; replay jsonb;
  before_state jsonb; result jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_companies',true);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],true);
  clean_name:=private_isg.workspace_text(p_name,200);
  IF p_mutation IS NULL OR p_expected IS NULL OR p_expected<0 OR p_hazard NOT IN ('low','medium','high') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_expected,clean_name,p_hazard)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'company.update',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  SELECT * INTO company FROM private_isg.workspace_companies
    WHERE id=p_company AND workspace_id=p_workspace AND status='active' FOR UPDATE;
  IF company.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF company.version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  before_state:=jsonb_build_object('name',company.name,'hazard_class',company.hazard_class,'version',company.version);
  UPDATE private_isg.workspace_companies SET name=clean_name,hazard_class=p_hazard,updated_by_user_id=actor,
    version=version+1,updated_at=clock_timestamp() WHERE id=company.id RETURNING * INTO company;
  UPDATE public.companies SET name=clean_name,hazard_class=p_hazard WHERE id=company.id AND workspace_id=p_workspace;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='COMPANY_CANONICAL_MISSING'; END IF;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',company.id,
    'legacy_company_id',company.legacy_company_id,'name',company.name,'hazard_class',company.hazard_class,
    'status',company.status,'version',company.version);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'company.update',fingerprint,p_workspace,
    'company',company.id,company.version,before_state,result,NULL,result);
END $$;

CREATE OR REPLACE FUNCTION private_isg.workspace_company_archive(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_expected bigint,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); manager private_isg.workspace_memberships;
  company private_isg.workspace_companies; assignment private_isg.company_assignments;
  clean_reason text; fingerprint bytea; replay jsonb; before_state jsonb; result jsonb; ended integer:=0;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_companies',true);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],true);
  clean_reason:=private_isg.workspace_text(p_reason,500);
  IF p_mutation IS NULL OR p_expected IS NULL OR p_expected<0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_expected,clean_reason)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'company.archive',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  SELECT * INTO company FROM private_isg.workspace_companies
    WHERE id=p_company AND workspace_id=p_workspace AND status='active' FOR UPDATE;
  IF company.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF company.version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  before_state:=jsonb_build_object('status',company.status,'version',company.version);
  FOR assignment IN SELECT * FROM private_isg.company_assignments a
    WHERE a.workspace_id=p_workspace AND a.company_id=p_company AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp()) AND a.ends_at IS DISTINCT FROM a.starts_at FOR UPDATE LOOP
    UPDATE private_isg.company_assignments SET ends_at=greatest(starts_at,clock_timestamp()),ended_by_user_id=actor,reason=clean_reason,
      version=version+1,updated_at=clock_timestamp() WHERE id=assignment.id RETURNING * INTO assignment;
    INSERT INTO private_isg.company_assignment_events(workspace_id,assignment_id,event_type,actor_user_id,
      before_state,after_state,reason,correlation_id) VALUES(p_workspace,assignment.id,'ended',actor,NULL,
      private_isg.company_assignment_json(assignment),clean_reason,p_mutation); ended:=ended+1;
  END LOOP;
  UPDATE private_isg.workspace_companies SET status='archived',archived_at=clock_timestamp(),
    updated_by_user_id=actor,version=version+1,updated_at=clock_timestamp()
    WHERE id=company.id RETURNING * INTO company;
  UPDATE public.companies SET is_archived=true WHERE id=company.id AND workspace_id=p_workspace;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='COMPANY_CANONICAL_MISSING'; END IF;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',company.id,
    'status',company.status,'version',company.version,'archived_at',company.archived_at,
    'ended_assignments',ended,'data_deleted',false);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'company.archive',fingerprint,p_workspace,
    'company',company.id,company.version,before_state,result,clean_reason,result);
END $$;

REVOKE ALL ON FUNCTION private_isg.workspace_company_canonical_sync(),
  private_isg.workspace_company_backfill_batch(uuid,text,uuid,integer,boolean)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
