-- Backfill photo metadata for Storage paths where the analysis UUID segment was
-- uploaded with uppercase letters by the iOS UUID string representation.

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
 and split_part(o.name, '/', 1) = a.user_id::text
 and lower(split_part(o.name, '/', 2)) = a.id::text
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
