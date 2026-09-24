-- The legacy companies trigger also enforced paid plans. Keep its input
-- normalization and validation, but defer subscription/count limits until the
-- production entitlement rollout.
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
  NEW.updated_at := now();
  RETURN NEW;
END $$;
