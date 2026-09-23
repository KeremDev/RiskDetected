-- Staging OSGB pilot: printed employer, participant title and trainer title
-- fields may be completed on paper. Training content checks stay in force.
BEGIN;

DO $patch$
DECLARE
  scope_source text := pg_get_functiondef('private_isg.education_scope(jsonb,jsonb,jsonb,boolean)'::regprocedure);
  certificate_source text := pg_get_functiondef('private_isg.education_certificate(jsonb)'::regprocedure);
  employer_line constant text := $line$ IF length(btrim(coalesce(p_scope->>'employer_name','')))=0 THEN issues:=issues||jsonb_build_array('EMPLOYER_MISSING'); END IF;$line$;
  legacy_line constant text := $line$ issues:=scope->'issues';$line$;
  job_line constant text := $line$ IF btrim(coalesce(person->>'job_title',''))='' THEN issues:=issues||jsonb_build_array('JOB_TITLE_MISSING'); END IF;$line$;
  trainer_line constant text := $line$  IF btrim(coalesce(tr->>'title',''))='' THEN issues:=issues||jsonb_build_array('TRAINER_TITLE_MISSING'); END IF;$line$;
BEGIN
  IF (length(scope_source)-length(replace(scope_source,employer_line,'')))/length(employer_line)<>1
     OR (length(certificate_source)-length(replace(certificate_source,legacy_line,'')))/length(legacy_line)<>1
     OR (length(certificate_source)-length(replace(certificate_source,job_line,'')))/length(job_line)<>1
     OR (length(certificate_source)-length(replace(certificate_source,trainer_line,'')))/length(trainer_line)<>1 THEN
    RAISE EXCEPTION 'Unexpected education certificate field checks';
  END IF;
  EXECUTE replace(scope_source,employer_line,'');
  certificate_source:=replace(certificate_source,legacy_line,
    $line$ issues:=coalesce(scope->'issues','[]'::jsonb)-'EMPLOYER_MISSING';$line$);
  certificate_source:=replace(certificate_source,job_line,'');
  certificate_source:=replace(certificate_source,trainer_line,'');
  EXECUTE certificate_source;
END $patch$;

NOTIFY pgrst, 'reload schema';
COMMIT;
