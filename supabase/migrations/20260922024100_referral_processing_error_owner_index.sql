BEGIN;
SET LOCAL lock_timeout = '5s';

-- Covers the owner foreign key used by referral processing diagnostics and cleanup.
CREATE INDEX IF NOT EXISTS referral_processing_errors_owner_idx
  ON private_isg.referral_processing_errors(owner_id);

COMMIT;
