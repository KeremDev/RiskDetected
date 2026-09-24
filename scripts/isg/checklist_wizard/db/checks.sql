-- Assertions after the base catalogue, its approval and the extension migration. Each block raises on failure.
DO $$
DECLARE base text:='checklist-tr-2026-09-15-v1'; ext text:='checklist-tr-2026-09-25-ext1'; n integer;
BEGIN
  IF (SELECT extends_catalog_version FROM private_isg.checklist_catalogs WHERE catalog_version=ext) IS DISTINCT FROM base
    OR (SELECT extends_catalog_version FROM private_isg.checklist_catalogs WHERE catalog_version=base) IS NOT NULL THEN
    RAISE EXCEPTION 'extension does not name its base';
  END IF;
  -- The base catalogue is untouched.
  IF (SELECT count(*) FROM private_isg.checklist_catalog_templates WHERE catalog_version=base)<>200
    OR (SELECT count(*) FROM private_isg.checklist_catalog_items WHERE catalog_version=base)<>2000
    OR (SELECT professional_review_status FROM private_isg.checklist_catalogs WHERE catalog_version=base)<>'approved' THEN
    RAISE EXCEPTION 'base catalogue changed';
  END IF;
  IF (SELECT count(*) FROM private_isg.checklist_catalog_templates WHERE catalog_version=ext)<>39
    OR (SELECT count(*) FROM private_isg.checklist_catalog_items WHERE catalog_version=ext)<>390
    OR (SELECT count(*) FROM private_isg.checklist_atomic_items WHERE catalog_version=ext)<>390
    OR (SELECT count(*) FROM private_isg.checklist_topic_packs WHERE catalog_version=ext)<>39 THEN
    RAISE EXCEPTION 'extension counts';
  END IF;
  -- Every source an extension template cites has a record in the extension catalogue.
  SELECT count(*) INTO n FROM private_isg.checklist_catalog_templates t
    CROSS JOIN LATERAL jsonb_array_elements_text(t.source_ids) s(id)
    WHERE t.catalog_version=ext AND NOT EXISTS(SELECT 1 FROM private_isg.checklist_catalog_sources x
      WHERE x.catalog_version=ext AND x.source_id=s.id);
  IF n<>0 THEN RAISE EXCEPTION 'extension cites % unrecorded sources',n; END IF;
  -- The runtime templates are published product templates whose items copy with method and help text.
  IF (SELECT count(*) FROM private_isg.checklist_templates t JOIN private_isg.checklist_template_versions v
        ON v.template_code=t.template_code AND v.status='published'
      WHERE t.catalog_version=ext AND t.owner_id IS NULL AND t.workspace_id IS NULL AND t.professional_review_status='pending')<>39
    OR (SELECT count(*) FROM private_isg.checklist_template_items i JOIN private_isg.checklist_templates t USING(template_code)
      WHERE t.catalog_version=ext AND i.verification_method IN ('G','K','Y') AND i.help_text<>'' AND i.atomic_item_code LIKE 'ACX-%')<>390 THEN
    RAISE EXCEPTION 'runtime templates';
  END IF;
  IF (SELECT prompt FROM private_isg.checklist_template_items WHERE template_code='catalog_ext_earthmove' AND item_code='ext_earthmove_01')
      <>'Makinenin devrilmeye ve düşen cisimlere karşı koruyucu kabini görünür hasardan arınmış mı?' THEN
    RAISE EXCEPTION 'runtime item code or text';
  END IF;
END $$;

DO $$
DECLARE r jsonb; codes text[];
BEGIN
  r:=private_isg.read_checklists_company_v3(NULL,'library',NULL,NULL,NULL,NULL,NULL,100,0);
  IF (r->>'total')::integer<>239 OR r->>'catalog_version'<>'checklist-tr-2026-09-15-v1'
    OR r->'catalog_versions'<>'["checklist-tr-2026-09-15-v1","checklist-tr-2026-09-25-ext1"]'::jsonb
    OR r->>'professional_review_status'<>'approved' THEN
    RAISE EXCEPTION 'library header %',r - 'rows' - 'sectors';
  END IF;
  -- Base search still works and extension rows are searchable, down to their questions.
  r:=private_isg.read_checklists_company_v3(NULL,'library','forklift',NULL,NULL,NULL,NULL,100,0);
  codes:=ARRAY(SELECT x->>'template_code' FROM jsonb_array_elements(r->'rows') x);
  IF NOT 'catalog_dpo_02'=ANY(codes) THEN RAISE EXCEPTION 'base forklift list missing: %',codes; END IF;
  r:=private_isg.read_checklists_company_v3(NULL,'library','sondaj',NULL,NULL,NULL,NULL,100,0);
  codes:=ARRAY(SELECT x->>'template_code' FROM jsonb_array_elements(r->'rows') x);
  IF NOT 'catalog_ext_drillrig'=ANY(codes) THEN RAISE EXCEPTION 'extension drilling list missing: %',codes; END IF;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'matched_items') m CROSS JOIN LATERAL jsonb_array_elements(m->'contexts') c
      WHERE c->>'template_code'='catalog_ext_drillrig' AND c->>'item_code' LIKE 'EXT-DRILLRIG-%') THEN
    RAISE EXCEPTION 'extension questions are not matched';
  END IF;
  IF (SELECT r2->>'professional_review_status' FROM jsonb_array_elements(r->'rows') r2
      WHERE r2->>'template_code'='catalog_ext_drillrig')<>'pending' THEN
    RAISE EXCEPTION 'extension row must read as pending';
  END IF;
  -- A sector filter keeps to that sector; extension templates have none.
  r:=private_isg.read_checklists_company_v3(NULL,'library',NULL,NULL,NULL,'DPO',NULL,100,0);
  IF (r->>'total')::integer<>8 THEN RAISE EXCEPTION 'sector filter total %',r->>'total'; END IF;
  r:=private_isg.read_checklists_company_v3(NULL,'library',NULL,'equipment',NULL,NULL,NULL,100,0);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'rows') x WHERE x->>'template_code'='catalog_ext_earthmove') THEN
    RAISE EXCEPTION 'kind filter misses extension equipment';
  END IF;
  -- The start flow offers the extension templates as published product templates.
  r:=private_isg.read_checklists_company_v3(NULL,'catalog',NULL,NULL,NULL,NULL,NULL,20,0);
  IF (r->>'product_template_count')::integer<>239 OR jsonb_array_length(r->'templates')<>239
    OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'templates') x
      WHERE x->>'template_code'='catalog_ext_fuel' AND (x->>'items')::integer=10 AND (x->>'is_product')::boolean) THEN
    RAISE EXCEPTION 'catalogue starters';
  END IF;
END $$;

SELECT 'ok';
