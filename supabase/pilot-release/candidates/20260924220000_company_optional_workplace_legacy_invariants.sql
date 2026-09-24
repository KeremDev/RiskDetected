-- The personal-workspace compatibility branch of root triggers previously returned
-- before checking the company/workplace rule. Keep the branch, but validate scope.
BEGIN;
CREATE FUNCTION private_isg.migration_guard_legacy_scope(
  p_signature regprocedure, p_field text) RETURNS void
LANGUAGE plpgsql SET search_path TO '' AS $patch$
DECLARE definition text; old_branch text; new_branch text; matches integer;
BEGIN
  IF p_field NOT IN ('workplace_id','scope_workplace_id') THEN
    RAISE EXCEPTION 'UNSUPPORTED_SCOPE_FIELD'; END IF;
  definition:=pg_get_functiondef(p_signature);
  old_branch:=$old$IF private_isg.workspace_is_legacy_company_write(NEW.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;$old$;
  matches:=(length(definition)-length(replace(definition,old_branch,'')))/length(old_branch);
  IF matches<>1 THEN RAISE EXCEPTION 'MIGRATION_SOURCE_DRIFT: % found %',p_signature,matches; END IF;
  new_branch:=format($new$IF private_isg.workspace_is_legacy_company_write(NEW.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN
    IF NOT private_isg.company_workplace_scope(NEW.company_id,NEW.%I,NEW.workspace_id,
        CASE WHEN TG_OP='UPDATE' THEN OLD.%I IS NULL ELSE false END) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='WORKPLACE_REQUIRED'; END IF;
    RETURN NEW;
  END IF;$new$,p_field,p_field);
  EXECUTE replace(definition,old_branch,new_branch);
END $patch$;

SELECT private_isg.migration_guard_legacy_scope('private_isg.workspace_appointment_invariant()'::regprocedure,'scope_workplace_id');
SELECT private_isg.migration_guard_legacy_scope('private_isg.workspace_assurance_root_invariant()'::regprocedure,'workplace_id');
SELECT private_isg.migration_guard_legacy_scope('private_isg.workspace_drill_invariant()'::regprocedure,'workplace_id');
SELECT private_isg.migration_guard_legacy_scope('private_isg.workspace_emergency_plan_invariant()'::regprocedure,'workplace_id');
SELECT private_isg.migration_guard_legacy_scope('private_isg.workspace_equipment_item_invariant()'::regprocedure,'workplace_id');
SELECT private_isg.migration_guard_legacy_scope('private_isg.workspace_operation_root_invariant()'::regprocedure,'workplace_id');
SELECT private_isg.migration_guard_legacy_scope('private_isg.checklist_run_scope_invariant()'::regprocedure,'workplace_id');

DROP FUNCTION private_isg.migration_guard_legacy_scope(regprocedure,text);
COMMIT;
