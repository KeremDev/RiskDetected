-- Service-only inspection entrypoint: service_role intentionally lacks private schema USAGE.
-- Keep the public grant service-only and execute the fixed private routine as owner.
ALTER FUNCTION public.isg_expert_file_inspection_v1(uuid,text,jsonb) SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.isg_expert_file_inspection_v1(uuid,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.isg_expert_file_inspection_v1(uuid,text,jsonb) TO service_role;
