-- Executed only inside the isolated, no-network P00 restore container.
-- COPY was restored with replica mode; explicitly validate every restored FK.
DO $$
DECLARE r record; predicate text; present text; invalid_count bigint;
BEGIN
  FOR r IN
    SELECT c.oid, c.conname, c.conrelid, c.confrelid, c.conkey, c.confkey, c.confmatchtype
    FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
    WHERE c.contype = 'f' AND n.nspname IN ('public', 'private', 'auth', 'storage')
  LOOP
    SELECT string_agg(format('child.%I = parent.%I', ca.attname, pa.attname), ' AND ' ORDER BY k.ordinality),
           string_agg(format('child.%I IS NOT NULL', ca.attname), ' AND ' ORDER BY k.ordinality)
      INTO predicate, present
    FROM unnest(r.conkey, r.confkey) WITH ORDINALITY k(child_num, parent_num, ordinality)
    JOIN pg_attribute ca ON ca.attrelid=r.conrelid AND ca.attnum=k.child_num
    JOIN pg_attribute pa ON pa.attrelid=r.confrelid AND pa.attnum=k.parent_num;
    IF r.confmatchtype <> 's' THEN
      RAISE EXCEPTION 'RESTORE_UNSUPPORTED_FK_MATCH_TYPE';
    END IF;
    EXECUTE format('SELECT count(*) FROM %s child WHERE (%s) AND NOT EXISTS (SELECT 1 FROM %s parent WHERE %s)',
      r.conrelid::regclass, present, r.confrelid::regclass, predicate) INTO invalid_count;
    IF invalid_count <> 0 THEN RAISE EXCEPTION 'RESTORE_FOREIGN_KEY_MISMATCH'; END IF;
  END LOOP;
END $$;

SELECT json_build_object(
  'auth_users', (SELECT count(*) FROM auth.users),
  'auth_identities', (SELECT count(*) FROM auth.identities),
  'profiles', (SELECT count(*) FROM public.profiles),
  'storage_objects', (SELECT count(*) FROM storage.objects),
  'foreign_keys_checked', (SELECT count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE c.contype='f' AND n.nspname IN ('public','private','auth','storage')),
  'public_tables_without_rls', (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p') AND NOT c.relrowsecurity),
  'company_limit_plus', (SELECT max(private.company_limit_for_user(id)) FROM public.profiles WHERE tier::text='plus'),
  'company_limit_pro', (SELECT max(private.company_limit_for_user(id)) FROM public.profiles WHERE tier::text='pro'),
  'cron_execution_enabled', current_setting('cron.launch_active_jobs'),
  'extensions', (SELECT json_agg(json_build_object('name',extname,'version',extversion) ORDER BY extname) FROM pg_extension)
);
