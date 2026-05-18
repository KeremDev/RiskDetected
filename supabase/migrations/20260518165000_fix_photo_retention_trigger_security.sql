-- Fix photo metadata persistence for inline analysis uploads.
--
-- The analyze Edge Function uploads inline photos with the service role, then
-- inserts a public.photos row. The photo retention trigger calls private plan
-- helpers; when invoked through the API role this can fail before metadata is
-- stored, leaving completed photo analyses without thumbnails.

create or replace function public.set_photo_retention_fields()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
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

grant execute on function public.set_photo_retention_fields() to authenticated, service_role;

drop trigger if exists photos_set_retention_fields on public.photos;
create trigger photos_set_retention_fields
  before insert or update of user_id, created_at, retention_expires_at, retention_policy
  on public.photos
  for each row
  execute function public.set_photo_retention_fields();

-- Backfill photo metadata rows for objects that were uploaded successfully but
-- lost their public.photos row because the trigger failed.
insert into public.photos (
  analysis_id,
  user_id,
  storage_path,
  width,
  height,
  size_bytes,
  mime_type
)
select
  a.id,
  a.user_id,
  o.name,
  null,
  null,
  case
    when (o.metadata ->> 'size') ~ '^[0-9]+$' then (o.metadata ->> 'size')::integer
    else null
  end,
  coalesce(
    nullif(o.metadata ->> 'mimetype', ''),
    case
      when lower(o.name) like '%.png' then 'image/png'
      else 'image/jpeg'
    end
  )
from public.analyses a
join storage.objects o
  on o.bucket_id = 'photos'
 and left(o.name, length(a.user_id::text || '/' || a.id::text || '/')) =
     a.user_id::text || '/' || a.id::text || '/'
left join public.photos p
  on p.analysis_id = a.id
 and p.storage_path = o.name
where a.kind = 'photo'
  and p.id is null
  and (
    lower(o.name) like '%.jpg'
    or lower(o.name) like '%.jpeg'
    or lower(o.name) like '%.png'
  );

select pg_notify('pgrst', 'reload schema');
