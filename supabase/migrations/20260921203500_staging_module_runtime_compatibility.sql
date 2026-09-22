-- Repair partially applied staging schema slices without weakening the current
-- tenant/RLS boundaries. These fixes are additive or qualify an ambiguous
-- source column; they do not broaden a user's data scope.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- The shared expert writer still accepts the legacy optional reference while
-- the current personal process flow uses asset_id. Keeping it nullable makes
-- both deployed clients safe during the transition.
ALTER TABLE private_isg.katip_contracts
  ADD COLUMN IF NOT EXISTS contract_location text
  CHECK (contract_location IS NULL OR length(contract_location) <= 300);

-- Personal findings never carried the workspace-only classification columns.
-- Preserve the complete score snapshot while supplying the two compatible
-- constants only in the personal-source branch.
DO $repair_analysis$
DECLARE
  definition text;
  marker text := 'ELSIF p_source_scope=''personal'' AND p_item_kind=''finding'' THEN';
  marker_at integer;
  prefix text;
  suffix text;
BEGIN
  SELECT pg_get_functiondef('private_isg.workspace_analysis_file(uuid,uuid,uuid,uuid,text,uuid,text,uuid,text,date,date)'::regprocedure)
    INTO definition;
  marker_at := strpos(definition, marker);
  IF marker_at = 0 THEN
    RAISE EXCEPTION 'workspace_analysis_file personal branch not found';
  END IF;
  prefix := left(definition, marker_at + length(marker) - 1);
  suffix := substr(definition, marker_at + length(marker));
  suffix := replace(suffix,
    '''is_scored'',f.is_scored,''item_class'',f.item_class',
    '''is_scored'',true,''item_class'',''risk_finding''');
  IF prefix || suffix = definition THEN
    RAISE EXCEPTION 'workspace_analysis_file compatibility replacement not applied';
  END IF;
  EXECUTE prefix || suffix;
END
$repair_analysis$;

-- PL/pgSQL's result variable shadowed checklist_run_items.result. Qualifying
-- the copied row fixes both company and personal revision paths.
DO $repair_checklists$
DECLARE
  signature text;
  definition text;
  patched text;
BEGIN
  FOREACH signature IN ARRAY ARRAY[
    'private_isg.mutate_checklists_company_v3(uuid,text,uuid,uuid,jsonb)',
    'private_isg.mutate_checklists(uuid,text,uuid,uuid,jsonb)'
  ] LOOP
    SELECT pg_get_functiondef(signature::regprocedure) INTO definition;
    patched := replace(definition,
      'SELECT revised,item_code,result,note,evidence_asset_id,stamp FROM private_isg.checklist_run_items',
      'SELECT revised,source.item_code,source.result,source.note,source.evidence_asset_id,stamp FROM private_isg.checklist_run_items source');
    IF patched = definition THEN
      RAISE EXCEPTION 'checklist compatibility replacement not applied: %', signature;
    END IF;
    EXECUTE patched;
  END LOOP;
END
$repair_checklists$;

NOTIFY pgrst, 'reload schema';
COMMIT;
