from pathlib import Path
import re
root=Path(__file__).resolve().parents[2]
core=(root/'supabase/migrations/20260914010000_isg_module_core_second.sql').read_text()
tables=['katip_contracts','annual_work_plans','annual_work_plan_items','board_meetings','board_decisions','work_permit_forms','site_visits','site_visit_observations']
s=["SET LOCAL lock_timeout='5s';", "ALTER TABLE private_isg.module_registry DROP CONSTRAINT module_registry_module_check;", "ALTER TABLE private_isg.module_registry ADD CONSTRAINT module_registry_module_check CHECK(module IN ('emergency_plan','drill','equipment','ppe','appointment','katip_contract','annual_work_plan','board','work_permit','site_visit','contractor'));", "INSERT INTO private_isg.module_registry(module) VALUES ('katip_contract'),('annual_work_plan'),('board'),('work_permit'),('site_visit'),('contractor');"]
for name in tables:
 t=re.search(r'CREATE TABLE private_isg\.'+name+r' \([\s\S]*?\n\);',core).group()
 t=re.sub(r'(\w+) uuid REFERENCES private_isg.file_assets\(asset_id\)',r'\1 uuid CHECK(\1 IS NULL)',t)
 t=t.replace('uuid REFERENCES private_isg.nonconformities(nonconformity_id) ON DELETE SET NULL','uuid CHECK(nonconformity_id IS NULL)')
 if name=='work_permit_forms':
  t=t.replace("  CHECK((state='draft')=(rendered_asset_id IS NULL)),",'')

 unique=re.search(r'  UNIQUE\(([^\n]+)\),',t)
 if unique:
  t=t.replace(unique.group(),'')
 s.extend([t,f'ALTER TABLE private_isg.{name} ADD COLUMN is_deleted boolean NOT NULL DEFAULT false;',f'ALTER TABLE private_isg.{name} ENABLE ROW LEVEL SECURITY;',f'REVOKE ALL ON private_isg.{name} FROM PUBLIC,anon,authenticated,service_role;'])
 if unique: s.append(f"CREATE UNIQUE INDEX {name}_active_identity ON private_isg.{name}({unique.group(1)}) WHERE NOT is_deleted;")
s.extend(["ALTER TABLE private_isg.katip_contracts ADD COLUMN declared_monthly_minutes integer CHECK(declared_monthly_minutes BETWEEN 1 AND 100000), ADD COLUMN declared_note text, ADD COLUMN contract_location text;", "ALTER TABLE private_isg.work_permit_forms ADD COLUMN work_location text, ADD COLUMN starts_at timestamptz, ADD COLUMN ends_at timestamptz, ADD COLUMN risk_precautions text;", "ALTER TABLE private_isg.site_visits ADD COLUMN responsible_contact text;", "ALTER TABLE private_isg.contractor_organizations ADD COLUMN contact text, ADD COLUMN identifiers text, ADD COLUMN notes text;", "ALTER TABLE private_isg.contractor_engagements ADD COLUMN is_deleted boolean NOT NULL DEFAULT false;"])
# Export/relationship metadata is kept out of the established domain tables.
s.append('''CREATE TABLE private_isg.process_record_meta (
 kind text NOT NULL,record_id uuid NOT NULL,company_id uuid NOT NULL,document_id uuid REFERENCES private_isg.document_obligations(obligation_id),
 related_kind text,related_id uuid,export_snapshot jsonb,PRIMARY KEY(kind,record_id));
CREATE TABLE private_isg.process_record_history (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),kind text NOT NULL,record_id uuid NOT NULL,company_id uuid NOT NULL,actor_id uuid NOT NULL,before_snapshot jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE private_isg.process_record_meta ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.process_record_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.process_record_meta,private_isg.process_record_history FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX process_meta_company_idx ON private_isg.process_record_meta(company_id);
CREATE INDEX process_meta_doc_idx ON private_isg.process_record_meta(document_id);
CREATE INDEX process_history_record_idx ON private_isg.process_record_history(kind,record_id);
''')
(root/'supabase/migrations/20260914213023_isg_pilot_remaining_records.sql').write_text('\n'.join(s)+'\n')
