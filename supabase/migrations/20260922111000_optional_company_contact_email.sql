alter table private_isg.p05_company_profiles
  drop constraint if exists p05_responsible_contact_pair;

alter table private_isg.p05_company_profiles
  add constraint p05_responsible_contact_pair check(
    (responsible_phone is null and responsible_email is null)
    or (responsible_employee_id is not null and responsible_phone is not null)
  );

create or replace function private_isg.p05_company_create_v3(
  p_mutation uuid,p_name text,p_hazard_class text,p_sector text,p_email text,
  p_employee_count integer,p_responsible_name text,p_responsible_phone text,
  p_responsible_email text
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=private_isg.active_actor(); result jsonb; company uuid;
  phone text; contact_mail text; fingerprint bytea; saved_hash bytea;
begin
  if p_responsible_name is not null then
    phone:=regexp_replace(private_isg.text_value(p_responsible_phone,64),'[ ()-]','','g');
    contact_mail:=nullif(private_isg.text_value(p_responsible_email,254),'');
    if phone !~ '^[+]?[0-9]{7,15}$'
       or (contact_mail is not null and contact_mail !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$') then
      raise exception using errcode='P0001',message='VALIDATION_ERROR';
    end if;
  elsif p_responsible_phone is not null or p_responsible_email is not null then
    raise exception using errcode='P0001',message='VALIDATION_ERROR';
  end if;
  fingerprint:=sha256(convert_to(jsonb_build_array(phone,contact_mail)::text,'UTF8'));
  result:=private_isg.p05_company_create_v2(p_mutation,p_name,p_hazard_class,p_sector,p_email,p_employee_count,p_responsible_name);
  company:=(result->'company'->>'id')::uuid;
  select contact_create_hash into saved_hash from private_isg.p05_company_profiles
    where company_id=company and owner_id=actor for update;
  if not found then raise exception using errcode='P0001',message='ACCESS_DENIED'; end if;
  if saved_hash is not null then
    if saved_hash is distinct from fingerprint then
      raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT';
    end if;
  else
    if (result->>'replayed')::boolean then
      raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT';
    end if;
    update private_isg.p05_company_profiles
      set responsible_phone=phone,responsible_email=contact_mail,contact_create_hash=fingerprint
      where company_id=company and owner_id=actor;
  end if;
  return result || jsonb_build_object('schema_version',3);
end $$;
