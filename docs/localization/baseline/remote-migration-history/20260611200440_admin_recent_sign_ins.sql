CREATE OR REPLACE FUNCTION public.admin_recent_sign_ins(p_limit integer DEFAULT 5)
RETURNS TABLE(user_id uuid, email text, last_sign_in_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'auth', 'public'
AS $$
  SELECT u.id, u.email::text, u.last_sign_in_at
  FROM auth.users u
  WHERE u.last_sign_in_at IS NOT NULL
  ORDER BY u.last_sign_in_at DESC
  LIMIT greatest(1, least(coalesce(p_limit, 5), 20));
$$;

REVOKE ALL ON FUNCTION public.admin_recent_sign_ins(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_recent_sign_ins(integer) TO service_role;;
