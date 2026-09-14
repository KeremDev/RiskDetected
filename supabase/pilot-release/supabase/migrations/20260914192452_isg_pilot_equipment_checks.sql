-- PILOT BUNDLE — Periyodik Kontroller (P10 equipment checks) for the live
-- P05 pilot account allowlist. This is NOT the development migration chain.
--
-- The live project carries hand-authored pilot bundles rather than the whole
-- `supabase/migrations` folder, so this file is the equipment slice trimmed to
-- what the live schema can actually satisfy, and it opens the two switches the
-- module needs. Every reachable entry stays inside the P05 pilot allowlist:
-- `require_equipment_company` calls `p05_pilot_can_read` and
-- `p05_pilot_account_enabled` exactly as `require_company` does, so a user who
-- is not on the pilot list gets FEATURE_UNAVAILABLE and reaches nothing.
--
-- Development sources, in order:
--   supabase/migrations/20260913230000_isg_module_core.sql   (equipment part)
--   supabase/migrations/20260915030000_isg_equipment_checks.sql
--   supabase/migrations/20260915050000_isg_equipment_periods.sql
--   supabase/migrations/20260915070000_isg_equipment_inspection_edit.sql
--
-- DELIBERATE DIVERGENCES FROM THOSE SOURCES, all in one direction — less:
--   1. Only the `equipment` module is built. Emergency plan, drill, PPE and
--      appointment tables are not created here; their registry rows exist and
--      stay closed so the gate answers MODULE_UNAVAILABLE, not "no such row".
--   2. `private_isg.file_assets` does not exist live, so
--      `equipment_inspections` has NO `evidence_asset_id` column. The key stays
--      in the payload allowlist because the client always sends it, but a
--      non-null value is REFUSED rather than stored as a reference to nothing,
--      and the read reports it as null. The archive slice is not in this pilot.
--   3. `require_equipment_company` carries the P05 pilot gates, which the
--      development function does not need and does not have.
-- Nothing here loosens a check, and no development file is edited to match.
SET LOCAL lock_timeout='5s';

-- The `modules` feature switch, and the per-module switch on top of it:
-- pausing one module must never pause another.
ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','modules'));
INSERT INTO private_isg.rollout(feature) VALUES('modules');
CREATE TABLE private_isg.module_registry (
  module text PRIMARY KEY CHECK(module IN ('emergency_plan','drill','equipment','ppe','appointment')),
  read_enabled boolean NOT NULL DEFAULT false,
  write_enabled boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK(NOT write_enabled OR read_enabled)
);
INSERT INTO private_isg.module_registry(module) VALUES
  ('emergency_plan'),('drill'),('equipment'),('ppe'),('appointment');

-- Equipment: the inspection period belongs to the equipment type, never one
-- fixed year for everything, and an exception is written down, not hidden.
CREATE TABLE private_isg.equipment_items (
  equipment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  equipment_type text NOT NULL CHECK(equipment_type ~ '^[a-z][a-z0-9_]{2,40}$'),
  serial_tag text NOT NULL CHECK(btrim(serial_tag)<>'' AND length(serial_tag)<=100),
  acquired_on date CHECK(acquired_on IS NULL OR isfinite(acquired_on)),
  is_archived boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,serial_tag),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.equipment_inspection_rules (
  company_id uuid NOT NULL, equipment_type text NOT NULL,
  period_months integer NOT NULL CHECK(period_months BETWEEN 1 AND 240),
  period_source text NOT NULL CHECK(period_source IN ('manufacturer','rule_version','unapproved_fixture')),
  exception_note text CHECK(exception_note IS NULL OR length(exception_note) BETWEEN 10 AND 1000),
  needs_review boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(company_id,equipment_type),
  CHECK(period_source<>'unapproved_fixture' OR needs_review)
);
-- No evidence_asset_id: see divergence 2 in the header.
CREATE TABLE private_isg.equipment_inspections (
  inspection_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  equipment_id uuid NOT NULL REFERENCES private_isg.equipment_items(equipment_id) ON DELETE CASCADE,
  performed_on date NOT NULL CHECK(isfinite(performed_on)),
  result text NOT NULL CHECK(result IN ('pass','fail','conditional')),
  next_due_on date CHECK(next_due_on IS NULL OR isfinite(next_due_on)),
  period_months integer CHECK(period_months IS NULL OR period_months BETWEEN 1 AND 240),
  external_ref text CHECK(external_ref IS NULL OR length(external_ref)<=200),
  note text, created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(equipment_id,performed_on),
  CHECK(next_due_on IS NULL OR next_due_on>performed_on)
);
CREATE INDEX equipment_scope_idx ON private_isg.equipment_items(company_id,workplace_id,is_archived);
CREATE INDEX equipment_owner_idx ON private_isg.equipment_items(company_id,owner_id);
CREATE INDEX equipment_type_idx ON private_isg.equipment_items(company_id,equipment_type);
CREATE INDEX inspection_due_idx ON private_isg.equipment_inspections(equipment_id,next_due_on);
ALTER TABLE private_isg.module_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.equipment_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.equipment_inspection_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.equipment_inspections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.module_gate(p_module text,p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='modules' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  PERFORM 1 FROM private_isg.module_registry WHERE module=p_module AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='MODULE_UNAVAILABLE'; END IF;
END $$;
CREATE FUNCTION private_isg.module_scope(p_module text,p_company uuid,p_workplace uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE owner uuid;
BEGIN
  PERFORM private_isg.module_gate(p_module,p_write);
  IF p_company IS NULL OR p_workplace IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT owner_id INTO owner FROM private_isg.workplaces WHERE company_id=p_company AND id=p_workplace FOR SHARE;
  IF owner IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN owner;
END $$;
CREATE FUNCTION private_isg.set_equipment_inspection_rule(p_company uuid,p_type text,p_period_months integer,
  p_source text,p_exception text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE review boolean;
BEGIN
  PERFORM private_isg.module_gate('equipment',true);
  IF p_company IS NULL OR p_type IS NULL OR p_period_months IS NULL OR p_source IS NULL OR p_now IS NULL OR
     p_period_months NOT BETWEEN 1 AND 240 OR p_source NOT IN ('manufacturer','rule_version','unapproved_fixture') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM 1 FROM public.companies WHERE id=p_company FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  review:=p_source='unapproved_fixture';
  INSERT INTO private_isg.equipment_inspection_rules(company_id,equipment_type,period_months,period_source,
      exception_note,needs_review,created_at)
    VALUES(p_company,p_type,p_period_months,p_source,p_exception,review,p_now)
  ON CONFLICT(company_id,equipment_type) DO UPDATE SET period_months=excluded.period_months,
    period_source=excluded.period_source,exception_note=excluded.exception_note,needs_review=excluded.needs_review;
  RETURN jsonb_build_object('schema_version',1,'equipment_type',p_type,'period_months',p_period_months,
    'period_source',p_source,'needs_review',review,'exception_note',p_exception);
END $$;
CREATE FUNCTION private_isg.register_equipment(p_company uuid,p_workplace uuid,p_type text,p_serial text,
  p_acquired_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE owner uuid; equipment uuid; existing uuid; tag text;
BEGIN
  owner:=private_isg.module_scope('equipment',p_company,p_workplace,true);
  IF p_type IS NULL OR p_serial IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  tag:=private_isg.text_value(p_serial,100);
  SELECT equipment_id INTO existing FROM private_isg.equipment_items WHERE company_id=p_company AND serial_tag=tag;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'equipment_id',existing,'replayed',true); END IF;
  INSERT INTO private_isg.equipment_items(company_id,owner_id,workplace_id,equipment_type,serial_tag,acquired_on,created_at)
    VALUES(p_company,owner,p_workplace,p_type,tag,p_acquired_on,p_now) RETURNING equipment_id INTO equipment;
  RETURN jsonb_build_object('schema_version',1,'equipment_id',equipment,'equipment_type',p_type,'replayed',false);
END $$;
CREATE FUNCTION private_isg.record_equipment_inspection(p_equipment uuid,p_performed_on date,p_result text,
  p_asset uuid,p_external_ref text,p_note text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE item private_isg.equipment_items; rule private_isg.equipment_inspection_rules;
  inspection uuid; existing private_isg.equipment_inspections; due date;
BEGIN
  PERFORM private_isg.module_gate('equipment',true);
  IF p_equipment IS NULL OR p_performed_on IS NULL OR NOT isfinite(p_performed_on) OR p_result IS NULL OR
     p_now IS NULL OR p_result NOT IN ('pass','fail','conditional') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  -- PILOT DIVERGENCE 2: there is no cleared asset to attach and no column to
  -- hold one, so an asset is refused rather than accepted and dropped.
  IF p_asset IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO item FROM private_isg.equipment_items WHERE equipment_id=p_equipment FOR SHARE;
  IF NOT FOUND OR item.is_archived THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO existing FROM private_isg.equipment_inspections
    WHERE equipment_id=p_equipment AND performed_on=p_performed_on;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'inspection_id',existing.inspection_id,
    'next_due_on',existing.next_due_on,'replayed',true); END IF;
  SELECT * INTO rule FROM private_isg.equipment_inspection_rules
    WHERE company_id=item.company_id AND equipment_type=item.equipment_type FOR SHARE;
  -- No type rule means no invented due date: the period is unknown, not a year.
  IF FOUND AND p_result<>'fail' THEN
    due:=(p_performed_on+make_interval(months=>rule.period_months))::date; END IF;
  INSERT INTO private_isg.equipment_inspections(equipment_id,performed_on,result,next_due_on,period_months,
      external_ref,note,created_at)
    VALUES(p_equipment,p_performed_on,p_result,due,rule.period_months,p_external_ref,p_note,p_now)
    RETURNING inspection_id INTO inspection;
  RETURN jsonb_build_object('schema_version',1,'inspection_id',inspection,'result',p_result,'next_due_on',due,
    'period_months',rule.period_months,'period_source',rule.period_source,
    'period_needs_review',coalesce(rule.needs_review,true),'exception_note',rule.exception_note,'replayed',false);
END $$;
-- The plan lists "kontrolü yapan" among the fields a periodic check record
-- carries. It is the expert's own note of who performed it; the product never
-- treats it as proof of accreditation.
ALTER TABLE private_isg.equipment_inspections
  ADD COLUMN inspector text CHECK(inspector IS NULL OR length(inspector)<=200);
-- Where the equipment stands inside its workplace. The workplace is the scope;
-- this is the shelf, the line or the floor.
ALTER TABLE private_isg.equipment_items
  ADD COLUMN location_note text CHECK(location_note IS NULL OR length(location_note)<=200);

-- Names the client may offer, and nothing else. There is deliberately NO period
-- column here: the plan forbids handing every piece of equipment one fixed
-- period, so a suggested name never arrives with a suggested duration.
CREATE TABLE private_isg.equipment_type_suggestions (
  equipment_type text PRIMARY KEY CHECK(equipment_type IN ('lifting_equipment','crane','forklift',
    'pressure_vessel','compressor','boiler','lift','scaffold','ladder','electrical_installation',
    'earthing','fire_extinguisher','fire_detection','ventilation','power_tool','welding_set',
    'conveyor','press_machine','lathe','other_equipment')),
  ordinal integer NOT NULL CHECK(ordinal BETWEEN 1 AND 999),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(ordinal)
);
INSERT INTO private_isg.equipment_type_suggestions(equipment_type,ordinal) VALUES
  ('lifting_equipment',1),('crane',2),('forklift',3),('pressure_vessel',4),('compressor',5),
  ('boiler',6),('lift',7),('scaffold',8),('ladder',9),('electrical_installation',10),
  ('earthing',11),('fire_extinguisher',12),('fire_detection',13),('ventilation',14),
  ('power_tool',15),('welding_set',16),('conveyor',17),('press_machine',18),('lathe',19),
  ('other_equipment',20);

CREATE TABLE private_isg.equipment_check_receipts (
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, company_id uuid NOT NULL,
  operation_id uuid NOT NULL, request_hash bytea NOT NULL, response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor_id,mutation_id),
  FOREIGN KEY(company_id,actor_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE INDEX equipment_check_receipt_company_idx ON private_isg.equipment_check_receipts(company_id,actor_id);
-- The page reads the latest report per item rather than sweeping the whole
-- inspection history. The company/type index the list also needs already
-- exists as equipment_type_idx from the P10 slice, so none is added here.
CREATE INDEX equipment_inspection_latest_idx
  ON private_isg.equipment_inspections(equipment_id,performed_on DESC,inspection_id);

ALTER TABLE private_isg.equipment_type_suggestions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.equipment_check_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

-- How long before a due date the page starts warning. One number, owned by the
-- server and reported on every read, so the client never invents a window.
CREATE FUNCTION private_isg.equipment_notice_days() RETURNS integer
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$ SELECT 30 $$;

-- What the inventory says about one item today. Nothing is stored: the answer
-- is worked out from the last inspection and the type's period at read time,
-- so no row can carry yesterday's answer.
--
-- 'period_unknown' is the honest answer when an inspection exists but the type
-- has no rule. It is deliberately NOT 'valid': not knowing when something is
-- next due is a gap in the record, not a clean bill.
CREATE FUNCTION private_isg.equipment_check_status(p_next_due date,p_has_inspection boolean,
  p_last_result text,p_notice_days integer,p_today date) RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF NOT p_has_inspection THEN RETURN 'never_inspected'; END IF;
  IF p_last_result='fail' THEN RETURN 'failed'; END IF;
  IF p_next_due IS NULL THEN RETURN 'period_unknown'; END IF;
  IF p_next_due<p_today THEN RETURN 'overdue'; END IF;
  IF p_next_due<=p_today+p_notice_days THEN RETURN 'due_soon'; END IF;
  RETURN 'valid';
END $$;

-- The counters the page shows. Five groups over six states, and every state
-- belongs to exactly one group, so a counter and the filter it carries can
-- never disagree about which rows they cover.
CREATE FUNCTION private_isg.equipment_check_group(p_state text) RETURNS text
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT CASE p_state
    WHEN 'valid' THEN 'current'
    WHEN 'due_soon' THEN 'due_soon'
    WHEN 'overdue' THEN 'overdue'
    WHEN 'failed' THEN 'failed'
    ELSE 'untracked' END
$$;

CREATE FUNCTION private_isg.equipment_check_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM private_isg.module_gate('equipment',p_write);
END $$;

-- A NULL company is the whole account, and only for reads: every write names
-- the company it writes into. The domain functions below were written for a
-- caller that had already checked ownership; this is that caller.
--
-- PILOT DIVERGENCE 3: this is the development function plus the two P05 pilot
-- gates `require_company` already applies live, so the module is reachable
-- only by an allowlisted pilot account and only for a company that account is
-- granted. A non-pilot user gets FEATURE_UNAVAILABLE before anything else.
CREATE FUNCTION private_isg.require_equipment_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  PERFORM private_isg.equipment_check_gate(p_write);
  IF p_write THEN
    IF p_company IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    IF NOT private_isg.p05_pilot_can_read(actor,p_company) OR
       NOT private_isg.p05_pilot_account_enabled(actor,true) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND
      status IN ('active','trialing','grace_period') AND
      (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSIF p_company IS NOT NULL THEN
    IF NOT private_isg.p05_pilot_can_read(actor,p_company) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSE
    -- The account-wide read is still a pilot surface: an account with no pilot
    -- enrolment does not get an empty board, it gets the closed answer.
    IF NOT private_isg.p05_pilot_account_enabled(actor,false) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  RETURN actor;
END $$;
-- The general period the product starts a type at. Separate from the name
-- catalogue, because a name is a name and a period is a claim that needs its
-- own basis written next to it.
CREATE TABLE private_isg.equipment_default_periods (
  equipment_type text PRIMARY KEY REFERENCES private_isg.equipment_type_suggestions(equipment_type),
  period_months integer NOT NULL CHECK(period_months BETWEEN 1 AND 240),
  basis_note text NOT NULL CHECK(length(basis_note) BETWEEN 20 AND 500),
  created_at timestamptz NOT NULL DEFAULT now()
);
-- One general period, stated as one. The annex's own rule is "yearly unless
-- something else is specified", so that is what ships; a standard, a manual or
-- a sector exception is the expert's to enter, and the note says so on the row.
INSERT INTO private_isg.equipment_default_periods(equipment_type,period_months,basis_note)
SELECT s.equipment_type,12,
  'Yönetmelik ekinde aksi belirtilmedikçe genel periyot bir yıldır. Standart, '||
  'üretici kılavuzu veya sektör istisnası farklı bir süre öngörüyorsa uzman değiştirir.'
FROM private_isg.equipment_type_suggestions s;

-- A default is flagged for the expert's confirmation the same way an
-- unapproved fixture is. The schema forces it; no function can opt out.
ALTER TABLE private_isg.equipment_inspection_rules
  DROP CONSTRAINT equipment_inspection_rules_period_source_check;
ALTER TABLE private_isg.equipment_inspection_rules
  ADD CONSTRAINT equipment_inspection_rules_period_source_check
  CHECK(period_source IN ('manufacturer','rule_version','unapproved_fixture','regulation_default'));
ALTER TABLE private_isg.equipment_inspection_rules
  ADD CONSTRAINT equipment_inspection_rules_default_needs_review_check
  CHECK(period_source<>'regulation_default' OR needs_review);

-- Which answer the stored next date is: the one the period produced, or the one
-- the expert wrote. A date nobody derived is never presented as derived.
ALTER TABLE private_isg.equipment_inspections
  ADD COLUMN due_source text CHECK(due_source IS NULL OR due_source IN ('period','expert'));
-- The expert's own note that an assignment was made in İSG-KATİP for this
-- check. Optional, and never a verification.
ALTER TABLE private_isg.equipment_inspections
  ADD COLUMN katip_assignment_declared boolean NOT NULL DEFAULT false,
  ADD COLUMN katip_declared_note text CHECK(katip_declared_note IS NULL OR length(katip_declared_note)<=200),
  -- Same guarantee the KATİP contract table carries: this can only be false,
  -- so no row can ever say the official system was checked.
  ADD COLUMN katip_official_verification boolean NOT NULL DEFAULT false
    CHECK(NOT katip_official_verification),
  ADD CONSTRAINT equipment_inspection_katip_note_check
    CHECK(katip_assignment_declared OR katip_declared_note IS NULL);

-- Materialises the default period as a real, visible, editable company rule the
-- first time a type is used. Nothing is hidden: the rule shows up in the period
-- list with its source and its review flag.
CREATE FUNCTION private_isg.ensure_equipment_period(p_company uuid,p_type text,p_now timestamptz) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE fallback private_isg.equipment_default_periods;
BEGIN
  PERFORM 1 FROM private_isg.equipment_inspection_rules
    WHERE company_id=p_company AND equipment_type=p_type FOR SHARE;
  IF FOUND THEN RETURN; END IF;
  SELECT * INTO fallback FROM private_isg.equipment_default_periods WHERE equipment_type=p_type;
  -- A type the product has no default for keeps no period at all, and the row
  -- goes on reading 'period_unknown' rather than borrowing another type's.
  IF NOT FOUND THEN RETURN; END IF;
  INSERT INTO private_isg.equipment_inspection_rules(company_id,equipment_type,period_months,
      period_source,exception_note,needs_review,created_at)
    VALUES(p_company,p_type,fallback.period_months,'regulation_default',fallback.basis_note,true,p_now)
  ON CONFLICT(company_id,equipment_type) DO NOTHING;
END $$;

-- What the period would produce for a given report date, so the boundary can
-- tell the server's own answer apart from the expert's without recomputing the
-- rule in two places.
CREATE FUNCTION private_isg.equipment_period_due(p_company uuid,p_type text,p_performed_on date,
  p_result text) RETURNS date
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT CASE WHEN p_result='fail' THEN NULL
    ELSE (p_performed_on+make_interval(months=>r.period_months))::date END
  FROM private_isg.equipment_inspection_rules r
  WHERE r.company_id=p_company AND r.equipment_type=p_type
$$;
CREATE OR REPLACE FUNCTION private_isg.equipment_check_row(p_equipment uuid,p_today date,p_history boolean) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE item private_isg.equipment_items; latest private_isg.equipment_inspections;
  rule private_isg.equipment_inspection_rules; notice integer:=private_isg.equipment_notice_days();
  state text;
BEGIN
  SELECT * INTO item FROM private_isg.equipment_items WHERE equipment_id=p_equipment;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO latest FROM private_isg.equipment_inspections
    WHERE equipment_id=p_equipment ORDER BY performed_on DESC,inspection_id LIMIT 1;
  SELECT * INTO rule FROM private_isg.equipment_inspection_rules
    WHERE company_id=item.company_id AND equipment_type=item.equipment_type;
  state:=private_isg.equipment_check_status(latest.next_due_on,latest.inspection_id IS NOT NULL,
    latest.result,notice,p_today);
  RETURN jsonb_build_object(
    'id',item.equipment_id,'company_id',item.company_id,'workplace_id',item.workplace_id,
    'equipment_type',item.equipment_type,'serial_tag',item.serial_tag,
    'acquired_on',item.acquired_on,'location_note',item.location_note,
    'is_archived',item.is_archived,'created_at',item.created_at,
    'state',state,'state_group',private_isg.equipment_check_group(state),
    'state_authority','computed_at_read','notice_days',notice,
    'period_months',rule.period_months,'period_source',rule.period_source,
    'period_needs_review',CASE WHEN rule.equipment_type IS NULL THEN NULL ELSE rule.needs_review END,
    'period_exception_note',rule.exception_note,
    'period_defined_after_report',rule.equipment_type IS NOT NULL AND latest.inspection_id IS NOT NULL
      AND latest.next_due_on IS NULL AND latest.result<>'fail',
    'last_performed_on',latest.performed_on,'last_result',latest.result,
    'last_inspector',latest.inspector,'last_external_ref',latest.external_ref,
    'next_due_on',latest.next_due_on,
    -- Whether that date is the one the period produced or the one the expert
    -- wrote. A changed date never reads as a derived one.
    'due_source',latest.due_source,
    'katip_assignment_declared',coalesce(latest.katip_assignment_declared,false),
    'katip_declared_note',latest.katip_declared_note,
    -- Structurally false: nothing here checked the official system.
    'katip_official_verification',false,
    'evidence_asset_id',NULL::uuid,
    'inspections',CASE WHEN p_history THEN
      (SELECT coalesce(jsonb_agg(jsonb_build_object('id',i.inspection_id,'performed_on',i.performed_on,
          'result',i.result,'next_due_on',i.next_due_on,'period_months',i.period_months,
          'due_source',i.due_source,'inspector',i.inspector,'external_ref',i.external_ref,'note',i.note,
          'katip_assignment_declared',i.katip_assignment_declared,
          'katip_declared_note',i.katip_declared_note,
          'evidence_asset_id',NULL::uuid)
          ORDER BY i.performed_on DESC,i.inspection_id),'[]'::jsonb)
       FROM private_isg.equipment_inspections i WHERE i.equipment_id=p_equipment) END,
    'health_record',false);
END $$;

-- The catalogue tells the client what a type starts at and what that default
-- is, so a period on screen is never a number with no story.
CREATE OR REPLACE FUNCTION private_isg.read_equipment_checks(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_type text,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; needle text; today date; notice integer:=private_isg.equipment_notice_days();
  page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_types jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_equipment_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'UTC')::date;

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',2,'kind','catalog','notice_days',notice,
      'suggestions',(SELECT coalesce(jsonb_agg(jsonb_build_object('code',s.equipment_type,
          'ordinal',s.ordinal,'default_period_months',d.period_months,
          'default_basis_note',d.basis_note) ORDER BY s.ordinal),'[]'::jsonb)
        FROM private_isg.equipment_type_suggestions s
        LEFT JOIN private_isg.equipment_default_periods d ON d.equipment_type=s.equipment_type),
      -- The product now starts a type at a period. It is a general default that
      -- the expert confirms, never a determination made for this company.
      'period_defaults_offered',true,
      'period_default_source','regulation_default',
      'period_default_needs_review',true,
      'rules',(SELECT coalesce(jsonb_agg(jsonb_build_object('equipment_type',r.equipment_type,
          'period_months',r.period_months,'period_source',r.period_source,
          'needs_review',r.needs_review,'exception_note',r.exception_note) ORDER BY r.equipment_type),'[]'::jsonb)
        FROM private_isg.equipment_inspection_rules r WHERE p_company IS NOT NULL AND r.company_id=p_company),
      'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name)
          ORDER BY w.name),'[]'::jsonb)
        FROM private_isg.workplaces w
        WHERE p_company IS NOT NULL AND w.company_id=p_company AND w.owner_id=actor AND NOT w.is_archived),
      'katip_official_verification',false,
      'health_records_tracked',false);
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.equipment_items e
      JOIN public.companies c ON c.id=e.company_id AND c.user_id=actor
      WHERE e.equipment_id=p_id AND (p_company IS NULL OR e.company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',2,'kind','detail','today',today,
      'row',private_isg.equipment_check_row(p_id,today,true));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('never_inspected','period_unknown','failed','overdue',
    'due_soon','valid','current','untracked') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE c.user_id=actor AND NOT c.is_archived
  ), latest AS (
    SELECT DISTINCT ON (i.equipment_id) i.equipment_id,i.next_due_on,i.result,i.performed_on
    FROM private_isg.equipment_inspections i
    JOIN private_isg.equipment_items e ON e.equipment_id=i.equipment_id
    WHERE e.company_id IN (SELECT id FROM scope)
    ORDER BY i.equipment_id,i.performed_on DESC,i.inspection_id
  ), page AS (
    SELECT e.equipment_id,e.company_id,s.name AS company_name,e.equipment_type,e.serial_tag,
      e.workplace_id,
      private_isg.equipment_check_status(l.next_due_on,l.equipment_id IS NOT NULL,l.result,notice,today) AS entry_state,
      l.next_due_on,
      row_number() OVER (ORDER BY
        CASE private_isg.equipment_check_status(l.next_due_on,l.equipment_id IS NOT NULL,l.result,notice,today)
          WHEN 'overdue' THEN 0 WHEN 'failed' THEN 1 WHEN 'never_inspected' THEN 2
          WHEN 'period_unknown' THEN 3 WHEN 'due_soon' THEN 4 ELSE 5 END,
        l.next_due_on NULLS FIRST,s.name,e.serial_tag,e.equipment_id) AS ordinal
    FROM private_isg.equipment_items e
    JOIN scope s ON s.id=e.company_id
    LEFT JOIN latest l ON l.equipment_id=e.equipment_id
    WHERE e.owner_id=actor AND NOT e.is_archived
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_workplace IS NULL OR workplace_id=p_workplace)
      AND (p_type IS NULL OR equipment_type=p_type)
      AND (p_state IS NULL OR entry_state=p_state
        OR private_isg.equipment_check_group(entry_state)=p_state)
      AND (needle IS NULL OR serial_tag ILIKE '%'||needle||'%'
           OR equipment_type ILIKE '%'||needle||'%' OR company_name ILIKE '%'||needle||'%')
  )
  SELECT
    (SELECT coalesce(jsonb_object_agg(state,total),'{}'::jsonb) FROM
      (SELECT entry_state AS state,count(*) AS total FROM page GROUP BY entry_state) a),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'total',total,'counts',states)
       ORDER BY name),'[]'::jsonb) FROM
      (SELECT company_id AS id,max(company_name) AS name,count(*) AS total,
        jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT company_id,company_name,entry_state,count(*) AS state_total FROM page
          GROUP BY company_id,company_name,entry_state) b GROUP BY company_id) c),
    (SELECT coalesce(jsonb_object_agg(equipment_type,states),'{}'::jsonb) FROM
      (SELECT equipment_type,jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT equipment_type,entry_state,count(*) AS state_total FROM scoped
          GROUP BY equipment_type,entry_state) d GROUP BY equipment_type) e),
    (SELECT count(*) FROM filtered),
    (SELECT coalesce(jsonb_agg(entry ORDER BY sort),'[]'::jsonb) FROM (
       SELECT picked.ordinal AS sort,
         private_isg.equipment_check_row(picked.equipment_id,today,false)
           ||jsonb_build_object('company_name',picked.company_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,tally_types,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',2,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,'type_counts',tally_types,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,'notice_days',notice,
    'katip_official_verification',false,
    'compliance_verdict',NULL,'health_records_tracked',false);
END $$;
CREATE OR REPLACE FUNCTION private_isg.mutate_equipment_checks(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.equipment_check_receipts;
  result jsonb; answer jsonb; target uuid; item private_isg.equipment_items;
  report private_isg.equipment_inspections;
  stamp timestamptz:=clock_timestamp(); today date; derived date; chosen date; inspection uuid;
BEGIN
  actor:=private_isg.require_equipment_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4096 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'UTC')::date;
  allowed:=CASE p_action
    WHEN 'set_rule' THEN ARRAY['equipment_type','period_months','period_source','exception_note']
    WHEN 'register_equipment' THEN ARRAY['workplace_id','equipment_type','serial_tag','acquired_on','location_note']
    WHEN 'update_equipment' THEN ARRAY['equipment_id','workplace_id','serial_tag','acquired_on','location_note']
    WHEN 'archive_equipment' THEN ARRAY['equipment_id']
    WHEN 'record_inspection' THEN ARRAY['equipment_id','performed_on','result','inspector',
      'external_ref','note','evidence_asset_id','next_due_on','katip_declared','katip_note']
    -- The date and the result are not here: they are what the report is.
    WHEN 'update_inspection' THEN ARRAY['equipment_id','inspection_id','inspector',
      'external_ref','note','evidence_asset_id','next_due_on','katip_declared','katip_note']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-equipment:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.equipment_check_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action='set_rule' THEN
    IF p_payload->>'equipment_type' IS NULL OR p_payload->>'period_months' IS NULL OR
       p_payload->>'period_source' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    answer:=private_isg.set_equipment_inspection_rule(p_company,p_payload->>'equipment_type',
      (p_payload->>'period_months')::integer,p_payload->>'period_source',
      nullif(btrim(coalesce(p_payload->>'exception_note','')),''),stamp);
    result:=jsonb_build_object('schema_version',3,'action',p_action,'rule',answer);
  ELSIF p_action='register_equipment' THEN
    IF p_payload->>'workplace_id' IS NULL OR p_payload->>'equipment_type' IS NULL OR
       p_payload->>'serial_tag' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM private_isg.ensure_equipment_period(p_company,p_payload->>'equipment_type',stamp);
    answer:=private_isg.register_equipment(p_company,(p_payload->>'workplace_id')::uuid,
      p_payload->>'equipment_type',p_payload->>'serial_tag',
      (p_payload->>'acquired_on')::date,stamp);
    target:=(answer->>'equipment_id')::uuid;
    IF NOT (answer->>'replayed')::boolean THEN
      UPDATE private_isg.equipment_items
        SET location_note=nullif(btrim(coalesce(p_payload->>'location_note','')),'')
        WHERE equipment_id=target;
    END IF;
    result:=jsonb_build_object('schema_version',3,'action',p_action,'equipment_id',target,
      'row',private_isg.equipment_check_row(target,today,true));
  ELSE
    target:=(p_payload->>'equipment_id')::uuid;
    SELECT * INTO item FROM private_isg.equipment_items
      WHERE equipment_id=target AND company_id=p_company AND owner_id=actor FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;

    IF p_action='update_equipment' THEN
      IF p_payload ? 'workplace_id' THEN
        PERFORM 1 FROM private_isg.workplaces WHERE id=(p_payload->>'workplace_id')::uuid
          AND company_id=p_company AND owner_id=actor AND NOT is_archived;
        IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      END IF;
      UPDATE private_isg.equipment_items SET
        workplace_id=coalesce((p_payload->>'workplace_id')::uuid,workplace_id),
        serial_tag=coalesce(private_isg.text_value(p_payload->>'serial_tag',100),serial_tag),
        acquired_on=CASE WHEN p_payload ? 'acquired_on' THEN (p_payload->>'acquired_on')::date ELSE acquired_on END,
        location_note=CASE WHEN p_payload ? 'location_note'
          THEN nullif(btrim(coalesce(p_payload->>'location_note','')),'') ELSE location_note END
        WHERE equipment_id=target;
    ELSIF p_action='archive_equipment' THEN
      UPDATE private_isg.equipment_items SET is_archived=true WHERE equipment_id=target;

    ELSIF p_action='update_inspection' THEN
      IF p_payload->>'inspection_id' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      SELECT * INTO report FROM private_isg.equipment_inspections
        WHERE inspection_id=(p_payload->>'inspection_id')::uuid AND equipment_id=target FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      IF p_payload ? 'evidence_asset_id' AND p_payload->>'evidence_asset_id' IS NOT NULL THEN
        -- PILOT DIVERGENCE: the file archive is not in this pilot, so there is
        -- no cleared asset to point at and no column to hold one. A reference
        -- is refused rather than stored unbacked.
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      -- The date is measured against the report's own date and result, which
      -- this action cannot change.
      derived:=private_isg.equipment_period_due(p_company,item.equipment_type,
        report.performed_on,report.result);
      chosen:=CASE WHEN p_payload ? 'next_due_on' THEN (p_payload->>'next_due_on')::date
                   ELSE report.next_due_on END;
      IF chosen IS NOT NULL THEN
        IF chosen<=report.performed_on THEN
          RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DUE_BEFORE_REPORT'; END IF;
        IF report.result='fail' THEN
          RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DUE_ON_A_FAILED_CHECK'; END IF;
      END IF;
      UPDATE private_isg.equipment_inspections SET
        inspector=CASE WHEN p_payload ? 'inspector'
          THEN nullif(btrim(coalesce(p_payload->>'inspector','')),'') ELSE inspector END,
        external_ref=CASE WHEN p_payload ? 'external_ref'
          THEN nullif(btrim(coalesce(p_payload->>'external_ref','')),'') ELSE external_ref END,
        note=CASE WHEN p_payload ? 'note'
          THEN nullif(btrim(coalesce(p_payload->>'note','')),'') ELSE note END,
        next_due_on=chosen,
        -- Recomputed the same way it is on entry: a corrected date that lands
        -- on what the period produces reads as the period's answer again.
        due_source=CASE WHEN chosen IS NULL THEN NULL
          WHEN chosen=derived THEN 'period' ELSE 'expert' END,
        katip_assignment_declared=CASE WHEN p_payload ? 'katip_declared'
          THEN coalesce((p_payload->>'katip_declared')::boolean,false)
          ELSE katip_assignment_declared END,
        katip_declared_note=CASE
          WHEN p_payload ? 'katip_declared' AND NOT coalesce((p_payload->>'katip_declared')::boolean,false) THEN NULL
          WHEN p_payload ? 'katip_note' THEN nullif(btrim(coalesce(p_payload->>'katip_note','')),'')
          ELSE katip_declared_note END
        WHERE inspection_id=report.inspection_id;

    ELSE
      IF p_payload->>'performed_on' IS NULL OR p_payload->>'result' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      IF (p_payload->>'performed_on')::date>today THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PERFORMED_IN_THE_FUTURE'; END IF;
      PERFORM private_isg.ensure_equipment_period(p_company,item.equipment_type,stamp);
      derived:=private_isg.equipment_period_due(p_company,item.equipment_type,
        (p_payload->>'performed_on')::date,p_payload->>'result');
      answer:=private_isg.record_equipment_inspection(target,(p_payload->>'performed_on')::date,
        p_payload->>'result',(p_payload->>'evidence_asset_id')::uuid,
        nullif(btrim(coalesce(p_payload->>'external_ref','')),''),
        nullif(btrim(coalesce(p_payload->>'note','')),''),stamp);
      inspection:=(answer->>'inspection_id')::uuid;
      IF NOT (answer->>'replayed')::boolean THEN
        chosen:=(p_payload->>'next_due_on')::date;
        IF chosen IS NOT NULL THEN
          IF chosen<=(p_payload->>'performed_on')::date THEN
            RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DUE_BEFORE_REPORT'; END IF;
          IF p_payload->>'result'='fail' THEN
            RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DUE_ON_A_FAILED_CHECK'; END IF;
        END IF;
        UPDATE private_isg.equipment_inspections SET
          inspector=nullif(btrim(coalesce(p_payload->>'inspector','')),''),
          next_due_on=coalesce(chosen,next_due_on),
          due_source=CASE
            WHEN coalesce(chosen,derived) IS NULL THEN NULL
            WHEN chosen IS NULL OR chosen=derived THEN 'period' ELSE 'expert' END,
          katip_assignment_declared=coalesce((p_payload->>'katip_declared')::boolean,false),
          katip_declared_note=CASE WHEN coalesce((p_payload->>'katip_declared')::boolean,false)
            THEN nullif(btrim(coalesce(p_payload->>'katip_note','')),'') END
          WHERE inspection_id=inspection;
      END IF;
    END IF;
    result:=jsonb_build_object('schema_version',3,'action',p_action,'equipment_id',target,
      'row',private_isg.equipment_check_row(target,today,true));
  END IF;

  INSERT INTO private_isg.equipment_check_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $$;
CREATE FUNCTION public.isg_equipment_checks_read_v1(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_type text,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_equipment_checks(p_company,p_kind,p_query,p_state,p_workplace,p_type,p_id,p_limit,p_offset)
$$;
CREATE FUNCTION public.isg_equipment_checks_mutate_v1(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.mutate_equipment_checks(p_company,p_action,p_operation,p_mutation,p_payload)
$$;

ALTER TABLE private_isg.equipment_default_periods ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private_isg.module_gate(text,boolean),
  private_isg.module_scope(text,uuid,uuid,boolean),
  private_isg.set_equipment_inspection_rule(uuid,text,integer,text,text,timestamptz),
  private_isg.register_equipment(uuid,uuid,text,text,date,timestamptz),
  private_isg.record_equipment_inspection(uuid,date,text,uuid,text,text,timestamptz),
  private_isg.ensure_equipment_period(uuid,text,timestamptz),
  private_isg.equipment_period_due(uuid,text,date,text),
  private_isg.equipment_notice_days(),
  private_isg.equipment_check_status(date,boolean,text,integer,date),
  private_isg.equipment_check_group(text),
  private_isg.equipment_check_gate(boolean),
  private_isg.require_equipment_company(uuid,boolean),
  private_isg.equipment_check_row(uuid,date,boolean),
  private_isg.read_equipment_checks(uuid,text,text,text,uuid,text,uuid,integer,integer),
  private_isg.mutate_equipment_checks(uuid,text,uuid,uuid,jsonb),
  public.isg_equipment_checks_read_v1(uuid,text,text,text,uuid,text,uuid,integer,integer),
  public.isg_equipment_checks_mutate_v1(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_equipment_checks(uuid,text,text,text,uuid,text,uuid,integer,integer),
  private_isg.mutate_equipment_checks(uuid,text,uuid,uuid,jsonb),
  public.isg_equipment_checks_read_v1(uuid,text,text,text,uuid,text,uuid,integer,integer),
  public.isg_equipment_checks_mutate_v1(uuid,text,uuid,uuid,jsonb) TO authenticated;

-- The switches this bundle exists to open. The pilot allowlist is what keeps
-- the audience narrow; these two only decide whether the module answers at all.
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='modules';
UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true WHERE module='equipment';
