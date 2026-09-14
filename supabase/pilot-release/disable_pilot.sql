-- MANUAL ONLY. Closes this approved pilot, never deletes companies/personnel.
-- Refuses to close the shared feature if another active pilot has been added.
BEGIN;
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='5s';
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM private_isg.p05_pilot_accounts
    WHERE approved_reference <> 'user-approved-p05-20260913-20260913201043'
      AND read_enabled AND revoked_at IS NULL AND expires_at>clock_timestamp()) THEN
    RAISE EXCEPTION 'OTHER_ACTIVE_PILOT_REQUIRES_SCOPED_ROLLBACK';
  END IF;
END $$;
-- Same lock order as creation: account before shared rollout.
UPDATE private_isg.p05_pilot_accounts
SET read_enabled=false,write_enabled=false,revoked_at=coalesce(revoked_at,clock_timestamp())
WHERE approved_reference='user-approved-p05-20260913-20260913201043';
UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='personnel';
COMMIT;
