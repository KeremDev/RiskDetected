-- Checklist runs are the only assurance root that may deliberately have no
-- company/workplace. Keep the common invariant for company runs and make the
-- personal shape explicit instead of weakening the shared trigger.
BEGIN;
CREATE FUNCTION private_isg.checklist_run_scope_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE company public.companies; workspace private_isg.workspaces;
BEGIN
  IF NEW.company_id IS NULL THEN
    IF NEW.workplace_id IS NOT NULL OR NEW.owner_id IS NULL OR
       NEW.created_by_user_id IS NULL OR NEW.updated_by_user_id IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PERSONAL_CHECKLIST_SCOPE_CONFLICT'; END IF;
    IF NEW.workspace_id IS NOT NULL THEN
      SELECT * INTO workspace FROM private_isg.workspaces WHERE id=NEW.workspace_id FOR SHARE;
      IF workspace.id IS NULL OR workspace.kind<>'osgb' THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PERSONAL_CHECKLIST_SCOPE_CONFLICT'; END IF;
    END IF;
    IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.owner_id,NEW.workplace_id,NEW.created_by_user_id)
      IS DISTINCT FROM ROW(OLD.workspace_id,OLD.company_id,OLD.owner_id,OLD.workplace_id,OLD.created_by_user_id) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE'; END IF;
    RETURN NEW;
  END IF;

  IF private_isg.workspace_is_legacy_company_write(NEW.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  SELECT * INTO company FROM public.companies WHERE id=NEW.company_id FOR SHARE;
  IF company.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='COMPANY_NOT_FOUND'; END IF;
  IF NEW.workspace_id IS NULL THEN NEW.workspace_id:=company.workspace_id; END IF;
  IF NEW.workspace_id IS DISTINCT FROM company.workspace_id THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='COMPANY_SCOPE_CONFLICT'; END IF;
  IF NEW.workspace_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO workspace FROM private_isg.workspaces WHERE id=NEW.workspace_id;
  IF workspace.kind='osgb' AND NEW.owner_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEGACY_OWNER_FORBIDDEN'; END IF;
  IF workspace.kind='personal' AND NEW.owner_id IS DISTINCT FROM company.user_id THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEGACY_OWNER_MISMATCH'; END IF;
  IF NOT EXISTS(SELECT 1 FROM private_isg.workplaces w WHERE w.workspace_id=NEW.workspace_id
      AND w.company_id=NEW.company_id AND w.id=NEW.workplace_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='WORKPLACE_SCOPE_CONFLICT'; END IF;
  IF NEW.created_by_user_id IS NULL OR NEW.updated_by_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACTOR_REQUIRED'; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.owner_id,NEW.workplace_id,NEW.created_by_user_id)
    IS DISTINCT FROM ROW(OLD.workspace_id,OLD.company_id,OLD.owner_id,OLD.workplace_id,OLD.created_by_user_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE'; END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS checklist_runs_workspace_scope_before ON private_isg.checklist_runs;
CREATE TRIGGER checklist_runs_workspace_scope_before BEFORE INSERT OR UPDATE
  ON private_isg.checklist_runs FOR EACH ROW EXECUTE FUNCTION private_isg.checklist_run_scope_invariant();
REVOKE ALL ON FUNCTION private_isg.checklist_run_scope_invariant()
  FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
