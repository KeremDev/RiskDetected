-- Include company-wide rows in the remaining legacy list readers.
BEGIN;
CREATE FUNCTION private_isg.migration_replace_once(
  p_signature regprocedure,p_old text,p_new text) RETURNS void
LANGUAGE plpgsql SET search_path TO '' AS $patch$
DECLARE definition text; matches integer;
BEGIN
  definition:=pg_get_functiondef(p_signature);
  matches:=(length(definition)-length(replace(definition,p_old,'')))/length(p_old);
  IF matches<>1 THEN RAISE EXCEPTION 'MIGRATION_SOURCE_DRIFT: % found %',p_signature,matches; END IF;
  EXECUTE replace(definition,p_old,p_new);
END $patch$;

SELECT private_isg.migration_replace_once(
 'private_isg.read_appointments(uuid,text,text,text,uuid,text,uuid,integer,integer)'::regprocedure,
 $old$JOIN private_isg.workplaces w ON w.company_id=a.company_id AND w.id=a.scope_workplace_id
    WHERE private_isg.expert_company_visible(w.owner_id,w.company_id,actor) AND NOT w.is_archived$old$,
 $new$LEFT JOIN private_isg.workplaces w ON w.company_id=a.company_id AND w.id=a.scope_workplace_id
    WHERE private_isg.expert_company_visible(a.owner_id,a.company_id,actor)
      AND (a.scope_workplace_id IS NULL OR NOT w.is_archived)$new$);
SELECT private_isg.migration_replace_once(
 'private_isg.read_checklists(uuid,text,text,text,uuid,text,uuid,integer,integer)'::regprocedure,
 $old$JOIN private_isg.workplaces w ON w.company_id=r.company_id AND w.id=r.workplace_id$old$,
 $new$LEFT JOIN private_isg.workplaces w ON w.company_id=r.company_id AND w.id=r.workplace_id$new$);
SELECT private_isg.migration_replace_once(
 'private_isg.read_drills(uuid,text,text,text,uuid,uuid,integer,integer)'::regprocedure,
 $old$JOIN private_isg.workplaces w ON w.company_id=v.company_id AND w.id=v.workplace_id
        WHERE p_company IS NOT NULL AND v.company_id=p_company AND private_isg.expert_company_visible(v.owner_id,v.company_id,actor)
          AND v.state='active' AND NOT w.is_archived$old$,
 $new$LEFT JOIN private_isg.workplaces w ON w.company_id=v.company_id AND w.id=v.workplace_id
        WHERE p_company IS NOT NULL AND v.company_id=p_company AND private_isg.expert_company_visible(v.owner_id,v.company_id,actor)
          AND v.state='active' AND (v.workplace_id IS NULL OR NOT w.is_archived)$new$);
SELECT private_isg.migration_replace_once(
 'private_isg.read_drills(uuid,text,text,text,uuid,uuid,integer,integer)'::regprocedure,
 $old$JOIN private_isg.workplaces w ON w.company_id=d.company_id AND w.id=d.workplace_id
    JOIN private_isg.emergency_plan_versions v
      ON v.plan_id=d.plan_id AND v.version=d.plan_version
    WHERE private_isg.expert_company_visible(v.owner_id,v.company_id,actor) AND NOT w.is_archived$old$,
 $new$LEFT JOIN private_isg.workplaces w ON w.company_id=d.company_id AND w.id=d.workplace_id
    JOIN private_isg.emergency_plan_versions v
      ON v.plan_id=d.plan_id AND v.version=d.plan_version
    WHERE private_isg.expert_company_visible(v.owner_id,v.company_id,actor)
      AND (d.workplace_id IS NULL OR NOT w.is_archived)$new$);
SELECT private_isg.migration_replace_once(
 'private_isg.read_emergency_plans(uuid,text,text,text,uuid,uuid,integer,integer)'::regprocedure,
 $old$JOIN private_isg.workplaces w ON w.company_id=v.company_id AND w.id=v.workplace_id
    WHERE private_isg.expert_company_visible(v.owner_id,v.company_id,actor) AND v.state='active' AND NOT w.is_archived$old$,
 $new$LEFT JOIN private_isg.workplaces w ON w.company_id=v.company_id AND w.id=v.workplace_id
    WHERE private_isg.expert_company_visible(v.owner_id,v.company_id,actor) AND v.state='active'
      AND (v.workplace_id IS NULL OR NOT w.is_archived)$new$);
SELECT private_isg.migration_replace_once(
 'private_isg.read_risk_versions(uuid,text,text,text,uuid,uuid,integer,integer)'::regprocedure,
 $old$JOIN private_isg.workplaces w ON w.company_id=a.company_id AND w.id=a.workplace_id
    WHERE private_isg.expert_company_visible(a.owner_id,a.company_id,actor) AND private_isg.p05_pilot_can_read(actor,a.company_id) AND NOT w.is_archived$old$,
 $new$LEFT JOIN private_isg.workplaces w ON w.company_id=a.company_id AND w.id=a.workplace_id
    WHERE private_isg.expert_company_visible(a.owner_id,a.company_id,actor) AND private_isg.p05_pilot_can_read(actor,a.company_id)
      AND (a.workplace_id IS NULL OR NOT w.is_archived)$new$);

DROP FUNCTION private_isg.migration_replace_once(regprocedure,text,text);
COMMIT;
