begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, private, extensions, pg_catalog;

select extensions.plan(41);

select has_table('private', 'analysis_engine_runs', 'vNext engine run table exists');
select has_table('private', 'analysis_photo_runs', 'vNext photo run table exists');
select has_table('private', 'analysis_provider_attempts', 'provider attempt table exists');
select has_table('private', 'analysis_fact_lineage', 'fact lineage table exists');
select has_table('private', 'analysis_module_audits', 'module audit table exists');
select has_table('private', 'analysis_inspection_signals', 'inspection signal table exists');
select has_table('private', 'analysis_targeted_runs', 'targeted checkpoint table exists');

select has_function(
  'public', 'checkpoint_analysis_targeted_run_v1',
  array['uuid','uuid','uuid','text','integer','text','text','text','jsonb','text','text'],
  'targeted result checkpoint RPC exists'
);
select has_function(
  'public', 'get_analysis_targeted_run_v1', array['uuid','uuid'],
  'targeted checkpoint read RPC exists'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.checkpoint_analysis_targeted_run_v1(uuid,uuid,uuid,text,integer,text,text,text,jsonb,text,text)',
    'execute'
  ),
  'authenticated users cannot checkpoint targeted provider output'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.checkpoint_analysis_targeted_run_v1(uuid,uuid,uuid,text,integer,text,text,text,jsonb,text,text)',
    'execute'
  ),
  'service role can checkpoint targeted provider output'
);

select has_function(
  'public', 'finalize_analysis_result_v3',
  array['uuid','uuid','bigint','integer','uuid','uuid','jsonb','jsonb','jsonb','jsonb','jsonb','jsonb'],
  'transactional v3 finalizer exists'
);
select has_function(
  'public', 'admin_analysis_engine_metrics_v3', array['integer','integer'],
  'vNext metrics RPC exists'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.admin_analysis_engine_metrics_v3(integer,integer)', 'execute'
  ),
  'authenticated users cannot read vNext metrics'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.admin_analysis_engine_metrics_v3(integer,integer)', 'execute'
  ),
  'service role can read vNext metrics'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.finalize_analysis_result_v3(uuid,uuid,bigint,integer,uuid,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,jsonb)',
    'execute'
  ),
  'authenticated users cannot finalize vNext analyses'
);
select is(
  (select config->>'primary_model' from private.analysis_engine_configs where is_active),
  'gemini-2.5-flash',
  'Gemini 2.5 Flash is the default primary model'
);
select is(
  (select config->>'fallback_model' from private.analysis_engine_configs where is_active),
  'gemini-2.5-flash',
  'disabled Luna experiment cannot remain the configured v3 fallback'
);
select is(
  (select (config->>'gemini_thinking_budget')::integer from private.analysis_engine_configs where is_active),
  3072,
  'Gemini top-level compatibility budget matches the active photo policy'
);
select is(
  public.admin_analysis_engine_metrics_v3(7, 28)->>'sample_status',
  'insufficient_sample',
  'empty vNext cohort reports insufficient sample'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000000a01'::uuid,
  'vnext-owner@example.invalid',
  'authenticated', 'authenticated', now(), now()
);

insert into public.analyses (
  id, user_id, title, kind, status, photo_count, plan_at_creation,
  output_language, analysis_sector, canvas
) values (
  '00000000-0000-4000-8000-000000000a02'::uuid,
  '00000000-0000-4000-8000-000000000a01'::uuid,
  'vnext fixture', 'photo', 'pending', 1, 'plus', 'tr',
  'construction', 'general'
);

insert into public.photos (
  id, analysis_id, user_id, storage_path, mime_type, sequence_index, is_primary
) values (
  '00000000-0000-4000-8000-000000000a03'::uuid,
  '00000000-0000-4000-8000-000000000a02'::uuid,
  '00000000-0000-4000-8000-000000000a01'::uuid,
  'fixture/vnext/photo_1.jpg', 'image/jpeg', 1, true
);

select is(
  public.admin_set_analysis_engine_vnext_user_v1(
    '00000000-0000-4000-8000-000000000a01'::uuid, true, 'test'
  )->>'state',
  'updated',
  'test owner is allowlisted'
);
select is(
  public.admin_set_analysis_engine_rollout_v1('user_allowlist', false, 0)
    ->'value'->>'rollout_mode',
  'user_allowlist',
  'rollout is set to allowlist mode'
);
select is(
  public.resolve_analysis_engine_route_v3(
    '00000000-0000-4000-8000-000000000a01'::uuid,
    '00000000-0000-4000-8000-000000000a02'::uuid
  )->>'engine',
  'vnext',
  'allowlisted analysis routes to vNext'
);

create temporary table vnext_submit as
select public.submit_analysis_job_v2(
  '00000000-0000-4000-8000-000000000a01'::uuid,
  '00000000-0000-4000-8000-000000000a02'::uuid,
  jsonb_build_object('job_mode','analysis','pipeline_version',2)
) response;

create temporary table vnext_claim as
select public.claim_analysis_job_v2(
  s.user_id, s.analysis_id, s.active_msg_id, s.generation,
  'analysis', 300, 3
) response
from private.analysis_job_state s
where s.analysis_id = '00000000-0000-4000-8000-000000000a02'::uuid;

select is(
  (select response->>'state' from vnext_claim),
  'claimed',
  'fixture worker claim is acquired'
);

create temporary table vnext_begin as
select public.begin_analysis_engine_run_v3(
  s.user_id, s.analysis_id, s.active_msg_id, s.generation,
  (select (response->>'claim_token')::uuid from vnext_claim), 'analysis'
) response
from private.analysis_job_state s
where s.analysis_id = '00000000-0000-4000-8000-000000000a02'::uuid;

select is(
  (select response->>'state' from vnext_begin),
  'running',
  'vNext engine run starts under the queue claim'
);

create temporary table vnext_photo_checkpoint as
select public.checkpoint_analysis_photo_run_v3(
  '00000000-0000-4000-8000-000000000a01'::uuid,
  (select (response->>'engine_run_id')::uuid from vnext_begin),
  '00000000-0000-4000-8000-000000000a03'::uuid,
  1, 'fixture/vnext/photo_1.jpg', 'gemini', 'gemini-2.5-flash',
  'completed', 1,
  jsonb_build_object('hazard_facts', jsonb_build_array(jsonb_build_object('fact_id','fixture'))),
  'fixture-sha', 100, 50, 20, 0.001, 1200, null
) response;

select is(
  (select response->>'state' from vnext_photo_checkpoint),
  'checkpointed',
  'photo output checkpoints independently'
);

select is(
  public.checkpoint_analysis_targeted_run_v1(
    '00000000-0000-4000-8000-000000000a01'::uuid,
    (select (response->>'engine_run_id')::uuid from vnext_begin),
    (select (response->>'photo_run_id')::uuid from vnext_photo_checkpoint),
    'fixture-signal', 1, 'gemini', 'gemini-2.5-flash', 'confirmed',
    jsonb_build_object(
      'hazard_facts', jsonb_build_array(jsonb_build_object('fact_id','targeted-fixture'))
    ),
    'targeted-fixture-sha', null
  )->>'state',
  'checkpointed',
  'targeted provider output checkpoints independently'
);
select is(
  public.checkpoint_analysis_targeted_run_v1(
    '00000000-0000-4000-8000-000000000a01'::uuid,
    (select (response->>'engine_run_id')::uuid from vnext_begin),
    (select (response->>'photo_run_id')::uuid from vnext_photo_checkpoint),
    'fixture-signal', 1, 'gemini', 'gemini-2.5-flash', 'confirmed',
    jsonb_build_object(
      'hazard_facts', jsonb_build_array(jsonb_build_object('fact_id','must-not-overwrite'))
    ),
    'different-sha', null
  )->>'state',
  'already_checkpointed',
  'a retry cannot overwrite or repeat the targeted checkpoint'
);
select is(
  public.get_analysis_targeted_run_v1(
    '00000000-0000-4000-8000-000000000a01'::uuid,
    (select (response->>'engine_run_id')::uuid from vnext_begin)
  )->>'status',
  'confirmed',
  'targeted checkpoint status is reusable on worker retry'
);
select is(
  public.get_analysis_targeted_run_v1(
    '00000000-0000-4000-8000-000000000a01'::uuid,
    (select (response->>'engine_run_id')::uuid from vnext_begin)
  )->'normalized_output'->'hazard_facts'->0->>'fact_id',
  'targeted-fixture',
  'the first paid targeted output remains authoritative'
);

select is(
  public.record_analysis_provider_attempt_v3(
    '00000000-0000-4000-8000-000000000a04'::uuid,
    '00000000-0000-4000-8000-000000000a01'::uuid,
    (select (response->>'engine_run_id')::uuid from vnext_begin),
    (select (response->>'photo_run_id')::uuid from vnext_photo_checkpoint),
    'primary', 1, 'gemini', 'gemini-2.5-flash', 'persisted',
    'provider-fixture', 100, 50, 20, 0, 0.001, 1200, 200, null
  )->>'state',
  'recorded',
  'provider attempt is recorded without raw image bytes'
);

create temporary table vnext_finalize as
select public.finalize_analysis_result_v3(
  '00000000-0000-4000-8000-000000000a01'::uuid,
  '00000000-0000-4000-8000-000000000a02'::uuid,
  s.active_msg_id, s.generation,
  (select (response->>'claim_token')::uuid from vnext_claim),
  (select (response->>'engine_run_id')::uuid from vnext_begin),
  jsonb_build_array(jsonb_build_object(
    'ordinal', 1, 'title', 'Pim ve segman eksikliği',
    'category', 'mekanik bütünlük', 'description', 'Görünür fiziksel cue.',
    'recommended_action', 'Kullanımı durdur.',
    'recommended_measures', jsonb_build_array(jsonb_build_object(
      'kind','corrective','title','Acil kontrol','text','Kullanımı durdur.'
    )),
    'references_text', '', 'root_cause_text', '', 'confidence', 0.9,
    'needs_field_verification', false,
    'ai_original_snapshot', jsonb_build_object('schema_version','hazard-fact-v3'),
    'source_photo_indices', jsonb_build_array(1),
    'source_photo_observations', jsonb_build_array(jsonb_build_object(
      'photo_index',1,'observation','Segman yok ve pim dışa kaymış.'
    )),
    'finding_budget_policy', jsonb_build_object('minimum_pressure',false),
    'ai_confidence', 0.9, 'fk_probability', 6, 'fk_frequency', 1,
    'fk_severity', 40, 'fk_band', 'high',
    'm5_probability', 4, 'm5_severity', 5, 'm5_band', 'critical',
    'display_group', 'Kaldırma bağlantısı', 'display_order', 1,
    'residual_fk_probability', 3, 'residual_fk_frequency', 1,
    'residual_fk_severity', 40, 'residual_m5_probability', 3,
    'residual_m5_severity', 5,
    'bounding_box', jsonb_build_object('x',0.1,'y',0.2,'w',0.3,'h',0.4)
  )),
  jsonb_build_object(
    'status_message','Analiz tamamlandı.', 'ai_summary','1 bulgu',
    'total_score_fk',240, 'total_score_m5',20,
    'highest_band_fk','high','highest_band_m5','critical',
    'hidden_or_rejected_findings_count',0,'max_findings_per_photo',50,
    'ai_models_used',jsonb_build_array('gemini-2.5-flash'),
    'duration_ms',1200,
    'raw_ai_response',jsonb_build_object('_quality_trace_v3',jsonb_build_object(
      'final_count',1,'stages',jsonb_build_array(jsonb_build_object(
        'name','provider_parsed_fact','total',1
      ))
    ))
  ),
  jsonb_build_array(jsonb_build_object(
    'photo_id','00000000-0000-4000-8000-000000000a03',
    'photo_sequence_index',1,'scene_summary','fixture',
    'candidate_findings_count',1,'generated_findings_count',1,
    'coverage_status','covered'
  )),
  jsonb_build_array(jsonb_build_object(
    'fact_trace_id','p1:fixture','final_ordinal',1,
    'source_photo_indices',jsonb_build_array(1),
    'evidence_regions',jsonb_build_array(),
    'semantic_inputs',jsonb_build_object('frequency_basis','missing_invalid_fallback'),
    'score_output',jsonb_build_object('fk_frequency',1),
    'mutations',jsonb_build_array(jsonb_build_object(
      'reason_code','fk_frequency_missing_fallback'
    )),
    'reason_codes',jsonb_build_array('fk_frequency_missing_fallback')
  )),
  jsonb_build_array(jsonb_build_object(
    'photo_index',1,'module_id','structural_mechanical_integrity',
    'entity_refs',jsonb_build_array('lift-arm-a'),'status','positive_evidence'
  )),
  '[]'::jsonb
) response
from private.analysis_job_state s
where s.analysis_id = '00000000-0000-4000-8000-000000000a02'::uuid;

select is(
  (select response->>'state' from vnext_finalize),
  'completed',
  'v3 finalizer completes the analysis atomically'
);
select is(
  (select status::text from public.analyses where id = '00000000-0000-4000-8000-000000000a02'),
  'completed',
  'public analysis is completed'
);
select is(
  (select residual_fk_probability from public.findings where analysis_id = '00000000-0000-4000-8000-000000000a02'),
  3::numeric,
  'planned residual Fine-Kinney score inputs persist'
);
select is(
  (select bounding_box->>'w' from public.findings where analysis_id = '00000000-0000-4000-8000-000000000a02'),
  '0.3',
  'public bounding box preserves the legacy w/h shape'
);
select is(
  (select count(*)::integer from private.analysis_fact_lineage where analysis_id = '00000000-0000-4000-8000-000000000a02'),
  1,
  'fact lineage is persisted'
);
select ok(
  (select final_finding_id is not null from private.analysis_fact_lineage where analysis_id = '00000000-0000-4000-8000-000000000a02'),
  'lineage links to the public finding id'
);
select is(
  (select total_provider_requests from private.analysis_engine_runs where analysis_id = '00000000-0000-4000-8000-000000000a02'),
  1,
  'provider request count is finalized from immutable attempts'
);
select is(
  public.admin_analysis_engine_run_v3('00000000-0000-4000-8000-000000000a02'::uuid)
    ->>'count_invariant_ok',
  'true',
  'admin run report verifies final trace and database counts'
);
insert into public.findings (
  analysis_id, user_id, ordinal, title, category, description,
  recommended_action, confidence, needs_field_verification,
  source_photo_indices, display_order, item_class, is_scored,
  fk_band, m5_band
) values (
  '00000000-0000-4000-8000-000000000a02'::uuid,
  '00000000-0000-4000-8000-000000000a01'::uuid,
  2, 'Saha teyidi', 'fixture', 'Skorsuz fixture',
  'Sahada doğrulayın.', 1, true, array[1], 2,
  'verification_request', false, 'unknown', 'unknown'
);
select lives_ok(
  $$select private.analysis_engine_window_v3(now() - interval '7 days', now())$$,
  'v3 metrics tolerate scoreless compatibility rows without null JSON keys'
);
select is(
  (
    select command from cron.job
    where jobname = 'riskdetected-analysis-quality-daily'
  ),
  'select private.evaluate_analysis_quality_regressions_v1(), private.evaluate_analysis_engine_regressions_v3();',
  'daily cron evaluates legacy and vNext cohorts separately'
);

select * from extensions.finish();
rollback;
