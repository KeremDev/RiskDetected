-- Known-good restore point for the v4 engine, 2026-08-26.
--
-- Single-photo analyses were verified clean at prompt v4-vision-core-v5 /
-- router claim-routing-v11 (git tag v4-known-good-2026-08-26). A rollback needs
-- all three parts to move together -- code, deployed function, and this config
-- row -- so the row is copied here verbatim rather than reconstructed from the
-- migration history.
--
-- The copy is inert: resolve_analysis_engine_route_v5 selects
--   where is_active and integrity_status = 'valid'
-- and this row is stored is_active = false, integrity_status = 'retired', so it
-- cannot be picked even if is_active were flipped by accident. Restoring it is
-- deliberate and goes through supabase/operations/v4_known_good_2026-08-26.
do $$
declare
  v_source private.analysis_v4_configs%rowtype;
  v_label constant text := 'known_good_checkpoint_2026_08_26';
begin
  select * into v_source from private.analysis_v4_configs
  where is_active and integrity_status = 'valid'
  order by updated_at desc limit 1;
  if not found then
    raise exception 'no active v4 config to checkpoint';
  end if;
  if v_source.router_version <> 'claim-routing-v11'
    or v_source.prompt_version <> 'v4-vision-core-v5' then
    raise exception 'active config is not the intended checkpoint (% / %)',
      v_source.prompt_version, v_source.router_version;
  end if;

  -- Idempotent: re-running replaces the stored copy rather than piling up rows.
  delete from private.analysis_v4_configs
  where config->>'checkpoint_label' = v_label;

  insert into private.analysis_v4_configs (
    engine_version, provider_contract_version, domain_schema_version,
    prompt_version, prompt_sha256, router_version, coverage_version,
    assurance_version, standards_version, quality_trace_version,
    report_projection_version, client_api_contract, config,
    integrity_status, is_active
  ) values (
    v_source.engine_version, v_source.provider_contract_version,
    v_source.domain_schema_version, v_source.prompt_version,
    v_source.prompt_sha256, v_source.router_version, v_source.coverage_version,
    v_source.assurance_version, v_source.standards_version,
    v_source.quality_trace_version, v_source.report_projection_version,
    v_source.client_api_contract,
    v_source.config || jsonb_build_object(
      'checkpoint_label', v_label,
      'checkpoint_taken_at', now()::text,
      'checkpoint_git_tag', 'v4-known-good-2026-08-26',
      'checkpoint_git_commit', '61e079615b48b083306ac8d450e07eb975d346d8'
    ),
    'retired', false
  );

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = v_label
    and is_active = false and integrity_status = 'retired'
    and router_version = 'claim-routing-v11';
  if not found then
    raise exception 'checkpoint row did not land';
  end if;

  -- The live row must be untouched and still the only active one.
  if (select count(*) from private.analysis_v4_configs
      where is_active and integrity_status = 'valid') <> 1 then
    raise exception 'checkpoint changed which config is live';
  end if;
end $$;
