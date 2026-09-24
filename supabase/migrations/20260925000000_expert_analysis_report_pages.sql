-- Analysis report pages (Rapor Merkezi > Analiz raporları): the workspace
-- "reports" action returned at most `lim` rows with no way to page, and no
-- file location, so an export could not be opened directly. It now pages with
-- `lim+1` / `off_` like the "list" action, returns `has_more`, and adds the
-- output asset's id, bucket and object path. Clients treat all three as
-- optional, so they work before and after this migration.
--
-- Only the reports branch of private_isg.expert_analysis is rewritten, in
-- place; the rest of the body, its settings and grants stay as they are.
DO $migration$
DECLARE
  definition text;
  old_block text := $snip$ELSIF p_action='reports' THEN
  SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]') INTO rows FROM (
   SELECT e.id,e.analysis_id,a.title,c.name company_name,e.format,e.created_at,
    fa.byte_size file_size,'İSG Raporu.'||e.format file_name
   FROM private_isg.workspace_export_jobs e JOIN private_isg.workspace_analyses a ON a.id=e.analysis_id
   JOIN public.companies c ON c.id=e.company_id JOIN private_isg.workspace_file_assets fa ON fa.id=e.output_asset_id
   WHERE e.workspace_id=w AND e.status='succeeded' AND private_isg.expert_company_visible(c.user_id,c.id,actor)
   ORDER BY e.created_at DESC LIMIT lim) x;
  RETURN jsonb_build_object('rows',rows);
$snip$;
  new_block text := $snip$ELSIF p_action='reports' THEN
  SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]') INTO rows FROM (
   SELECT e.id,e.analysis_id,a.title,c.name company_name,e.format,e.created_at,
    fa.byte_size file_size,'İSG Raporu.'||e.format file_name,
    fa.id asset_id,fa.bucket download_bucket,fa.object_path download_path
   FROM private_isg.workspace_export_jobs e JOIN private_isg.workspace_analyses a ON a.id=e.analysis_id
   JOIN public.companies c ON c.id=e.company_id JOIN private_isg.workspace_file_assets fa ON fa.id=e.output_asset_id
   WHERE e.workspace_id=w AND e.status='succeeded' AND private_isg.expert_company_visible(c.user_id,c.id,actor)
   ORDER BY e.created_at DESC LIMIT lim+1 OFFSET off_) x;
  RETURN jsonb_build_object(
    'rows',coalesce((SELECT jsonb_agg(value) FROM jsonb_array_elements(rows) WITH ORDINALITY x(value,n) WHERE n<=lim),'[]'),
    'has_more',jsonb_array_length(rows)>lim);
$snip$;
BEGIN
  definition := pg_catalog.pg_get_functiondef('private_isg.expert_analysis(text,jsonb)'::pg_catalog.regprocedure);
  IF position(new_block IN definition) > 0 THEN RETURN; END IF;
  IF position(old_block IN definition) = 0 THEN RAISE EXCEPTION 'EXPERT_ANALYSIS_REPORTS_CHANGED'; END IF;
  EXECUTE replace(definition, old_block, new_block);
END
$migration$;
