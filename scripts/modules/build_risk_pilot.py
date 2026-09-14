from pathlib import Path
import re
root=Path(__file__).resolve().parents[2]
a=(root/'supabase/migrations/20260913190000_isg_risk_versioning.sql').read_text()
b=(root/'supabase/migrations/20260915090000_isg_risk_versions.sql').read_text()
a=a[a.index('CREATE TABLE private_isg.risk_assessments'):]
a=a.replace('file_asset_id uuid REFERENCES private_isg.file_assets(asset_id)','file_asset_id uuid CHECK(file_asset_id IS NULL)')
a=a.replace('asset_id uuid NOT NULL REFERENCES private_isg.file_assets(asset_id)','asset_id uuid NOT NULL CHECK(asset_id IS NULL)')
a=a.replace('rule private_isg.rule_versions; ','')
a=re.sub(r"    IF p_rule_code IS NOT NULL THEN\n      SELECT \* INTO rule.*?years:=rule.period_length; source:='rule_version';", "    IF p_rule_code IS NOT NULL THEN\n      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RULE_NEEDS_REVIEW';",a,flags=re.S)
a=a.replace("valid:=private_isg.next_due_on(revision.assessment_on,'years',years);", "valid:=(revision.assessment_on+make_interval(years=>years))::date;")
a=re.sub(r"    PERFORM 1 FROM private_isg.file_assets.*?END IF;", "    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FILE_STORAGE_UNAVAILABLE';",a,flags=re.S,count=1)
a=a.replace("  PERFORM private_isg.risk_gate(true);\n  IF p_assessment IS NULL OR p_kind", "  PERFORM private_isg.risk_gate(true);\n  IF p_kind='rescan' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FILE_STORAGE_UNAVAILABLE'; END IF;\n  IF p_assessment IS NULL OR p_kind")
# The unavailable file operation has no dangling runtime table reference.
start=a.index('CREATE FUNCTION private_isg.attach_rescan_variant(');end=a.index('CREATE FUNCTION private_isg.finalize_risk_version(',start)
header=a[start:a.index('DECLARE',start)]
a=a[:start]+header+"BEGIN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FILE_STORAGE_UNAVAILABLE'; END $$;\n"+a[end:]
b=re.sub(r"'rules',\(SELECT coalesce\(jsonb_agg.*?r.period_kind='years'\)","'rules','[]'::jsonb",b,flags=re.S)
b=b.replace("jsonb_build_array('full','partial','metadata','rescan')", "jsonb_build_array('full','partial','metadata')")
b=b.replace('  PERFORM private_isg.risk_version_gate(p_write);', "  PERFORM private_isg.risk_version_gate(p_write);\n  IF NOT private_isg.p05_pilot_account_enabled(actor,p_write) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;\n  IF p_company IS NOT NULL AND NOT private_isg.p05_pilot_can_read(actor,p_company) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;")
b=b.replace('c.user_id=actor','c.user_id=actor AND private_isg.p05_pilot_can_read(actor,c.id)').replace('a.owner_id=actor AND NOT w.is_archived','a.owner_id=actor AND private_isg.p05_pilot_can_read(actor,a.company_id) AND NOT w.is_archived')
b=b.replace("  today:=(stamp AT TIME ZONE 'UTC')::date;", "  today:=(stamp AT TIME ZONE 'UTC')::date;\n  IF p_action NOT IN ('open_assessment','draft_version','finalize_version','record_impact') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;")
a=a.replace('    valid:=entry.valid_until;', "    valid:=entry.valid_until;\n    SELECT r.period_years,r.period_source,r.period_needs_review INTO years,source,review FROM private_isg.risk_assessment_versions r WHERE r.assessment_id=p_assessment AND r.version=entry.current_version;")
s=a+'\n'+b
s=re.sub(r'^BEGIN;|^COMMIT;', '', s, flags=re.M).replace("AT TIME ZONE 'UTC'","AT TIME ZONE 'Europe/Istanbul'").replace(' STABLE ',' VOLATILE ')
s=s.replace('REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;', 'REVOKE ALL ON private_isg.risk_assessments,private_isg.risk_assessment_versions,private_isg.risk_source_links,private_isg.revision_impacts,private_isg.risk_file_variants FROM PUBLIC,anon,authenticated,service_role;')
s=s.replace('CREATE INDEX risk_version_receipt_company_idx', 'REVOKE ALL ON private_isg.risk_version_receipts FROM PUBLIC,anon,authenticated,service_role;\nCREATE INDEX risk_version_receipt_company_idx')
# A superseded historical revision cannot be republished over the current version.
s=s.replace("  IF entry.current_version<>p_expected_current THEN RAISE EXCEPTION", "  IF revision.state='superseded' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_FINALIZED'; END IF;\n  IF entry.current_version<>p_expected_current THEN RAISE EXCEPTION",1) if False else s
# insert only in finalize function (draft has no revision variable)
needle="  IF revision.kind='full' THEN"
s=s.replace(needle,"  IF revision.state<>'draft' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_FINALIZED'; END IF;\n"+needle,1)
(root/'supabase/migrations/20260914221301_isg_pilot_risk_records.sql').write_text("-- Narrow pilot: expert records; no uploaded files or published legal rules.\nINSERT INTO private_isg.rollout(feature) VALUES('risk') ON CONFLICT DO NOTHING;\n"+s)
