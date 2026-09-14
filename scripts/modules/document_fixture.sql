CREATE TABLE IF NOT EXISTS private_isg.document_templates (
  template_code text PRIMARY KEY CHECK(template_code ~ '^[a-z][a-z0-9_]{2,60}$'),
  source_domain text NOT NULL CHECK(source_domain IN ('training','risk','nonconformity','module','personnel')),
  title text NOT NULL CHECK(btrim(title)<>'' AND length(title)<=200),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private_isg.document_templates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.document_templates FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE IF NOT EXISTS private_isg.document_template_versions (
  template_code text NOT NULL REFERENCES private_isg.document_templates(template_code) ON DELETE CASCADE,
  version integer NOT NULL CHECK(version BETWEEN 1 AND 1000),
  status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','superseded')),
  approved_by uuid REFERENCES public.profiles(id), approval_note text, published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(template_code,version),
  CHECK(status<>'published' OR (approved_by IS NOT NULL AND approval_note IS NOT NULL AND published_at IS NOT NULL))
);
ALTER TABLE private_isg.document_template_versions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.document_template_versions FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE IF NOT EXISTS private_isg.documents (
  document_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid,
  source_domain text NOT NULL CHECK(source_domain IN ('training','risk','nonconformity','module','personnel')),
  source_ref text NOT NULL CHECK(btrim(source_ref)<>'' AND length(source_ref)<=200),
  template_code text NOT NULL REFERENCES private_isg.document_templates(template_code),
  current_version integer NOT NULL DEFAULT 0 CHECK(current_version BETWEEN 0 AND 10000),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,source_domain,source_ref,template_code),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
ALTER TABLE private_isg.documents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.documents FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE IF NOT EXISTS private_isg.document_number_sequences (
  company_id uuid NOT NULL, scope text NOT NULL CHECK(scope ~ '^[a-z][a-z0-9_]{1,19}$'),
  year integer NOT NULL CHECK(year BETWEEN 2000 AND 2100),
  next_value bigint NOT NULL DEFAULT 1 CHECK(next_value>=1),
  PRIMARY KEY(company_id,scope,year)
);
ALTER TABLE private_isg.document_number_sequences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.document_number_sequences FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE IF NOT EXISTS private_isg.document_versions (
  document_id uuid NOT NULL REFERENCES private_isg.documents(document_id) ON DELETE CASCADE,
  version integer NOT NULL CHECK(version BETWEEN 1 AND 10000),
  template_version integer NOT NULL,
  document_no text NOT NULL CHECK(document_no ~ '^[A-Z0-9_]{2,20}-[0-9]{4}-[0-9]{1,9}$'),
  source_kind text NOT NULL CHECK(source_kind IN ('structured','scanned')),
  snapshot jsonb NOT NULL, snapshot_sha256 bytea NOT NULL CHECK(octet_length(snapshot_sha256)=32),
  finalized_by uuid NOT NULL REFERENCES public.profiles(id), finalized_at timestamptz NOT NULL,
  mutation_id uuid NOT NULL,
  PRIMARY KEY(document_id,version),
  UNIQUE(document_id,mutation_id)
);
ALTER TABLE private_isg.document_versions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.document_versions FROM PUBLIC,anon,authenticated,service_role;



CREATE TABLE private_isg.education_document_counters(scope text,year integer,next_value bigint,PRIMARY KEY(scope,year));
