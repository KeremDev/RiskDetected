-- Company creation is temporarily available to every active pilot account.
-- The paid-plan and company-count gates will be reintroduced when limits are
-- ready for the production rollout. Read/write access to existing companies
-- and every other module remains protected by its own entitlement boundary.
CREATE OR REPLACE FUNCTION private.enforce_company_write_rules()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='public','private' AS $$
BEGIN
  NEW.name := btrim(NEW.name);
  NEW.logo_path := nullif(btrim(coalesce(NEW.logo_path,'')), '');
  NEW.address := nullif(btrim(coalesce(NEW.address,'')), '');
  NEW.contact_person := nullif(btrim(coalesce(NEW.contact_person,'')), '');
  NEW.department := nullif(btrim(coalesce(NEW.department,'')), '');
  NEW.default_responsible := nullif(btrim(coalesce(NEW.default_responsible,'')), '');
  IF NEW.name='' THEN RAISE EXCEPTION 'company_name_required'; END IF;
  IF NEW.default_due_days IS NOT NULL AND (NEW.default_due_days<1 OR NEW.default_due_days>365) THEN
    RAISE EXCEPTION 'company_default_due_days_invalid';
  END IF;
  -- Intentionally no subscription or company-count check during the pilot.
  NEW.updated_at := now();
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION private_isg.p05_pilot_create_company(
  p_mutation uuid,
  p_name text,
  p_hazard_class text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  actor uuid:=private_isg.active_actor();
  account private_isg.p05_pilot_accounts;
  prior private_isg.p05_pilot_company_origins;
  company public.companies;
  fingerprint bytea;
  name text;
BEGIN
  IF p_mutation IS NULL OR p_name IS NULL OR p_hazard_class IS NULL
     OR p_hazard_class NOT IN ('low','medium','high') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';
  END IF;

  name:=private_isg.text_value(p_name,200);
  SELECT * INTO account
    FROM private_isg.p05_pilot_accounts
   WHERE actor_id=actor
   FOR UPDATE;
  IF NOT FOUND OR NOT private_isg.p05_pilot_account_enabled(actor,true) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE';
  END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(name,p_hazard_class)::text,'UTF8'));
  SELECT * INTO prior
    FROM private_isg.p05_pilot_company_origins
   WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_sha256<>fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT';
    END IF;
    -- Replays must work even while the paid-plan gate is disabled. Ownership,
    -- archive state and pilot grant are still checked explicitly.
    SELECT * INTO STRICT company
      FROM public.companies
     WHERE id=prior.company_id AND user_id=actor AND NOT is_archived;
    IF NOT private_isg.p05_pilot_can_read(actor,prior.company_id) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';
    END IF;
    RETURN jsonb_build_object('schema_version',1,'company',to_jsonb(company),'replayed',true);
  END IF;

  INSERT INTO public.companies(user_id,name,hazard_class)
  VALUES(actor,name,p_hazard_class)
  RETURNING * INTO company;
  INSERT INTO private_isg.p05_pilot_company_origins(company_id,actor_id,mutation_id,request_sha256)
  VALUES(company.id,actor,p_mutation,fingerprint);
  INSERT INTO private_isg.p05_pilot_grants(actor_id,company_id,approved_reference,expires_at)
  VALUES(actor,company.id,account.approved_reference,account.expires_at);
  PERFORM private_isg.ensure_default(company.id);
  RETURN jsonb_build_object('schema_version',1,'company',to_jsonb(company),'replayed',false);
END $$;
