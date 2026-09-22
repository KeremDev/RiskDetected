-- The guided education editor is the single training experience for the
-- personal expert, OSGB expert and OSGB workspace surfaces.  The catalogue
-- control used to be left disabled after the v3 schema landed, which made
-- the client deliberately fall back to the old one-page v2 form.  Keep
-- certificate issuing separately gated, but make the training record flow
-- available to every already-authorized expert context.
BEGIN;

UPDATE private_isg.education_controls
   SET enabled = true
 WHERE key = 'catalog_v1';

NOTIFY pgrst, 'reload schema';
COMMIT;
