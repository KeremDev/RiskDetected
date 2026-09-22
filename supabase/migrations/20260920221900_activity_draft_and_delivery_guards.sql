-- Tighten draft exclusions without changing mutation RPC signatures or authorization.
DO $$
DECLARE definition text;
BEGIN
 definition:=pg_get_functiondef('private_isg.activity_from_receipt()'::regprocedure);
 IF position('payload:=coalesce(answer' IN definition)=0 THEN RAISE EXCEPTION 'ACTIVITY_RECEIPT_CONTRACT_CHANGED'; END IF;
 definition:=replace(definition,
 'payload:=coalesce(answer->''row'',answer->''answer'',answer->''result'',answer);',
 'payload:=coalesce(answer->''row'',answer->''answer'',answer->''result'',answer);
 IF action IN (''open_assessment'',''draft_version'',''attach_source'',''open_upload'',''flag_source_drift'')
 OR coalesce(payload->>''state'','''') IN (''draft'',''editing'') THEN RETURN NEW; END IF;');
 EXECUTE definition;
 definition:=pg_get_functiondef('private_isg.activity_business_row()'::regprocedure);
 IF position('-- Anonymous maintenance' IN definition)=0 THEN RAISE EXCEPTION 'ACTIVITY_ROW_CONTRACT_CHANGED'; END IF;
 definition:=replace(definition,'-- Anonymous maintenance is not an expert operation.',
 '-- The accepted clean-file promotion is performed by a worker on behalf of the uploader.
 IF TG_TABLE_NAME=''file_library_entries'' THEN
   IF r->>''asset_id'' IS NULL THEN RETURN coalesce(NEW,OLD); END IF;
   IF actor IS NULL AND auth.role()=''service_role'' THEN
     actor:=coalesce(r->>''uploaded_by_user_id'',r->>''owner_id'')::uuid;
   END IF;
 END IF;
 -- Anonymous maintenance is not an expert operation.');
 EXECUTE definition;
END $$;

-- A crashed delivery worker has an unknown send outcome. Never replay it automatically.
CREATE FUNCTION private_isg.expire_notebook_delivery_leases() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 UPDATE private_isg.notebook_deliveries SET state='ambiguous',finished_at=clock_timestamp()
 WHERE state='claimed' AND created_at<clock_timestamp()-interval '5 minutes';
$$;
REVOKE ALL ON FUNCTION private_isg.expire_notebook_delivery_leases() FROM PUBLIC,anon,authenticated;
SELECT cron.schedule('isg-notebook-delivery-leases','*/5 * * * *','SELECT private_isg.expire_notebook_delivery_leases()');
