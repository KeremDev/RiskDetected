-- Personal workspace backfill candidate. NOT DEPLOYED.
-- The function is deliberately private and defaults to observation-only.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

CREATE TABLE private_isg.workspace_backfill_checkpoints (
  run_id uuid PRIMARY KEY,
  source_fingerprint text NOT NULL CHECK(source_fingerprint ~ '^[0-9a-f]{64}$'),
  last_profile_id uuid,
  scanned_count bigint NOT NULL DEFAULT 0 CHECK(scanned_count>=0),
  created_workspace_count bigint NOT NULL DEFAULT 0 CHECK(created_workspace_count>=0),
  created_membership_count bigint NOT NULL DEFAULT 0 CHECK(created_membership_count>=0),
  completed boolean NOT NULL DEFAULT false,
  started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE private_isg.workspace_backfill_checkpoints ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_backfill_checkpoints FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.workspace_backfill_personal_batch(
  p_run_id uuid,p_source_fingerprint text,p_after uuid DEFAULT NULL,
  p_limit integer DEFAULT 250,p_apply boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE profile_row record; v_workspace_id uuid; last_id uuid:=p_after;
  scanned integer:=0; proposed integer:=0; workspace_created integer:=0;
  membership_created integer:=0; has_more boolean; checkpoint private_isg.workspace_backfill_checkpoints;
BEGIN
  IF p_run_id IS NULL OR p_source_fingerprint IS NULL OR
     p_source_fingerprint !~ '^[0-9a-f]{64}$' OR p_limit NOT BETWEEN 1 AND 1000 OR p_apply IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';
  END IF;
  SELECT * INTO checkpoint FROM private_isg.workspace_backfill_checkpoints WHERE run_id=p_run_id FOR UPDATE;
  IF FOUND AND checkpoint.source_fingerprint<>p_source_fingerprint THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SOURCE_FINGERPRINT_CONFLICT';
  END IF;
  IF FOUND AND checkpoint.completed AND p_apply THEN
    RETURN jsonb_build_object('schema_version',1,'run_id',p_run_id,'apply',true,
      'last_profile_id',checkpoint.last_profile_id,'scanned',0,'proposed',0,
      'created_workspaces',0,'created_memberships',0,'has_more',false,'completed',true,'replayed',true);
  END IF;
  FOR profile_row IN
    SELECT p.id FROM public.profiles p WHERE p_after IS NULL OR p.id>p_after ORDER BY p.id LIMIT p_limit
  LOOP
    scanned:=scanned+1; last_id:=profile_row.id;
    IF NOT EXISTS(SELECT 1 FROM private_isg.workspaces w
      WHERE w.kind='personal' AND w.personal_owner_user_id=profile_row.id) THEN proposed:=proposed+1; END IF;
    IF p_apply THEN
      v_workspace_id:=NULL;
      INSERT INTO private_isg.workspaces(kind,name,status,timezone,created_by_user_id,personal_owner_user_id)
        VALUES('personal','Kişisel Çalışma Alanı','active','Europe/Istanbul',profile_row.id,profile_row.id)
        ON CONFLICT DO NOTHING RETURNING id INTO v_workspace_id;
      IF v_workspace_id IS NOT NULL THEN workspace_created:=workspace_created+1;
      ELSE
        SELECT id INTO v_workspace_id FROM private_isg.workspaces
          WHERE kind='personal' AND personal_owner_user_id=profile_row.id;
      END IF;
      IF v_workspace_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PERSONAL_WORKSPACE_CONFLICT';
      END IF;
      INSERT INTO private_isg.workspace_memberships(workspace_id,user_id,role,status)
        VALUES(v_workspace_id,profile_row.id,'owner','active') ON CONFLICT(workspace_id,user_id) DO NOTHING;
      IF FOUND THEN membership_created:=membership_created+1; END IF;
    END IF;
  END LOOP;
  SELECT EXISTS(SELECT 1 FROM public.profiles p WHERE last_id IS NOT NULL AND p.id>last_id) INTO has_more;
  IF p_apply THEN
    INSERT INTO private_isg.workspace_backfill_checkpoints(run_id,source_fingerprint,last_profile_id,
      scanned_count,created_workspace_count,created_membership_count,completed)
      VALUES(p_run_id,p_source_fingerprint,last_id,scanned,workspace_created,membership_created,NOT has_more)
    ON CONFLICT(run_id) DO UPDATE SET
      last_profile_id=EXCLUDED.last_profile_id,
      scanned_count=private_isg.workspace_backfill_checkpoints.scanned_count+EXCLUDED.scanned_count,
      created_workspace_count=private_isg.workspace_backfill_checkpoints.created_workspace_count+EXCLUDED.created_workspace_count,
      created_membership_count=private_isg.workspace_backfill_checkpoints.created_membership_count+EXCLUDED.created_membership_count,
      completed=EXCLUDED.completed,updated_at=clock_timestamp();
  END IF;
  RETURN jsonb_build_object('schema_version',1,'run_id',p_run_id,'apply',p_apply,
    'last_profile_id',last_id,'scanned',scanned,'proposed',proposed,
    'created_workspaces',workspace_created,'created_memberships',membership_created,
    'has_more',has_more,'completed',NOT has_more,'replayed',false);
END $$;

REVOKE ALL ON FUNCTION private_isg.workspace_backfill_personal_batch(uuid,text,uuid,integer,boolean)
  FROM PUBLIC,anon,authenticated,service_role;
