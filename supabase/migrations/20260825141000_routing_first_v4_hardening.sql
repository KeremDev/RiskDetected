-- Routing-first v4 hardening: deterministic assurance coverage, indexed
-- ledgers, authoritative usage trace and owner-only pilot diagnostics.

create index if not exists analysis_claim_candidates_analysis_idx
  on private.analysis_claim_candidates(analysis_id);
create index if not exists analysis_claim_candidates_user_idx
  on private.analysis_claim_candidates(user_id);
create index if not exists analysis_items_v4_engine_run_idx
  on private.analysis_items_v4(engine_run_id);
create index if not exists analysis_items_v4_candidate_idx
  on private.analysis_items_v4(candidate_id) where candidate_id is not null;
create index if not exists analysis_items_v4_public_finding_idx
  on private.analysis_items_v4(public_finding_id) where public_finding_id is not null;
create index if not exists analysis_items_v4_user_idx
  on private.analysis_items_v4(user_id);
create index if not exists analysis_routing_ledger_engine_run_idx
  on private.analysis_routing_ledger(engine_run_id);
create index if not exists analysis_routing_ledger_analysis_idx
  on private.analysis_routing_ledger(analysis_id);
create index if not exists analysis_routing_ledger_candidate_idx
  on private.analysis_routing_ledger(candidate_id) where candidate_id is not null;
create index if not exists analysis_hard_rejection_engine_run_idx
  on private.analysis_hard_rejection_ledger(engine_run_id);
create index if not exists analysis_hard_rejection_analysis_idx
  on private.analysis_hard_rejection_ledger(analysis_id);
create index if not exists analysis_hard_rejection_candidate_idx
  on private.analysis_hard_rejection_ledger(candidate_id);
create index if not exists analysis_quality_trace_v4_analysis_idx
  on private.analysis_quality_trace_v4(analysis_id);
create index if not exists analysis_quality_trace_v4_user_idx
  on private.analysis_quality_trace_v4(user_id);
create index if not exists analysis_targeted_runs_v4_analysis_idx
  on private.analysis_targeted_runs_v4(analysis_id);
create index if not exists analysis_targeted_runs_v4_user_idx
  on private.analysis_targeted_runs_v4(user_id);
create index if not exists analysis_targeted_runs_v4_attempt_idx
  on private.analysis_targeted_runs_v4(provider_attempt_id)
  where provider_attempt_id is not null;
create index if not exists analysis_human_reviews_run_idx
  on private.analysis_human_reviews(engine_run_id);
create index if not exists analysis_human_reviews_analysis_idx
  on private.analysis_human_reviews(analysis_id);
create index if not exists analysis_human_reviews_candidate_idx
  on private.analysis_human_reviews(candidate_id) where candidate_id is not null;
create index if not exists analysis_human_reviews_item_idx
  on private.analysis_human_reviews(item_id) where item_id is not null;
create index if not exists analysis_human_reviews_reviewer_idx
  on private.analysis_human_reviews(reviewer_user_id);
create index if not exists standards_registry_jurisdiction_idx
  on private.standards_registry(jurisdiction_profile_id);
create index if not exists standards_registry_supersedes_idx
  on private.standards_registry(supersedes) where supersedes is not null;
create index if not exists analysis_item_standard_links_standard_idx
  on private.analysis_item_standard_links(standard_id);
create index if not exists analysis_item_standard_links_version_idx
  on private.analysis_item_standard_links(standard_version_id);
create index if not exists analysis_item_standard_links_rule_idx
  on private.analysis_item_standard_links(applicability_rule_id)
  where applicability_rule_id is not null;

-- The topic catalogue spans every canonical sector id. It remains metadata
-- only: a topic is emitted only when a visible asset is present and the
-- provider explicitly marks the question as non-visual assurance.
update private.assurance_topics set sectors = case id
  when 'working_at_height_access' then array[
    'construction','mining','energy','municipal_field_services','hospitality'
  ]
  when 'machine_protective_systems' then array[
    'manufacturing','mining','food_production','agriculture_livestock'
  ]
  when 'electrical_internal_integrity' then array[
    'general','construction','manufacturing','mining','energy','office',
    'logistics_warehouse','chemical_laboratory','healthcare','food_production',
    'agriculture_livestock','retail','municipal_field_services','education','hospitality'
  ]
  when 'lifting_inspection' then array[
    'construction','manufacturing','mining','logistics_warehouse',
    'agriculture_livestock','municipal_field_services'
  ]
  when 'process_containment_integrity' then array[
    'manufacturing','mining','energy','chemical_laboratory','food_production'
  ]
  when 'chemical_identity_and_exposure' then array[
    'manufacturing','mining','chemical_laboratory','healthcare',
    'food_production','agriculture_livestock','education','hospitality'
  ]
  when 'confined_space_controls' then array[
    'construction','mining','energy','chemical_laboratory',
    'agriculture_livestock','municipal_field_services'
  ]
  when 'hot_work_controls' then array[
    'construction','manufacturing','mining','energy','chemical_laboratory',
    'municipal_field_services'
  ]
  when 'biosecurity_controls' then array[
    'chemical_laboratory','healthcare','food_production',
    'agriculture_livestock','education','hospitality'
  ]
  when 'fire_emergency_readiness' then array[
    'general','construction','manufacturing','mining','energy','office',
    'logistics_warehouse','chemical_laboratory','healthcare','food_production',
    'agriculture_livestock','retail','municipal_field_services','education','hospitality'
  ]
  else sectors
end, updated_at = now()
where id in (
  'working_at_height_access','machine_protective_systems',
  'electrical_internal_integrity','lifting_inspection',
  'process_containment_integrity','chemical_identity_and_exposure',
  'confined_space_controls','hot_work_controls','biosecurity_controls',
  'fire_emergency_readiness'
);

insert into private.assurance_topics (
  id,topic_family,asset_families,sectors,title_tr,description_template_tr,
  control_template_tr,applicability_rule,priority
) values
(
  'mobile_equipment_controls','mobile_equipment',
  array['forklift','truck','mobile_equipment','agricultural_vehicle'],
  array['construction','manufacturing','mining','logistics_warehouse',
        'agriculture_livestock','retail','municipal_field_services'],
  'Hareketli ekipman güvenceleri saha teyidi',
  'Görünen hareketli ekipmanın kapasitesi, kör nokta kontrolleri, bakım ve yetkilendirme durumu fotoğraftan kesinleştirilemez.',
  'Ekipman kimliğini, çalışma sınırlarını, bakım durumunu ve yaya–araç yönetimini sahada doğrulayın.',
  '{"requires_visible_asset":true,"visual_only":false}'::jsonb,20
),
(
  'excavation_stability_controls','ground_and_excavation',
  array['excavation','trench','pit','underground_face'],
  array['construction','mining','energy','municipal_field_services'],
  'Kazı ve zemin stabilitesi saha teyidi',
  'Zemin özellikleri, iksa yeterliliği, yeraltı hizmetleri ve stabilite hesabı tek görüntüyle doğrulanamaz.',
  'Zemin, iksa, yaklaşma mesafeleri, yeraltı hizmetleri ve yetkili kontrolü sahada doğrulayın.',
  '{"requires_visible_asset":true,"visual_only":false}'::jsonb,10
),
(
  'combustible_dust_controls','combustible_dust',
  array['dust_process','silo','mill','production_line'],
  array['manufacturing','mining','food_production','agriculture_livestock'],
  'Yanıcı toz güvenceleri saha teyidi',
  'Tozun patlayıcılık özellikleri, konsantrasyonu, zon sınıflandırması ve koruma performansı fotoğraftan belirlenemez.',
  'Malzeme özelliklerini, toz kontrolünü, tutuşturucu kaynakları ve patlamadan korunma düzenini sahada doğrulayın.',
  '{"requires_visible_asset":true,"visual_only":false}'::jsonb,15
),
(
  'energy_isolation_controls','hazardous_energy',
  array['machine','electrical_system','process_system','stored_energy'],
  array['construction','manufacturing','mining','energy','logistics_warehouse',
        'chemical_laboratory','healthcare','food_production',
        'agriculture_livestock','municipal_field_services'],
  'Tehlikeli enerji izolasyonu saha teyidi',
  'İzolasyon noktaları, birikmiş enerji ve yeniden enerjilenmeyi önleyen prosedürel güvenceler görüntüden bütünüyle doğrulanamaz.',
  'Tüm enerji kaynaklarını, izolasyon noktalarını, kilitleme düzenini ve sıfır enerji doğrulamasını sahada kontrol edin.',
  '{"requires_visible_asset":true,"visual_only":false}'::jsonb,15
)
on conflict (id) do update set
  topic_family=excluded.topic_family,
  asset_families=excluded.asset_families,
  sectors=excluded.sectors,
  title_tr=excluded.title_tr,
  description_template_tr=excluded.description_template_tr,
  control_template_tr=excluded.control_template_tr,
  applicability_rule=excluded.applicability_rule,
  priority=excluded.priority,
  updated_at=now();

create or replace function private.sync_v4_authoritative_usage_trace()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.engine_version = 'vnext-v4' and new.status = 'completed' then
    update private.analysis_quality_trace_v4
    set provider_usage = coalesce(provider_usage,'{}'::jsonb) || jsonb_build_object(
      'provider_requests',new.total_provider_requests,
      'input_tokens',new.total_input_tokens,
      'visible_output_tokens',new.total_output_tokens,
      'thinking_tokens',new.total_reasoning_tokens,
      'cost_usd',new.total_cost_usd,
      'standard_equivalent_cost_usd',new.total_standard_equivalent_cost_usd,
      'source','analysis_provider_attempts_authoritative'
    ), updated_at = now()
    where engine_run_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists analysis_engine_runs_v4_usage_trace on private.analysis_engine_runs;
create trigger analysis_engine_runs_v4_usage_trace
after insert or update of status,total_provider_requests,total_input_tokens,
  total_output_tokens,total_reasoning_tokens,total_cost_usd,
  total_standard_equivalent_cost_usd
on private.analysis_engine_runs
for each row execute function private.sync_v4_authoritative_usage_trace();

revoke all on function private.sync_v4_authoritative_usage_trace() from public,anon,authenticated;

create or replace function public.admin_analysis_v4_pilot_report_v1(p_analysis_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run private.analysis_engine_runs%rowtype;
  v_analysis public.analyses%rowtype;
  v_report jsonb;
begin
  select * into v_run from private.analysis_engine_runs
  where analysis_id=p_analysis_id and engine_version='vnext-v4'
  order by started_at desc limit 1;
  if not found then
    return jsonb_build_object('ok',false,'state','v4_run_not_found');
  end if;
  select * into v_analysis from public.analyses where id=p_analysis_id;
  select jsonb_build_object(
    'ok',true,
    'analysis_id',p_analysis_id,
    'engine_run',jsonb_build_object(
      'id',v_run.id,'status',v_run.status,'engine_version',v_run.engine_version,
      'schema_version',v_run.schema_version,'prompt_version',v_run.prompt_version,
      'policy_version',v_run.policy_version,'model',v_run.model,
      'duration_ms',v_run.duration_ms,'provider_requests',v_run.total_provider_requests,
      'input_tokens',v_run.total_input_tokens,'visible_output_tokens',v_run.total_output_tokens,
      'thinking_tokens',v_run.total_reasoning_tokens,'cost_usd',v_run.total_cost_usd,
      'standard_equivalent_cost_usd',v_run.total_standard_equivalent_cost_usd,
      'compute_profile',v_run.compute_profile,'provider_pool',v_run.provider_pool,
      'requested_service_tier',v_run.requested_service_tier
    ),
    'analysis',jsonb_build_object(
      'photo_count',v_analysis.photo_count,'finding_count',v_analysis.finding_count,
      'total_score_fk',v_analysis.total_score_fk,'total_score_m5',v_analysis.total_score_m5,
      'highest_band_fk',v_analysis.highest_band_fk,'highest_band_m5',v_analysis.highest_band_m5
    ),
    'item_counts',(
      select coalesce(jsonb_object_agg(item_class,item_count),'{}'::jsonb)
      from (select item_class,count(*) item_count from private.analysis_items_v4
            where engine_run_id=v_run.id group by item_class) counts
    ),
    'candidate_counts',jsonb_build_object(
      'total',(select count(*) from private.analysis_claim_candidates where engine_run_id=v_run.id),
      'hard_rejected',(select count(*) from private.analysis_hard_rejection_ledger where engine_run_id=v_run.id),
      'routed',(select count(*) from private.analysis_routing_ledger where engine_run_id=v_run.id)
    ),
    'provider_attempts',(
      select coalesce(jsonb_agg(jsonb_build_object(
        'kind',attempt_kind,'number',attempt_number,'state',state,
        'requested_service_tier',requested_service_tier,
        'effective_service_tier',effective_service_tier,
        'input_tokens',input_tokens,'visible_output_tokens',output_tokens,
        'thinking_tokens',reasoning_tokens,'cost_usd',cost_usd,
        'duration_ms',duration_ms,'error_code',error_code,
        'fallback_reason',service_tier_fallback_reason
      ) order by created_at),'[]'::jsonb)
      from private.analysis_provider_attempts where engine_run_id=v_run.id
    ),
    'quality_trace',(
      select trace || jsonb_build_object('provider_usage',provider_usage)
      from private.analysis_quality_trace_v4 where engine_run_id=v_run.id
    ),
    'matched_v3_baselines',(
      select coalesce(jsonb_agg(b.payload order by b.completed_at desc),'[]'::jsonb)
      from (
        select a.completed_at,jsonb_build_object(
          'analysis_id',a.id,'completed_at',a.completed_at,'photo_count',a.photo_count,
          'finding_count',a.finding_count,'total_score_fk',a.total_score_fk,
          'highest_band_fk',a.highest_band_fk,'duration_ms',r.duration_ms,
          'provider_requests',r.total_provider_requests,'input_tokens',r.total_input_tokens,
          'visible_output_tokens',r.total_output_tokens,'thinking_tokens',r.total_reasoning_tokens,
          'cost_usd',r.total_cost_usd,'model',r.model
        ) payload
        from public.analyses a
        join private.analysis_engine_runs r on r.analysis_id=a.id and r.status='completed'
        where a.user_id=v_run.user_id and a.id<>p_analysis_id
          and a.status='completed' and a.photo_count=v_analysis.photo_count
          and r.engine_version='vnext-v3'
        order by a.completed_at desc limit 2
      ) b
    ),
    'registry',jsonb_build_object(
      'version','standards-registry-v1',
      'active_verified_standards',(
        select count(*) from private.standards_registry
        where status='active' and last_verified_at is not null
      ),
      'free_text_references_allowed',false
    )
  ) into v_report;
  return v_report;
end;
$$;

revoke all on function public.admin_analysis_v4_pilot_report_v1(uuid)
  from public,anon,authenticated;
grant execute on function public.admin_analysis_v4_pilot_report_v1(uuid)
  to service_role;

comment on function public.admin_analysis_v4_pilot_report_v1(uuid) is
  'Service-only owner pilot report: v4 claim fate, quality, token, cost and matched v3 baselines.';
