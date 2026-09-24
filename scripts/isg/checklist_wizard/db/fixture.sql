-- Stand-ins for the objects the checklist catalogue migrations touch. The catalogue tables themselves are
-- created by run_database.mjs from the real 20260921072445_checklist_catalog_v1.sql DDL; this file only
-- provides what those tables and read_checklists_company_v3's catalogue branches reference.
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role;
CREATE SCHEMA private_isg;
CREATE TABLE public.profiles (id uuid PRIMARY KEY);
INSERT INTO public.profiles VALUES ('00000000-0000-0000-0000-00000000a001');

-- Final column shape after nonconformity_core, isg_checklist_runs, checklist_catalog_v1/completion and
-- the workspace migrations.
CREATE TABLE private_isg.checklist_templates (
  template_code text PRIMARY KEY CHECK(template_code ~ '^[a-z][a-z0-9_]{2,60}$'),
  title text NOT NULL CHECK(btrim(title)<>'' AND length(title)<=200),
  created_at timestamptz NOT NULL DEFAULT now(),
  owner_id uuid REFERENCES public.profiles(id),
  is_archived boolean NOT NULL DEFAULT false,
  workspace_id uuid,
  catalog_version text,
  catalog_template_code text,
  sector_code text,
  template_kind text,
  aliases jsonb NOT NULL DEFAULT '[]',
  scope_note text,
  professional_review_status text,
  source_ids jsonb NOT NULL DEFAULT '[]'
);
CREATE UNIQUE INDEX checklist_product_catalog_identity_idx
  ON private_isg.checklist_templates(catalog_version,catalog_template_code)
  WHERE owner_id IS NULL AND catalog_version IS NOT NULL;
CREATE TABLE private_isg.checklist_template_versions (
  template_code text NOT NULL REFERENCES private_isg.checklist_templates(template_code) ON DELETE CASCADE,
  version integer NOT NULL CHECK(version BETWEEN 1 AND 1000),
  status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','superseded')),
  approved_by uuid REFERENCES public.profiles(id), approval_note text, published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  edit_revision bigint NOT NULL DEFAULT 0,
  PRIMARY KEY(template_code,version),
  CONSTRAINT checklist_template_versions_publication_check CHECK(
    status<>'published' OR (approval_note IS NOT NULL AND published_at IS NOT NULL AND
      (approved_by IS NOT NULL OR approval_note LIKE 'Ürün kataloğu%')))
);
CREATE UNIQUE INDEX checklist_single_published_idx ON private_isg.checklist_template_versions(template_code) WHERE status='published';
CREATE TABLE private_isg.checklist_template_items (
  template_code text NOT NULL, version integer NOT NULL,
  item_code text NOT NULL CHECK(item_code ~ '^[a-z0-9_]{2,40}$'),
  prompt text NOT NULL CHECK(btrim(prompt)<>'' AND length(prompt)<=500),
  allows_not_applicable boolean NOT NULL DEFAULT true,
  position integer NOT NULL CHECK(position BETWEEN 1 AND 500),
  atomic_item_code text, verification_method text, help_text text, tags jsonb NOT NULL DEFAULT '[]',
  risk_topic text, source_ids jsonb NOT NULL DEFAULT '[]', na_reason_required boolean NOT NULL DEFAULT false,
  evidence_recommended boolean NOT NULL DEFAULT false, photo_required boolean NOT NULL DEFAULT false,
  catalog_item_code text, section_title text, scope_key text,
  PRIMARY KEY(template_code,version,item_code),
  UNIQUE(template_code,version,position),
  FOREIGN KEY(template_code,version) REFERENCES private_isg.checklist_template_versions(template_code,version) ON DELETE CASCADE
);

-- What read_checklists_company_v3 calls before and inside its catalogue branches.
CREATE TABLE private_isg.workplaces (id uuid PRIMARY KEY, name text NOT NULL, needs_review boolean NOT NULL DEFAULT false,
  company_id uuid NOT NULL, owner_id uuid, is_archived boolean NOT NULL DEFAULT false);
CREATE FUNCTION private_isg.require_checklist_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE sql AS $$ SELECT '00000000-0000-0000-0000-00000000a001'::uuid $$;
CREATE FUNCTION private_isg.expert_workspace() RETURNS uuid LANGUAGE sql AS $$ SELECT NULL::uuid $$;
CREATE FUNCTION private_isg.expert_company_visible(p_owner uuid,p_company uuid,p_actor uuid) RETURNS boolean
LANGUAGE sql AS $$ SELECT true $$;
