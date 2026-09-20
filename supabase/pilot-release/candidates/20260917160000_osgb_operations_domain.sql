-- D6 workspace operational records. NOT DEPLOYED; default OFF.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='30s';

ALTER TABLE private_isg.workspace_audit DROP CONSTRAINT workspace_audit_entity_type_check;
ALTER TABLE private_isg.workspace_audit ADD CONSTRAINT workspace_audit_entity_type_check CHECK(entity_type IN
  ('workspace','membership','invitation','company','assignment','seat','subscription','wallet','asset','handover',
   'workplace','department','employee','domain','training','risk','nonconformity','checklist','emergency_plan',
   'drill','appointment','ppe','equipment','katip_contract','annual_plan','board','work_permit','site_visit','notebook_archive'));
ALTER TABLE private_isg.workspace_outbox DROP CONSTRAINT workspace_outbox_aggregate_type_check;
ALTER TABLE private_isg.workspace_outbox ADD CONSTRAINT workspace_outbox_aggregate_type_check CHECK(aggregate_type IN
  ('workspace','membership','invitation','company','assignment','seat','subscription','wallet','asset','handover',
   'workplace','department','employee','domain','training','risk','nonconformity','checklist','emergency_plan',
   'drill','appointment','ppe','equipment','katip_contract','annual_plan','board','work_permit','site_visit','notebook_archive'));

-- Roots keep legacy ownership for personal workspaces and real author identity
-- for OSGB workspaces. Workspace assets are separate from the legacy file id.
ALTER TABLE private_isg.katip_contracts ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.katip_contracts ADD COLUMN workspace_asset_id uuid REFERENCES private_isg.workspace_file_assets(id) ON DELETE RESTRICT;
ALTER TABLE private_isg.katip_contracts ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.katip_contracts ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.katip_contracts ADD COLUMN version bigint NOT NULL DEFAULT 0;
ALTER TABLE private_isg.katip_contracts ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.katip_contracts ADD CONSTRAINT katip_workspace_company_fk FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.katip_contracts ADD CONSTRAINT katip_workspace_workplace_fk FOREIGN KEY(workspace_id,company_id,workplace_id) REFERENCES private_isg.workplaces(workspace_id,company_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.katip_contracts ADD CONSTRAINT katip_workspace_identity_unique UNIQUE(workspace_id,company_id,contract_id);

ALTER TABLE private_isg.annual_work_plans ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.annual_work_plans ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.annual_work_plans ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.annual_work_plans ADD COLUMN version bigint NOT NULL DEFAULT 0;
ALTER TABLE private_isg.annual_work_plans ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.annual_work_plans ADD CONSTRAINT annual_plans_workspace_company_fk FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.annual_work_plans ADD CONSTRAINT annual_plans_workspace_workplace_fk FOREIGN KEY(workspace_id,company_id,workplace_id) REFERENCES private_isg.workplaces(workspace_id,company_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.annual_work_plans ADD CONSTRAINT annual_plans_workspace_identity_unique UNIQUE(workspace_id,company_id,plan_id);
ALTER TABLE private_isg.annual_work_plan_items ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.annual_work_plan_items ADD COLUMN company_id uuid;
ALTER TABLE private_isg.annual_work_plan_items ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.annual_work_plan_items ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.annual_work_plan_items ADD COLUMN version bigint NOT NULL DEFAULT 0;
ALTER TABLE private_isg.annual_work_plan_items ADD CONSTRAINT annual_items_workspace_parent_fk FOREIGN KEY(workspace_id,company_id,plan_id) REFERENCES private_isg.annual_work_plans(workspace_id,company_id,plan_id) ON DELETE CASCADE;
ALTER TABLE private_isg.annual_work_plan_items ADD CONSTRAINT annual_items_workspace_identity_unique UNIQUE(workspace_id,company_id,item_id);

ALTER TABLE private_isg.board_meetings ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.board_meetings ADD COLUMN workspace_asset_id uuid REFERENCES private_isg.workspace_file_assets(id) ON DELETE RESTRICT;
ALTER TABLE private_isg.board_meetings ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.board_meetings ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.board_meetings ADD COLUMN version bigint NOT NULL DEFAULT 0;
ALTER TABLE private_isg.board_meetings ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.board_meetings ADD CONSTRAINT boards_workspace_company_fk FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.board_meetings ADD CONSTRAINT boards_workspace_workplace_fk FOREIGN KEY(workspace_id,company_id,workplace_id) REFERENCES private_isg.workplaces(workspace_id,company_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.board_meetings ADD CONSTRAINT boards_workspace_identity_unique UNIQUE(workspace_id,company_id,meeting_id);
ALTER TABLE private_isg.board_decisions ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.board_decisions ADD COLUMN company_id uuid;
ALTER TABLE private_isg.board_decisions ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.board_decisions ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.board_decisions ADD COLUMN updated_at timestamptz NOT NULL DEFAULT clock_timestamp();
ALTER TABLE private_isg.board_decisions ADD COLUMN version bigint NOT NULL DEFAULT 0;
ALTER TABLE private_isg.board_decisions ADD CONSTRAINT board_decisions_workspace_parent_fk FOREIGN KEY(workspace_id,company_id,meeting_id) REFERENCES private_isg.board_meetings(workspace_id,company_id,meeting_id) ON DELETE CASCADE;
ALTER TABLE private_isg.board_decisions ADD CONSTRAINT board_decisions_workspace_identity_unique UNIQUE(workspace_id,company_id,decision_id);

ALTER TABLE private_isg.work_permit_forms ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.work_permit_forms ADD COLUMN workspace_asset_id uuid REFERENCES private_isg.workspace_file_assets(id) ON DELETE RESTRICT;
ALTER TABLE private_isg.work_permit_forms ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.work_permit_forms ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.work_permit_forms ADD COLUMN version bigint NOT NULL DEFAULT 0;
ALTER TABLE private_isg.work_permit_forms ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.work_permit_forms ADD CONSTRAINT permits_workspace_company_fk FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.work_permit_forms ADD CONSTRAINT permits_workspace_workplace_fk FOREIGN KEY(workspace_id,company_id,workplace_id) REFERENCES private_isg.workplaces(workspace_id,company_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.work_permit_forms ADD CONSTRAINT permits_workspace_identity_unique UNIQUE(workspace_id,company_id,permit_id);

ALTER TABLE private_isg.site_visits ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.site_visits ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.site_visits ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.site_visits ADD COLUMN updated_at timestamptz NOT NULL DEFAULT clock_timestamp();
ALTER TABLE private_isg.site_visits ADD COLUMN version bigint NOT NULL DEFAULT 0;
ALTER TABLE private_isg.site_visits ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.site_visits ADD CONSTRAINT visits_workspace_company_fk FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.site_visits ADD CONSTRAINT visits_workspace_workplace_fk FOREIGN KEY(workspace_id,company_id,workplace_id) REFERENCES private_isg.workplaces(workspace_id,company_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.site_visits ADD CONSTRAINT visits_workspace_identity_unique UNIQUE(workspace_id,company_id,visit_id);
ALTER TABLE private_isg.site_visit_observations ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.site_visit_observations ADD COLUMN company_id uuid;
ALTER TABLE private_isg.site_visit_observations ADD COLUMN workspace_asset_id uuid REFERENCES private_isg.workspace_file_assets(id) ON DELETE RESTRICT;
ALTER TABLE private_isg.site_visit_observations ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.site_visit_observations ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.site_visit_observations ADD COLUMN updated_at timestamptz NOT NULL DEFAULT clock_timestamp();
ALTER TABLE private_isg.site_visit_observations ADD COLUMN version bigint NOT NULL DEFAULT 0;
ALTER TABLE private_isg.site_visit_observations ADD CONSTRAINT observations_workspace_parent_fk FOREIGN KEY(workspace_id,company_id,visit_id) REFERENCES private_isg.site_visits(workspace_id,company_id,visit_id) ON DELETE CASCADE;
ALTER TABLE private_isg.site_visit_observations ADD CONSTRAINT observations_workspace_identity_unique UNIQUE(workspace_id,company_id,observation_id);

-- The curated pilot release intentionally did not ship the legacy notebook
-- archive slice.  D6 still exposes notebook archives to workspace clients, so
-- create the compatible root when that optional legacy slice is absent.  This
-- is additive and keeps the signed-copy invariant used by both personal and
-- OSGB workspaces.
CREATE TABLE IF NOT EXISTS private_isg.notebook_archive_entries (
  entry_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  owner_id uuid NOT NULL,
  workplace_id uuid NOT NULL,
  notebook_ref text NOT NULL CHECK(btrim(notebook_ref)<>'' AND length(notebook_ref)<=200),
  entry_on date NOT NULL CHECK(isfinite(entry_on)),
  asset_id uuid NOT NULL REFERENCES private_isg.file_assets(asset_id),
  ai_draft_ref text CHECK(ai_draft_ref IS NULL OR length(ai_draft_ref)<=200),
  ai_text_is_official_record boolean NOT NULL DEFAULT false CHECK(NOT ai_text_is_official_record),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,notebook_ref,entry_on),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS notebook_scope_idx
  ON private_isg.notebook_archive_entries(company_id,workplace_id,entry_on);
CREATE INDEX IF NOT EXISTS notebook_owner_idx
  ON private_isg.notebook_archive_entries(company_id,owner_id);
CREATE INDEX IF NOT EXISTS notebook_asset_idx
  ON private_isg.notebook_archive_entries(asset_id);
ALTER TABLE private_isg.notebook_archive_entries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.notebook_archive_entries FROM PUBLIC,anon,authenticated,service_role;

ALTER TABLE private_isg.notebook_archive_entries ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.notebook_archive_entries ADD COLUMN workspace_asset_id uuid REFERENCES private_isg.workspace_file_assets(id) ON DELETE RESTRICT;
ALTER TABLE private_isg.notebook_archive_entries ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.notebook_archive_entries ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.notebook_archive_entries ADD COLUMN updated_at timestamptz NOT NULL DEFAULT clock_timestamp();
ALTER TABLE private_isg.notebook_archive_entries ADD COLUMN version bigint NOT NULL DEFAULT 0;
ALTER TABLE private_isg.notebook_archive_entries ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.notebook_archive_entries ALTER COLUMN asset_id DROP NOT NULL;
ALTER TABLE private_isg.notebook_archive_entries ADD CONSTRAINT notebook_workspace_asset_required
  CHECK(asset_id IS NOT NULL OR workspace_asset_id IS NOT NULL);
ALTER TABLE private_isg.notebook_archive_entries ADD CONSTRAINT notebook_workspace_company_fk FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.notebook_archive_entries ADD CONSTRAINT notebook_workspace_workplace_fk FOREIGN KEY(workspace_id,company_id,workplace_id) REFERENCES private_isg.workplaces(workspace_id,company_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.notebook_archive_entries ADD CONSTRAINT notebook_workspace_identity_unique UNIQUE(workspace_id,company_id,entry_id);

UPDATE private_isg.katip_contracts r SET workspace_id=c.workspace_id,created_by_user_id=r.owner_id,updated_by_user_id=r.owner_id FROM public.companies c WHERE c.id=r.company_id AND c.workspace_id IS NOT NULL;
UPDATE private_isg.annual_work_plans r SET workspace_id=c.workspace_id,created_by_user_id=r.owner_id,updated_by_user_id=r.owner_id FROM public.companies c WHERE c.id=r.company_id AND c.workspace_id IS NOT NULL;
UPDATE private_isg.annual_work_plan_items i SET workspace_id=p.workspace_id,company_id=p.company_id,created_by_user_id=p.created_by_user_id,updated_by_user_id=p.updated_by_user_id FROM private_isg.annual_work_plans p WHERE p.plan_id=i.plan_id AND p.workspace_id IS NOT NULL;
UPDATE private_isg.board_meetings r SET workspace_id=c.workspace_id,created_by_user_id=r.owner_id,updated_by_user_id=r.owner_id FROM public.companies c WHERE c.id=r.company_id AND c.workspace_id IS NOT NULL;
UPDATE private_isg.board_decisions i SET workspace_id=p.workspace_id,company_id=p.company_id,created_by_user_id=p.created_by_user_id,updated_by_user_id=p.updated_by_user_id FROM private_isg.board_meetings p WHERE p.meeting_id=i.meeting_id AND p.workspace_id IS NOT NULL;
UPDATE private_isg.work_permit_forms r SET workspace_id=c.workspace_id,created_by_user_id=r.owner_id,updated_by_user_id=r.owner_id FROM public.companies c WHERE c.id=r.company_id AND c.workspace_id IS NOT NULL;
UPDATE private_isg.site_visits r SET workspace_id=c.workspace_id,created_by_user_id=r.owner_id,updated_by_user_id=r.owner_id FROM public.companies c WHERE c.id=r.company_id AND c.workspace_id IS NOT NULL;
UPDATE private_isg.site_visit_observations i SET workspace_id=p.workspace_id,company_id=p.company_id,created_by_user_id=p.created_by_user_id,updated_by_user_id=p.updated_by_user_id FROM private_isg.site_visits p WHERE p.visit_id=i.visit_id AND p.workspace_id IS NOT NULL;
UPDATE private_isg.notebook_archive_entries r SET workspace_id=c.workspace_id,created_by_user_id=r.owner_id,updated_by_user_id=r.owner_id FROM public.companies c WHERE c.id=r.company_id AND c.workspace_id IS NOT NULL;

CREATE INDEX operations_katip_workspace_page ON private_isg.katip_contracts(workspace_id,company_id,state,starts_on,contract_id);
CREATE INDEX operations_plan_workspace_page ON private_isg.annual_work_plans(workspace_id,company_id,state,plan_year,plan_id);
CREATE INDEX operations_board_workspace_page ON private_isg.board_meetings(workspace_id,company_id,state,planned_on,meeting_id);
CREATE INDEX operations_permit_workspace_page ON private_isg.work_permit_forms(workspace_id,company_id,state,planned_on,permit_id);
CREATE INDEX operations_visit_workspace_page ON private_isg.site_visits(workspace_id,company_id,visited_on,visit_id);
CREATE INDEX operations_notebook_workspace_page ON private_isg.notebook_archive_entries(workspace_id,company_id,entry_on,entry_id);

CREATE FUNCTION private_isg.workspace_operation_root_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE company public.companies; workspace private_isg.workspaces; asset private_isg.workspace_file_assets;
BEGIN
  IF private_isg.workspace_is_legacy_company_write(NEW.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  SELECT * INTO company FROM public.companies WHERE id=NEW.company_id FOR SHARE;
  IF NEW.workspace_id IS NULL THEN NEW.workspace_id:=company.workspace_id; END IF;
  IF company.id IS NULL OR NEW.workspace_id IS DISTINCT FROM company.workspace_id OR NOT EXISTS(
    SELECT 1 FROM private_isg.workplaces w WHERE w.workspace_id=NEW.workspace_id AND w.company_id=NEW.company_id AND w.id=NEW.workplace_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='OPERATION_SCOPE_CONFLICT'; END IF;
  IF NEW.workspace_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO workspace FROM private_isg.workspaces WHERE id=NEW.workspace_id;
  IF workspace.kind='osgb' AND NEW.owner_id IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEGACY_OWNER_FORBIDDEN'; END IF;
  IF workspace.kind='personal' AND NEW.owner_id IS DISTINCT FROM company.user_id THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEGACY_OWNER_MISMATCH'; END IF;
  IF NEW.created_by_user_id IS NULL OR NEW.updated_by_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACTOR_REQUIRED'; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.owner_id,NEW.created_by_user_id) IS DISTINCT FROM ROW(OLD.workspace_id,OLD.company_id,OLD.owner_id,OLD.created_by_user_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER katip_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.katip_contracts FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_operation_root_invariant();
CREATE TRIGGER annual_plan_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.annual_work_plans FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_operation_root_invariant();
CREATE TRIGGER board_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.board_meetings FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_operation_root_invariant();
CREATE TRIGGER permit_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.work_permit_forms FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_operation_root_invariant();
CREATE TRIGGER visit_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.site_visits FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_operation_root_invariant();
CREATE TRIGGER notebook_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.notebook_archive_entries FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_operation_root_invariant();

CREATE FUNCTION private_isg.workspace_operation_child_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE parent_workspace uuid; parent_company uuid; parent_value uuid;
BEGIN
  parent_value:=(to_jsonb(NEW)->>TG_ARGV[2])::uuid;
  EXECUTE format('SELECT workspace_id,company_id FROM private_isg.%I WHERE %I=$1 FOR SHARE',TG_ARGV[0],TG_ARGV[1])
    INTO parent_workspace,parent_company USING parent_value;
  IF private_isg.workspace_is_legacy_company_write(parent_company,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  IF parent_workspace IS NULL OR parent_company IS NULL THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='OPERATION_PARENT_NOT_FOUND'; END IF;
  IF NEW.workspace_id IS NULL THEN NEW.workspace_id:=parent_workspace; END IF;
  IF NEW.company_id IS NULL THEN NEW.company_id:=parent_company; END IF;
  IF ROW(NEW.workspace_id,NEW.company_id) IS DISTINCT FROM ROW(parent_workspace,parent_company) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='OPERATION_CHILD_SCOPE_CONFLICT'; END IF;
  IF NEW.created_by_user_id IS NULL OR NEW.updated_by_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACTOR_REQUIRED'; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.created_by_user_id) IS DISTINCT FROM ROW(OLD.workspace_id,OLD.company_id,OLD.created_by_user_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER annual_item_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.annual_work_plan_items
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_operation_child_invariant('annual_work_plans','plan_id','plan_id');
CREATE TRIGGER board_decision_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.board_decisions
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_operation_child_invariant('board_meetings','meeting_id','meeting_id');
CREATE TRIGGER site_observation_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.site_visit_observations
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_operation_child_invariant('site_visits','visit_id','visit_id');

CREATE FUNCTION private_isg.workspace_operation_asset(p_workspace uuid,p_company uuid,p_asset uuid,p_required boolean) RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF p_asset IS NULL AND p_required THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSET_REQUIRED'; END IF;
  IF p_asset IS NULL THEN RETURN NULL; END IF;
  PERFORM 1 FROM private_isg.workspace_file_assets WHERE id=p_asset AND workspace_id=p_workspace AND company_id=p_company AND lifecycle='active';
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSET_SCOPE_CONFLICT'; END IF;
  RETURN p_asset;
END $$;

CREATE FUNCTION private_isg.workspace_operations_read(p_workspace uuid,p_company uuid,p_kind text,p_id uuid,p_after uuid,p_limit integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rows jsonb; next_id uuid; id_key text;
BEGIN
  PERFORM private_isg.workspace_domain_gate('operations',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  IF p_kind NOT IN ('katip_contract','annual_plan','board','work_permit','site_visit','notebook_archive')
    OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR (p_id IS NOT NULL AND p_after IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_kind='katip_contract' THEN
    id_key:='contract_id';
    SELECT coalesce(jsonb_agg(to_jsonb(r)-ARRAY['owner_id','workspace_id','asset_id'] ORDER BY r.contract_id),'[]') INTO rows
    FROM (SELECT * FROM private_isg.katip_contracts WHERE workspace_id=p_workspace AND company_id=p_company
      AND NOT is_deleted AND (p_id IS NULL OR contract_id=p_id) AND (p_after IS NULL OR contract_id>p_after)
      ORDER BY contract_id LIMIT CASE WHEN p_id IS NULL THEN p_limit+1 ELSE 1 END) r;
  ELSIF p_kind='annual_plan' THEN
    id_key:='plan_id';
    SELECT coalesce(jsonb_agg((to_jsonb(r)-ARRAY['owner_id','workspace_id'])||jsonb_build_object('items',(SELECT coalesce(jsonb_agg(to_jsonb(i)-ARRAY['workspace_id','company_id'] ORDER BY i.planned_on,i.item_id),'[]') FROM private_isg.annual_work_plan_items i WHERE i.workspace_id=p_workspace AND i.company_id=p_company AND i.plan_id=r.plan_id AND NOT i.is_deleted)) ORDER BY r.plan_id),'[]') INTO rows
    FROM (SELECT * FROM private_isg.annual_work_plans WHERE workspace_id=p_workspace AND company_id=p_company
      AND NOT is_deleted AND (p_id IS NULL OR plan_id=p_id) AND (p_after IS NULL OR plan_id>p_after)
      ORDER BY plan_id LIMIT CASE WHEN p_id IS NULL THEN p_limit+1 ELSE 1 END) r;
  ELSIF p_kind='board' THEN
    id_key:='meeting_id';
    SELECT coalesce(jsonb_agg((to_jsonb(r)-ARRAY['owner_id','workspace_id','minutes_asset_id'])||jsonb_build_object('decisions',(SELECT coalesce(jsonb_agg(to_jsonb(i)-ARRAY['workspace_id','company_id'] ORDER BY i.decision_no),'[]') FROM private_isg.board_decisions i WHERE i.workspace_id=p_workspace AND i.company_id=p_company AND i.meeting_id=r.meeting_id AND NOT i.is_deleted)) ORDER BY r.meeting_id),'[]') INTO rows
    FROM (SELECT * FROM private_isg.board_meetings WHERE workspace_id=p_workspace AND company_id=p_company
      AND NOT is_deleted AND (p_id IS NULL OR meeting_id=p_id) AND (p_after IS NULL OR meeting_id>p_after)
      ORDER BY meeting_id LIMIT CASE WHEN p_id IS NULL THEN p_limit+1 ELSE 1 END) r;
  ELSIF p_kind='work_permit' THEN
    id_key:='permit_id';
    SELECT coalesce(jsonb_agg(to_jsonb(r)-ARRAY['owner_id','workspace_id','rendered_asset_id'] ORDER BY r.permit_id),'[]') INTO rows
    FROM (SELECT * FROM private_isg.work_permit_forms WHERE workspace_id=p_workspace AND company_id=p_company
      AND NOT is_deleted AND (p_id IS NULL OR permit_id=p_id) AND (p_after IS NULL OR permit_id>p_after)
      ORDER BY permit_id LIMIT CASE WHEN p_id IS NULL THEN p_limit+1 ELSE 1 END) r;
  ELSIF p_kind='site_visit' THEN
    id_key:='visit_id';
    SELECT coalesce(jsonb_agg((to_jsonb(r)-ARRAY['owner_id','workspace_id'])||jsonb_build_object('observations',(SELECT coalesce(jsonb_agg(to_jsonb(i)-ARRAY['workspace_id','company_id','evidence_asset_id'] ORDER BY i.created_at,i.observation_id),'[]') FROM private_isg.site_visit_observations i WHERE i.workspace_id=p_workspace AND i.company_id=p_company AND i.visit_id=r.visit_id AND NOT i.is_deleted)) ORDER BY r.visit_id),'[]') INTO rows
    FROM (SELECT * FROM private_isg.site_visits WHERE workspace_id=p_workspace AND company_id=p_company
      AND NOT is_deleted AND (p_id IS NULL OR visit_id=p_id) AND (p_after IS NULL OR visit_id>p_after)
      ORDER BY visit_id LIMIT CASE WHEN p_id IS NULL THEN p_limit+1 ELSE 1 END) r;
  ELSE
    id_key:='entry_id';
    SELECT coalesce(jsonb_agg(to_jsonb(r)-ARRAY['owner_id','workspace_id','asset_id'] ORDER BY r.entry_id),'[]') INTO rows
    FROM (SELECT * FROM private_isg.notebook_archive_entries WHERE workspace_id=p_workspace AND company_id=p_company
      AND (p_id IS NULL OR entry_id=p_id) AND (p_after IS NULL OR entry_id>p_after)
      ORDER BY entry_id LIMIT CASE WHEN p_id IS NULL THEN p_limit+1 ELSE 1 END) r;
  END IF;
  IF p_id IS NOT NULL AND jsonb_array_length(rows)=0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF p_id IS NULL AND jsonb_array_length(rows)>p_limit THEN next_id:=(rows->(p_limit-1)->>id_key)::uuid; END IF;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'kind',p_kind,
    'rows',(SELECT coalesce(jsonb_agg(value),'[]') FROM (SELECT value FROM jsonb_array_elements(rows) LIMIT p_limit) q),
    'next',next_id);
END $$;

CREATE FUNCTION private_isg.workspace_operations_mutate(p_mutation uuid,p_workspace uuid,p_company uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); kind text:=p_payload->>'kind'; action text:=p_payload->>'action'; target uuid:=(p_payload->>'id')::uuid;
  fingerprint bytea; replay jsonb; expected bigint; result jsonb; before_state jsonb; aggregate_version bigint:=0;
  parent uuid; asset uuid; root jsonb; employee_count integer;
BEGIN
  PERFORM private_isg.workspace_domain_gate('operations',true);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,true);
  IF p_mutation IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>65536 OR
     EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) AS keys(key) WHERE key NOT IN
       ('kind','action','id','expected_version','workplace_id','workspace_asset_id','counterparty','expert_contact',
        'scope','starts_on','ends_before','declared_monthly_minutes','declared_note','contract_location',
        'plan_year','plan_id','activity','responsible_contact','planned_on','performed_on','reason','carried_to_plan_id',
        'applicability','agenda','meeting_id','decision_no','decision_text','due_on','state','attendance','held_on',
        'template_code','job_description','parties','work_location','starts_at','ends_at','risk_precautions',
        'visited_on','location_note','expert_note','visit_id','note','nonconformity_id','external_ref',
        'notebook_ref','entry_on','ai_draft_ref')) OR
     kind IS NULL OR kind NOT IN ('katip_contract','annual_plan','annual_item','board','board_decision','work_permit','site_visit','site_observation','notebook_archive') OR
     action IS NULL OR action NOT IN ('create','archive','close','perform','cancel','hold','settle') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_payload)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'operations.'||kind||'.'||action,fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  asset:=private_isg.workspace_operation_asset(p_workspace,p_company,(p_payload->>'workspace_asset_id')::uuid,kind='notebook_archive' AND action='create');

  IF kind='katip_contract' AND action='create' THEN
    INSERT INTO private_isg.katip_contracts(workspace_id,company_id,owner_id,workplace_id,counterparty,expert_contact,scope,
      starts_on,ends_before,workspace_asset_id,declared_monthly_minutes,declared_note,contract_location,created_by_user_id,updated_by_user_id)
    VALUES(p_workspace,p_company,NULL,(p_payload->>'workplace_id')::uuid,private_isg.workspace_text(p_payload->>'counterparty',200),
      private_isg.workspace_text(p_payload->>'expert_contact',200),private_isg.workspace_text(p_payload->>'scope',300),
      (p_payload->>'starts_on')::date,(p_payload->>'ends_before')::date,asset,(p_payload->>'declared_monthly_minutes')::integer,
      nullif(btrim(coalesce(p_payload->>'declared_note','')),''),nullif(btrim(coalesce(p_payload->>'contract_location','')),''),actor,actor)
    RETURNING contract_id,version INTO target,aggregate_version;
  ELSIF kind='annual_plan' AND action='create' THEN
    INSERT INTO private_isg.annual_work_plans(workspace_id,company_id,owner_id,workplace_id,plan_year,created_by_user_id,updated_by_user_id)
    VALUES(p_workspace,p_company,NULL,(p_payload->>'workplace_id')::uuid,(p_payload->>'plan_year')::integer,actor,actor)
    RETURNING plan_id,version INTO target,aggregate_version;
  ELSIF kind='annual_item' AND action='create' THEN
    parent:=(p_payload->>'plan_id')::uuid;
    PERFORM 1 FROM private_isg.annual_work_plans WHERE workspace_id=p_workspace AND company_id=p_company AND plan_id=parent AND state='active' FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF extract(year FROM (p_payload->>'planned_on')::date)<>(SELECT plan_year FROM private_isg.annual_work_plans WHERE plan_id=parent) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PLAN_YEAR_MISMATCH'; END IF;
    INSERT INTO private_isg.annual_work_plan_items(workspace_id,company_id,plan_id,activity,responsible_contact,planned_on,created_by_user_id,updated_by_user_id)
    VALUES(p_workspace,p_company,parent,private_isg.workspace_text(p_payload->>'activity',300),nullif(btrim(coalesce(p_payload->>'responsible_contact','')),''),(p_payload->>'planned_on')::date,actor,actor)
    RETURNING item_id,version INTO target,aggregate_version;
  ELSIF kind='board' AND action='create' THEN
    IF jsonb_typeof(p_payload->'agenda') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'agenda') NOT BETWEEN 1 AND 100 OR p_payload->>'applicability' NOT IN ('mandatory','voluntary') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    INSERT INTO private_isg.board_meetings(workspace_id,company_id,owner_id,workplace_id,applicability,counts_towards_legal_score,planned_on,agenda,created_by_user_id,updated_by_user_id)
    VALUES(p_workspace,p_company,NULL,(p_payload->>'workplace_id')::uuid,p_payload->>'applicability',p_payload->>'applicability'='mandatory',(p_payload->>'planned_on')::date,p_payload->'agenda',actor,actor)
    RETURNING meeting_id,version INTO target,aggregate_version;
  ELSIF kind='board_decision' AND action='create' THEN
    parent:=(p_payload->>'meeting_id')::uuid;
    PERFORM 1 FROM private_isg.board_meetings WHERE workspace_id=p_workspace AND company_id=p_company AND meeting_id=parent FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    INSERT INTO private_isg.board_decisions(workspace_id,company_id,meeting_id,decision_no,decision_text,responsible_contact,due_on,created_by_user_id,updated_by_user_id)
    VALUES(p_workspace,p_company,parent,(p_payload->>'decision_no')::integer,private_isg.workspace_text(p_payload->>'decision_text',2000),nullif(btrim(coalesce(p_payload->>'responsible_contact','')),''),(p_payload->>'due_on')::date,actor,actor)
    RETURNING decision_id,version INTO target,aggregate_version;
  ELSIF kind='work_permit' AND action='create' THEN
    IF jsonb_typeof(p_payload->'parties') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'parties')<1 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    INSERT INTO private_isg.work_permit_forms(workspace_id,company_id,owner_id,workplace_id,template_code,template_version,job_description,parties,planned_on,work_location,starts_at,ends_at,risk_precautions,workspace_asset_id,created_by_user_id,updated_by_user_id)
    VALUES(p_workspace,p_company,NULL,(p_payload->>'workplace_id')::uuid,p_payload->>'template_code',1,private_isg.workspace_text(p_payload->>'job_description',1000),p_payload->'parties',(p_payload->>'planned_on')::date,nullif(btrim(coalesce(p_payload->>'work_location','')),''),(p_payload->>'starts_at')::timestamptz,(p_payload->>'ends_at')::timestamptz,nullif(btrim(coalesce(p_payload->>'risk_precautions','')),''),asset,actor,actor)
    RETURNING permit_id,version INTO target,aggregate_version;
  ELSIF kind='site_visit' AND action='create' THEN
    INSERT INTO private_isg.site_visits(workspace_id,company_id,owner_id,workplace_id,visited_on,location_note,expert_note,responsible_contact,created_by_user_id,updated_by_user_id)
    VALUES(p_workspace,p_company,NULL,(p_payload->>'workplace_id')::uuid,(p_payload->>'visited_on')::date,nullif(btrim(coalesce(p_payload->>'location_note','')),''),private_isg.workspace_text(p_payload->>'expert_note',4000),nullif(btrim(coalesce(p_payload->>'responsible_contact','')),''),actor,actor)
    RETURNING visit_id,version INTO target,aggregate_version;
  ELSIF kind='site_observation' AND action='create' THEN
    parent:=(p_payload->>'visit_id')::uuid;
    PERFORM 1 FROM private_isg.site_visits WHERE workspace_id=p_workspace AND company_id=p_company AND visit_id=parent FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF p_payload->>'nonconformity_id' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private_isg.nonconformities WHERE workspace_id=p_workspace AND company_id=p_company AND nonconformity_id=(p_payload->>'nonconformity_id')::uuid) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    INSERT INTO private_isg.site_visit_observations(workspace_id,company_id,visit_id,note,workspace_asset_id,nonconformity_id,external_ref,created_by_user_id,updated_by_user_id)
    VALUES(p_workspace,p_company,parent,private_isg.workspace_text(p_payload->>'note',2000),asset,(p_payload->>'nonconformity_id')::uuid,nullif(btrim(coalesce(p_payload->>'external_ref','')),''),actor,actor)
    RETURNING observation_id,version INTO target,aggregate_version;
  ELSIF kind='notebook_archive' AND action='create' THEN
    INSERT INTO private_isg.notebook_archive_entries(workspace_id,company_id,owner_id,workplace_id,notebook_ref,entry_on,asset_id,workspace_asset_id,ai_draft_ref,created_by_user_id,updated_by_user_id)
    VALUES(p_workspace,p_company,NULL,(p_payload->>'workplace_id')::uuid,private_isg.workspace_text(p_payload->>'notebook_ref',200),(p_payload->>'entry_on')::date,NULL,asset,nullif(btrim(coalesce(p_payload->>'ai_draft_ref','')),''),actor,actor)
    RETURNING entry_id,version INTO target,aggregate_version;
  ELSE
    expected:=(p_payload->>'expected_version')::bigint;
    IF kind='katip_contract' AND action='archive' THEN
      SELECT to_jsonb(r) INTO before_state FROM private_isg.katip_contracts r WHERE workspace_id=p_workspace AND company_id=p_company AND contract_id=target AND version=expected AND NOT is_deleted FOR UPDATE;
      IF before_state IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      UPDATE private_isg.katip_contracts SET state='archived',version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp() WHERE contract_id=target RETURNING version INTO aggregate_version;
    ELSIF kind='annual_plan' AND action='close' THEN
      SELECT to_jsonb(r) INTO before_state FROM private_isg.annual_work_plans r WHERE workspace_id=p_workspace AND company_id=p_company AND plan_id=target AND version=expected AND state='active' FOR UPDATE;
      IF before_state IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      IF EXISTS(SELECT 1 FROM private_isg.annual_work_plan_items WHERE workspace_id=p_workspace AND company_id=p_company AND plan_id=target AND state='planned' AND NOT is_deleted) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='OPEN_PLAN_ITEMS'; END IF;
      UPDATE private_isg.annual_work_plans SET state='closed',closed_on=(clock_timestamp() AT TIME ZONE 'UTC')::date,version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp() WHERE plan_id=target RETURNING version INTO aggregate_version;
    ELSIF kind='annual_item' AND action IN ('perform','cancel','settle') THEN
      SELECT to_jsonb(i) INTO before_state FROM private_isg.annual_work_plan_items i WHERE workspace_id=p_workspace AND company_id=p_company AND item_id=target AND version=expected FOR UPDATE;
      IF before_state IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      IF action='settle' AND p_payload->>'state' NOT IN ('performed','carried_over','cancelled') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      IF coalesce(CASE action WHEN 'perform' THEN 'performed' WHEN 'cancel' THEN 'cancelled' ELSE p_payload->>'state' END,'')='carried_over' THEN
        PERFORM 1 FROM private_isg.annual_work_plans target_plan JOIN private_isg.annual_work_plan_items source_item ON source_item.item_id=target
          JOIN private_isg.annual_work_plans source_plan ON source_plan.plan_id=source_item.plan_id
          WHERE target_plan.workspace_id=p_workspace AND target_plan.company_id=p_company
            AND target_plan.plan_id=(p_payload->>'carried_to_plan_id')::uuid AND target_plan.plan_year=source_plan.plan_year+1;
        IF NOT FOUND OR length(btrim(coalesce(p_payload->>'reason','')))<10 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CARRY_OVER_INVALID'; END IF;
      END IF;
      UPDATE private_isg.annual_work_plan_items SET
        state=CASE action WHEN 'perform' THEN 'performed' WHEN 'cancel' THEN 'cancelled' ELSE p_payload->>'state' END,
        performed_on=CASE WHEN coalesce(CASE action WHEN 'perform' THEN 'performed' ELSE p_payload->>'state' END,'')='performed' THEN (p_payload->>'performed_on')::date END,
        carry_over_reason=CASE WHEN coalesce(CASE action WHEN 'cancel' THEN 'cancelled' ELSE p_payload->>'state' END,'') IN ('cancelled','carried_over') THEN private_isg.workspace_text(p_payload->>'reason',1000) END,
        carried_to_plan_id=CASE WHEN p_payload->>'state'='carried_over' THEN (p_payload->>'carried_to_plan_id')::uuid END,
        version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp()
      WHERE item_id=target RETURNING version INTO aggregate_version;
    ELSIF kind='board' AND action='hold' THEN
      IF jsonb_typeof(p_payload->'attendance') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'attendance')<1 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      SELECT count(*) INTO employee_count FROM private_isg.employees e JOIN jsonb_array_elements_text(p_payload->'attendance') a(employee_id) ON e.id=a.employee_id::uuid WHERE e.workspace_id=p_workspace AND e.company_id=p_company AND NOT e.is_archived;
      IF employee_count<>jsonb_array_length(p_payload->'attendance') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PARTICIPANT_INVALID'; END IF;
      SELECT to_jsonb(r) INTO before_state FROM private_isg.board_meetings r WHERE workspace_id=p_workspace AND company_id=p_company AND meeting_id=target AND version=expected AND state='planned' FOR UPDATE;
      IF before_state IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      UPDATE private_isg.board_meetings SET state='held',held_on=(p_payload->>'held_on')::date,attendance=(SELECT jsonb_agg(jsonb_build_object('id',e.id,'full_name',e.full_name)) FROM private_isg.employees e JOIN jsonb_array_elements_text(p_payload->'attendance') a(employee_id) ON e.id=a.employee_id::uuid),workspace_asset_id=coalesce(asset,workspace_asset_id),version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp() WHERE meeting_id=target RETURNING version INTO aggregate_version;
    ELSIF kind='board_decision' AND action='settle' THEN
      SELECT to_jsonb(r) INTO before_state FROM private_isg.board_decisions r WHERE workspace_id=p_workspace AND company_id=p_company AND decision_id=target AND version=expected FOR UPDATE;
      IF before_state IS NULL OR p_payload->>'state' NOT IN ('done','cancelled') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      UPDATE private_isg.board_decisions SET state=p_payload->>'state',version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp() WHERE decision_id=target RETURNING version INTO aggregate_version;
    ELSIF kind='work_permit' AND action='archive' THEN
      SELECT to_jsonb(r) INTO before_state FROM private_isg.work_permit_forms r WHERE workspace_id=p_workspace AND company_id=p_company AND permit_id=target AND version=expected AND NOT is_deleted FOR UPDATE;
      IF before_state IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      UPDATE private_isg.work_permit_forms SET state='archived',version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp() WHERE permit_id=target RETURNING version INTO aggregate_version;
    ELSIF kind='board' AND action='cancel' THEN
      SELECT to_jsonb(r) INTO before_state FROM private_isg.board_meetings r WHERE workspace_id=p_workspace AND company_id=p_company AND meeting_id=target AND version=expected AND state='planned' FOR UPDATE;
      IF before_state IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      UPDATE private_isg.board_meetings SET state='cancelled',cancelled_reason=private_isg.workspace_text(p_payload->>'reason',1000),version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp() WHERE meeting_id=target RETURNING version INTO aggregate_version;
    ELSE
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';
    END IF;
  END IF;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'kind',kind,'action',action,'id',target,'version',aggregate_version,'official_integration',false,'authorises_work',false,'ai_text_is_official_record',false);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'operations.'||kind||'.'||action,fingerprint,p_workspace,
    CASE kind WHEN 'katip_contract' THEN 'katip_contract' WHEN 'annual_plan' THEN 'annual_plan' WHEN 'annual_item' THEN 'annual_plan' WHEN 'board_decision' THEN 'board' WHEN 'site_observation' THEN 'site_visit' ELSE kind END,
    target,aggregate_version,before_state,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_operations_metrics(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM private_isg.workspace_domain_gate('operations',false); PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'measured',true,
    'katip_active',(SELECT count(*) FROM private_isg.katip_contracts WHERE workspace_id=p_workspace AND company_id=p_company AND state='active' AND NOT is_deleted),
    'annual_open_items',(SELECT count(*) FROM private_isg.annual_work_plan_items WHERE workspace_id=p_workspace AND company_id=p_company AND state='planned' AND NOT is_deleted),
    'board_open_decisions',(SELECT count(*) FROM private_isg.board_decisions WHERE workspace_id=p_workspace AND company_id=p_company AND state='open' AND NOT is_deleted),
    'work_permits',(SELECT count(*) FROM private_isg.work_permit_forms WHERE workspace_id=p_workspace AND company_id=p_company AND NOT is_deleted),
    'site_visits',(SELECT count(*) FROM private_isg.site_visits WHERE workspace_id=p_workspace AND company_id=p_company AND NOT is_deleted),
    'notebook_archives',(SELECT count(*) FROM private_isg.notebook_archive_entries WHERE workspace_id=p_workspace AND company_id=p_company));
END $$;

CREATE FUNCTION public.isg_workspace_operations_read_v1(p_workspace uuid,p_company uuid,p_kind text,p_id uuid DEFAULT NULL,p_after uuid DEFAULT NULL,p_limit integer DEFAULT 50) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_operations_read(p_workspace,p_company,p_kind,p_id,p_after,p_limit) $$;
CREATE FUNCTION public.isg_workspace_operations_mutate_v1(p_mutation uuid,p_workspace uuid,p_company uuid,p_payload jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_operations_mutate(p_mutation,p_workspace,p_company,p_payload) $$;
CREATE FUNCTION public.isg_workspace_operations_metrics_v1(p_workspace uuid,p_company uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_operations_metrics(p_workspace,p_company) $$;

REVOKE ALL ON FUNCTION private_isg.workspace_operation_root_invariant(),private_isg.workspace_operation_child_invariant(),private_isg.workspace_operation_asset(uuid,uuid,uuid,boolean),private_isg.workspace_operations_read(uuid,uuid,text,uuid,uuid,integer),private_isg.workspace_operations_mutate(uuid,uuid,uuid,jsonb),private_isg.workspace_operations_metrics(uuid,uuid),public.isg_workspace_operations_read_v1(uuid,uuid,text,uuid,uuid,integer),public.isg_workspace_operations_mutate_v1(uuid,uuid,uuid,jsonb),public.isg_workspace_operations_metrics_v1(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_operations_read(uuid,uuid,text,uuid,uuid,integer),private_isg.workspace_operations_mutate(uuid,uuid,uuid,jsonb),private_isg.workspace_operations_metrics(uuid,uuid),public.isg_workspace_operations_read_v1(uuid,uuid,text,uuid,uuid,integer),public.isg_workspace_operations_mutate_v1(uuid,uuid,uuid,jsonb),public.isg_workspace_operations_metrics_v1(uuid,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
