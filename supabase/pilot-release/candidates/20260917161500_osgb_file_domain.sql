-- D7 workspace file library, logical filing and legacy locator bridge.
-- NOT DEPLOYED; domain flag `files` remains OFF by default.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='30s';

ALTER TABLE private_isg.workspace_audit DROP CONSTRAINT workspace_audit_entity_type_check;
ALTER TABLE private_isg.workspace_audit ADD CONSTRAINT workspace_audit_entity_type_check CHECK(entity_type IN
  ('workspace','membership','invitation','company','assignment','seat','subscription','wallet','asset','handover',
   'workplace','department','employee','domain','training','risk','nonconformity','checklist','emergency_plan',
   'drill','appointment','ppe','equipment','katip_contract','annual_plan','board','work_permit','site_visit',
   'notebook_archive','file_entry','file_reference'));
ALTER TABLE private_isg.workspace_outbox DROP CONSTRAINT workspace_outbox_aggregate_type_check;
ALTER TABLE private_isg.workspace_outbox ADD CONSTRAINT workspace_outbox_aggregate_type_check CHECK(aggregate_type IN
  ('workspace','membership','invitation','company','assignment','seat','subscription','wallet','asset','handover',
   'workplace','department','employee','domain','training','risk','nonconformity','checklist','emergency_plan',
   'drill','appointment','ppe','equipment','katip_contract','annual_plan','board','work_permit','site_visit',
   'notebook_archive','file_entry','file_reference'));

ALTER TABLE private_isg.workspace_file_assets
  ADD CONSTRAINT workspace_file_assets_workspace_identity_unique UNIQUE(workspace_id,id);
ALTER TABLE private_isg.workspace_file_assets ADD COLUMN media_type text;
ALTER TABLE private_isg.workspace_file_assets ADD COLUMN extension text;
ALTER TABLE private_isg.workspace_file_assets ADD CONSTRAINT workspace_asset_media_type_check
  CHECK(media_type IS NULL OR octet_length(media_type) BETWEEN 3 AND 120);
ALTER TABLE private_isg.workspace_file_assets ADD CONSTRAINT workspace_asset_extension_check
  CHECK(extension IS NULL OR extension ~ '^[a-z0-9]{1,12}$');
UPDATE private_isg.workspace_file_assets a SET media_type=i.media_type,extension=i.extension
  FROM private_isg.workspace_upload_intents i WHERE i.asset_id=a.id;

CREATE TABLE private_isg.workspace_file_categories (
  code text PRIMARY KEY CHECK(code IN ('company_logo','risk_assessment','emergency_plan','training_material',
    'inspection_report','measurement_report','accident_record','board_document','handover_form',
    'personnel_document','contract','permit_form','visit_evidence','notebook_archive','other')),
  ordinal integer NOT NULL UNIQUE CHECK(ordinal BETWEEN 1 AND 999),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO private_isg.workspace_file_categories(code,ordinal) VALUES
  ('company_logo',1),('risk_assessment',2),('emergency_plan',3),('training_material',4),
  ('inspection_report',5),('measurement_report',6),('accident_record',7),('board_document',8),
  ('handover_form',9),('personnel_document',10),('contract',11),('permit_form',12),
  ('visit_evidence',13),('notebook_archive',14),('other',15);

CREATE TABLE private_isg.workspace_file_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  company_id uuid,
  category text NOT NULL REFERENCES private_isg.workspace_file_categories(code),
  visibility text NOT NULL CHECK(visibility IN ('company_team','workspace_management','member_private')),
  private_to_membership_id uuid,
  title text NOT NULL CHECK(octet_length(title) BETWEEN 1 AND 320),
  original_filename text NOT NULL CHECK(octet_length(original_filename) BETWEEN 1 AND 400),
  note text CHECK(note IS NULL OR octet_length(note)<=2000),
  tags text[] NOT NULL DEFAULT '{}',
  active_revision integer NOT NULL DEFAULT 1 CHECK(active_revision>0),
  state text NOT NULL DEFAULT 'active' CHECK(state IN ('active','archived')),
  created_by_user_id uuid NOT NULL,
  updated_by_user_id uuid NOT NULL,
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  archived_at timestamptz,
  UNIQUE(workspace_id,id),
  UNIQUE(workspace_id,company_id,id),
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,private_to_membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT,
  CHECK(cardinality(tags)<=12),
  CHECK((visibility='company_team' AND company_id IS NOT NULL AND private_to_membership_id IS NULL) OR
        (visibility='workspace_management' AND company_id IS NULL AND private_to_membership_id IS NULL) OR
        (visibility='member_private' AND company_id IS NULL AND private_to_membership_id IS NOT NULL)),
  CHECK((state='archived')=(archived_at IS NOT NULL))
);

CREATE TABLE private_isg.workspace_file_versions (
  workspace_id uuid NOT NULL,
  entry_id uuid NOT NULL,
  revision integer NOT NULL CHECK(revision>0),
  asset_id uuid NOT NULL,
  created_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(entry_id,revision),
  UNIQUE(workspace_id,entry_id,revision),
  FOREIGN KEY(workspace_id,entry_id) REFERENCES private_isg.workspace_file_entries(workspace_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,asset_id) REFERENCES private_isg.workspace_file_assets(workspace_id,id) ON DELETE RESTRICT
);

CREATE TABLE private_isg.workspace_file_references (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  entry_id uuid NOT NULL,
  entry_revision integer NOT NULL,
  asset_id uuid NOT NULL,
  parent_kind text NOT NULL CHECK(parent_kind IN ('company','employee','training','risk_assessment',
    'nonconformity','checklist','emergency_plan','drill','appointment','ppe','equipment',
    'equipment_inspection','katip_contract','annual_plan','board','work_permit','site_visit',
    'site_observation','notebook_archive')),
  parent_id uuid NOT NULL,
  field_name text NOT NULL CHECK(field_name ~ '^[a-z][a-z0-9_]{0,79}$'),
  created_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  archived_at timestamptz,
  UNIQUE(workspace_id,company_id,parent_kind,parent_id,field_name,entry_id,entry_revision),
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,entry_id,entry_revision)
    REFERENCES private_isg.workspace_file_versions(workspace_id,entry_id,revision) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,asset_id) REFERENCES private_isg.workspace_file_assets(workspace_id,id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX workspace_file_reference_active_field
  ON private_isg.workspace_file_references(workspace_id,company_id,parent_kind,parent_id,field_name)
  WHERE archived_at IS NULL AND field_name IN ('logo','signed_copy','report','minutes','rendered_document');

CREATE TABLE private_isg.workspace_legacy_file_inventory (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  source_kind text NOT NULL CHECK(source_kind IN ('company_logo','photo','report','document')),
  bucket text NOT NULL CHECK(octet_length(bucket) BETWEEN 1 AND 100),
  object_path text NOT NULL CHECK(octet_length(object_path) BETWEEN 1 AND 1000),
  discovered_bytes bigint CHECK(discovered_bytes IS NULL OR discovered_bytes>0),
  discovered_version text,
  status text NOT NULL DEFAULT 'discovered' CHECK(status IN ('discovered','migrated','missing')),
  migrated_asset_id uuid,
  discovered_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  checked_at timestamptz,
  UNIQUE(workspace_id,bucket,object_path),
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,migrated_asset_id) REFERENCES private_isg.workspace_file_assets(workspace_id,id) ON DELETE RESTRICT,
  CHECK((status='migrated')=(migrated_asset_id IS NOT NULL))
);
INSERT INTO private_isg.workspace_legacy_file_inventory(workspace_id,company_id,source_kind,bucket,object_path)
SELECT workspace_id,id,'company_logo','logos',logo_path FROM public.companies
WHERE workspace_id IS NOT NULL AND logo_path IS NOT NULL AND btrim(logo_path)<>''
ON CONFLICT(workspace_id,bucket,object_path) DO NOTHING;

CREATE TABLE private_isg.workspace_legacy_download_intents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  legacy_file_id uuid NOT NULL REFERENCES private_isg.workspace_legacy_file_inventory(id) ON DELETE RESTRICT,
  membership_id uuid NOT NULL,
  token_hash bytea NOT NULL UNIQUE CHECK(octet_length(token_hash)=32),
  status text NOT NULL DEFAULT 'issued' CHECK(status IN ('issued','claimed','expired','revoked')),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  claimed_at timestamptz,
  FOREIGN KEY(workspace_id,membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT,
  CHECK(expires_at>created_at)
);

ALTER TABLE public.companies ADD COLUMN workspace_logo_entry_id uuid;
ALTER TABLE public.companies ADD CONSTRAINT companies_workspace_logo_entry_fk
  FOREIGN KEY(workspace_id,workspace_logo_entry_id)
  REFERENCES private_isg.workspace_file_entries(workspace_id,id) ON DELETE RESTRICT;

CREATE INDEX workspace_file_entry_page ON private_isg.workspace_file_entries
  (workspace_id,company_id,state,category,updated_at DESC,id);
CREATE INDEX workspace_file_reference_parent ON private_isg.workspace_file_references
  (workspace_id,company_id,parent_kind,parent_id,archived_at,id);
CREATE INDEX workspace_file_version_asset ON private_isg.workspace_file_versions(workspace_id,asset_id);
CREATE INDEX workspace_legacy_file_company ON private_isg.workspace_legacy_file_inventory(workspace_id,company_id,status,id);

ALTER TABLE private_isg.workspace_file_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_file_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_file_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_file_references ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_legacy_file_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_legacy_download_intents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_file_categories,private_isg.workspace_file_entries,
  private_isg.workspace_file_versions,private_isg.workspace_file_references,
  private_isg.workspace_legacy_file_inventory,private_isg.workspace_legacy_download_intents
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.workspace_file_asset(p_workspace uuid,p_company uuid,p_asset uuid)
RETURNS private_isg.workspace_file_assets
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE asset private_isg.workspace_file_assets;
BEGIN
  SELECT * INTO asset FROM private_isg.workspace_file_assets
    WHERE id=p_asset AND workspace_id=p_workspace AND lifecycle='active'
      AND (company_id IS NULL OR company_id IS NOT DISTINCT FROM p_company);
  IF asset.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSET_SCOPE_CONFLICT'; END IF;
  RETURN asset;
END $$;

CREATE FUNCTION private_isg.workspace_file_parent_exists(p_workspace uuid,p_company uuid,p_kind text,p_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  RETURN CASE p_kind
    WHEN 'company' THEN EXISTS(SELECT 1 FROM public.companies WHERE workspace_id=p_workspace AND id=p_company AND id=p_id)
    WHEN 'employee' THEN EXISTS(SELECT 1 FROM private_isg.employees WHERE workspace_id=p_workspace AND company_id=p_company AND id=p_id)
    WHEN 'training' THEN EXISTS(SELECT 1 FROM private_isg.pilot_training_records WHERE workspace_id=p_workspace AND company_id=p_company AND id=p_id)
    WHEN 'risk_assessment' THEN EXISTS(SELECT 1 FROM private_isg.risk_assessments WHERE workspace_id=p_workspace AND company_id=p_company AND assessment_id=p_id)
    WHEN 'nonconformity' THEN EXISTS(SELECT 1 FROM private_isg.nonconformities WHERE workspace_id=p_workspace AND company_id=p_company AND nonconformity_id=p_id)
    WHEN 'checklist' THEN EXISTS(SELECT 1 FROM private_isg.checklist_runs WHERE workspace_id=p_workspace AND company_id=p_company AND run_id=p_id)
    WHEN 'emergency_plan' THEN EXISTS(SELECT 1 FROM private_isg.emergency_plan_versions WHERE workspace_id=p_workspace AND company_id=p_company AND plan_id=p_id)
    WHEN 'drill' THEN EXISTS(SELECT 1 FROM private_isg.drill_records WHERE workspace_id=p_workspace AND company_id=p_company AND drill_id=p_id)
    WHEN 'appointment' THEN EXISTS(SELECT 1 FROM private_isg.appointments WHERE workspace_id=p_workspace AND company_id=p_company AND appointment_id=p_id)
    WHEN 'ppe' THEN EXISTS(SELECT 1 FROM private_isg.ppe_handovers WHERE workspace_id=p_workspace AND company_id=p_company AND handover_id=p_id)
    WHEN 'equipment' THEN EXISTS(SELECT 1 FROM private_isg.equipment_items WHERE workspace_id=p_workspace AND company_id=p_company AND equipment_id=p_id)
    WHEN 'equipment_inspection' THEN EXISTS(SELECT 1 FROM private_isg.equipment_inspections WHERE workspace_id=p_workspace AND company_id=p_company AND inspection_id=p_id)
    WHEN 'katip_contract' THEN EXISTS(SELECT 1 FROM private_isg.katip_contracts WHERE workspace_id=p_workspace AND company_id=p_company AND contract_id=p_id)
    WHEN 'annual_plan' THEN EXISTS(SELECT 1 FROM private_isg.annual_work_plans WHERE workspace_id=p_workspace AND company_id=p_company AND plan_id=p_id)
    WHEN 'board' THEN EXISTS(SELECT 1 FROM private_isg.board_meetings WHERE workspace_id=p_workspace AND company_id=p_company AND meeting_id=p_id)
    WHEN 'work_permit' THEN EXISTS(SELECT 1 FROM private_isg.work_permit_forms WHERE workspace_id=p_workspace AND company_id=p_company AND permit_id=p_id)
    WHEN 'site_visit' THEN EXISTS(SELECT 1 FROM private_isg.site_visits WHERE workspace_id=p_workspace AND company_id=p_company AND visit_id=p_id)
    WHEN 'site_observation' THEN EXISTS(SELECT 1 FROM private_isg.site_visit_observations WHERE workspace_id=p_workspace AND company_id=p_company AND observation_id=p_id)
    WHEN 'notebook_archive' THEN EXISTS(SELECT 1 FROM private_isg.notebook_archive_entries WHERE workspace_id=p_workspace AND company_id=p_company AND entry_id=p_id)
    ELSE false END;
END $$;

CREATE FUNCTION private_isg.workspace_file_entry_row(p_entry uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE entry private_isg.workspace_file_entries; file_version private_isg.workspace_file_versions;
  asset private_isg.workspace_file_assets;
BEGIN
  SELECT * INTO entry FROM private_isg.workspace_file_entries WHERE id=p_entry;
  IF entry.id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO file_version FROM private_isg.workspace_file_versions
    WHERE entry_id=entry.id AND revision=entry.active_revision;
  SELECT * INTO asset FROM private_isg.workspace_file_assets WHERE id=file_version.asset_id;
  RETURN jsonb_build_object('id',entry.id,'company_id',entry.company_id,'category',entry.category,
    'visibility',entry.visibility,'title',entry.title,'original_filename',entry.original_filename,
    'note',entry.note,'tags',to_jsonb(entry.tags),'state',entry.state,'revision',entry.active_revision,
    'version',entry.version,'asset',jsonb_build_object('id',asset.id,'byte_size',asset.byte_size,
      'media_type',asset.media_type,'extension',asset.extension,'source_kind',asset.source_kind,
      'lifecycle',asset.lifecycle),'created_by_user_id',entry.created_by_user_id,
    'updated_by_user_id',entry.updated_by_user_id,'created_at',entry.created_at,'updated_at',entry.updated_at);
END $$;

CREATE FUNCTION private_isg.workspace_file_can_access(p_entry private_isg.workspace_file_entries,
  p_member private_isg.workspace_memberships) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT CASE p_entry.visibility
    WHEN 'company_team' THEN p_entry.company_id IS NOT NULL AND (
      p_member.role IN ('owner','admin') OR EXISTS(SELECT 1 FROM private_isg.company_assignments a
        WHERE a.workspace_id=p_entry.workspace_id AND a.company_id=p_entry.company_id
          AND a.membership_id=p_member.id AND a.starts_at<=clock_timestamp()
          AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp())))
    WHEN 'workspace_management' THEN p_member.role IN ('owner','admin')
    WHEN 'member_private' THEN p_entry.private_to_membership_id=p_member.id
    ELSE false END
$$;

CREATE FUNCTION private_isg.workspace_file_read(p_workspace uuid,p_company uuid,p_id uuid,p_query text,
  p_category text,p_include_archived boolean,p_after uuid,p_limit integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE member private_isg.workspace_memberships; entry private_isg.workspace_file_entries;
  rows jsonb; legacy_logo jsonb; next_id uuid; needle text:=nullif(btrim(coalesce(p_query,'')),'');
BEGIN
  PERFORM private_isg.workspace_domain_gate('files',false);
  member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],false);
  IF p_company IS NOT NULL THEN PERFORM private_isg.workspace_require_company(p_workspace,p_company,false); END IF;
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR p_include_archived IS NULL OR
     (p_id IS NOT NULL AND p_after IS NOT NULL) OR
     (p_category IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private_isg.workspace_file_categories WHERE code=p_category)) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_id IS NOT NULL THEN
    SELECT * INTO entry FROM private_isg.workspace_file_entries WHERE id=p_id AND workspace_id=p_workspace;
    IF entry.id IS NULL OR entry.company_id IS DISTINCT FROM p_company OR
       NOT private_isg.workspace_file_can_access(entry,member) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'row',private_isg.workspace_file_entry_row(entry.id));
  END IF;
  SELECT coalesce(jsonb_agg(private_isg.workspace_file_entry_row(q.id) ORDER BY q.id),'[]'),
    (array_agg(q.id) FILTER (WHERE q.ordinal=p_limit AND q.total>p_limit))[1] INTO rows,next_id
    FROM (SELECT e.id,row_number() OVER (ORDER BY e.id) ordinal,count(*) OVER () total
      FROM private_isg.workspace_file_entries e
      WHERE e.workspace_id=p_workspace AND e.company_id IS NOT DISTINCT FROM p_company
        AND private_isg.workspace_file_can_access(e,member)
        AND (p_include_archived OR e.state='active') AND (p_category IS NULL OR e.category=p_category)
        AND (needle IS NULL OR e.title ILIKE '%'||needle||'%' OR e.original_filename ILIKE '%'||needle||'%'
          OR coalesce(e.note,'') ILIKE '%'||needle||'%' OR array_to_string(e.tags,' ') ILIKE '%'||needle||'%')
        AND (p_after IS NULL OR e.id>p_after)
      ORDER BY e.id LIMIT p_limit+1) q WHERE q.ordinal<=p_limit;
  IF p_company IS NOT NULL THEN
    SELECT jsonb_build_object('id',l.id,'source_kind',l.source_kind,'status',l.status,
      'migrated_asset_id',l.migrated_asset_id) INTO legacy_logo
      FROM private_isg.workspace_legacy_file_inventory l
      WHERE l.workspace_id=p_workspace AND l.company_id=p_company AND l.source_kind='company_logo'
      ORDER BY l.discovered_at DESC,l.id LIMIT 1;
  END IF;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'rows',rows,'returned',jsonb_array_length(rows),'next',next_id,'legacy_company_logo',legacy_logo);
END $$;

-- Lets a client resolve the uncertain outcome of an unchanged file-create
-- command without replaying or exposing an upload credential.
CREATE FUNCTION private_isg.workspace_file_create_receipt(p_workspace uuid,p_company uuid,p_mutation uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); response jsonb;
BEGIN
  PERFORM private_isg.workspace_domain_gate('files',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  IF p_mutation IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT r.response INTO response FROM private_isg.workspace_receipts r
    WHERE r.actor_user_id=actor AND r.mutation_id=p_mutation AND r.workspace_id=p_workspace
      AND r.action='files.create';
  IF response IS NULL THEN
    RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'found',false);
  END IF;
  IF response->>'workspace_id' IS DISTINCT FROM p_workspace::text OR
     response->>'company_id' IS DISTINCT FROM p_company::text OR response->>'action'<>'create' OR
     response->'row'->'asset'->>'id' IS NULL OR response->'row'->'asset'->>'byte_size' IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RECEIPT_SCOPE_CONFLICT'; END IF;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'found',true,
    'entry_id',response->>'entry_id','asset_id',response->'row'->'asset'->>'id',
    'byte_size',(response->'row'->'asset'->>'byte_size')::bigint);
END $$;

CREATE FUNCTION private_isg.workspace_file_mutate(p_mutation uuid,p_workspace uuid,p_company uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); member private_isg.workspace_memberships;
  action text:=p_payload->>'action'; fingerprint bytea; replay jsonb; target uuid; reference_id uuid;
  expected bigint; entry private_isg.workspace_file_entries; asset private_isg.workspace_file_assets;
  file_version private_isg.workspace_file_versions; result jsonb; before_state jsonb; visibility text;
  v_revision integer; v_parent_kind text; v_parent_id uuid; v_field_name text; clean_tags text[];
BEGIN
  PERFORM private_isg.workspace_domain_gate('files',true);
  member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],true);
  IF p_company IS NOT NULL THEN member:=private_isg.workspace_require_company(p_workspace,p_company,true); END IF;
  IF p_mutation IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>32768 OR
     action NOT IN ('create','revise','rename','archive','attach','detach','set_company_logo') OR
     EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k(key) WHERE key NOT IN
       ('action','entry_id','reference_id','expected_version','asset_id','category','visibility','title',
        'original_filename','note','tags','parent_kind','parent_id','field_name')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_payload ? 'tags' AND (jsonb_typeof(p_payload->'tags')<>'array' OR jsonb_array_length(p_payload->'tags')>12 OR
     EXISTS(SELECT 1 FROM jsonb_array_elements_text(p_payload->'tags') tag WHERE octet_length(btrim(tag)) NOT BETWEEN 1 AND 40)) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT coalesce(array_agg(DISTINCT btrim(tag) ORDER BY btrim(tag)),'{}') INTO clean_tags
    FROM jsonb_array_elements_text(coalesce(p_payload->'tags','[]')) tag;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_payload)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'files.'||action,fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;

  IF action='create' THEN
    asset:=private_isg.workspace_file_asset(p_workspace,p_company,(p_payload->>'asset_id')::uuid);
    visibility:=coalesce(p_payload->>'visibility',CASE WHEN p_company IS NULL THEN 'member_private' ELSE 'company_team' END);
    IF (p_company IS NOT NULL AND visibility<>'company_team') OR
       (p_company IS NULL AND visibility NOT IN ('workspace_management','member_private')) OR
       (visibility='workspace_management' AND member.role NOT IN ('owner','admin')) OR
       NOT EXISTS(SELECT 1 FROM private_isg.workspace_file_categories WHERE code=p_payload->>'category') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    INSERT INTO private_isg.workspace_file_entries(workspace_id,company_id,category,visibility,
      private_to_membership_id,title,original_filename,note,tags,created_by_user_id,updated_by_user_id)
    VALUES(p_workspace,p_company,p_payload->>'category',visibility,
      CASE WHEN visibility='member_private' THEN member.id END,
      private_isg.workspace_text(p_payload->>'title',320),private_isg.workspace_text(p_payload->>'original_filename',400),
      nullif(btrim(coalesce(p_payload->>'note','')),''),clean_tags,actor,actor) RETURNING * INTO entry;
    INSERT INTO private_isg.workspace_file_versions(workspace_id,entry_id,revision,asset_id,created_by_user_id)
      VALUES(p_workspace,entry.id,1,asset.id,actor) RETURNING * INTO file_version;
    target:=entry.id;
  ELSE
    target:=(p_payload->>'entry_id')::uuid;
    SELECT * INTO entry FROM private_isg.workspace_file_entries WHERE id=target AND workspace_id=p_workspace FOR UPDATE;
    IF entry.id IS NULL OR entry.company_id IS DISTINCT FROM p_company OR
       NOT private_isg.workspace_file_can_access(entry,member) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    before_state:=private_isg.workspace_file_entry_row(entry.id);
    expected:=(p_payload->>'expected_version')::bigint;
    IF action IN ('revise','rename','archive') AND (expected IS NULL OR expected<>entry.version) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    IF action='revise' THEN
      asset:=private_isg.workspace_file_asset(p_workspace,p_company,(p_payload->>'asset_id')::uuid);
      v_revision:=entry.active_revision+1;
      INSERT INTO private_isg.workspace_file_versions(workspace_id,entry_id,revision,asset_id,created_by_user_id)
        VALUES(p_workspace,entry.id,v_revision,asset.id,actor);
      UPDATE private_isg.workspace_file_entries SET active_revision=v_revision,version=version+1,
        updated_by_user_id=actor,updated_at=clock_timestamp() WHERE id=entry.id;
    ELSIF action='rename' THEN
      UPDATE private_isg.workspace_file_entries SET
        title=CASE WHEN p_payload ? 'title' THEN private_isg.workspace_text(p_payload->>'title',320) ELSE title END,
        note=CASE WHEN p_payload ? 'note' THEN nullif(btrim(coalesce(p_payload->>'note','')),'') ELSE note END,
        tags=CASE WHEN p_payload ? 'tags' THEN clean_tags ELSE tags END,
        version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp() WHERE id=entry.id;
    ELSIF action='archive' THEN
      UPDATE private_isg.workspace_file_entries SET state='archived',archived_at=clock_timestamp(),
        version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp() WHERE id=entry.id;
    ELSIF action IN ('attach','set_company_logo') THEN
      IF p_company IS NULL OR entry.state<>'active' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      v_parent_kind:=CASE WHEN action='set_company_logo' THEN 'company' ELSE p_payload->>'parent_kind' END;
      v_parent_id:=CASE WHEN action='set_company_logo' THEN p_company ELSE (p_payload->>'parent_id')::uuid END;
      v_field_name:=CASE WHEN action='set_company_logo' THEN 'logo' ELSE private_isg.workspace_text(p_payload->>'field_name',80) END;
      IF action='set_company_logo' AND entry.category<>'company_logo' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CATEGORY_CONFLICT'; END IF;
      IF NOT private_isg.workspace_file_parent_exists(p_workspace,p_company,v_parent_kind,v_parent_id) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PARENT_SCOPE_CONFLICT'; END IF;
      SELECT * INTO file_version FROM private_isg.workspace_file_versions fv
        WHERE fv.entry_id=entry.id AND fv.revision=entry.active_revision;
      IF v_field_name IN ('logo','signed_copy','report','minutes','rendered_document') THEN
        UPDATE private_isg.workspace_file_references r SET archived_at=clock_timestamp()
          WHERE r.workspace_id=p_workspace AND r.company_id=p_company AND r.parent_kind=v_parent_kind
            AND r.parent_id=v_parent_id AND r.field_name=v_field_name AND r.archived_at IS NULL;
      END IF;
      INSERT INTO private_isg.workspace_file_references(workspace_id,company_id,entry_id,entry_revision,
        asset_id,parent_kind,parent_id,field_name,created_by_user_id)
      VALUES(p_workspace,p_company,entry.id,entry.active_revision,file_version.asset_id,v_parent_kind,v_parent_id,v_field_name,actor)
      RETURNING id INTO reference_id;
      IF action='set_company_logo' THEN
        UPDATE public.companies SET workspace_logo_entry_id=entry.id,updated_at=clock_timestamp()
          WHERE workspace_id=p_workspace AND id=p_company;
      END IF;
    ELSE
      reference_id:=(p_payload->>'reference_id')::uuid;
      UPDATE private_isg.workspace_file_references SET archived_at=clock_timestamp()
        WHERE id=reference_id AND workspace_id=p_workspace AND company_id=p_company AND entry_id=entry.id
          AND archived_at IS NULL;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      UPDATE public.companies SET workspace_logo_entry_id=NULL,updated_at=clock_timestamp()
        WHERE workspace_id=p_workspace AND id=p_company AND workspace_logo_entry_id=entry.id
          AND EXISTS(SELECT 1 FROM private_isg.workspace_file_references r WHERE r.id=reference_id AND r.field_name='logo');
    END IF;
  END IF;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'action',action,'entry_id',target,'reference_id',reference_id,'row',private_isg.workspace_file_entry_row(target));
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'files.'||action,fingerprint,p_workspace,
    CASE WHEN action IN ('attach','detach','set_company_logo') THEN 'file_reference' ELSE 'file_entry' END,
    coalesce(reference_id,target),(SELECT version FROM private_isg.workspace_file_entries WHERE id=target),
    before_state,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_legacy_download_open(p_workspace uuid,p_legacy uuid,p_expires timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE member private_isg.workspace_memberships; legacy private_isg.workspace_legacy_file_inventory;
  token text; intent private_isg.workspace_legacy_download_intents;
BEGIN
  PERFORM private_isg.workspace_domain_gate('files',false);
  SELECT * INTO legacy FROM private_isg.workspace_legacy_file_inventory
    WHERE id=p_legacy AND workspace_id=p_workspace AND status<>'missing';
  IF legacy.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  member:=private_isg.workspace_require_company(p_workspace,legacy.company_id,false);
  IF p_expires<=clock_timestamp() OR p_expires>clock_timestamp()+interval '5 minutes' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  token:=private_isg.workspace_random_token();
  INSERT INTO private_isg.workspace_legacy_download_intents(workspace_id,legacy_file_id,membership_id,token_hash,expires_at)
    VALUES(p_workspace,legacy.id,member.id,sha256(convert_to(token,'UTF8')),p_expires) RETURNING * INTO intent;
  RETURN jsonb_build_object('schema_version',1,'download_id',intent.id,'download_token',token,'expires_at',intent.expires_at);
END $$;

CREATE FUNCTION private_isg.workspace_legacy_download_claim(p_token text,p_now timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE intent private_isg.workspace_legacy_download_intents; legacy private_isg.workspace_legacy_file_inventory;
  member private_isg.workspace_memberships;
BEGIN
  IF p_token !~ '^[0-9a-f]{64}$' OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO intent FROM private_isg.workspace_legacy_download_intents
    WHERE token_hash=sha256(convert_to(p_token,'UTF8')) FOR UPDATE;
  IF intent.id IS NULL OR intent.status NOT IN ('issued','claimed') OR intent.expires_at<=p_now THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DOWNLOAD_TOKEN_EXPIRED'; END IF;
  SELECT * INTO legacy FROM private_isg.workspace_legacy_file_inventory WHERE id=intent.legacy_file_id;
  SELECT * INTO member FROM private_isg.workspace_memberships
    WHERE workspace_id=intent.workspace_id AND id=intent.membership_id;
  IF legacy.id IS NULL OR legacy.status='missing' OR member.id IS NULL OR member.status<>'active' OR
     (member.role='expert' AND NOT EXISTS(SELECT 1 FROM private_isg.company_assignments a
       WHERE a.workspace_id=intent.workspace_id AND a.company_id=legacy.company_id AND a.membership_id=member.id
         AND a.starts_at<=p_now AND (a.ends_at IS NULL OR a.ends_at>p_now))) THEN
    UPDATE private_isg.workspace_legacy_download_intents SET status='revoked' WHERE id=intent.id;
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  UPDATE private_isg.workspace_legacy_download_intents SET status='claimed',claimed_at=coalesce(claimed_at,p_now)
    WHERE id=intent.id;
  RETURN jsonb_build_object('download_id',intent.id,'workspace_id',intent.workspace_id,
    'legacy_file_id',legacy.id,'bucket',legacy.bucket,'object_path',legacy.object_path,
    'object_version',legacy.discovered_version,'byte_size',legacy.discovered_bytes);
END $$;

CREATE FUNCTION private_isg.workspace_asset_reference_count(p_workspace uuid,p_asset uuid) RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT
    (SELECT count(*) FROM private_isg.workspace_file_versions v WHERE v.workspace_id=p_workspace AND v.asset_id=p_asset)+
    (SELECT count(*) FROM private_isg.equipment_inspections v WHERE v.workspace_id=p_workspace AND v.workspace_asset_id=p_asset)+
    (SELECT count(*) FROM private_isg.katip_contracts v WHERE v.workspace_id=p_workspace AND v.workspace_asset_id=p_asset)+
    (SELECT count(*) FROM private_isg.board_meetings v WHERE v.workspace_id=p_workspace AND v.workspace_asset_id=p_asset)+
    (SELECT count(*) FROM private_isg.work_permit_forms v WHERE v.workspace_id=p_workspace AND v.workspace_asset_id=p_asset)+
    (SELECT count(*) FROM private_isg.site_visit_observations v WHERE v.workspace_id=p_workspace AND v.workspace_asset_id=p_asset)+
    (SELECT count(*) FROM private_isg.notebook_archive_entries v WHERE v.workspace_id=p_workspace AND v.workspace_asset_id=p_asset)+
    (SELECT count(*) FROM private_isg.workspace_ai_jobs v WHERE v.workspace_id=p_workspace AND v.output_asset_id=p_asset)
$$;

CREATE OR REPLACE FUNCTION private_isg.workspace_asset_delete_request(p_workspace uuid,p_asset uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE member private_isg.workspace_memberships; asset private_isg.workspace_file_assets;
  deletion private_isg.workspace_asset_deletions;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_storage',true);
  SELECT * INTO asset FROM private_isg.workspace_file_assets WHERE id=p_asset AND workspace_id=p_workspace FOR UPDATE;
  IF asset.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF asset.company_id IS NULL THEN member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],true);
  ELSE member:=private_isg.workspace_require_company(p_workspace,asset.company_id,true); END IF;
  IF member.role='expert' AND member.id<>asset.uploaded_by_membership_id THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO deletion FROM private_isg.workspace_asset_deletions WHERE asset_id=p_asset;
  IF FOUND THEN RETURN jsonb_build_object('deletion_id',deletion.id,'state',deletion.state,'replayed',true); END IF;
  IF asset.lifecycle<>'active' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSET_STATE_CONFLICT'; END IF;
  IF private_isg.workspace_asset_reference_count(p_workspace,p_asset)>0 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSET_IN_USE'; END IF;
  UPDATE private_isg.workspace_file_assets SET lifecycle='delete_requested',delete_requested_at=clock_timestamp() WHERE id=asset.id;
  INSERT INTO private_isg.workspace_asset_deletions(workspace_id,asset_id,requested_by_membership_id,reason)
    VALUES(p_workspace,p_asset,member.id,private_isg.workspace_text(p_reason,500)) RETURNING * INTO deletion;
  RETURN jsonb_build_object('deletion_id',deletion.id,'asset_id',p_asset,'state','requested','replayed',false);
END $$;

CREATE FUNCTION public.isg_workspace_file_read_v1(p_workspace uuid,p_company uuid,p_id uuid,p_query text,
  p_category text,p_include_archived boolean,p_after uuid DEFAULT NULL,p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_file_read(p_workspace,p_company,p_id,p_query,p_category,p_include_archived,p_after,p_limit) $$;
CREATE FUNCTION public.isg_workspace_file_create_receipt_v1(p_workspace uuid,p_company uuid,p_mutation uuid)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_file_create_receipt(p_workspace,p_company,p_mutation) $$;
CREATE FUNCTION public.isg_workspace_file_mutate_v1(p_mutation uuid,p_workspace uuid,p_company uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_file_mutate(p_mutation,p_workspace,p_company,p_payload) $$;
CREATE FUNCTION public.isg_workspace_legacy_download_open_v1(p_workspace uuid,p_legacy uuid,p_expires timestamptz)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_legacy_download_open(p_workspace,p_legacy,p_expires) $$;

REVOKE ALL ON FUNCTION private_isg.workspace_file_asset(uuid,uuid,uuid),
  private_isg.workspace_file_parent_exists(uuid,uuid,text,uuid),
  private_isg.workspace_file_entry_row(uuid),
  private_isg.workspace_file_can_access(private_isg.workspace_file_entries,private_isg.workspace_memberships),
  private_isg.workspace_file_read(uuid,uuid,uuid,text,text,boolean,uuid,integer),
  private_isg.workspace_file_create_receipt(uuid,uuid,uuid),
  private_isg.workspace_file_mutate(uuid,uuid,uuid,jsonb),
  private_isg.workspace_legacy_download_open(uuid,uuid,timestamptz),
  private_isg.workspace_legacy_download_claim(text,timestamptz),
  private_isg.workspace_asset_reference_count(uuid,uuid),
  public.isg_workspace_file_read_v1(uuid,uuid,uuid,text,text,boolean,uuid,integer),
  public.isg_workspace_file_create_receipt_v1(uuid,uuid,uuid),
  public.isg_workspace_file_mutate_v1(uuid,uuid,uuid,jsonb),
  public.isg_workspace_legacy_download_open_v1(uuid,uuid,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_file_read(uuid,uuid,uuid,text,text,boolean,uuid,integer),
  private_isg.workspace_file_create_receipt(uuid,uuid,uuid),
  private_isg.workspace_file_mutate(uuid,uuid,uuid,jsonb),
  private_isg.workspace_legacy_download_open(uuid,uuid,timestamptz),
  public.isg_workspace_file_read_v1(uuid,uuid,uuid,text,text,boolean,uuid,integer),
  public.isg_workspace_file_create_receipt_v1(uuid,uuid,uuid),
  public.isg_workspace_file_mutate_v1(uuid,uuid,uuid,jsonb),
  public.isg_workspace_legacy_download_open_v1(uuid,uuid,timestamptz)
  TO authenticated;
GRANT EXECUTE ON FUNCTION private_isg.workspace_legacy_download_claim(text,timestamptz) TO service_role;

NOTIFY pgrst,'reload schema';
