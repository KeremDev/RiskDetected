-- Preserve the scored finding inputs in the normal editable nonconformity detail.
DO $migration$
DECLARE original text:=pg_get_functiondef('private_isg.expert_analysis(text,jsonb)'::regprocedure);
 old_part text:=$old$sources->>'references_text',sources->>'responsible',NULL,NULL,NULL,NULL,NULL,NULL,clock_timestamp());$old$;
 new_part text:=$new$sources->>'references_text',sources->>'responsible',
    CASE WHEN coalesce((sources->>'is_scored')::boolean,false) THEN sources->>'primary_method' END,
    CASE WHEN (sources->>'is_scored')::boolean AND sources->>'primary_method'='fine_kinney' THEN (sources->>'fk_probability')::numeric END,
    CASE WHEN (sources->>'is_scored')::boolean AND sources->>'primary_method'='fine_kinney' THEN (sources->>'fk_frequency')::numeric END,
    CASE WHEN (sources->>'is_scored')::boolean AND sources->>'primary_method'='fine_kinney' THEN (sources->>'fk_severity')::numeric END,
    CASE WHEN (sources->>'is_scored')::boolean AND sources->>'primary_method'='matrix_5x5' THEN (sources->>'m5_probability')::integer END,
    CASE WHEN (sources->>'is_scored')::boolean AND sources->>'primary_method'='matrix_5x5' THEN (sources->>'m5_severity')::integer END,clock_timestamp());$new$;
BEGIN
 IF position(old_part in original)=0 THEN RAISE EXCEPTION 'UNEXPECTED_EXPERT_ANALYSIS_DEFINITION'; END IF;
 EXECUTE replace(original,old_part,new_part);
END $migration$;
