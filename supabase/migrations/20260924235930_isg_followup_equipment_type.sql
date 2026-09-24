-- Expose the equipment category beside its serial in deadline cards.
-- Preserve the installed function's authorization and filtering logic.
SET LOCAL lock_timeout = '2s';
SET LOCAL statement_timeout = '30s';

DO $$
DECLARE
  definition text := pg_catalog.pg_get_functiondef(
    'public.isg_pilot_followup_v2(uuid,text,text,text,integer)'::pg_catalog.regprocedure);
  file_field text := '      END AS file_category,';
  base_field text := '    FROM base b';
BEGIN
  IF definition NOT LIKE '%END AS file_category,%'
     OR definition NOT LIKE '%FROM base b%'
     OR definition LIKE '%AS equipment_type,%' THEN
    RAISE EXCEPTION 'FOLLOWUP_V2_SHAPE_CHANGED';
  END IF;
  definition := replace(definition, file_field,
    file_field || E'\n' ||
    '      CASE WHEN b.kind = ''equipment'' THEN equipment.equipment_type END AS equipment_type,' || E'\n' ||
    '      CASE WHEN b.kind = ''equipment'' THEN equipment.equipment_type_label END AS equipment_type_label,');
  definition := replace(definition, base_field,
    base_field || E'\n' ||
    '    LEFT JOIN private_isg.equipment_items equipment' || E'\n' ||
    '      ON b.kind = ''equipment'' AND equipment.equipment_id = b.record_id');
  IF definition NOT LIKE '%AS equipment_type,%'
     OR definition NOT LIKE '%LEFT JOIN private_isg.equipment_items equipment%' THEN
    RAISE EXCEPTION 'FOLLOWUP_V2_PATCH_FAILED';
  END IF;
  EXECUTE definition;
END $$;
