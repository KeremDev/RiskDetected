#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const root = path.resolve(import.meta.dirname, "../..");
const seedPath = path.join(root, "docs/isg/checklists/ISG_ADASI_CHECKLIST_SEED.json");
const cataloguePath = path.join(root, "docs/isg/checklists/ISG_ADASI_CHECKLIST_TAM_MADDE_KATALOGU_DOGRULANMIS.md");
const pretty = fs.readFileSync(seedPath, "utf8");
const seed = JSON.parse(pretty);
const seedSHA = crypto.createHash("sha256").update(pretty).digest("hex");
const catalogueSHA = crypto.createHash("sha256").update(fs.readFileSync(cataloguePath)).digest("hex");
const phase = process.argv[2];
const index = Number(process.argv[3] ?? 0);
const atomicBatchSize = 240;
const templateBatchSize = 20;

if (seed.templates?.length !== 200 || seed.counts?.visible_item_rows !== 2000) {
  throw new Error("Unexpected catalogue shape.");
}

const literal = (value, tag) => {
  const json = JSON.stringify(value);
  if (json.includes(`$${tag}$`)) throw new Error(`Dollar tag collision: ${tag}`);
  return `$${tag}$${json}$${tag}$::jsonb`;
};

if (phase === "list") {
  console.log(JSON.stringify([
    { phase: "meta", count: 1 },
    { phase: "packs", count: 1 },
    { phase: "atomic", count: Math.ceil(seed.atomic_items.length / atomicBatchSize) },
    { phase: "templates", count: Math.ceil(seed.templates.length / templateBatchSize) },
    { phase: "verify", count: 1 }
  ]));
  process.exit(0);
}

let sql;
if (phase === "meta") {
  const meta = {
    ...seed,
    topic_packs: undefined,
    atomic_items: undefined,
    templates: undefined
  };
  sql = `DO $batch$ DECLARE seed jsonb := ${literal(meta, "checklist_meta")}; row jsonb; BEGIN
    INSERT INTO private_isg.checklist_catalogs(catalog_version,schema_version,language,generated_on,
      publication_status,professional_review_status,seed_sha256,catalog_sha256,template_count,item_count,
      answer_contract,verification_methods,source_payload,created_at)
    VALUES(seed->>'catalog_version',seed->>'schema_version',seed->>'language',(seed->>'generated_at')::date,
      seed->>'publication_status','pending','${seedSHA}','${catalogueSHA}',
      (seed#>>'{counts,total_templates}')::integer,(seed#>>'{counts,visible_item_rows}')::integer,
      seed->'answer_contract',seed->'verification_methods',seed,clock_timestamp())
    ON CONFLICT(catalog_version) DO NOTHING;
    IF NOT EXISTS(SELECT 1 FROM private_isg.checklist_catalogs WHERE catalog_version=seed->>'catalog_version'
      AND seed_sha256='${seedSHA}' AND template_count=200 AND item_count=2000) THEN
      RAISE EXCEPTION 'CHECKLIST_CATALOG_IMMUTABILITY_CONFLICT'; END IF;
    FOR row IN SELECT value FROM jsonb_array_elements(seed->'sectors') LOOP
      INSERT INTO private_isg.checklist_catalog_sectors(catalog_version,sector_code,name,aliases,pack_codes)
      VALUES(seed->>'catalog_version',row->>'code',row->>'name',row->'aliases',row->'packs')
      ON CONFLICT(catalog_version,sector_code) DO NOTHING; END LOOP;
    FOR row IN SELECT value FROM jsonb_array_elements(seed->'sources') LOOP
      INSERT INTO private_isg.checklist_catalog_sources(catalog_version,source_id,title,url,jurisdiction,
        source_type,reviewed_scope,source_checked_on,effective_on,item_level_legal_reviewed_at,rights_status)
      VALUES(seed->>'catalog_version',row->>'source_id',row->>'title',row->>'url',row->>'jurisdiction',
        row->>'source_type',row->>'reviewed_scope',(row->>'source_checked_at')::date,
        (row->>'effective_date')::date,(row->>'item_level_legal_reviewed_at')::timestamptz,row->>'rights_status')
      ON CONFLICT(catalog_version,source_id) DO NOTHING; END LOOP;
  END $batch$;`;
} else if (phase === "packs") {
  const rows = seed.topic_packs.map(({ items, ...pack }) => ({ ...pack, item_count: items.length }));
  sql = `DO $batch$ DECLARE row jsonb; BEGIN FOR row IN SELECT value FROM jsonb_array_elements(${literal(rows, "checklist_packs")}) LOOP
    INSERT INTO private_isg.checklist_topic_packs(catalog_version,pack_code,title,kind,aliases,source_ids,item_count)
    VALUES('${seed.catalog_version}',row->>'code',row->>'title_tr',row->>'kind',row->'aliases',row->'source_ids',
      (row->>'item_count')::integer) ON CONFLICT(catalog_version,pack_code) DO NOTHING;
  END LOOP; END $batch$;`;
} else if (phase === "atomic") {
  const rows = seed.atomic_items.slice(index * atomicBatchSize, (index + 1) * atomicBatchSize);
  if (!rows.length) throw new Error(`Unknown atomic batch ${index}`);
  sql = `DO $batch$ DECLARE row jsonb; BEGIN FOR row IN SELECT value FROM jsonb_array_elements(${literal(rows, "checklist_atomic")}) LOOP
    INSERT INTO private_isg.checklist_atomic_items(catalog_version,atomic_item_code,prompt,source_ids,tags,
      content_status,professional_review_status,professional_reviewed_at,legal_binding_claim)
    VALUES('${seed.catalog_version}',row->>'atomic_item_code',row->>'text_tr',row->'source_ids',row->'tags',
      row->>'content_status',row->>'professional_review_status',(row->>'professional_reviewed_at')::timestamptz,
      coalesce((row->>'legal_binding_claim')::boolean,false))
    ON CONFLICT(catalog_version,atomic_item_code) DO NOTHING;
  END LOOP; END $batch$;`;
} else if (phase === "templates") {
  const rows = seed.templates.slice(index * templateBatchSize, (index + 1) * templateBatchSize);
  if (!rows.length) throw new Error(`Unknown template batch ${index}`);
  sql = `DO $batch$ DECLARE template jsonb; item jsonb; runtime_template text; runtime_item text; BEGIN
    FOR template IN SELECT value FROM jsonb_array_elements(${literal(rows, "checklist_templates")}) LOOP
      runtime_template := 'catalog_' || lower(replace(template->>'template_code','-','_'));
      INSERT INTO private_isg.checklist_catalog_templates(catalog_version,template_code,runtime_template_code,
        sector_code,sector_name,title,pack_code,kind,aliases,source_ids,scope_note,content_status,
        professional_review_status,suggested_frequency,frequency_basis,item_count,search_document)
      VALUES('${seed.catalog_version}',template->>'template_code',runtime_template,
        nullif(template->>'sector_code',''),nullif(template->>'sector_name',''),template->>'title_tr',
        template->>'pack_code',template->>'kind',template->'aliases',template->'source_ids',template->>'scope_note',
        template->>'content_status',template->>'professional_review_status',template->>'suggested_frequency',
        template->>'frequency_basis',jsonb_array_length(template->'items'),
        private_isg.checklist_search_fold(concat_ws(' ',template->>'template_code',template->>'title_tr',
          template->>'sector_name',template->>'scope_note',template->'aliases'::text)))
      ON CONFLICT(catalog_version,template_code) DO NOTHING;
      INSERT INTO private_isg.checklist_templates(template_code,title,owner_id,is_archived,workspace_id,
        catalog_version,catalog_template_code,sector_code,template_kind,aliases,scope_note,
        professional_review_status,source_ids,created_at)
      VALUES(runtime_template,template->>'title_tr',NULL,false,NULL,'${seed.catalog_version}',
        template->>'template_code',nullif(template->>'sector_code',''),template->>'kind',template->'aliases',
        template->>'scope_note',template->>'professional_review_status',template->'source_ids',clock_timestamp())
      ON CONFLICT(template_code) DO NOTHING;
      INSERT INTO private_isg.checklist_template_versions(template_code,version,status,approved_by,approval_note,
        published_at,created_at) VALUES(runtime_template,1,'published',NULL,
        'Ürün kataloğu · uzmanlık alanı incelemesi bekliyor',clock_timestamp(),clock_timestamp())
      ON CONFLICT(template_code,version) DO NOTHING;
      FOR item IN SELECT value FROM jsonb_array_elements(template->'items') LOOP
        runtime_item := lower(replace(item->>'item_code','-','_'));
        INSERT INTO private_isg.checklist_catalog_items(catalog_version,template_code,item_code,atomic_item_code,
          source_pack_item_code,position,prompt,verification_method,help_text,tags,risk_topic,source_ids,
          content_status,response_required,allows_not_applicable,na_reason_required,evidence_recommended,
          photo_required,search_document)
        VALUES('${seed.catalog_version}',template->>'template_code',item->>'item_code',item->>'atomic_item_code',
          item->>'source_pack_item_code',(item->>'order')::integer,item->>'text_tr',item->>'verification_method',
          item->>'help_text',item->'tags',item->>'risk_topic',item->'source_ids',item->>'content_status',
          coalesce((item->>'response_required')::boolean,true),coalesce((item->>'na_allowed')::boolean,true),
          coalesce((item->>'na_reason_required')::boolean,true),coalesce((item->>'evidence_recommended')::boolean,false),
          coalesce((item->>'photo_required')::boolean,false),private_isg.checklist_search_fold(concat_ws(' ',
            item->>'item_code',item->>'text_tr',item->>'help_text',item->>'risk_topic',item->'tags'::text)))
        ON CONFLICT(catalog_version,template_code,item_code) DO NOTHING;
        INSERT INTO private_isg.checklist_template_items(template_code,version,item_code,prompt,
          allows_not_applicable,position,atomic_item_code,verification_method,help_text,tags,risk_topic,source_ids,
          na_reason_required,evidence_recommended,photo_required,catalog_item_code)
        VALUES(runtime_template,1,runtime_item,item->>'text_tr',coalesce((item->>'na_allowed')::boolean,true),
          (item->>'order')::integer,item->>'atomic_item_code',item->>'verification_method',item->>'help_text',
          item->'tags',item->>'risk_topic',item->'source_ids',coalesce((item->>'na_reason_required')::boolean,true),
          coalesce((item->>'evidence_recommended')::boolean,false),coalesce((item->>'photo_required')::boolean,false),
          item->>'item_code') ON CONFLICT(template_code,version,item_code) DO NOTHING;
      END LOOP;
    END LOOP;
  END $batch$;`;
} else if (phase === "verify") {
  sql = `DO $batch$ BEGIN
    IF (SELECT count(*) FROM private_isg.checklist_catalog_sectors WHERE catalog_version='${seed.catalog_version}') <> 24
      OR (SELECT count(*) FROM private_isg.checklist_catalog_sources WHERE catalog_version='${seed.catalog_version}') <> 54
      OR (SELECT count(*) FROM private_isg.checklist_topic_packs WHERE catalog_version='${seed.catalog_version}') <> 117
      OR (SELECT count(*) FROM private_isg.checklist_atomic_items WHERE catalog_version='${seed.catalog_version}') <> 1169
      OR (SELECT count(*) FROM private_isg.checklist_catalog_templates WHERE catalog_version='${seed.catalog_version}') <> 200
      OR (SELECT count(*) FROM private_isg.checklist_catalog_items WHERE catalog_version='${seed.catalog_version}') <> 2000
      OR (SELECT count(*) FROM private_isg.checklist_templates WHERE catalog_version='${seed.catalog_version}') <> 200
      OR (SELECT count(*) FROM private_isg.checklist_template_items i JOIN private_isg.checklist_templates t
          ON t.template_code=i.template_code WHERE t.catalog_version='${seed.catalog_version}' AND i.version=1) <> 2000
    THEN RAISE EXCEPTION 'CHECKLIST_CATALOG_COUNT_MISMATCH'; END IF;
  END $batch$;`;
} else {
  throw new Error("Usage: generate_checklist_catalog_batch.mjs list|meta|packs|atomic|templates|verify [index]");
}

process.stdout.write(sql);
