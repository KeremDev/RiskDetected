ALTER TABLE private_isg.file_library_entries ALTER COLUMN asset_id DROP NOT NULL;
-- Isolated tag transaction fixture: upload/scan mechanics have separate P04 tests.
ALTER TABLE private_isg.file_library_entries ADD COLUMN intent_id uuid,ADD COLUMN category text,ADD COLUMN file_name text,ADD COLUMN note text,ADD COLUMN version bigint DEFAULT 1,ADD COLUMN updated_at timestamptz DEFAULT now();
ALTER TABLE private_isg.file_assets ADD COLUMN bucket text,ADD COLUMN immutable_path text,ADD COLUMN preview_status text;
CREATE TABLE private_isg.upload_intents(intent_id uuid PRIMARY KEY,state text,declared_extension text,declared_bytes bigint,received_bytes bigint,detected_type text,purpose text,expires_at timestamptz,quarantine_path text,rejection_code text);
CREATE TABLE private_isg.file_scan_results(intent_id uuid,scanner text,finding_code text);
CREATE TABLE private_isg.file_scanners(scanner text,assurance text,detects_malware bool);
CREATE TABLE private_isg.file_library_categories(category text PRIMARY KEY,section text);
INSERT INTO private_isg.file_library_categories VALUES('other','files');
CREATE TABLE private_isg.file_library_receipts(actor_id uuid,mutation_id uuid,company_id uuid,operation_id uuid,request_hash bytea,response jsonb,PRIMARY KEY(actor_id,mutation_id));
CREATE FUNCTION private_isg.require_file_library_company(c uuid,w bool) RETURNS uuid LANGUAGE sql AS $$ SELECT private_isg.process_guard('approved_notebook',c,w) $$;
CREATE FUNCTION private_isg.file_library_purpose(e text) RETURNS text LANGUAGE sql AS $$ SELECT 'document'::text $$;
CREATE FUNCTION private_isg.open_upload_intent(a uuid,c uuid,p text,e text,b bigint,h bytea,o uuid,m uuid,x uuid,f bool,n int,s timestamptz) RETURNS jsonb LANGUAGE plpgsql AS $$ DECLARE id uuid:=gen_random_uuid(); BEGIN INSERT INTO private_isg.upload_intents(intent_id,state,declared_extension,declared_bytes,purpose) VALUES(id,'pending',e,b,p); RETURN jsonb_build_object('intent_id',id); END $$;
CREATE FUNCTION private_isg.reject_upload_intent(i uuid,c text,s timestamptz) RETURNS void LANGUAGE sql AS $$ UPDATE private_isg.upload_intents SET state='expired' WHERE intent_id=i $$;

ALTER TABLE private_isg.equipment_inspections ADD COLUMN evidence_asset_id uuid;
