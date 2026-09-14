CREATE TABLE private_isg.pilot_training_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL,
  title text NOT NULL CHECK(length(btrim(title)) BETWEEN 1 AND 200),
  trainer text NOT NULL CHECK(length(btrim(trainer)) BETWEEN 1 AND 200),
  location text NOT NULL DEFAULT '' CHECK(length(location)<=300),
  notes text NOT NULL DEFAULT '' CHECK(length(notes)<=2000),
  starts_at timestamptz NOT NULL CHECK(isfinite(starts_at)),
  duration_minutes integer NOT NULL CHECK(duration_minutes BETWEEN 1 AND 1440),
  valid_until date CHECK(valid_until IS NULL OR isfinite(valid_until)),
  state text NOT NULL DEFAULT 'planned' CHECK(state IN ('planned','completed','cancelled')),
  version bigint NOT NULL DEFAULT 1,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(company_id,id),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
