


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "private";


ALTER SCHEMA "private" OWNER TO "postgres";


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."analysis_kind" AS ENUM (
    'photo',
    'text'
);


ALTER TYPE "public"."analysis_kind" OWNER TO "postgres";


CREATE TYPE "public"."analysis_review_status" AS ENUM (
    'open',
    'reviewed',
    'closed'
);


ALTER TYPE "public"."analysis_review_status" OWNER TO "postgres";


CREATE TYPE "public"."analysis_status" AS ENUM (
    'pending',
    'analyzing',
    'completed',
    'failed',
    'queued'
);


ALTER TYPE "public"."analysis_status" OWNER TO "postgres";


CREATE TYPE "public"."canvas_id" AS ENUM (
    'general',
    'ppe',
    'mark',
    'sector',
    'urgent',
    'procedure',
    'machine',
    'warning_signs',
    'electrical',
    'fire',
    'ergonomics',
    'environment_measurement',
    'explosion',
    'environment',
    'legislation',
    'working_at_height',
    'mobile_equipment',
    'general_premium',
    'construction_machinery'
);


ALTER TYPE "public"."canvas_id" OWNER TO "postgres";


CREATE TYPE "public"."risk_level" AS ENUM (
    'critical',
    'high',
    'medium',
    'low',
    'unknown'
);


ALTER TYPE "public"."risk_level" OWNER TO "postgres";


CREATE TYPE "public"."risk_method" AS ENUM (
    'fine_kinney',
    'matrix_5x5'
);


ALTER TYPE "public"."risk_method" OWNER TO "postgres";


CREATE TYPE "public"."subscription_period" AS ENUM (
    'monthly',
    'yearly'
);


ALTER TYPE "public"."subscription_period" OWNER TO "postgres";


CREATE TYPE "public"."subscription_tier" AS ENUM (
    'free',
    'pro',
    'plus'
);


ALTER TYPE "public"."subscription_tier" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."archive_retention_days"("p_tier" "text") RETURNS integer
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'private'
    AS $$
  select case p_tier
    when 'free' then 7
    when 'plus' then 30
    when 'pro' then null
    else 7
  end;
$$;


ALTER FUNCTION "private"."archive_retention_days"("p_tier" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."cleanup_expired_retention"("batch_size" integer DEFAULT 500) RETURNS TABLE("expired_raw_ai" integer, "expired_photo_rows" integer, "storage_objects_requiring_api_delete" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'storage', 'private'
    AS $$
declare
  raw_count integer := 0;
  photo_count integer := 0;
  storage_pending_count integer := 0;
begin
  if batch_size is null or batch_size < 1 then
    batch_size := 500;
  end if;

  with expired as (
    select id
    from public.analyses
    where raw_ai_response is not null
      and raw_ai_response_expires_at is not null
      and raw_ai_response_expires_at < now()
    order by raw_ai_response_expires_at
    limit batch_size
  ), updated as (
    update public.analyses a
    set raw_ai_response = null,
        updated_at = now()
    from expired e
    where a.id = e.id
    returning a.id
  )
  select count(*) into raw_count from updated;

  with expired_photos as materialized (
    select id, storage_path
    from public.photos
    where retention_expires_at is not null
      and retention_expires_at < now()
    order by retention_expires_at
    limit batch_size
  ), cleared_findings as (
    update public.findings f
    set photo_id = null
    from expired_photos p
    where f.photo_id = p.id
    returning f.id
  ), deleted_photos as (
    delete from public.photos ph
    using expired_photos p
    where ph.id = p.id
    returning ph.id
  )
  select
    (select count(*) from expired_photos),
    (select count(*) from deleted_photos)
  into storage_pending_count, photo_count;

  expired_raw_ai := raw_count;
  expired_photo_rows := photo_count;
  storage_objects_requiring_api_delete := storage_pending_count;
  return next;
end;
$$;


ALTER FUNCTION "private"."cleanup_expired_retention"("batch_size" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."company_limit_for_user"("p_user_id" "uuid") RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
  select case coalesce(private.user_plan_tier(p_user_id), p.tier::text)
    when 'plus' then 5
    when 'pro' then 25
    else 0
  end
  from public.profiles p
  where p.id = p_user_id
$$;


ALTER FUNCTION "private"."company_limit_for_user"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."enforce_analysis_company_owner"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
begin
  if new.company_id is not null and not exists (
    select 1
    from public.companies c
    where c.id = new.company_id
      and c.user_id = new.user_id
  ) then
    raise exception 'company_not_owned';
  end if;

  return new;
end $$;


ALTER FUNCTION "private"."enforce_analysis_company_owner"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."enforce_company_write_rules"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
declare
  v_limit integer;
  v_active_count integer;
begin
  new.name := btrim(new.name);
  new.logo_path := nullif(btrim(coalesce(new.logo_path, '')), '');
  new.address := nullif(btrim(coalesce(new.address, '')), '');
  new.contact_person := nullif(btrim(coalesce(new.contact_person, '')), '');
  new.department := nullif(btrim(coalesce(new.department, '')), '');
  new.default_responsible := nullif(btrim(coalesce(new.default_responsible, '')), '');

  if new.name = '' then
    raise exception 'company_name_required';
  end if;

  if new.default_due_days is not null and (new.default_due_days < 1 or new.default_due_days > 365) then
    raise exception 'company_default_due_days_invalid';
  end if;

  v_limit := coalesce(private.company_limit_for_user(new.user_id), 0);
  if v_limit <= 0 then
    raise exception 'company_feature_requires_paid_plan';
  end if;

  if new.is_archived = false then
    select count(*)
      into v_active_count
    from public.companies c
    where c.user_id = new.user_id
      and c.is_archived = false
      and (tg_op <> 'UPDATE' or c.id <> new.id);

    if v_active_count >= v_limit then
      raise exception 'company_limit_exceeded';
    end if;
  end if;

  new.updated_at := now();
  return new;
end $$;


ALTER FUNCTION "private"."enforce_company_write_rules"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."enforce_report_company_owner"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
begin
  if new.company_id is not null and not exists (
    select 1
    from public.companies c
    where c.id = new.company_id
      and c.user_id = new.user_id
  ) then
    raise exception 'company_not_owned';
  end if;

  return new;
end $$;


ALTER FUNCTION "private"."enforce_report_company_owner"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."notification_admin_has_scope"("p_actor_user_id" "uuid", "p_scope" "text") RETURNS boolean
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1
    from public.admin_users au
    where au.user_id = p_actor_user_id
      and au.is_active
      and (
        '*' = any(au.allowed_scopes)
        or p_scope = any(au.allowed_scopes)
      )
  );
$$;


ALTER FUNCTION "private"."notification_admin_has_scope"("p_actor_user_id" "uuid", "p_scope" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."notification_conditions_valid"("p_rule_type" "text", "p_conditions" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
declare
  v_key text;
begin
  if jsonb_typeof(p_conditions) <> 'object' then
    return false;
  end if;

  for v_key in select jsonb_object_keys(p_conditions)
  loop
    if p_rule_type = 'first_analysis'
       and v_key not in ('min_hours', 'max_hours') then
      return false;
    elsif p_rule_type = 'inactivity'
       and v_key not in ('inactivity_days') then
      return false;
    end if;
  end loop;

  if p_rule_type = 'first_analysis' then
    return jsonb_typeof(p_conditions->'min_hours') = 'number'
      and jsonb_typeof(p_conditions->'max_hours') = 'number'
      and (p_conditions->>'min_hours')::numeric between 1 and 168
      and (p_conditions->>'max_hours')::numeric between 2 and 336
      and (p_conditions->>'max_hours')::numeric
        > (p_conditions->>'min_hours')::numeric;
  end if;

  if p_rule_type = 'inactivity' then
    return jsonb_typeof(p_conditions->'inactivity_days') = 'number'
      and (p_conditions->>'inactivity_days')::numeric between 1 and 90;
  end if;

  return false;
exception
  when others then
    return false;
end;
$$;


ALTER FUNCTION "private"."notification_conditions_valid"("p_rule_type" "text", "p_conditions" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."notification_feature_flag"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $$
declare
  v_value jsonb;
  v_rollout_mode text;
  v_percentage integer;
begin
  select value into v_value
  from public.app_feature_flags
  where key = 'engagement_notification_automation';

  if jsonb_typeof(v_value) is distinct from 'object'
     or coalesce(v_value->>'rollout_mode', '')
       not in ('off', 'allowlist', 'on')
     or jsonb_typeof(v_value->'enabled_user_hashes') is distinct from 'array'
     or jsonb_typeof(v_value->'kill_switch') is distinct from 'boolean' then
    raise exception 'invalid_notification_feature_flag';
  end if;

  v_rollout_mode := v_value->>'rollout_mode';
  v_percentage := case
    when v_value ? 'rollout_percentage'
      then (v_value->>'rollout_percentage')::integer
    when v_rollout_mode = 'on'
      then 100
    else 0
  end;

  if v_percentage not between 0 and 100 then
    raise exception 'invalid_notification_rollout_percentage';
  end if;

  return jsonb_build_object(
    'rollout_mode', v_rollout_mode,
    'enabled_user_hashes', v_value->'enabled_user_hashes',
    'rollout_percentage', v_percentage,
    'kill_switch', (v_value->>'kill_switch')::boolean
  );
exception
  when others then
    return '{
      "rollout_mode":"off",
      "enabled_user_hashes":[],
      "rollout_percentage":0,
      "kill_switch":true
    }'::jsonb;
end;
$$;


ALTER FUNCTION "private"."notification_feature_flag"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."notification_rollout_allows"("p_flag" "jsonb", "p_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select
    coalesce((p_flag->>'kill_switch')::boolean, true) = false
    and (
      p_flag->>'rollout_mode' = 'on'
      and private.notification_user_bucket(p_user_id)
        < coalesce((p_flag->>'rollout_percentage')::integer, 100)
      or (
        p_flag->>'rollout_mode' = 'allowlist'
        and coalesce(p_flag->'enabled_user_hashes', '[]'::jsonb)
          ? private.notification_user_hash(p_user_id)
      )
    );
$$;


ALTER FUNCTION "private"."notification_rollout_allows"("p_flag" "jsonb", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."notification_user_bucket"("p_user_id" "uuid") RETURNS integer
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  select (
    get_byte(extensions.digest(p_user_id::text, 'sha256'), 0) * 256
    + get_byte(extensions.digest(p_user_id::text, 'sha256'), 1)
  ) % 100;
$$;


ALTER FUNCTION "private"."notification_user_bucket"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."notification_user_hash"("p_user_id" "uuid") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  select encode(extensions.digest(p_user_id::text, 'sha256'), 'hex');
$$;


ALTER FUNCTION "private"."notification_user_hash"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_competency_for_finding"("p_category" "text", "p_title" "text", "p_description" "text", "p_action" "text", "p_canvas" "text", "p_sectors" "text"[] DEFAULT '{}'::"text"[]) RETURNS TABLE("competency_key" "text", "matched_by" "text", "confidence" numeric, "source_text" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
declare
  v_category text := lower(coalesce(p_category, ''));
  v_text text := lower(
    coalesce(p_category, '') || ' ' ||
    coalesce(p_title, '') || ' ' ||
    coalesce(p_description, '') || ' ' ||
    coalesce(p_action, '')
  );
  v_canvas text := coalesce(p_canvas, '');
  v_sectors text[] := coalesce(p_sectors, '{}'::text[]);
begin
  if private.pp_contains_any(v_category, array['yangın','yangin','söndürücü','sondurucu','tahliye','acil çıkış','acil cikis','yanıcı','yanici','parlayıcı','parlayici','alev','duman','yangın dolabı','yangin dolabi']) then
    return query select 'fire', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['kimyasal','sds','msds','solvent','asit','baz','dökülme','dokulme','sızıntı','sizinti','gaz','buhar','maruziyet','toz','etiketsiz kap']) then
    return query select 'chemical', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['elektrik','pano','kablo','kaçak akım','kacak akim','topraklama','izolasyon','sigorta','gerilim','priz']) then
    return query select 'electrical', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['makine','mekanik','koruyucu','sıkışma','sikisma','ezilme','kesilme','forklift','vinç','vinc','transpalet','hareketli ekipman','döner parça','doner parca']) then
    return query select 'mechanical', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['ergonomi','duruş','durus','manuel taşıma','manuel tasima','tekrarlı','tekrarli','oturuş','oturus']) then
    return query select 'ergonomics', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['psikososyal','stres','mobbing','vardiya','tükenmişlik','tukenmislik','iş yükü','is yuku']) then
    return query select 'psychosocial', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['yüksekte','yuksekte','iskele','ankraj','yaşam hattı','yasam hatti','emniyet kemeri','korkuluk','düşme','dusme','merdiven']) then
    return query select 'working_at_height', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['kkd','baret','gözlük','gozluk','eldiven','maske','kulaklık','kulaklik','emniyet ayakkabısı','emniyet ayakkabisi','reflektif','yelek','kişisel koruyucu','kisisel koruyucu']) then
    return query select 'ppe', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['maden','ocak','galeri','tünel','tunel','göçük','gocuk','taşocağı','tasocagi','havalandırma','havalandirma']) then
    return query select 'mining', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['inşaat','insaat','şantiye','santiye','hafriyat','kalıp','kalip','beton','yapı','yapi']) then
    return query select 'construction', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['fabrika','üretim','uretim','atölye','atolye','pres','konveyör','konveyor','üretim hattı','uretim hatti']) then
    return query select 'factory', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['maden','ocak','galeri','tünel','tunel','göçük','gocuk','taşocağı','tasocagi','havalandırma','havalandirma']) then
    return query select 'mining', 'finding_text', 0.92::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['inşaat','insaat','şantiye','santiye','hafriyat','kalıp','kalip','beton','yapı','yapi']) then
    return query select 'construction', 'finding_text', 0.9::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['fabrika','üretim','uretim','atölye','atolye','pres','konveyör','konveyor','üretim hattı','uretim hatti']) then
    return query select 'factory', 'finding_text', 0.9::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['yangın','yangin','söndürücü','sondurucu','tahliye','acil çıkış','acil cikis','yanıcı','yanici','parlayıcı','parlayici','alev','duman','yangın dolabı','yangin dolabi']) then
    return query select 'fire', 'finding_text', 0.9::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['kimyasal','sds','msds','solvent','asit','baz','dökülme','dokulme','sızıntı','sizinti','gaz','buhar','maruziyet','toz','etiketsiz kap']) then
    return query select 'chemical', 'finding_text', 0.88::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['elektrik','pano','kablo','kaçak akım','kacak akim','topraklama','izolasyon','sigorta','gerilim','priz']) then
    return query select 'electrical', 'finding_text', 0.88::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['yüksekte','yuksekte','iskele','ankraj','yaşam hattı','yasam hatti','emniyet kemeri','korkuluk','düşme','dusme','merdiven']) then
    return query select 'working_at_height', 'finding_text', 0.88::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['kkd','baret','gözlük','gozluk','eldiven','maske','kulaklık','kulaklik','emniyet ayakkabısı','emniyet ayakkabisi','reflektif','yelek','kişisel koruyucu','kisisel koruyucu']) then
    return query select 'ppe', 'finding_text', 0.88::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['makine','koruyucu','sıkışma','sikisma','ezilme','kesilme','forklift','vinç','vinc','transpalet','hareketli ekipman','döner parça','doner parca']) then
    return query select 'mechanical', 'finding_text', 0.82::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['ergonomi','duruş','durus','manuel taşıma','manuel tasima','tekrarlı','tekrarli','oturuş','oturus']) then
    return query select 'ergonomics', 'finding_text', 0.82::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['psikososyal','stres','mobbing','vardiya','tükenmişlik','tukenmislik','iş yükü','is yuku']) then
    return query select 'psychosocial', 'finding_text', 0.82::numeric, p_category;
    return;
  end if;

  case v_canvas
    when 'fire' then
      return query select 'fire', 'canvas_fallback', 0.62::numeric, p_category;
      return;
    when 'explosion' then
      return query select 'fire', 'canvas_fallback', 0.58::numeric, p_category;
      return;
    when 'electrical' then
      return query select 'electrical', 'canvas_fallback', 0.62::numeric, p_category;
      return;
    when 'ppe' then
      return query select 'ppe', 'canvas_fallback', 0.62::numeric, p_category;
      return;
    when 'working_at_height' then
      return query select 'working_at_height', 'canvas_fallback', 0.62::numeric, p_category;
      return;
    when 'machine', 'mobile_equipment', 'construction_machinery' then
      return query select 'mechanical', 'canvas_fallback', 0.58::numeric, p_category;
      return;
    when 'ergonomics' then
      return query select 'ergonomics', 'canvas_fallback', 0.58::numeric, p_category;
      return;
    when 'sector' then
      if 'mining' = any(v_sectors) then
        return query select 'mining', 'onboarding_context', 0.45::numeric, p_category;
        return;
      elsif 'construction' = any(v_sectors) then
        return query select 'construction', 'onboarding_context', 0.45::numeric, p_category;
        return;
      elsif 'manufacturing' = any(v_sectors) then
        return query select 'factory', 'onboarding_context', 0.45::numeric, p_category;
        return;
      end if;
    else
      null;
  end case;

  return;
end;
$$;


ALTER FUNCTION "private"."pp_competency_for_finding"("p_category" "text", "p_title" "text", "p_description" "text", "p_action" "text", "p_canvas" "text", "p_sectors" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_competency_label"("p_key" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'private', 'public', 'pg_temp'
    AS $$
  select case p_key
    when 'fire' then 'Yangın'
    when 'chemical' then 'Kimyasal'
    when 'electrical' then 'Elektrik'
    when 'mechanical' then 'Mekanik'
    when 'ergonomics' then 'Ergonomi'
    when 'psychosocial' then 'Psikososyal'
    when 'working_at_height' then 'Yüksekte Çalışma'
    when 'ppe' then 'KKD'
    when 'mining' then 'Maden'
    when 'construction' then 'İnşaat'
    when 'factory' then 'Fabrika'
    else 'Genel'
  end;
$$;


ALTER FUNCTION "private"."pp_competency_label"("p_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_contains_any"("p_text" "text", "p_terms" "text"[]) RETURNS boolean
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'private', 'public', 'pg_temp'
    AS $$
  select exists (
    select 1
    from unnest(p_terms) as term(value)
    where position(term.value in coalesce(p_text, '')) > 0
  );
$$;


ALTER FUNCTION "private"."pp_contains_any"("p_text" "text", "p_terms" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_ensure_profile"("p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
begin
  insert into public.professional_progress_profiles (user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;
end;
$$;


ALTER FUNCTION "private"."pp_ensure_profile"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_highest_risk_level"("p_fk" "text", "p_m5" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'private', 'public', 'pg_temp'
    AS $$
  select case
    when greatest(private.pp_risk_rank(p_fk), private.pp_risk_rank(p_m5)) = 4 then 'critical'
    when greatest(private.pp_risk_rank(p_fk), private.pp_risk_rank(p_m5)) = 3 then 'high'
    when greatest(private.pp_risk_rank(p_fk), private.pp_risk_rank(p_m5)) = 2 then 'medium'
    when greatest(private.pp_risk_rank(p_fk), private.pp_risk_rank(p_m5)) = 1 then 'low'
    else 'unknown'
  end;
$$;


ALTER FUNCTION "private"."pp_highest_risk_level"("p_fk" "text", "p_m5" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_insert_message"("p_user_id" "uuid", "p_type" "text", "p_title" "text", "p_body" "text", "p_analysis_id" "uuid" DEFAULT NULL::"uuid", "p_report_id" "uuid" DEFAULT NULL::"uuid", "p_competency_key" "text" DEFAULT NULL::"text", "p_risk_level" "text" DEFAULT NULL::"text", "p_metadata" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
begin
  insert into public.professional_progress_messages (
    user_id,
    message_type,
    title,
    body,
    related_analysis_id,
    related_report_id,
    competency_key,
    risk_level,
    metadata
  )
  values (
    p_user_id,
    p_type,
    p_title,
    p_body,
    p_analysis_id,
    p_report_id,
    p_competency_key,
    p_risk_level,
    coalesce(p_metadata, '{}'::jsonb)
  );
end;
$$;


ALTER FUNCTION "private"."pp_insert_message"("p_user_id" "uuid", "p_type" "text", "p_title" "text", "p_body" "text", "p_analysis_id" "uuid", "p_report_id" "uuid", "p_competency_key" "text", "p_risk_level" "text", "p_metadata" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_process_analysis_completed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
declare
  v_inserted boolean;
  v_analysis_mdp integer := 0;
  v_highest_risk text;
  v_onboarding_sectors text[] := '{}'::text[];
  v_finding record;
  v_class record;
  v_competency text;
  v_risk text;
  v_distinct_competencies text[] := '{}'::text[];
  v_total_findings integer := 0;
  v_critical integer := 0;
  v_high integer := 0;
  v_medium integer := 0;
  v_low integer := 0;
  v_unknown integer := 0;
begin
  if new.status <> 'completed' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'completed' then
    return new;
  end if;

  select private.pp_highest_risk_level(new.highest_band_fk::text, new.highest_band_m5::text)
    into v_highest_risk;

  if coalesce(new.analysis_mode, 'standard') <> 'standard' then
    v_analysis_mdp := v_analysis_mdp + 70;
  end if;
  if v_highest_risk in ('critical', 'high') then
    v_analysis_mdp := v_analysis_mdp + 120;
  end if;

  v_inserted := private.pp_record_event(
    new.user_id,
    'analysis_completed:' || new.id::text,
    'analysis_completed',
    v_analysis_mdp,
    new.id,
    null,
    null,
    jsonb_build_object(
      'analysis_mode', coalesce(new.analysis_mode, 'standard'),
      'highest_risk', v_highest_risk,
      'economy_version', 'v2_2026_05_26'
    ),
    coalesce(new.completed_at, now())
  );
  if not v_inserted then
    return new;
  end if;

  select coalesce(uoa.sectors, '{}'::text[])
    into v_onboarding_sectors
  from public.user_onboarding_answers uoa
  where uoa.user_id = new.user_id;

  for v_finding in
    select *
    from public.findings f
    where f.analysis_id = new.id
      and f.user_id = new.user_id
  loop
    v_total_findings := v_total_findings + 1;
    v_risk := private.pp_highest_risk_level(v_finding.fk_band::text, v_finding.m5_band::text);
    if v_risk = 'critical' then
      v_critical := v_critical + 1;
    elsif v_risk = 'high' then
      v_high := v_high + 1;
    elsif v_risk = 'medium' then
      v_medium := v_medium + 1;
    elsif v_risk = 'low' then
      v_low := v_low + 1;
    else
      v_unknown := v_unknown + 1;
    end if;

    select *
      into v_class
    from private.pp_competency_for_finding(
      v_finding.category,
      v_finding.title,
      v_finding.description,
      v_finding.recommended_action,
      new.canvas::text,
      coalesce(v_onboarding_sectors, '{}'::text[])
    )
    limit 1;

    insert into public.professional_progress_finding_classifications (
      user_id,
      analysis_id,
      finding_id,
      competency_key,
      risk_level,
      source_category_text,
      matched_by,
      confidence
    )
    values (
      new.user_id,
      new.id,
      v_finding.id,
      case
        when v_class.competency_key is not null and coalesce(v_class.confidence, 0) >= 0.45
          then v_class.competency_key
        else 'unclassified'
      end,
      v_risk,
      coalesce(v_class.source_text, v_finding.category),
      case
        when v_class.competency_key is not null and coalesce(v_class.confidence, 0) >= 0.45
          then v_class.matched_by
        else 'unclassified'
      end,
      case
        when v_class.competency_key is not null and coalesce(v_class.confidence, 0) >= 0.45
          then v_class.confidence
        else 0
      end
    )
    on conflict (finding_id) do nothing;

    if v_class.competency_key is not null and coalesce(v_class.confidence, 0) >= 0.45 then
      insert into public.professional_progress_competency_stats (
        user_id,
        competency_key,
        finding_count,
        critical_count,
        high_count,
        medium_count,
        low_count,
        unknown_count,
        last_detected_at,
        updated_at
      )
      values (
        new.user_id,
        v_class.competency_key,
        1,
        case when v_risk = 'critical' then 1 else 0 end,
        case when v_risk = 'high' then 1 else 0 end,
        case when v_risk = 'medium' then 1 else 0 end,
        case when v_risk = 'low' then 1 else 0 end,
        case when v_risk = 'unknown' then 1 else 0 end,
        coalesce(new.completed_at, now()),
        now()
      )
      on conflict (user_id, competency_key) do update
      set finding_count = professional_progress_competency_stats.finding_count + 1,
          critical_count = professional_progress_competency_stats.critical_count + excluded.critical_count,
          high_count = professional_progress_competency_stats.high_count + excluded.high_count,
          medium_count = professional_progress_competency_stats.medium_count + excluded.medium_count,
          low_count = professional_progress_competency_stats.low_count + excluded.low_count,
          unknown_count = professional_progress_competency_stats.unknown_count + excluded.unknown_count,
          last_detected_at = greatest(coalesce(professional_progress_competency_stats.last_detected_at, excluded.last_detected_at), excluded.last_detected_at),
          updated_at = now();

      if not (v_class.competency_key = any(v_distinct_competencies)) then
        v_distinct_competencies := array_append(v_distinct_competencies, v_class.competency_key);
      end if;

      perform private.pp_record_event(
        new.user_id,
        'first_competency_used:' || v_class.competency_key,
        'first_competency_used',
        20,
        new.id,
        null,
        v_class.competency_key,
        jsonb_build_object(
          'competency_key', v_class.competency_key,
          'economy_version', 'v2_2026_05_26'
        ),
        coalesce(new.completed_at, now())
      );
    end if;
  end loop;

  foreach v_competency in array v_distinct_competencies loop
    update public.professional_progress_competency_stats
    set analysis_count = analysis_count + 1,
        updated_at = now()
    where user_id = new.user_id
      and competency_key = v_competency;
  end loop;

  update public.professional_progress_profiles
  set total_analyses = total_analyses + 1,
      total_findings = total_findings + v_total_findings,
      critical_findings = critical_findings + v_critical,
      high_findings = high_findings + v_high,
      medium_findings = medium_findings + v_medium,
      low_findings = low_findings + v_low,
      unknown_findings = unknown_findings + v_unknown,
      updated_at = now()
  where user_id = new.user_id;

  perform private.pp_refresh_active_days(new.user_id);
  perform private.pp_refresh_weekly_summary(new.user_id, coalesce(new.completed_at, now()));
  perform private.pp_unlock_badges_for_user(new.user_id);

  return new;
exception when others then
  raise warning 'professional_progress analysis processing failed for analysis %: %', new.id, sqlerrm;
  return new;
end;
$$;


ALTER FUNCTION "private"."pp_process_analysis_completed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_process_report_created"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
declare
  v_mdp integer := 60;
  v_uncapped_mdp integer := 60;
  v_is_risk_report boolean := false;
  v_workflow_existing_mdp integer := 0;
  v_inserted boolean;
  v_week_start date;
  v_week_reports integer;
  v_month_findings integer;
  v_best record;
  v_competency text;
begin
  v_is_risk_report := coalesce(new.kind, '') in ('riskAnalysis', 'risk_analysis')
    or coalesce(new.format, '') = 'xlsx';
  if v_is_risk_report then
    v_uncapped_mdp := v_uncapped_mdp + 90;
  end if;

  v_mdp := v_uncapped_mdp;

  if new.analysis_id is not null then
    select coalesce(sum(mdp_delta), 0)::int
      into v_workflow_existing_mdp
    from public.professional_progress_events
    where user_id = new.user_id
      and analysis_id = new.analysis_id
      and event_type in ('analysis_completed', 'first_competency_used', 'report_created');

    v_mdp := least(v_uncapped_mdp, greatest(400 - coalesce(v_workflow_existing_mdp, 0), 0));
  end if;

  v_inserted := private.pp_record_event(
    new.user_id,
    'report_created:' || new.id::text,
    'report_created',
    v_mdp,
    new.analysis_id,
    new.id,
    null,
    jsonb_build_object(
      'format', new.format,
      'kind', new.kind,
      'risk_report', v_is_risk_report,
      'uncapped_mdp', v_uncapped_mdp,
      'workflow_cap_mdp', 400,
      'workflow_existing_mdp', v_workflow_existing_mdp,
      'economy_version', 'v2_2026_05_26'
    ),
    new.created_at
  );
  if not v_inserted then
    return new;
  end if;

  update public.professional_progress_profiles
  set total_reports = total_reports + 1,
      updated_at = now()
  where user_id = new.user_id;

  for v_competency in
    select distinct competency_key
    from public.professional_progress_finding_classifications
    where user_id = new.user_id
      and analysis_id = new.analysis_id
      and competency_key <> 'unclassified'
  loop
    update public.professional_progress_competency_stats
    set report_count = report_count + 1,
        updated_at = now()
    where user_id = new.user_id
      and competency_key = v_competency;
  end loop;

  v_week_start := (date_trunc('week', new.created_at at time zone 'Europe/Istanbul'))::date;
  perform private.pp_record_event(
    new.user_id,
    'weekly_bonus:' || v_week_start::text,
    'weekly_report_bonus',
    25,
    null,
    new.id,
    null,
    jsonb_build_object(
      'week_start', v_week_start,
      'economy_version', 'v2_2026_05_26'
    ),
    new.created_at
  );

  select count(*)
    into v_week_reports
  from public.reports r
  where r.user_id = new.user_id
    and (r.created_at at time zone 'Europe/Istanbul')::date >= v_week_start
    and (r.created_at at time zone 'Europe/Istanbul')::date < v_week_start + 7;

  select coalesce(sum(finding_count), 0)
    into v_month_findings
  from public.professional_progress_competency_stats
  where user_id = new.user_id;

  select c.competency_key, c.risk_level, count(*)::int as count
    into v_best
  from public.professional_progress_finding_classifications c
  where c.user_id = new.user_id
    and c.analysis_id = new.analysis_id
    and c.competency_key <> 'unclassified'
  group by c.competency_key, c.risk_level
  order by private.pp_risk_rank(c.risk_level) desc, count(*) desc
  limit 1;

  if v_best.competency_key is not null then
    perform private.pp_insert_message(
      new.user_id,
      'instant',
      'Rapor arşivlendi',
      case
        when v_best.risk_level in ('critical', 'high') then
          'Bu raporda ' || private.pp_competency_label(v_best.competency_key) || ' alanında yüksek/kritik riskleri görünür kıldın.'
        else
          'Bu hafta ' || coalesce(v_week_reports, 1)::text || '. raporun. İstikrarlı ilerliyorsun.'
      end,
      new.analysis_id,
      new.id,
      v_best.competency_key,
      v_best.risk_level,
      jsonb_build_object('week_reports', v_week_reports, 'total_documented_risks', v_month_findings)
    );
  else
    perform private.pp_insert_message(
      new.user_id,
      'instant',
      'Rapor arşivlendi',
      'Bu hafta ' || coalesce(v_week_reports, 1)::text || '. raporun. İstikrarlı ilerliyorsun.',
      new.analysis_id,
      new.id,
      null,
      null,
      jsonb_build_object('week_reports', v_week_reports, 'total_documented_risks', v_month_findings)
    );
  end if;

  perform private.pp_refresh_active_days(new.user_id);
  perform private.pp_refresh_weekly_summary(new.user_id, new.created_at);
  perform private.pp_unlock_badges_for_user(new.user_id);

  return new;
exception when others then
  raise warning 'professional_progress report processing failed for report %: %', new.id, sqlerrm;
  return new;
end;
$$;


ALTER FUNCTION "private"."pp_process_report_created"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_record_event"("p_user_id" "uuid", "p_event_key" "text", "p_event_type" "text", "p_mdp" integer DEFAULT 0, "p_analysis_id" "uuid" DEFAULT NULL::"uuid", "p_report_id" "uuid" DEFAULT NULL::"uuid", "p_competency_key" "text" DEFAULT NULL::"text", "p_metadata" "jsonb" DEFAULT '{}'::"jsonb", "p_occurred_at" timestamp with time zone DEFAULT "now"()) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
declare
  v_inserted integer := 0;
  v_old_title text;
  v_new_title text;
  v_new_total integer;
begin
  perform private.pp_ensure_profile(p_user_id);

  insert into public.professional_progress_events (
    user_id,
    event_key,
    event_type,
    mdp_delta,
    analysis_id,
    report_id,
    competency_key,
    metadata,
    occurred_at
  )
  values (
    p_user_id,
    p_event_key,
    p_event_type,
    greatest(coalesce(p_mdp, 0), 0),
    p_analysis_id,
    p_report_id,
    p_competency_key,
    coalesce(p_metadata, '{}'::jsonb),
    coalesce(p_occurred_at, now())
  )
  on conflict (user_id, event_key) do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    return false;
  end if;

  select current_title_key
    into v_old_title
  from public.professional_progress_profiles
  where user_id = p_user_id;

  update public.professional_progress_profiles
  set
    total_mdp = total_mdp + greatest(coalesce(p_mdp, 0), 0),
    last_event_at = greatest(coalesce(last_event_at, p_occurred_at), p_occurred_at),
    updated_at = now()
  where user_id = p_user_id
  returning total_mdp into v_new_total;

  v_new_title := private.pp_title_key_for_mdp(v_new_total);
  if v_new_title is distinct from v_old_title then
    update public.professional_progress_profiles
    set current_title_key = v_new_title,
        last_title_change_at = now(),
        updated_at = now()
    where user_id = p_user_id;

    insert into public.professional_progress_events (
      user_id,
      event_key,
      event_type,
      mdp_delta,
      metadata,
      occurred_at
    )
    values (
      p_user_id,
      'title_changed:' || v_new_title,
      'title_changed',
      0,
      jsonb_build_object(
        'title_key', v_new_title,
        'title_label', private.pp_title_label(v_new_title),
        'total_mdp', v_new_total
      ),
      now()
    )
    on conflict (user_id, event_key) do nothing;

    insert into public.professional_progress_badges (
      user_id,
      badge_key,
      badge_type,
      title,
      subtitle,
      icon_name,
      metadata
    )
    values (
      p_user_id,
      'title:' || v_new_title,
      'title',
      private.pp_title_label(v_new_title),
      'RiskDetected içi mesleki birikim ünvanı kazanıldı.',
      'checkmark.seal.fill',
      jsonb_build_object('title_key', v_new_title, 'total_mdp', v_new_total)
    )
    on conflict (user_id, badge_key) do nothing;

    perform private.pp_insert_message(
      p_user_id,
      'title_change',
      'Yeni ünvan',
      'Tebrikler. ' || private.pp_title_label(v_new_title) || ' ünvanına ulaştınız. Bu, ' || v_new_total::text || ' MDP''lik mesleki birikim demek.',
      null,
      null,
      null,
      null,
      jsonb_build_object('title_key', v_new_title, 'total_mdp', v_new_total)
    );
  end if;

  return true;
end;
$$;


ALTER FUNCTION "private"."pp_record_event"("p_user_id" "uuid", "p_event_key" "text", "p_event_type" "text", "p_mdp" integer, "p_analysis_id" "uuid", "p_report_id" "uuid", "p_competency_key" "text", "p_metadata" "jsonb", "p_occurred_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_refresh_active_days"("p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
declare
  v_count integer;
begin
  select count(distinct (occurred_at at time zone 'Europe/Istanbul')::date)
    into v_count
  from public.professional_progress_events
  where user_id = p_user_id
    and event_type in ('analysis_completed', 'report_created');

  update public.professional_progress_profiles
  set active_days = coalesce(v_count, 0),
      updated_at = now()
  where user_id = p_user_id;
end;
$$;


ALTER FUNCTION "private"."pp_refresh_active_days"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_refresh_weekly_summaries_for_week"("p_reference_at" timestamp with time zone DEFAULT "now"()) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
declare
  v_profile record;
  v_count integer := 0;
begin
  for v_profile in
    select user_id
    from public.professional_progress_profiles
  loop
    perform private.pp_refresh_weekly_summary(v_profile.user_id, p_reference_at);
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;


ALTER FUNCTION "private"."pp_refresh_weekly_summaries_for_week"("p_reference_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_refresh_weekly_summary"("p_user_id" "uuid", "p_reference_at" timestamp with time zone DEFAULT "now"()) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
declare
  v_week_start date;
  v_week_end date;
  v_reports integer := 0;
  v_analyses integer := 0;
  v_findings integer := 0;
  v_top_competency text;
  v_title text := 'Haftalık Takip';
  v_body text;
begin
  v_week_start := (date_trunc('week', coalesce(p_reference_at, now()) at time zone 'Europe/Istanbul'))::date;
  v_week_end := v_week_start + 7;

  select count(*)::int
    into v_reports
  from public.reports
  where user_id = p_user_id
    and (created_at at time zone 'Europe/Istanbul')::date >= v_week_start
    and (created_at at time zone 'Europe/Istanbul')::date < v_week_end;

  select count(*)::int
    into v_analyses
  from public.analyses
  where user_id = p_user_id
    and status = 'completed'
    and (coalesce(completed_at, created_at) at time zone 'Europe/Istanbul')::date >= v_week_start
    and (coalesce(completed_at, created_at) at time zone 'Europe/Istanbul')::date < v_week_end;

  select count(*)::int
    into v_findings
  from public.professional_progress_finding_classifications c
  join public.analyses a on a.id = c.analysis_id
  where c.user_id = p_user_id
    and (coalesce(a.completed_at, a.created_at) at time zone 'Europe/Istanbul')::date >= v_week_start
    and (coalesce(a.completed_at, a.created_at) at time zone 'Europe/Istanbul')::date < v_week_end;

  select c.competency_key
    into v_top_competency
  from public.professional_progress_finding_classifications c
  join public.analyses a on a.id = c.analysis_id
  where c.user_id = p_user_id
    and c.competency_key <> 'unclassified'
    and (coalesce(a.completed_at, a.created_at) at time zone 'Europe/Istanbul')::date >= v_week_start
    and (coalesce(a.completed_at, a.created_at) at time zone 'Europe/Istanbul')::date < v_week_end
  group by c.competency_key
  order by count(*) desc, c.competency_key
  limit 1;

  if coalesce(v_reports, 0) = 0 and coalesce(v_analyses, 0) = 0 then
    v_body := 'Bu hafta ilk analizini başlat. 😔';
  elsif coalesce(v_reports, 0) = 0 then
    v_body := coalesce(v_analyses, 0)::text ||
      ' analiz tamamladın. Şimdi rapora dönüştür.';
  elsif coalesce(v_reports, 0) = 1 then
    v_body := 'İlk rapor tamam. Devam et.';
  else
    v_body := 'Bu hafta ' || coalesce(v_reports, 0)::text ||
      ' rapor tamamladın. 💪';
  end if;

  insert into public.professional_progress_weekly_summaries (
    user_id,
    week_start,
    reports_count,
    analyses_count,
    findings_count,
    top_competency_key,
    message_title,
    message_body
  )
  values (
    p_user_id,
    v_week_start,
    coalesce(v_reports, 0),
    coalesce(v_analyses, 0),
    coalesce(v_findings, 0),
    v_top_competency,
    v_title,
    v_body
  )
  on conflict (user_id, week_start) do update
  set reports_count = excluded.reports_count,
      analyses_count = excluded.analyses_count,
      findings_count = excluded.findings_count,
      top_competency_key = excluded.top_competency_key,
      message_title = excluded.message_title,
      message_body = excluded.message_body;
end;
$$;


ALTER FUNCTION "private"."pp_refresh_weekly_summary"("p_user_id" "uuid", "p_reference_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_risk_rank"("p_level" "text") RETURNS integer
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'private', 'public', 'pg_temp'
    AS $$
  select case p_level
    when 'critical' then 4
    when 'high' then 3
    when 'medium' then 2
    when 'low' then 1
    else 0
  end;
$$;


ALTER FUNCTION "private"."pp_risk_rank"("p_level" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_seed_competency"("p_user_id" "uuid", "p_competency_key" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
begin
  if p_competency_key is null then
    return;
  end if;

  insert into public.professional_progress_competency_stats (
    user_id,
    competency_key,
    onboarding_seed,
    updated_at
  )
  values (
    p_user_id,
    p_competency_key,
    true,
    now()
  )
  on conflict (user_id, competency_key) do update
  set onboarding_seed = true,
      updated_at = now();

  perform private.pp_record_event(
    p_user_id,
    'onboarding_competency_seeded:' || p_competency_key,
    'onboarding_competency_seeded',
    0,
    null,
    null,
    p_competency_key,
    jsonb_build_object('competency_key', p_competency_key),
    now()
  );
end;
$$;


ALTER FUNCTION "private"."pp_seed_competency"("p_user_id" "uuid", "p_competency_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_seed_onboarding_competencies"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
begin
  perform private.pp_ensure_profile(new.user_id);

  if 'mining' = any(new.sectors) then
    perform private.pp_seed_competency(new.user_id, 'mining');
  end if;
  if 'construction' = any(new.sectors) then
    perform private.pp_seed_competency(new.user_id, 'construction');
  end if;
  if 'manufacturing' = any(new.sectors) then
    perform private.pp_seed_competency(new.user_id, 'factory');
  end if;
  if 'energy' = any(new.sectors) then
    perform private.pp_seed_competency(new.user_id, 'chemical');
    perform private.pp_seed_competency(new.user_id, 'electrical');
    perform private.pp_seed_competency(new.user_id, 'fire');
  end if;
  if 'office' = any(new.sectors) then
    perform private.pp_seed_competency(new.user_id, 'ergonomics');
    perform private.pp_seed_competency(new.user_id, 'psychosocial');
  end if;

  return new;
exception when others then
  raise warning 'professional_progress onboarding seed failed for user %: %', new.user_id, sqlerrm;
  return new;
end;
$$;


ALTER FUNCTION "private"."pp_seed_onboarding_competencies"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_title_key_for_mdp"("p_mdp" integer) RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'private', 'public', 'pg_temp'
    AS $$
  select case
    when coalesce(p_mdp, 0) >= 180000 then 'master_hse_specialist'
    when coalesce(p_mdp, 0) >= 90000 then 'safety_strategist'
    when coalesce(p_mdp, 0) >= 40000 then 'senior_risk_specialist'
    when coalesce(p_mdp, 0) >= 15000 then 'hazard_analyst'
    when coalesce(p_mdp, 0) >= 5000 then 'risk_hunter'
    when coalesce(p_mdp, 0) >= 1000 then 'field_observer'
    else 'candidate'
  end;
$$;


ALTER FUNCTION "private"."pp_title_key_for_mdp"("p_mdp" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_title_label"("p_key" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'private', 'public', 'pg_temp'
    AS $$
  select case p_key
    when 'field_observer' then 'Saha Gözlemcisi'
    when 'risk_hunter' then 'Risk Avcısı'
    when 'hazard_analyst' then 'Tehlike Analisti'
    when 'senior_risk_specialist' then 'Kıdemli Risk Uzmanı'
    when 'safety_strategist' then 'Güvenlik Stratejisti'
    when 'master_hse_specialist' then 'Usta İSG Uzmanı'
    else 'Aday Uzman'
  end;
$$;


ALTER FUNCTION "private"."pp_title_label"("p_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_unlock_badge"("p_user_id" "uuid", "p_badge_key" "text", "p_badge_type" "text", "p_title" "text", "p_subtitle" "text", "p_icon_name" "text", "p_metadata" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
declare
  v_inserted integer := 0;
begin
  insert into public.professional_progress_badges (
    user_id,
    badge_key,
    badge_type,
    title,
    subtitle,
    icon_name,
    metadata
  )
  values (
    p_user_id,
    p_badge_key,
    p_badge_type,
    p_title,
    p_subtitle,
    p_icon_name,
    coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (user_id, badge_key) do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted > 0 then
    perform private.pp_insert_message(
      p_user_id,
      'milestone',
      p_title,
      p_subtitle,
      null,
      null,
      null,
      null,
      jsonb_build_object('badge_key', p_badge_key, 'badge_type', p_badge_type)
    );
  end if;
end;
$$;


ALTER FUNCTION "private"."pp_unlock_badge"("p_user_id" "uuid", "p_badge_key" "text", "p_badge_type" "text", "p_title" "text", "p_subtitle" "text", "p_icon_name" "text", "p_metadata" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pp_unlock_badges_for_user"("p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
declare
  v_profile public.professional_progress_profiles%rowtype;
  v_diversity integer;
  v_onboarding record;
begin
  select * into v_profile
  from public.professional_progress_profiles
  where user_id = p_user_id;
  if not found then
    return;
  end if;

  if v_profile.total_reports >= 1 then
    perform private.pp_unlock_badge(p_user_id, 'reports:1', 'report_count', 'İlk Adım', 'İlk raporunu oluşturdun. Mesleki takip izin başladı.', 'rosette');
  end if;
  if v_profile.total_reports >= 10 then
    perform private.pp_unlock_badge(p_user_id, 'reports:10', 'report_count', 'Kararlı Başlangıç', '10 rapora ulaştın. Raporlama disiplinin güçleniyor.', 'medal.fill');
  end if;
  if v_profile.total_reports >= 25 then
    perform private.pp_unlock_badge(p_user_id, 'reports:25', 'report_count', 'İstikrarlı Uzman', '25 raporla düzenli takip alışkanlığı oluşturdun.', 'medal.fill');
  end if;
  if v_profile.total_reports >= 50 then
    perform private.pp_unlock_badge(p_user_id, 'reports:50', 'report_count', 'Deneyimli Gözlemci', '50 rapor, güçlü bir saha gözlemi birikimi demek.', 'trophy.fill');
  end if;
  if v_profile.total_reports >= 100 then
    perform private.pp_unlock_badge(p_user_id, 'reports:100', 'report_count', 'Yüz Rapor Kulübü', '100. raporun. Bu, mesleki anlamda ciddi bir kilometre taşı.', 'trophy.fill');
  end if;
  if v_profile.total_reports >= 250 then
    perform private.pp_unlock_badge(p_user_id, 'reports:250', 'report_count', 'Saha Veterani', '250 rapora ulaştın. Takip izin derinleşiyor.', 'trophy.fill');
  end if;
  if v_profile.total_reports >= 500 then
    perform private.pp_unlock_badge(p_user_id, 'reports:500', 'report_count', 'Kıdemli Saha Lideri', '500 rapor, uzun soluklu bir saha disiplini gösterir.', 'trophy.fill');
  end if;
  if v_profile.total_reports >= 1000 then
    perform private.pp_unlock_badge(p_user_id, 'reports:1000', 'report_count', 'Bin Rapor Ustası', '1.000 rapora ulaştın. Bu büyük bir mesleki arşiv.', 'trophy.fill');
  end if;

  select count(*)
    into v_diversity
  from public.professional_progress_competency_stats
  where user_id = p_user_id
    and (finding_count > 0 or report_count > 0);

  if v_diversity >= 3 then
    perform private.pp_unlock_badge(p_user_id, 'competency:3', 'competency_diversity', 'Çok Yönlü Bakış', '3 farklı yetkinlik alanında risk dokümante ettin.', 'square.grid.2x2.fill');
  end if;
  if v_diversity >= 5 then
    perform private.pp_unlock_badge(p_user_id, 'competency:5', 'competency_diversity', 'Geniş Spektrum Uzmanı', '5 farklı yetkinlik alanında birikim oluşturdun.', 'square.grid.3x2.fill');
  end if;
  if v_diversity >= 8 then
    perform private.pp_unlock_badge(p_user_id, 'competency:8', 'competency_diversity', 'Tam Kapsamlı Analist', '8 farklı yetkinlik alanını görünür kıldın.', 'square.grid.3x3.fill');
  end if;
  if v_diversity >= 11 then
    perform private.pp_unlock_badge(p_user_id, 'competency:11', 'competency_diversity', 'Tam Spektrum Analisti', '11 yetkinlik alanının tamamında iz bıraktın.', 'sparkles');
  end if;

  if v_profile.critical_findings + v_profile.high_findings >= 1 then
    perform private.pp_unlock_badge(p_user_id, 'risk:first_high', 'risk', 'Cesur Karar', 'İlk yüksek/kritik riskli analizini tamamladın. Zor olanı görünür kıldın.', 'exclamationmark.triangle.fill');
  end if;

  if exists (
    select 1
    from public.professional_progress_events
    where user_id = p_user_id
      and event_type = 'report_created'
      and coalesce(metadata->>'risk_report', 'false') = 'true'
  ) then
    perform private.pp_unlock_badge(p_user_id, 'report_kind:first_risk_analysis', 'report_kind', 'Risk Analizi Raporu', 'İlk detaylı risk analizi raporunu arşivledin.', 'doc.richtext.fill');
  end if;

  if v_profile.active_days >= 30 then
    perform private.pp_unlock_badge(p_user_id, 'active_days:30', 'active_days', 'Bir Aylık Yolculuk', '30 farklı aktif günde analiz veya rapor ürettin.', 'calendar.badge.checkmark');
  end if;
  if v_profile.active_days >= 90 then
    perform private.pp_unlock_badge(p_user_id, 'active_days:90', 'active_days', 'Üç Aylık Süreklilik', '90 aktif güne yayılan mesleki takip izi oluşturdun.', 'calendar.badge.checkmark');
  end if;
  if v_profile.active_days >= 365 then
    perform private.pp_unlock_badge(p_user_id, 'active_days:365', 'active_days', 'Yıllık Birikim', 'Bir yıla yayılan aktif RiskDetected birikimi oluşturdun.', 'calendar.badge.checkmark');
  end if;

  for v_onboarding in
    select competency_key
    from public.professional_progress_competency_stats
    where user_id = p_user_id
      and onboarding_seed = true
      and report_count > 0
  loop
    perform private.pp_unlock_badge(
      p_user_id,
      'onboarding_area:first_report:' || v_onboarding.competency_key,
      'onboarding_area',
      'Beyan Edilen Alanda İlk Rapor',
      'Onboardingde belirttiğin çalışma alanında ilk gerçek raporunu oluşturdun.',
      'checkmark.seal.fill',
      jsonb_build_object('competency_key', v_onboarding.competency_key)
    );
  end loop;
end;
$$;


ALTER FUNCTION "private"."pp_unlock_badges_for_user"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."report_monthly_limit"("p_tier" "text") RETURNS integer
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'private'
    AS $$
  select case p_tier
    when 'free' then 3
    when 'plus' then 150
    when 'pro' then 750
    else 3
  end;
$$;


ALTER FUNCTION "private"."report_monthly_limit"("p_tier" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."tg_protect_completed_analysis_status"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if old.status::text = 'completed' and new.status::text <> 'completed' then
    raise exception using
      errcode = '23514',
      message = 'completed_analysis_status_is_terminal';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "private"."tg_protect_completed_analysis_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."user_plan_tier"("p_user_id" "uuid") RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
  select coalesce((
    select us.tier
    from public.user_subscriptions us
    where us.user_id = p_user_id
      and us.tier in ('plus', 'pro')
      and us.status in ('active', 'trialing', 'grace_period')
      and (us.current_period_ends_at is null or us.current_period_ends_at > now())
    order by case us.tier when 'pro' then 2 when 'plus' then 1 else 0 end desc,
             us.updated_at desc
    limit 1
  ), 'free');
$$;


ALTER FUNCTION "private"."user_plan_tier"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_analysis_pipeline_metrics_v2"() RETURNS "jsonb"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select jsonb_build_object(
    'queue_depth', (select count(*) from pgmq.q_analysis_jobs),
    'queued_analyses', (
      select count(*) from public.analyses where status::text = 'queued'
    ),
    'analyzing_analyses', (
      select count(*) from public.analyses where status::text = 'analyzing'
    ),
    'expired_analysis_leases', (
      select count(*)
      from private.analysis_job_state
      where claim_token is not null and lease_expires_at <= now()
    ),
    'abandoned_pending_drafts', (
      select count(*)
      from public.analyses
      where status::text = 'pending'
        and photo_count = 0
        and queued_at is null
        and worker_started_at is null
        and created_at < now() - interval '24 hours'
    ),
    'failed_analyses_7d', (
      select count(*)
      from public.analyses
      where status::text = 'failed'
        and created_at >= now() - interval '7 days'
        and (failure_category = 'technical' or failure_category is null)
    ),
    'business_rejections_7d', (
      select count(*)
      from public.analyses
      where status::text = 'failed'
        and created_at >= now() - interval '7 days'
        and failure_category = 'business'
    ),
    'persistence_pending_over_5m', (
      select count(*)
      from public.ai_usage_logs
      where persistence_outcome = 'pending'
        and persistence_updated_at < now() - interval '5 minutes'
    ),
    'ambiguous_dispatches_24h', (
      select count(*)
      from private.analysis_job_events
      where event_type = 'dispatch_ambiguous_transport'
        and created_at >= now() - interval '24 hours'
    ),
    'ambiguous_then_first_attempt_completed_24h', (
      select count(distinct (a.analysis_id, a.job_generation, a.worker_attempt))
      from private.analysis_job_events a
      where a.event_type = 'dispatch_ambiguous_transport'
        and a.created_at >= now() - interval '24 hours'
        and exists (
          select 1
          from private.analysis_job_events f
          where f.analysis_id = a.analysis_id
            and f.job_generation = a.job_generation
            and f.worker_attempt = a.worker_attempt
            and f.event_type = 'finalized'
            and f.created_at >= a.created_at
        )
    ),
    'lease_expiry_retries_24h', (
      select count(*)
      from private.analysis_job_events
      where event_type = 'lease_expired_retry'
        and created_at >= now() - interval '24 hours'
    ),
    'analyses_with_multiple_successful_ai_calls_24h', (
      select count(*)
      from (
        select
          analysis_id,
          coalesce(job_mode, 'analysis') as logical_job_mode,
          coalesce(job_generation, 1) as logical_generation
        from public.ai_usage_logs
        where analysis_id is not null
          and error is null
          and created_at >= now() - interval '24 hours'
        group by
          analysis_id,
          coalesce(job_mode, 'analysis'),
          coalesce(job_generation, 1)
        having count(*) > 1
      ) duplicated_successes
    ),
    'discarded_lost_claim_24h', (
      select count(*)
      from public.ai_usage_logs
      where persistence_outcome = 'discarded'
        and persistence_error_code = 'lost_claim'
        and created_at >= now() - interval '24 hours'
    ),
    'analyses_with_coverage_repair_24h', (
      select count(distinct analysis_id)
      from public.ai_usage_logs
      where job_mode = 'repair'
        and created_at >= now() - interval '24 hours'
    ),
    'successful_coverage_repair_calls_24h', (
      select count(*)
      from public.ai_usage_logs
      where job_mode = 'repair'
        and error is null
        and created_at >= now() - interval '24 hours'
    ),
    'analyses_with_multiple_provider_requests_24h', (
      select count(distinct analysis_id)
      from public.ai_usage_logs
      where provider_request_count > 1
        and created_at >= now() - interval '24 hours'
    ),
    'coverage_contract_violations_24h', (
      select count(*)
      from public.ai_usage_logs
      where coverage_contract_outcome in (
          'normalized_contract_violation',
          'missing_records'
        )
        and created_at >= now() - interval '24 hours'
    ),
    'coverage_schema_fallbacks_24h', (
      select count(*)
      from public.ai_usage_logs
      where coverage_schema_fallback_used
        and created_at >= now() - interval '24 hours'
    ),
    'provider_attempt_total_tokens_24h', (
      select coalesce(sum(provider_attempt_total_tokens), 0)
      from public.ai_usage_logs
      where created_at >= now() - interval '24 hours'
    )
  );
$$;


ALTER FUNCTION "public"."admin_analysis_pipeline_metrics_v2"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_cohort_retention_matrix"("p_weeks" integer DEFAULT 8, "p_periods" integer DEFAULT 6) RETURNS TABLE("cohort_week" "date", "period_index" integer, "active_users" bigint, "cohort_size" bigint, "retention_rate" numeric)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with params as (
    select
      greatest(4, least(coalesce(p_weeks, 8), 16))::integer as weeks,
      greatest(1, least(coalesce(p_periods, 6), 8))::integer as periods
  ),
  cohorts as (
    select
      p.id as user_id,
      (date_trunc('week', p.created_at at time zone 'Europe/Istanbul'))::date as cohort_week
    from public.profiles p
    where p.created_at >= (
      date_trunc('week', now() at time zone 'Europe/Istanbul')::date
      - ((select weeks from params) * interval '7 days')
    )
  ),
  cohort_sizes as (
    select cohort_week, count(*)::bigint as cohort_size
    from cohorts
    group by cohort_week
  ),
  periods as (
    select generate_series(0, (select periods from params) - 1) as period_index
  ),
  activity_weeks as (
    select
      e.user_id,
      (date_trunc('week', e.ts at time zone 'Europe/Istanbul'))::date as activity_week
    from (
      select user_id, coalesce(completed_at, created_at) as ts
      from public.analyses
      where status = 'completed'
      union all
      select user_id, created_at from public.reports
    ) e
  ),
  matrix as (
    select
      c.cohort_week,
      p.period_index,
      count(distinct c.user_id) filter (where aw.user_id is not null)::bigint as active_users
    from cohorts c
    cross join periods p
    left join activity_weeks aw on aw.user_id = c.user_id
      and aw.activity_week = c.cohort_week + (p.period_index * 7)
    group by c.cohort_week, p.period_index
  )
  select
    m.cohort_week,
    m.period_index,
    m.active_users,
    cs.cohort_size,
    case
      when cs.cohort_size > 0
        then round((m.active_users::numeric / cs.cohort_size::numeric) * 100, 1)
      else 0
    end as retention_rate
  from matrix m
  join cohort_sizes cs on cs.cohort_week = m.cohort_week
  order by m.cohort_week desc, m.period_index asc;
$$;


ALTER FUNCTION "public"."admin_cohort_retention_matrix"("p_weeks" integer, "p_periods" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_cohort_summary"("p_weeks" integer DEFAULT 12) RETURNS TABLE("cohort_week" "date", "cohort_size" bigint, "activated_7d" bigint, "activated_30d" bigint, "paid_30d" bigint)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with params as (
    select greatest(4, least(coalesce(p_weeks, 12), 26))::integer as weeks
  ),
  cohorts as (
    select
      p.id as user_id,
      p.created_at,
      (date_trunc('week', p.created_at at time zone 'Europe/Istanbul'))::date as cohort_week
    from public.profiles p
    where p.created_at >= (
      date_trunc('week', now() at time zone 'Europe/Istanbul')::date
      - ((select weeks from params) * interval '7 days')
    )
  ),
  first_activation as (
    select
      a.user_id,
      min(coalesce(a.completed_at, a.created_at)) as first_active_at
    from public.analyses a
    where a.status = 'completed'
    group by a.user_id
  ),
  paid_within_30d as (
    select distinct c.user_id
    from cohorts c
    join public.user_subscriptions us on us.user_id = c.user_id
    where us.created_at <= c.created_at + interval '30 days'
      and us.status in ('active', 'trialing', 'past_due')
  )
  select
    c.cohort_week,
    count(distinct c.user_id)::bigint as cohort_size,
    count(distinct c.user_id) filter (
      where fa.first_active_at is not null
        and fa.first_active_at <= c.created_at + interval '7 days'
    )::bigint as activated_7d,
    count(distinct c.user_id) filter (
      where fa.first_active_at is not null
        and fa.first_active_at <= c.created_at + interval '30 days'
    )::bigint as activated_30d,
    count(distinct c.user_id) filter (
      where pw.user_id is not null
    )::bigint as paid_30d
  from cohorts c
  left join first_activation fa on fa.user_id = c.user_id
  left join paid_within_30d pw on pw.user_id = c.user_id
  group by c.cohort_week
  order by c.cohort_week desc;
$$;


ALTER FUNCTION "public"."admin_cohort_summary"("p_weeks" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_dashboard_daily_series"("p_days" integer DEFAULT 30) RETURNS TABLE("day" "date", "new_users" bigint, "analyses" bigint, "completed_analyses" bigint, "reports" bigint, "ai_calls" bigint, "ai_tokens" bigint, "support_requests" bigint)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with bounds as (
    select (
      (now() at time zone 'Europe/Istanbul')::date
      - (greatest(1, least(p_days, 90)) - 1)
    )::date as start_day,
    (now() at time zone 'Europe/Istanbul')::date as end_day
  ),
  days as (
    select generate_series(
      (select start_day from bounds),
      (select end_day from bounds),
      interval '1 day'
    )::date as day
  ),
  users_by_day as (
    select (created_at at time zone 'Europe/Istanbul')::date as day, count(*)::bigint as cnt
    from profiles, bounds
    where (created_at at time zone 'Europe/Istanbul')::date >= bounds.start_day
    group by 1
  ),
  analyses_by_day as (
    select (created_at at time zone 'Europe/Istanbul')::date as day, count(*)::bigint as cnt
    from analyses, bounds
    where (created_at at time zone 'Europe/Istanbul')::date >= bounds.start_day
    group by 1
  ),
  completed_by_day as (
    select (completed_at at time zone 'Europe/Istanbul')::date as day, count(*)::bigint as cnt
    from analyses, bounds
    where completed_at is not null
      and (completed_at at time zone 'Europe/Istanbul')::date >= bounds.start_day
    group by 1
  ),
  reports_by_day as (
    select (created_at at time zone 'Europe/Istanbul')::date as day, count(*)::bigint as cnt
    from reports, bounds
    where (created_at at time zone 'Europe/Istanbul')::date >= bounds.start_day
    group by 1
  ),
  ai_by_day as (
    select (created_at at time zone 'Europe/Istanbul')::date as day,
           count(*)::bigint as calls,
           coalesce(sum(total_tokens), 0)::bigint as tokens
    from ai_usage_logs, bounds
    where (created_at at time zone 'Europe/Istanbul')::date >= bounds.start_day
    group by 1
  ),
  support_by_day as (
    select (created_at at time zone 'Europe/Istanbul')::date as day, count(*)::bigint as cnt
    from support_requests, bounds
    where (created_at at time zone 'Europe/Istanbul')::date >= bounds.start_day
    group by 1
  )
  select
    d.day,
    coalesce(u.cnt, 0),
    coalesce(a.cnt, 0),
    coalesce(c.cnt, 0),
    coalesce(r.cnt, 0),
    coalesce(ai.calls, 0),
    coalesce(ai.tokens, 0),
    coalesce(s.cnt, 0)
  from days d
  left join users_by_day u on u.day = d.day
  left join analyses_by_day a on a.day = d.day
  left join completed_by_day c on c.day = d.day
  left join reports_by_day r on r.day = d.day
  left join ai_by_day ai on ai.day = d.day
  left join support_by_day s on s.day = d.day
  order by d.day;
$$;


ALTER FUNCTION "public"."admin_dashboard_daily_series"("p_days" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_data_quality_scan"() RETURNS TABLE("check_key" "text", "category" "text", "severity" "text", "issue_count" bigint, "description" "text", "sample_ids" "text"[])
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with stale_cutoff as (
    select now() - interval '15 minutes' as ts
  ),
  last7d as (
    select now() - interval '7 days' as ts
  ),
  checks as (
    select
      'subscription_inconsistency'::text as check_key,
      'subscriptions'::text as category,
      case
        when count(*) filter (where s.severity = 'high') > 0 then 'high'
        when count(*) > 0 then 'medium'
        else 'low'
      end as severity,
      count(*)::bigint as issue_count,
      'Profil planı ile RevenueCat abonelik kaydı uyuşmuyor'::text as description,
      coalesce(
        (
          select array_agg(s.user_id::text order by s.user_id)
          from (
            select user_id
            from public.admin_subscription_inconsistency_scan()
            limit 5
          ) s
        ),
        '{}'::text[]
      ) as sample_ids
    from public.admin_subscription_inconsistency_scan() s

    union all

    select
      'orphan_analyses',
      'analyses',
      'high',
      count(*)::bigint,
      'Profil kaydı olmayan kullanıcıya bağlı analizler',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select a.id
            from public.analyses a
            left join public.profiles p on p.id = a.user_id
            where p.id is null
            order by a.created_at desc
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.analyses a
    left join public.profiles p on p.id = a.user_id
    where p.id is null

    union all

    select
      'completed_no_findings',
      'analyses',
      'low',
      count(*)::bigint,
      'Tamamlanmış ancak bulgu sayısı sıfır analizler (30g)',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select id
            from public.analyses
            where status = 'completed'
              and coalesce(finding_count, 0) = 0
              and created_at >= now() - interval '30 days'
            order by created_at desc
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.analyses
    where status = 'completed'
      and coalesce(finding_count, 0) = 0
      and created_at >= now() - interval '30 days'

    union all

    select
      'stale_queue',
      'system',
      'high',
      count(*)::bigint,
      '15 dakikadan uzun süredir queued durumunda analizler',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select id
            from public.analyses, stale_cutoff sc
            where status = 'queued'
              and queued_at is not null
              and queued_at < sc.ts
            order by queued_at asc
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.analyses, stale_cutoff sc
    where status = 'queued'
      and queued_at is not null
      and queued_at < sc.ts

    union all

    select
      'profiles_missing_email',
      'profiles',
      'medium',
      count(*)::bigint,
      'E-posta alanı boş profiller',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select id
            from public.profiles
            where email is null or btrim(email) = ''
            order by created_at desc
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.profiles
    where email is null or btrim(email) = ''

    union all

    select
      'pending_deletion_backlog',
      'operations',
      'medium',
      count(*)::bigint,
      'Bekleyen veya işlenmekte olan hesap silme talepleri',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select id
            from public.account_deletion_requests
            where status in ('pending', 'processing')
            order by created_at asc
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.account_deletion_requests
    where status in ('pending', 'processing')

    union all

    select
      'ai_errors_7d',
      'ai',
      case
        when count(*) >= 50 then 'high'
        when count(*) >= 10 then 'medium'
        when count(*) > 0 then 'low'
        else 'low'
      end,
      count(*)::bigint,
      'Son 7 günde hata ile sonuçlanan AI çağrıları',
      '{}'::text[]
    from public.ai_usage_logs, last7d l
    where created_at >= l.ts
      and error is not null

    union all

    select
      'completion_push_backlog',
      'notifications',
      'low',
      count(*)::bigint,
      'Tamamlanmış analizlerde gönderilmemiş completion push (7g)',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select id
            from public.analyses, last7d l
            where status = 'completed'
              and completion_push_sent_at is null
              and completed_at >= l.ts
            order by completed_at desc
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.analyses, last7d l
    where status = 'completed'
      and completion_push_sent_at is null
      and completed_at >= l.ts

    union all

    select
      'paid_without_onboarding',
      'onboarding',
      'low',
      count(*)::bigint,
      'Plus/Pro profil ancak onboarding cevabı yok',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select p.id
            from public.profiles p
            left join public.user_onboarding_answers o on o.user_id = p.id
            where p.tier in ('plus', 'pro')
              and o.user_id is null
            order by p.created_at desc
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.profiles p
    left join public.user_onboarding_answers o on o.user_id = p.id
    where p.tier in ('plus', 'pro')
      and o.user_id is null

    union all

    select
      'photo_count_mismatch',
      'multi_photo',
      'medium',
      count(*)::bigint,
      'Analiz photo_count ile photos satır sayısı uyuşmuyor',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select a.id
            from public.analyses a
            left join lateral (
              select count(*)::integer as photo_rows
              from public.photos p
              where p.analysis_id = a.id
            ) pc on true
            where coalesce(a.photo_count, 0) != coalesce(pc.photo_rows, 0)
            order by a.created_at desc
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.analyses a
    left join lateral (
      select count(*)::integer as photo_rows
      from public.photos p
      where p.analysis_id = a.id
    ) pc on true
    where coalesce(a.photo_count, 0) != coalesce(pc.photo_rows, 0)

    union all

    select
      'missing_photo_summaries',
      'multi_photo',
      'medium',
      count(*)::bigint,
      'Tamamlanan çoklu foto analizde analysis_photo_summaries eksik',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select a.id
            from public.analyses a
            left join lateral (
              select count(*)::integer as summary_rows
              from public.analysis_photo_summaries s
              where s.analysis_id = a.id
            ) sc on true
            where a.status = 'completed'
              and coalesce(a.photo_count, 0) > 1
              and coalesce(sc.summary_rows, 0) < coalesce(a.photo_count, 0)
            order by a.completed_at desc nulls last
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.analyses a
    left join lateral (
      select count(*)::integer as summary_rows
      from public.analysis_photo_summaries s
      where s.analysis_id = a.id
    ) sc on true
    where a.status = 'completed'
      and coalesce(a.photo_count, 0) > 1
      and coalesce(sc.summary_rows, 0) < coalesce(a.photo_count, 0)

    union all

    select
      'coverage_gap_open',
      'multi_photo',
      case when count(*) >= 10 then 'high' when count(*) > 0 then 'medium' else 'low' end,
      count(*)::bigint,
      'Coverage gap/fail ve tamamlanmış analiz (7g)',
      coalesce(
        (
          select array_agg(x.analysis_id::text)
          from (
            select distinct s.analysis_id
            from public.analysis_photo_summaries s
            join public.analyses a on a.id = s.analysis_id
            join last7d l on true
            where a.status = 'completed'
              and a.completed_at >= l.ts
              and coalesce(s.coverage_status, '') in ('gap', 'fail')
            order by s.analysis_id
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.analysis_photo_summaries s
    join public.analyses a on a.id = s.analysis_id
    join last7d l on true
    where a.status = 'completed'
      and a.completed_at >= l.ts
      and coalesce(s.coverage_status, '') in ('gap', 'fail')

    union all

    select
      'edits_without_events',
      'findings_edit',
      'high',
      count(*)::bigint,
      'has_user_edits=true ancak finding_edit_events kaydı yok',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select a.id
            from public.analyses a
            where a.has_user_edits = true
              and not exists (
                select 1
                from public.finding_edit_events e
                where e.analysis_id = a.id
              )
            order by a.updated_at desc nulls last
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.analyses a
    where a.has_user_edits = true
      and not exists (
        select 1
        from public.finding_edit_events e
        where e.analysis_id = a.id
      )

    union all

    select
      'findings_count_drift',
      'findings_edit',
      'medium',
      count(*)::bigint,
      'visible_findings_count ile görünür bulgu sayısı uyuşmuyor',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select a.id
            from public.analyses a
            left join lateral (
              select count(*)::integer as visible_rows
              from public.findings f
              where f.analysis_id = a.id
                and coalesce(f.report_visibility, 'visible') = 'visible'
                and coalesce(f.is_user_deleted, false) = false
            ) fc on true
            where coalesce(a.visible_findings_count, -1) != coalesce(fc.visible_rows, 0)
            order by a.updated_at desc nulls last
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.analyses a
    left join lateral (
      select count(*)::integer as visible_rows
      from public.findings f
      where f.analysis_id = a.id
        and coalesce(f.report_visibility, 'visible') = 'visible'
        and coalesce(f.is_user_deleted, false) = false
    ) fc on true
    where coalesce(a.visible_findings_count, -1) != coalesce(fc.visible_rows, 0)

    union all

    select
      'report_snapshot_missing',
      'findings_edit',
      'medium',
      count(*)::bigint,
      'Yeni raporlarda findings_snapshot_json boş (30g)',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select r.id
            from public.reports r
            where r.created_at >= now() - interval '30 days'
              and (
                r.findings_snapshot_json is null
                or jsonb_typeof(r.findings_snapshot_json) is null
                or r.findings_snapshot_json = '[]'::jsonb
                or r.findings_snapshot_json = '{}'::jsonb
              )
            order by r.created_at desc
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.reports r
    where r.created_at >= now() - interval '30 days'
      and (
        r.findings_snapshot_json is null
        or jsonb_typeof(r.findings_snapshot_json) is null
        or r.findings_snapshot_json = '[]'::jsonb
        or r.findings_snapshot_json = '{}'::jsonb
      )
  )
  select
    c.check_key,
    c.category,
    c.severity,
    c.issue_count,
    c.description,
    c.sample_ids
  from checks c
  where c.issue_count > 0
  order by
    case c.severity
      when 'high' then 1
      when 'medium' then 2
      else 3
    end,
    c.issue_count desc,
    c.check_key;
$$;


ALTER FUNCTION "public"."admin_data_quality_scan"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_findings_analytics"("p_days" integer DEFAULT 30) RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with params as (
    select greatest(1, least(coalesce(p_days, 30), 90))::integer as days
  ),
  bounds as (
    select days, (now() - (days || ' days')::interval) as since
    from params
  ),
  scoped as (
    select f.*
    from public.findings f
    cross join bounds b
    where f.created_at >= b.since
  ),
  summary as (
    select
      count(*)::bigint as total_findings,
      count(*) filter (where not is_resolved)::bigint as unresolved_findings,
      count(*) filter (where is_resolved)::bigint as resolved_findings,
      count(*) filter (where photo_id is not null)::bigint as with_photo,
      count(*) filter (where bounding_box is not null)::bigint as with_bounding_box,
      round(avg(fk_score)::numeric, 2) as avg_fk_score,
      round(avg(m5_score)::numeric, 2) as avg_m5_score,
      count(distinct analysis_id)::bigint as analyses_with_findings
    from scoped
  ),
  fk_bands as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object('band', band, 'count', cnt)
        order by
          case band
            when 'critical' then 1
            when 'high' then 2
            when 'medium' then 3
            when 'low' then 4
            else 5
          end
      ),
      '[]'::jsonb
    ) as data
    from (
      select fk_band::text as band, count(*)::bigint as cnt
      from scoped
      group by fk_band
    ) t
  ),
  m5_bands as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object('band', band, 'count', cnt)
        order by
          case band
            when 'critical' then 1
            when 'high' then 2
            when 'medium' then 3
            when 'low' then 4
            else 5
          end
      ),
      '[]'::jsonb
    ) as data
    from (
      select m5_band::text as band, count(*)::bigint as cnt
      from scoped
      group by m5_band
    ) t
  ),
  top_categories as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'category', category,
          'count', cnt,
          'criticalCount', critical_cnt,
          'unresolvedCount', unresolved_cnt
        )
        order by cnt desc
      ),
      '[]'::jsonb
    ) as data
    from (
      select
        coalesce(nullif(trim(category), ''), 'Belirtilmemiş') as category,
        count(*)::bigint as cnt,
        count(*) filter (where fk_band = 'critical' or m5_band = 'critical')::bigint as critical_cnt,
        count(*) filter (where not is_resolved)::bigint as unresolved_cnt
      from scoped
      group by 1
      order by cnt desc
      limit 12
    ) t
  ),
  responsible_backlog as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object('responsible', responsible, 'unresolved', unresolved)
        order by unresolved desc
      ),
      '[]'::jsonb
    ) as data
    from (
      select
        coalesce(nullif(trim(responsible), ''), 'Belirtilmemiş') as responsible,
        count(*)::bigint as unresolved
      from scoped
      where not is_resolved
      group by 1
      order by unresolved desc
      limit 10
    ) t
  ),
  deadline_breakdown as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object('deadline', deadline, 'count', cnt, 'unresolved', unresolved)
        order by cnt desc
      ),
      '[]'::jsonb
    ) as data
    from (
      select
        coalesce(nullif(trim(deadline), ''), 'Belirtilmemiş') as deadline,
        count(*)::bigint as cnt,
        count(*) filter (where not is_resolved)::bigint as unresolved
      from scoped
      group by 1
      order by cnt desc
      limit 10
    ) t
  ),
  daily_trend as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'day', day,
          'total', total,
          'unresolved', unresolved,
          'critical', critical
        )
        order by day
      ),
      '[]'::jsonb
    ) as data
    from (
      select
        created_at::date as day,
        count(*)::bigint as total,
        count(*) filter (where not is_resolved)::bigint as unresolved,
        count(*) filter (where fk_band = 'critical' or m5_band = 'critical')::bigint as critical
      from scoped
      group by 1
      order by 1
    ) t
  )
  select jsonb_build_object(
    'days', (select days from bounds),
    'summary', (
      select jsonb_build_object(
        'totalFindings', total_findings,
        'unresolvedFindings', unresolved_findings,
        'resolvedFindings', resolved_findings,
        'withPhoto', with_photo,
        'withBoundingBox', with_bounding_box,
        'avgFkScore', avg_fk_score,
        'avgM5Score', avg_m5_score,
        'analysesWithFindings', analyses_with_findings
      )
      from summary
    ),
    'fkBands', (select data from fk_bands),
    'm5Bands', (select data from m5_bands),
    'topCategories', (select data from top_categories),
    'responsibleBacklog', (select data from responsible_backlog),
    'deadlineBreakdown', (select data from deadline_breakdown),
    'dailyTrend', (select data from daily_trend)
  );
$$;


ALTER FUNCTION "public"."admin_findings_analytics"("p_days" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_notification_mutation_v1"("p_actor_user_id" "uuid", "p_action" "text", "p_payload" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_action text := lower(btrim(coalesce(p_action, '')));
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_required_scope text;
  v_admin_email text;
  v_id uuid;
  v_rule_id uuid;
  v_rule_type text;
  v_template_id uuid;
  v_version_id uuid;
  v_version integer;
  v_status text;
  v_rollout_percentage integer;
  v_conditions jsonb;
  v_target_spec jsonb;
  v_result jsonb;
begin
  if jsonb_typeof(v_payload) <> 'object' then
    raise exception 'payload_must_be_object' using errcode = '22023';
  end if;

  v_required_scope := case
    when v_action in (
      'create_template',
      'update_template',
      'create_rule',
      'create_rule_version'
    )
      then 'notifications.rules.write'
    when v_action in (
      'set_rule_status',
      'set_campaign_status',
      'set_rollout'
    )
      then 'notifications.publish'
    when v_action = 'create_campaign'
      then 'notifications.campaigns.write'
    when v_action = 'set_kill_switch'
      then 'notifications.kill_switch'
    else null
  end;

  if v_required_scope is null then
    raise exception 'unsupported_notification_action' using errcode = '22023';
  end if;

  if not private.notification_admin_has_scope(
    p_actor_user_id,
    v_required_scope
  ) then
    raise exception 'admin_scope_required:%', v_required_scope
      using errcode = '42501';
  end if;

  select email into v_admin_email
  from public.admin_users
  where user_id = p_actor_user_id
    and is_active;

  if v_action = 'create_template' then
    insert into private.notification_templates (
      key,
      name,
      title,
      body,
      destination,
      status,
      variables,
      created_by
    )
    values (
      lower(btrim(v_payload->>'key')),
      left(btrim(v_payload->>'name'), 120),
      btrim(v_payload->>'title'),
      btrim(v_payload->>'body'),
      coalesce(nullif(v_payload->>'destination', ''), 'home'),
      coalesce(nullif(v_payload->>'status', ''), 'draft'),
      coalesce(v_payload->'variables', '[]'::jsonb),
      p_actor_user_id
    )
    returning id into v_id;
    v_result := jsonb_build_object('id', v_id, 'action', v_action);

  elsif v_action = 'update_template' then
    v_id := (v_payload->>'template_id')::uuid;
    if exists (
      select 1
      from private.notification_rules
      where template_id = v_id
        and status in ('shadow', 'allowlist', 'active')
    ) then
      raise exception 'active_template_requires_new_rule_version'
        using errcode = '55000';
    end if;

    update private.notification_templates
    set name = coalesce(
          nullif(left(btrim(v_payload->>'name'), 120), ''),
          name
        ),
        title = coalesce(
          nullif(btrim(v_payload->>'title'), ''),
          title
        ),
        body = coalesce(
          nullif(btrim(v_payload->>'body'), ''),
          body
        ),
        destination = coalesce(
          nullif(v_payload->>'destination', ''),
          destination
        ),
        status = coalesce(nullif(v_payload->>'status', ''), status),
        updated_at = now()
    where id = v_id
    returning id into v_rule_id;

    if v_rule_id is null then
      raise exception 'template_not_found' using errcode = 'P0002';
    end if;
    v_result := jsonb_build_object('id', v_id, 'action', v_action);

  elsif v_action = 'create_rule' then
    v_rule_type := lower(btrim(v_payload->>'rule_type'));
    v_template_id := (v_payload->>'template_id')::uuid;
    v_conditions := coalesce(v_payload->'conditions', '{}'::jsonb);

    if not private.notification_conditions_valid(
      v_rule_type,
      v_conditions
    ) then
      raise exception 'invalid_rule_conditions' using errcode = '22023';
    end if;

    if not exists (
      select 1
      from private.notification_templates
      where id = v_template_id
        and status <> 'archived'
    ) then
      raise exception 'template_not_found' using errcode = 'P0002';
    end if;

    insert into private.notification_rules (
      key,
      name,
      rule_type,
      status,
      template_id,
      priority,
      created_by
    )
    values (
      lower(btrim(v_payload->>'key')),
      left(btrim(v_payload->>'name'), 120),
      v_rule_type,
      'draft',
      v_template_id,
      greatest(
        1,
        least(coalesce((v_payload->>'priority')::integer, 100), 1000)
      ),
      p_actor_user_id
    )
    returning id into v_rule_id;

    insert into private.notification_rule_versions (
      rule_id,
      version,
      conditions,
      template_snapshot,
      enabled_user_hashes,
      created_by
    )
    select
      v_rule_id,
      1,
      v_conditions,
      jsonb_build_object(
        'template_id', t.id,
        'title', t.title,
        'body', t.body,
        'destination', t.destination
      ),
      coalesce(
        array(
          select jsonb_array_elements_text(
            coalesce(v_payload->'enabled_user_hashes', '[]'::jsonb)
          )
        ),
        '{}'::text[]
      ),
      p_actor_user_id
    from private.notification_templates t
    where t.id = v_template_id
    returning id into v_version_id;

    update private.notification_rules
    set current_version_id = v_version_id,
        updated_at = now()
    where id = v_rule_id;

    v_result := jsonb_build_object(
      'id', v_rule_id,
      'version_id', v_version_id,
      'action', v_action
    );

  elsif v_action = 'create_rule_version' then
    v_rule_id := (v_payload->>'rule_id')::uuid;
    select rule_type, template_id
    into v_rule_type, v_template_id
    from private.notification_rules
    where id = v_rule_id
      and status <> 'archived'
    for update;

    if not found then
      raise exception 'rule_not_found' using errcode = 'P0002';
    end if;

    v_template_id := coalesce(
      nullif(v_payload->>'template_id', '')::uuid,
      v_template_id
    );
    v_conditions := coalesce(v_payload->'conditions', '{}'::jsonb);

    if not private.notification_conditions_valid(
      v_rule_type,
      v_conditions
    ) then
      raise exception 'invalid_rule_conditions' using errcode = '22023';
    end if;

    select coalesce(max(version), 0) + 1
    into v_version
    from private.notification_rule_versions
    where rule_id = v_rule_id;

    insert into private.notification_rule_versions (
      rule_id,
      version,
      conditions,
      template_snapshot,
      enabled_user_hashes,
      created_by
    )
    select
      v_rule_id,
      v_version,
      v_conditions,
      jsonb_build_object(
        'template_id', t.id,
        'title', t.title,
        'body', t.body,
        'destination', t.destination
      ),
      coalesce(
        array(
          select jsonb_array_elements_text(
            coalesce(v_payload->'enabled_user_hashes', '[]'::jsonb)
          )
        ),
        '{}'::text[]
      ),
      p_actor_user_id
    from private.notification_templates t
    where t.id = v_template_id
      and t.status <> 'archived'
    returning id into v_version_id;

    if v_version_id is null then
      raise exception 'template_not_found' using errcode = 'P0002';
    end if;

    update private.notification_rules
    set current_version_id = v_version_id,
        template_id = v_template_id,
        status = 'draft',
        updated_at = now()
    where id = v_rule_id;

    update private.notification_jobs
    set status = 'cancelled',
        claim_token = null,
        claimed_at = null,
        lease_expires_at = null,
        completed_at = now(),
        last_error_code = 'rule_version_superseded',
        last_error_text = null,
        updated_at = now()
    where rule_id = v_rule_id
      and rule_version_id is distinct from v_version_id
      and status in ('pending', 'claimed');

    v_result := jsonb_build_object(
      'id', v_rule_id,
      'version_id', v_version_id,
      'version', v_version,
      'action', v_action
    );

  elsif v_action = 'set_rule_status' then
    v_rule_id := (v_payload->>'rule_id')::uuid;
    v_status := lower(btrim(v_payload->>'status'));
    if v_status not in (
      'shadow',
      'allowlist',
      'active',
      'paused',
      'archived'
    ) then
      raise exception 'invalid_rule_status' using errcode = '22023';
    end if;

    update private.notification_rules
    set status = v_status,
        updated_at = now()
    where id = v_rule_id
      and current_version_id is not null
    returning id into v_id;

    if v_id is null then
      raise exception 'rule_not_found' using errcode = 'P0002';
    end if;

    if v_status = 'paused' then
      update private.notification_jobs
      set status = 'pending',
          attempt_count = case
            when status = 'claimed' then greatest(attempt_count - 1, 0)
            else attempt_count
          end,
          claim_token = null,
          claimed_at = null,
          lease_expires_at = null,
          completed_at = null,
          last_error_code = 'rule_paused',
          updated_at = now()
      where rule_id = v_rule_id
        and status in ('pending', 'claimed');
    elsif v_status = 'archived' then
      update private.notification_jobs
      set status = 'cancelled',
          claim_token = null,
          claimed_at = null,
          lease_expires_at = null,
          completed_at = now(),
          last_error_code = 'rule_' || v_status,
          updated_at = now()
      where rule_id = v_rule_id
        and status in ('pending', 'claimed');
    else
      update private.notification_rule_versions
      set published_at = coalesce(published_at, now())
      where id = (
        select current_version_id
        from private.notification_rules
        where id = v_rule_id
      );
    end if;

    v_result := jsonb_build_object(
      'id', v_rule_id,
      'status', v_status,
      'action', v_action
    );

  elsif v_action = 'create_campaign' then
    v_target_spec := coalesce(
      v_payload->'target_spec',
      '{"audience":"allowlist","user_hashes":[]}'::jsonb
    );
    if jsonb_typeof(v_target_spec) <> 'object'
       or v_target_spec->>'audience' not in ('allowlist', 'all_eligible') then
      raise exception 'invalid_campaign_target_spec' using errcode = '22023';
    end if;

    if v_target_spec->>'audience' = 'allowlist'
       and (
         jsonb_typeof(v_target_spec->'user_hashes') <> 'array'
         or jsonb_array_length(v_target_spec->'user_hashes') > 1000
       ) then
      raise exception 'invalid_campaign_target_spec' using errcode = '22023';
    end if;

    insert into private.notification_campaigns (
      name,
      status,
      template_id,
      title,
      body,
      destination,
      target_spec,
      scheduled_at,
      created_by
    )
    values (
      left(btrim(v_payload->>'name'), 120),
      'draft',
      nullif(v_payload->>'template_id', '')::uuid,
      btrim(v_payload->>'title'),
      btrim(v_payload->>'body'),
      coalesce(nullif(v_payload->>'destination', ''), 'home'),
      v_target_spec,
      nullif(v_payload->>'scheduled_at', '')::timestamptz,
      p_actor_user_id
    )
    returning id into v_id;
    v_result := jsonb_build_object('id', v_id, 'action', v_action);

  elsif v_action = 'set_campaign_status' then
    v_id := (v_payload->>'campaign_id')::uuid;
    v_status := lower(btrim(v_payload->>'status'));
    if v_status not in ('scheduled', 'paused', 'cancelled', 'completed') then
      raise exception 'invalid_campaign_status' using errcode = '22023';
    end if;

    if v_status = 'completed'
       and exists (
         select 1
         from private.notification_jobs
         where campaign_id = v_id
           and status in ('pending', 'claimed')
       ) then
      raise exception 'campaign_has_unfinished_jobs' using errcode = '55000';
    end if;

    update private.notification_campaigns
    set status = v_status,
        scheduled_at = case
          when v_status = 'scheduled'
            then coalesce(
              nullif(v_payload->>'scheduled_at', '')::timestamptz,
              scheduled_at,
              now()
            )
          else scheduled_at
        end,
        completed_at = case
          when v_status in ('cancelled', 'completed') then now()
          else completed_at
        end,
        updated_at = now()
    where id = v_id
      and status not in ('completed', 'cancelled')
    returning id into v_rule_id;

    if v_rule_id is null then
      raise exception 'campaign_not_found_or_terminal' using errcode = 'P0002';
    end if;

    if v_status = 'paused' then
      update private.notification_jobs
      set status = 'pending',
          attempt_count = case
            when status = 'claimed' then greatest(attempt_count - 1, 0)
            else attempt_count
          end,
          claim_token = null,
          claimed_at = null,
          lease_expires_at = null,
          completed_at = null,
          last_error_code = 'campaign_paused',
          updated_at = now()
      where campaign_id = v_id
        and status in ('pending', 'claimed');
    elsif v_status = 'cancelled' then
      update private.notification_jobs
      set status = 'cancelled',
          claim_token = null,
          claimed_at = null,
          lease_expires_at = null,
          completed_at = now(),
          last_error_code = 'campaign_' || v_status,
          updated_at = now()
      where campaign_id = v_id
        and status in ('pending', 'claimed');
    end if;

    v_result := jsonb_build_object(
      'id', v_id,
      'status', v_status,
      'action', v_action
    );

  elsif v_action = 'set_kill_switch' then
    insert into public.app_feature_flags (key, value)
    values (
      'engagement_notification_automation',
      jsonb_build_object(
        'rollout_mode', 'off',
        'enabled_user_hashes', jsonb_build_array(),
        'kill_switch', coalesce((v_payload->>'enabled')::boolean, true)
      )
    )
    on conflict (key) do update set
      value = jsonb_set(
        public.app_feature_flags.value,
        '{kill_switch}',
        to_jsonb(coalesce((v_payload->>'enabled')::boolean, true)),
        true
      ),
      updated_at = now();

    if coalesce((v_payload->>'enabled')::boolean, true) then
      update private.notification_jobs
      set status = 'pending',
          attempt_count = case
            when status = 'claimed' then greatest(attempt_count - 1, 0)
            else attempt_count
          end,
          claim_token = null,
          claimed_at = null,
          lease_expires_at = null,
          completed_at = null,
          last_error_code = 'global_kill_switch',
          updated_at = now()
      where status in ('pending', 'claimed');
    end if;

    v_result := jsonb_build_object(
      'enabled', coalesce((v_payload->>'enabled')::boolean, true),
      'action', v_action
    );

  elsif v_action = 'set_rollout' then
    v_status := lower(btrim(v_payload->>'rollout_mode'));
    if v_status not in ('off', 'allowlist', 'on') then
      raise exception 'invalid_rollout_mode' using errcode = '22023';
    end if;

    v_rollout_percentage := case
      when v_status = 'on'
        then coalesce((v_payload->>'rollout_percentage')::integer, 100)
      else 0
    end;
    if v_rollout_percentage not between 0 and 100 then
      raise exception 'invalid_rollout_percentage' using errcode = '22023';
    end if;

    if jsonb_typeof(
      coalesce(v_payload->'enabled_user_hashes', '[]'::jsonb)
    ) <> 'array'
       or jsonb_array_length(
         coalesce(v_payload->'enabled_user_hashes', '[]'::jsonb)
       ) > 1000 then
      raise exception 'invalid_rollout_allowlist' using errcode = '22023';
    end if;

    insert into public.app_feature_flags (key, value)
    values (
      'engagement_notification_automation',
      jsonb_build_object(
        'rollout_mode', v_status,
        'enabled_user_hashes',
          coalesce(v_payload->'enabled_user_hashes', '[]'::jsonb),
        'rollout_percentage', v_rollout_percentage,
        'kill_switch', false
      )
    )
    on conflict (key) do update set
      value = jsonb_set(
        jsonb_set(
          jsonb_set(
            public.app_feature_flags.value,
            '{rollout_mode}',
            to_jsonb(v_status),
            true
          ),
          '{enabled_user_hashes}',
          coalesce(v_payload->'enabled_user_hashes', '[]'::jsonb),
          true
        ),
        '{rollout_percentage}',
        to_jsonb(v_rollout_percentage),
        true
      ),
      updated_at = now();

    if v_status = 'off' then
      update private.notification_jobs
      set status = 'pending',
          attempt_count = case
            when status = 'claimed' then greatest(attempt_count - 1, 0)
            else attempt_count
          end,
          claim_token = null,
          claimed_at = null,
          lease_expires_at = null,
          completed_at = null,
          last_error_code = 'rollout_off',
          updated_at = now()
      where status in ('pending', 'claimed');
    end if;

    v_result := jsonb_build_object(
      'rollout_mode', v_status,
      'rollout_percentage', v_rollout_percentage,
      'action', v_action
    );
  end if;

  insert into public.admin_audit_logs (
    admin_user_id,
    admin_email,
    action,
    target_type,
    target_id,
    metadata
  )
  values (
    p_actor_user_id,
    v_admin_email,
    'notifications.' || v_action,
    case
      when v_action like '%rule%' then 'notification_rule'
      when v_action like '%campaign%' then 'notification_campaign'
      when v_action in ('create_template', 'update_template')
        then 'notification_template'
      else 'notification_automation'
    end,
    coalesce(
      v_result->>'id',
      v_result->>'enabled',
      'global'
    ),
    jsonb_build_object(
      'action', v_action,
      'status', v_result->>'status',
      'version', v_result->>'version'
    )
  );

  return v_result;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'invalid_notification_payload'
      using errcode = '22023';
end;
$$;


ALTER FUNCTION "public"."admin_notification_mutation_v1"("p_actor_user_id" "uuid", "p_action" "text", "p_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_notification_preview_v1"("p_actor_user_id" "uuid", "p_rule_id" "uuid" DEFAULT NULL::"uuid", "p_campaign_id" "uuid" DEFAULT NULL::"uuid", "p_now" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_rule_type text;
  v_conditions jsonb;
  v_target_spec jsonb;
  v_count bigint := 0;
begin
  if not private.notification_admin_has_scope(
    p_actor_user_id,
    'notifications.read'
  ) then
    raise exception 'admin_scope_required:notifications.read'
      using errcode = '42501';
  end if;

  if (p_rule_id is null) = (p_campaign_id is null) then
    raise exception 'exactly_one_preview_target_required'
      using errcode = '22023';
  end if;

  if p_rule_id is not null then
    select r.rule_type, rv.conditions
    into v_rule_type, v_conditions
    from private.notification_rules r
    join private.notification_rule_versions rv
      on rv.id = r.current_version_id
    where r.id = p_rule_id;

    if not found then
      raise exception 'rule_not_found' using errcode = 'P0002';
    end if;

    if v_rule_type = 'first_analysis' then
      select count(*) into v_count
      from public.user_engagement_state e
      join auth.users u on u.id = e.user_id
      left join public.user_onboarding_answers o on o.user_id = e.user_id
      join public.notification_preferences p on p.user_id = e.user_id
      where p.enabled
        and p.app_reminders
        and e.authorization_status in ('authorized', 'provisional', 'ephemeral')
        and exists (
          select 1
          from public.push_device_tokens dt
          where dt.user_id = e.user_id
            and dt.environment = 'production'
            and dt.notifications_enabled
        )
        and p_now >= coalesce(o.completed_at, u.created_at)
          + (v_conditions->>'min_hours')::numeric * interval '1 hour'
        and p_now < coalesce(o.completed_at, u.created_at)
          + (v_conditions->>'max_hours')::numeric * interval '1 hour'
        and not exists (
          select 1
          from public.analyses a
          where a.user_id = e.user_id
            and (
              a.status::text <> 'pending'
              or a.queued_at is not null
              or a.worker_started_at is not null
            )
        );
    else
      select count(*) into v_count
      from public.user_engagement_state e
      join public.notification_preferences p on p.user_id = e.user_id
      where p.enabled
        and p.app_reminders
        and e.authorization_status in ('authorized', 'provisional', 'ephemeral')
        and exists (
          select 1
          from public.push_device_tokens dt
          where dt.user_id = e.user_id
            and dt.environment = 'production'
            and dt.notifications_enabled
        )
        and exists (
          select 1
          from public.analyses a
          where a.user_id = e.user_id
            and a.status::text = 'completed'
        )
        and e.last_foreground_at <= p_now
          - (v_conditions->>'inactivity_days')::numeric * interval '1 day';
    end if;
  else
    select target_spec into v_target_spec
    from private.notification_campaigns
    where id = p_campaign_id;

    if not found then
      raise exception 'campaign_not_found' using errcode = 'P0002';
    end if;

    select count(*) into v_count
    from public.user_engagement_state e
    join public.notification_preferences p on p.user_id = e.user_id
    where p.enabled
      and p.app_reminders
      and e.authorization_status in ('authorized', 'provisional', 'ephemeral')
      and exists (
        select 1
        from public.push_device_tokens dt
        where dt.user_id = e.user_id
          and dt.environment = 'production'
          and dt.notifications_enabled
      )
      and (
        v_target_spec->>'audience' = 'all_eligible'
        or (
          v_target_spec->>'audience' = 'allowlist'
          and coalesce(v_target_spec->'user_hashes', '[]'::jsonb)
            ? private.notification_user_hash(e.user_id)
        )
      );
  end if;

  return jsonb_build_object(
    'eligible_count', v_count,
    'evaluated_at', p_now,
    'note', 'Preview excludes final send-time revalidation and frequency deferrals.'
  );
end;
$$;


ALTER FUNCTION "public"."admin_notification_preview_v1"("p_actor_user_id" "uuid", "p_rule_id" "uuid", "p_campaign_id" "uuid", "p_now" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_notification_snapshot_v1"("p_actor_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
begin
  if not private.notification_admin_has_scope(
    p_actor_user_id,
    'notifications.read'
  ) then
    raise exception 'admin_scope_required:notifications.read'
      using errcode = '42501';
  end if;

  select jsonb_build_object(
    'feature_flag', private.notification_feature_flag(),
    'rules', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'key', r.key,
            'name', r.name,
            'rule_type', r.rule_type,
            'status', r.status,
            'priority', r.priority,
            'template_id', r.template_id,
            'current_version_id', r.current_version_id,
            'version', rv.version,
            'conditions', rv.conditions,
            'enabled_user_hashes', rv.enabled_user_hashes,
            'updated_at', r.updated_at
          )
          order by r.priority, r.created_at
        )
        from private.notification_rules r
        left join private.notification_rule_versions rv
          on rv.id = r.current_version_id
      ),
      '[]'::jsonb
    ),
    'templates', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', t.id,
            'key', t.key,
            'name', t.name,
            'title', t.title,
            'body', t.body,
            'destination', t.destination,
            'status', t.status,
            'updated_at', t.updated_at
          )
          order by t.key
        )
        from private.notification_templates t
      ),
      '[]'::jsonb
    ),
    'campaigns', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', c.id,
            'name', c.name,
            'status', c.status,
            'title', c.title,
            'body', c.body,
            'destination', c.destination,
            'target_spec', c.target_spec,
            'scheduled_at', c.scheduled_at,
            'started_at', c.started_at,
            'completed_at', c.completed_at,
            'created_at', c.created_at
          )
          order by c.created_at desc
        )
        from private.notification_campaigns c
        where c.created_at > now() - interval '180 days'
      ),
      '[]'::jsonb
    ),
    'metrics', jsonb_build_object(
      'jobs_24h', (
        select count(*)
        from private.notification_jobs
        where created_at > now() - interval '24 hours'
      ),
      'sent_24h', (
        select count(*)
        from private.notification_jobs
        where status = 'sent'
          and completed_at > now() - interval '24 hours'
      ),
      'skipped_24h', (
        select count(*)
        from private.notification_jobs
        where status = 'skipped'
          and completed_at > now() - interval '24 hours'
      ),
      'failed_24h', (
        select count(*)
        from private.notification_jobs
        where status in ('failed', 'ambiguous')
          and completed_at > now() - interval '24 hours'
      ),
      'pending', (
        select count(*)
        from private.notification_jobs
        where status in ('pending', 'claimed')
      ),
      'apns_accepted_24h', (
        select count(*)
        from private.notification_delivery_attempts
        where outcome = 'accepted'
          and created_at > now() - interval '24 hours'
      ),
      'apns_permanent_24h', (
        select count(*)
        from private.notification_delivery_attempts
        where outcome = 'permanent'
          and created_at > now() - interval '24 hours'
      ),
      'apns_transient_24h', (
        select count(*)
        from private.notification_delivery_attempts
        where outcome = 'transient'
          and created_at > now() - interval '24 hours'
      ),
      'apns_ambiguous_24h', (
        select count(*)
        from private.notification_delivery_attempts
        where outcome = 'ambiguous'
          and created_at > now() - interval '24 hours'
      ),
      'opened_24h', (
        select count(*)
        from public.notification_events
        where opened_at > now() - interval '24 hours'
      )
    )
  ) into v_result;

  return v_result;
end;
$$;


ALTER FUNCTION "public"."admin_notification_snapshot_v1"("p_actor_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_pgmq_queue_messages"("p_limit" integer DEFAULT 20) RETURNS TABLE("msg_id" bigint, "enqueued_at" timestamp with time zone, "read_ct" integer, "vt" timestamp with time zone, "analysis_id" "uuid", "is_stuck" boolean, "is_visibility_expired" boolean)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pgmq'
    AS $$
  select
    m.msg_id,
    m.enqueued_at,
    m.read_ct,
    m.vt,
    nullif(m.message ->> 'analysis_id', '')::uuid as analysis_id,
    (m.read_ct >= 3) as is_stuck,
    (m.vt <= now()) as is_visibility_expired
  from pgmq.q_analysis_jobs m
  order by m.enqueued_at asc
  limit greatest(1, least(coalesce(p_limit, 20), 50));
$$;


ALTER FUNCTION "public"."admin_pgmq_queue_messages"("p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_pgmq_queue_metrics"() RETURNS TABLE("queue_name" "text", "depth" bigint, "archive_depth" bigint, "oldest_enqueued_at" timestamp with time zone, "oldest_age_seconds" bigint, "max_read_count" integer, "stuck_messages" bigint, "visibility_expired" bigint)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pgmq'
    AS $$
  select
    'analysis_jobs'::text as queue_name,
    (select count(*)::bigint from pgmq.q_analysis_jobs) as depth,
    (select count(*)::bigint from pgmq.a_analysis_jobs) as archive_depth,
    (select min(enqueued_at) from pgmq.q_analysis_jobs) as oldest_enqueued_at,
    (
      select extract(epoch from (now() - min(enqueued_at)))::bigint
      from pgmq.q_analysis_jobs
    ) as oldest_age_seconds,
    (select coalesce(max(read_ct), 0) from pgmq.q_analysis_jobs) as max_read_count,
    (
      select count(*)::bigint
      from pgmq.q_analysis_jobs
      where read_ct >= 3
    ) as stuck_messages,
    (
      select count(*)::bigint
      from pgmq.q_analysis_jobs
      where vt <= now()
    ) as visibility_expired;
$$;


ALTER FUNCTION "public"."admin_pgmq_queue_metrics"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_recent_sign_ins"("p_limit" integer DEFAULT 5) RETURNS TABLE("user_id" "uuid", "email" "text", "last_sign_in_at" timestamp with time zone, "last_activity_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'auth', 'public'
    AS $$
  with per_user as (
    select
      u.id as user_id,
      u.email::text as email,
      u.last_sign_in_at,
      greatest(
        coalesce(u.last_sign_in_at, '-infinity'::timestamptz),
        coalesce(
          (select max(a.created_at) from public.analyses a where a.user_id = u.id),
          '-infinity'::timestamptz
        ),
        coalesce(
          (select max(r.created_at) from public.reports r where r.user_id = u.id),
          '-infinity'::timestamptz
        ),
        coalesce(
          (select max(e.created_at) from public.usage_events e where e.user_id = u.id),
          '-infinity'::timestamptz
        )
      ) as last_activity_at
    from auth.users u
  )
  select
    user_id,
    email,
    last_sign_in_at,
    last_activity_at
  from per_user
  where last_activity_at > '-infinity'::timestamptz
  order by last_activity_at desc
  limit greatest(1, least(coalesce(p_limit, 5), 20));
$$;


ALTER FUNCTION "public"."admin_recent_sign_ins"("p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_subscription_inconsistency_scan"() RETURNS TABLE("user_id" "uuid", "email" "text", "full_name" "text", "profile_tier" "text", "subscription_tier" "text", "subscription_status" "text", "current_period_ends_at" timestamp with time zone, "subscription_updated_at" timestamp with time zone, "issue_type" "text", "severity" "text", "description" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with joined as (
    select
      p.id as user_id,
      p.email,
      p.full_name,
      coalesce(p.tier::text, 'free') as profile_tier,
      us.tier as subscription_tier,
      us.status as subscription_status,
      us.current_period_ends_at,
      us.updated_at as subscription_updated_at
    from public.profiles p
    left join public.user_subscriptions us on us.user_id = p.id
  ),
  classified as (
    select
      j.*,
      case
        when j.subscription_tier is null and j.profile_tier in ('plus', 'pro')
          then 'missing_subscription'
        when j.subscription_tier is not null and j.profile_tier is distinct from j.subscription_tier
          then 'tier_mismatch'
        when j.profile_tier = 'free'
          and j.subscription_tier in ('plus', 'pro')
          and j.subscription_status in ('active', 'trialing', 'grace_period')
          then 'active_sub_profile_free'
        when j.profile_tier in ('plus', 'pro')
          and (
            j.subscription_tier is null
            or j.subscription_status is null
            or j.subscription_status not in ('active', 'trialing', 'grace_period')
          )
          then 'profile_paid_inactive_sub'
        else null
      end as issue_type
    from joined j
  )
  select
    c.user_id,
    c.email,
    c.full_name,
    c.profile_tier,
    coalesce(c.subscription_tier, '—') as subscription_tier,
    coalesce(c.subscription_status, 'missing') as subscription_status,
    c.current_period_ends_at,
    c.subscription_updated_at,
    c.issue_type,
    case
      when c.issue_type in ('missing_subscription', 'tier_mismatch', 'active_sub_profile_free')
        then 'high'
      else 'medium'
    end as severity,
    case c.issue_type
      when 'missing_subscription'
        then 'Profil ücretli plan gösteriyor ancak abonelik kaydı yok'
      when 'tier_mismatch'
        then 'Profil planı ile RevenueCat abonelik planı uyuşmuyor'
      when 'active_sub_profile_free'
        then 'Aktif ücretli abonelik var ancak profil Free görünüyor'
      when 'profile_paid_inactive_sub'
        then 'Profil ücretli plan gösteriyor ancak abonelik aktif değil'
      else 'Bilinmeyen tutarsızlık'
    end as description
  from classified c
  where c.issue_type is not null
  order by
    case c.issue_type
      when 'missing_subscription' then 1
      when 'active_sub_profile_free' then 2
      when 'tier_mismatch' then 3
      else 4
    end,
    c.subscription_updated_at desc nulls last;
$$;


ALTER FUNCTION "public"."admin_subscription_inconsistency_scan"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_user_segments_list"("p_segment" "text", "p_limit" integer DEFAULT 20, "p_offset" integer DEFAULT 0) RETURNS TABLE("user_id" "uuid", "email" "text", "full_name" "text", "tier" "text", "last_activity_at" timestamp with time zone, "activity_score_30d" bigint, "completed_analyses_30d" bigint, "reports_30d" bigint, "subscription_status" "text", "segment" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with bounds as (
    select
      now() - interval '30 days' as d30,
      now() - interval '90 days' as d90
  ),
  last_activity as (
    select user_id, max(ts) as last_ts
    from (
      select user_id, created_at as ts from public.analyses
      union all
      select user_id, created_at from public.reports
      union all
      select user_id, created_at from public.ai_usage_logs
      union all
      select user_id, created_at from public.usage_events
    ) events
    group by user_id
  ),
  metrics as (
    select
      p.id as user_id,
      p.email,
      p.full_name,
      p.tier,
      p.created_at,
      la.last_ts as last_activity_at,
      (
        select count(*)::bigint
        from public.analyses ax
        where ax.user_id = p.id
          and ax.status = 'completed'
          and ax.created_at >= (select d30 from bounds)
      ) as completed_analyses_30d,
      (
        select count(*)::bigint
        from public.reports rx
        where rx.user_id = p.id
          and rx.created_at >= (select d30 from bounds)
      ) as reports_30d,
      (
        select count(*)::bigint
        from public.ai_usage_logs al
        where al.user_id = p.id
          and al.created_at >= (select d30 from bounds)
      ) as ai_calls_30d,
      us.status as subscription_status,
      case
        when (
          (
            select count(*)
            from public.analyses ax
            where ax.user_id = p.id
              and ax.status = 'completed'
              and ax.created_at >= (select d30 from bounds)
          ) >= 5
          or (
            select count(*)
            from public.reports rx
            where rx.user_id = p.id
              and rx.created_at >= (select d30 from bounds)
          ) >= 3
          or (
            (
              select count(*)
              from public.analyses ax
              where ax.user_id = p.id
                and ax.status = 'completed'
                and ax.created_at >= (select d30 from bounds)
            ) * 3
            + (
              select count(*)
              from public.reports rx
              where rx.user_id = p.id
                and rx.created_at >= (select d30 from bounds)
            ) * 2
            + (
              select count(*)
              from public.ai_usage_logs al
              where al.user_id = p.id
                and al.created_at >= (select d30 from bounds)
            )
          ) >= 8
        ) then 'power_user'
        when p.tier in ('plus', 'pro')
          and coalesce(la.last_ts, p.created_at) < (select d30 from bounds)
          and la.last_ts is not null
          and la.last_ts >= (select d90 from bounds)
          then 'churn_risk_paid'
        when p.tier = 'free'
          and exists (
            select 1
            from public.analyses ax
            where ax.user_id = p.id
              and ax.status = 'completed'
          )
          and coalesce(la.last_ts, p.created_at) < (select d30 from bounds)
          then 'churn_risk_inactive'
        when p.created_at < (select d30 from bounds)
          and not exists (
            select 1
            from public.analyses ax
            where ax.user_id = p.id
              and ax.status = 'completed'
          )
          then 'dormant'
        else null
      end as segment
    from public.profiles p
    left join last_activity la on la.user_id = p.id
    left join public.user_subscriptions us on us.user_id = p.id
  )
  select
    m.user_id,
    m.email,
    m.full_name,
    m.tier,
    m.last_activity_at,
    (m.completed_analyses_30d * 3 + m.reports_30d * 2 + m.ai_calls_30d) as activity_score_30d,
    m.completed_analyses_30d,
    m.reports_30d,
    coalesce(m.subscription_status, 'missing') as subscription_status,
    m.segment
  from metrics m
  where m.segment = p_segment
  order by
    case p_segment
      when 'power_user' then m.completed_analyses_30d * 3 + m.reports_30d * 2 + m.ai_calls_30d
      else 0
    end desc,
    m.last_activity_at asc nulls last
  limit greatest(1, least(coalesce(p_limit, 20), 50))
  offset greatest(coalesce(p_offset, 0), 0);
$$;


ALTER FUNCTION "public"."admin_user_segments_list"("p_segment" "text", "p_limit" integer, "p_offset" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_user_segments_summary"() RETURNS TABLE("power_users" bigint, "churn_risk_paid" bigint, "churn_risk_inactive" bigint, "dormant" bigint, "activated" bigint)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with bounds as (
    select
      now() - interval '30 days' as d30,
      now() - interval '90 days' as d90
  ),
  last_activity as (
    select user_id, max(ts) as last_ts
    from (
      select user_id, created_at as ts from public.analyses
      union all
      select user_id, created_at from public.reports
      union all
      select user_id, created_at from public.ai_usage_logs
      union all
      select user_id, created_at from public.usage_events
    ) events
    group by user_id
  ),
  activity_30d as (
    select user_id, count(*)::bigint as events_30d
    from (
      select user_id from public.analyses
      where status = 'completed' and created_at >= (select d30 from bounds)
      union all
      select user_id from public.reports
      where created_at >= (select d30 from bounds)
      union all
      select user_id from public.ai_usage_logs
      where created_at >= (select d30 from bounds)
    ) recent
    group by user_id
  ),
  completed_ever as (
    select distinct user_id
    from public.analyses
    where status = 'completed'
  ),
  classified as (
    select
      p.id,
      case
        when coalesce(a30.events_30d, 0) >= 8
          or (
            select count(*)
            from public.analyses ax
            where ax.user_id = p.id
              and ax.status = 'completed'
              and ax.created_at >= (select d30 from bounds)
          ) >= 5
          or (
            select count(*)
            from public.reports rx
            where rx.user_id = p.id
              and rx.created_at >= (select d30 from bounds)
          ) >= 3
          then 'power_user'
        when p.tier in ('plus', 'pro')
          and coalesce(la.last_ts, p.created_at) < (select d30 from bounds)
          and la.last_ts is not null
          and la.last_ts >= (select d90 from bounds)
          then 'churn_risk_paid'
        when p.tier = 'free'
          and ce.user_id is not null
          and coalesce(la.last_ts, p.created_at) < (select d30 from bounds)
          then 'churn_risk_inactive'
        when p.created_at < (select d30 from bounds)
          and ce.user_id is null
          then 'dormant'
        else null
      end as segment
    from public.profiles p
    left join last_activity la on la.user_id = p.id
    left join activity_30d a30 on a30.user_id = p.id
    left join completed_ever ce on ce.user_id = p.id
  )
  select
    count(*) filter (where c.segment = 'power_user')::bigint as power_users,
    count(*) filter (where c.segment = 'churn_risk_paid')::bigint as churn_risk_paid,
    count(*) filter (where c.segment = 'churn_risk_inactive')::bigint as churn_risk_inactive,
    count(*) filter (where c.segment = 'dormant')::bigint as dormant,
    (select count(*)::bigint from completed_ever) as activated
  from classified c;
$$;


ALTER FUNCTION "public"."admin_user_segments_summary"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_and_consume_quota"("p_user_id" "uuid") RETURNS TABLE("allowed" boolean, "remaining" integer, "tier" "public"."subscription_tier")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_tier subscription_tier;
  v_used int;
  v_reset date;
  v_limit int := 5;
begin
  select p.tier, p.daily_quota_used, p.daily_quota_reset_at
    into v_tier, v_used, v_reset
  from public.profiles p
  where p.id = p_user_id
  for update;

  if not found then
    return query select false, 0, 'free'::subscription_tier;
    return;
  end if;

  if v_tier = 'pro' then
    return query select true, 9999, v_tier;
    return;
  end if;

  if v_reset < current_date then
    update public.profiles p
       set daily_quota_used = 0,
           daily_quota_reset_at = current_date
     where p.id = p_user_id;
    v_used := 0;
  end if;

  if v_used >= v_limit then
    return query select false, 0, v_tier;
    return;
  end if;

  update public.profiles p
     set daily_quota_used = p.daily_quota_used + 1
   where p.id = p_user_id;

  return query select true, (v_limit - v_used - 1), v_tier;
end;
$$;


ALTER FUNCTION "public"."check_and_consume_quota"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_support_request_rate_limit"("p_user_id" "uuid", "p_hour_limit" integer DEFAULT 5, "p_day_limit" integer DEFAULT 20) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
declare
  v_now timestamptz := now();
  v_hour_start timestamptz := date_trunc('hour', now());
  v_day_start timestamptz := date_trunc('day', now());
  v_row private.support_request_rate_limits%rowtype;
  v_retry integer;
begin
  if p_user_id is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'validation_failed',
      'retry_after_seconds', 60
    );
  end if;

  perform pg_advisory_xact_lock(hashtext(p_user_id::text || ':support_rate_limit'));

  insert into private.support_request_rate_limits (
    user_id,
    hour_window_start,
    hour_count,
    day_window_start,
    day_count
  ) values (
    p_user_id,
    v_hour_start,
    0,
    v_day_start,
    0
  )
  on conflict (user_id) do nothing;

  select *
    into v_row
  from private.support_request_rate_limits
  where user_id = p_user_id
  for update;

  if v_row.hour_window_start < v_hour_start then
    v_row.hour_window_start := v_hour_start;
    v_row.hour_count := 0;
  end if;

  if v_row.day_window_start < v_day_start then
    v_row.day_window_start := v_day_start;
    v_row.day_count := 0;
  end if;

  if v_row.hour_count >= greatest(p_hour_limit, 1) then
    v_retry := greatest(
      60,
      ceil(extract(epoch from (v_row.hour_window_start + interval '1 hour' - v_now)))::integer
    );
    update private.support_request_rate_limits
    set hour_window_start = v_row.hour_window_start,
        hour_count = v_row.hour_count,
        day_window_start = v_row.day_window_start,
        day_count = v_row.day_count,
        updated_at = v_now
    where user_id = p_user_id;
    return jsonb_build_object(
      'ok', false,
      'code', 'support_hourly_rate_limited',
      'retry_after_seconds', v_retry
    );
  end if;

  if v_row.day_count >= greatest(p_day_limit, 1) then
    v_retry := greatest(
      60,
      ceil(extract(epoch from (v_row.day_window_start + interval '1 day' - v_now)))::integer
    );
    update private.support_request_rate_limits
    set hour_window_start = v_row.hour_window_start,
        hour_count = v_row.hour_count,
        day_window_start = v_row.day_window_start,
        day_count = v_row.day_count,
        updated_at = v_now
    where user_id = p_user_id;
    return jsonb_build_object(
      'ok', false,
      'code', 'support_daily_rate_limited',
      'retry_after_seconds', v_retry
    );
  end if;

  update private.support_request_rate_limits
  set hour_window_start = v_row.hour_window_start,
      hour_count = v_row.hour_count + 1,
      day_window_start = v_row.day_window_start,
      day_count = v_row.day_count + 1,
      updated_at = v_now
  where user_id = p_user_id;

  return jsonb_build_object(
    'ok', true,
    'hour_limit', greatest(p_hour_limit, 1),
    'hour_used', v_row.hour_count + 1,
    'day_limit', greatest(p_day_limit, 1),
    'day_used', v_row.day_count + 1
  );
end;
$$;


ALTER FUNCTION "public"."check_support_request_rate_limit"("p_user_id" "uuid", "p_hour_limit" integer, "p_day_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."claim_analysis_job_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_job_mode" "text", "p_lease_seconds" integer DEFAULT 300, "p_max_attempts" integer DEFAULT 3) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_analysis public.analyses%rowtype;
  v_state private.analysis_job_state%rowtype;
  v_token uuid;
  v_attempt integer;
  v_claim_reason text;
  v_lease_seconds integer := greatest(
    30,
    least(coalesce(p_lease_seconds, 300), 900)
  );
begin
  select * into v_analysis
  from public.analyses
  where id = p_analysis_id and user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'state', 'analysis_not_found');
  end if;
  if v_analysis.status::text = 'completed' then
    return jsonb_build_object('ok', false, 'state', 'completed');
  end if;
  if v_analysis.status::text = 'failed' then
    return jsonb_build_object('ok', false, 'state', 'failed');
  end if;

  select * into v_state
  from private.analysis_job_state
  where analysis_id = p_analysis_id and user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'state', 'job_state_missing');
  end if;
  if v_state.active_msg_id is distinct from p_msg_id
    or v_state.generation is distinct from p_generation
    or v_state.job_mode is distinct from (
      case when p_job_mode = 'repair' then 'repair' else 'analysis' end
    )
  then
    return jsonb_build_object('ok', false, 'state', 'superseded');
  end if;

  if v_state.claim_token is not null
    and v_state.lease_expires_at is not null
    and v_state.lease_expires_at > now()
  then
    return jsonb_build_object(
      'ok', false,
      'state', 'busy',
      'retry_after_seconds', greatest(
        1,
        ceil(extract(epoch from (v_state.lease_expires_at - now())))::integer
      ),
      'worker_attempt', v_state.worker_attempt_count
    );
  end if;

  if v_state.worker_attempt_count >= greatest(
    1,
    least(coalesce(p_max_attempts, 3), 10)
  ) then
    update public.analyses
    set status = 'failed',
        status_message = 'Analiz arka planda tamamlanamadı. Lütfen tekrar dene.',
        last_worker_error = 'worker_attempts_exhausted',
        failure_category = 'technical',
        failure_code = 'worker_attempts_exhausted'
    where id = p_analysis_id and user_id = p_user_id;

    delete from public.usage_events
    where user_id = p_user_id
      and source_id = p_analysis_id
      and feature in ('analysis_standard', 'analysis_detailed')
      and event_type = 'reserved';

    update private.analysis_job_state
    set claim_token = null,
        claimed_at = null,
        lease_expires_at = null,
        updated_at = now()
    where analysis_id = p_analysis_id;

    return jsonb_build_object(
      'ok', false,
      'state', 'max_attempts',
      'worker_attempt', v_state.worker_attempt_count
    );
  end if;

  v_claim_reason := case
    when v_state.worker_attempt_count = 0 then 'initial'
    when v_state.claim_token is not null
      and v_state.lease_expires_at is not null
      and v_state.lease_expires_at <= now()
      then 'lease_expired'
    else 'released_retry'
  end;
  v_token := gen_random_uuid();
  v_attempt := v_state.worker_attempt_count + 1;

  update private.analysis_job_state
  set claim_token = v_token,
      claimed_at = now(),
      lease_expires_at = now() + make_interval(secs => v_lease_seconds),
      worker_attempt_count = v_attempt,
      updated_at = now()
  where analysis_id = p_analysis_id;

  update public.analyses
  set status = 'analyzing',
      started_at = coalesce(started_at, now()),
      worker_started_at = now(),
      worker_attempt_count = v_attempt,
      last_worker_error = null,
      failure_category = null,
      failure_code = null
  where id = p_analysis_id and user_id = p_user_id;

  return jsonb_build_object(
    'ok', true,
    'state', 'claimed',
    'claim_token', v_token,
    'worker_attempt', v_attempt,
    'claim_reason', v_claim_reason,
    'lease_seconds', v_lease_seconds,
    'lease_expires_at', now() + make_interval(secs => v_lease_seconds)
  );
end;
$$;


ALTER FUNCTION "public"."claim_analysis_job_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_job_mode" "text", "p_lease_seconds" integer, "p_max_attempts" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."claim_notification_jobs_v1"("p_now" timestamp with time zone DEFAULT "now"(), "p_limit" integer DEFAULT 50, "p_lease_seconds" integer DEFAULT 300) RETURNS TABLE("job_id" "uuid", "claim_token" "uuid", "user_id" "uuid", "rule_id" "uuid", "rule_version_id" "uuid", "campaign_id" "uuid", "template_id" "uuid", "kind" "text", "title" "text", "body" "text", "destination" "text", "payload_data" "jsonb", "dedupe_key" "text", "attempt_count" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_flag jsonb := private.notification_feature_flag();
  v_limit integer := greatest(1, least(coalesce(p_limit, 50), 200));
  v_lease_seconds integer := greatest(60, least(coalesce(p_lease_seconds, 300), 900));
begin
  update private.notification_jobs j
  set status = 'failed',
      claim_token = null,
      claimed_at = null,
      lease_expires_at = null,
      completed_at = p_now,
      last_error_code = 'max_attempts_after_lease_expiry',
      last_error_text = null,
      updated_at = p_now
  where j.status = 'claimed'
    and j.lease_expires_at <= p_now
    and j.attempt_count >= 3;

  if coalesce((v_flag->>'kill_switch')::boolean, true)
     or coalesce(v_flag->>'rollout_mode', 'off') = 'off' then
    return;
  end if;

  return query
  with claimable as (
    select j.id
    from private.notification_jobs j
    left join private.notification_rules r on r.id = j.rule_id
    left join private.notification_campaigns c on c.id = j.campaign_id
    where (
      j.status = 'pending'
      or (
        j.status = 'claimed'
        and j.lease_expires_at <= p_now
      )
    )
      and j.due_at <= p_now
      and j.attempt_count < 3
      and (
        (j.rule_id is not null and r.status in ('allowlist', 'active'))
        or
        (j.campaign_id is not null and c.status in ('scheduled', 'running'))
      )
    order by j.due_at, j.created_at
    for update of j skip locked
    limit v_limit
  ),
  claimed as (
    update private.notification_jobs j
    set status = 'claimed',
        claim_token = gen_random_uuid(),
        claimed_at = p_now,
        lease_expires_at = p_now + make_interval(secs => v_lease_seconds),
        attempt_count = j.attempt_count + 1,
        updated_at = p_now
    from claimable c
    where j.id = c.id
    returning j.*
  )
  select
    c.id,
    c.claim_token,
    c.user_id,
    c.rule_id,
    c.rule_version_id,
    c.campaign_id,
    c.template_id,
    c.kind,
    c.title,
    c.body,
    c.destination,
    c.payload_data,
    c.dedupe_key,
    c.attempt_count
  from claimed c;
end;
$$;


ALTER FUNCTION "public"."claim_notification_jobs_v1"("p_now" timestamp with time zone, "p_limit" integer, "p_lease_seconds" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."complete_notification_job_v1"("p_job_id" "uuid", "p_claim_token" "uuid", "p_result" "text", "p_notification_event_id" "uuid" DEFAULT NULL::"uuid", "p_retryable" boolean DEFAULT false, "p_error_code" "text" DEFAULT NULL::"text", "p_error_text" "text" DEFAULT NULL::"text", "p_now" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_job private.notification_jobs;
  v_next_status text;
  v_next_due timestamptz;
begin
  select * into v_job
  from private.notification_jobs
  where id = p_job_id
  for update;

  if not found
     or v_job.status <> 'claimed'
     or v_job.claim_token is distinct from p_claim_token then
    return jsonb_build_object('updated', false, 'reason', 'lost_claim');
  end if;

  if p_result not in ('sent', 'skipped', 'failed', 'ambiguous') then
    raise exception 'invalid_job_result' using errcode = '22023';
  end if;

  if p_result = 'failed' and p_retryable and v_job.attempt_count < 3 then
    v_next_status := 'pending';
    v_next_due := p_now + make_interval(
      secs => case v_job.attempt_count
        when 1 then 300
        when 2 then 900
        else 1800
      end
    );
  else
    v_next_status := p_result;
    v_next_due := v_job.due_at;
  end if;

  update private.notification_jobs
  set status = v_next_status,
      due_at = v_next_due,
      notification_event_id = coalesce(
        p_notification_event_id,
        notification_event_id
      ),
      claim_token = null,
      claimed_at = null,
      lease_expires_at = null,
      completed_at = case
        when v_next_status in ('sent', 'skipped', 'failed', 'ambiguous')
          then p_now
        else null
      end,
      last_error_code = nullif(left(btrim(coalesce(p_error_code, '')), 100), ''),
      last_error_text = nullif(left(btrim(coalesce(p_error_text, '')), 500), ''),
      updated_at = p_now
  where id = p_job_id
    and claim_token = p_claim_token;

  return jsonb_build_object(
    'updated', true,
    'status', v_next_status,
    'attempt_count', v_job.attempt_count,
    'next_due_at', v_next_due
  );
end;
$$;


ALTER FUNCTION "public"."complete_notification_job_v1"("p_job_id" "uuid", "p_claim_token" "uuid", "p_result" "text", "p_notification_event_id" "uuid", "p_retryable" boolean, "p_error_code" "text", "p_error_text" "text", "p_now" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."defer_analysis_job_message_v2"("p_msg_id" bigint, "p_visibility_timeout" integer) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  perform * from pgmq.set_vt(
    'analysis_jobs',
    p_msg_id,
    greatest(1, least(coalesce(p_visibility_timeout, 30), 900))
  );
  return found;
end;
$$;


ALTER FUNCTION "public"."defer_analysis_job_message_v2"("p_msg_id" bigint, "p_visibility_timeout" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_analysis_job_message"("p_msg_id" bigint) RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pgmq'
    AS $$
  select pgmq.delete('analysis_jobs', p_msg_id);
$$;


ALTER FUNCTION "public"."delete_analysis_job_message"("p_msg_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_report_plan_limits"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
declare
  tier text;
  monthly_limit integer;
  day_start timestamptz;
  day_end timestamptz;
  month_start timestamptz;
  month_end timestamptz;
  used_count integer;
  risk_trial_used integer;
  is_risk_analysis_report boolean;
  quota_feature text;
begin
  tier := coalesce(private.user_plan_tier(new.user_id), 'free');
  monthly_limit := private.report_monthly_limit(tier);
  is_risk_analysis_report :=
    coalesce(new.kind, '') in ('riskAnalysis', 'risk_analysis')
    or coalesce(new.format, '') = 'xlsx';

  day_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  day_end := day_start + interval '1 day';
  month_start := date_trunc('month', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  month_end := month_start + interval '1 month';

  if tier = 'free' then
    perform pg_advisory_xact_lock(hashtext(new.user_id::text || ':free_report_quota:' || day_start::text));

    if is_risk_analysis_report then
      quota_feature := 'report_risk_analysis_trial';

      select count(*)
        into risk_trial_used
      from public.usage_events ue
      where ue.user_id = new.user_id
        and ue.feature = quota_feature
        and ue.event_type = 'completed';

      select risk_trial_used + count(*)
        into risk_trial_used
      from public.reports r
      where r.user_id = new.user_id
        and (
          coalesce(r.kind, '') in ('riskAnalysis', 'risk_analysis')
          or coalesce(r.format, '') = 'xlsx'
        )
        and not exists (
          select 1
          from public.usage_events ue
          where ue.user_id = r.user_id
            and ue.source_id = r.id
            and ue.feature = quota_feature
        );

      if risk_trial_used >= 1 then
        raise exception 'free_risk_analysis_trial_exhausted:1/1'
          using errcode = 'P0001',
                hint = 'Free users can create one risk analysis table as a trial.';
      end if;
    else
      quota_feature := 'report_standard';

      select count(*)
        into used_count
      from public.usage_events ue
      where ue.user_id = new.user_id
        and ue.feature = quota_feature
        and ue.event_type = 'completed'
        and ue.created_at >= day_start
        and ue.created_at < day_end;

      select used_count + count(*)
        into used_count
      from public.reports r
      where r.user_id = new.user_id
        and r.created_at >= day_start
        and r.created_at < day_end
        and not (
          coalesce(r.kind, '') in ('riskAnalysis', 'risk_analysis')
          or coalesce(r.format, '') = 'xlsx'
        )
        and not exists (
          select 1
          from public.usage_events ue
          where ue.user_id = r.user_id
            and ue.source_id = r.id
            and ue.feature = quota_feature
        );

      if used_count >= 1 then
        raise exception 'report_quota_exceeded:1/1'
          using errcode = 'P0001',
                hint = 'Free standard report quota renews daily.';
      end if;
    end if;

    insert into public.usage_events (
      user_id,
      feature,
      event_type,
      source_id,
      metadata
    ) values (
      new.user_id,
      quota_feature,
      'completed',
      new.id,
      jsonb_build_object(
        'source', 'report_insert',
        'tier', tier,
        'format', new.format,
        'kind', new.kind,
        'method', new.method,
        'period_start', case when quota_feature = 'report_standard' then day_start else null end
      )
    )
    on conflict (user_id, feature, source_id)
    where source_id is not null
      and feature in ('report_standard', 'report_risk_analysis_trial')
    do nothing;

    return new;
  end if;

  if monthly_limit is null then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtext(new.user_id::text || ':report_quota:' || month_start::text));
  quota_feature := 'report_standard';

  select count(*)
    into used_count
  from public.usage_events ue
  where ue.user_id = new.user_id
    and ue.feature = quota_feature
    and ue.event_type = 'completed'
    and ue.created_at >= month_start
    and ue.created_at < month_end;

  select used_count + count(*)
    into used_count
  from public.reports r
  where r.user_id = new.user_id
    and r.created_at >= month_start
    and r.created_at < month_end
    and not exists (
      select 1
      from public.usage_events ue
      where ue.user_id = r.user_id
        and ue.source_id = r.id
        and ue.feature = quota_feature
    );

  if used_count >= monthly_limit then
    raise exception 'report_quota_exceeded:%/%', monthly_limit, monthly_limit
      using errcode = 'P0001',
            hint = 'Upgrade plan or wait until the next monthly quota period.';
  end if;

  insert into public.usage_events (
    user_id,
    feature,
    event_type,
    source_id,
    metadata
  ) values (
    new.user_id,
    quota_feature,
    'completed',
    new.id,
    jsonb_build_object(
      'source', 'report_insert',
      'tier', tier,
      'format', new.format,
      'kind', new.kind,
      'method', new.method,
      'period_start', month_start
    )
  )
  on conflict (user_id, feature, source_id)
  where source_id is not null
    and feature in ('report_standard', 'report_risk_analysis_trial')
  do nothing;

  return new;
end;
$$;


ALTER FUNCTION "public"."enforce_report_plan_limits"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enqueue_analysis_job_message"("p_message" "jsonb") RETURNS bigint
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pgmq'
    AS $$
  select pgmq.send('analysis_jobs', p_message, 0);
$$;


ALTER FUNCTION "public"."enqueue_analysis_job_message"("p_message" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enqueue_notification_jobs_v1"("p_now" timestamp with time zone DEFAULT "now"(), "p_limit" integer DEFAULT 500) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_flag jsonb := private.notification_feature_flag();
  v_limit integer := greatest(1, least(coalesce(p_limit, 500), 2000));
  v_first_analysis integer := 0;
  v_inactivity integer := 0;
  v_manual integer := 0;
  v_shadow integer := 0;
begin
  if coalesce((v_flag->>'kill_switch')::boolean, true)
     or coalesce(v_flag->>'rollout_mode', 'off') = 'off' then
    return jsonb_build_object(
      'enabled', false,
      'reason', case
        when coalesce((v_flag->>'kill_switch')::boolean, true)
          then 'kill_switch'
        else 'rollout_off'
      end,
      'first_analysis', 0,
      'inactivity', 0,
      'manual', 0,
      'shadow', 0
    );
  end if;

  with runtime_rules as (
    select
      r.id as rule_id,
      r.rule_type,
      r.status as rule_status,
      r.template_id,
      rv.id as rule_version_id,
      rv.version,
      rv.conditions,
      rv.enabled_user_hashes,
      coalesce(rv.template_snapshot->>'title', t.title) as title,
      coalesce(rv.template_snapshot->>'body', t.body) as body,
      coalesce(
        rv.template_snapshot->>'destination',
        t.destination
      ) as destination
    from private.notification_rules r
    join private.notification_rule_versions rv
      on rv.id = r.current_version_id
    join private.notification_templates t
      on t.id = r.template_id
    where r.rule_type = 'first_analysis'
      and r.status in ('shadow', 'allowlist', 'active')
      and t.status = 'active'
  ),
  eligible_users as (
    select
      e.user_id,
      e.timezone,
      coalesce(o.completed_at, u.created_at) as onboarding_anchor
    from public.user_engagement_state e
    join auth.users u on u.id = e.user_id
    left join public.user_onboarding_answers o on o.user_id = e.user_id
    join public.notification_preferences p on p.user_id = e.user_id
    where p.enabled
      and p.app_reminders
      and e.authorization_status in ('authorized', 'provisional', 'ephemeral')
      and exists (
        select 1
        from public.push_device_tokens dt
        where dt.user_id = e.user_id
          and dt.environment = 'production'
          and dt.notifications_enabled
      )
      and (p_now at time zone e.timezone)::time >= time '10:00'
      and (p_now at time zone e.timezone)::time < time '20:00'
      and private.notification_rollout_allows(v_flag, e.user_id)
      and not exists (
        select 1
        from public.notification_events ne
        where ne.user_id = e.user_id
          and ne.status = 'sent'
          and ne.created_at > p_now - interval '24 hours'
      )
      and (
        select count(*)
        from public.notification_events ne
        where ne.user_id = e.user_id
          and ne.kind in (
            'first_analysis_reminder',
            'inactivity_reminder',
            'manual_app_reminder'
          )
          and ne.status = 'sent'
          and ne.created_at > p_now - interval '7 days'
      ) < 1
      and (
        select count(*)
        from public.notification_events ne
        where ne.user_id = e.user_id
          and ne.kind in (
            'first_analysis_reminder',
            'inactivity_reminder',
            'manual_app_reminder'
          )
          and ne.status = 'sent'
          and ne.created_at > p_now - interval '30 days'
      ) < 2
  ),
  candidates as (
    select rr.*, eu.*
    from runtime_rules rr
    cross join eligible_users eu
    where p_now >= eu.onboarding_anchor + (
      case
        when jsonb_typeof(rr.conditions->'min_hours') = 'number'
          then (rr.conditions->>'min_hours')::numeric
        else 24
      end
    ) * interval '1 hour'
      and p_now < eu.onboarding_anchor + (
        case
          when jsonb_typeof(rr.conditions->'max_hours') = 'number'
            then (rr.conditions->>'max_hours')::numeric
          else 72
        end
      ) * interval '1 hour'
      and (
        rr.rule_status <> 'allowlist'
        or private.notification_user_hash(eu.user_id)
          = any(rr.enabled_user_hashes)
      )
      and not exists (
        select 1
        from public.analyses a
        where a.user_id = eu.user_id
          and (
            a.status::text <> 'pending'
            or a.queued_at is not null
            or a.worker_started_at is not null
          )
      )
      and not exists (
        select 1
        from private.notification_jobs existing_job
        where existing_job.user_id = eu.user_id
          and existing_job.kind = 'first_analysis_reminder'
          and existing_job.status = 'sent'
      )
      and not exists (
        select 1
        from public.notification_events sent_event
        where sent_event.user_id = eu.user_id
          and sent_event.kind = 'first_analysis_reminder'
          and sent_event.status = 'sent'
      )
    order by eu.onboarding_anchor
    limit v_limit
  ),
  inserted as (
    insert into private.notification_jobs (
      user_id,
      rule_id,
      rule_version_id,
      template_id,
      kind,
      episode_key,
      dedupe_key,
      status,
      due_at,
      timezone,
      title,
      body,
      destination,
      payload_data,
      eligibility_snapshot
    )
    select
      c.user_id,
      c.rule_id,
      c.rule_version_id,
      c.template_id,
      'first_analysis_reminder',
      'lifetime',
      concat(
        case when c.rule_status = 'shadow' then 'shadow:' else 'send:' end,
        c.rule_id::text,
        ':',
        c.rule_version_id::text,
        ':',
        c.user_id::text,
        ':lifetime'
      ),
      case when c.rule_status = 'shadow' then 'shadow' else 'pending' end,
      p_now,
      c.timezone,
      c.title,
      c.body,
      c.destination,
      jsonb_build_object(
        'destination', c.destination,
        'event', 'first_analysis_reminder'
      ),
      jsonb_build_object(
        'evaluated_at', p_now,
        'onboarding_anchor', c.onboarding_anchor,
        'rule_version', c.version
      )
    from candidates c
    on conflict do nothing
    returning status
  )
  select
    count(*) filter (where status = 'pending'),
    count(*) filter (where status = 'shadow')
  into v_first_analysis, v_shadow
  from inserted;

  with runtime_rules as (
    select
      r.id as rule_id,
      r.rule_type,
      r.status as rule_status,
      r.template_id,
      rv.id as rule_version_id,
      rv.version,
      rv.conditions,
      rv.enabled_user_hashes,
      coalesce(rv.template_snapshot->>'title', t.title) as title,
      coalesce(rv.template_snapshot->>'body', t.body) as body,
      coalesce(
        rv.template_snapshot->>'destination',
        t.destination
      ) as destination
    from private.notification_rules r
    join private.notification_rule_versions rv
      on rv.id = r.current_version_id
    join private.notification_templates t
      on t.id = r.template_id
    where r.rule_type = 'inactivity'
      and r.status in ('shadow', 'allowlist', 'active')
      and t.status = 'active'
  ),
  user_activity as (
    select
      e.user_id,
      e.timezone,
      greatest(
        e.last_foreground_at,
        coalesce(
          (
            select max(greatest(a.updated_at, coalesce(a.completed_at, a.created_at)))
            from public.analyses a
            where a.user_id = e.user_id
              and a.status::text = 'completed'
          ),
          '-infinity'::timestamptz
        ),
        coalesce(
          (
            select max(r.created_at)
            from public.reports r
            where r.user_id = e.user_id
          ),
          '-infinity'::timestamptz
        )
      ) as last_meaningful_activity_at
    from public.user_engagement_state e
    join public.notification_preferences p on p.user_id = e.user_id
    where p.enabled
      and p.app_reminders
      and e.authorization_status in ('authorized', 'provisional', 'ephemeral')
      and exists (
        select 1
        from public.push_device_tokens dt
        where dt.user_id = e.user_id
          and dt.environment = 'production'
          and dt.notifications_enabled
      )
      and exists (
        select 1
        from public.analyses a
        where a.user_id = e.user_id
          and a.status::text = 'completed'
      )
      and (p_now at time zone e.timezone)::time >= time '10:00'
      and (p_now at time zone e.timezone)::time < time '20:00'
      and private.notification_rollout_allows(v_flag, e.user_id)
      and not exists (
        select 1
        from public.notification_events ne
        where ne.user_id = e.user_id
          and ne.status = 'sent'
          and ne.created_at > p_now - interval '24 hours'
      )
      and (
        select count(*)
        from public.notification_events ne
        where ne.user_id = e.user_id
          and ne.kind in (
            'first_analysis_reminder',
            'inactivity_reminder',
            'manual_app_reminder'
          )
          and ne.status = 'sent'
          and ne.created_at > p_now - interval '7 days'
      ) < 1
      and (
        select count(*)
        from public.notification_events ne
        where ne.user_id = e.user_id
          and ne.kind in (
            'first_analysis_reminder',
            'inactivity_reminder',
            'manual_app_reminder'
          )
          and ne.status = 'sent'
          and ne.created_at > p_now - interval '30 days'
      ) < 2
  ),
  candidates as (
    select rr.*, ua.*
    from runtime_rules rr
    cross join user_activity ua
    where ua.last_meaningful_activity_at <= p_now - (
      case
        when jsonb_typeof(rr.conditions->'inactivity_days') = 'number'
          then (rr.conditions->>'inactivity_days')::numeric
        else 5
      end
    ) * interval '1 day'
      and (
        rr.rule_status <> 'allowlist'
        or private.notification_user_hash(ua.user_id)
          = any(rr.enabled_user_hashes)
      )
      and not exists (
        select 1
        from private.notification_jobs existing_job
        where existing_job.user_id = ua.user_id
          and existing_job.kind = 'inactivity_reminder'
          and existing_job.episode_key =
            extract(epoch from ua.last_meaningful_activity_at)::bigint::text
          and existing_job.status in ('pending', 'claimed', 'sent', 'ambiguous')
      )
      and not exists (
        select 1
        from public.notification_events sent_event
        join private.notification_jobs event_job
          on event_job.id = sent_event.job_id
        where sent_event.user_id = ua.user_id
          and sent_event.kind = 'inactivity_reminder'
          and sent_event.status = 'sent'
          and event_job.episode_key =
            extract(epoch from ua.last_meaningful_activity_at)::bigint::text
      )
    order by ua.last_meaningful_activity_at
    limit v_limit
  ),
  inserted as (
    insert into private.notification_jobs (
      user_id,
      rule_id,
      rule_version_id,
      template_id,
      kind,
      episode_key,
      dedupe_key,
      status,
      due_at,
      timezone,
      title,
      body,
      destination,
      payload_data,
      eligibility_snapshot
    )
    select
      c.user_id,
      c.rule_id,
      c.rule_version_id,
      c.template_id,
      'inactivity_reminder',
      extract(epoch from c.last_meaningful_activity_at)::bigint::text,
      concat(
        case when c.rule_status = 'shadow' then 'shadow:' else 'send:' end,
        c.rule_id::text,
        ':',
        c.rule_version_id::text,
        ':',
        c.user_id::text,
        ':',
        extract(epoch from c.last_meaningful_activity_at)::bigint::text
      ),
      case when c.rule_status = 'shadow' then 'shadow' else 'pending' end,
      p_now,
      c.timezone,
      c.title,
      c.body,
      c.destination,
      jsonb_build_object(
        'destination', c.destination,
        'event', 'inactivity_reminder'
      ),
      jsonb_build_object(
        'evaluated_at', p_now,
        'last_meaningful_activity_at', c.last_meaningful_activity_at,
        'rule_version', c.version
      )
    from candidates c
    on conflict do nothing
    returning status
  )
  select
    count(*) filter (where status = 'pending'),
    v_shadow + count(*) filter (where status = 'shadow')
  into v_inactivity, v_shadow
  from inserted;

  with due_campaigns as (
    select c.*
    from private.notification_campaigns c
    where c.status in ('scheduled', 'running')
      and c.scheduled_at is not null
      and c.scheduled_at <= p_now
    order by c.scheduled_at
  ),
  eligible_users as (
    select e.user_id, e.timezone
    from public.user_engagement_state e
    join public.notification_preferences p on p.user_id = e.user_id
    where p.enabled
      and p.app_reminders
      and e.authorization_status in ('authorized', 'provisional', 'ephemeral')
      and exists (
        select 1
        from public.push_device_tokens dt
        where dt.user_id = e.user_id
          and dt.environment = 'production'
          and dt.notifications_enabled
      )
      and (p_now at time zone e.timezone)::time >= time '10:00'
      and (p_now at time zone e.timezone)::time < time '20:00'
      and private.notification_rollout_allows(v_flag, e.user_id)
      and not exists (
        select 1
        from public.notification_events ne
        where ne.user_id = e.user_id
          and ne.status = 'sent'
          and ne.created_at > p_now - interval '24 hours'
      )
      and (
        select count(*)
        from public.notification_events ne
        where ne.user_id = e.user_id
          and ne.kind in (
            'first_analysis_reminder',
            'inactivity_reminder',
            'manual_app_reminder'
          )
          and ne.status = 'sent'
          and ne.created_at > p_now - interval '7 days'
      ) < 1
      and (
        select count(*)
        from public.notification_events ne
        where ne.user_id = e.user_id
          and ne.kind in (
            'first_analysis_reminder',
            'inactivity_reminder',
            'manual_app_reminder'
          )
          and ne.status = 'sent'
          and ne.created_at > p_now - interval '30 days'
      ) < 2
  ),
  candidates as (
    select dc.*, eu.user_id, eu.timezone
    from due_campaigns dc
    cross join eligible_users eu
    where (
      dc.target_spec->>'audience' = 'all_eligible'
      or (
        dc.target_spec->>'audience' = 'allowlist'
        and coalesce(dc.target_spec->'user_hashes', '[]'::jsonb)
          ? private.notification_user_hash(eu.user_id)
      )
    )
      and not exists (
        select 1
        from private.notification_jobs existing_job
        where existing_job.campaign_id = dc.id
          and existing_job.user_id = eu.user_id
      )
    order by dc.scheduled_at, eu.user_id
    limit v_limit
  ),
  inserted as (
    insert into private.notification_jobs (
      user_id,
      campaign_id,
      template_id,
      kind,
      episode_key,
      dedupe_key,
      status,
      due_at,
      timezone,
      title,
      body,
      destination,
      payload_data,
      eligibility_snapshot
    )
    select
      c.user_id,
      c.id,
      c.template_id,
      'manual_app_reminder',
      c.id::text,
      concat('campaign:', c.id::text, ':', c.user_id::text),
      'pending',
      p_now,
      c.timezone,
      c.title,
      c.body,
      c.destination,
      jsonb_build_object(
        'destination', c.destination,
        'event', 'manual_app_reminder'
      ),
      jsonb_build_object(
        'evaluated_at', p_now,
        'campaign_id', c.id
      )
    from candidates c
    on conflict do nothing
    returning campaign_id
  )
  select count(*) into v_manual from inserted;

  update private.notification_campaigns c
  set status = 'running',
      started_at = coalesce(started_at, p_now),
      updated_at = p_now
  where c.status = 'scheduled'
    and c.scheduled_at <= p_now
    and exists (
      select 1
      from private.notification_jobs j
      where j.campaign_id = c.id
    );

  return jsonb_build_object(
    'enabled', true,
    'rollout_mode', v_flag->>'rollout_mode',
    'first_analysis', v_first_analysis,
    'inactivity', v_inactivity,
    'manual', v_manual,
    'shadow', v_shadow
  );
end;
$$;


ALTER FUNCTION "public"."enqueue_notification_jobs_v1"("p_now" timestamp with time zone, "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_analysis_usage_event_on_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  quota_feature text;
begin
  if old.user_id is null or old.status <> 'completed' then
    return old;
  end if;

  if not exists (
    select 1
    from auth.users u
    where u.id = old.user_id
  ) then
    return old;
  end if;

  quota_feature := case
    when old.analysis_mode = 'detailed' then 'analysis_detailed'
    else 'analysis_standard'
  end;

  insert into public.usage_events (
    user_id,
    feature,
    event_type,
    source_id,
    metadata,
    created_at
  ) values (
    old.user_id,
    quota_feature,
    'completed',
    old.id,
    jsonb_build_object(
      'source', 'analysis_delete_tombstone',
      'analysis_mode', coalesce(old.analysis_mode, 'standard'),
      'status', old.status
    ),
    coalesce(old.completed_at, old.created_at)
  )
  on conflict (user_id, feature, source_id)
  where source_id is not null
    and feature in ('analysis_standard', 'analysis_detailed')
  do nothing;

  return old;
end;
$$;


ALTER FUNCTION "public"."ensure_analysis_usage_event_on_delete"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_report_usage_event_on_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
declare
  tier text;
  is_risk_analysis_report boolean;
  quota_feature text;
begin
  if old.user_id is null then
    return old;
  end if;

  if not exists (
    select 1
    from auth.users u
    where u.id = old.user_id
  ) then
    return old;
  end if;

  tier := coalesce(private.user_plan_tier(old.user_id), 'free');
  is_risk_analysis_report :=
    coalesce(old.kind, '') in ('riskAnalysis', 'risk_analysis')
    or coalesce(old.format, '') = 'xlsx';
  quota_feature := case
    when tier = 'free' and is_risk_analysis_report
      then 'report_risk_analysis_trial'
    else 'report_standard'
  end;

  insert into public.usage_events (
    user_id,
    feature,
    event_type,
    source_id,
    metadata,
    created_at
  ) values (
    old.user_id,
    quota_feature,
    'completed',
    old.id,
    jsonb_build_object(
      'source', 'report_delete_tombstone',
      'format', old.format,
      'kind', old.kind,
      'method', old.method
    ),
    old.created_at
  )
  on conflict (user_id, feature, source_id)
  where source_id is not null
    and feature in ('report_standard', 'report_risk_analysis_trial')
  do nothing;

  return old;
end;
$$;


ALTER FUNCTION "public"."ensure_report_usage_event_on_delete"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."finalize_analysis_result_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_claim_token" "uuid", "p_findings" "jsonb", "p_analysis_result" "jsonb", "p_photo_summaries" "jsonb" DEFAULT '[]'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_analysis public.analyses%rowtype;
  v_state private.analysis_job_state%rowtype;
  v_finding jsonb;
  v_summary jsonb;
  v_source_indices integer[];
  v_inserted integer := 0;
begin
  select * into v_analysis
  from public.analyses
  where id = p_analysis_id and user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'state', 'analysis_not_found');
  end if;
  if v_analysis.status::text = 'completed' then
    return jsonb_build_object(
      'ok', true,
      'state', 'already_completed',
      'finding_count', v_analysis.finding_count
    );
  end if;

  select * into v_state
  from private.analysis_job_state
  where analysis_id = p_analysis_id and user_id = p_user_id
  for update;

  if not found
    or v_state.active_msg_id is distinct from p_msg_id
    or v_state.generation is distinct from p_generation
    or v_state.claim_token is distinct from p_claim_token
  then
    return jsonb_build_object('ok', false, 'state', 'lost_claim');
  end if;

  delete from public.findings
  where analysis_id = p_analysis_id
    and user_id = p_user_id
    and origin = 'ai';

  for v_finding in
    select value from jsonb_array_elements(coalesce(p_findings, '[]'::jsonb))
  loop
    select coalesce(array_agg(value::integer), '{}'::integer[])
      into v_source_indices
    from jsonb_array_elements_text(
      case
        when jsonb_typeof(v_finding->'source_photo_indices') = 'array'
          then v_finding->'source_photo_indices'
        else '[]'::jsonb
      end
    );

    insert into public.findings (
      analysis_id,
      user_id,
      ordinal,
      title,
      category,
      description,
      recommended_action,
      recommended_measures,
      references_text,
      root_cause_text,
      confidence,
      needs_field_verification,
      origin,
      ai_original_snapshot,
      source_photo_indices,
      source_photo_observations,
      finding_budget_policy,
      ai_confidence,
      fk_probability,
      fk_frequency,
      fk_severity,
      fk_band,
      m5_probability,
      m5_severity,
      m5_band,
      display_order
    ) values (
      p_analysis_id,
      p_user_id,
      (v_finding->>'ordinal')::integer,
      v_finding->>'title',
      v_finding->>'category',
      v_finding->>'description',
      v_finding->>'recommended_action',
      coalesce(v_finding->'recommended_measures', '[]'::jsonb),
      v_finding->>'references_text',
      v_finding->>'root_cause_text',
      coalesce((v_finding->>'confidence')::numeric, 0),
      coalesce((v_finding->>'needs_field_verification')::boolean, false),
      'ai',
      v_finding->'ai_original_snapshot',
      v_source_indices,
      v_finding->'source_photo_observations',
      v_finding->'finding_budget_policy',
      nullif(v_finding->>'ai_confidence', '')::numeric,
      (v_finding->>'fk_probability')::numeric,
      (v_finding->>'fk_frequency')::numeric,
      (v_finding->>'fk_severity')::numeric,
      (v_finding->>'fk_band')::public.risk_level,
      (v_finding->>'m5_probability')::integer,
      (v_finding->>'m5_severity')::integer,
      (v_finding->>'m5_band')::public.risk_level,
      (v_finding->>'display_order')::integer
    );
    v_inserted := v_inserted + 1;
  end loop;

  update public.analyses
  set status = 'completed',
      status_message = p_analysis_result->>'status_message',
      completed_at = now(),
      ai_summary = p_analysis_result->>'ai_summary',
      total_score_fk = nullif(p_analysis_result->>'total_score_fk', '')::numeric,
      total_score_m5 = nullif(p_analysis_result->>'total_score_m5', '')::integer,
      highest_band_fk = nullif(p_analysis_result->>'highest_band_fk', '')::public.risk_level,
      highest_band_m5 = nullif(p_analysis_result->>'highest_band_m5', '')::public.risk_level,
      finding_count = v_inserted,
      generated_findings_count = v_inserted,
      visible_findings_count = v_inserted,
      hidden_or_rejected_findings_count = coalesce(
        nullif(p_analysis_result->>'hidden_or_rejected_findings_count', '')::integer,
        0
      ),
      max_findings_per_photo = coalesce(
        nullif(p_analysis_result->>'max_findings_per_photo', '')::integer,
        max_findings_per_photo
      ),
      max_findings_total = nullif(p_analysis_result->>'max_findings_total', '')::integer,
      raw_ai_response = p_analysis_result->'raw_ai_response',
      ai_models_used = array(
        select jsonb_array_elements_text(
          coalesce(p_analysis_result->'ai_models_used', '[]'::jsonb)
        )
      ),
      last_worker_error = null,
      failure_category = null,
      failure_code = null
  where id = p_analysis_id and user_id = p_user_id;

  update public.usage_events
  set event_type = 'completed'
  where user_id = p_user_id
    and source_id = p_analysis_id
    and feature in ('analysis_standard', 'analysis_detailed')
    and event_type = 'reserved';

  begin
    for v_summary in
      select value
      from jsonb_array_elements(coalesce(p_photo_summaries, '[]'::jsonb))
    loop
      insert into public.analysis_photo_summaries (
        analysis_id,
        user_id,
        photo_id,
        photo_sequence_index,
        scene_summary,
        candidate_findings_count,
        generated_findings_count,
        highest_risk_level,
        ai_confidence,
        coverage_status,
        coverage_gap_reason,
        target_findings_min,
        target_findings_max,
        raw_summary
      ) values (
        p_analysis_id,
        p_user_id,
        nullif(v_summary->>'photo_id', '')::uuid,
        (v_summary->>'photo_sequence_index')::integer,
        v_summary->>'scene_summary',
        coalesce(nullif(v_summary->>'candidate_findings_count', '')::integer, 0),
        coalesce(nullif(v_summary->>'generated_findings_count', '')::integer, 0),
        v_summary->>'highest_risk_level',
        nullif(v_summary->>'ai_confidence', '')::numeric,
        v_summary->>'coverage_status',
        v_summary->>'coverage_gap_reason',
        nullif(v_summary->>'target_findings_min', '')::integer,
        nullif(v_summary->>'target_findings_max', '')::integer,
        v_summary->'raw_summary'
      )
      on conflict (analysis_id, photo_sequence_index) do update set
        user_id = excluded.user_id,
        photo_id = excluded.photo_id,
        scene_summary = excluded.scene_summary,
        candidate_findings_count = excluded.candidate_findings_count,
        generated_findings_count = excluded.generated_findings_count,
        highest_risk_level = excluded.highest_risk_level,
        ai_confidence = excluded.ai_confidence,
        coverage_status = excluded.coverage_status,
        coverage_gap_reason = excluded.coverage_gap_reason,
        target_findings_min = excluded.target_findings_min,
        target_findings_max = excluded.target_findings_max,
        raw_summary = excluded.raw_summary;
    end loop;
  exception when others then
    raise warning 'analysis_photo_summaries skipped for analysis %: %',
      p_analysis_id, sqlerrm;
  end;

  update private.analysis_job_state
  set claim_token = null,
      claimed_at = null,
      lease_expires_at = null,
      updated_at = now()
  where analysis_id = p_analysis_id;

  return jsonb_build_object(
    'ok', true,
    'state', 'completed',
    'finding_count', v_inserted
  );
end;
$$;


ALTER FUNCTION "public"."finalize_analysis_result_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_claim_token" "uuid", "p_findings" "jsonb", "p_analysis_result" "jsonb", "p_photo_summaries" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."next_document_no"("p_user_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  y int := extract(year from now())::int;
  n int;
begin
  if p_user_id is null then
    raise exception 'missing_user_id';
  end if;

  perform 1
  from public.profiles
  where id = p_user_id;

  if not found then
    raise exception 'user_not_found';
  end if;

  insert into public.report_year_counters(year, last_no)
  values (y, 1)
  on conflict (year) do update
    set last_no = public.report_year_counters.last_no + 1
  returning last_no into n;

  return 'RD-RA-' || y::text || '-' || lpad(n::text, 4, '0');
end
$$;


ALTER FUNCTION "public"."next_document_no"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."read_analysis_job_messages"("p_limit" integer DEFAULT 1, "p_visibility_timeout" integer DEFAULT 600) RETURNS "jsonb"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pgmq'
    AS $$
  select coalesce(jsonb_agg(to_jsonb(m)), '[]'::jsonb)
  from pgmq.read(
    'analysis_jobs',
    greatest(1, least(p_visibility_timeout, 900)),
    greatest(1, least(p_limit, 3))
  ) as m;
$$;


ALTER FUNCTION "public"."read_analysis_job_messages"("p_limit" integer, "p_visibility_timeout" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recalc_analysis_rollup"("p_analysis_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_user_id uuid;
  v_count integer;
  v_total_fk numeric;
  v_total_m5 integer;
  v_highest_fk text;
  v_highest_m5 text;
begin
  if p_analysis_id is null then
    return;
  end if;

  select user_id into v_user_id
  from public.analyses
  where id = p_analysis_id;

  if v_user_id is null then
    return;
  end if;

  select
    count(*)::integer,
    coalesce(sum(fk_score), 0),
    coalesce(sum(m5_score), 0)::integer,
    coalesce((
      array_agg(fk_band::text order by
        case fk_band::text
          when 'critical' then 4
          when 'high' then 3
          when 'medium' then 2
          when 'low' then 1
          else 0
        end desc
      )
    )[1], 'unknown'),
    coalesce((
      array_agg(m5_band::text order by
        case m5_band::text
          when 'critical' then 4
          when 'high' then 3
          when 'medium' then 2
          when 'low' then 1
          else 0
        end desc
      )
    )[1], 'unknown')
  into v_count, v_total_fk, v_total_m5, v_highest_fk, v_highest_m5
  from public.findings
  where analysis_id = p_analysis_id
    and coalesce(is_user_deleted, false) = false
    and coalesce(report_visibility, 'visible') = 'visible';

  update public.analyses
  set finding_count = v_count,
      generated_findings_count = greatest(generated_findings_count, v_count),
      visible_findings_count = v_count,
      total_score_fk = v_total_fk,
      total_score_m5 = v_total_m5,
      highest_band_fk = nullif(v_highest_fk, 'unknown')::risk_level,
      highest_band_m5 = nullif(v_highest_m5, 'unknown')::risk_level,
      updated_at = now()
  where id = p_analysis_id;
end
$$;


ALTER FUNCTION "public"."recalc_analysis_rollup"("p_analysis_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_analysis_job_event_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_worker_attempt" integer, "p_job_mode" "text", "p_event_type" "text", "p_http_status" integer DEFAULT NULL::integer, "p_response_code" "text" DEFAULT NULL::"text", "p_claim_action" "text" DEFAULT NULL::"text", "p_safe_error_text" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_safe_error text;
begin
  if not exists (
    select 1
    from public.analyses a
    where a.id = p_analysis_id
      and a.user_id = p_user_id
  ) then
    return jsonb_build_object('ok', false, 'state', 'analysis_not_found');
  end if;

  if p_msg_id is null
    or p_generation is null or p_generation <= 0
    or p_worker_attempt is null or p_worker_attempt <= 0
    or p_job_mode not in ('analysis', 'repair')
    or p_event_type not in (
      'claim_acquired',
      'dispatch_success_response',
      'dispatch_application_error',
      'dispatch_ambiguous_transport',
      'claim_kept',
      'claim_released_for_retry',
      'terminal_failed',
      'repair_superseded',
      'finalized',
      'message_deleted_after_response_loss',
      'lease_expired_retry',
      'max_attempts'
    )
  then
    return jsonb_build_object('ok', false, 'state', 'validation_failed');
  end if;

  v_safe_error := nullif(
    left(
      regexp_replace(
        coalesce(p_safe_error_text, ''),
        'Bearer[[:space:]]+[^[:space:]]+',
        'Bearer [redacted]',
        'gi'
      ),
      500
    ),
    ''
  );

  insert into private.analysis_job_events (
    analysis_id,
    user_id,
    msg_id,
    job_generation,
    worker_attempt,
    job_mode,
    event_type,
    http_status,
    response_code,
    claim_action,
    safe_error_text
  ) values (
    p_analysis_id,
    p_user_id,
    p_msg_id,
    p_generation,
    p_worker_attempt,
    p_job_mode,
    p_event_type,
    case
      when p_http_status between 100 and 599 then p_http_status
      else null
    end,
    left(nullif(p_response_code, ''), 120),
    left(nullif(p_claim_action, ''), 80),
    v_safe_error
  );

  return jsonb_build_object('ok', true, 'state', 'recorded');
exception when others then
  -- Telemetry must never change queue or analysis correctness.
  return jsonb_build_object('ok', false, 'state', 'event_record_failed');
end;
$$;


ALTER FUNCTION "public"."record_analysis_job_event_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_worker_attempt" integer, "p_job_mode" "text", "p_event_type" "text", "p_http_status" integer, "p_response_code" "text", "p_claim_action" "text", "p_safe_error_text" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_analysis_job_failure_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_claim_token" "uuid", "p_error" "text", "p_failure_code" "text", "p_status_message" "text", "p_terminal" boolean DEFAULT false, "p_raw_ai_response" "jsonb" DEFAULT NULL::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_analysis public.analyses%rowtype;
  v_state private.analysis_job_state%rowtype;
begin
  select * into v_analysis
  from public.analyses
  where id = p_analysis_id and user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'state', 'analysis_not_found');
  end if;
  if v_analysis.status::text = 'completed' then
    return jsonb_build_object('ok', false, 'state', 'completed');
  end if;

  select * into v_state
  from private.analysis_job_state
  where analysis_id = p_analysis_id and user_id = p_user_id
  for update;

  if not found
    or v_state.active_msg_id is distinct from p_msg_id
    or v_state.generation is distinct from p_generation
    or v_state.claim_token is distinct from p_claim_token
  then
    return jsonb_build_object('ok', false, 'state', 'lost_claim');
  end if;

  if p_terminal then
    update public.analyses
    set status = 'failed',
        status_message = coalesce(nullif(p_status_message, ''), 'Analiz tamamlanamadı.'),
        last_worker_error = left(coalesce(p_error, 'worker_failed'), 2000),
        failure_category = 'technical',
        failure_code = left(coalesce(nullif(p_failure_code, ''), 'worker_failed'), 120),
        raw_ai_response = coalesce(p_raw_ai_response, raw_ai_response)
    where id = p_analysis_id and user_id = p_user_id;

    delete from public.usage_events
    where user_id = p_user_id
      and source_id = p_analysis_id
      and feature in ('analysis_standard', 'analysis_detailed')
      and event_type = 'reserved';
  else
    update public.analyses
    set last_worker_error = left(coalesce(p_error, 'worker_retry'), 2000),
        failure_category = null,
        failure_code = null
    where id = p_analysis_id and user_id = p_user_id;
  end if;

  update private.analysis_job_state
  set claim_token = null,
      claimed_at = null,
      lease_expires_at = null,
      updated_at = now()
  where analysis_id = p_analysis_id;

  return jsonb_build_object(
    'ok', true,
    'state', case when p_terminal then 'failed' else 'retry_pending' end,
    'worker_attempt', v_state.worker_attempt_count
  );
end;
$$;


ALTER FUNCTION "public"."record_analysis_job_failure_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_claim_token" "uuid", "p_error" "text", "p_failure_code" "text", "p_status_message" "text", "p_terminal" boolean, "p_raw_ai_response" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_notification_delivery_attempt_v1"("p_notification_event_id" "uuid", "p_job_id" "uuid", "p_push_device_token_id" "uuid", "p_environment" "text", "p_attempt_number" integer, "p_outcome" "text", "p_http_status" integer DEFAULT NULL::integer, "p_apns_id" "text" DEFAULT NULL::"text", "p_reason" "text" DEFAULT NULL::"text", "p_duration_ms" integer DEFAULT NULL::integer) RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_id bigint;
begin
  insert into private.notification_delivery_attempts (
    notification_event_id,
    job_id,
    push_device_token_id,
    environment,
    attempt_number,
    outcome,
    http_status,
    apns_id,
    reason,
    duration_ms
  )
  values (
    p_notification_event_id,
    p_job_id,
    p_push_device_token_id,
    p_environment,
    p_attempt_number,
    p_outcome,
    p_http_status,
    nullif(left(btrim(coalesce(p_apns_id, '')), 200), ''),
    nullif(left(btrim(coalesce(p_reason, '')), 500), ''),
    p_duration_ms
  )
  on conflict (
    notification_event_id,
    push_device_token_id,
    attempt_number
  ) do update set
    outcome = excluded.outcome,
    http_status = excluded.http_status,
    apns_id = excluded.apns_id,
    reason = excluded.reason,
    duration_ms = excluded.duration_ms
  returning id into v_id;

  return v_id;
end;
$$;


ALTER FUNCTION "public"."record_notification_delivery_attempt_v1"("p_notification_event_id" "uuid", "p_job_id" "uuid", "p_push_device_token_id" "uuid", "p_environment" "text", "p_attempt_number" integer, "p_outcome" "text", "p_http_status" integer, "p_apns_id" "text", "p_reason" "text", "p_duration_ms" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_notification_open_v1"("p_notification_event_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_updated integer := 0;
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  update public.notification_events
  set opened_at = coalesce(opened_at, now()),
      open_count = open_count + 1
  where id = p_notification_event_id
    and user_id = v_user_id;

  get diagnostics v_updated = row_count;
  return jsonb_build_object(
    'recorded', v_updated = 1,
    'event_id', p_notification_event_id
  );
end;
$$;


ALTER FUNCTION "public"."record_notification_open_v1"("p_notification_event_id" "uuid") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."user_engagement_state" (
    "user_id" "uuid" NOT NULL,
    "last_foreground_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "timezone" "text" NOT NULL,
    "locale" "text",
    "authorization_status" "text" NOT NULL,
    "authorization_synced_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "app_version" "text",
    "app_build" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_engagement_app_build_length_check" CHECK ((("app_build" IS NULL) OR ("char_length"("app_build") <= 40))),
    CONSTRAINT "user_engagement_app_version_length_check" CHECK ((("app_version" IS NULL) OR ("char_length"("app_version") <= 40))),
    CONSTRAINT "user_engagement_authorization_status_check" CHECK (("authorization_status" = ANY (ARRAY['not_determined'::"text", 'denied'::"text", 'authorized'::"text", 'provisional'::"text", 'ephemeral'::"text"]))),
    CONSTRAINT "user_engagement_locale_length_check" CHECK ((("locale" IS NULL) OR ("char_length"("locale") <= 35))),
    CONSTRAINT "user_engagement_timezone_length_check" CHECK ((("char_length"("timezone") >= 1) AND ("char_length"("timezone") <= 100)))
);


ALTER TABLE "public"."user_engagement_state" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_user_engagement_state_v1"("p_timezone" "text", "p_locale" "text" DEFAULT NULL::"text", "p_authorization_status" "text" DEFAULT 'not_determined'::"text", "p_app_version" "text" DEFAULT NULL::"text", "p_app_build" "text" DEFAULT NULL::"text") RETURNS "public"."user_engagement_state"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_timezone text := btrim(coalesce(p_timezone, ''));
  v_authorization_status text := lower(btrim(coalesce(p_authorization_status, '')));
  v_now timestamptz := now();
  v_existing public.user_engagement_state;
  v_row public.user_engagement_state;
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  if v_timezone = ''
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names
       where name = v_timezone
     ) then
    raise exception 'invalid_timezone' using errcode = '22023';
  end if;

  if v_authorization_status not in (
    'not_determined',
    'denied',
    'authorized',
    'provisional',
    'ephemeral'
  ) then
    raise exception 'invalid_authorization_status' using errcode = '22023';
  end if;

  select * into v_existing
  from public.user_engagement_state
  where user_id = v_user_id;

  if found
     and v_existing.authorization_status = v_authorization_status
     and v_existing.updated_at > v_now - interval '1 minute' then
    return v_existing;
  end if;

  insert into public.user_engagement_state (
    user_id,
    last_foreground_at,
    timezone,
    locale,
    authorization_status,
    authorization_synced_at,
    app_version,
    app_build,
    created_at,
    updated_at
  )
  values (
    v_user_id,
    v_now,
    v_timezone,
    nullif(left(btrim(coalesce(p_locale, '')), 35), ''),
    v_authorization_status,
    v_now,
    nullif(left(btrim(coalesce(p_app_version, '')), 40), ''),
    nullif(left(btrim(coalesce(p_app_build, '')), 40), ''),
    v_now,
    v_now
  )
  on conflict (user_id) do update set
    last_foreground_at = case
      when public.user_engagement_state.last_foreground_at <= v_now - interval '6 hours'
        then v_now
      else public.user_engagement_state.last_foreground_at
    end,
    timezone = excluded.timezone,
    locale = excluded.locale,
    authorization_status = excluded.authorization_status,
    authorization_synced_at = v_now,
    app_version = excluded.app_version,
    app_build = excluded.app_build,
    updated_at = v_now
  returning * into v_row;

  if v_authorization_status = 'denied' then
    update public.push_device_tokens
    set notifications_enabled = false,
        last_failure_at = v_now,
        last_failure_reason = 'system_authorization_denied'
    where user_id = v_user_id
      and notifications_enabled = true;
  end if;

  return v_row;
end;
$$;


ALTER FUNCTION "public"."record_user_engagement_state_v1"("p_timezone" "text", "p_locale" "text", "p_authorization_status" "text", "p_app_version" "text", "p_app_build" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reserve_analysis_quota"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_analysis_mode" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
declare
  user_tier text;
  quota_feature text;
  quota_limit integer;
  period_start timestamptz;
  used_count integer;
  existing_event_type text;
begin
  if p_user_id is null or p_analysis_id is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'validation_failed',
      'message', 'Analiz kotası için kullanıcı ve analiz zorunludur.'
    );
  end if;

  perform pg_advisory_xact_lock(hashtext(p_user_id::text || ':analysis_quota'));

  user_tier := coalesce(private.user_plan_tier(p_user_id), 'free');
  quota_feature := case
    when p_analysis_mode = 'detailed' then 'analysis_detailed'
    else 'analysis_standard'
  end;

  if user_tier = 'free' then
    if quota_feature <> 'analysis_standard' then
      return jsonb_build_object(
        'ok', false,
        'code', 'plan_required',
        'tier', user_tier,
        'message', 'Detaylı analiz Plus veya Pro üyelik gerektirir.'
      );
    end if;
    quota_limit := 1;
    period_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  elsif user_tier = 'plus' and quota_feature = 'analysis_standard' then
    quota_limit := 10;
    period_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  elsif user_tier = 'plus' and quota_feature = 'analysis_detailed' then
    quota_limit := 2;
    period_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  elsif user_tier = 'pro' and quota_feature = 'analysis_standard' then
    quota_limit := 40;
    period_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  elsif user_tier = 'pro' and quota_feature = 'analysis_detailed' then
    quota_limit := 10;
    period_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  else
    quota_limit := 0;
    period_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  end if;

  select ue.event_type
    into existing_event_type
  from public.usage_events ue
  where ue.user_id = p_user_id
    and ue.feature = quota_feature
    and ue.source_id = p_analysis_id
    and ue.event_type in ('reserved', 'completed')
  limit 1;

  if existing_event_type is not null then
    return jsonb_build_object(
      'ok', true,
      'tier', user_tier,
      'feature', quota_feature,
      'limit', quota_limit,
      'already_reserved', true,
      'event_type', existing_event_type
    );
  end if;

  select count(*)
    into used_count
  from public.usage_events ue
  where ue.user_id = p_user_id
    and ue.event_type in ('reserved', 'completed')
    and ue.created_at >= period_start
    and (
      (user_tier = 'free' and ue.feature in ('analysis_standard', 'analysis_detailed'))
      or (user_tier <> 'free' and ue.feature = quota_feature)
    );

  select used_count + count(*)
    into used_count
  from public.analyses a
  where a.user_id = p_user_id
    and a.status = 'completed'
    and a.created_at >= period_start
    and (
      (user_tier = 'free' and coalesce(a.analysis_mode, 'standard') in ('standard', 'detailed'))
      or (
        user_tier <> 'free'
        and coalesce(a.analysis_mode, 'standard') = case
          when quota_feature = 'analysis_detailed' then 'detailed'
          else 'standard'
        end
      )
    )
    and not exists (
      select 1
      from public.usage_events ue
      where ue.user_id = a.user_id
        and ue.source_id = a.id
        and (
          (user_tier = 'free' and ue.feature in ('analysis_standard', 'analysis_detailed'))
          or (user_tier <> 'free' and ue.feature = quota_feature)
        )
    );

  if used_count >= quota_limit then
    return jsonb_build_object(
      'ok', false,
      'code', 'quota_exceeded',
      'tier', user_tier,
      'feature', quota_feature,
      'limit', quota_limit,
      'used', used_count,
      'message', case
        when user_tier = 'free' then 'Günde 1 ücretsiz analiz hakkın doldu.'
        when quota_feature = 'analysis_detailed' then 'Günlük detaylı analiz kotan doldu (' || quota_limit || '/gün).'
        else 'Günlük analiz kotan doldu (' || quota_limit || '/gün).'
      end
    );
  end if;

  insert into public.usage_events (
    user_id,
    feature,
    event_type,
    source_id,
    metadata
  ) values (
    p_user_id,
    quota_feature,
    'reserved',
    p_analysis_id,
    jsonb_build_object(
      'analysis_mode', p_analysis_mode,
      'tier', user_tier,
      'limit', quota_limit,
      'period_start', period_start
    )
  )
  on conflict (user_id, feature, source_id)
  where source_id is not null
    and feature in ('analysis_standard', 'analysis_detailed')
  do nothing;

  return jsonb_build_object(
    'ok', true,
    'tier', user_tier,
    'feature', quota_feature,
    'limit', quota_limit,
    'used', used_count + 1
  );
end;
$$;


ALTER FUNCTION "public"."reserve_analysis_quota"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_analysis_mode" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_analysis_retention_fields"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
begin
  if new.raw_ai_response is not null
     and new.raw_ai_response_expires_at is null then
    new.raw_ai_response_expires_at := coalesce(new.completed_at, new.created_at, now()) + interval '30 days';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."set_analysis_retention_fields"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notification_preferences" (
    "user_id" "uuid" NOT NULL,
    "enabled" boolean DEFAULT false NOT NULL,
    "analysis_complete" boolean DEFAULT true NOT NULL,
    "report_ready" boolean DEFAULT true NOT NULL,
    "account_updates" boolean DEFAULT true NOT NULL,
    "marketing" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "progress_weekly_summary" boolean DEFAULT true NOT NULL,
    "progress_monthly_summary" boolean DEFAULT true NOT NULL,
    "progress_milestones" boolean DEFAULT true NOT NULL,
    "trial_reminder" boolean DEFAULT true NOT NULL,
    "app_reminders" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."notification_preferences" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_notification_master_preference_v1"("p_enabled" boolean) RETURNS "public"."notification_preferences"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_row public.notification_preferences;
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  insert into public.notification_preferences (
    user_id,
    enabled,
    analysis_complete,
    report_ready,
    account_updates,
    marketing,
    trial_reminder,
    progress_weekly_summary,
    progress_monthly_summary,
    progress_milestones,
    app_reminders
  )
  values (
    v_user_id,
    p_enabled,
    p_enabled,
    p_enabled,
    p_enabled,
    false,
    p_enabled,
    p_enabled,
    p_enabled,
    p_enabled,
    p_enabled
  )
  on conflict (user_id) do update set
    enabled = excluded.enabled
  returning * into v_row;

  update public.push_device_tokens
  set notifications_enabled = p_enabled
  where user_id = v_user_id
    and notifications_enabled is distinct from p_enabled;

  return v_row;
end;
$$;


ALTER FUNCTION "public"."set_notification_master_preference_v1"("p_enabled" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_photo_retention_fields"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
declare
  user_tier text;
  retention_days integer;
begin
  user_tier := coalesce(private.user_plan_tier(new.user_id), 'free');
  retention_days := private.archive_retention_days(user_tier);

  if new.retention_expires_at is null then
    new.retention_expires_at := case
      when retention_days is null then null
      else coalesce(new.created_at, now()) + make_interval(days => retention_days)
    end;
  end if;

  if new.retention_policy is null or new.retention_policy = 'analysis_photo' then
    new.retention_policy := case
      when retention_days is null then 'pro_photo_unlimited'
      else user_tier || '_photo_' || retention_days || 'd'
    end;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."set_photo_retention_fields"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_analysis_job_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_message" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_analysis public.analyses%rowtype;
  v_state private.analysis_job_state%rowtype;
  v_generation integer;
  v_msg_id bigint;
  v_message jsonb;
begin
  if p_user_id is null or p_analysis_id is null or p_message is null then
    return jsonb_build_object('ok', false, 'code', 'validation_failed');
  end if;

  select * into v_analysis
  from public.analyses
  where id = p_analysis_id and user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'code', 'analysis_not_found');
  end if;

  select * into v_state
  from private.analysis_job_state
  where analysis_id = p_analysis_id
  for update;

  if v_analysis.status::text in ('queued', 'analyzing') then
    return jsonb_build_object(
      'ok', true,
      'state', v_analysis.status::text,
      'enqueued', false,
      'pipeline_version', case when v_state.analysis_id is null then 1 else 2 end,
      'msg_id', v_state.active_msg_id,
      'generation', v_state.generation
    );
  end if;

  if v_analysis.status::text = 'completed' then
    return jsonb_build_object(
      'ok', true,
      'state', 'completed',
      'enqueued', false,
      'pipeline_version', case when v_state.analysis_id is null then 1 else 2 end
    );
  end if;

  if v_analysis.status::text = 'failed' then
    return jsonb_build_object(
      'ok', false,
      'code', 'analysis_already_failed',
      'state', 'failed',
      'enqueued', false
    );
  end if;

  if v_analysis.status::text <> 'pending' then
    return jsonb_build_object(
      'ok', false,
      'code', 'analysis_status_not_submittable',
      'state', v_analysis.status::text
    );
  end if;

  v_generation := coalesce(v_state.generation + 1, 1);
  v_message := (
    p_message
      - 'pipeline_version'
      - '__job_generation'
      - '__worker_claim_token'
      - '__queue_msg_id'
      - '__worker_attempt'
  ) ||
    jsonb_build_object(
      'analysis_id', p_analysis_id::text,
      'user_id', p_user_id::text,
      'job_mode', 'analysis',
      'pipeline_version', 2,
      '__job_generation', v_generation
    );

  select * into v_msg_id
  from pgmq.send('analysis_jobs', v_message, 0);

  insert into private.analysis_job_state (
    analysis_id,
    user_id,
    active_msg_id,
    job_mode,
    generation,
    claim_token,
    claimed_at,
    lease_expires_at,
    worker_attempt_count,
    updated_at
  ) values (
    p_analysis_id,
    p_user_id,
    v_msg_id,
    'analysis',
    v_generation,
    null,
    null,
    null,
    0,
    now()
  )
  on conflict (analysis_id) do update set
    user_id = excluded.user_id,
    active_msg_id = excluded.active_msg_id,
    job_mode = excluded.job_mode,
    generation = excluded.generation,
    claim_token = null,
    claimed_at = null,
    lease_expires_at = null,
    worker_attempt_count = 0,
    updated_at = now();

  update public.analyses
  set status = 'queued',
      queued_at = now(),
      status_message = coalesce(
        nullif(p_message->>'queued_status_message', ''),
        'Analiz kuyruğa alındı.'
      ),
      last_worker_error = null,
      failure_category = null,
      failure_code = null
  where id = p_analysis_id and user_id = p_user_id;

  return jsonb_build_object(
    'ok', true,
    'state', 'queued',
    'enqueued', true,
    'pipeline_version', 2,
    'msg_id', v_msg_id,
    'generation', v_generation
  );
end;
$$;


ALTER FUNCTION "public"."submit_analysis_job_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_message" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tg_create_profile_for_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(coalesce(new.email,''), '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end $$;


ALTER FUNCTION "public"."tg_create_profile_for_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tg_recalc_finding_count"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  update public.analyses
  set finding_count = (
    select count(*)
    from public.findings
    where analysis_id = coalesce(new.analysis_id, old.analysis_id)
  )
  where id = coalesce(new.analysis_id, old.analysis_id);

  return null;
end
$$;


ALTER FUNCTION "public"."tg_recalc_finding_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tg_set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
begin
  new.updated_at := now();
  return new;
end $$;


ALTER FUNCTION "public"."tg_set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."transition_analysis_to_repair_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_claim_token" "uuid", "p_message" "jsonb", "p_intermediate_raw_response" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_analysis public.analyses%rowtype;
  v_state private.analysis_job_state%rowtype;
  v_generation integer;
  v_msg_id bigint;
  v_message jsonb;
begin
  select * into v_analysis
  from public.analyses
  where id = p_analysis_id and user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'state', 'analysis_not_found');
  end if;
  if v_analysis.status::text = 'completed' then
    return jsonb_build_object('ok', false, 'state', 'completed');
  end if;

  select * into v_state
  from private.analysis_job_state
  where analysis_id = p_analysis_id and user_id = p_user_id
  for update;

  if not found
    or v_state.active_msg_id is distinct from p_msg_id
    or v_state.generation is distinct from p_generation
    or v_state.claim_token is distinct from p_claim_token
  then
    return jsonb_build_object('ok', false, 'state', 'lost_claim');
  end if;

  v_generation := v_state.generation + 1;
  v_message := (
    p_message
      - 'pipeline_version'
      - '__job_generation'
      - '__worker_claim_token'
      - '__queue_msg_id'
      - '__worker_attempt'
  ) ||
    jsonb_build_object(
      'analysis_id', p_analysis_id::text,
      'user_id', p_user_id::text,
      'job_mode', 'repair',
      'pipeline_version', 2,
      '__job_generation', v_generation
    );

  select * into v_msg_id
  from pgmq.send('analysis_jobs', v_message, 0);

  update private.analysis_job_state
  set active_msg_id = v_msg_id,
      job_mode = 'repair',
      generation = v_generation,
      claim_token = null,
      claimed_at = null,
      lease_expires_at = null,
      updated_at = now()
  where analysis_id = p_analysis_id;

  update public.analyses
  set status = 'queued',
      queued_at = now(),
      status_message = coalesce(
        nullif(p_message->>'queued_status_message', ''),
        'Analiz kapsamı ikinci taramaya alındı.'
      ),
      raw_ai_response = coalesce(p_intermediate_raw_response, raw_ai_response),
      last_worker_error = null,
      failure_category = null,
      failure_code = null
  where id = p_analysis_id and user_id = p_user_id;

  return jsonb_build_object(
    'ok', true,
    'state', 'repair_queued',
    'msg_id', v_msg_id,
    'generation', v_generation
  );
end;
$$;


ALTER FUNCTION "public"."transition_analysis_to_repair_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_claim_token" "uuid", "p_message" "jsonb", "p_intermediate_raw_response" "jsonb") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_onboarding_answers" (
    "user_id" "uuid" NOT NULL,
    "onboarding_version" "text" DEFAULT 'v2'::"text" NOT NULL,
    "certificate_class" "text",
    "hazard_classes" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "sectors" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "audit_frequency" "text",
    "selected_plan" "text",
    "raw_answers" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "completed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_onboarding_answers_certificate_check" CHECK ((("certificate_class" IS NULL) OR ("certificate_class" = ANY (ARRAY['A'::"text", 'B'::"text", 'C'::"text", 'doctor'::"text", 'otherHealth'::"text"])))),
    CONSTRAINT "user_onboarding_answers_frequency_check" CHECK ((("audit_frequency" IS NULL) OR ("audit_frequency" = ANY (ARRAY['1'::"text", '2-5'::"text", '6-15'::"text", '15+'::"text"])))),
    CONSTRAINT "user_onboarding_answers_hazards_check" CHECK ((("hazard_classes" <@ ARRAY['critical'::"text", 'high'::"text", 'low'::"text"]) AND ("cardinality"("hazard_classes") <= 3))),
    CONSTRAINT "user_onboarding_answers_plan_check" CHECK ((("selected_plan" IS NULL) OR ("selected_plan" = ANY (ARRAY['yearly'::"text", 'monthly'::"text"])))),
    CONSTRAINT "user_onboarding_answers_raw_object_check" CHECK (("jsonb_typeof"("raw_answers") = 'object'::"text")),
    CONSTRAINT "user_onboarding_answers_sectors_check" CHECK ((("sectors" <@ ARRAY['construction'::"text", 'manufacturing'::"text", 'energy'::"text", 'mining'::"text", 'office'::"text", 'other'::"text", 'logistics_warehouse'::"text", 'chemical_laboratory'::"text", 'healthcare'::"text", 'food_production'::"text", 'agriculture_livestock'::"text", 'retail'::"text", 'municipal_field_services'::"text", 'education'::"text", 'hospitality'::"text"]) AND ("cardinality"("sectors") <= 15))),
    CONSTRAINT "user_onboarding_answers_version_check" CHECK (("onboarding_version" = 'v2'::"text"))
);


ALTER TABLE "public"."user_onboarding_answers" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."upsert_onboarding_v2_answers"("p_onboarding_version" "text" DEFAULT 'v2'::"text", "p_certificate_class" "text" DEFAULT NULL::"text", "p_hazard_classes" "text"[] DEFAULT '{}'::"text"[], "p_sectors" "text"[] DEFAULT '{}'::"text"[], "p_audit_frequency" "text" DEFAULT NULL::"text", "p_selected_plan" "text" DEFAULT NULL::"text", "p_raw_answers" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "public"."user_onboarding_answers"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_hazard_classes text[];
  v_sectors text[];
  v_raw_answers jsonb := coalesce(p_raw_answers, '{}'::jsonb);
  v_row public.user_onboarding_answers;
  v_allowed_sectors text[] := array[
    'construction', 'manufacturing', 'energy', 'mining', 'office', 'other',
    'logistics_warehouse', 'chemical_laboratory', 'healthcare', 'food_production',
    'agriculture_livestock', 'retail', 'municipal_field_services', 'education', 'hospitality'
  ]::text[];
begin
  if v_user_id is null then raise exception 'auth_required' using errcode = '28000'; end if;
  v_hazard_classes := coalesce((select array_agg(distinct h order by h) from unnest(coalesce(p_hazard_classes, '{}'::text[])) as hazard(h) where h is not null and btrim(h) <> ''), '{}'::text[]);
  v_sectors := coalesce((select array_agg(distinct s order by s) from unnest(coalesce(p_sectors, '{}'::text[])) as sector(s) where s is not null and btrim(s) <> ''), '{}'::text[]);
  if p_onboarding_version is distinct from 'v2' then raise exception 'invalid_onboarding_version' using errcode = '22023'; end if;
  if p_certificate_class is not null and p_certificate_class not in ('A', 'B', 'C', 'doctor', 'otherHealth') then raise exception 'invalid_certificate_class' using errcode = '22023'; end if;
  if not (v_hazard_classes <@ array['critical', 'high', 'low']::text[]) or cardinality(v_hazard_classes) > 3 then raise exception 'invalid_hazard_classes' using errcode = '22023'; end if;
  if not (v_sectors <@ v_allowed_sectors) or cardinality(v_sectors) > 15 then raise exception 'invalid_sectors' using errcode = '22023'; end if;
  if p_audit_frequency is not null and p_audit_frequency not in ('1', '2-5', '6-15', '15+') then raise exception 'invalid_audit_frequency' using errcode = '22023'; end if;
  if p_selected_plan is not null and p_selected_plan not in ('yearly', 'monthly') then raise exception 'invalid_selected_plan' using errcode = '22023'; end if;
  if jsonb_typeof(v_raw_answers) is distinct from 'object' then raise exception 'invalid_raw_answers' using errcode = '22023'; end if;
  insert into public.user_onboarding_answers (user_id, onboarding_version, certificate_class, hazard_classes, sectors, audit_frequency, selected_plan, raw_answers, completed_at)
  values (v_user_id, 'v2', p_certificate_class, v_hazard_classes, v_sectors, p_audit_frequency, p_selected_plan, v_raw_answers, now())
  on conflict (user_id) do update set onboarding_version = excluded.onboarding_version, certificate_class = coalesce(excluded.certificate_class, user_onboarding_answers.certificate_class), hazard_classes = case when cardinality(excluded.hazard_classes) > 0 then excluded.hazard_classes else user_onboarding_answers.hazard_classes end, sectors = case when cardinality(excluded.sectors) > 0 then excluded.sectors else user_onboarding_answers.sectors end, audit_frequency = coalesce(excluded.audit_frequency, user_onboarding_answers.audit_frequency), selected_plan = coalesce(excluded.selected_plan, user_onboarding_answers.selected_plan), raw_answers = coalesce(user_onboarding_answers.raw_answers, '{}'::jsonb) || excluded.raw_answers, completed_at = now()
  returning * into v_row;
  return v_row;
end;
$$;


ALTER FUNCTION "public"."upsert_onboarding_v2_answers"("p_onboarding_version" "text", "p_certificate_class" "text", "p_hazard_classes" "text"[], "p_sectors" "text"[], "p_audit_frequency" "text", "p_selected_plan" "text", "p_raw_answers" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_analysis_job_claim_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_claim_token" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select case
    when a.id is null then jsonb_build_object('ok', false, 'state', 'analysis_not_found')
    when a.status::text = 'completed' then jsonb_build_object('ok', false, 'state', 'completed')
    when a.status::text = 'failed' then jsonb_build_object('ok', false, 'state', 'failed')
    when s.analysis_id is null then jsonb_build_object('ok', false, 'state', 'job_state_missing')
    when s.active_msg_id is distinct from p_msg_id
      or s.generation is distinct from p_generation
      then jsonb_build_object('ok', false, 'state', 'superseded')
    when s.claim_token is distinct from p_claim_token
      then jsonb_build_object('ok', false, 'state', 'lost_claim')
    when s.lease_expires_at is null or s.lease_expires_at <= now()
      then jsonb_build_object('ok', false, 'state', 'lease_expired')
    else jsonb_build_object(
      'ok', true,
      'state', 'claimed',
      'worker_attempt', s.worker_attempt_count,
      'job_mode', s.job_mode,
      'lease_expires_at', s.lease_expires_at
    )
  end
  from (select 1) seed
  left join public.analyses a
    on a.id = p_analysis_id and a.user_id = p_user_id
  left join private.analysis_job_state s
    on s.analysis_id = a.id and s.user_id = a.user_id;
$$;


ALTER FUNCTION "public"."validate_analysis_job_claim_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_claim_token" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_notification_job_v1"("p_job_id" "uuid", "p_claim_token" "uuid", "p_now" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_job private.notification_jobs;
  v_flag jsonb := private.notification_feature_flag();
  v_rule_status text;
  v_campaign_status text;
  v_last_meaningful_activity timestamptz;
  v_onboarding_anchor timestamptz;
  v_existing_sent_event_id uuid;
  v_reason text;
  v_defer_until timestamptz;
begin
  select * into v_job
  from private.notification_jobs
  where id = p_job_id
  for update;

  if not found
     or v_job.status <> 'claimed'
     or v_job.claim_token is distinct from p_claim_token then
    return jsonb_build_object('allowed', false, 'reason', 'lost_claim');
  end if;

  if v_job.lease_expires_at <= p_now then
    return jsonb_build_object('allowed', false, 'reason', 'lease_expired');
  end if;

  select ne.id into v_existing_sent_event_id
  from public.notification_events ne
  where ne.job_id = v_job.id
    and ne.status = 'sent'
  order by ne.created_at
  limit 1;

  if v_existing_sent_event_id is not null then
    update private.notification_jobs
    set status = 'sent',
        notification_event_id = v_existing_sent_event_id,
        claim_token = null,
        claimed_at = null,
        lease_expires_at = null,
        completed_at = p_now,
        last_error_code = 'already_delivered_current_job',
        last_error_text = null,
        updated_at = p_now
    where id = p_job_id
      and claim_token = p_claim_token;

    return jsonb_build_object(
      'allowed', false,
      'reason', 'already_delivered_current_job',
      'event_id', v_existing_sent_event_id
    );
  end if;

  if coalesce((v_flag->>'kill_switch')::boolean, true)
     or coalesce(v_flag->>'rollout_mode', 'off') = 'off'
     or not private.notification_rollout_allows(v_flag, v_job.user_id) then
    v_reason := 'automation_disabled';
  end if;

  if v_reason is null and v_job.rule_id is not null then
    select status into v_rule_status
    from private.notification_rules
    where id = v_job.rule_id;
    if v_rule_status = 'paused' then
      v_reason := 'rule_paused';
    elsif v_rule_status not in ('allowlist', 'active') then
      v_reason := 'rule_inactive';
    end if;
  end if;

  if v_reason is null and v_job.campaign_id is not null then
    select status into v_campaign_status
    from private.notification_campaigns
    where id = v_job.campaign_id;
    if v_campaign_status = 'paused' then
      v_reason := 'campaign_paused';
    elsif v_campaign_status not in ('scheduled', 'running') then
      v_reason := 'campaign_inactive';
    end if;
  end if;

  if v_reason is null and not exists (
    select 1
    from public.notification_preferences p
    where p.user_id = v_job.user_id
      and p.enabled
      and p.app_reminders
  ) then
    v_reason := 'user_preference_disabled';
  end if;

  if v_reason is null and not exists (
    select 1
    from public.user_engagement_state e
    where e.user_id = v_job.user_id
      and e.authorization_status in ('authorized', 'provisional', 'ephemeral')
      and e.timezone = v_job.timezone
  ) then
    v_reason := 'authorization_or_timezone_changed';
  end if;

  if v_reason is null and (
    (p_now at time zone v_job.timezone)::time < time '10:00'
    or (p_now at time zone v_job.timezone)::time >= time '20:00'
  ) then
    v_reason := 'outside_local_window';
    v_defer_until := (
      case
        when (p_now at time zone v_job.timezone)::time < time '10:00'
          then (p_now at time zone v_job.timezone)::date
        else (p_now at time zone v_job.timezone)::date + 1
      end + time '10:00'
    ) at time zone v_job.timezone;
  end if;

  if v_reason is null and not exists (
    select 1
    from public.push_device_tokens dt
    where dt.user_id = v_job.user_id
      and dt.environment = 'production'
      and dt.notifications_enabled
  ) then
    v_reason := 'no_active_production_token';
  end if;

  if v_reason is null and exists (
    select 1
    from public.notification_events ne
    where ne.user_id = v_job.user_id
      and ne.status = 'sent'
      and ne.created_at > p_now - interval '24 hours'
  ) then
    v_reason := 'recent_push';
    select max(ne.created_at) + interval '24 hours 1 second'
    into v_defer_until
    from public.notification_events ne
    where ne.user_id = v_job.user_id
      and ne.status = 'sent'
      and ne.created_at > p_now - interval '24 hours';
  end if;

  if v_reason is null and (
    select count(*)
    from public.notification_events ne
    where ne.user_id = v_job.user_id
      and ne.kind in (
        'first_analysis_reminder',
        'inactivity_reminder',
        'manual_app_reminder'
      )
      and ne.status = 'sent'
      and ne.created_at > p_now - interval '7 days'
  ) >= 1 then
    v_reason := 'frequency_cap_7d';
    select max(ne.created_at) + interval '7 days 1 second'
    into v_defer_until
    from public.notification_events ne
    where ne.user_id = v_job.user_id
      and ne.kind in (
        'first_analysis_reminder',
        'inactivity_reminder',
        'manual_app_reminder'
      )
      and ne.status = 'sent'
      and ne.created_at > p_now - interval '7 days';
  end if;

  if v_reason is null and (
    select count(*)
    from public.notification_events ne
    where ne.user_id = v_job.user_id
      and ne.kind in (
        'first_analysis_reminder',
        'inactivity_reminder',
        'manual_app_reminder'
      )
      and ne.status = 'sent'
      and ne.created_at > p_now - interval '30 days'
  ) >= 2 then
    v_reason := 'frequency_cap_30d';
    select min(ne.created_at) + interval '30 days 1 second'
    into v_defer_until
    from public.notification_events ne
    where ne.user_id = v_job.user_id
      and ne.kind in (
        'first_analysis_reminder',
        'inactivity_reminder',
        'manual_app_reminder'
      )
      and ne.status = 'sent'
      and ne.created_at > p_now - interval '30 days';
  end if;

  if v_reason is null and v_job.kind = 'first_analysis_reminder' then
    select coalesce(o.completed_at, u.created_at)
    into v_onboarding_anchor
    from auth.users u
    left join public.user_onboarding_answers o on o.user_id = u.id
    where u.id = v_job.user_id;

    if v_onboarding_anchor is null
       or p_now < v_onboarding_anchor + interval '24 hours'
       or p_now >= v_onboarding_anchor + interval '72 hours' then
      v_reason := 'first_analysis_window_closed';
    elsif exists (
      select 1
      from public.notification_events ne
      where ne.user_id = v_job.user_id
        and ne.kind = 'first_analysis_reminder'
        and ne.status = 'sent'
    ) then
      v_reason := 'first_analysis_already_sent';
    elsif exists (
      select 1
      from public.analyses a
      where a.user_id = v_job.user_id
        and (
          a.status::text <> 'pending'
          or a.queued_at is not null
          or a.worker_started_at is not null
        )
    ) then
      v_reason := 'analysis_submitted';
    end if;
  end if;

  if v_reason is null and v_job.kind = 'inactivity_reminder' then
    select greatest(
      e.last_foreground_at,
      coalesce(
        (
          select max(greatest(a.updated_at, coalesce(a.completed_at, a.created_at)))
          from public.analyses a
          where a.user_id = v_job.user_id
            and a.status::text = 'completed'
        ),
        '-infinity'::timestamptz
      ),
      coalesce(
        (
          select max(r.created_at)
          from public.reports r
          where r.user_id = v_job.user_id
        ),
        '-infinity'::timestamptz
      )
    )
    into v_last_meaningful_activity
    from public.user_engagement_state e
    where e.user_id = v_job.user_id;

    if v_last_meaningful_activity is null
       or v_last_meaningful_activity > p_now - interval '5 days'
       or extract(epoch from v_last_meaningful_activity)::bigint::text
          <> v_job.episode_key then
      v_reason := 'inactivity_episode_changed';
    elsif exists (
      select 1
      from public.notification_events ne
      join private.notification_jobs prior_job
        on prior_job.id = ne.job_id
      where ne.user_id = v_job.user_id
        and ne.kind = 'inactivity_reminder'
        and ne.status = 'sent'
        and prior_job.episode_key = v_job.episode_key
        and prior_job.id <> v_job.id
    ) then
      v_reason := 'inactivity_episode_already_sent';
    end if;
  end if;

  if v_reason in (
    'automation_disabled',
    'rule_paused',
    'campaign_paused',
    'outside_local_window',
    'recent_push',
    'frequency_cap_7d',
    'frequency_cap_30d'
  ) then
    v_defer_until := greatest(
      coalesce(v_defer_until, p_now + interval '15 minutes'),
      p_now + interval '1 minute'
    );

    update private.notification_jobs
    set status = 'pending',
        due_at = v_defer_until,
        attempt_count = greatest(attempt_count - 1, 0),
        claim_token = null,
        claimed_at = null,
        lease_expires_at = null,
        completed_at = null,
        last_error_code = v_reason,
        last_error_text = null,
        updated_at = p_now
    where id = p_job_id
      and claim_token = p_claim_token;

    return jsonb_build_object(
      'allowed', false,
      'reason', v_reason,
      'deferred', true,
      'due_at', v_defer_until
    );
  end if;

  if v_reason is not null then
    update private.notification_jobs
    set status = case
          when v_reason in ('rule_inactive', 'campaign_inactive')
            then 'cancelled'
          else 'skipped'
        end,
        claim_token = null,
        claimed_at = null,
        lease_expires_at = null,
        completed_at = p_now,
        last_error_code = v_reason,
        last_error_text = null,
        updated_at = p_now
    where id = p_job_id
      and claim_token = p_claim_token;

    return jsonb_build_object('allowed', false, 'reason', v_reason);
  end if;

  return jsonb_build_object(
    'allowed', true,
    'reason', 'allowed',
    'job_id', v_job.id,
    'attempt_count', v_job.attempt_count
  );
end;
$$;


ALTER FUNCTION "public"."validate_notification_job_v1"("p_job_id" "uuid", "p_claim_token" "uuid", "p_now" timestamp with time zone) OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."analysis_job_events" (
    "id" bigint NOT NULL,
    "analysis_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "msg_id" bigint NOT NULL,
    "job_generation" integer NOT NULL,
    "worker_attempt" integer NOT NULL,
    "job_mode" "text" NOT NULL,
    "event_type" "text" NOT NULL,
    "http_status" integer,
    "response_code" "text",
    "claim_action" "text",
    "safe_error_text" character varying(500),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "analysis_job_events_event_type_check" CHECK (("event_type" = ANY (ARRAY['claim_acquired'::"text", 'dispatch_success_response'::"text", 'dispatch_application_error'::"text", 'dispatch_ambiguous_transport'::"text", 'claim_kept'::"text", 'claim_released_for_retry'::"text", 'terminal_failed'::"text", 'repair_superseded'::"text", 'finalized'::"text", 'message_deleted_after_response_loss'::"text", 'lease_expired_retry'::"text", 'max_attempts'::"text"]))),
    CONSTRAINT "analysis_job_events_http_status_check" CHECK ((("http_status" IS NULL) OR (("http_status" >= 100) AND ("http_status" <= 599)))),
    CONSTRAINT "analysis_job_events_job_generation_check" CHECK (("job_generation" > 0)),
    CONSTRAINT "analysis_job_events_job_mode_check" CHECK (("job_mode" = ANY (ARRAY['analysis'::"text", 'repair'::"text"]))),
    CONSTRAINT "analysis_job_events_worker_attempt_check" CHECK (("worker_attempt" > 0))
);


ALTER TABLE "private"."analysis_job_events" OWNER TO "postgres";


ALTER TABLE "private"."analysis_job_events" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "private"."analysis_job_events_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "private"."analysis_job_state" (
    "analysis_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "active_msg_id" bigint,
    "job_mode" "text" DEFAULT 'analysis'::"text" NOT NULL,
    "generation" integer DEFAULT 1 NOT NULL,
    "claim_token" "uuid",
    "claimed_at" timestamp with time zone,
    "lease_expires_at" timestamp with time zone,
    "worker_attempt_count" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "analysis_job_state_generation_check" CHECK (("generation" > 0)),
    CONSTRAINT "analysis_job_state_job_mode_check" CHECK (("job_mode" = ANY (ARRAY['analysis'::"text", 'repair'::"text"]))),
    CONSTRAINT "analysis_job_state_worker_attempt_count_check" CHECK (("worker_attempt_count" >= 0))
);


ALTER TABLE "private"."analysis_job_state" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."notification_campaigns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "template_id" "uuid",
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "destination" "text" DEFAULT 'home'::"text" NOT NULL,
    "target_spec" "jsonb" DEFAULT '{"audience": "allowlist", "user_hashes": []}'::"jsonb" NOT NULL,
    "scheduled_at" timestamp with time zone,
    "started_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notification_campaigns_body_check" CHECK ((("char_length"("body") >= 1) AND ("char_length"("body") <= 240))),
    CONSTRAINT "notification_campaigns_destination_check" CHECK (("destination" = ANY (ARRAY['home'::"text", 'new_analysis'::"text", 'profile'::"text"]))),
    CONSTRAINT "notification_campaigns_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'scheduled'::"text", 'running'::"text", 'paused'::"text", 'cancelled'::"text", 'completed'::"text"]))),
    CONSTRAINT "notification_campaigns_target_spec_check" CHECK (("jsonb_typeof"("target_spec") = 'object'::"text")),
    CONSTRAINT "notification_campaigns_title_check" CHECK ((("char_length"("title") >= 1) AND ("char_length"("title") <= 80)))
);


ALTER TABLE "private"."notification_campaigns" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."notification_delivery_attempts" (
    "id" bigint NOT NULL,
    "notification_event_id" "uuid" NOT NULL,
    "job_id" "uuid",
    "push_device_token_id" "uuid",
    "environment" "text" NOT NULL,
    "attempt_number" integer NOT NULL,
    "outcome" "text" NOT NULL,
    "http_status" integer,
    "apns_id" "text",
    "reason" "text",
    "duration_ms" integer,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notification_delivery_attempt_check" CHECK ((("attempt_number" >= 1) AND ("attempt_number" <= 3))),
    CONSTRAINT "notification_delivery_duration_check" CHECK ((("duration_ms" IS NULL) OR ("duration_ms" >= 0))),
    CONSTRAINT "notification_delivery_environment_check" CHECK (("environment" = ANY (ARRAY['sandbox'::"text", 'production'::"text"]))),
    CONSTRAINT "notification_delivery_http_status_check" CHECK ((("http_status" IS NULL) OR (("http_status" >= 100) AND ("http_status" <= 599)))),
    CONSTRAINT "notification_delivery_outcome_check" CHECK (("outcome" = ANY (ARRAY['accepted'::"text", 'transient'::"text", 'permanent'::"text", 'ambiguous'::"text"]))),
    CONSTRAINT "notification_delivery_reason_length_check" CHECK ((("reason" IS NULL) OR ("char_length"("reason") <= 500)))
);


ALTER TABLE "private"."notification_delivery_attempts" OWNER TO "postgres";


ALTER TABLE "private"."notification_delivery_attempts" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "private"."notification_delivery_attempts_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "private"."notification_jobs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "rule_id" "uuid",
    "rule_version_id" "uuid",
    "campaign_id" "uuid",
    "template_id" "uuid",
    "kind" "text" NOT NULL,
    "episode_key" "text" NOT NULL,
    "dedupe_key" "text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "due_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "timezone" "text" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "destination" "text" NOT NULL,
    "payload_data" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "eligibility_snapshot" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "attempt_count" integer DEFAULT 0 NOT NULL,
    "claim_token" "uuid",
    "claimed_at" timestamp with time zone,
    "lease_expires_at" timestamp with time zone,
    "notification_event_id" "uuid",
    "last_error_code" "text",
    "last_error_text" "text",
    "completed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notification_jobs_attempt_count_check" CHECK ((("attempt_count" >= 0) AND ("attempt_count" <= 3))),
    CONSTRAINT "notification_jobs_body_check" CHECK ((("char_length"("body") >= 1) AND ("char_length"("body") <= 240))),
    CONSTRAINT "notification_jobs_destination_check" CHECK (("destination" = ANY (ARRAY['home'::"text", 'new_analysis'::"text", 'profile'::"text"]))),
    CONSTRAINT "notification_jobs_kind_check" CHECK (("kind" = ANY (ARRAY['first_analysis_reminder'::"text", 'inactivity_reminder'::"text", 'manual_app_reminder'::"text"]))),
    CONSTRAINT "notification_jobs_owner_check" CHECK ((((("rule_id" IS NOT NULL))::integer + (("campaign_id" IS NOT NULL))::integer) = 1)),
    CONSTRAINT "notification_jobs_payload_check" CHECK (("jsonb_typeof"("payload_data") = 'object'::"text")),
    CONSTRAINT "notification_jobs_snapshot_check" CHECK (("jsonb_typeof"("eligibility_snapshot") = 'object'::"text")),
    CONSTRAINT "notification_jobs_status_check" CHECK (("status" = ANY (ARRAY['shadow'::"text", 'pending'::"text", 'claimed'::"text", 'sent'::"text", 'skipped'::"text", 'failed'::"text", 'cancelled'::"text", 'ambiguous'::"text"]))),
    CONSTRAINT "notification_jobs_title_check" CHECK ((("char_length"("title") >= 1) AND ("char_length"("title") <= 80)))
);


ALTER TABLE "private"."notification_jobs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."notification_rule_versions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rule_id" "uuid" NOT NULL,
    "version" integer NOT NULL,
    "conditions" "jsonb" NOT NULL,
    "template_snapshot" "jsonb" NOT NULL,
    "enabled_user_hashes" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "published_at" timestamp with time zone,
    CONSTRAINT "notification_rule_versions_conditions_check" CHECK (("jsonb_typeof"("conditions") = 'object'::"text")),
    CONSTRAINT "notification_rule_versions_hash_count_check" CHECK (("cardinality"("enabled_user_hashes") <= 1000)),
    CONSTRAINT "notification_rule_versions_template_snapshot_check" CHECK (("jsonb_typeof"("template_snapshot") = 'object'::"text")),
    CONSTRAINT "notification_rule_versions_version_check" CHECK (("version" > 0))
);


ALTER TABLE "private"."notification_rule_versions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."notification_rules" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "key" "text" NOT NULL,
    "name" "text" NOT NULL,
    "rule_type" "text" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "template_id" "uuid" NOT NULL,
    "current_version_id" "uuid",
    "priority" integer DEFAULT 100 NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notification_rules_key_check" CHECK (("key" ~ '^[a-z0-9][a-z0-9_]{2,79}$'::"text")),
    CONSTRAINT "notification_rules_priority_check" CHECK ((("priority" >= 1) AND ("priority" <= 1000))),
    CONSTRAINT "notification_rules_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'shadow'::"text", 'allowlist'::"text", 'active'::"text", 'paused'::"text", 'archived'::"text"]))),
    CONSTRAINT "notification_rules_type_check" CHECK (("rule_type" = ANY (ARRAY['first_analysis'::"text", 'inactivity'::"text"])))
);


ALTER TABLE "private"."notification_rules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."notification_templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "key" "text" NOT NULL,
    "name" "text" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "destination" "text" DEFAULT 'home'::"text" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "variables" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notification_templates_body_check" CHECK ((("char_length"("body") >= 1) AND ("char_length"("body") <= 240))),
    CONSTRAINT "notification_templates_destination_check" CHECK (("destination" = ANY (ARRAY['home'::"text", 'new_analysis'::"text", 'profile'::"text"]))),
    CONSTRAINT "notification_templates_key_check" CHECK (("key" ~ '^[a-z0-9][a-z0-9_]{2,79}$'::"text")),
    CONSTRAINT "notification_templates_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'active'::"text", 'archived'::"text"]))),
    CONSTRAINT "notification_templates_title_check" CHECK ((("char_length"("title") >= 1) AND ("char_length"("title") <= 80))),
    CONSTRAINT "notification_templates_variables_check" CHECK (("jsonb_typeof"("variables") = 'array'::"text"))
);


ALTER TABLE "private"."notification_templates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."support_request_rate_limits" (
    "user_id" "uuid" NOT NULL,
    "hour_window_start" timestamp with time zone NOT NULL,
    "hour_count" integer DEFAULT 0 NOT NULL,
    "day_window_start" timestamp with time zone NOT NULL,
    "day_count" integer DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "support_request_rate_limits_day_count_check" CHECK (("day_count" >= 0)),
    CONSTRAINT "support_request_rate_limits_hour_count_check" CHECK (("hour_count" >= 0))
);


ALTER TABLE "private"."support_request_rate_limits" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."account_deletion_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "email" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "requested_scope" "text" DEFAULT 'account_and_data'::"text" NOT NULL,
    "note" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "processing_started_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "processed_by" "text",
    "completion_support_id" "text",
    "completion_error" "text",
    "target_user_id" "uuid",
    "target_email" "text",
    "target_user_hash" "text",
    "deleted_photo_objects" integer DEFAULT 0 NOT NULL,
    "deleted_report_objects" integer DEFAULT 0 NOT NULL,
    "deleted_logo_objects" integer DEFAULT 0 NOT NULL,
    "auth_user_deleted" boolean DEFAULT false NOT NULL,
    "deleted_avatar_objects" integer DEFAULT 0 NOT NULL,
    CONSTRAINT "account_deletion_requests_requested_scope_check" CHECK (("requested_scope" = ANY (ARRAY['account_and_data'::"text", 'data_only'::"text"]))),
    CONSTRAINT "account_deletion_requests_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'processing'::"text", 'completed'::"text", 'cancelled'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."account_deletion_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."admin_alert_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rule_id" "uuid" NOT NULL,
    "rule_key" "text" NOT NULL,
    "severity" "text" NOT NULL,
    "title" "text" NOT NULL,
    "message" "text" NOT NULL,
    "metric_key" "text" NOT NULL,
    "metric_value" numeric NOT NULL,
    "threshold" numeric NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "fingerprint" "text" NOT NULL,
    "acknowledged_at" timestamp with time zone,
    "acknowledged_by" "uuid",
    "resolved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "admin_alert_events_severity_check" CHECK (("severity" = ANY (ARRAY['critical'::"text", 'warning'::"text", 'info'::"text"]))),
    CONSTRAINT "admin_alert_events_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'acknowledged'::"text", 'resolved'::"text"])))
);


ALTER TABLE "public"."admin_alert_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."admin_alert_rules" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rule_key" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text" DEFAULT ''::"text" NOT NULL,
    "metric_key" "text" NOT NULL,
    "operator" "text" NOT NULL,
    "threshold" numeric NOT NULL,
    "severity" "text" DEFAULT 'warning'::"text" NOT NULL,
    "is_enabled" boolean DEFAULT true NOT NULL,
    "cooldown_minutes" integer DEFAULT 60 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "admin_alert_rules_cooldown_check" CHECK ((("cooldown_minutes" >= 5) AND ("cooldown_minutes" <= 1440))),
    CONSTRAINT "admin_alert_rules_operator_check" CHECK (("operator" = ANY (ARRAY['gt'::"text", 'gte'::"text", 'lt'::"text", 'lte'::"text", 'eq'::"text"]))),
    CONSTRAINT "admin_alert_rules_severity_check" CHECK (("severity" = ANY (ARRAY['critical'::"text", 'warning'::"text", 'info'::"text"])))
);


ALTER TABLE "public"."admin_alert_rules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."admin_audit_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "admin_user_id" "uuid",
    "admin_email" "text",
    "action" "text" NOT NULL,
    "target_type" "text",
    "target_id" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "ip_hash" "text",
    "user_agent_hash" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."admin_audit_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."admin_exports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "admin_user_id" "uuid",
    "admin_email" "text",
    "resource" "text" NOT NULL,
    "format" "text" NOT NULL,
    "reason" "text" NOT NULL,
    "filter_json" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "row_count" integer DEFAULT 0 NOT NULL,
    "file_name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "admin_exports_format_check" CHECK (("format" = ANY (ARRAY['csv'::"text", 'xlsx'::"text"]))),
    CONSTRAINT "admin_exports_resource_check" CHECK (("resource" = ANY (ARRAY['users'::"text", 'analyses'::"text", 'reports'::"text", 'subscriptions'::"text", 'support'::"text", 'deletion'::"text", 'audit-logs'::"text"])))
);


ALTER TABLE "public"."admin_exports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."admin_notes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "admin_user_id" "uuid" NOT NULL,
    "target_type" "text" NOT NULL,
    "target_id" "text" NOT NULL,
    "body" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "admin_notes_body_check" CHECK ((("char_length"(TRIM(BOTH FROM "body")) > 0) AND ("char_length"("body") <= 2000))),
    CONSTRAINT "admin_notes_target_type_check" CHECK (("target_type" = ANY (ARRAY['user'::"text", 'analysis'::"text", 'support'::"text", 'deletion'::"text"])))
);


ALTER TABLE "public"."admin_notes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."admin_rate_limit_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "bucket" "text" NOT NULL,
    "key_hash" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."admin_rate_limit_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."admin_saved_filters" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "admin_user_id" "uuid" NOT NULL,
    "resource" "text" NOT NULL,
    "name" "text" NOT NULL,
    "filter_json" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "admin_saved_filters_resource_check" CHECK (("resource" = ANY (ARRAY['users'::"text", 'analyses'::"text", 'reports'::"text", 'subscriptions'::"text", 'support'::"text", 'deletion'::"text", 'audit-logs'::"text"])))
);


ALTER TABLE "public"."admin_saved_filters" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."admin_users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "role" "text" DEFAULT 'owner'::"text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "mfa_required" boolean DEFAULT true NOT NULL,
    "allowed_scopes" "text"[] DEFAULT ARRAY['*'::"text"] NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "last_login_at" timestamp with time zone,
    CONSTRAINT "admin_users_role_check" CHECK (("role" = ANY (ARRAY['owner'::"text", 'support'::"text", 'finance'::"text", 'analyst'::"text", 'legal_ops'::"text"])))
);


ALTER TABLE "public"."admin_users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ai_usage_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "analysis_id" "uuid",
    "user_id" "uuid" NOT NULL,
    "provider" "text" DEFAULT 'gemini'::"text" NOT NULL,
    "model" "text" NOT NULL,
    "tokens_in" integer DEFAULT 0 NOT NULL,
    "tokens_out" integer DEFAULT 0 NOT NULL,
    "duration_ms" integer DEFAULT 0 NOT NULL,
    "error" "text",
    "user_plan" "text" DEFAULT 'free'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "request_id" "text",
    "support_id" "text",
    "error_code" "text",
    "http_status" integer,
    "fallback_source" "text",
    "api_key_alias" "text",
    "attempt_count" integer,
    "prompt_version" "text",
    "personalization_version" "text",
    "context_hash" "text",
    "cached_tokens" integer,
    "thoughts_tokens" integer,
    "total_tokens" integer,
    "quality_tier" "text",
    "ai_execution_route" "text",
    "job_mode" "text",
    "job_generation" integer,
    "worker_attempt" integer,
    "persistence_outcome" "text" DEFAULT 'not_started'::"text" NOT NULL,
    "persistence_error_code" "text",
    "persistence_updated_at" timestamp with time zone,
    "coverage_schema_version" integer,
    "coverage_contract_outcome" "text",
    "coverage_expected_records" integer,
    "coverage_returned_records" integer,
    "coverage_schema_fallback_used" boolean DEFAULT false NOT NULL,
    "provider_request_count" integer DEFAULT 0 NOT NULL,
    "provider_attempt_total_tokens" bigint DEFAULT 0 NOT NULL,
    "provider_attempts" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    CONSTRAINT "ai_usage_logs_ai_execution_route_check" CHECK (("ai_execution_route" = ANY (ARRAY['free_legacy'::"text", 'free_paid_trial'::"text", 'paid_plan'::"text", 'cancelled_plus_trial_free'::"text"]))),
    CONSTRAINT "ai_usage_logs_coverage_contract_outcome_check" CHECK ((("coverage_contract_outcome" IS NULL) OR ("coverage_contract_outcome" = ANY (ARRAY['not_applicable'::"text", 'complete'::"text", 'normalized_contract_violation'::"text", 'missing_records'::"text"])))),
    CONSTRAINT "ai_usage_logs_coverage_expected_records_check" CHECK ((("coverage_expected_records" IS NULL) OR ("coverage_expected_records" >= 0))),
    CONSTRAINT "ai_usage_logs_coverage_returned_records_check" CHECK ((("coverage_returned_records" IS NULL) OR ("coverage_returned_records" >= 0))),
    CONSTRAINT "ai_usage_logs_coverage_schema_version_check" CHECK ((("coverage_schema_version" IS NULL) OR ("coverage_schema_version" = ANY (ARRAY[1, 2])))),
    CONSTRAINT "ai_usage_logs_job_mode_check" CHECK ((("job_mode" IS NULL) OR ("job_mode" = ANY (ARRAY['analysis'::"text", 'repair'::"text"])))),
    CONSTRAINT "ai_usage_logs_persistence_outcome_check" CHECK ((("persistence_outcome" IS NULL) OR ("persistence_outcome" = ANY (ARRAY['not_started'::"text", 'pending'::"text", 'persisted'::"text", 'failed'::"text", 'discarded'::"text"])))),
    CONSTRAINT "ai_usage_logs_provider_attempt_total_tokens_check" CHECK (("provider_attempt_total_tokens" >= 0)),
    CONSTRAINT "ai_usage_logs_provider_attempts_check" CHECK ((("jsonb_typeof"("provider_attempts") = 'array'::"text") AND ("jsonb_array_length"("provider_attempts") <= 32))),
    CONSTRAINT "ai_usage_logs_provider_request_count_check" CHECK (("provider_request_count" >= 0)),
    CONSTRAINT "ai_usage_logs_quality_tier_check" CHECK (("quality_tier" = ANY (ARRAY['free'::"text", 'plus'::"text", 'pro'::"text"])))
);


ALTER TABLE "public"."ai_usage_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."analyses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "title" "text" DEFAULT 'Adsız analiz'::"text" NOT NULL,
    "kind" "public"."analysis_kind" NOT NULL,
    "canvas" "public"."canvas_id" DEFAULT 'general'::"public"."canvas_id" NOT NULL,
    "text_input" "text",
    "status" "public"."analysis_status" DEFAULT 'pending'::"public"."analysis_status" NOT NULL,
    "status_message" "text",
    "started_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "ai_models_used" "text"[],
    "primary_method" "public"."risk_method" DEFAULT 'fine_kinney'::"public"."risk_method" NOT NULL,
    "ai_summary" "text",
    "total_score_fk" numeric,
    "total_score_m5" integer,
    "highest_band_fk" "public"."risk_level",
    "highest_band_m5" "public"."risk_level",
    "finding_count" integer DEFAULT 0 NOT NULL,
    "review_status" "public"."analysis_review_status" DEFAULT 'open'::"public"."analysis_review_status" NOT NULL,
    "location" "text",
    "raw_ai_response" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "raw_ai_response_expires_at" timestamp with time zone,
    "analysis_mode" "text" DEFAULT 'standard'::"text" NOT NULL,
    "company_id" "uuid",
    "queued_at" timestamp with time zone,
    "worker_started_at" timestamp with time zone,
    "last_worker_error" "text",
    "worker_attempt_count" integer DEFAULT 0 NOT NULL,
    "completion_push_sent_at" timestamp with time zone,
    "analysis_sector" "text",
    "analysis_sector_source" "text",
    "analysis_sector_prompt_version" "text",
    "input_payload_version" "text" DEFAULT 'analysis-v1'::"text" NOT NULL,
    "photo_count" integer DEFAULT 0 NOT NULL,
    "max_photos_allowed_at_creation" integer,
    "max_findings_per_photo" integer DEFAULT 12 NOT NULL,
    "max_findings_total" integer,
    "generated_findings_count" integer DEFAULT 0 NOT NULL,
    "visible_findings_count" integer DEFAULT 0 NOT NULL,
    "hidden_or_rejected_findings_count" integer DEFAULT 0 NOT NULL,
    "has_user_edits" boolean DEFAULT false NOT NULL,
    "user_edit_count" integer DEFAULT 0 NOT NULL,
    "analysis_edit_version" integer DEFAULT 0 NOT NULL,
    "finalized_for_report_at" timestamp with time zone,
    "plan_at_creation" "text",
    "capability_snapshot" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "rollout_snapshot" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "failure_category" "text",
    "failure_code" "text",
    CONSTRAINT "analyses_analysis_mode_check" CHECK (("analysis_mode" = ANY (ARRAY['standard'::"text", 'detailed'::"text", 'emergency'::"text", 'procedure'::"text"]))),
    CONSTRAINT "analyses_failure_category_check" CHECK ((("failure_category" IS NULL) OR ("failure_category" = ANY (ARRAY['business'::"text", 'technical'::"text"])))),
    CONSTRAINT "analyses_photo_count_check" CHECK (("photo_count" >= 0))
);


ALTER TABLE "public"."analyses" OWNER TO "postgres";


COMMENT ON COLUMN "public"."analyses"."analysis_sector" IS 'Canonical active sector selected by the user for this specific analysis. Nullable for legacy clients/old analyses.';



COMMENT ON COLUMN "public"."analyses"."analysis_sector_source" IS 'Source of active analysis sector: user_selected, legacy_missing, system_migrated, etc.';



COMMENT ON COLUMN "public"."analyses"."analysis_sector_prompt_version" IS 'Prompt/guidance version used for active sector context.';



CREATE TABLE IF NOT EXISTS "public"."analysis_photo_summaries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "analysis_id" "uuid" NOT NULL,
    "photo_id" "uuid",
    "user_id" "uuid" NOT NULL,
    "photo_sequence_index" integer NOT NULL,
    "scene_summary" "text",
    "candidate_findings_count" integer DEFAULT 0 NOT NULL,
    "generated_findings_count" integer DEFAULT 0 NOT NULL,
    "highest_risk_level" "text",
    "ai_confidence" numeric,
    "raw_summary" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "coverage_status" "text",
    "coverage_gap_reason" "text",
    "target_findings_min" integer,
    "target_findings_max" integer
);


ALTER TABLE "public"."analysis_photo_summaries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."app_feature_flags" (
    "key" "text" NOT NULL,
    "value" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."app_feature_flags" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."audit_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "action" "text" NOT NULL,
    "entity_type" "text",
    "entity_id" "uuid",
    "metadata" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."audit_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."companies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "hazard_class" "text" NOT NULL,
    "logo_path" "text",
    "is_archived" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "address" "text",
    "contact_person" "text",
    "department" "text",
    "default_responsible" "text",
    "default_due_days" integer,
    CONSTRAINT "companies_default_due_days_check" CHECK ((("default_due_days" IS NULL) OR (("default_due_days" >= 1) AND ("default_due_days" <= 365)))),
    CONSTRAINT "companies_hazard_class_check" CHECK (("hazard_class" = ANY (ARRAY['low'::"text", 'medium'::"text", 'high'::"text"]))),
    CONSTRAINT "companies_name_not_blank" CHECK (("length"("btrim"("name")) > 0))
);


ALTER TABLE "public"."companies" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."consents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "kvkk_version" "text" NOT NULL,
    "terms_version" "text" NOT NULL,
    "explicit_consent_version" "text" DEFAULT ''::"text" NOT NULL,
    "accepted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "source" "text" DEFAULT 'first_analysis'::"text" NOT NULL,
    "app_version" "text",
    "device_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."consents" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."finding_edit_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "analysis_id" "uuid" NOT NULL,
    "finding_id" "uuid",
    "actor_user_id" "uuid",
    "event_type" "text" NOT NULL,
    "before_snapshot" "jsonb",
    "after_snapshot" "jsonb",
    "changed_fields" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "finding_version_before" integer,
    "finding_version_after" integer,
    "client_app_version" "text",
    "request_id" "text",
    "support_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "finding_edit_events_event_type_check" CHECK (("event_type" = ANY (ARRAY['update'::"text", 'hard_delete'::"text"])))
);


ALTER TABLE "public"."finding_edit_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."findings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "analysis_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "ordinal" integer NOT NULL,
    "title" "text" NOT NULL,
    "category" "text",
    "description" "text",
    "recommended_action" "text",
    "references_text" "text",
    "confidence" numeric DEFAULT 0 NOT NULL,
    "fk_probability" numeric NOT NULL,
    "fk_frequency" numeric NOT NULL,
    "fk_severity" numeric NOT NULL,
    "fk_score" numeric GENERATED ALWAYS AS ((("fk_probability" * "fk_frequency") * "fk_severity")) STORED,
    "fk_band" "public"."risk_level" NOT NULL,
    "m5_probability" integer NOT NULL,
    "m5_severity" integer NOT NULL,
    "m5_score" integer GENERATED ALWAYS AS (("m5_probability" * "m5_severity")) STORED,
    "m5_band" "public"."risk_level" NOT NULL,
    "residual_fk_probability" numeric,
    "residual_fk_frequency" numeric,
    "residual_fk_severity" numeric,
    "residual_fk_score" numeric GENERATED ALWAYS AS (COALESCE((("residual_fk_probability" * "residual_fk_frequency") * "residual_fk_severity"), NULL::numeric)) STORED,
    "residual_m5_probability" integer,
    "residual_m5_severity" integer,
    "residual_m5_score" integer GENERATED ALWAYS AS (COALESCE(("residual_m5_probability" * "residual_m5_severity"), NULL::integer)) STORED,
    "responsible" "text",
    "deadline" "text",
    "is_resolved" boolean DEFAULT false NOT NULL,
    "resolved_at" timestamp with time zone,
    "photo_id" "uuid",
    "bounding_box" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "root_cause_text" "text",
    "recommended_measures" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "origin" "text" DEFAULT 'ai'::"text" NOT NULL,
    "ai_original_snapshot" "jsonb",
    "source_photo_indices" integer[] DEFAULT '{}'::integer[] NOT NULL,
    "source_photo_observations" "jsonb",
    "finding_budget_policy" "jsonb",
    "ai_confidence" numeric,
    "is_user_deleted" boolean DEFAULT false NOT NULL,
    "user_deleted_at" timestamp with time zone,
    "user_deleted_by" "uuid",
    "last_user_edit_at" timestamp with time zone,
    "last_user_edit_by" "uuid",
    "user_edit_count" integer DEFAULT 0 NOT NULL,
    "finding_version" integer DEFAULT 1 NOT NULL,
    "report_visibility" "text" DEFAULT 'visible'::"text" NOT NULL,
    "display_group" "text",
    "display_order" integer,
    "needs_field_verification" boolean DEFAULT false NOT NULL,
    CONSTRAINT "findings_fk_frequency_check" CHECK (("fk_frequency" = ANY (ARRAY[0.5, (1)::numeric, (2)::numeric, (3)::numeric, (6)::numeric, (10)::numeric]))),
    CONSTRAINT "findings_fk_probability_check" CHECK (("fk_probability" = ANY (ARRAY[0.2, 0.5, (1)::numeric, (3)::numeric, (6)::numeric, (10)::numeric]))),
    CONSTRAINT "findings_fk_severity_check" CHECK (("fk_severity" = ANY (ARRAY[(1)::numeric, (3)::numeric, (7)::numeric, (15)::numeric, (40)::numeric, (100)::numeric]))),
    CONSTRAINT "findings_m5_probability_check" CHECK ((("m5_probability" >= 1) AND ("m5_probability" <= 5))),
    CONSTRAINT "findings_m5_severity_check" CHECK ((("m5_severity" >= 1) AND ("m5_severity" <= 5))),
    CONSTRAINT "findings_origin_check" CHECK (("origin" = ANY (ARRAY['ai'::"text", 'user'::"text"]))),
    CONSTRAINT "findings_recommended_measures_is_array" CHECK (("jsonb_typeof"("recommended_measures") = 'array'::"text")),
    CONSTRAINT "findings_report_visibility_check" CHECK (("report_visibility" = ANY (ARRAY['visible'::"text", 'hidden'::"text"])))
);


ALTER TABLE "public"."findings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."legal_document_acknowledgements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "document_kind" "text" NOT NULL,
    "version" "text" NOT NULL,
    "change_type" "text" NOT NULL,
    "seen_at" timestamp with time zone,
    "continued_use_accepted_at" timestamp with time zone,
    "explicitly_accepted_at" timestamp with time zone,
    "source" "text" DEFAULT 'legal_update_notice'::"text" NOT NULL,
    "app_version" "text",
    "device_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "legal_document_acknowledgements_change_type_check" CHECK (("change_type" = ANY (ARRAY['info'::"text", 'material_terms'::"text", 'explicit_consent'::"text"]))),
    CONSTRAINT "legal_document_acknowledgements_document_kind_check" CHECK (("document_kind" = ANY (ARRAY['terms'::"text", 'privacy'::"text", 'kvkk'::"text", 'consent'::"text"])))
);


ALTER TABLE "public"."legal_document_acknowledgements" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."model_pricing_catalog" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "provider" "text" NOT NULL,
    "model" "text" NOT NULL,
    "effective_from" "date" DEFAULT CURRENT_DATE NOT NULL,
    "input_price_per_million" numeric(12,6) NOT NULL,
    "output_price_per_million" numeric(12,6) NOT NULL,
    "cached_price_per_million" numeric(12,6),
    "thoughts_price_per_million" numeric(12,6),
    "currency" "text" DEFAULT 'USD'::"text" NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."model_pricing_catalog" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notification_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "kind" "text" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "data" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "status" "text" DEFAULT 'queued'::"text" NOT NULL,
    "sent_count" integer DEFAULT 0 NOT NULL,
    "failure_count" integer DEFAULT 0 NOT NULL,
    "last_error" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "sent_at" timestamp with time zone,
    "source" "text" DEFAULT 'transactional'::"text" NOT NULL,
    "job_id" "uuid",
    "campaign_id" "uuid",
    "template_id" "uuid",
    "destination" "text",
    "dedupe_key" "text",
    "opened_at" timestamp with time zone,
    "open_count" integer DEFAULT 0 NOT NULL,
    CONSTRAINT "notification_events_destination_check" CHECK ((("destination" IS NULL) OR ("destination" = ANY (ARRAY['home'::"text", 'history'::"text", 'new_analysis'::"text", 'profile'::"text", 'reports'::"text"])))),
    CONSTRAINT "notification_events_open_count_check" CHECK (("open_count" >= 0)),
    CONSTRAINT "notification_events_source_check" CHECK (("source" = ANY (ARRAY['transactional'::"text", 'trial'::"text", 'progress'::"text", 'automation'::"text", 'manual'::"text"]))),
    CONSTRAINT "notification_events_status_check" CHECK (("status" = ANY (ARRAY['queued'::"text", 'sent'::"text", 'failed'::"text", 'skipped'::"text"])))
);


ALTER TABLE "public"."notification_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."paywall_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "funnel_session_id" "uuid" NOT NULL,
    "source" "text" NOT NULL,
    "variant_id" "text" NOT NULL,
    "segment_key" "text",
    "event_name" "text" NOT NULL,
    "selected_tier" "public"."subscription_tier",
    "billing" "text",
    "product_identifier" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "paywall_events_billing_check" CHECK ((("billing" IS NULL) OR ("billing" = ANY (ARRAY['yearly'::"text", 'monthly'::"text"])))),
    CONSTRAINT "paywall_events_event_name_check" CHECK (("event_name" = ANY (ARRAY['view'::"text", 'close'::"text", 'cta_tap'::"text", 'plan_select'::"text", 'billing_select'::"text", 'purchase_started'::"text", 'purchase_succeeded'::"text", 'purchase_failed'::"text", 'restore_tap'::"text", 'personal_plan_view'::"text", 'personal_plan_continue'::"text", 'trial_invite_view'::"text", 'trial_invite_cta_tap'::"text"]))),
    CONSTRAINT "paywall_events_metadata_object_check" CHECK (("jsonb_typeof"("metadata") = 'object'::"text")),
    CONSTRAINT "paywall_events_segment_key_check" CHECK ((("segment_key" IS NULL) OR ("segment_key" = ANY (ARRAY['construction'::"text", 'industrial_high_risk'::"text", 'osgb_high_volume'::"text", 'office_service'::"text", 'health_team'::"text"])))),
    CONSTRAINT "paywall_events_source_check" CHECK (("source" = ANY (ARRAY['in_app'::"text", 'onboarding_v2'::"text"])))
);


ALTER TABLE "public"."paywall_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."photos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "analysis_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "storage_path" "text" NOT NULL,
    "width" integer,
    "height" integer,
    "size_bytes" integer,
    "mime_type" "text" DEFAULT 'image/jpeg'::"text" NOT NULL,
    "annotations" "jsonb",
    "exif" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "retention_expires_at" timestamp with time zone,
    "retention_policy" "text" DEFAULT 'analysis_photo'::"text" NOT NULL,
    "sequence_index" integer,
    "client_photo_id" "text",
    "is_primary" boolean DEFAULT false NOT NULL,
    "original_filename" "text",
    "byte_size" integer,
    "sha256" "text",
    "thumbnail_storage_path" "text",
    "annotation_storage_path" "text",
    "user_caption" "text",
    "upload_payload_version" "text" DEFAULT 'photo-single-v1'::"text" NOT NULL,
    "compression_metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "ai_scene_summary" "text"
);


ALTER TABLE "public"."photos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."plan_capability_rules" (
    "plan" "text" NOT NULL,
    "max_photos_per_analysis" integer NOT NULL,
    "visible_photo_slots_in_ui" integer DEFAULT 5 NOT NULL,
    "max_findings_per_photo" integer DEFAULT 12 NOT NULL,
    "max_findings_per_analysis" integer NOT NULL,
    "can_use_multi_photo_analysis" boolean DEFAULT false NOT NULL,
    "can_edit_ai_findings" boolean DEFAULT true NOT NULL,
    "can_add_manual_findings" boolean DEFAULT false NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "plan_capability_rules_max_findings_per_analysis_check" CHECK (("max_findings_per_analysis" >= 1)),
    CONSTRAINT "plan_capability_rules_max_findings_per_photo_check" CHECK (("max_findings_per_photo" >= 1)),
    CONSTRAINT "plan_capability_rules_max_photos_per_analysis_check" CHECK (("max_photos_per_analysis" >= 1)),
    CONSTRAINT "plan_capability_rules_plan_check" CHECK (("plan" = ANY (ARRAY['free'::"text", 'plus'::"text", 'pro'::"text"]))),
    CONSTRAINT "plan_capability_rules_visible_photo_slots_in_ui_check" CHECK (("visible_photo_slots_in_ui" >= 1))
);


ALTER TABLE "public"."plan_capability_rules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."professional_progress_badges" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "badge_key" "text" NOT NULL,
    "badge_type" "text" NOT NULL,
    "title" "text" NOT NULL,
    "subtitle" "text" NOT NULL,
    "icon_name" "text" NOT NULL,
    "unlocked_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "seen_at" timestamp with time zone,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    CONSTRAINT "professional_progress_badges_metadata_object_check" CHECK (("jsonb_typeof"("metadata") = 'object'::"text")),
    CONSTRAINT "professional_progress_badges_type_check" CHECK (("badge_type" = ANY (ARRAY['report_count'::"text", 'competency_diversity'::"text", 'risk'::"text", 'report_kind'::"text", 'onboarding_area'::"text", 'active_days'::"text", 'title'::"text"])))
);


ALTER TABLE "public"."professional_progress_badges" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."professional_progress_competency_stats" (
    "user_id" "uuid" NOT NULL,
    "competency_key" "text" NOT NULL,
    "analysis_count" integer DEFAULT 0 NOT NULL,
    "report_count" integer DEFAULT 0 NOT NULL,
    "finding_count" integer DEFAULT 0 NOT NULL,
    "critical_count" integer DEFAULT 0 NOT NULL,
    "high_count" integer DEFAULT 0 NOT NULL,
    "medium_count" integer DEFAULT 0 NOT NULL,
    "low_count" integer DEFAULT 0 NOT NULL,
    "unknown_count" integer DEFAULT 0 NOT NULL,
    "onboarding_seed" boolean DEFAULT false NOT NULL,
    "last_detected_at" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "professional_progress_competency_stats_analysis_count_check" CHECK (("analysis_count" >= 0)),
    CONSTRAINT "professional_progress_competency_stats_critical_count_check" CHECK (("critical_count" >= 0)),
    CONSTRAINT "professional_progress_competency_stats_finding_count_check" CHECK (("finding_count" >= 0)),
    CONSTRAINT "professional_progress_competency_stats_high_count_check" CHECK (("high_count" >= 0)),
    CONSTRAINT "professional_progress_competency_stats_key_check" CHECK (("competency_key" = ANY (ARRAY['fire'::"text", 'chemical'::"text", 'electrical'::"text", 'mechanical'::"text", 'ergonomics'::"text", 'psychosocial'::"text", 'working_at_height'::"text", 'ppe'::"text", 'mining'::"text", 'construction'::"text", 'factory'::"text"]))),
    CONSTRAINT "professional_progress_competency_stats_low_count_check" CHECK (("low_count" >= 0)),
    CONSTRAINT "professional_progress_competency_stats_medium_count_check" CHECK (("medium_count" >= 0)),
    CONSTRAINT "professional_progress_competency_stats_report_count_check" CHECK (("report_count" >= 0)),
    CONSTRAINT "professional_progress_competency_stats_unknown_count_check" CHECK (("unknown_count" >= 0))
);


ALTER TABLE "public"."professional_progress_competency_stats" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."professional_progress_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "event_key" "text" NOT NULL,
    "event_type" "text" NOT NULL,
    "mdp_delta" integer DEFAULT 0 NOT NULL,
    "analysis_id" "uuid",
    "report_id" "uuid",
    "competency_key" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "occurred_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "professional_progress_events_mdp_delta_check" CHECK (("mdp_delta" >= 0)),
    CONSTRAINT "professional_progress_events_metadata_object_check" CHECK (("jsonb_typeof"("metadata") = 'object'::"text")),
    CONSTRAINT "professional_progress_events_type_check" CHECK (("event_type" = ANY (ARRAY['analysis_completed'::"text", 'report_created'::"text", 'first_competency_used'::"text", 'weekly_report_bonus'::"text", 'badge_unlocked'::"text", 'title_changed'::"text", 'onboarding_competency_seeded'::"text", 'backfill_seed'::"text"])))
);


ALTER TABLE "public"."professional_progress_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."professional_progress_finding_classifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "analysis_id" "uuid" NOT NULL,
    "finding_id" "uuid" NOT NULL,
    "competency_key" "text" NOT NULL,
    "risk_level" "text" NOT NULL,
    "source_category_text" "text",
    "matched_by" "text" NOT NULL,
    "confidence" numeric DEFAULT 0 NOT NULL,
    "classifier_version" "text" DEFAULT 'v1_keyword_2026_05_26'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "professional_progress_finding_classifications_confidence_check" CHECK ((("confidence" >= (0)::numeric) AND ("confidence" <= (1)::numeric))),
    CONSTRAINT "professional_progress_finding_competency_check" CHECK (("competency_key" = ANY (ARRAY['fire'::"text", 'chemical'::"text", 'electrical'::"text", 'mechanical'::"text", 'ergonomics'::"text", 'psychosocial'::"text", 'working_at_height'::"text", 'ppe'::"text", 'mining'::"text", 'construction'::"text", 'factory'::"text", 'unclassified'::"text"]))),
    CONSTRAINT "professional_progress_finding_risk_check" CHECK (("risk_level" = ANY (ARRAY['critical'::"text", 'high'::"text", 'medium'::"text", 'low'::"text", 'unknown'::"text"])))
);


ALTER TABLE "public"."professional_progress_finding_classifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."professional_progress_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "message_type" "text" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "related_analysis_id" "uuid",
    "related_report_id" "uuid",
    "competency_key" "text",
    "risk_level" "text",
    "seen_at" timestamp with time zone,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "professional_progress_messages_metadata_object_check" CHECK (("jsonb_typeof"("metadata") = 'object'::"text")),
    CONSTRAINT "professional_progress_messages_type_check" CHECK (("message_type" = ANY (ARRAY['instant'::"text", 'weekly_summary'::"text", 'monthly_summary'::"text", 'milestone'::"text", 'title_change'::"text"])))
);


ALTER TABLE "public"."professional_progress_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."professional_progress_profiles" (
    "user_id" "uuid" NOT NULL,
    "total_mdp" integer DEFAULT 0 NOT NULL,
    "current_title_key" "text" DEFAULT 'candidate'::"text" NOT NULL,
    "total_analyses" integer DEFAULT 0 NOT NULL,
    "total_reports" integer DEFAULT 0 NOT NULL,
    "total_findings" integer DEFAULT 0 NOT NULL,
    "critical_findings" integer DEFAULT 0 NOT NULL,
    "high_findings" integer DEFAULT 0 NOT NULL,
    "medium_findings" integer DEFAULT 0 NOT NULL,
    "low_findings" integer DEFAULT 0 NOT NULL,
    "unknown_findings" integer DEFAULT 0 NOT NULL,
    "active_days" integer DEFAULT 0 NOT NULL,
    "last_event_at" timestamp with time zone,
    "last_title_change_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "professional_progress_profiles_active_days_check" CHECK (("active_days" >= 0)),
    CONSTRAINT "professional_progress_profiles_critical_findings_check" CHECK (("critical_findings" >= 0)),
    CONSTRAINT "professional_progress_profiles_high_findings_check" CHECK (("high_findings" >= 0)),
    CONSTRAINT "professional_progress_profiles_low_findings_check" CHECK (("low_findings" >= 0)),
    CONSTRAINT "professional_progress_profiles_medium_findings_check" CHECK (("medium_findings" >= 0)),
    CONSTRAINT "professional_progress_profiles_title_check" CHECK (("current_title_key" = ANY (ARRAY['candidate'::"text", 'field_observer'::"text", 'risk_hunter'::"text", 'hazard_analyst'::"text", 'senior_risk_specialist'::"text", 'safety_strategist'::"text", 'master_hse_specialist'::"text"]))),
    CONSTRAINT "professional_progress_profiles_total_analyses_check" CHECK (("total_analyses" >= 0)),
    CONSTRAINT "professional_progress_profiles_total_findings_check" CHECK (("total_findings" >= 0)),
    CONSTRAINT "professional_progress_profiles_total_mdp_check" CHECK (("total_mdp" >= 0)),
    CONSTRAINT "professional_progress_profiles_total_reports_check" CHECK (("total_reports" >= 0)),
    CONSTRAINT "professional_progress_profiles_unknown_findings_check" CHECK (("unknown_findings" >= 0))
);


ALTER TABLE "public"."professional_progress_profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."professional_progress_weekly_summaries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "week_start" "date" NOT NULL,
    "reports_count" integer DEFAULT 0 NOT NULL,
    "analyses_count" integer DEFAULT 0 NOT NULL,
    "findings_count" integer DEFAULT 0 NOT NULL,
    "top_competency_key" "text",
    "message_title" "text",
    "message_body" "text",
    "push_sent_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "professional_progress_weekly_summaries_analyses_count_check" CHECK (("analyses_count" >= 0)),
    CONSTRAINT "professional_progress_weekly_summaries_findings_count_check" CHECK (("findings_count" >= 0)),
    CONSTRAINT "professional_progress_weekly_summaries_reports_count_check" CHECK (("reports_count" >= 0))
);


ALTER TABLE "public"."professional_progress_weekly_summaries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "email" "text",
    "full_name" "text",
    "initials" "text",
    "title" "text",
    "certificate_number" "text",
    "company_name" "text",
    "company_logo_url" "text",
    "phone" "text",
    "tier" "public"."subscription_tier" DEFAULT 'free'::"public"."subscription_tier" NOT NULL,
    "subscription_period" "public"."subscription_period",
    "subscription_renewal_at" timestamp with time zone,
    "daily_quota_used" integer DEFAULT 0 NOT NULL,
    "daily_quota_reset_at" "date" DEFAULT CURRENT_DATE NOT NULL,
    "preferred_method" "public"."risk_method" DEFAULT 'fine_kinney'::"public"."risk_method" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "welcome_email_sent_at" timestamp with time zone,
    "welcome_email_status" "text",
    "welcome_email_error" "text",
    "avatar_url" "text",
    CONSTRAINT "profiles_tier_check" CHECK ((("tier")::"text" = ANY (ARRAY['free'::"text", 'plus'::"text", 'pro'::"text"]))),
    CONSTRAINT "profiles_welcome_email_status_check" CHECK ((("welcome_email_status" IS NULL) OR ("welcome_email_status" = ANY (ARRAY['sending'::"text", 'sent'::"text", 'email_failed'::"text"]))))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."push_device_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "token" "text" NOT NULL,
    "platform" "text" DEFAULT 'ios'::"text" NOT NULL,
    "environment" "text" DEFAULT 'sandbox'::"text" NOT NULL,
    "app_version" "text",
    "device_model" "text",
    "notifications_enabled" boolean DEFAULT true NOT NULL,
    "last_registered_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_success_at" timestamp with time zone,
    "last_failure_at" timestamp with time zone,
    "last_failure_reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "push_device_tokens_environment_check" CHECK (("environment" = ANY (ARRAY['sandbox'::"text", 'production'::"text"]))),
    CONSTRAINT "push_device_tokens_platform_check" CHECK (("platform" = 'ios'::"text"))
);


ALTER TABLE "public"."push_device_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."report_counters" (
    "user_id" "uuid" NOT NULL,
    "year" integer NOT NULL,
    "last_no" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."report_counters" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."report_year_counters" (
    "year" integer NOT NULL,
    "last_no" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."report_year_counters" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "analysis_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "document_no" "text" NOT NULL,
    "format" "text" DEFAULT 'pdf'::"text" NOT NULL,
    "storage_path" "text" NOT NULL,
    "size_bytes" integer,
    "page_count" integer,
    "method" "public"."risk_method" NOT NULL,
    "signed_url_expires_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "kind" "text" DEFAULT 'standard'::"text" NOT NULL,
    "title" "text" DEFAULT 'RiskDetected Report'::"text" NOT NULL,
    "file_name" "text" NOT NULL,
    "mime_type" "text" DEFAULT 'application/pdf'::"text" NOT NULL,
    "file_size" integer,
    "request_id" "text",
    "support_id" "text",
    "company_id" "uuid",
    "company_snapshot" "jsonb",
    "report_ready_push_sent_at" timestamp with time zone,
    "findings_snapshot_json" "jsonb",
    "photos_snapshot_json" "jsonb",
    "analysis_edit_version" integer DEFAULT 0 NOT NULL,
    "generated_from_user_edited_findings" boolean DEFAULT false NOT NULL,
    "source_photo_count" integer,
    "visible_findings_count" integer,
    "report_page_count" integer,
    CONSTRAINT "reports_format_check" CHECK (("format" = ANY (ARRAY['pdf'::"text", 'xlsx'::"text"])))
);


ALTER TABLE "public"."reports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."subscription_events" (
    "event_id" "text" NOT NULL,
    "user_id" "uuid",
    "app_user_id" "text",
    "event_type" "text" NOT NULL,
    "product_id" "text",
    "entitlement_ids" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "environment" "text",
    "raw_event" "jsonb" NOT NULL,
    "received_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "processed_at" timestamp with time zone
);


ALTER TABLE "public"."subscription_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."subscription_test_overrides" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "tier" "text" NOT NULL,
    "reason" "text" DEFAULT 'manual_test'::"text" NOT NULL,
    "starts_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "revoked_at" timestamp with time zone,
    "created_by" "text" DEFAULT CURRENT_USER NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "subscription_test_overrides_tier_check" CHECK (("tier" = ANY (ARRAY['plus'::"text", 'pro'::"text"]))),
    CONSTRAINT "subscription_test_overrides_valid_window" CHECK (("expires_at" > "starts_at"))
);


ALTER TABLE "public"."subscription_test_overrides" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."support_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "support_id" "text" NOT NULL,
    "subject" "text" NOT NULL,
    "message" "text" NOT NULL,
    "sender_name" "text",
    "sender_email" "text",
    "sender_phone" "text",
    "tier" "text",
    "company_name" "text",
    "title" "text",
    "attachment_count" integer DEFAULT 0 NOT NULL,
    "attachments" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "delivery_status" "text" DEFAULT 'stored'::"text" NOT NULL,
    "delivery_error" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "support_requests_delivery_status_check" CHECK (("delivery_status" = ANY (ARRAY['sent'::"text", 'stored'::"text", 'email_failed'::"text"])))
);


ALTER TABLE "public"."support_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."usage_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "feature" "text" NOT NULL,
    "event_type" "text" NOT NULL,
    "source_id" "uuid",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."usage_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_subscriptions" (
    "user_id" "uuid" NOT NULL,
    "tier" "text" DEFAULT 'free'::"text" NOT NULL,
    "source" "text" DEFAULT 'revenuecat'::"text" NOT NULL,
    "status" "text" DEFAULT 'inactive'::"text" NOT NULL,
    "revenuecat_app_user_id" "text",
    "product_id" "text",
    "entitlement_id" "text",
    "entitlement_ids" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "environment" "text",
    "current_period_ends_at" timestamp with time zone,
    "last_event_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "trial_started_at" timestamp with time zone,
    "trial_ends_at" timestamp with time zone,
    "trial_product_id" "text",
    "will_renew" boolean,
    "trial_reminder_sent_at" timestamp with time zone,
    "trial_reminder_last_attempt_at" timestamp with time zone,
    "trial_reminder_status" "text",
    "trial_reminder_notification_event_id" "uuid",
    CONSTRAINT "user_subscriptions_tier_check" CHECK (("tier" = ANY (ARRAY['free'::"text", 'plus'::"text", 'pro'::"text"]))),
    CONSTRAINT "user_subscriptions_trial_dates_check" CHECK ((("trial_started_at" IS NULL) OR ("trial_ends_at" IS NULL) OR ("trial_ends_at" > "trial_started_at"))),
    CONSTRAINT "user_subscriptions_trial_product_check" CHECK ((("trial_product_id" IS NULL) OR ("trial_product_id" = 'riskdetected_plus_yearly'::"text"))),
    CONSTRAINT "user_subscriptions_trial_reminder_status_check" CHECK ((("trial_reminder_status" IS NULL) OR ("trial_reminder_status" = ANY (ARRAY['pending'::"text", 'sent'::"text", 'skipped'::"text", 'failed'::"text", 'inactive'::"text"]))))
);


ALTER TABLE "public"."user_subscriptions" OWNER TO "postgres";


ALTER TABLE ONLY "private"."analysis_job_events"
    ADD CONSTRAINT "analysis_job_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "private"."analysis_job_state"
    ADD CONSTRAINT "analysis_job_state_pkey" PRIMARY KEY ("analysis_id");



ALTER TABLE ONLY "private"."analysis_job_state"
    ADD CONSTRAINT "analysis_job_state_user_id_analysis_id_key" UNIQUE ("user_id", "analysis_id");



ALTER TABLE ONLY "private"."notification_campaigns"
    ADD CONSTRAINT "notification_campaigns_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "private"."notification_delivery_attempts"
    ADD CONSTRAINT "notification_delivery_attempt_notification_event_id_push_de_key" UNIQUE ("notification_event_id", "push_device_token_id", "attempt_number");



ALTER TABLE ONLY "private"."notification_delivery_attempts"
    ADD CONSTRAINT "notification_delivery_attempts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "private"."notification_jobs"
    ADD CONSTRAINT "notification_jobs_dedupe_key_key" UNIQUE ("dedupe_key");



ALTER TABLE ONLY "private"."notification_jobs"
    ADD CONSTRAINT "notification_jobs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "private"."notification_rule_versions"
    ADD CONSTRAINT "notification_rule_versions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "private"."notification_rule_versions"
    ADD CONSTRAINT "notification_rule_versions_rule_id_version_key" UNIQUE ("rule_id", "version");



ALTER TABLE ONLY "private"."notification_rules"
    ADD CONSTRAINT "notification_rules_key_key" UNIQUE ("key");



ALTER TABLE ONLY "private"."notification_rules"
    ADD CONSTRAINT "notification_rules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "private"."notification_templates"
    ADD CONSTRAINT "notification_templates_key_key" UNIQUE ("key");



ALTER TABLE ONLY "private"."notification_templates"
    ADD CONSTRAINT "notification_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "private"."support_request_rate_limits"
    ADD CONSTRAINT "support_request_rate_limits_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."account_deletion_requests"
    ADD CONSTRAINT "account_deletion_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE "public"."account_deletion_requests"
    ADD CONSTRAINT "account_deletion_requests_target_self_check" CHECK ((("target_user_id" IS NULL) OR ("user_id" IS NULL) OR ("target_user_id" = "user_id"))) NOT VALID;



ALTER TABLE ONLY "public"."admin_alert_events"
    ADD CONSTRAINT "admin_alert_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."admin_alert_rules"
    ADD CONSTRAINT "admin_alert_rules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."admin_alert_rules"
    ADD CONSTRAINT "admin_alert_rules_rule_key_key" UNIQUE ("rule_key");



ALTER TABLE ONLY "public"."admin_audit_logs"
    ADD CONSTRAINT "admin_audit_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."admin_exports"
    ADD CONSTRAINT "admin_exports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."admin_notes"
    ADD CONSTRAINT "admin_notes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."admin_rate_limit_events"
    ADD CONSTRAINT "admin_rate_limit_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."admin_saved_filters"
    ADD CONSTRAINT "admin_saved_filters_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."admin_users"
    ADD CONSTRAINT "admin_users_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."admin_users"
    ADD CONSTRAINT "admin_users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ai_usage_logs"
    ADD CONSTRAINT "ai_usage_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."analyses"
    ADD CONSTRAINT "analyses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."analysis_photo_summaries"
    ADD CONSTRAINT "analysis_photo_summaries_analysis_id_photo_sequence_index_key" UNIQUE ("analysis_id", "photo_sequence_index");



ALTER TABLE ONLY "public"."analysis_photo_summaries"
    ADD CONSTRAINT "analysis_photo_summaries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."app_feature_flags"
    ADD CONSTRAINT "app_feature_flags_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."audit_logs"
    ADD CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."companies"
    ADD CONSTRAINT "companies_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."consents"
    ADD CONSTRAINT "consents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."consents"
    ADD CONSTRAINT "consents_user_id_kvkk_version_terms_version_explicit_consen_key" UNIQUE ("user_id", "kvkk_version", "terms_version", "explicit_consent_version");



ALTER TABLE ONLY "public"."finding_edit_events"
    ADD CONSTRAINT "finding_edit_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."findings"
    ADD CONSTRAINT "findings_analysis_id_ordinal_key" UNIQUE ("analysis_id", "ordinal");



ALTER TABLE ONLY "public"."findings"
    ADD CONSTRAINT "findings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."legal_document_acknowledgements"
    ADD CONSTRAINT "legal_document_acknowledgemen_user_id_document_kind_version_key" UNIQUE ("user_id", "document_kind", "version");



ALTER TABLE ONLY "public"."legal_document_acknowledgements"
    ADD CONSTRAINT "legal_document_acknowledgements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."model_pricing_catalog"
    ADD CONSTRAINT "model_pricing_catalog_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."model_pricing_catalog"
    ADD CONSTRAINT "model_pricing_catalog_unique" UNIQUE ("provider", "model", "effective_from");



ALTER TABLE ONLY "public"."notification_events"
    ADD CONSTRAINT "notification_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_preferences"
    ADD CONSTRAINT "notification_preferences_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."paywall_events"
    ADD CONSTRAINT "paywall_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."photos"
    ADD CONSTRAINT "photos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."plan_capability_rules"
    ADD CONSTRAINT "plan_capability_rules_pkey" PRIMARY KEY ("plan");



ALTER TABLE ONLY "public"."professional_progress_badges"
    ADD CONSTRAINT "professional_progress_badges_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."professional_progress_badges"
    ADD CONSTRAINT "professional_progress_badges_user_id_badge_key_key" UNIQUE ("user_id", "badge_key");



ALTER TABLE ONLY "public"."professional_progress_competency_stats"
    ADD CONSTRAINT "professional_progress_competency_stats_pkey" PRIMARY KEY ("user_id", "competency_key");



ALTER TABLE ONLY "public"."professional_progress_events"
    ADD CONSTRAINT "professional_progress_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."professional_progress_events"
    ADD CONSTRAINT "professional_progress_events_user_id_event_key_key" UNIQUE ("user_id", "event_key");



ALTER TABLE ONLY "public"."professional_progress_finding_classifications"
    ADD CONSTRAINT "professional_progress_finding_classifications_finding_id_key" UNIQUE ("finding_id");



ALTER TABLE ONLY "public"."professional_progress_finding_classifications"
    ADD CONSTRAINT "professional_progress_finding_classifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."professional_progress_messages"
    ADD CONSTRAINT "professional_progress_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."professional_progress_profiles"
    ADD CONSTRAINT "professional_progress_profiles_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."professional_progress_weekly_summaries"
    ADD CONSTRAINT "professional_progress_weekly_summaries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."professional_progress_weekly_summaries"
    ADD CONSTRAINT "professional_progress_weekly_summaries_user_id_week_start_key" UNIQUE ("user_id", "week_start");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_device_tokens"
    ADD CONSTRAINT "push_device_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_device_tokens"
    ADD CONSTRAINT "push_device_tokens_user_id_token_key" UNIQUE ("user_id", "token");



ALTER TABLE ONLY "public"."report_counters"
    ADD CONSTRAINT "report_counters_pkey" PRIMARY KEY ("user_id", "year");



ALTER TABLE ONLY "public"."report_year_counters"
    ADD CONSTRAINT "report_year_counters_pkey" PRIMARY KEY ("year");



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_user_storage_path_key" UNIQUE ("user_id", "storage_path");



ALTER TABLE ONLY "public"."subscription_events"
    ADD CONSTRAINT "subscription_events_pkey" PRIMARY KEY ("event_id");



ALTER TABLE ONLY "public"."subscription_test_overrides"
    ADD CONSTRAINT "subscription_test_overrides_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."support_requests"
    ADD CONSTRAINT "support_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."support_requests"
    ADD CONSTRAINT "support_requests_support_id_key" UNIQUE ("support_id");



ALTER TABLE ONLY "public"."usage_events"
    ADD CONSTRAINT "usage_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_engagement_state"
    ADD CONSTRAINT "user_engagement_state_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."user_onboarding_answers"
    ADD CONSTRAINT "user_onboarding_answers_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."user_subscriptions"
    ADD CONSTRAINT "user_subscriptions_pkey" PRIMARY KEY ("user_id");



CREATE INDEX "analysis_job_events_analysis_created_idx" ON "private"."analysis_job_events" USING "btree" ("analysis_id", "created_at" DESC);



CREATE INDEX "analysis_job_events_attempt_idx" ON "private"."analysis_job_events" USING "btree" ("analysis_id", "job_generation", "worker_attempt", "created_at");



CREATE INDEX "analysis_job_events_type_created_idx" ON "private"."analysis_job_events" USING "btree" ("event_type", "created_at" DESC);



CREATE INDEX "analysis_job_events_user_created_idx" ON "private"."analysis_job_events" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "analysis_job_state_active_msg_idx" ON "private"."analysis_job_state" USING "btree" ("active_msg_id", "generation") WHERE ("active_msg_id" IS NOT NULL);



CREATE INDEX "analysis_job_state_lease_idx" ON "private"."analysis_job_state" USING "btree" ("lease_expires_at") WHERE ("claim_token" IS NOT NULL);



CREATE INDEX "notification_campaigns_created_by_idx" ON "private"."notification_campaigns" USING "btree" ("created_by") WHERE ("created_by" IS NOT NULL);



CREATE INDEX "notification_campaigns_due_idx" ON "private"."notification_campaigns" USING "btree" ("status", "scheduled_at") WHERE ("status" = ANY (ARRAY['scheduled'::"text", 'running'::"text"]));



CREATE INDEX "notification_campaigns_template_idx" ON "private"."notification_campaigns" USING "btree" ("template_id") WHERE ("template_id" IS NOT NULL);



CREATE INDEX "notification_delivery_event_idx" ON "private"."notification_delivery_attempts" USING "btree" ("notification_event_id", "created_at");



CREATE INDEX "notification_delivery_job_idx" ON "private"."notification_delivery_attempts" USING "btree" ("job_id") WHERE ("job_id" IS NOT NULL);



CREATE INDEX "notification_delivery_outcome_idx" ON "private"."notification_delivery_attempts" USING "btree" ("outcome", "created_at" DESC);



CREATE INDEX "notification_delivery_token_idx" ON "private"."notification_delivery_attempts" USING "btree" ("push_device_token_id") WHERE ("push_device_token_id" IS NOT NULL);



CREATE UNIQUE INDEX "notification_jobs_active_episode_unique" ON "private"."notification_jobs" USING "btree" ("user_id", "kind", "episode_key") WHERE ("status" = ANY (ARRAY['pending'::"text", 'claimed'::"text", 'sent'::"text", 'ambiguous'::"text"]));



CREATE INDEX "notification_jobs_campaign_status_idx" ON "private"."notification_jobs" USING "btree" ("campaign_id", "status", "created_at" DESC) WHERE ("campaign_id" IS NOT NULL);



CREATE INDEX "notification_jobs_due_idx" ON "private"."notification_jobs" USING "btree" ("due_at", "created_at") WHERE ("status" = ANY (ARRAY['pending'::"text", 'claimed'::"text"]));



CREATE INDEX "notification_jobs_event_idx" ON "private"."notification_jobs" USING "btree" ("notification_event_id") WHERE ("notification_event_id" IS NOT NULL);



CREATE INDEX "notification_jobs_rule_status_idx" ON "private"."notification_jobs" USING "btree" ("rule_id", "status", "created_at" DESC);



CREATE INDEX "notification_jobs_rule_version_idx" ON "private"."notification_jobs" USING "btree" ("rule_version_id") WHERE ("rule_version_id" IS NOT NULL);



CREATE INDEX "notification_jobs_template_idx" ON "private"."notification_jobs" USING "btree" ("template_id") WHERE ("template_id" IS NOT NULL);



CREATE INDEX "notification_jobs_user_created_idx" ON "private"."notification_jobs" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "notification_rule_versions_created_by_idx" ON "private"."notification_rule_versions" USING "btree" ("created_by") WHERE ("created_by" IS NOT NULL);



CREATE INDEX "notification_rules_created_by_idx" ON "private"."notification_rules" USING "btree" ("created_by") WHERE ("created_by" IS NOT NULL);



CREATE INDEX "notification_rules_current_version_idx" ON "private"."notification_rules" USING "btree" ("current_version_id") WHERE ("current_version_id" IS NOT NULL);



CREATE UNIQUE INDEX "notification_rules_one_runtime_per_type" ON "private"."notification_rules" USING "btree" ("rule_type") WHERE ("status" = ANY (ARRAY['shadow'::"text", 'allowlist'::"text", 'active'::"text"]));



CREATE INDEX "notification_rules_runtime_idx" ON "private"."notification_rules" USING "btree" ("status", "priority", "updated_at");



CREATE INDEX "notification_rules_template_idx" ON "private"."notification_rules" USING "btree" ("template_id");



CREATE INDEX "notification_templates_created_by_idx" ON "private"."notification_templates" USING "btree" ("created_by") WHERE ("created_by" IS NOT NULL);



CREATE INDEX "account_deletion_requests_completion_status_idx" ON "public"."account_deletion_requests" USING "btree" ("status", "processing_started_at", "completed_at");



CREATE INDEX "account_deletion_requests_status_created_idx" ON "public"."account_deletion_requests" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "account_deletion_requests_target_user_idx" ON "public"."account_deletion_requests" USING "btree" ("target_user_id", "created_at" DESC);



CREATE INDEX "account_deletion_requests_user_created_idx" ON "public"."account_deletion_requests" USING "btree" ("user_id", "created_at" DESC);



CREATE UNIQUE INDEX "admin_alert_events_fingerprint_open_idx" ON "public"."admin_alert_events" USING "btree" ("fingerprint") WHERE ("status" = 'open'::"text");



CREATE INDEX "admin_alert_events_rule_status_idx" ON "public"."admin_alert_events" USING "btree" ("rule_id", "status", "created_at" DESC);



CREATE INDEX "admin_alert_events_status_created_idx" ON "public"."admin_alert_events" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "admin_audit_logs_action_idx" ON "public"."admin_audit_logs" USING "btree" ("action");



CREATE INDEX "admin_audit_logs_admin_user_id_idx" ON "public"."admin_audit_logs" USING "btree" ("admin_user_id");



CREATE INDEX "admin_audit_logs_created_at_idx" ON "public"."admin_audit_logs" USING "btree" ("created_at" DESC);



CREATE INDEX "admin_audit_logs_target_idx" ON "public"."admin_audit_logs" USING "btree" ("target_type", "target_id");



CREATE INDEX "admin_exports_admin_user_id_idx" ON "public"."admin_exports" USING "btree" ("admin_user_id");



CREATE INDEX "admin_exports_created_at_idx" ON "public"."admin_exports" USING "btree" ("created_at" DESC);



CREATE INDEX "admin_notes_created_at_idx" ON "public"."admin_notes" USING "btree" ("created_at" DESC);



CREATE INDEX "admin_notes_target_idx" ON "public"."admin_notes" USING "btree" ("target_type", "target_id");



CREATE INDEX "admin_rate_limit_events_bucket_key_created_idx" ON "public"."admin_rate_limit_events" USING "btree" ("bucket", "key_hash", "created_at" DESC);



CREATE INDEX "admin_saved_filters_admin_resource_idx" ON "public"."admin_saved_filters" USING "btree" ("admin_user_id", "resource");



CREATE UNIQUE INDEX "admin_saved_filters_admin_resource_name_idx" ON "public"."admin_saved_filters" USING "btree" ("admin_user_id", "resource", "name");



CREATE UNIQUE INDEX "admin_users_user_id_idx" ON "public"."admin_users" USING "btree" ("user_id");



CREATE INDEX "ai_usage_logs_ai_execution_route_created_idx" ON "public"."ai_usage_logs" USING "btree" ("ai_execution_route", "created_at" DESC) WHERE ("ai_execution_route" IS NOT NULL);



CREATE INDEX "ai_usage_logs_analysis" ON "public"."ai_usage_logs" USING "btree" ("analysis_id");



CREATE INDEX "ai_usage_logs_api_key_alias" ON "public"."ai_usage_logs" USING "btree" ("api_key_alias") WHERE ("api_key_alias" IS NOT NULL);



CREATE INDEX "ai_usage_logs_context_hash_created_idx" ON "public"."ai_usage_logs" USING "btree" ("context_hash", "created_at" DESC) WHERE ("context_hash" IS NOT NULL);



CREATE INDEX "ai_usage_logs_coverage_metrics_idx" ON "public"."ai_usage_logs" USING "btree" ("created_at" DESC, "coverage_contract_outcome") WHERE ("coverage_schema_version" = 2);



CREATE INDEX "ai_usage_logs_job_analysis_idx" ON "public"."ai_usage_logs" USING "btree" ("analysis_id", "job_generation", "worker_attempt", "created_at" DESC);



CREATE INDEX "ai_usage_logs_persistence_pending_idx" ON "public"."ai_usage_logs" USING "btree" ("persistence_updated_at", "created_at") WHERE ("persistence_outcome" = 'pending'::"text");



CREATE INDEX "ai_usage_logs_prompt_version_created_idx" ON "public"."ai_usage_logs" USING "btree" ("prompt_version", "created_at" DESC);



CREATE INDEX "ai_usage_logs_quality_tier_created_idx" ON "public"."ai_usage_logs" USING "btree" ("quality_tier", "created_at" DESC) WHERE ("quality_tier" IS NOT NULL);



CREATE INDEX "ai_usage_logs_request_id" ON "public"."ai_usage_logs" USING "btree" ("request_id") WHERE ("request_id" IS NOT NULL);



CREATE INDEX "ai_usage_logs_support_id" ON "public"."ai_usage_logs" USING "btree" ("support_id") WHERE ("support_id" IS NOT NULL);



CREATE INDEX "ai_usage_logs_user_created" ON "public"."ai_usage_logs" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "analyses_async_status_idx" ON "public"."analyses" USING "btree" ("status", "queued_at", "worker_started_at");



CREATE INDEX "analyses_completion_push_pending_idx" ON "public"."analyses" USING "btree" ("status", "completed_at", "completion_push_sent_at");



CREATE INDEX "analyses_failure_category_created_idx" ON "public"."analyses" USING "btree" ("failure_category", "created_at" DESC) WHERE ("status" = 'failed'::"public"."analysis_status");



CREATE INDEX "analyses_raw_ai_response_expires_idx" ON "public"."analyses" USING "btree" ("raw_ai_response_expires_at") WHERE ("raw_ai_response" IS NOT NULL);



CREATE INDEX "analyses_status_idx" ON "public"."analyses" USING "btree" ("status") WHERE ("status" <> 'completed'::"public"."analysis_status");



CREATE INDEX "analyses_user_company_created_idx" ON "public"."analyses" USING "btree" ("user_id", "company_id", "created_at" DESC);



CREATE INDEX "analyses_user_id_idx" ON "public"."analyses" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "analyses_user_mode_created" ON "public"."analyses" USING "btree" ("user_id", "analysis_mode", "created_at" DESC);



CREATE INDEX "analyses_user_sector_created_idx" ON "public"."analyses" USING "btree" ("user_id", "analysis_sector", "created_at" DESC);



CREATE INDEX "analysis_photo_summaries_user_created_idx" ON "public"."analysis_photo_summaries" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "audit_logs_user_id_idx" ON "public"."audit_logs" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "companies_user_active_created_idx" ON "public"."companies" USING "btree" ("user_id", "is_archived", "created_at" DESC);



CREATE UNIQUE INDEX "companies_user_active_name_idx" ON "public"."companies" USING "btree" ("user_id", "lower"("btrim"("name"))) WHERE ("is_archived" = false);



CREATE INDEX "consents_user_accepted" ON "public"."consents" USING "btree" ("user_id", "accepted_at" DESC);



CREATE INDEX "finding_edit_events_actor_created_idx" ON "public"."finding_edit_events" USING "btree" ("actor_user_id", "created_at" DESC);



CREATE INDEX "finding_edit_events_analysis_created_idx" ON "public"."finding_edit_events" USING "btree" ("analysis_id", "created_at" DESC);



CREATE INDEX "findings_analysis_display_order_idx" ON "public"."findings" USING "btree" ("analysis_id", "display_order");



CREATE INDEX "findings_analysis_id_idx" ON "public"."findings" USING "btree" ("analysis_id", "ordinal");



CREATE INDEX "findings_analysis_visible_idx" ON "public"."findings" USING "btree" ("analysis_id", "ordinal") WHERE ("is_user_deleted" = false);



CREATE INDEX "findings_source_photo_indices_gin_idx" ON "public"."findings" USING "gin" ("source_photo_indices");



CREATE INDEX "findings_unresolved_idx" ON "public"."findings" USING "btree" ("user_id") WHERE ("is_resolved" = false);



CREATE INDEX "findings_user_id_idx" ON "public"."findings" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "legal_document_ack_user_seen" ON "public"."legal_document_acknowledgements" USING "btree" ("user_id", "seen_at" DESC);



CREATE INDEX "legal_document_ack_user_version" ON "public"."legal_document_acknowledgements" USING "btree" ("user_id", "document_kind", "version");



CREATE INDEX "model_pricing_catalog_lookup_idx" ON "public"."model_pricing_catalog" USING "btree" ("provider", "model", "effective_from" DESC);



CREATE INDEX "notification_events_campaign_idx" ON "public"."notification_events" USING "btree" ("campaign_id") WHERE ("campaign_id" IS NOT NULL);



CREATE UNIQUE INDEX "notification_events_dedupe_key_unique" ON "public"."notification_events" USING "btree" ("dedupe_key") WHERE ("dedupe_key" IS NOT NULL);



CREATE INDEX "notification_events_job_idx" ON "public"."notification_events" USING "btree" ("job_id") WHERE ("job_id" IS NOT NULL);



CREATE INDEX "notification_events_kind_status_created_idx" ON "public"."notification_events" USING "btree" ("kind", "status", "created_at" DESC);



CREATE INDEX "notification_events_opened_idx" ON "public"."notification_events" USING "btree" ("opened_at" DESC) WHERE ("opened_at" IS NOT NULL);



CREATE INDEX "notification_events_template_idx" ON "public"."notification_events" USING "btree" ("template_id") WHERE ("template_id" IS NOT NULL);



CREATE INDEX "notification_events_user_created_idx" ON "public"."notification_events" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "paywall_events_funnel_session_idx" ON "public"."paywall_events" USING "btree" ("funnel_session_id", "created_at");



CREATE INDEX "paywall_events_user_created_idx" ON "public"."paywall_events" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "paywall_events_variant_event_idx" ON "public"."paywall_events" USING "btree" ("variant_id", "event_name", "created_at" DESC);



CREATE INDEX "photos_analysis_id_idx" ON "public"."photos" USING "btree" ("analysis_id");



CREATE INDEX "photos_analysis_order_idx" ON "public"."photos" USING "btree" ("analysis_id", "sequence_index");



CREATE UNIQUE INDEX "photos_analysis_sequence_unique" ON "public"."photos" USING "btree" ("analysis_id", "sequence_index") WHERE ("sequence_index" IS NOT NULL);



CREATE UNIQUE INDEX "photos_analysis_sequence_v2_unique" ON "public"."photos" USING "btree" ("analysis_id", "sequence_index");



CREATE INDEX "photos_analysis_sha256_idx" ON "public"."photos" USING "btree" ("analysis_id", "sha256") WHERE ("sha256" IS NOT NULL);



CREATE INDEX "photos_retention_expires_idx" ON "public"."photos" USING "btree" ("retention_expires_at") WHERE ("retention_expires_at" IS NOT NULL);



CREATE INDEX "professional_progress_badges_user_unlocked_idx" ON "public"."professional_progress_badges" USING "btree" ("user_id", "unlocked_at" DESC);



CREATE INDEX "professional_progress_events_analysis_idx" ON "public"."professional_progress_events" USING "btree" ("analysis_id");



CREATE INDEX "professional_progress_events_report_idx" ON "public"."professional_progress_events" USING "btree" ("report_id");



CREATE INDEX "professional_progress_events_user_created_idx" ON "public"."professional_progress_events" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "professional_progress_finding_user_competency_idx" ON "public"."professional_progress_finding_classifications" USING "btree" ("user_id", "competency_key", "risk_level");



CREATE INDEX "professional_progress_messages_user_created_idx" ON "public"."professional_progress_messages" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "push_device_tokens_active_idx" ON "public"."push_device_tokens" USING "btree" ("user_id", "environment") WHERE ("notifications_enabled" = true);



CREATE INDEX "push_device_tokens_user_idx" ON "public"."push_device_tokens" USING "btree" ("user_id");



CREATE INDEX "reports_analysis_created" ON "public"."reports" USING "btree" ("analysis_id", "created_at" DESC);



CREATE UNIQUE INDEX "reports_document_no_idx" ON "public"."reports" USING "btree" ("document_no");



CREATE INDEX "reports_ready_push_pending_idx" ON "public"."reports" USING "btree" ("created_at" DESC) WHERE ("report_ready_push_sent_at" IS NULL);



CREATE INDEX "reports_request_id" ON "public"."reports" USING "btree" ("request_id") WHERE ("request_id" IS NOT NULL);



CREATE INDEX "reports_support_id" ON "public"."reports" USING "btree" ("support_id") WHERE ("support_id" IS NOT NULL);



CREATE INDEX "reports_user_company_created_idx" ON "public"."reports" USING "btree" ("user_id", "company_id", "created_at" DESC);



CREATE INDEX "reports_user_created" ON "public"."reports" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "reports_user_format_created" ON "public"."reports" USING "btree" ("user_id", "format", "created_at" DESC);



CREATE INDEX "subscription_events_user_received" ON "public"."subscription_events" USING "btree" ("user_id", "received_at" DESC);



CREATE INDEX "subscription_test_overrides_user_active" ON "public"."subscription_test_overrides" USING "btree" ("user_id", "expires_at" DESC) WHERE ("revoked_at" IS NULL);



CREATE INDEX "support_requests_support_id" ON "public"."support_requests" USING "btree" ("support_id");



CREATE INDEX "support_requests_user_created_at" ON "public"."support_requests" USING "btree" ("user_id", "created_at" DESC);



CREATE UNIQUE INDEX "usage_events_analysis_feature_unique" ON "public"."usage_events" USING "btree" ("user_id", "feature", "source_id") WHERE (("source_id" IS NOT NULL) AND ("feature" = ANY (ARRAY['analysis_standard'::"text", 'analysis_detailed'::"text"])));



CREATE UNIQUE INDEX "usage_events_report_feature_unique" ON "public"."usage_events" USING "btree" ("user_id", "feature", "source_id") WHERE (("source_id" IS NOT NULL) AND ("feature" = ANY (ARRAY['report_standard'::"text", 'report_risk_analysis_trial'::"text"])));



CREATE INDEX "usage_events_user_feature_created" ON "public"."usage_events" USING "btree" ("user_id", "feature", "created_at" DESC);



CREATE INDEX "user_engagement_last_foreground_idx" ON "public"."user_engagement_state" USING "btree" ("last_foreground_at");



CREATE INDEX "user_subscriptions_status_expires" ON "public"."user_subscriptions" USING "btree" ("status", "current_period_ends_at");



CREATE INDEX "user_subscriptions_trial_reminder_due_idx" ON "public"."user_subscriptions" USING "btree" ("trial_ends_at", "trial_reminder_last_attempt_at") WHERE (("trial_reminder_sent_at" IS NULL) AND ("trial_ends_at" IS NOT NULL) AND ("trial_product_id" = 'riskdetected_plus_yearly'::"text"));



CREATE OR REPLACE TRIGGER "analyses_enforce_company_owner" BEFORE INSERT OR UPDATE OF "user_id", "company_id" ON "public"."analyses" FOR EACH ROW EXECUTE FUNCTION "private"."enforce_analysis_company_owner"();



CREATE OR REPLACE TRIGGER "analyses_keep_usage_on_delete" BEFORE DELETE ON "public"."analyses" FOR EACH ROW EXECUTE FUNCTION "public"."ensure_analysis_usage_event_on_delete"();



CREATE OR REPLACE TRIGGER "analyses_protect_completed_status" BEFORE UPDATE OF "status" ON "public"."analyses" FOR EACH ROW EXECUTE FUNCTION "private"."tg_protect_completed_analysis_status"();



CREATE OR REPLACE TRIGGER "analyses_set_retention_fields" BEFORE INSERT OR UPDATE OF "raw_ai_response", "raw_ai_response_expires_at", "completed_at", "created_at" ON "public"."analyses" FOR EACH ROW EXECUTE FUNCTION "public"."set_analysis_retention_fields"();



CREATE OR REPLACE TRIGGER "analyses_set_updated_at" BEFORE UPDATE ON "public"."analyses" FOR EACH ROW EXECUTE FUNCTION "public"."tg_set_updated_at"();



CREATE OR REPLACE TRIGGER "companies_enforce_write_rules" BEFORE INSERT OR UPDATE ON "public"."companies" FOR EACH ROW EXECUTE FUNCTION "private"."enforce_company_write_rules"();



CREATE OR REPLACE TRIGGER "findings_after_change" AFTER INSERT OR DELETE ON "public"."findings" FOR EACH ROW EXECUTE FUNCTION "public"."tg_recalc_finding_count"();



CREATE OR REPLACE TRIGGER "findings_set_updated_at" BEFORE UPDATE ON "public"."findings" FOR EACH ROW EXECUTE FUNCTION "public"."tg_set_updated_at"();



CREATE OR REPLACE TRIGGER "legal_document_acknowledgements_set_updated_at" BEFORE UPDATE ON "public"."legal_document_acknowledgements" FOR EACH ROW EXECUTE FUNCTION "public"."tg_set_updated_at"();



CREATE OR REPLACE TRIGGER "notification_preferences_set_updated_at" BEFORE UPDATE ON "public"."notification_preferences" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "photos_set_retention_fields" BEFORE INSERT OR UPDATE OF "user_id", "created_at", "retention_expires_at", "retention_policy" ON "public"."photos" FOR EACH ROW EXECUTE FUNCTION "public"."set_photo_retention_fields"();



CREATE OR REPLACE TRIGGER "professional_progress_analysis_completed" AFTER INSERT OR UPDATE OF "status" ON "public"."analyses" FOR EACH ROW EXECUTE FUNCTION "private"."pp_process_analysis_completed"();



CREATE OR REPLACE TRIGGER "professional_progress_report_created" AFTER INSERT ON "public"."reports" FOR EACH ROW EXECUTE FUNCTION "private"."pp_process_report_created"();



CREATE OR REPLACE TRIGGER "professional_progress_seed_onboarding" AFTER INSERT OR UPDATE OF "sectors" ON "public"."user_onboarding_answers" FOR EACH ROW EXECUTE FUNCTION "private"."pp_seed_onboarding_competencies"();



CREATE OR REPLACE TRIGGER "profiles_set_updated_at" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."tg_set_updated_at"();



CREATE OR REPLACE TRIGGER "push_device_tokens_set_updated_at" BEFORE UPDATE ON "public"."push_device_tokens" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "reports_enforce_company_owner" BEFORE INSERT OR UPDATE OF "user_id", "company_id" ON "public"."reports" FOR EACH ROW EXECUTE FUNCTION "private"."enforce_report_company_owner"();



CREATE OR REPLACE TRIGGER "reports_enforce_plan_limits" BEFORE INSERT ON "public"."reports" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_report_plan_limits"();



CREATE OR REPLACE TRIGGER "reports_keep_usage_on_delete" BEFORE DELETE ON "public"."reports" FOR EACH ROW EXECUTE FUNCTION "public"."ensure_report_usage_event_on_delete"();



CREATE OR REPLACE TRIGGER "user_onboarding_answers_set_updated_at" BEFORE UPDATE ON "public"."user_onboarding_answers" FOR EACH ROW EXECUTE FUNCTION "public"."tg_set_updated_at"();



ALTER TABLE ONLY "private"."analysis_job_events"
    ADD CONSTRAINT "analysis_job_events_analysis_id_fkey" FOREIGN KEY ("analysis_id") REFERENCES "public"."analyses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."analysis_job_events"
    ADD CONSTRAINT "analysis_job_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."analysis_job_state"
    ADD CONSTRAINT "analysis_job_state_analysis_id_fkey" FOREIGN KEY ("analysis_id") REFERENCES "public"."analyses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."analysis_job_state"
    ADD CONSTRAINT "analysis_job_state_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."notification_campaigns"
    ADD CONSTRAINT "notification_campaigns_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "private"."notification_campaigns"
    ADD CONSTRAINT "notification_campaigns_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "private"."notification_templates"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "private"."notification_delivery_attempts"
    ADD CONSTRAINT "notification_delivery_attempts_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "private"."notification_jobs"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "private"."notification_delivery_attempts"
    ADD CONSTRAINT "notification_delivery_attempts_notification_event_id_fkey" FOREIGN KEY ("notification_event_id") REFERENCES "public"."notification_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."notification_delivery_attempts"
    ADD CONSTRAINT "notification_delivery_attempts_push_device_token_id_fkey" FOREIGN KEY ("push_device_token_id") REFERENCES "public"."push_device_tokens"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "private"."notification_jobs"
    ADD CONSTRAINT "notification_jobs_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "private"."notification_campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."notification_jobs"
    ADD CONSTRAINT "notification_jobs_notification_event_id_fkey" FOREIGN KEY ("notification_event_id") REFERENCES "public"."notification_events"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "private"."notification_jobs"
    ADD CONSTRAINT "notification_jobs_rule_id_fkey" FOREIGN KEY ("rule_id") REFERENCES "private"."notification_rules"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."notification_jobs"
    ADD CONSTRAINT "notification_jobs_rule_version_id_fkey" FOREIGN KEY ("rule_version_id") REFERENCES "private"."notification_rule_versions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."notification_jobs"
    ADD CONSTRAINT "notification_jobs_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "private"."notification_templates"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "private"."notification_jobs"
    ADD CONSTRAINT "notification_jobs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."notification_rule_versions"
    ADD CONSTRAINT "notification_rule_versions_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "private"."notification_rule_versions"
    ADD CONSTRAINT "notification_rule_versions_rule_id_fkey" FOREIGN KEY ("rule_id") REFERENCES "private"."notification_rules"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."notification_rules"
    ADD CONSTRAINT "notification_rules_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "private"."notification_rules"
    ADD CONSTRAINT "notification_rules_current_version_fk" FOREIGN KEY ("current_version_id") REFERENCES "private"."notification_rule_versions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "private"."notification_rules"
    ADD CONSTRAINT "notification_rules_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "private"."notification_templates"("id");



ALTER TABLE ONLY "private"."notification_templates"
    ADD CONSTRAINT "notification_templates_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "private"."support_request_rate_limits"
    ADD CONSTRAINT "support_request_rate_limits_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."account_deletion_requests"
    ADD CONSTRAINT "account_deletion_requests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."admin_alert_events"
    ADD CONSTRAINT "admin_alert_events_acknowledged_by_fkey" FOREIGN KEY ("acknowledged_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."admin_alert_events"
    ADD CONSTRAINT "admin_alert_events_rule_id_fkey" FOREIGN KEY ("rule_id") REFERENCES "public"."admin_alert_rules"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."admin_audit_logs"
    ADD CONSTRAINT "admin_audit_logs_admin_user_id_fkey" FOREIGN KEY ("admin_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."admin_exports"
    ADD CONSTRAINT "admin_exports_admin_user_id_fkey" FOREIGN KEY ("admin_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."admin_notes"
    ADD CONSTRAINT "admin_notes_admin_user_id_fkey" FOREIGN KEY ("admin_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."admin_saved_filters"
    ADD CONSTRAINT "admin_saved_filters_admin_user_id_fkey" FOREIGN KEY ("admin_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."admin_users"
    ADD CONSTRAINT "admin_users_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."admin_users"
    ADD CONSTRAINT "admin_users_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ai_usage_logs"
    ADD CONSTRAINT "ai_usage_logs_analysis_id_fkey" FOREIGN KEY ("analysis_id") REFERENCES "public"."analyses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ai_usage_logs"
    ADD CONSTRAINT "ai_usage_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."analyses"
    ADD CONSTRAINT "analyses_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."analyses"
    ADD CONSTRAINT "analyses_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."analysis_photo_summaries"
    ADD CONSTRAINT "analysis_photo_summaries_analysis_id_fkey" FOREIGN KEY ("analysis_id") REFERENCES "public"."analyses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."analysis_photo_summaries"
    ADD CONSTRAINT "analysis_photo_summaries_photo_id_fkey" FOREIGN KEY ("photo_id") REFERENCES "public"."photos"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."analysis_photo_summaries"
    ADD CONSTRAINT "analysis_photo_summaries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."audit_logs"
    ADD CONSTRAINT "audit_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."companies"
    ADD CONSTRAINT "companies_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."consents"
    ADD CONSTRAINT "consents_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."finding_edit_events"
    ADD CONSTRAINT "finding_edit_events_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."finding_edit_events"
    ADD CONSTRAINT "finding_edit_events_analysis_id_fkey" FOREIGN KEY ("analysis_id") REFERENCES "public"."analyses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."finding_edit_events"
    ADD CONSTRAINT "finding_edit_events_finding_id_fkey" FOREIGN KEY ("finding_id") REFERENCES "public"."findings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."findings"
    ADD CONSTRAINT "findings_analysis_id_fkey" FOREIGN KEY ("analysis_id") REFERENCES "public"."analyses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."findings"
    ADD CONSTRAINT "findings_last_user_edit_by_fkey" FOREIGN KEY ("last_user_edit_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."findings"
    ADD CONSTRAINT "findings_photo_id_fkey" FOREIGN KEY ("photo_id") REFERENCES "public"."photos"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."findings"
    ADD CONSTRAINT "findings_user_deleted_by_fkey" FOREIGN KEY ("user_deleted_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."findings"
    ADD CONSTRAINT "findings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."legal_document_acknowledgements"
    ADD CONSTRAINT "legal_document_acknowledgements_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notification_events"
    ADD CONSTRAINT "notification_events_campaign_fk" FOREIGN KEY ("campaign_id") REFERENCES "private"."notification_campaigns"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."notification_events"
    ADD CONSTRAINT "notification_events_job_fk" FOREIGN KEY ("job_id") REFERENCES "private"."notification_jobs"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."notification_events"
    ADD CONSTRAINT "notification_events_template_fk" FOREIGN KEY ("template_id") REFERENCES "private"."notification_templates"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."notification_events"
    ADD CONSTRAINT "notification_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notification_preferences"
    ADD CONSTRAINT "notification_preferences_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."paywall_events"
    ADD CONSTRAINT "paywall_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."photos"
    ADD CONSTRAINT "photos_analysis_id_fkey" FOREIGN KEY ("analysis_id") REFERENCES "public"."analyses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."photos"
    ADD CONSTRAINT "photos_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."professional_progress_badges"
    ADD CONSTRAINT "professional_progress_badges_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."professional_progress_competency_stats"
    ADD CONSTRAINT "professional_progress_competency_stats_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."professional_progress_events"
    ADD CONSTRAINT "professional_progress_events_analysis_id_fkey" FOREIGN KEY ("analysis_id") REFERENCES "public"."analyses"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."professional_progress_events"
    ADD CONSTRAINT "professional_progress_events_report_id_fkey" FOREIGN KEY ("report_id") REFERENCES "public"."reports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."professional_progress_events"
    ADD CONSTRAINT "professional_progress_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."professional_progress_finding_classifications"
    ADD CONSTRAINT "professional_progress_finding_classifications_analysis_id_fkey" FOREIGN KEY ("analysis_id") REFERENCES "public"."analyses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."professional_progress_finding_classifications"
    ADD CONSTRAINT "professional_progress_finding_classifications_finding_id_fkey" FOREIGN KEY ("finding_id") REFERENCES "public"."findings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."professional_progress_finding_classifications"
    ADD CONSTRAINT "professional_progress_finding_classifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."professional_progress_messages"
    ADD CONSTRAINT "professional_progress_messages_related_analysis_id_fkey" FOREIGN KEY ("related_analysis_id") REFERENCES "public"."analyses"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."professional_progress_messages"
    ADD CONSTRAINT "professional_progress_messages_related_report_id_fkey" FOREIGN KEY ("related_report_id") REFERENCES "public"."reports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."professional_progress_messages"
    ADD CONSTRAINT "professional_progress_messages_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."professional_progress_profiles"
    ADD CONSTRAINT "professional_progress_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."professional_progress_weekly_summaries"
    ADD CONSTRAINT "professional_progress_weekly_summaries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."push_device_tokens"
    ADD CONSTRAINT "push_device_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."report_counters"
    ADD CONSTRAINT "report_counters_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_analysis_id_fkey" FOREIGN KEY ("analysis_id") REFERENCES "public"."analyses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."subscription_events"
    ADD CONSTRAINT "subscription_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."subscription_test_overrides"
    ADD CONSTRAINT "subscription_test_overrides_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."support_requests"
    ADD CONSTRAINT "support_requests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."usage_events"
    ADD CONSTRAINT "usage_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_engagement_state"
    ADD CONSTRAINT "user_engagement_state_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_onboarding_answers"
    ADD CONSTRAINT "user_onboarding_answers_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_subscriptions"
    ADD CONSTRAINT "user_subscriptions_trial_reminder_notification_event_id_fkey" FOREIGN KEY ("trial_reminder_notification_event_id") REFERENCES "public"."notification_events"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_subscriptions"
    ADD CONSTRAINT "user_subscriptions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Deny anonymous job event access" ON "private"."analysis_job_events" TO "anon" USING (false) WITH CHECK (false);



CREATE POLICY "Deny authenticated job event access" ON "private"."analysis_job_events" TO "authenticated" USING (false) WITH CHECK (false);



ALTER TABLE "private"."analysis_job_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."notification_campaigns" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."notification_delivery_attempts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."notification_jobs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."notification_rule_versions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."notification_rules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."notification_templates" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Users create own deletion requests" ON "public"."account_deletion_requests" FOR INSERT WITH CHECK (((( SELECT "auth"."uid"() AS "uid") = "user_id") AND (("target_user_id" IS NULL) OR ("target_user_id" = ( SELECT "auth"."uid"() AS "uid")))));



CREATE POLICY "Users delete own push tokens" ON "public"."push_device_tokens" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users delete own reports" ON "public"."reports" FOR DELETE USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users insert own consents" ON "public"."consents" FOR INSERT TO "authenticated" WITH CHECK (((( SELECT "auth"."uid"() AS "uid") IS NOT NULL) AND (( SELECT "auth"."uid"() AS "uid") = "user_id")));



CREATE POLICY "Users insert own legal acknowledgements" ON "public"."legal_document_acknowledgements" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users insert own notification preferences" ON "public"."notification_preferences" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users insert own profile" ON "public"."profiles" FOR INSERT WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "id"));



CREATE POLICY "Users insert own push tokens" ON "public"."push_device_tokens" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users read own consents" ON "public"."consents" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") IS NOT NULL) AND (( SELECT "auth"."uid"() AS "uid") = "user_id")));



CREATE POLICY "Users read own deletion requests" ON "public"."account_deletion_requests" FOR SELECT USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users read own legal acknowledgements" ON "public"."legal_document_acknowledgements" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users read own logs" ON "public"."ai_usage_logs" FOR SELECT USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users read own notification events" ON "public"."notification_events" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users read own notification preferences" ON "public"."notification_preferences" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users read own profile" ON "public"."profiles" FOR SELECT USING ((( SELECT "auth"."uid"() AS "uid") = "id"));



CREATE POLICY "Users read own push tokens" ON "public"."push_device_tokens" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users read own reports" ON "public"."reports" FOR SELECT USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users read own subscription" ON "public"."user_subscriptions" FOR SELECT USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users read own usage events" ON "public"."usage_events" FOR SELECT USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users update own legal acknowledgements" ON "public"."legal_document_acknowledgements" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users update own notification preferences" ON "public"."notification_preferences" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users update own profile" ON "public"."profiles" FOR UPDATE USING ((( SELECT "auth"."uid"() AS "uid") = "id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "id"));



CREATE POLICY "Users update own push tokens" ON "public"."push_device_tokens" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."account_deletion_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."admin_alert_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."admin_alert_rules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."admin_audit_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."admin_exports" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."admin_notes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."admin_rate_limit_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."admin_saved_filters" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."admin_users" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ai_usage_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."analyses" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "analyses_delete_own" ON "public"."analyses" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "analyses_insert_own" ON "public"."analyses" FOR INSERT TO "authenticated" WITH CHECK (((( SELECT "auth"."uid"() AS "uid") = "user_id") AND ("status" = 'pending'::"public"."analysis_status")));



CREATE POLICY "analyses_select_own" ON "public"."analyses" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "analyses_update_own_editable_fields" ON "public"."analyses" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."analysis_photo_summaries" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "analysis_photo_summaries_select_own" ON "public"."analysis_photo_summaries" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."app_feature_flags" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "app_feature_flags_select_authenticated" ON "public"."app_feature_flags" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."audit_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "audit_logs_select_own" ON "public"."audit_logs" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."companies" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "companies_insert_paid_own" ON "public"."companies" FOR INSERT TO "authenticated" WITH CHECK (((( SELECT "auth"."uid"() AS "uid") = "user_id") AND (( SELECT COALESCE("private"."company_limit_for_user"(( SELECT "auth"."uid"() AS "uid")), 0) AS "coalesce") > 0)));



CREATE POLICY "companies_select_own" ON "public"."companies" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "companies_update_paid_own" ON "public"."companies" FOR UPDATE TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "user_id") AND (( SELECT COALESCE("private"."company_limit_for_user"(( SELECT "auth"."uid"() AS "uid")), 0) AS "coalesce") > 0))) WITH CHECK (((( SELECT "auth"."uid"() AS "uid") = "user_id") AND (( SELECT COALESCE("private"."company_limit_for_user"(( SELECT "auth"."uid"() AS "uid")), 0) AS "coalesce") > 0)));



ALTER TABLE "public"."consents" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."finding_edit_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."findings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "findings_select_own" ON "public"."findings" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."legal_document_acknowledgements" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."model_pricing_catalog" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notification_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notification_preferences" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."paywall_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "paywall_events_insert_own" ON "public"."paywall_events" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "paywall_events_select_own" ON "public"."paywall_events" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."photos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "photos_delete_own" ON "public"."photos" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "photos_insert_own" ON "public"."photos" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "photos_select_own" ON "public"."photos" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "photos_update_own" ON "public"."photos" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."plan_capability_rules" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "plan_capability_rules_select_authenticated" ON "public"."plan_capability_rules" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."professional_progress_badges" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "professional_progress_badges_seen_own" ON "public"."professional_progress_badges" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "professional_progress_badges_select_own" ON "public"."professional_progress_badges" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "professional_progress_classifications_select_own" ON "public"."professional_progress_finding_classifications" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "professional_progress_competency_select_own" ON "public"."professional_progress_competency_stats" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."professional_progress_competency_stats" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."professional_progress_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "professional_progress_events_select_own" ON "public"."professional_progress_events" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."professional_progress_finding_classifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."professional_progress_messages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "professional_progress_messages_seen_own" ON "public"."professional_progress_messages" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "professional_progress_messages_select_own" ON "public"."professional_progress_messages" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."professional_progress_profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "professional_progress_profiles_select_own" ON "public"."professional_progress_profiles" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "professional_progress_weekly_select_own" ON "public"."professional_progress_weekly_summaries" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."professional_progress_weekly_summaries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_select_own" ON "public"."profiles" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "id"));



CREATE POLICY "profiles_update_own" ON "public"."profiles" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "id"));



ALTER TABLE "public"."push_device_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."report_counters" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "report_counters_select_own" ON "public"."report_counters" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."report_year_counters" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."reports" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."subscription_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."subscription_test_overrides" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."support_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."usage_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_engagement_state" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_onboarding_answers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_onboarding_answers_insert_own" ON "public"."user_onboarding_answers" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "user_onboarding_answers_select_own" ON "public"."user_onboarding_answers" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "user_onboarding_answers_update_own" ON "public"."user_onboarding_answers" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."user_subscriptions" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "private"."archive_retention_days"("p_tier" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."cleanup_expired_retention"("batch_size" integer) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."company_limit_for_user"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."company_limit_for_user"("p_user_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."enforce_analysis_company_owner"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."enforce_company_write_rules"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."enforce_report_company_owner"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."notification_admin_has_scope"("p_actor_user_id" "uuid", "p_scope" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."notification_admin_has_scope"("p_actor_user_id" "uuid", "p_scope" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."notification_conditions_valid"("p_rule_type" "text", "p_conditions" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."notification_conditions_valid"("p_rule_type" "text", "p_conditions" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "private"."notification_feature_flag"() FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."notification_feature_flag"() TO "service_role";



REVOKE ALL ON FUNCTION "private"."notification_rollout_allows"("p_flag" "jsonb", "p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."notification_rollout_allows"("p_flag" "jsonb", "p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."notification_user_bucket"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."notification_user_bucket"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."notification_user_hash"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."notification_user_hash"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."pp_competency_for_finding"("p_category" "text", "p_title" "text", "p_description" "text", "p_action" "text", "p_canvas" "text", "p_sectors" "text"[]) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."pp_competency_label"("p_key" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."pp_contains_any"("p_text" "text", "p_terms" "text"[]) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."pp_ensure_profile"("p_user_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."pp_highest_risk_level"("p_fk" "text", "p_m5" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."pp_insert_message"("p_user_id" "uuid", "p_type" "text", "p_title" "text", "p_body" "text", "p_analysis_id" "uuid", "p_report_id" "uuid", "p_competency_key" "text", "p_risk_level" "text", "p_metadata" "jsonb") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."pp_process_analysis_completed"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."pp_process_report_created"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."pp_record_event"("p_user_id" "uuid", "p_event_key" "text", "p_event_type" "text", "p_mdp" integer, "p_analysis_id" "uuid", "p_report_id" "uuid", "p_competency_key" "text", "p_metadata" "jsonb", "p_occurred_at" timestamp with time zone) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."pp_refresh_active_days"("p_user_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."pp_refresh_weekly_summaries_for_week"("p_reference_at" timestamp with time zone) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."pp_refresh_weekly_summary"("p_user_id" "uuid", "p_reference_at" timestamp with time zone) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."pp_risk_rank"("p_level" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."pp_seed_competency"("p_user_id" "uuid", "p_competency_key" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."pp_seed_onboarding_competencies"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."pp_title_key_for_mdp"("p_mdp" integer) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."pp_title_label"("p_key" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."pp_unlock_badge"("p_user_id" "uuid", "p_badge_key" "text", "p_badge_type" "text", "p_title" "text", "p_subtitle" "text", "p_icon_name" "text", "p_metadata" "jsonb") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."pp_unlock_badges_for_user"("p_user_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."report_monthly_limit"("p_tier" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."tg_protect_completed_analysis_status"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."user_plan_tier"("p_user_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."admin_analysis_pipeline_metrics_v2"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_analysis_pipeline_metrics_v2"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_cohort_retention_matrix"("p_weeks" integer, "p_periods" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_cohort_retention_matrix"("p_weeks" integer, "p_periods" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_cohort_summary"("p_weeks" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_cohort_summary"("p_weeks" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_dashboard_daily_series"("p_days" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_dashboard_daily_series"("p_days" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_data_quality_scan"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_data_quality_scan"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_findings_analytics"("p_days" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_findings_analytics"("p_days" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_notification_mutation_v1"("p_actor_user_id" "uuid", "p_action" "text", "p_payload" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_notification_mutation_v1"("p_actor_user_id" "uuid", "p_action" "text", "p_payload" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_notification_preview_v1"("p_actor_user_id" "uuid", "p_rule_id" "uuid", "p_campaign_id" "uuid", "p_now" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_notification_preview_v1"("p_actor_user_id" "uuid", "p_rule_id" "uuid", "p_campaign_id" "uuid", "p_now" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_notification_snapshot_v1"("p_actor_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_notification_snapshot_v1"("p_actor_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_pgmq_queue_messages"("p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_pgmq_queue_messages"("p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_pgmq_queue_metrics"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_pgmq_queue_metrics"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_recent_sign_ins"("p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_recent_sign_ins"("p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_subscription_inconsistency_scan"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_subscription_inconsistency_scan"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_user_segments_list"("p_segment" "text", "p_limit" integer, "p_offset" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_user_segments_list"("p_segment" "text", "p_limit" integer, "p_offset" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_user_segments_summary"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_user_segments_summary"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."check_and_consume_quota"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."check_and_consume_quota"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."check_support_request_rate_limit"("p_user_id" "uuid", "p_hour_limit" integer, "p_day_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."check_support_request_rate_limit"("p_user_id" "uuid", "p_hour_limit" integer, "p_day_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."claim_analysis_job_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_job_mode" "text", "p_lease_seconds" integer, "p_max_attempts" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."claim_analysis_job_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_job_mode" "text", "p_lease_seconds" integer, "p_max_attempts" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."claim_notification_jobs_v1"("p_now" timestamp with time zone, "p_limit" integer, "p_lease_seconds" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."claim_notification_jobs_v1"("p_now" timestamp with time zone, "p_limit" integer, "p_lease_seconds" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_notification_job_v1"("p_job_id" "uuid", "p_claim_token" "uuid", "p_result" "text", "p_notification_event_id" "uuid", "p_retryable" boolean, "p_error_code" "text", "p_error_text" "text", "p_now" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_notification_job_v1"("p_job_id" "uuid", "p_claim_token" "uuid", "p_result" "text", "p_notification_event_id" "uuid", "p_retryable" boolean, "p_error_code" "text", "p_error_text" "text", "p_now" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."defer_analysis_job_message_v2"("p_msg_id" bigint, "p_visibility_timeout" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."defer_analysis_job_message_v2"("p_msg_id" bigint, "p_visibility_timeout" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."delete_analysis_job_message"("p_msg_id" bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."delete_analysis_job_message"("p_msg_id" bigint) TO "service_role";



REVOKE ALL ON FUNCTION "public"."enforce_report_plan_limits"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enforce_report_plan_limits"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."enqueue_analysis_job_message"("p_message" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enqueue_analysis_job_message"("p_message" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."enqueue_notification_jobs_v1"("p_now" timestamp with time zone, "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enqueue_notification_jobs_v1"("p_now" timestamp with time zone, "p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."ensure_analysis_usage_event_on_delete"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ensure_analysis_usage_event_on_delete"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."ensure_report_usage_event_on_delete"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ensure_report_usage_event_on_delete"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."finalize_analysis_result_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_claim_token" "uuid", "p_findings" "jsonb", "p_analysis_result" "jsonb", "p_photo_summaries" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."finalize_analysis_result_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_claim_token" "uuid", "p_findings" "jsonb", "p_analysis_result" "jsonb", "p_photo_summaries" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."next_document_no"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."next_document_no"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."read_analysis_job_messages"("p_limit" integer, "p_visibility_timeout" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."read_analysis_job_messages"("p_limit" integer, "p_visibility_timeout" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."recalc_analysis_rollup"("p_analysis_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."recalc_analysis_rollup"("p_analysis_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_analysis_job_event_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_worker_attempt" integer, "p_job_mode" "text", "p_event_type" "text", "p_http_status" integer, "p_response_code" "text", "p_claim_action" "text", "p_safe_error_text" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_analysis_job_event_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_worker_attempt" integer, "p_job_mode" "text", "p_event_type" "text", "p_http_status" integer, "p_response_code" "text", "p_claim_action" "text", "p_safe_error_text" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_analysis_job_failure_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_claim_token" "uuid", "p_error" "text", "p_failure_code" "text", "p_status_message" "text", "p_terminal" boolean, "p_raw_ai_response" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_analysis_job_failure_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_claim_token" "uuid", "p_error" "text", "p_failure_code" "text", "p_status_message" "text", "p_terminal" boolean, "p_raw_ai_response" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_notification_delivery_attempt_v1"("p_notification_event_id" "uuid", "p_job_id" "uuid", "p_push_device_token_id" "uuid", "p_environment" "text", "p_attempt_number" integer, "p_outcome" "text", "p_http_status" integer, "p_apns_id" "text", "p_reason" "text", "p_duration_ms" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_notification_delivery_attempt_v1"("p_notification_event_id" "uuid", "p_job_id" "uuid", "p_push_device_token_id" "uuid", "p_environment" "text", "p_attempt_number" integer, "p_outcome" "text", "p_http_status" integer, "p_apns_id" "text", "p_reason" "text", "p_duration_ms" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_notification_open_v1"("p_notification_event_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_notification_open_v1"("p_notification_event_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_notification_open_v1"("p_notification_event_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."user_engagement_state" TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_user_engagement_state_v1"("p_timezone" "text", "p_locale" "text", "p_authorization_status" "text", "p_app_version" "text", "p_app_build" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_user_engagement_state_v1"("p_timezone" "text", "p_locale" "text", "p_authorization_status" "text", "p_app_version" "text", "p_app_build" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_user_engagement_state_v1"("p_timezone" "text", "p_locale" "text", "p_authorization_status" "text", "p_app_version" "text", "p_app_build" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."reserve_analysis_quota"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_analysis_mode" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reserve_analysis_quota"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_analysis_mode" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_analysis_retention_fields"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_analysis_retention_fields"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_analysis_retention_fields"() TO "service_role";



GRANT ALL ON TABLE "public"."notification_preferences" TO "anon";
GRANT ALL ON TABLE "public"."notification_preferences" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_preferences" TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_notification_master_preference_v1"("p_enabled" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_notification_master_preference_v1"("p_enabled" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_notification_master_preference_v1"("p_enabled" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_photo_retention_fields"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_photo_retention_fields"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."submit_analysis_job_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_message" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."submit_analysis_job_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_message" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."tg_create_profile_for_new_user"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."tg_create_profile_for_new_user"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."tg_recalc_finding_count"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."tg_recalc_finding_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."tg_set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."tg_set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."tg_set_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."transition_analysis_to_repair_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_claim_token" "uuid", "p_message" "jsonb", "p_intermediate_raw_response" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."transition_analysis_to_repair_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_claim_token" "uuid", "p_message" "jsonb", "p_intermediate_raw_response" "jsonb") TO "service_role";



GRANT ALL ON TABLE "public"."user_onboarding_answers" TO "authenticated";
GRANT ALL ON TABLE "public"."user_onboarding_answers" TO "service_role";



REVOKE ALL ON FUNCTION "public"."upsert_onboarding_v2_answers"("p_onboarding_version" "text", "p_certificate_class" "text", "p_hazard_classes" "text"[], "p_sectors" "text"[], "p_audit_frequency" "text", "p_selected_plan" "text", "p_raw_answers" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."upsert_onboarding_v2_answers"("p_onboarding_version" "text", "p_certificate_class" "text", "p_hazard_classes" "text"[], "p_sectors" "text"[], "p_audit_frequency" "text", "p_selected_plan" "text", "p_raw_answers" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."upsert_onboarding_v2_answers"("p_onboarding_version" "text", "p_certificate_class" "text", "p_hazard_classes" "text"[], "p_sectors" "text"[], "p_audit_frequency" "text", "p_selected_plan" "text", "p_raw_answers" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."validate_analysis_job_claim_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_claim_token" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."validate_analysis_job_claim_v2"("p_user_id" "uuid", "p_analysis_id" "uuid", "p_msg_id" bigint, "p_generation" integer, "p_claim_token" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."validate_notification_job_v1"("p_job_id" "uuid", "p_claim_token" "uuid", "p_now" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."validate_notification_job_v1"("p_job_id" "uuid", "p_claim_token" "uuid", "p_now" timestamp with time zone) TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "private"."analysis_job_events" TO "service_role";



GRANT SELECT,USAGE ON SEQUENCE "private"."analysis_job_events_id_seq" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "private"."analysis_job_state" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "private"."notification_campaigns" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "private"."notification_delivery_attempts" TO "service_role";



GRANT SELECT,USAGE ON SEQUENCE "private"."notification_delivery_attempts_id_seq" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "private"."notification_jobs" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "private"."notification_rule_versions" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "private"."notification_rules" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "private"."notification_templates" TO "service_role";



GRANT ALL ON TABLE "public"."account_deletion_requests" TO "anon";
GRANT ALL ON TABLE "public"."account_deletion_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."account_deletion_requests" TO "service_role";



GRANT ALL ON TABLE "public"."admin_alert_events" TO "service_role";



GRANT ALL ON TABLE "public"."admin_alert_rules" TO "service_role";



GRANT ALL ON TABLE "public"."admin_audit_logs" TO "service_role";



GRANT ALL ON TABLE "public"."admin_exports" TO "service_role";



GRANT ALL ON TABLE "public"."admin_notes" TO "service_role";



GRANT ALL ON TABLE "public"."admin_rate_limit_events" TO "service_role";



GRANT ALL ON TABLE "public"."admin_saved_filters" TO "service_role";



GRANT ALL ON TABLE "public"."admin_users" TO "service_role";



GRANT ALL ON TABLE "public"."ai_usage_logs" TO "anon";
GRANT ALL ON TABLE "public"."ai_usage_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_usage_logs" TO "service_role";



GRANT ALL ON TABLE "public"."analyses" TO "anon";
GRANT ALL ON TABLE "public"."analyses" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."analyses" TO "authenticated";



GRANT INSERT("id") ON TABLE "public"."analyses" TO "authenticated";



GRANT INSERT("user_id") ON TABLE "public"."analyses" TO "authenticated";



GRANT INSERT("title") ON TABLE "public"."analyses" TO "authenticated";



GRANT INSERT("kind") ON TABLE "public"."analyses" TO "authenticated";



GRANT INSERT("canvas") ON TABLE "public"."analyses" TO "authenticated";



GRANT INSERT("text_input") ON TABLE "public"."analyses" TO "authenticated";



GRANT INSERT("status") ON TABLE "public"."analyses" TO "authenticated";



GRANT INSERT("company_id"),UPDATE("company_id") ON TABLE "public"."analyses" TO "authenticated";



GRANT INSERT("analysis_sector") ON TABLE "public"."analyses" TO "authenticated";



GRANT INSERT("analysis_sector_source") ON TABLE "public"."analyses" TO "authenticated";



GRANT INSERT("analysis_sector_prompt_version") ON TABLE "public"."analyses" TO "authenticated";



GRANT ALL ON TABLE "public"."analysis_photo_summaries" TO "anon";
GRANT ALL ON TABLE "public"."analysis_photo_summaries" TO "authenticated";
GRANT ALL ON TABLE "public"."analysis_photo_summaries" TO "service_role";



GRANT ALL ON TABLE "public"."app_feature_flags" TO "anon";
GRANT ALL ON TABLE "public"."app_feature_flags" TO "authenticated";
GRANT ALL ON TABLE "public"."app_feature_flags" TO "service_role";



GRANT ALL ON TABLE "public"."audit_logs" TO "anon";
GRANT ALL ON TABLE "public"."audit_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."audit_logs" TO "service_role";



GRANT ALL ON TABLE "public"."companies" TO "anon";
GRANT ALL ON TABLE "public"."companies" TO "authenticated";
GRANT ALL ON TABLE "public"."companies" TO "service_role";



GRANT ALL ON TABLE "public"."consents" TO "service_role";
GRANT SELECT,INSERT ON TABLE "public"."consents" TO "authenticated";



GRANT ALL ON TABLE "public"."finding_edit_events" TO "service_role";



GRANT ALL ON TABLE "public"."findings" TO "anon";
GRANT ALL ON TABLE "public"."findings" TO "service_role";
GRANT SELECT ON TABLE "public"."findings" TO "authenticated";



GRANT ALL ON TABLE "public"."legal_document_acknowledgements" TO "service_role";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."legal_document_acknowledgements" TO "authenticated";



GRANT ALL ON TABLE "public"."model_pricing_catalog" TO "service_role";



GRANT ALL ON TABLE "public"."notification_events" TO "anon";
GRANT ALL ON TABLE "public"."notification_events" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_events" TO "service_role";



GRANT ALL ON TABLE "public"."paywall_events" TO "authenticated";
GRANT ALL ON TABLE "public"."paywall_events" TO "service_role";



GRANT ALL ON TABLE "public"."photos" TO "anon";
GRANT ALL ON TABLE "public"."photos" TO "authenticated";
GRANT ALL ON TABLE "public"."photos" TO "service_role";



GRANT ALL ON TABLE "public"."plan_capability_rules" TO "anon";
GRANT ALL ON TABLE "public"."plan_capability_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."plan_capability_rules" TO "service_role";



GRANT ALL ON TABLE "public"."professional_progress_badges" TO "service_role";
GRANT SELECT ON TABLE "public"."professional_progress_badges" TO "authenticated";



GRANT UPDATE("seen_at") ON TABLE "public"."professional_progress_badges" TO "authenticated";



GRANT ALL ON TABLE "public"."professional_progress_competency_stats" TO "service_role";
GRANT SELECT ON TABLE "public"."professional_progress_competency_stats" TO "authenticated";



GRANT ALL ON TABLE "public"."professional_progress_events" TO "service_role";
GRANT SELECT ON TABLE "public"."professional_progress_events" TO "authenticated";



GRANT ALL ON TABLE "public"."professional_progress_finding_classifications" TO "service_role";
GRANT SELECT ON TABLE "public"."professional_progress_finding_classifications" TO "authenticated";



GRANT ALL ON TABLE "public"."professional_progress_messages" TO "service_role";
GRANT SELECT ON TABLE "public"."professional_progress_messages" TO "authenticated";



GRANT UPDATE("seen_at") ON TABLE "public"."professional_progress_messages" TO "authenticated";



GRANT ALL ON TABLE "public"."professional_progress_profiles" TO "service_role";
GRANT SELECT ON TABLE "public"."professional_progress_profiles" TO "authenticated";



GRANT ALL ON TABLE "public"."professional_progress_weekly_summaries" TO "service_role";
GRANT SELECT ON TABLE "public"."professional_progress_weekly_summaries" TO "authenticated";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."push_device_tokens" TO "anon";
GRANT ALL ON TABLE "public"."push_device_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."push_device_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."report_counters" TO "anon";
GRANT ALL ON TABLE "public"."report_counters" TO "authenticated";
GRANT ALL ON TABLE "public"."report_counters" TO "service_role";



GRANT ALL ON TABLE "public"."report_year_counters" TO "service_role";



GRANT ALL ON TABLE "public"."reports" TO "anon";
GRANT ALL ON TABLE "public"."reports" TO "service_role";
GRANT SELECT,DELETE ON TABLE "public"."reports" TO "authenticated";



GRANT ALL ON TABLE "public"."subscription_events" TO "anon";
GRANT ALL ON TABLE "public"."subscription_events" TO "authenticated";
GRANT ALL ON TABLE "public"."subscription_events" TO "service_role";



GRANT ALL ON TABLE "public"."subscription_test_overrides" TO "service_role";



GRANT ALL ON TABLE "public"."support_requests" TO "anon";
GRANT ALL ON TABLE "public"."support_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."support_requests" TO "service_role";



GRANT ALL ON TABLE "public"."usage_events" TO "anon";
GRANT ALL ON TABLE "public"."usage_events" TO "authenticated";
GRANT ALL ON TABLE "public"."usage_events" TO "service_role";



GRANT ALL ON TABLE "public"."user_subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."user_subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."user_subscriptions" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







