begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(52);

select has_column(
  'public',
  'notification_preferences',
  'app_reminders',
  '1 app reminder preference exists'
);
select has_table(
  'public',
  'user_engagement_state',
  '2 engagement state exists'
);
select has_table('private', 'notification_templates', '3 templates are private');
select has_table('private', 'notification_rules', '4 rules are private');
select has_table('private', 'notification_rule_versions', '5 versions are private');
select has_table('private', 'notification_campaigns', '6 campaigns are private');
select has_table('private', 'notification_jobs', '7 jobs are private');
select has_table(
  'private',
  'notification_delivery_attempts',
  '8 delivery attempts are private'
);

select ok(
  (
    select value->>'rollout_mode' = 'on'
      and value->>'kill_switch' = 'false'
      and value->>'rollout_percentage' = '100'
      and jsonb_typeof(value->'enabled_user_hashes') = 'array'
      and value->>'shadow_observation_started_at' is not null
    from public.app_feature_flags
    where key = 'engagement_notification_automation'
  ),
  '9 current migration head enables bounded shadow evaluation'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.user_engagement_state'::regclass),
  '10 engagement state has RLS'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'private.notification_jobs'::regclass),
  '11 private jobs have RLS defense in depth'
);
select ok(
  not has_table_privilege('authenticated', 'private.notification_jobs', 'select'),
  '12 authenticated cannot read private jobs'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.record_user_engagement_state_v1(text,text,text,text,text)',
    'execute'
  ),
  '13 anon cannot record engagement'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.record_user_engagement_state_v1(text,text,text,text,text)',
    'execute'
  ),
  '14 authenticated can record own engagement'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.enqueue_notification_jobs_v1(timestamptz,integer)',
    'execute'
  ),
  '15 authenticated cannot enqueue jobs'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.enqueue_notification_jobs_v1(timestamptz,integer)',
    'execute'
  ),
  '16 service role can enqueue jobs'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.admin_notification_mutation_v1(uuid,text,jsonb)',
    'execute'
  ),
  '17 authenticated cannot call admin mutations'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values
  (
    '00000000-0000-4000-8000-000000000801'::uuid,
    'notification-owner@example.invalid',
    'authenticated',
    'authenticated',
    '2026-07-24 10:00:00+00',
    '2026-07-24 10:00:00+00'
  ),
  (
    '00000000-0000-4000-8000-000000000802'::uuid,
    'notification-other@example.invalid',
    'authenticated',
    'authenticated',
    '2026-07-24 10:00:00+00',
    '2026-07-24 10:00:00+00'
  );

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000801',
  true
);

select lives_ok(
  $$select public.set_notification_master_preference_v1(true)$$,
  '18 first master enable initializes preferences'
);
select ok(
  (
    select enabled and app_reminders and analysis_complete and report_ready
    from public.notification_preferences
    where user_id = '00000000-0000-4000-8000-000000000801'::uuid
  ),
  '19 first permission initializes all user-facing categories'
);

update public.notification_preferences
set app_reminders = false,
    progress_weekly_summary = false,
    analysis_complete = false,
    report_ready = false,
    account_updates = false
where user_id = '00000000-0000-4000-8000-000000000801'::uuid;

select public.set_notification_master_preference_v1(false);
select public.set_notification_master_preference_v1(true);

select ok(
  (
    select enabled
      and analysis_complete
      and report_ready
      and account_updates
      and not app_reminders
      and not progress_weekly_summary
    from public.notification_preferences
    where user_id = '00000000-0000-4000-8000-000000000801'::uuid
  ),
  '20 master re-enable restores core categories and preserves user-managed opt-outs'
);

update public.notification_preferences
set app_reminders = true
where user_id = '00000000-0000-4000-8000-000000000801'::uuid;

select lives_ok(
  $$
    select public.record_user_engagement_state_v1(
      'Europe/Istanbul',
      'tr_TR',
      'authorized',
      '1.0',
      '80'
    )
  $$,
  '21 valid IANA timezone heartbeat succeeds'
);
select throws_ok(
  $$
    select public.record_user_engagement_state_v1(
      'Invalid/Timezone',
      'tr_TR',
      'authorized',
      '1.0',
      '80'
    )
  $$,
  '22023',
  'invalid_timezone',
  '22 invalid timezone fails closed'
);

insert into public.push_device_tokens (
  user_id,
  token,
  environment,
  notifications_enabled
)
values (
  '00000000-0000-4000-8000-000000000801'::uuid,
  'notification-test-token',
  'production',
  true
);

select public.record_user_engagement_state_v1(
  'Europe/Istanbul',
  'tr_TR',
  'denied',
  '1.0',
  '80'
);
select is(
  (
    select notifications_enabled
    from public.push_device_tokens
    where token = 'notification-test-token'
  ),
  false,
  '23 denied system permission disables active tokens'
);

update public.push_device_tokens
set notifications_enabled = true
where token = 'notification-test-token';
select public.record_user_engagement_state_v1(
  'Europe/Istanbul',
  'tr_TR',
  'authorized',
  '1.0',
  '80'
);

insert into public.notification_events (
  id,
  user_id,
  kind,
  title,
  body,
  status
)
values (
  '00000000-0000-4000-8000-000000000811'::uuid,
  '00000000-0000-4000-8000-000000000801'::uuid,
  'account_updates',
  'Test',
  'Test',
  'sent'
);

select is(
  (
    public.record_notification_open_v1(
      '00000000-0000-4000-8000-000000000811'::uuid
    )->>'recorded'
  )::boolean,
  true,
  '24 owner records notification open'
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000802',
  true
);
select is(
  (
    public.record_notification_open_v1(
      '00000000-0000-4000-8000-000000000811'::uuid
    )->>'recorded'
  )::boolean,
  false,
  '25 another user cannot open owner event'
);

delete from public.notification_events
where id = '00000000-0000-4000-8000-000000000811'::uuid;

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000801',
  true
);
update public.user_engagement_state
set timezone = 'UTC',
    authorization_status = 'authorized',
    last_foreground_at = '2026-07-25 11:00:00+00'
where user_id = '00000000-0000-4000-8000-000000000801'::uuid;
update public.user_onboarding_answers
set completed_at = '2026-07-24 10:00:00+00'
where user_id = '00000000-0000-4000-8000-000000000801'::uuid;
insert into public.user_onboarding_answers (
  user_id,
  completed_at
)
values (
  '00000000-0000-4000-8000-000000000801'::uuid,
  '2026-07-24 10:00:00+00'
)
on conflict (user_id) do update
set completed_at = excluded.completed_at;

update private.notification_rules
set status = 'active'
where key = 'first_analysis_after_24h';
update public.app_feature_flags
set value = '{"rollout_mode":"on","enabled_user_hashes":[],"kill_switch":false}'::jsonb
where key = 'engagement_notification_automation';

select ok(
  (
    public.enqueue_notification_jobs_v1(
      '2026-07-25 12:00:00+00',
      20
    )->>'first_analysis'
  )::integer >= 1,
  '26 eligible first-analysis user is enqueued once'
);
select is(
  (
    select count(*)::bigint
    from private.notification_jobs
    where user_id = '00000000-0000-4000-8000-000000000801'::uuid
      and kind = 'first_analysis_reminder'
      and status = 'pending'
  ),
  1::bigint,
  '27 duplicate-safe enqueue creates one pending job'
);

create temporary table notification_claim as
select *
from public.claim_notification_jobs_v1(
  '2026-07-25 12:00:00+00',
  10,
  300
);

select is(
  (select count(*)::bigint from notification_claim),
  1::bigint,
  '28 one worker claims the job'
);
select is(
  (
    select count(*)::bigint
    from public.claim_notification_jobs_v1(
      '2026-07-25 12:01:00+00',
      10,
      300
    )
  ),
  0::bigint,
  '29 active lease prevents a duplicate claim'
);
select is(
  (
    select public.validate_notification_job_v1(
      job_id,
      claim_token,
      '2026-07-25 12:01:00+00'
    )->>'allowed'
    from notification_claim
  )::boolean,
  true,
  '30 claimed job passes final send-time revalidation'
);

insert into public.admin_users (
  user_id,
  email,
  role,
  mfa_required,
  allowed_scopes
)
values (
  '00000000-0000-4000-8000-000000000801'::uuid,
  'notification-owner@example.invalid',
  'owner',
  false,
  array['notifications.publish']
);

insert into private.notification_campaigns (
  id,
  name,
  status,
  title,
  body,
  destination,
  target_spec,
  scheduled_at,
  started_at,
  created_by
)
values (
  '00000000-0000-4000-8000-000000000821'::uuid,
  'Batch completion safety',
  'running',
  'Test',
  'Test',
  'home',
  '{"audience":"allowlist","user_hashes":[]}'::jsonb,
  '2026-07-25 10:00:00+00',
  '2026-07-25 10:00:00+00',
  '00000000-0000-4000-8000-000000000801'::uuid
);

insert into private.notification_jobs (
  id,
  user_id,
  campaign_id,
  kind,
  episode_key,
  dedupe_key,
  status,
  due_at,
  timezone,
  title,
  body,
  destination,
  attempt_count,
  claim_token,
  claimed_at,
  lease_expires_at
)
values (
  '00000000-0000-4000-8000-000000000822'::uuid,
  '00000000-0000-4000-8000-000000000801'::uuid,
  '00000000-0000-4000-8000-000000000821'::uuid,
  'manual_app_reminder',
  'batch-1',
  'campaign-completion-test-1',
  'claimed',
  '2026-07-25 12:00:00+00',
  'UTC',
  'Test',
  'Test',
  'home',
  1,
  '00000000-0000-4000-8000-000000000823'::uuid,
  '2026-07-25 12:00:00+00',
  '2026-07-25 12:05:00+00'
);

select public.complete_notification_job_v1(
  '00000000-0000-4000-8000-000000000822'::uuid,
  '00000000-0000-4000-8000-000000000823'::uuid,
  'sent',
  null,
  false,
  null,
  null,
  '2026-07-25 12:01:00+00'
);

select is(
  (
    select status
    from private.notification_campaigns
    where id = '00000000-0000-4000-8000-000000000821'::uuid
  ),
  'running',
  '31 completing one batch job does not prematurely complete its campaign'
);

insert into private.notification_jobs (
  id,
  user_id,
  campaign_id,
  kind,
  episode_key,
  dedupe_key,
  status,
  due_at,
  timezone,
  title,
  body,
  destination
)
values (
  '00000000-0000-4000-8000-000000000824'::uuid,
  '00000000-0000-4000-8000-000000000801'::uuid,
  '00000000-0000-4000-8000-000000000821'::uuid,
  'manual_app_reminder',
  'batch-2',
  'campaign-completion-test-2',
  'pending',
  '2026-07-25 12:00:00+00',
  'UTC',
  'Test',
  'Test',
  'home'
);

select throws_ok(
  $$
    select public.admin_notification_mutation_v1(
      '00000000-0000-4000-8000-000000000801'::uuid,
      'set_campaign_status',
      '{
        "campaign_id":"00000000-0000-4000-8000-000000000821",
        "status":"completed"
      }'::jsonb
    )
  $$,
  '55000',
  'campaign_has_unfinished_jobs',
  '32 campaign cannot complete while a pending job exists'
);

update private.notification_jobs
set status = 'sent',
    completed_at = '2026-07-25 12:02:00+00'
where id = '00000000-0000-4000-8000-000000000824'::uuid;

select lives_ok(
  $$
    select public.admin_notification_mutation_v1(
      '00000000-0000-4000-8000-000000000801'::uuid,
      'set_campaign_status',
      '{
        "campaign_id":"00000000-0000-4000-8000-000000000821",
        "status":"completed"
      }'::jsonb
    )
  $$,
  '33 authorized admin completes a fully terminal campaign'
);

select ok(
  (
    select status = 'completed' and completed_at is not null
    from private.notification_campaigns
    where id = '00000000-0000-4000-8000-000000000821'::uuid
  ),
  '34 completed campaign records its terminal timestamp'
);

insert into private.notification_jobs (
  id,
  user_id,
  campaign_id,
  kind,
  episode_key,
  dedupe_key,
  status,
  due_at,
  timezone,
  title,
  body,
  destination,
  attempt_count,
  claim_token,
  claimed_at,
  lease_expires_at
)
values (
  '00000000-0000-4000-8000-000000000825'::uuid,
  '00000000-0000-4000-8000-000000000801'::uuid,
  '00000000-0000-4000-8000-000000000821'::uuid,
  'manual_app_reminder',
  'expired-attempt-3',
  'expired-attempt-3',
  'claimed',
  '2026-07-25 12:00:00+00',
  'UTC',
  'Test',
  'Test',
  'home',
  3,
  '00000000-0000-4000-8000-000000000826'::uuid,
  '2026-07-25 12:00:00+00',
  '2026-07-25 12:05:00+00'
);

select lives_ok(
  $$
    select count(*)
    from public.claim_notification_jobs_v1(
      '2026-07-25 12:10:00+00',
      10,
      300
    )
  $$,
  '35 expired third attempt is swept without starting attempt four'
);

select ok(
  (
    select status = 'failed'
      and claim_token is null
      and last_error_code = 'max_attempts_after_lease_expiry'
    from private.notification_jobs
    where id = '00000000-0000-4000-8000-000000000825'::uuid
  ),
  '36 attempt exhaustion becomes an observable terminal failure'
);

select has_index(
  'private',
  'notification_rules',
  'notification_rules_one_runtime_per_type',
  '37 only one runtime rule can exist for each automation type'
);

select has_index(
  'private',
  'notification_jobs',
  'notification_jobs_active_episode_unique',
  '38 active notification episodes are unique across rule versions'
);

insert into private.notification_campaigns (
  id,
  name,
  status,
  title,
  body,
  destination,
  target_spec,
  scheduled_at,
  started_at,
  created_by
)
values (
  '00000000-0000-4000-8000-000000000830'::uuid,
  'Validation safety',
  'running',
  'Test',
  'Test',
  'home',
  '{"audience":"allowlist","user_hashes":[]}'::jsonb,
  '2026-07-25 10:00:00+00',
  '2026-07-25 10:00:00+00',
  '00000000-0000-4000-8000-000000000801'::uuid
);

insert into public.notification_events (
  id,
  user_id,
  kind,
  title,
  body,
  status,
  created_at,
  sent_at
)
values (
  '00000000-0000-4000-8000-000000000831'::uuid,
  '00000000-0000-4000-8000-000000000801'::uuid,
  'account_updates',
  'Test',
  'Test',
  'sent',
  '2026-07-25 12:00:00+00',
  '2026-07-25 12:00:00+00'
);

insert into private.notification_jobs (
  id,
  user_id,
  campaign_id,
  kind,
  episode_key,
  dedupe_key,
  status,
  due_at,
  timezone,
  title,
  body,
  destination,
  attempt_count,
  claim_token,
  claimed_at,
  lease_expires_at
)
values (
  '00000000-0000-4000-8000-000000000832'::uuid,
  '00000000-0000-4000-8000-000000000801'::uuid,
  '00000000-0000-4000-8000-000000000830'::uuid,
  'manual_app_reminder',
  'defer-episode',
  'defer-episode',
  'claimed',
  '2026-07-25 12:00:00+00',
  'UTC',
  'Test',
  'Test',
  'home',
  1,
  '00000000-0000-4000-8000-000000000833'::uuid,
  '2026-07-25 12:00:00+00',
  '2026-07-25 12:20:00+00'
);

select is(
  (
    public.validate_notification_job_v1(
      '00000000-0000-4000-8000-000000000832'::uuid,
      '00000000-0000-4000-8000-000000000833'::uuid,
      '2026-07-25 12:01:00+00'
    )->>'deferred'
  )::boolean,
  true,
  '39 a newly arrived push defers rather than discards the engagement job'
);

select ok(
  (
    select status = 'pending'
      and attempt_count = 0
      and claim_token is null
      and due_at = '2026-07-26 12:00:01+00'::timestamptz
    from private.notification_jobs
    where id = '00000000-0000-4000-8000-000000000832'::uuid
  ),
  '40 eligibility deferral preserves worker attempts and schedules exact retry'
);

select throws_ok(
  $$
    insert into private.notification_jobs (
      user_id,
      campaign_id,
      kind,
      episode_key,
      dedupe_key,
      status,
      due_at,
      timezone,
      title,
      body,
      destination
    )
    values (
      '00000000-0000-4000-8000-000000000801'::uuid,
      '00000000-0000-4000-8000-000000000830'::uuid,
      'manual_app_reminder',
      'defer-episode',
      'defer-episode-duplicate',
      'pending',
      '2026-07-25 12:02:00+00',
      'UTC',
      'Test',
      'Test',
      'home'
    )
  $$,
  '23505',
  'duplicate key value violates unique constraint "notification_jobs_active_episode_unique"',
  '41 duplicate active episode is rejected across dedupe keys'
);

insert into private.notification_jobs (
  id,
  user_id,
  campaign_id,
  kind,
  episode_key,
  dedupe_key,
  status,
  due_at,
  timezone,
  title,
  body,
  destination,
  attempt_count,
  claim_token,
  claimed_at,
  lease_expires_at
)
values (
  '00000000-0000-4000-8000-000000000834'::uuid,
  '00000000-0000-4000-8000-000000000801'::uuid,
  '00000000-0000-4000-8000-000000000830'::uuid,
  'manual_app_reminder',
  'response-loss-episode',
  'response-loss-episode',
  'claimed',
  '2026-07-25 12:00:00+00',
  'UTC',
  'Test',
  'Test',
  'home',
  1,
  '00000000-0000-4000-8000-000000000836'::uuid,
  '2026-07-25 12:00:00+00',
  '2026-07-25 12:20:00+00'
);

insert into public.notification_events (
  id,
  user_id,
  kind,
  title,
  body,
  status,
  job_id,
  dedupe_key,
  created_at,
  sent_at
)
values (
  '00000000-0000-4000-8000-000000000835'::uuid,
  '00000000-0000-4000-8000-000000000801'::uuid,
  'manual_app_reminder',
  'Test',
  'Test',
  'sent',
  '00000000-0000-4000-8000-000000000834'::uuid,
  'notification-job:00000000-0000-4000-8000-000000000834',
  '2026-07-25 12:01:00+00',
  '2026-07-25 12:01:00+00'
);

select is(
  public.validate_notification_job_v1(
    '00000000-0000-4000-8000-000000000834'::uuid,
    '00000000-0000-4000-8000-000000000836'::uuid,
    '2026-07-25 12:02:00+00'
  )->>'reason',
  'already_delivered_current_job',
  '42 response-loss reconciliation detects the accepted APNs event'
);

select ok(
  (
    select status = 'sent'
      and notification_event_id =
        '00000000-0000-4000-8000-000000000835'::uuid
      and claim_token is null
    from private.notification_jobs
    where id = '00000000-0000-4000-8000-000000000834'::uuid
  ),
  '43 accepted APNs response loss completes the job without another send'
);

select matches(
  pg_get_functiondef(
    'public.enqueue_notification_jobs_v1(timestamptz,integer)'::regprocedure
  ),
  'template_snapshot',
  '44 runtime jobs use the immutable rule-version template snapshot'
);

select lives_ok(
  $$
    insert into public.notification_events (
      user_id,
      kind,
      title,
      body,
      destination,
      status
    )
    values (
      '00000000-0000-4000-8000-000000000801'::uuid,
      'analysis_complete',
      'Test',
      'Test',
      'history',
      'skipped'
    )
  $$,
  '45 legacy analysis history destination remains backward compatible'
);

select lives_ok(
  $$
    select public.admin_notification_mutation_v1(
      '00000000-0000-4000-8000-000000000801'::uuid,
      'set_campaign_status',
      '{
        "campaign_id":"00000000-0000-4000-8000-000000000830",
        "status":"paused"
      }'::jsonb
    )
  $$,
  '46 campaign pause safely parks its outstanding jobs'
);

select lives_ok(
  $$
    select public.admin_notification_mutation_v1(
      '00000000-0000-4000-8000-000000000801'::uuid,
      'set_campaign_status',
      '{
        "campaign_id":"00000000-0000-4000-8000-000000000830",
        "status":"scheduled"
      }'::jsonb
    )
  $$,
  '47 paused campaign can be resumed without recreating its jobs'
);

select ok(
  (
    select c.status = 'scheduled'
      and j.status = 'pending'
      and j.claim_token is null
      and j.last_error_code = 'campaign_paused'
    from private.notification_campaigns c
    join private.notification_jobs j
      on j.campaign_id = c.id
    where c.id = '00000000-0000-4000-8000-000000000830'::uuid
      and j.id = '00000000-0000-4000-8000-000000000832'::uuid
  ),
  '48 pause parks work and resume preserves the original episode'
);

select public.record_user_engagement_state_v1(
  'UTC',
  'rate_limit_probe',
  'authorized',
  '9.9',
  '999'
);

select is(
  (
    select locale
    from public.user_engagement_state
    where user_id = '00000000-0000-4000-8000-000000000801'::uuid
  ),
  'tr_TR',
  '49 server-side heartbeat throttle ignores repeated same-state writes'
);

select is(
  private.notification_rollout_allows(
    '{
      "rollout_mode":"on",
      "enabled_user_hashes":[],
      "rollout_percentage":0,
      "kill_switch":false
    }'::jsonb,
    '00000000-0000-4000-8000-000000000801'::uuid
  ),
  false,
  '50 zero-percent rollout denies every deterministic bucket'
);

select is(
  private.notification_rollout_allows(
    '{
      "rollout_mode":"on",
      "enabled_user_hashes":[],
      "rollout_percentage":100,
      "kill_switch":false
    }'::jsonb,
    '00000000-0000-4000-8000-000000000801'::uuid
  ),
  true,
  '51 full rollout accepts every deterministic bucket'
);

update public.app_feature_flags
set value = '{"rollout_mode":"on"}'::jsonb
where key = 'engagement_notification_automation';

select ok(
  (
    select value->>'rollout_mode' = 'off'
      and value->>'kill_switch' = 'true'
      and value->>'rollout_percentage' = '0'
    from (
      select private.notification_feature_flag() as value
    ) normalized_flag
  ),
  '52 malformed rollout flag fails closed without throwing'
);

select * from extensions.finish();
rollback;
