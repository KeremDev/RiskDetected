-- Bring legacy workplace rows into their company's existing workspace. These
-- rows were created before workspace_id was populated and would otherwise be
-- invisible to workspace scoped foreign keys and scope checks.
BEGIN;

ALTER TABLE private_isg.workplaces DISABLE TRIGGER workplaces_workspace_scope_before;
UPDATE private_isg.workplaces w SET workspace_id=c.workspace_id
FROM public.companies c JOIN private_isg.workspaces ws ON ws.id=c.workspace_id
WHERE w.company_id=c.id AND w.workspace_id IS NULL AND c.workspace_id IS NOT NULL
  AND ((ws.kind='personal' AND w.owner_id=c.user_id)
    OR (ws.kind='osgb' AND w.owner_id IS NULL));
ALTER TABLE private_isg.workplaces ENABLE TRIGGER workplaces_workspace_scope_before;

CREATE OR REPLACE FUNCTION private_isg.company_workplace_scope(
  p_company uuid, p_workplace uuid, p_workspace uuid, p_existing boolean DEFAULT false)
RETURNS boolean LANGUAGE sql STABLE SET search_path TO '' AS $scope$
  SELECT CASE WHEN p_workplace IS NULL THEN p_existing OR NOT EXISTS (
    SELECT 1 FROM private_isg.workplaces w WHERE w.company_id=p_company AND NOT w.is_archived
  ) ELSE EXISTS (
    SELECT 1 FROM private_isg.workplaces w WHERE w.company_id=p_company
      AND w.id=p_workplace AND NOT w.is_archived
      AND (p_workspace IS NULL OR w.workspace_id=p_workspace OR w.workspace_id IS NULL)
  ) END;
$scope$;

DO $patch$
DECLARE definition text;
BEGIN
  definition:=pg_get_functiondef('private_isg.module_scope(text,uuid,uuid,boolean)'::regprocedure);
  IF position('w.company_id=p_company AND w.workspace_id=private_isg.expert_workspace()' IN definition)=0 THEN
    RAISE EXCEPTION 'MIGRATION_SOURCE_DRIFT: module_scope'; END IF;
  definition:=replace(definition,
    'w.company_id=p_company AND w.workspace_id=private_isg.expert_workspace()',
    'w.company_id=p_company');
  definition:=replace(definition,
    'AND w.workspace_id=private_isg.expert_workspace() AND NOT w.is_archived',
    'AND (w.workspace_id=private_isg.expert_workspace() OR w.workspace_id IS NULL) AND NOT w.is_archived');
  EXECUTE definition;

  definition:=pg_get_functiondef('private_isg.workspace_equipment_item_invariant()'::regprocedure);
  IF position('w.workspace_id=NEW.workspace_id' IN definition)=0 THEN
    RAISE EXCEPTION 'MIGRATION_SOURCE_DRIFT: workspace_equipment_item_invariant'; END IF;
  definition:=replace(definition,
    'SELECT 1 FROM private_isg.workplaces w WHERE w.workspace_id=NEW.workspace_id
        AND w.company_id=NEW.company_id AND NOT w.is_archived',
    'SELECT 1 FROM private_isg.workplaces w WHERE w.company_id=NEW.company_id
        AND NOT w.is_archived');
  EXECUTE definition;
END $patch$;
COMMIT;
