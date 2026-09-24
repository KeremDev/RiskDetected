-- A company run may cover the whole company when it has no workplaces.
-- The start/run authorization function enforces the conditional workplace choice.
BEGIN;
ALTER TABLE private_isg.checklist_runs
  DROP CONSTRAINT checklist_runs_scope_shape_check;
ALTER TABLE private_isg.checklist_runs
  ADD CONSTRAINT checklist_runs_scope_shape_check CHECK (
    company_id IS NOT NULL OR (company_id IS NULL AND workplace_id IS NULL AND owner_id IS NOT NULL)
  );
COMMIT;
