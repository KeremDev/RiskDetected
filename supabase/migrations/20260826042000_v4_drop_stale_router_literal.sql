-- begin_analysis_engine_run_v4 fell back to the literal 'claim-routing-v3' when
-- the route snapshot carried no policy_version. Every live snapshot does carry
-- one, so the fallback never fires today -- but it is the same stale-pin shape
-- that already broke this engine twice: bump the router and any snapshot missing
-- the field silently records the old version, after which the deployed function
-- rejects its own run as v4_runtime_snapshot_mismatch.
--
-- The snapshot gate now requires policy_version the way it already requires
-- prompt_version, and the insert reads it with no literal default, so a
-- malformed snapshot fails loudly at the gate instead of producing a
-- mislabelled run. The function keeps its original security definer and empty
-- search_path; every reference in the body is schema-qualified.
do $$
declare
  v_oid oid;
  v_src text;
begin
  select p.oid into v_oid from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'begin_analysis_engine_run_v4';
  if v_oid is null then
    raise exception 'begin_analysis_engine_run_v4 is missing';
  end if;

  select prosrc into v_src from pg_proc where oid = v_oid;

  v_src := replace(
    v_src,
    'or coalesce(v_engine->>''prompt_sha256'','''') !~ ''^[a-f0-9]{64}$'' then',
    'or coalesce(v_engine->>''prompt_sha256'','''') !~ ''^[a-f0-9]{64}$''
    or coalesce(v_engine->>''policy_version'','''') = '''' then'
  );
  v_src := replace(
    v_src,
    'coalesce(v_engine->>''policy_version'',''claim-routing-v3'')',
    'v_engine->>''policy_version'''
  );

  if v_src like '%claim-routing-v3%' then
    raise exception 'stale router literal still present after rewrite';
  end if;
  if v_src not like '%coalesce(v_engine->>''policy_version'','''') = ''''%' then
    raise exception 'policy_version gate was not added';
  end if;

  execute format(
    'create or replace function public.begin_analysis_engine_run_v4(%s) '
    'returns jsonb language plpgsql security definer set search_path = '''' as %L',
    -- Not identity arguments: p_job_mode carries a default and dropping it
    -- makes Postgres refuse the replace outright.
    pg_get_function_arguments(v_oid),
    v_src
  );
end $$;

do $$
begin
  perform 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'begin_analysis_engine_run_v4'
    and p.prosecdef
    and p.proconfig @> array['search_path=""']
    and p.prosrc not like '%claim-routing-v3%'
    and p.prosrc like '%coalesce(v_engine->>''policy_version'','''') = ''''%';
  if not found then
    raise exception 'begin_analysis_engine_run_v4 did not take the router literal removal';
  end if;
end $$;
