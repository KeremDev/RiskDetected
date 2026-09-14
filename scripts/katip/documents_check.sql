SELECT pg_temp.katip(:'CA','record_contract',jsonb_build_object('workplace_id',:'WA',
 'counterparty','Document contract','expert_contact','Expert','scope','Documents','starts_on','2026-01-01'))->>'contract_id' AS id \gset doc_
INSERT INTO private_isg.file_library_entries VALUES
 ('60000000-0000-0000-0000-000000000001',:'CA',:'A',gen_random_uuid(),'Ready',false),
 ('60000000-0000-0000-0000-000000000002',:'CB',:'A',gen_random_uuid(),'Wrong company',false),
 ('60000000-0000-0000-0000-000000000003',:'CA',:'A',NULL,'Pending',false),
 ('60000000-0000-0000-0000-000000000004',:'CA',:'A',gen_random_uuid(),'Archived',true);
CREATE FUNCTION pg_temp.link(k uuid,f uuid,v bigint) RETURNS jsonb LANGUAGE sql AS $$
 SELECT pg_temp.katip('10000000-0000-0000-0000-000000000001','link_document',
 jsonb_build_object('contract_id',k,'file_entry_id',f,'expected_version',v))
$$;
SELECT pg_temp.expect_refusal(format('SELECT pg_temp.link(%L,%L,0)',:'doc_id','60000000-0000-0000-0000-000000000002'),'ACCESS_DENIED','other company file refused');
SELECT pg_temp.expect_refusal(format('SELECT pg_temp.link(%L,%L,0)',:'doc_id','60000000-0000-0000-0000-000000000003'),'DOCUMENT_NOT_READY','pending file refused');
SELECT pg_temp.expect_refusal(format('SELECT pg_temp.link(%L,%L,0)',:'doc_id','60000000-0000-0000-0000-000000000004'),'ACCESS_DENIED','archived file refused');
SELECT gen_random_uuid() AS operation,gen_random_uuid() AS mutation \gset doc_
SELECT public.isg_katip_mutate_v1(:'CA','link_document',:'doc_operation',:'doc_mutation',jsonb_build_object(
 'contract_id',:'doc_id','file_entry_id','60000000-0000-0000-0000-000000000001','expected_version',0)) AS value \gset linked_
SELECT pg_temp.expect(:'linked_value'::jsonb#>>'{row,contract_stored}','true','linked ready file stored');
SELECT pg_temp.expect(:'linked_value'::jsonb#>>'{row,document_version}','1','link advances version');
SELECT pg_temp.expect(public.isg_katip_mutate_v1(:'CA','link_document',:'doc_operation',:'doc_mutation',jsonb_build_object(
 'contract_id',:'doc_id','file_entry_id','60000000-0000-0000-0000-000000000001','expected_version',0))->>'replayed','true','link replay preserves receipt');
SELECT pg_temp.expect_refusal(format('SELECT pg_temp.link(%L,NULL,0)',:'doc_id'),'VERSION_CONFLICT','stale unlink refused');
SELECT pg_temp.expect(pg_temp.link(:'doc_id',NULL,1)#>>'{row,contract_stored}','false','unlink clears association');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.file_library_entries),'4','unlink retains all library files');
SELECT pg_temp.expect(has_function_privilege('authenticated','private_isg.mutate_katip_contracts_base(uuid,text,uuid,uuid,jsonb)','EXECUTE')::text,'false','old implementation not exposed');
SELECT 'PASS: KATIP document link boundary';
UPDATE private_isg.file_library_entries SET owner_id='20000000-0000-0000-0000-000000000002'
 WHERE entry_id='60000000-0000-0000-0000-000000000001';
SELECT pg_temp.expect_refusal(format('SELECT pg_temp.link(%L,%L,2)',:'doc_id','60000000-0000-0000-0000-000000000001'),'ACCESS_DENIED','other owner file refused');
UPDATE private_isg.file_library_entries SET owner_id=:'A' WHERE entry_id='60000000-0000-0000-0000-000000000001';
SELECT pg_temp.link(:'doc_id','60000000-0000-0000-0000-000000000001',2);
UPDATE private_isg.file_library_entries SET is_archived=true WHERE entry_id='60000000-0000-0000-0000-000000000001';
SELECT pg_temp.expect(public.isg_katip_read_v1(:'CA','detail',NULL,NULL,NULL,:'doc_id',10,0)#>>'{row,contract_stored}','false','archiving library entry revokes availability');
SELECT pg_temp.katip(:'CA','archive_contract',jsonb_build_object('contract_id',:'doc_id'));
SELECT pg_temp.expect_refusal(format('SELECT pg_temp.link(%L,NULL,3)',:'doc_id'),'CONTRACT_ARCHIVED','archived contract link unchanged');
