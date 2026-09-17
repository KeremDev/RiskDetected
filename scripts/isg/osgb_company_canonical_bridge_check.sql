\set ON_ERROR_STOP on
UPDATE private_isg.workspace_rollout SET read_enabled=true,write_enabled=true;

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
SELECT public.isg_personal_workspace_ensure_v1('b1000000-0000-4000-8000-000000000001');
INSERT INTO public.companies(user_id,name,hazard_class)
VALUES('20000000-0000-0000-0000-000000000001','Eski Kişisel Firma','medium');

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000004',false);
INSERT INTO public.companies(user_id,name,hazard_class)
VALUES('20000000-0000-0000-0000-000000000004','Eşlenmeyi Bekleyen Firma','low');

DO $$ DECLARE dry jsonb; BEGIN
  dry:=private_isg.workspace_company_backfill_batch('b1000000-0000-4000-8000-000000000002',
    repeat('a',64),NULL,250,false);
  IF (dry->>'blocked')::integer<>1 OR (dry->>'mapped')::integer<>1 THEN
    RAISE EXCEPTION 'unexpected dry-run %',dry; END IF;
END $$;

SELECT public.isg_personal_workspace_ensure_v1('b1000000-0000-4000-8000-000000000003');
SELECT private_isg.workspace_company_backfill_batch('b1000000-0000-4000-8000-000000000004',
  repeat('b',64),NULL,250,true);

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
SELECT body->>'workspace_id' workspace_id FROM (
  SELECT public.isg_osgb_workspace_create_v1('b1000000-0000-4000-8000-000000000005',
    'Kanonik OSGB','Europe/Istanbul') body
) created \gset
UPDATE private_isg.workspaces SET status='active' WHERE id=:'workspace_id'::uuid;
SELECT body->>'company_id' company_id FROM (
  SELECT public.isg_workspace_company_create_v1('b1000000-0000-4000-8000-000000000006',
    :'workspace_id'::uuid,'OSGB Firması','high') body
) company \gset

SELECT public.isg_workspace_company_update_v1('b1000000-0000-4000-8000-000000000007',
  :'workspace_id'::uuid,:'company_id'::uuid,0,'OSGB Firması Güncel','medium');
SELECT set_config('test.workspace',:'workspace_id',false),set_config('test.company',:'company_id',false);

DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.companies c JOIN private_isg.workspace_companies w ON w.id=c.id
      WHERE c.id=current_setting('test.company')::uuid AND c.workspace_id=current_setting('test.workspace')::uuid AND c.user_id IS NULL
        AND c.name='OSGB Firması Güncel' AND w.name=c.name AND w.legacy_company_id=c.id AND w.version=1) OR
     (SELECT count(*) FROM public.companies c JOIN private_isg.workspace_companies w ON w.id=c.id
      JOIN private_isg.workspaces s ON s.id=c.workspace_id
      WHERE c.user_id IS NOT NULL AND s.kind='personal' AND s.personal_owner_user_id=c.user_id)<>2 THEN
    RAISE EXCEPTION 'canonical company mapping invariant failed'; END IF;
END $$;

SELECT public.isg_workspace_company_archive_v1('b1000000-0000-4000-8000-000000000008',
  :'workspace_id'::uuid,:'company_id'::uuid,1,'müşteri arşiv talebi');

DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.companies c JOIN private_isg.workspace_companies w ON w.id=c.id
    WHERE c.id=current_setting('test.company')::uuid AND c.is_archived AND w.status='archived' AND w.version=2) THEN
    RAISE EXCEPTION 'canonical archive mismatch'; END IF;
  RAISE NOTICE 'ok personal legacy mapping, dry-run backfill, OSGB canonical create, update and archive';
END $$;
