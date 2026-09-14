-- Link an existing company library entry. No new upload/storage path.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.katip_contracts ADD COLUMN file_entry_id uuid
  REFERENCES private_isg.file_library_entries(entry_id) ON DELETE RESTRICT;
ALTER TABLE private_isg.katip_contracts ADD COLUMN document_version bigint NOT NULL DEFAULT 0;
ALTER FUNCTION private_isg.katip_contract_row(uuid,date) RENAME TO katip_contract_row_base;
CREATE FUNCTION private_isg.katip_contract_row(p_contract uuid,p_today date) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT private_isg.katip_contract_row_base(p_contract,p_today)||jsonb_build_object(
   'file_entry_id',k.file_entry_id,'document_version',k.document_version,
   'document_title',f.title,'contract_stored',coalesce(f.asset_id IS NOT NULL AND NOT f.is_archived,false))
 FROM private_isg.katip_contracts k LEFT JOIN private_isg.file_library_entries f
   ON f.entry_id=k.file_entry_id AND f.company_id=k.company_id AND f.owner_id=k.owner_id
 WHERE k.contract_id=p_contract
$$;
ALTER FUNCTION private_isg.mutate_katip_contracts(uuid,text,uuid,uuid,jsonb) RENAME TO mutate_katip_contracts_base;
REVOKE ALL ON FUNCTION private_isg.mutate_katip_contracts_base(uuid,text,uuid,uuid,jsonb) FROM authenticated;
CREATE FUNCTION private_isg.mutate_katip_contracts(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; k private_isg.katip_contracts; f private_isg.file_library_entries;
 receipt private_isg.katip_receipts; fingerprint bytea; result jsonb; target uuid;
BEGIN
 IF p_action IS DISTINCT FROM 'link_document' THEN
   RETURN private_isg.mutate_katip_contracts_base(p_company,p_action,p_operation,p_mutation,p_payload);
 END IF;
 actor:=private_isg.require_katip_company(p_company,true);
 IF p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object'
   OR octet_length(p_payload::text)>4096 OR p_payload->>'contract_id' IS NULL
   OR p_payload->>'expected_version' IS NULL OR NOT p_payload ? 'file_entry_id' THEN
   RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) keys(key)
   WHERE key NOT IN ('contract_id','file_entry_id','expected_version')) THEN
   RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;
 fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
 PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-katip:'||p_mutation::text,0));
 SELECT * INTO receipt FROM private_isg.katip_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
 IF FOUND THEN
   IF receipt.request_hash<>fingerprint THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
   RETURN receipt.response||jsonb_build_object('replayed',true);
 END IF;
 SELECT * INTO k FROM private_isg.katip_contracts
   WHERE contract_id=(p_payload->>'contract_id')::uuid AND company_id=p_company AND owner_id=actor FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 IF k.state='archived' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CONTRACT_ARCHIVED'; END IF;
 IF k.document_version<>(p_payload->>'expected_version')::bigint THEN
   RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
 target:=(p_payload->>'file_entry_id')::uuid;
 IF target IS NOT NULL THEN
   PERFORM private_isg.require_file_library_company(p_company,false);
   SELECT * INTO f FROM private_isg.file_library_entries
     WHERE entry_id=target AND company_id=p_company AND owner_id=actor AND NOT is_archived FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
   IF f.asset_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DOCUMENT_NOT_READY'; END IF;
 END IF;
 UPDATE private_isg.katip_contracts SET file_entry_id=target,document_version=document_version+1
   WHERE contract_id=k.contract_id;
 result:=jsonb_build_object('schema_version',1,'contract_id',k.contract_id,
   'row',private_isg.katip_contract_row(k.contract_id,(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date),
   'official_submission_made',false);
 INSERT INTO private_isg.katip_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
 VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
 RETURN result||jsonb_build_object('replayed',false);
END $$;
REVOKE ALL ON FUNCTION private_isg.katip_contract_row(uuid,date),
 private_isg.mutate_katip_contracts(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.mutate_katip_contracts(uuid,text,uuid,uuid,jsonb) TO authenticated;
-- Rebind SQL wrapper after the implementation was renamed.
CREATE OR REPLACE FUNCTION public.isg_katip_mutate_v1(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
 SELECT private_isg.mutate_katip_contracts(p_company,p_action,p_operation,p_mutation,p_payload)
$$;
NOTIFY pgrst,'reload schema';
COMMIT;
