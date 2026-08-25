-- Routing-first v4 analysis engine. This migration is expand-only: v3 routes,
-- prompts and finalizers remain untouched. Activation is performed by a
-- separate migration after the Edge Functions and compatible clients exist.

alter table public.findings
  add column if not exists item_class text not null default 'observed_finding',
  add column if not exists is_scored boolean not null default true;

alter table public.findings
  drop constraint if exists findings_item_class_check;
alter table public.findings
  add constraint findings_item_class_check check (
    item_class in (
      'observed_finding', 'assurance_requirement', 'verification_request'
    )
  );

alter table public.findings
  alter column fk_probability drop not null,
  alter column fk_frequency drop not null,
  alter column fk_severity drop not null,
  alter column fk_band set default 'unknown'::public.risk_level,
  alter column m5_probability drop not null,
  alter column m5_severity drop not null,
  alter column m5_band set default 'unknown'::public.risk_level;

alter table public.findings
  drop constraint if exists findings_scoring_shape_check;
alter table public.findings
  add constraint findings_scoring_shape_check check (
    (
      is_scored
      and item_class = 'observed_finding'
      and fk_probability is not null
      and fk_frequency is not null
      and fk_severity is not null
      and m5_probability is not null
      and m5_severity is not null
    )
    or (
      not is_scored
      and item_class in ('assurance_requirement', 'verification_request')
      and fk_probability is null
      and fk_frequency is null
      and fk_severity is null
      and m5_probability is null
      and m5_severity is null
      and fk_band = 'unknown'::public.risk_level
      and m5_band = 'unknown'::public.risk_level
    )
  ) not valid;

create index if not exists findings_analysis_scored_display_idx
  on public.findings (analysis_id, is_scored desc, display_order, ordinal)
  where coalesce(is_user_deleted, false) = false;

alter table private.analysis_engine_runs
  add column if not exists engine_variant text generated always as
    (coalesce(config_snapshot->>'engine_variant', 'vnext-v3')) stored;

create table private.analysis_v4_configs (
  id uuid primary key default gen_random_uuid(),
  engine_version text not null check (engine_version = 'vnext-v4'),
  provider_contract_version text not null,
  domain_schema_version text not null,
  prompt_version text not null,
  prompt_sha256 text not null check (prompt_sha256 ~ '^[a-f0-9]{64}$'),
  router_version text not null,
  coverage_version text not null,
  assurance_version text not null,
  standards_version text not null,
  quality_trace_version text not null,
  report_projection_version text not null,
  client_api_contract integer not null check (client_api_contract >= 3),
  config jsonb not null default '{}'::jsonb,
  integrity_status text not null default 'valid'
    check (integrity_status in ('valid', 'invalid', 'retired')),
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index analysis_v4_configs_one_active_idx
  on private.analysis_v4_configs (is_active) where is_active;

create table private.analysis_v4_allowlist (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  enabled boolean not null default false,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table private.analysis_claim_candidates (
  id uuid primary key,
  engine_run_id uuid not null references private.analysis_engine_runs(id) on delete cascade,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  photo_index integer not null check (photo_index between 1 and 3),
  candidate_key text not null,
  module_id text not null,
  raw_label text,
  normalized_condition_code text,
  evidence_level text not null check (evidence_level in ('E0','E1','E2','E3','E4','E5')),
  criticality text not null default 'ordinary'
    check (criticality in ('ordinary','serious','permanent','fatal')),
  evidence_region jsonb,
  affirmative_cues jsonb not null default '[]'::jsonb,
  counter_cues jsonb not null default '[]'::jsonb,
  event_path jsonb not null default '{}'::jsonb,
  resolvability jsonb not null default '{}'::jsonb,
  normalized_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (engine_run_id, candidate_key)
);

create table private.analysis_items_v4 (
  id uuid primary key,
  engine_run_id uuid not null references private.analysis_engine_runs(id) on delete cascade,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  candidate_id uuid references private.analysis_claim_candidates(id) on delete set null,
  public_finding_id uuid references public.findings(id) on delete set null,
  item_class text not null check (item_class in (
    'observed_finding', 'assurance_requirement', 'verification_request',
    'positive_control', 'not_assessable'
  )),
  is_scored boolean not null,
  criticality text not null default 'ordinary'
    check (criticality in ('ordinary','serious','permanent','fatal')),
  title text not null,
  description text,
  control_text text,
  root_cause_text text,
  references_text text,
  needs_field_verification boolean not null default false,
  source_photo_indices integer[] not null default '{}',
  display_order integer not null,
  score_payload jsonb,
  internal_priority jsonb not null default '{}'::jsonb,
  canonical_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check ((item_class = 'observed_finding') = is_scored)
);

create index analysis_items_v4_analysis_display_idx
  on private.analysis_items_v4 (analysis_id, display_order);

create table private.analysis_routing_ledger (
  id bigint generated always as identity primary key,
  engine_run_id uuid not null references private.analysis_engine_runs(id) on delete cascade,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  candidate_id uuid references private.analysis_claim_candidates(id) on delete cascade,
  from_state text not null,
  to_state text not null,
  reason_code text not null,
  evidence_level text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table private.analysis_hard_rejection_ledger (
  id bigint generated always as identity primary key,
  engine_run_id uuid not null references private.analysis_engine_runs(id) on delete cascade,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  candidate_id uuid references private.analysis_claim_candidates(id) on delete cascade,
  reason_code text not null,
  criticality text not null,
  evidence_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table private.analysis_quality_trace_v4 (
  engine_run_id uuid primary key references private.analysis_engine_runs(id) on delete cascade,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  prompt_sha256 text not null,
  version_snapshot jsonb not null,
  photo_coverage_matrix jsonb not null default '[]'::jsonb,
  candidate_counts jsonb not null default '{}'::jsonb,
  routing_counts jsonb not null default '{}'::jsonb,
  critical_silent_drop_count integer not null default 0 check (critical_silent_drop_count >= 0),
  targeted_queue jsonb not null default '{}'::jsonb,
  standards_trace jsonb not null default '{}'::jsonb,
  provider_usage jsonb not null default '{}'::jsonb,
  quality_flags text[] not null default '{}',
  trace jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table private.analysis_targeted_runs_v4 (
  id uuid primary key default gen_random_uuid(),
  engine_run_id uuid not null references private.analysis_engine_runs(id) on delete cascade,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  region_key text not null,
  candidate_ids uuid[] not null default '{}',
  photo_index integer not null check (photo_index between 1 and 3),
  status text not null check (status in ('queued','running','completed','failed','budget_excluded')),
  provider_attempt_id uuid references private.analysis_provider_attempts(id) on delete set null,
  result jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (engine_run_id, region_key)
);

create table private.analysis_human_reviews (
  id uuid primary key default gen_random_uuid(),
  engine_run_id uuid not null references private.analysis_engine_runs(id) on delete cascade,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  candidate_id uuid references private.analysis_claim_candidates(id) on delete set null,
  item_id uuid references private.analysis_items_v4(id) on delete set null,
  reviewer_user_id uuid references public.profiles(id) on delete set null,
  label text not null,
  notes text,
  review_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table private.jurisdiction_profiles (
  id text primary key,
  country_code text not null,
  region_code text,
  label text not null,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table private.standards_registry (
  id text primary key,
  source_family text not null,
  title text not null,
  jurisdiction_profile_id text references private.jurisdiction_profiles(id),
  official_url text,
  source_rights text not null check (source_rights in ('official_metadata','licensed_summary','public_domain','unverified')),
  status text not null check (status in ('draft','active','withdrawn','superseded')),
  last_verified_at timestamptz,
  supersedes text references private.standards_registry(id),
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table private.standard_versions (
  id uuid primary key default gen_random_uuid(),
  standard_id text not null references private.standards_registry(id) on delete cascade,
  edition text not null,
  effective_from date,
  effective_to date,
  rights_verified boolean not null default false,
  allowed_summary text,
  metadata jsonb not null default '{}'::jsonb,
  unique (standard_id, edition)
);

create table private.standard_applicability_rules (
  id uuid primary key default gen_random_uuid(),
  standard_id text not null references private.standards_registry(id) on delete cascade,
  sector_id text,
  module_id text,
  condition_codes text[] not null default '{}',
  item_classes text[] not null default '{}',
  rule jsonb not null default '{}'::jsonb,
  is_active boolean not null default false,
  created_at timestamptz not null default now()
);

create table private.assurance_topics (
  id text primary key,
  topic_family text not null,
  asset_families text[] not null default '{}',
  sectors text[] not null default '{}',
  title_tr text not null,
  description_template_tr text not null,
  control_template_tr text not null,
  applicability_rule jsonb not null default '{}'::jsonb,
  priority integer not null default 50,
  version text not null default 'assurance-topic-v1',
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);

create table private.analysis_item_standard_links (
  item_id uuid not null references private.analysis_items_v4(id) on delete cascade,
  standard_id text not null references private.standards_registry(id),
  standard_version_id uuid references private.standard_versions(id),
  applicability_rule_id uuid references private.standard_applicability_rules(id),
  reference_text text,
  created_at timestamptz not null default now(),
  primary key (item_id, standard_id)
);

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'analysis_v4_configs','analysis_v4_allowlist','analysis_claim_candidates',
    'analysis_items_v4','analysis_routing_ledger','analysis_hard_rejection_ledger',
    'analysis_quality_trace_v4','analysis_targeted_runs_v4','analysis_human_reviews',
    'jurisdiction_profiles','standards_registry','standard_versions',
    'standard_applicability_rules','assurance_topics','analysis_item_standard_links'
  ] loop
    execute format('alter table private.%I enable row level security', v_table);
    execute format('revoke all on table private.%I from public, anon, authenticated', v_table);
    execute format('grant select, insert, update, delete on table private.%I to service_role', v_table);
  end loop;
end $$;

-- The advisor findings were caused by private state tables without RLS. Their
-- only direct grant is service_role; security-definer RPCs remain the access
-- boundary. Enabling RLS therefore closes Data API exposure without changing
-- authenticated-client behavior.
alter table private.analysis_job_state enable row level security;
alter table private.support_request_rate_limits enable row level security;
revoke all on table private.analysis_job_state from public, anon, authenticated;
revoke all on table private.support_request_rate_limits from public, anon, authenticated;
grant select, insert, update, delete on table private.analysis_job_state to service_role;
grant select, insert, update, delete on table private.support_request_rate_limits to service_role;

insert into public.app_feature_flags (key, value)
values ('analysis_engine_v4', jsonb_build_object(
  'rollout_mode', 'off',
  'kill_switch', true,
  'required_api_contract', 3,
  'required_capability', 'safety_claim_v4_scoreless'
)) on conflict (key) do nothing;

insert into private.jurisdiction_profiles (id, country_code, label)
values ('tr-current', 'TR', 'Türkiye güncel profil')
on conflict (id) do nothing;

-- Registry infrastructure is active, but entries stay draft until source,
-- edition, rights and applicability have been verified independently.
insert into private.assurance_topics (
  id, topic_family, asset_families, sectors, title_tr,
  description_template_tr, control_template_tr, applicability_rule, priority
) values
('working_at_height_access', 'access_and_protection', array['scaffold','platform','roof'], array['construction','municipal_public_works'], 'Yüksekte çalışma erişimi ve koruması saha teyidi', 'Görünen çalışma alanında erişim ve koruma düzeninin tüm geometrisi fotoğraftan kesinleştirilemiyor.', 'Erişim, kenar koruması, platform bütünlüğü ve düşen cisim önlemlerini sahada birlikte doğrulayın.', '{"requires_visible_asset":true,"visual_only":false}'::jsonb, 10),
('machine_protective_systems', 'protective_systems', array['machine','production_line'], array['manufacturing_factory','food_production'], 'Makine koruyucu sistemleri saha teyidi', 'Makinenin koruyucu düzeni, kilitlemeleri veya durdurma işlevi görüntüden bütünüyle doğrulanamıyor.', 'Koruyucuları, kilitlemeleri ve acil durdurma işlevini yetkili kişiyle sahada doğrulayın.', '{"requires_visible_asset":true,"visual_only":false}'::jsonb, 15),
('electrical_internal_integrity', 'internal_integrity', array['electrical_panel','transformer','cable_system'], array['energy','manufacturing_factory','office','retail_store','education'], 'Elektriksel iç bütünlük saha teyidi', 'Görünen elektrik ekipmanının iç bağlantıları, koruma düzeni ve test durumu fotoğraftan doğrulanamaz.', 'Yetkili elektrik personeliyle koruma, topraklama ve test kayıtlarını sahada doğrulayın.', '{"requires_visible_asset":true,"visual_only":false}'::jsonb, 20),
('lifting_inspection', 'inspection_and_capacity', array['crane','hoist','forklift','lifting_accessory'], array['construction','warehouse_logistics','mining','municipal_public_works'], 'Kaldırma ekipmanı güvencesi saha teyidi', 'Görünen kaldırma ekipmanının kapasitesi, iç bütünlüğü ve kontrol durumu fotoğraftan belirlenemez.', 'Ekipman kimliği, kapasite, aksesuar uygunluğu ve kontrol kayıtlarını sahada doğrulayın.', '{"requires_visible_asset":true,"visual_only":false}'::jsonb, 20),
('process_containment_integrity', 'process_integrity', array['tank','pressure_vessel','pipework'], array['chemical_laboratory','energy','food_production','manufacturing_factory'], 'Proses bütünlüğü saha teyidi', 'Görünen tank veya borulama sisteminin iç bütünlüğü, proses koşulları ve koruma katmanları görüntüden kesinleştirilemez.', 'İç bütünlük, proses parametreleri, izolasyon ve acil durum düzenini sahada doğrulayın.', '{"requires_visible_asset":true,"visual_only":false}'::jsonb, 15),
('chemical_identity_and_exposure', 'identity_and_measurement', array['chemical_container','laboratory_system'], array['chemical_laboratory','healthcare_hospital','agriculture_livestock','food_production'], 'Kimyasal kimlik ve maruziyet saha teyidi', 'Maddenin kimliği, konsantrasyonu veya maruziyet düzeyi görüntüden güvenilir biçimde belirlenemez.', 'Etiket, güvenlik bilgi formu, proses bilgisi ve gerekli ölçümleri sahada doğrulayın.', '{"requires_visible_asset":true,"visual_only":false}'::jsonb, 25),
('confined_space_controls', 'permit_and_atmosphere', array['confined_space','tank','pit'], array['mining','construction','chemical_laboratory','municipal_public_works'], 'Kapalı alan güvenceleri saha teyidi', 'Atmosfer, izolasyon, kurtarma ve izin düzeni tek görüntüyle doğrulanamaz.', 'Atmosfer ölçümü, enerji izolasyonu, gözcü, iletişim ve kurtarma planını sahada doğrulayın.', '{"requires_visible_asset":true,"visual_only":false}'::jsonb, 10),
('hot_work_controls', 'permit_and_fire_watch', array['hot_work_area','welding_equipment'], array['construction','manufacturing_factory','energy','mining'], 'Sıcak çalışma güvenceleri saha teyidi', 'İzin, gaz ölçümü, yangın gözcüsü ve çalışma sonrası izleme görüntüden doğrulanamaz.', 'Sıcak çalışma izin ve gözetim düzenini, yanıcı kontrolünü ve yangın hazırlığını sahada doğrulayın.', '{"requires_visible_asset":true,"visual_only":false}'::jsonb, 20),
('biosecurity_controls', 'biosecurity', array['clinical_area','laboratory_system','animal_care_area'], array['healthcare_hospital','chemical_laboratory','agriculture_livestock'], 'Biyogüvenlik güvenceleri saha teyidi', 'Maruziyet sınıfı, dekontaminasyon ve prosedürel kontroller fotoğraftan bütünüyle doğrulanamaz.', 'Biyolojik risk sınıfını, dekontaminasyon akışını ve koruyucu prosedürleri sahada doğrulayın.', '{"requires_visible_asset":true,"visual_only":false}'::jsonb, 30),
('fire_emergency_readiness', 'emergency_readiness', array['building','workplace'], array['general','office','retail_store','education','hotel_accommodation','healthcare_hospital'], 'Yangın ve acil durum hazırlığı saha teyidi', 'Tatbikat, bakım, kapasite ve organizasyonel hazırlık tek görüntüden doğrulanamaz.', 'Acil durum planını, bakım kayıtlarını, görevleri ve tahliye düzenini sahada doğrulayın.', '{"requires_visible_asset":true,"visual_only":false}'::jsonb, 40)
on conflict (id) do update set
  asset_families = excluded.asset_families,
  sectors = excluded.sectors,
  title_tr = excluded.title_tr,
  description_template_tr = excluded.description_template_tr,
  control_template_tr = excluded.control_template_tr,
  applicability_rule = excluded.applicability_rule,
  priority = excluded.priority,
  updated_at = now();

create or replace function public.resolve_analysis_engine_route_v5(
  p_user_id uuid,
  p_analysis_id uuid,
  p_compute_routing jsonb default '{}'::jsonb,
  p_client_routing jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_route private.analysis_engine_routes%rowtype;
  v_config private.analysis_v4_configs%rowtype;
  v_flag jsonb := '{}'::jsonb;
  v_allowlisted boolean := false;
  v_client_ok boolean := false;
  v_v4_ok boolean := false;
  v_plan text := 'free';
  v_profile text := 'premium';
  v_pool text := 'paid_standard';
  v_tier text := 'standard';
  v_route_name text;
  v_compute jsonb;
  v_snapshot jsonb;
  v_base jsonb;
  v_fallback_reason text := null;
begin
  select * into v_route from private.analysis_engine_routes
  where analysis_id = p_analysis_id and user_id = p_user_id;
  if found then
    return jsonb_build_object(
      'ok', true, 'state', 'pinned', 'engine', v_route.engine,
      'engine_variant', coalesce(v_route.config_snapshot->>'engine_variant', 'vnext-v3'),
      'rollout_mode', v_route.rollout_mode,
      'config_snapshot', v_route.config_snapshot
    );
  end if;

  select value into v_flag from public.app_feature_flags
  where key = 'analysis_engine_v4';
  select coalesce(enabled, false) into v_allowlisted
  from private.analysis_v4_allowlist where user_id = p_user_id;
  v_allowlisted := coalesce(v_allowlisted, false);

  v_client_ok := coalesce((p_client_routing->>'snapshot_version')::integer, 0) = 1
    and p_client_routing->>'source' = 'trusted_analyze_enqueue'
    and coalesce((p_client_routing->>'api_contract_version')::integer, 0) >= 3
    and coalesce((p_client_routing->>'safety_claim_v4_scoreless')::boolean, false);

  select * into v_config from private.analysis_v4_configs
  where is_active and integrity_status = 'valid'
  order by updated_at desc limit 1;

  v_v4_ok := coalesce(v_flag->>'rollout_mode', 'off') = 'user_allowlist'
    and not coalesce((v_flag->>'kill_switch')::boolean, true)
    and v_allowlisted and v_client_ok and found
    and v_config.engine_version = 'vnext-v4'
    and v_config.provider_contract_version = 'visual-claim-candidate-v1'
    and v_config.domain_schema_version = 'safety-claim-v4.0'
    and v_config.prompt_version = 'v4-vision-core-v1'
    and v_config.router_version = 'claim-routing-v1'
    and v_config.prompt_sha256 ~ '^[a-f0-9]{64}$';

  if v_v4_ok then
    select coalesce(a.plan_at_creation::text, 'free') into v_plan
    from public.analyses a where a.id = p_analysis_id and a.user_id = p_user_id;
    v_route_name := nullif(p_compute_routing->>'ai_execution_route', '');
    if coalesce((p_compute_routing->>'snapshot_version')::integer, 0) <> 1
      or p_compute_routing->>'source' <> 'trusted_analyze_enqueue'
      or v_route_name not in ('free_legacy','free_paid_trial','paid_plan','cancelled_plus_trial_free')
    then
      v_route_name := 'compute_route_snapshot_missing';
    elsif v_route_name in ('free_legacy','cancelled_plus_trial_free') then
      v_profile := 'economy';
    end if;
    if v_profile = 'economy' and coalesce((v_config.config->>'paid_flex_enabled')::boolean, false) then
      v_pool := 'paid_flex'; v_tier := 'flex';
    end if;
    v_compute := jsonb_build_object(
      'snapshot_version', 1,
      'ai_execution_route', v_route_name,
      'compute_profile', v_profile,
      'compute_profile_version', coalesce(v_config.config->>'compute_profile_version', 'compute-profile-v1'),
      'provider_pool', v_pool,
      'requested_service_tier', v_tier,
      'product_plan', v_plan,
      'source', 'trusted_analyze_enqueue'
    );
    v_snapshot := jsonb_build_object(
      'engine_variant', 'vnext-v4',
      'engine_config', v_config.config || jsonb_build_object(
        'engine_version', v_config.engine_version,
        'schema_version', v_config.domain_schema_version,
        'provider_contract_version', v_config.provider_contract_version,
        'prompt_version', v_config.prompt_version,
        'prompt_sha256', v_config.prompt_sha256,
        'policy_version', v_config.router_version,
        'coverage_version', v_config.coverage_version,
        'assurance_version', v_config.assurance_version,
        'standards_version', v_config.standards_version,
        'quality_trace_version', v_config.quality_trace_version,
        'report_projection_version', v_config.report_projection_version
      ),
      'compute_routing', v_compute,
      'client_routing', p_client_routing
    );
    insert into private.analysis_engine_routes (
      analysis_id, user_id, engine, rollout_mode, config_snapshot
    ) values (p_analysis_id, p_user_id, 'vnext', 'user_allowlist', v_snapshot)
    on conflict (analysis_id) do nothing;
    select * into v_route from private.analysis_engine_routes
    where analysis_id = p_analysis_id and user_id = p_user_id;
    return jsonb_build_object(
      'ok', true, 'state', 'resolved', 'engine', v_route.engine,
      'engine_variant', coalesce(v_route.config_snapshot->>'engine_variant', 'vnext-v3'),
      'rollout_mode', v_route.rollout_mode,
      'config_snapshot', v_route.config_snapshot
    );
  end if;

  v_fallback_reason := case
    when coalesce(v_flag->>'rollout_mode', 'off') <> 'user_allowlist' then 'v4_rollout_off'
    when coalesce((v_flag->>'kill_switch')::boolean, true) then 'v4_kill_switch'
    when not v_allowlisted then 'v4_user_not_allowlisted'
    when not v_client_ok then 'v4_client_incompatible'
    when v_config.id is null then 'v4_config_missing_or_invalid'
    else 'v4_integrity_mismatch'
  end;
  v_base := public.resolve_analysis_engine_route_v4(p_user_id, p_analysis_id, p_compute_routing);
  update private.analysis_engine_routes
  set config_snapshot = jsonb_set(config_snapshot, '{v4_fallback_reason}', to_jsonb(v_fallback_reason), true)
  where analysis_id = p_analysis_id and user_id = p_user_id;
  return v_base || jsonb_build_object('v4_fallback_reason', v_fallback_reason);
exception when others then
  return jsonb_build_object('ok', false, 'state', 'v4_route_resolution_failed');
end;
$$;

create or replace function public.begin_analysis_engine_run_v4(
  p_user_id uuid,
  p_analysis_id uuid,
  p_msg_id bigint,
  p_generation integer,
  p_claim_token uuid,
  p_job_mode text default 'analysis'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state private.analysis_job_state%rowtype;
  v_route private.analysis_engine_routes%rowtype;
  v_run private.analysis_engine_runs%rowtype;
  v_engine jsonb;
  v_photo_runs jsonb;
begin
  select * into v_state from private.analysis_job_state
  where analysis_id = p_analysis_id and user_id = p_user_id;
  if not found or v_state.active_msg_id is distinct from p_msg_id
    or v_state.generation is distinct from p_generation
    or v_state.claim_token is distinct from p_claim_token then
    return jsonb_build_object('ok', false, 'state', 'lost_claim');
  end if;
  select * into v_route from private.analysis_engine_routes
  where analysis_id = p_analysis_id and user_id = p_user_id;
  if not found or v_route.engine <> 'vnext'
    or v_route.config_snapshot->>'engine_variant' <> 'vnext-v4' then
    return jsonb_build_object('ok', false, 'state', 'route_not_v4');
  end if;
  v_engine := v_route.config_snapshot->'engine_config';
  if coalesce(v_engine->>'engine_version','') <> 'vnext-v4'
    or coalesce(v_engine->>'prompt_version','') <> 'v4-vision-core-v1'
    or coalesce(v_engine->>'prompt_sha256','') !~ '^[a-f0-9]{64}$' then
    return jsonb_build_object('ok', false, 'state', 'v4_snapshot_invalid');
  end if;

  insert into private.analysis_engine_runs (
    analysis_id,user_id,queue_msg_id,job_generation,job_mode,
    engine_version,schema_version,prompt_version,policy_version,
    control_catalog_version,visual_input_mode,provider,model,status,config_snapshot
  ) values (
    p_analysis_id,p_user_id,p_msg_id,p_generation,
    case when p_job_mode='repair' then 'repair' else 'analysis' end,
    'vnext-v4','safety-claim-v4.0','v4-vision-core-v1','claim-routing-v1',
    'controls-v19',coalesce(v_engine->>'visual_input_mode','native_per_photo'),
    'gemini',coalesce(v_engine->>'primary_model','gemini-2.5-flash'),'running',v_route.config_snapshot
  ) on conflict (analysis_id,job_generation,job_mode) do update set
    queue_msg_id=excluded.queue_msg_id,
    status=case when private.analysis_engine_runs.status='completed' then 'completed' else 'running' end,
    error_code=case when private.analysis_engine_runs.status='completed' then private.analysis_engine_runs.error_code else null end,
    completed_at=case when private.analysis_engine_runs.status='completed' then private.analysis_engine_runs.completed_at else null end,
    updated_at=now()
  returning * into v_run;

  update private.analysis_provider_attempts set state='ambiguous',
    error_code='ambiguous_provider_attempt',updated_at=now()
  where engine_run_id=v_run.id and state='received';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,'photo_id',p.photo_id,'photo_index',p.photo_index,
    'storage_path',p.storage_path,'status',p.status,'provider',p.provider,
    'model',p.model,'attempt_count',p.attempt_count,
    'normalized_output',p.normalized_output,'input_tokens',p.input_tokens,
    'output_tokens',p.output_tokens,'reasoning_tokens',p.reasoning_tokens,
    'cost_usd',p.cost_usd,'duration_ms',p.duration_ms,'error_code',p.error_code
  ) order by p.photo_index),'[]'::jsonb) into v_photo_runs
  from private.analysis_photo_runs p where p.engine_run_id=v_run.id;

  return jsonb_build_object(
    'ok',true,'state',case when v_run.status='completed' then 'completed' else 'running' end,
    'engine_run_id',v_run.id,'engine_version',v_run.engine_version,
    'schema_version',v_run.schema_version,'prompt_version',v_run.prompt_version,
    'policy_version',v_run.policy_version,'provider',v_run.provider,'model',v_run.model,
    'config_snapshot',v_run.config_snapshot,'photo_runs',v_photo_runs
  );
end;
$$;

create or replace function public.finalize_analysis_result_v4(
  p_user_id uuid,
  p_analysis_id uuid,
  p_msg_id bigint,
  p_generation integer,
  p_claim_token uuid,
  p_engine_run_id uuid,
  p_bundle jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_analysis public.analyses%rowtype;
  v_state private.analysis_job_state%rowtype;
  v_run private.analysis_engine_runs%rowtype;
  v_entry jsonb;
  v_candidate_id uuid;
  v_item_id uuid;
  v_public_id uuid;
  v_source_indices integer[];
  v_visible_count integer := 0;
  v_scored_count integer := 0;
  v_total_fk numeric := 0;
  v_total_m5 integer := 0;
  v_highest_fk public.risk_level := 'unknown';
  v_highest_m5 public.risk_level := 'unknown';
  v_total_requests integer := 0;
  v_total_input bigint := 0;
  v_total_output bigint := 0;
  v_total_reasoning bigint := 0;
  v_total_cost numeric := 0;
  v_unrouted_critical integer := 0;
begin
  select * into v_analysis from public.analyses
  where id=p_analysis_id and user_id=p_user_id for update;
  if not found then return jsonb_build_object('ok',false,'state','analysis_not_found'); end if;
  if v_analysis.status::text='completed' then
    return jsonb_build_object('ok',true,'state','already_completed','finding_count',v_analysis.finding_count);
  end if;
  select * into v_state from private.analysis_job_state
  where analysis_id=p_analysis_id and user_id=p_user_id for update;
  if not found or v_state.active_msg_id is distinct from p_msg_id
    or v_state.generation is distinct from p_generation
    or v_state.claim_token is distinct from p_claim_token then
    return jsonb_build_object('ok',false,'state','lost_claim');
  end if;
  select * into v_run from private.analysis_engine_runs
  where id=p_engine_run_id and analysis_id=p_analysis_id and user_id=p_user_id for update;
  if not found or v_run.engine_version <> 'vnext-v4' or v_run.status <> 'running' then
    return jsonb_build_object('ok',false,'state','engine_run_not_running');
  end if;

  -- Reject any bundle that would silently lose a critical candidate.
  select count(*) into v_unrouted_critical
  from jsonb_array_elements(coalesce(p_bundle->'candidates','[]'::jsonb)) c
  where c->>'criticality' in ('fatal','permanent')
    and not exists (
      select 1 from jsonb_array_elements(coalesce(p_bundle->'items','[]'::jsonb)) i
      where i->>'candidate_id'=c->>'id'
    )
    and not exists (
      select 1 from jsonb_array_elements(coalesce(p_bundle->'hard_rejections','[]'::jsonb)) h
      where h->>'candidate_id'=c->>'id' and nullif(h->>'reason_code','') is not null
    );
  if v_unrouted_critical > 0 then
    return jsonb_build_object('ok',false,'state','critical_candidate_unrouted','count',v_unrouted_critical);
  end if;

  delete from private.analysis_item_standard_links where item_id in (
    select id from private.analysis_items_v4 where engine_run_id=p_engine_run_id
  );
  delete from private.analysis_items_v4 where engine_run_id=p_engine_run_id;
  delete from private.analysis_routing_ledger where engine_run_id=p_engine_run_id;
  delete from private.analysis_hard_rejection_ledger where engine_run_id=p_engine_run_id;
  delete from private.analysis_claim_candidates where engine_run_id=p_engine_run_id;
  delete from public.findings where analysis_id=p_analysis_id and user_id=p_user_id and origin='ai';

  for v_entry in select value from jsonb_array_elements(coalesce(p_bundle->'candidates','[]'::jsonb)) loop
    v_candidate_id := (v_entry->>'id')::uuid;
    insert into private.analysis_claim_candidates (
      id,engine_run_id,analysis_id,user_id,photo_index,candidate_key,module_id,
      raw_label,normalized_condition_code,evidence_level,criticality,evidence_region,
      affirmative_cues,counter_cues,event_path,resolvability,normalized_payload
    ) values (
      v_candidate_id,p_engine_run_id,p_analysis_id,p_user_id,(v_entry->>'photo_index')::integer,
      left(v_entry->>'candidate_key',200),left(v_entry->>'module_id',120),left(v_entry->>'raw_label',500),
      left(v_entry->>'condition_code',160),v_entry->>'evidence_level',
      coalesce(v_entry->>'criticality','ordinary'),v_entry->'evidence_region',
      coalesce(v_entry->'affirmative_cues','[]'::jsonb),coalesce(v_entry->'counter_cues','[]'::jsonb),
      coalesce(v_entry->'event_path','{}'::jsonb),coalesce(v_entry->'resolvability','{}'::jsonb),v_entry
    );
  end loop;

  for v_entry in select value from jsonb_array_elements(coalesce(p_bundle->'routing_ledger','[]'::jsonb)) loop
    insert into private.analysis_routing_ledger (
      engine_run_id,analysis_id,candidate_id,from_state,to_state,reason_code,evidence_level,details
    ) values (
      p_engine_run_id,p_analysis_id,nullif(v_entry->>'candidate_id','')::uuid,
      left(coalesce(v_entry->>'from_state','candidate'),80),left(v_entry->>'to_state',80),
      left(v_entry->>'reason_code',160),left(v_entry->>'evidence_level',4),
      coalesce(v_entry->'details','{}'::jsonb)
    );
  end loop;
  for v_entry in select value from jsonb_array_elements(coalesce(p_bundle->'hard_rejections','[]'::jsonb)) loop
    insert into private.analysis_hard_rejection_ledger (
      engine_run_id,analysis_id,candidate_id,reason_code,criticality,evidence_snapshot
    ) values (
      p_engine_run_id,p_analysis_id,nullif(v_entry->>'candidate_id','')::uuid,
      left(v_entry->>'reason_code',160),coalesce(v_entry->>'criticality','ordinary'),
      coalesce(v_entry->'evidence_snapshot','{}'::jsonb)
    );
  end loop;

  for v_entry in select value from jsonb_array_elements(coalesce(p_bundle->'items','[]'::jsonb))
    order by (value->>'display_order')::integer
  loop
    v_item_id := (v_entry->>'id')::uuid;
    select coalesce(array_agg(value::integer),'{}'::integer[]) into v_source_indices
    from jsonb_array_elements_text(coalesce(v_entry->'source_photo_indices','[]'::jsonb));
    v_public_id := null;
    if v_entry->>'item_class' in ('observed_finding','assurance_requirement','verification_request') then
      insert into public.findings (
        analysis_id,user_id,ordinal,title,category,description,recommended_action,
        recommended_measures,references_text,root_cause_text,confidence,
        needs_field_verification,origin,ai_original_snapshot,source_photo_indices,
        source_photo_observations,finding_budget_policy,ai_confidence,
        fk_probability,fk_frequency,fk_severity,fk_band,
        m5_probability,m5_severity,m5_band,display_group,display_order,item_class,is_scored
      ) values (
        p_analysis_id,p_user_id,(v_entry->>'ordinal')::integer,v_entry->>'title',v_entry->>'category',
        v_entry->>'description',v_entry->>'recommended_action',coalesce(v_entry->'recommended_measures','[]'::jsonb),
        nullif(v_entry->>'references_text',''),nullif(v_entry->>'root_cause_text',''),
        coalesce((v_entry->>'confidence')::numeric,0),
        case when v_entry->>'item_class'='observed_finding' then coalesce((v_entry->>'needs_field_verification')::boolean,false) else true end,
        'ai',v_entry,v_source_indices,v_entry->'source_photo_observations',v_entry->'finding_budget_policy',
        nullif(v_entry->>'ai_confidence','')::numeric,
        case when (v_entry->>'is_scored')::boolean then (v_entry->>'fk_probability')::numeric else null end,
        case when (v_entry->>'is_scored')::boolean then (v_entry->>'fk_frequency')::numeric else null end,
        case when (v_entry->>'is_scored')::boolean then (v_entry->>'fk_severity')::numeric else null end,
        case when (v_entry->>'is_scored')::boolean then (v_entry->>'fk_band')::public.risk_level else 'unknown'::public.risk_level end,
        case when (v_entry->>'is_scored')::boolean then (v_entry->>'m5_probability')::integer else null end,
        case when (v_entry->>'is_scored')::boolean then (v_entry->>'m5_severity')::integer else null end,
        case when (v_entry->>'is_scored')::boolean then (v_entry->>'m5_band')::public.risk_level else 'unknown'::public.risk_level end,
        v_entry->>'display_group',(v_entry->>'display_order')::integer,
        v_entry->>'item_class',(v_entry->>'is_scored')::boolean
      ) returning id into v_public_id;
      v_visible_count := v_visible_count + 1;
    end if;
    insert into private.analysis_items_v4 (
      id,engine_run_id,analysis_id,user_id,candidate_id,public_finding_id,item_class,
      is_scored,criticality,title,description,control_text,root_cause_text,references_text,
      needs_field_verification,source_photo_indices,display_order,score_payload,internal_priority,canonical_payload
    ) values (
      v_item_id,p_engine_run_id,p_analysis_id,p_user_id,nullif(v_entry->>'candidate_id','')::uuid,v_public_id,
      v_entry->>'item_class',(v_entry->>'is_scored')::boolean,coalesce(v_entry->>'criticality','ordinary'),
      v_entry->>'title',v_entry->>'description',v_entry->>'recommended_action',nullif(v_entry->>'root_cause_text',''),
      nullif(v_entry->>'references_text',''),coalesce((v_entry->>'needs_field_verification')::boolean,false),
      v_source_indices,(v_entry->>'display_order')::integer,v_entry->'score_payload',
      coalesce(v_entry->'internal_priority','{}'::jsonb),v_entry
    );
  end loop;

  select count(*)::integer,coalesce(sum(fk_score),0),coalesce(sum(m5_score),0)::integer
    into v_scored_count,v_total_fk,v_total_m5
  from public.findings where analysis_id=p_analysis_id and user_id=p_user_id
    and is_scored and coalesce(is_user_deleted,false)=false;
  select coalesce((array_agg(fk_band order by case fk_band::text when 'critical' then 4 when 'high' then 3 when 'medium' then 2 when 'low' then 1 else 0 end desc))[1],'unknown'::public.risk_level),
    coalesce((array_agg(m5_band order by case m5_band::text when 'critical' then 4 when 'high' then 3 when 'medium' then 2 when 'low' then 1 else 0 end desc))[1],'unknown'::public.risk_level)
    into v_highest_fk,v_highest_m5
  from public.findings where analysis_id=p_analysis_id and user_id=p_user_id and is_scored;

  insert into private.analysis_quality_trace_v4 (
    engine_run_id,analysis_id,user_id,prompt_sha256,version_snapshot,photo_coverage_matrix,
    candidate_counts,routing_counts,critical_silent_drop_count,targeted_queue,
    standards_trace,provider_usage,quality_flags,trace
  ) values (
    p_engine_run_id,p_analysis_id,p_user_id,
    coalesce(p_bundle#>>'{quality_trace,prompt_sha256}',v_run.config_snapshot#>>'{engine_config,prompt_sha256}'),
    coalesce(p_bundle#>'{quality_trace,version_snapshot}','{}'::jsonb),
    coalesce(p_bundle#>'{quality_trace,photo_coverage_matrix}','[]'::jsonb),
    coalesce(p_bundle#>'{quality_trace,candidate_counts}','{}'::jsonb),
    coalesce(p_bundle#>'{quality_trace,routing_counts}','{}'::jsonb),0,
    coalesce(p_bundle#>'{quality_trace,targeted_queue}','{}'::jsonb),
    coalesce(p_bundle#>'{quality_trace,standards_trace}','{}'::jsonb),
    coalesce(p_bundle#>'{quality_trace,provider_usage}','{}'::jsonb),
    array(select jsonb_array_elements_text(coalesce(p_bundle#>'{quality_trace,quality_flags}','[]'::jsonb))),
    coalesce(p_bundle->'quality_trace','{}'::jsonb)
  ) on conflict (engine_run_id) do update set
    photo_coverage_matrix=excluded.photo_coverage_matrix,candidate_counts=excluded.candidate_counts,
    routing_counts=excluded.routing_counts,critical_silent_drop_count=0,targeted_queue=excluded.targeted_queue,
    standards_trace=excluded.standards_trace,provider_usage=excluded.provider_usage,
    quality_flags=excluded.quality_flags,trace=excluded.trace;

  update public.analyses set status='completed',
    status_message=coalesce(p_bundle#>>'{analysis_result,status_message}','Analiz tamamlandı.'),
    completed_at=now(),ai_summary=p_bundle#>>'{analysis_result,ai_summary}',
    total_score_fk=v_total_fk,total_score_m5=v_total_m5,
    highest_band_fk=v_highest_fk,highest_band_m5=v_highest_m5,
    finding_count=v_visible_count,generated_findings_count=v_visible_count,
    visible_findings_count=v_visible_count,
    hidden_or_rejected_findings_count=jsonb_array_length(coalesce(p_bundle->'hard_rejections','[]'::jsonb)),
    raw_ai_response=jsonb_build_object(
      '_engine','vnext-v4','_quality_trace_version','quality-trace-v4',
      '_summary',coalesce(p_bundle->'analysis_result','{}'::jsonb)
    ),ai_models_used=array[v_run.model],last_worker_error=null,failure_category=null,failure_code=null
  where id=p_analysis_id and user_id=p_user_id;

  update public.usage_events set event_type='completed'
  where user_id=p_user_id and source_id=p_analysis_id
    and feature in ('analysis_standard','analysis_detailed') and event_type='reserved';
  update private.analysis_job_state set claim_token=null,claimed_at=null,lease_expires_at=null,updated_at=now()
  where analysis_id=p_analysis_id;
  select count(*),coalesce(sum(input_tokens),0),coalesce(sum(output_tokens),0),
    coalesce(sum(reasoning_tokens),0),coalesce(sum(cost_usd),0)
  into v_total_requests,v_total_input,v_total_output,v_total_reasoning,v_total_cost
  from private.analysis_provider_attempts where engine_run_id=p_engine_run_id;
  update private.analysis_engine_runs set status='completed',total_provider_requests=v_total_requests,
    total_input_tokens=v_total_input,total_output_tokens=v_total_output,
    total_reasoning_tokens=v_total_reasoning,total_cost_usd=v_total_cost,
    duration_ms=floor(extract(epoch from (now()-started_at))*1000)::bigint,
    completed_at=now(),error_code=null,updated_at=now()
  where id=p_engine_run_id;
  return jsonb_build_object('ok',true,'state','completed','engine','vnext-v4',
    'engine_run_id',p_engine_run_id,'finding_count',v_visible_count,
    'scored_finding_count',v_scored_count,'provider_requests',v_total_requests,
    'provider_cost_usd',v_total_cost);
end;
$$;

create or replace function public.checkpoint_analysis_targeted_run_v4(
  p_user_id uuid,
  p_engine_run_id uuid,
  p_region_key text,
  p_candidate_ids uuid[],
  p_photo_index integer,
  p_status text,
  p_provider_attempt_id uuid default null,
  p_result jsonb default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_run private.analysis_engine_runs%rowtype; v_id uuid;
begin
  select * into v_run from private.analysis_engine_runs
  where id=p_engine_run_id and user_id=p_user_id;
  if not found or v_run.engine_version <> 'vnext-v4' then
    return jsonb_build_object('ok',false,'state','engine_run_not_v4');
  end if;
  insert into private.analysis_targeted_runs_v4 (
    engine_run_id,analysis_id,user_id,region_key,candidate_ids,photo_index,
    status,provider_attempt_id,result
  ) values (
    p_engine_run_id,v_run.analysis_id,p_user_id,left(p_region_key,240),
    coalesce(p_candidate_ids,'{}'::uuid[]),p_photo_index,
    case when p_status in ('queued','running','completed','failed','budget_excluded') then p_status else 'failed' end,
    p_provider_attempt_id,p_result
  ) on conflict (engine_run_id,region_key) do update set
    candidate_ids=excluded.candidate_ids,photo_index=excluded.photo_index,
    status=excluded.status,provider_attempt_id=excluded.provider_attempt_id,
    result=excluded.result,updated_at=now()
  returning id into v_id;
  return jsonb_build_object('ok',true,'state','checkpointed','targeted_run_id',v_id);
end $$;

create or replace function public.recalc_analysis_rollup(p_analysis_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_user_id uuid; v_count integer; v_total_fk numeric; v_total_m5 integer;
  v_highest_fk text; v_highest_m5 text;
begin
  if p_analysis_id is null then return; end if;
  select user_id into v_user_id from public.analyses where id=p_analysis_id;
  if v_user_id is null then return; end if;
  select count(*)::integer,
    coalesce(sum(fk_score) filter (where is_scored),0),
    coalesce(sum(m5_score) filter (where is_scored),0)::integer,
    coalesce((array_agg(fk_band::text order by case fk_band::text when 'critical' then 4 when 'high' then 3 when 'medium' then 2 when 'low' then 1 else 0 end desc) filter (where is_scored))[1],'unknown'),
    coalesce((array_agg(m5_band::text order by case m5_band::text when 'critical' then 4 when 'high' then 3 when 'medium' then 2 when 'low' then 1 else 0 end desc) filter (where is_scored))[1],'unknown')
  into v_count,v_total_fk,v_total_m5,v_highest_fk,v_highest_m5
  from public.findings where analysis_id=p_analysis_id
    and coalesce(is_user_deleted,false)=false and coalesce(report_visibility,'visible')='visible';
  update public.analyses set finding_count=v_count,
    generated_findings_count=greatest(generated_findings_count,v_count),visible_findings_count=v_count,
    total_score_fk=v_total_fk,total_score_m5=v_total_m5,
    highest_band_fk=nullif(v_highest_fk,'unknown')::public.risk_level,
    highest_band_m5=nullif(v_highest_m5,'unknown')::public.risk_level,updated_at=now()
  where id=p_analysis_id;
end $$;

revoke all on function public.resolve_analysis_engine_route_v5(uuid,uuid,jsonb,jsonb) from public,anon,authenticated;
revoke all on function public.begin_analysis_engine_run_v4(uuid,uuid,bigint,integer,uuid,text) from public,anon,authenticated;
revoke all on function public.finalize_analysis_result_v4(uuid,uuid,bigint,integer,uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.checkpoint_analysis_targeted_run_v4(uuid,uuid,text,uuid[],integer,text,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.recalc_analysis_rollup(uuid) from public,anon,authenticated;
grant execute on function public.resolve_analysis_engine_route_v5(uuid,uuid,jsonb,jsonb) to service_role;
grant execute on function public.begin_analysis_engine_run_v4(uuid,uuid,bigint,integer,uuid,text) to service_role;
grant execute on function public.finalize_analysis_result_v4(uuid,uuid,bigint,integer,uuid,uuid,jsonb) to service_role;
grant execute on function public.checkpoint_analysis_targeted_run_v4(uuid,uuid,text,uuid[],integer,text,uuid,jsonb) to service_role;
grant execute on function public.recalc_analysis_rollup(uuid) to service_role;
grant usage, select on all sequences in schema private to service_role;

-- Professional Progress must receive only scored observations. Preserve the
-- existing economy-v2 function byte-for-byte apart from its finding scope so
-- the v3 reward policy and thresholds cannot drift in this migration.
do $$
declare v_definition text; v_updated text;
begin
  select pg_get_functiondef('private.pp_process_analysis_completed()'::regprocedure)
  into v_definition;
  v_updated := regexp_replace(
    v_definition,
    '(where\s+f\.analysis_id\s*=\s*new\.id\s+and\s+f\.user_id\s*=\s*new\.user_id)',
    '\1 and coalesce(f.is_scored, true)',
    'i'
  );
  if v_updated = v_definition then
    raise exception 'pp_process_analysis_completed scored filter patch did not match';
  end if;
  execute v_updated;
end $$;

comment on table private.analysis_items_v4 is
  'Canonical v4 items. Public findings is only the backward-compatible visible projection.';
comment on column public.findings.is_scored is
  'False for v4 assurance/verification cards; P/F/S and generated scores remain null.';
