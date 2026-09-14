from pathlib import Path
import re
root=Path(__file__).resolve().parents[2]
parts=["""DO $$ DECLARE expression text; BEGIN
SELECT pg_get_expr(conbin,conrelid) INTO expression FROM pg_constraint WHERE conrelid='private_isg.rollout'::regclass AND conname='rollout_feature_check';
IF expression IS NULL THEN RAISE EXCEPTION 'Missing rollout constraint'; END IF;
ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
EXECUTE format('ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check CHECK((%s) OR feature IN (''nonconformity'',''risk''))',expression);
END $$;"""]
for file in ['20260913210000_isg_nonconformity_core.sql','20260914170000_isg_nonconformity_owner_rpc.sql','20260914190000_isg_nonconformity_detail.sql','20260915110000_isg_checklist_runs.sql']:
 s=(root/'supabase/migrations'/file).read_text()
 s=re.sub(r'^BEGIN;\s*','',s,flags=re.M);s=re.sub(r'^COMMIT;\s*','',s,flags=re.M)
 s=re.sub(r'ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;[\s\S]*?INSERT INTO private_isg.rollout\(feature\) VALUES\(\'nonconformity\'\);',"INSERT INTO private_isg.rollout(feature) VALUES('nonconformity') ON CONFLICT DO NOTHING;",s)
 s=re.sub(r'(\w+) uuid REFERENCES private_isg.file_assets\(asset_id\)',r'\1 uuid CHECK(\1 IS NULL)',s)
 s=re.sub(r"  IF p_asset IS NOT NULL THEN\n    PERFORM 1 FROM private_isg.file_assets[\s\S]*?\n  END IF;","  IF p_asset IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FILE_STORAGE_UNAVAILABLE'; END IF;",s)
 names=re.findall(r'CREATE TABLE private_isg\.(\w+)',s)
 s=s.replace('REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;','\n'.join(f'REVOKE ALL ON private_isg.{n} FROM PUBLIC,anon,authenticated,service_role;' for n in names))
 s=s.replace('DECLARE actor uuid:=private_isg.active_actor();\nBEGIN', '''DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  IF NOT private_isg.p05_pilot_account_enabled(actor,p_write) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_company IS NOT NULL AND NOT private_isg.p05_pilot_can_read(actor,p_company) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;''')
 s=s.replace('WHERE c.user_id=actor AND NOT c.is_archived','WHERE c.user_id=actor AND NOT c.is_archived AND private_isg.p05_pilot_can_read(actor,c.id)')
 s=s.replace("AT TIME ZONE 'UTC'","AT TIME ZONE 'Europe/Istanbul'")
 s=s.replace('LANGUAGE plpgsql STABLE SECURITY DEFINER','LANGUAGE plpgsql VOLATILE SECURITY DEFINER')
 parts.append(s)
(root/'supabase/migrations/20260914215132_isg_pilot_findings_checklists.sql').write_text('\n'.join(parts))
