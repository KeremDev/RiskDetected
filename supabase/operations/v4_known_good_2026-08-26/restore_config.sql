-- Restores the v4 engine config to the 2026-08-26 known-good checkpoint.
--
-- Run this ONLY as part of the full rollback in README.md. The config row and
-- the deployed edge function carry the same prompt and router versions, and the
-- function rejects its own run as v4_runtime_snapshot_mismatch when they differ,
-- so restoring one without the other takes the engine down rather than back.
--
-- Deploy the tagged code first, then run this. Safe to re-run.
do $$
declare
  v_checkpoint private.analysis_v4_configs%rowtype;
  v_label constant text := 'known_good_checkpoint_2026_08_26';
  v_live_id uuid;
begin
  select * into v_checkpoint from private.analysis_v4_configs
  where config->>'checkpoint_label' = v_label;
  if not found then
    raise exception 'checkpoint % is missing; restore it from migration 20260826123000 first', v_label;
  end if;

  select id into v_live_id from private.analysis_v4_configs
  where is_active and integrity_status = 'valid'
  order by updated_at desc limit 1;
  if v_live_id is null then
    raise exception 'no live v4 config row to restore onto';
  end if;

  -- Write the checkpoint back onto the live row rather than activating the
  -- copy, so the checkpoint stays available for the next rollback.
  update private.analysis_v4_configs
  set prompt_version = v_checkpoint.prompt_version,
      prompt_sha256 = v_checkpoint.prompt_sha256,
      router_version = v_checkpoint.router_version,
      coverage_version = v_checkpoint.coverage_version,
      assurance_version = v_checkpoint.assurance_version,
      standards_version = v_checkpoint.standards_version,
      quality_trace_version = v_checkpoint.quality_trace_version,
      report_projection_version = v_checkpoint.report_projection_version,
      provider_contract_version = v_checkpoint.provider_contract_version,
      domain_schema_version = v_checkpoint.domain_schema_version,
      client_api_contract = v_checkpoint.client_api_contract,
      config = v_checkpoint.config
        - 'checkpoint_label' - 'checkpoint_taken_at'
        - 'checkpoint_git_tag' - 'checkpoint_git_commit',
      integrity_status = 'valid',
      is_active = true,
      updated_at = now()
  where id = v_live_id;

  -- Anything else that was live gets stood down, so the route resolver's
  -- "order by updated_at desc limit 1" cannot pick a newer stray row.
  update private.analysis_v4_configs
  set is_active = false, updated_at = now()
  where is_active and id <> v_live_id;

  perform 1 from private.analysis_v4_configs
  where id = v_live_id
    and is_active and integrity_status = 'valid'
    and prompt_version = 'v4-vision-core-v5'
    and prompt_sha256 = '116ac911e576c83c61810ecfc956a8f7d0a4b1bb51b16fe8a7c4ec3d1caefb2e'
    and router_version = 'claim-routing-v11';
  if not found then
    raise exception 'restore did not land on the checkpoint versions';
  end if;
  if (select count(*) from private.analysis_v4_configs
      where is_active and integrity_status = 'valid') <> 1 then
    raise exception 'more than one live v4 config after restore';
  end if;
end $$;
