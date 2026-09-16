SET LOCAL lock_timeout='1s';
-- P04 deduplicates blobs by owner + digest. The library entry, not the blob's
-- first upload, is the authority for filing that same content in a company.
DO $$ DECLARE d text; old_clause text; BEGIN
 d:=pg_get_functiondef('private_isg.pilot_record_validate()'::regprocedure);
 old_clause:=' AND a.company_id=NEW.company_id';
 IF (length(d)-length(replace(d,old_clause,'')))/length(old_clause)<>2 THEN RAISE EXCEPTION 'ASSET_TRIGGER_BASELINE_CHANGED'; END IF;
 EXECUTE replace(d,old_clause,''); -- owner + clean + current-company filing remain required
 d:=pg_get_functiondef('private_isg.process_mutate(uuid,text,uuid,uuid,jsonb)'::regprocedure);
 old_clause:='AND fa.company_id=p_company AND fle.company_id=p_company';
 IF strpos(d,old_clause)=0 THEN RAISE EXCEPTION 'ASSET_WRITE_BASELINE_CHANGED'; END IF;
 EXECUTE replace(d,old_clause,'AND (fa.company_id=p_company OR private_isg.p05_pilot_account_enabled(actor,true)) AND fle.company_id=p_company');
 d:=pg_get_functiondef('private_isg.pilot_process_attachment(text,uuid,text)'::regprocedure);
 old_clause:='AND fa.company_id=fle.company_id AND fa.scan_status=''clean''';
 IF strpos(d,old_clause)=0 THEN RAISE EXCEPTION 'ASSET_READ_BASELINE_CHANGED'; END IF;
 EXECUTE replace(d,old_clause,'AND (fa.company_id=fle.company_id OR private_isg.p05_pilot_account_enabled(actor,false)) AND fa.scan_status=''clean''');
END $$;
NOTIFY pgrst,'reload schema';
