BEGIN;
SET LOCAL lock_timeout='5s';
-- Forward-only staging fix for OSGB workspace companies, whose user_id is
-- deliberately NULL. Access still fails closed in mutate/read RPC scope.
ALTER TABLE private_isg.checklist_template_assignments
  ALTER COLUMN owner_id DROP NOT NULL;
COMMIT;
