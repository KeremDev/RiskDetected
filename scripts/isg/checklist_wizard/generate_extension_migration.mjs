#!/usr/bin/env node
// Fills the generated seed block of the checklist catalogue extension migration from the wizard's
// extension packs (content/isg/checklist_wizard/source/packs.json).
//
//   node scripts/isg/checklist_wizard/generate_extension_migration.mjs           write the block
//   node scripts/isg/checklist_wizard/generate_extension_migration.mjs --check   fail if it is stale

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import {BASE_CATALOG, EXTENSION_CATALOG, EXTENSION_MIGRATION, extAtomicCode, extItemCode, extRuntimeItem, extRuntimeTemplate,
  extTemplateCode} from "./codes.mjs";

const root = path.resolve(import.meta.dirname, "../../..");
const packsPath = path.join(root, "content/isg/checklist_wizard/source/packs.json");
const seed = JSON.parse(fs.readFileSync(path.join(root, "docs/isg/checklists/ISG_ADASI_CHECKLIST_SEED.json"), "utf8"));
const packsText = fs.readFileSync(packsPath, "utf8");
const packs = JSON.parse(packsText).packs;
const migrationPath = path.join(root, EXTENSION_MIGRATION);
const start = "-- BEGIN GENERATED CHECKLIST EXTENSION SEED";
const end = "-- END GENERATED CHECKLIST EXTENSION SEED";

if (seed.catalog_version !== BASE_CATALOG) throw new Error(`seed is ${seed.catalog_version}, expected ${BASE_CATALOG}`);

// Turkish legislation the extension packs cite that the base catalogue has no source record for.
// Titles name the instrument; the link is the official portal, not a verified article reference.
const MEVZUAT = "https://www.mevzuat.gov.tr/";
const NEW_SOURCES = {
  "TR6331": ["6331 sayılı İş Sağlığı ve Güvenliği Kanunu", MEVZUAT],
  "TR-ADR": ["Tehlikeli malların karayoluyla taşınmasına ilişkin mevzuat (ADR)", MEVZUAT],
  "TR-ASBESTOS": ["Asbestle Çalışmalarda Sağlık ve Güvenlik Önlemleri Hakkında Yönetmelik", MEVZUAT],
  "TR-ATEX": ["Çalışanların Patlayıcı Ortamların Tehlikelerinden Korunması Hakkında Yönetmelik", MEVZUAT],
  "TR-BIOCIDE": ["Biyosidal ürünler ve bitki koruma ürünleri mevzuatı", MEVZUAT],
  "TR-BUILDINGS": ["İşyeri Bina ve Eklentilerinde Alınacak Sağlık ve Güvenlik Önlemlerine İlişkin Yönetmelik", MEVZUAT],
  "TR-CHEMICAL": ["Kimyasal Maddelerle Çalışmalarda Sağlık ve Güvenlik Önlemleri Hakkında Yönetmelik", MEVZUAT],
  "TR-CONSTRUCTION": ["Yapı İşlerinde İş Sağlığı ve Güvenliği Yönetmeliği", MEVZUAT],
  "TR-DUST": ["Tozla Mücadele Yönetmeliği", MEVZUAT],
  "TR-EARTHING": ["Elektrik Tesislerinde Topraklamalar Yönetmeliği", MEVZUAT],
  "TR-EPDK": ["EPDK mevzuatı; TS 12820 ve TS 11939 standartları", "https://www.epdk.gov.tr/"],
  "TR-EQUIPMENT": ["İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği", MEVZUAT],
  "TR-FGAS": ["Florlu sera gazları mevzuatı", MEVZUAT],
  "TR-FIREBUILD": ["Binaların Yangından Korunması Hakkında Yönetmelik", MEVZUAT],
  "TR-GASINSTALL": ["Doğal gaz iç tesisat ve sertifika mevzuatı", MEVZUAT],
  "TR-HANDLING": ["Elle Taşıma İşleri Yönetmeliği", MEVZUAT],
  "TR-HVFACILITY": ["Elektrik Kuvvetli Akım Tesisleri Yönetmeliği", MEVZUAT],
  "TR-HYGIENETRAINING": ["Hijyen Eğitimi Yönetmeliği", MEVZUAT],
  "TR-LIFT": ["Asansör Yönetmeliği (2014/33/AB) ve Asansör İşletme, Bakım ve Periyodik Kontrol Yönetmeliği", MEVZUAT],
  "TR-PPE": ["Kişisel Koruyucu Donanımların İşyerlerinde Kullanılması Hakkında Yönetmelik", MEVZUAT],
  "TR-PREGNANT": ["Gebe veya Emziren Kadınların Çalıştırılma Şartlarıyla Emzirme Odaları ve Çocuk Bakım Yurtlarına Dair Yönetmelik", MEVZUAT],
  "TR-PYRO": ["Piroteknik maddelere ilişkin mevzuat", MEVZUAT],
  "TR-RADIATION": ["Nükleer Düzenleme Kurumu radyasyon güvenliği düzenlemeleri", "https://ndk.org.tr/"],
  "TR-RISK": ["İş Sağlığı ve Güvenliği Risk Değerlendirmesi Yönetmeliği", MEVZUAT],
  "TR-SEVESO": ["Büyük Endüstriyel Kazaların Önlenmesi ve Etkilerinin Azaltılması Hakkında Yönetmelik", MEVZUAT],
  "TR-TRAFFIC": ["2918 sayılı Karayolları Trafik Kanunu", MEVZUAT],
  "TR-YOUNG": ["Çocuk ve Genç İşçilerin Çalıştırılma Usul ve Esasları Hakkında Yönetmelik", MEVZUAT],
};

const baseSources = new Set(seed.sources.map((s) => s.source_id));
const used = [...new Set(packs.flatMap((p) => p.sources))].sort();
const missing = used.filter((id) => !baseSources.has(id) && !NEW_SOURCES[id]);
if (missing.length) throw new Error(`no source record for ${missing.join(", ")}`);

const today = "2026-09-25";
const scope = "Kontrol listesi sihirbazının genişleme şablonu; yalnız seçilen iş, alan veya ekipmana uygulanır. Alan uzmanı incelemesi bekliyor.";
const extension = {
  catalog_version: EXTENSION_CATALOG, extends: BASE_CATALOG, generated_at: today, publication_status: "draft_pending_domain_review",
  template_count: packs.length, item_count: packs.reduce((n, p) => n + p.items.length, 0),
  base_sources: used.filter((id) => baseSources.has(id)),
  sources: used.filter((id) => !baseSources.has(id)).map((id) => ({source_id: id, title: NEW_SOURCES[id][0], url: NEW_SOURCES[id][1],
    jurisdiction: "TR", source_type: "official_regulation", source_checked_at: today, rights_status: "original_questions_not_a_copy_of_source",
    reviewed_scope: "Konu başlığı düzeyinde atıf; madde düzeyinde hukuki inceleme yapılmadı."})),
  topic_packs: packs.map((p) => ({code: p.code, title_tr: p.title, kind: p.kind, aliases: p.aliases, source_ids: p.sources, item_count: p.items.length})),
  atomic_items: packs.flatMap((p) => p.items.map(([, text], i) => ({atomic_item_code: extAtomicCode(p.code, i), text_tr: text,
    source_ids: p.sources, tags: p.aliases.slice(0, 3)}))),
  templates: packs.map((p) => ({template_code: extTemplateCode(p.code), runtime_template_code: extRuntimeTemplate(p.code), pack_code: p.code,
    title_tr: p.title, kind: p.kind, aliases: p.aliases, source_ids: p.sources, scope_note: scope,
    items: p.items.map(([vm, text], i) => ({item_code: extItemCode(p.code, i), runtime_item_code: extRuntimeItem(p.code, i),
      atomic_item_code: extAtomicCode(p.code, i), order: i + 1, text_tr: text, verification_method: vm,
      help_text: seed.verification_methods[vm].help, tags: p.aliases.slice(0, 3), risk_topic: p.title}))})),
};

const compact = JSON.stringify(extension);
const tag = "$isg_checklist_extension$";
if (compact.includes(tag)) throw new Error("Unexpected dollar-quote marker in the extension seed.");
const seedSha = crypto.createHash("sha256").update(compact).digest("hex");
const sourceSha = crypto.createHash("sha256").update(packsText).digest("hex");

const block = `${start}
DO $seed$
DECLARE
  seed jsonb := ${tag}${compact}${tag}::jsonb;
  base private_isg.checklist_catalogs;
  source jsonb;
  pack jsonb;
  atom jsonb;
  template jsonb;
  item jsonb;
BEGIN
  SELECT * INTO base FROM private_isg.checklist_catalogs WHERE catalog_version=seed->>'extends';
  IF NOT FOUND THEN RAISE EXCEPTION 'CHECKLIST_EXTENSION_BASE_MISSING'; END IF;

  INSERT INTO private_isg.checklist_catalogs(
    catalog_version,schema_version,language,generated_on,publication_status,professional_review_status,
    seed_sha256,catalog_sha256,template_count,item_count,answer_contract,verification_methods,source_payload,
    created_at,extends_catalog_version)
  VALUES(
    seed->>'catalog_version',base.schema_version,base.language,(seed->>'generated_at')::date,
    seed->>'publication_status','pending','${seedSha}','${sourceSha}',
    (seed->>'template_count')::integer,(seed->>'item_count')::integer,base.answer_contract,
    base.verification_methods,seed - 'templates' - 'atomic_items' - 'topic_packs',clock_timestamp(),base.catalog_version)
  ON CONFLICT(catalog_version) DO NOTHING;

  IF NOT EXISTS(
    SELECT 1 FROM private_isg.checklist_catalogs
    WHERE catalog_version=seed->>'catalog_version' AND seed_sha256='${seedSha}'
      AND extends_catalog_version=base.catalog_version
  ) THEN
    RAISE EXCEPTION 'CHECKLIST_CATALOG_IMMUTABILITY_CONFLICT';
  END IF;

  -- Sources the base catalogue already describes are copied as they are; the rest are new records.
  INSERT INTO private_isg.checklist_catalog_sources(
    catalog_version,source_id,title,url,jurisdiction,source_type,reviewed_scope,source_checked_on,
    effective_on,item_level_legal_reviewed_at,rights_status)
  SELECT seed->>'catalog_version',s.source_id,s.title,s.url,s.jurisdiction,s.source_type,s.reviewed_scope,
    s.source_checked_on,s.effective_on,s.item_level_legal_reviewed_at,s.rights_status
  FROM private_isg.checklist_catalog_sources s
  WHERE s.catalog_version=base.catalog_version
    AND s.source_id IN (SELECT jsonb_array_elements_text(seed->'base_sources'))
  ON CONFLICT(catalog_version,source_id) DO NOTHING;
  FOR source IN SELECT value FROM jsonb_array_elements(seed->'sources') LOOP
    INSERT INTO private_isg.checklist_catalog_sources(
      catalog_version,source_id,title,url,jurisdiction,source_type,reviewed_scope,source_checked_on,
      effective_on,item_level_legal_reviewed_at,rights_status)
    VALUES(seed->>'catalog_version',source->>'source_id',source->>'title',source->>'url',
      source->>'jurisdiction',source->>'source_type',source->>'reviewed_scope',
      (source->>'source_checked_at')::date,NULL,NULL,source->>'rights_status')
    ON CONFLICT(catalog_version,source_id) DO NOTHING;
  END LOOP;

  FOR pack IN SELECT value FROM jsonb_array_elements(seed->'topic_packs') LOOP
    INSERT INTO private_isg.checklist_topic_packs(catalog_version,pack_code,title,kind,aliases,source_ids,item_count)
    VALUES(seed->>'catalog_version',pack->>'code',pack->>'title_tr',pack->>'kind',pack->'aliases',
      pack->'source_ids',(pack->>'item_count')::integer)
    ON CONFLICT(catalog_version,pack_code) DO NOTHING;
  END LOOP;

  FOR atom IN SELECT value FROM jsonb_array_elements(seed->'atomic_items') LOOP
    INSERT INTO private_isg.checklist_atomic_items(
      catalog_version,atomic_item_code,prompt,source_ids,tags,content_status,
      professional_review_status,professional_reviewed_at,legal_binding_claim)
    VALUES(seed->>'catalog_version',atom->>'atomic_item_code',atom->>'text_tr',atom->'source_ids',atom->'tags',
      'product_template','pending',NULL,false)
    ON CONFLICT(catalog_version,atomic_item_code) DO NOTHING;
  END LOOP;

  FOR template IN SELECT value FROM jsonb_array_elements(seed->'templates') LOOP
    INSERT INTO private_isg.checklist_catalog_templates(
      catalog_version,template_code,runtime_template_code,sector_code,sector_name,title,pack_code,kind,
      aliases,source_ids,scope_note,content_status,professional_review_status,suggested_frequency,
      frequency_basis,item_count,search_document)
    VALUES(seed->>'catalog_version',template->>'template_code',template->>'runtime_template_code',NULL,NULL,
      template->>'title_tr',template->>'pack_code',template->>'kind',template->'aliases',template->'source_ids',
      template->>'scope_note','product_template','pending',NULL,'user_defined_not_statutory',
      jsonb_array_length(template->'items'),
      private_isg.checklist_search_fold(concat_ws(' ',template->>'template_code',template->>'title_tr',
        template->>'scope_note',template->'aliases'::text)))
    ON CONFLICT(catalog_version,template_code) DO NOTHING;

    INSERT INTO private_isg.checklist_templates(
      template_code,title,owner_id,is_archived,workspace_id,catalog_version,catalog_template_code,
      sector_code,template_kind,aliases,scope_note,professional_review_status,source_ids,created_at)
    VALUES(template->>'runtime_template_code',template->>'title_tr',NULL,false,NULL,seed->>'catalog_version',
      template->>'template_code',NULL,template->>'kind',template->'aliases',template->>'scope_note','pending',
      template->'source_ids',clock_timestamp())
    ON CONFLICT(template_code) DO NOTHING;

    INSERT INTO private_isg.checklist_template_versions(
      template_code,version,status,approved_by,approval_note,published_at,created_at)
    VALUES(template->>'runtime_template_code',1,'published',NULL,
      'Ürün kataloğu · uzmanlık alanı incelemesi bekliyor',clock_timestamp(),clock_timestamp())
    ON CONFLICT(template_code,version) DO NOTHING;

    FOR item IN SELECT value FROM jsonb_array_elements(template->'items') LOOP
      INSERT INTO private_isg.checklist_catalog_items(
        catalog_version,template_code,item_code,atomic_item_code,source_pack_item_code,position,prompt,
        verification_method,help_text,tags,risk_topic,source_ids,content_status,response_required,
        allows_not_applicable,na_reason_required,evidence_recommended,photo_required,search_document)
      VALUES(seed->>'catalog_version',template->>'template_code',item->>'item_code',item->>'atomic_item_code',
        item->>'item_code',(item->>'order')::integer,item->>'text_tr',item->>'verification_method',
        item->>'help_text',item->'tags',item->>'risk_topic',template->'source_ids','product_template',true,
        true,true,true,false,
        private_isg.checklist_search_fold(concat_ws(' ',item->>'item_code',item->>'text_tr',
          item->>'help_text',item->>'risk_topic',item->'tags'::text)))
      ON CONFLICT(catalog_version,template_code,item_code) DO NOTHING;

      INSERT INTO private_isg.checklist_template_items(
        template_code,version,item_code,prompt,allows_not_applicable,position,atomic_item_code,
        verification_method,help_text,tags,risk_topic,source_ids,na_reason_required,
        evidence_recommended,photo_required,catalog_item_code)
      VALUES(template->>'runtime_template_code',1,item->>'runtime_item_code',item->>'text_tr',true,
        (item->>'order')::integer,item->>'atomic_item_code',item->>'verification_method',item->>'help_text',
        item->'tags',item->>'risk_topic',template->'source_ids',true,true,false,item->>'item_code')
      ON CONFLICT(template_code,version,item_code) DO NOTHING;
    END LOOP;
  END LOOP;

  IF (SELECT count(*) FROM private_isg.checklist_catalog_templates
      WHERE catalog_version=seed->>'catalog_version') <> (seed->>'template_count')::integer
    OR (SELECT count(*) FROM private_isg.checklist_catalog_items
      WHERE catalog_version=seed->>'catalog_version') <> (seed->>'item_count')::integer THEN
    RAISE EXCEPTION 'CHECKLIST_CATALOG_COUNT_MISMATCH';
  END IF;
END
$seed$;
${end}`;

const migration = fs.readFileSync(migrationPath, "utf8");
const from = migration.indexOf(start);
const to = migration.indexOf(end);
if (from < 0 || to < from) throw new Error(`generated seed markers are missing from ${EXTENSION_MIGRATION}`);
const output = migration.slice(0, from) + block + migration.slice(to + end.length);
const summary = `${EXTENSION_CATALOG} extends ${BASE_CATALOG}: templates=${extension.template_count} items=${extension.item_count} ` +
  `new sources=${extension.sources.length} seed_sha256=${seedSha}`;
if (process.argv.includes("--check")) {
  if (output !== migration) { console.error(`${EXTENSION_MIGRATION} is stale; run node scripts/isg/checklist_wizard/generate_extension_migration.mjs`); process.exit(1); }
  console.log(`${EXTENSION_MIGRATION} up to date · ${summary}`);
} else {
  fs.writeFileSync(migrationPath, output);
  console.log(`wrote ${EXTENSION_MIGRATION} · ${summary}`);
}
