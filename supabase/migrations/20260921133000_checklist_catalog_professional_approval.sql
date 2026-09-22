-- Record the product-owner/domain-expert approval given for the staging pilot.
-- This does not turn the catalogue into a legal-compliance verdict; it only
-- closes the explicit professional-review gate carried by every catalogue row.
BEGIN;
SET LOCAL lock_timeout='5s';

ALTER TABLE private_isg.checklist_catalogs
  ADD COLUMN IF NOT EXISTS professional_reviewed_at timestamptz,
  ADD COLUMN IF NOT EXISTS professional_review_note text;

UPDATE private_isg.checklist_catalogs
SET professional_review_status='approved',
    publication_status='pilot_approved',
    professional_reviewed_at=coalesce(professional_reviewed_at,clock_timestamp()),
    professional_review_note='Pilot kullanım için ürün sahibi ve alan uzmanı onayı alındı; saha kapsamı ve mevzuat sorumluluğu uygulayıcı uzmandadır.'
WHERE catalog_version='checklist-tr-2026-09-15-v1';

UPDATE private_isg.checklist_atomic_items
SET professional_review_status='approved',
    professional_reviewed_at=coalesce(professional_reviewed_at,clock_timestamp())
WHERE catalog_version='checklist-tr-2026-09-15-v1';

UPDATE private_isg.checklist_catalog_templates
SET professional_review_status='approved'
WHERE catalog_version='checklist-tr-2026-09-15-v1';

UPDATE private_isg.checklist_templates
SET professional_review_status='approved'
WHERE catalog_version='checklist-tr-2026-09-15-v1'
  AND owner_id IS NULL AND workspace_id IS NULL;

DO $$
DECLARE catalog_rows integer; pending_atoms integer; pending_templates integer;
BEGIN
  SELECT count(*) INTO catalog_rows FROM private_isg.checklist_catalogs
    WHERE catalog_version='checklist-tr-2026-09-15-v1'
      AND professional_review_status='approved' AND publication_status='pilot_approved';
  SELECT count(*) INTO pending_atoms FROM private_isg.checklist_atomic_items
    WHERE catalog_version='checklist-tr-2026-09-15-v1' AND professional_review_status<>'approved';
  SELECT count(*) INTO pending_templates FROM private_isg.checklist_catalog_templates
    WHERE catalog_version='checklist-tr-2026-09-15-v1' AND professional_review_status<>'approved';
  IF catalog_rows<>1 OR pending_atoms<>0 OR pending_templates<>0 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CHECKLIST_APPROVAL_INCOMPLETE';
  END IF;
END $$;

NOTIFY pgrst,'reload schema';
COMMIT;
