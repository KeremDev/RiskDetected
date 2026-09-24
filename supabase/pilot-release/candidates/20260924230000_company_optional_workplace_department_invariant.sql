-- Departments may be company-wide only while the company has no workplaces.
-- Enforce this even for the personal-workspace compatibility write path.
BEGIN;
DO $patch$
DECLARE definition text; anchor text; replacement text; matches integer;
BEGIN
  definition:=pg_get_functiondef('private_isg.workspace_personnel_scope_invariant()'::regprocedure);
  anchor:=$old$BEGIN
  IF private_isg.workspace_is_legacy_company_write(NEW.company_id,NEW.workspace_id,$old$;
  replacement:=$new$BEGIN
  IF TG_TABLE_NAME='departments' THEN
    IF NOT private_isg.company_workplace_scope(NEW.company_id,NEW.workplace_id,NEW.workspace_id,
        CASE WHEN TG_OP='UPDATE' THEN OLD.workplace_id IS NULL ELSE false END) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='WORKPLACE_REQUIRED'; END IF;
  END IF;
  IF private_isg.workspace_is_legacy_company_write(NEW.company_id,NEW.workspace_id,$new$;
  matches:=(length(definition)-length(replace(definition,anchor,'')))/length(anchor);
  IF matches<>1 THEN RAISE EXCEPTION 'MIGRATION_SOURCE_DRIFT: %',matches; END IF;
  EXECUTE replace(definition,anchor,replacement);
END $patch$;
COMMIT;
