#!/usr/bin/env node
// Builds the checklist wizard catalogue (App/WizardAssets/isg_wizard_v6/rd-checklist.json).
//
// Inputs, all read-only:
//   docs/isg/checklists/ISG_ADASI_CHECKLIST_SEED.json   the server catalogue (117 packs, 200 templates)
//   content/isg/checklist_wizard/source/packs.json      wizard-only extension packs
//   content/isg/checklist_wizard/source/triggers.json   pack triggers against the V6 wizard answers
//   App/WizardAssets/isg_wizard_v6/rd-data.json         V6 taxonomy the triggers point at
//
// Items that exist on the server carry their runtime template and item code, so a saved list can copy
// them with their verification method and help text. Extension items carry none and are saved as the
// expert's own questions.
//
//   node scripts/isg/checklist_wizard/build.mjs           write the catalogue
//   node scripts/isg/checklist_wizard/build.mjs --check   fail if the written catalogue is stale

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const root = path.resolve(import.meta.dirname, "../../..");
const read = (p) => JSON.parse(fs.readFileSync(path.join(root, p), "utf8"));
const OUT = "App/WizardAssets/isg_wizard_v6/rd-checklist.json";
const VERSION = "isgada-kontrol-1.0.0";
const KINDS = ["general", "sector", "hazard", "activity", "equipment"];

const seed = read("docs/isg/checklists/ISG_ADASI_CHECKLIST_SEED.json");
const ext = read("content/isg/checklist_wizard/source/packs.json");
const trig = read("content/isg/checklist_wizard/source/triggers.json");
const data = read("App/WizardAssets/isg_wizard_v6/rd-data.json");

const errors = [];
const fail = (msg) => errors.push(msg);

// Everything RDEngine.features() can put in the feature set.
const known = new Set(["employee_count_10plus", "employee_count_50plus", "hazard_class_low", "hazard_class_medium", "hazard_class_high"]);
for (const kind of ["sectors", "equipment", "tasks", "materials"]) data[kind].forEach((x) => (x.f || []).forEach((f) => known.add(f)));
data.followups.forEach((f) => f.o.forEach((o) => (o.f || []).forEach((x) => known.add(x))));
Object.entries(data.fi).forEach(([k, v]) => { known.add(k); v.forEach((x) => known.add(x)); });
Object.keys(data.cond).forEach((k) => known.add(k));
data.areas.forEach((a) => known.add(a.id));
(data.em ? data.em.site : []).forEach((s) => known.add(s.id));
const ids = {eq: new Set(data.equipment.map((x) => x.id)), tk: new Set(data.tasks.map((x) => x.id)), mt: new Set(data.materials.map((x) => x.id))};

// Source titles: the seed's own records and the V6 legal labels.
const sources = {};
seed.sources.forEach((s) => { sources[s.source_id] = s.title; });
Object.entries(data.legal).forEach(([k, v]) => { if (!sources[k]) sources[k] = v; });

// One published product template per pack is enough to copy its items.
const firstTemplate = new Map();
seed.templates.forEach((t) => { if (!firstTemplate.has(t.pack_code)) firstTemplate.set(t.pack_code, t); });
const runtimeCode = (code) => code.toLowerCase().replace(/-/g, "_");

const packs = [];
seed.topic_packs.forEach((p) => {
  const t = firstTemplate.get(p.code);
  if (!t) { fail(`pack ${p.code} has no product template`); return; }
  const items = t.items.map((i) => {
    const pi = p.items.find((x) => x.atomic_item_code === i.atomic_item_code);
    if (!pi || pi.text_tr !== i.text_tr) fail(`pack ${p.code} item ${i.item_code} differs from its template copy`);
    return [i.atomic_item_code, i.text_tr, i.verification_method, runtimeCode(i.item_code)];
  });
  packs.push({id: p.code, t: p.title_tr, k: p.kind, al: p.aliases, sr: p.source_ids, ref: "catalog_" + runtimeCode(t.template_code), it: items, nw: 0});
});
const seen = new Set(packs.map((p) => p.id));
ext.packs.forEach((p) => {
  if (seen.has(p.code)) fail(`extension pack ${p.code} repeats an existing code`);
  seen.add(p.code);
  if (!/^[A-Z][A-Z0-9]{1,15}$/.test(p.code)) fail(`extension pack code ${p.code} is not upper-case`);
  if (p.items.length < 6 || p.items.length > 12) fail(`extension pack ${p.code} has ${p.items.length} items`);
  const items = p.items.map(([vm, text], i) => {
    if (!["G", "K", "Y"].includes(vm)) fail(`${p.code}-${i + 1}: unknown method ${vm}`);
    if (!/\?$/.test(text) || text.length > 200) fail(`${p.code}-${i + 1}: an item is one question up to 200 characters`);
    return ["ACX-" + p.code + "-" + String(i + 1).padStart(2, "0"), text, vm, ""];
  });
  packs.push({id: p.code, t: p.title, k: p.kind, al: p.aliases, sr: p.sources, ref: "", it: items, nw: 1});
});

const texts = new Map();
packs.forEach((p) => {
  if (!KINDS.includes(p.k)) fail(`pack ${p.id} has unknown kind ${p.k}`);
  p.sr.forEach((s) => { if (!sources[s]) fail(`pack ${p.id} cites unknown source ${s}`); });
  p.it.forEach(([code, text]) => {
    const key = text.toLocaleLowerCase("tr");
    if (texts.has(key) && texts.get(key) !== code) fail(`duplicate question text in ${code} and ${texts.get(key)}`);
    texts.set(key, code);
  });
});

const byId = new Map(packs.map((p) => [p.id, p]));
Object.keys(trig.packs).forEach((id) => { if (!byId.has(id)) fail(`triggers name unknown pack ${id}`); });
packs.forEach((p) => {
  const t = trig.packs[p.id];
  if (!t) { fail(`pack ${p.id} has no trigger entry`); return; }
  const tr = {};
  (t.f || []).forEach((f) => { if (!known.has(f)) fail(`pack ${p.id} trigger feature ${f} never occurs`); });
  ["eq", "tk", "mt"].forEach((k) => (t[k] || []).forEach((x) => { if (!ids[k].has(x)) fail(`pack ${p.id} trigger ${k} ${x} does not exist`); }));
  // An equipment group stands for every machine in it, so the catalogue only ever lists equipment ids.
  const grouped = (t.eg || []).flatMap((g) => {
    const members = data.equipment.filter((x) => x.g === g).map((x) => x.id);
    if (!members.length) fail(`pack ${p.id} trigger group ${g} is empty`);
    return members;
  });
  const eq = [...new Set((t.eq || []).concat(grouped))];
  if (eq.length) tr.eq = eq;
  ["f", "tk", "mt"].forEach((k) => { if ((t[k] || []).length) tr[k] = t[k]; });
  p.tr = tr;
});

data.sectors.forEach((s) => { if (!trig.sectors[s.id]) fail(`sector ${s.id} ${s.n} has no checklist packs`); });
Object.entries(trig.sectors).forEach(([sid, list]) => {
  if (!data.sectors.some((s) => s.id === sid)) fail(`sector map names unknown sector ${sid}`);
  list.forEach((id) => { if (!byId.has(id)) fail(`sector ${sid} names unknown pack ${id}`); });
});
trig.core.concat(Object.values(trig.frequency)).forEach((id) => { if (!byId.has(id)) fail(`core/frequency names unknown pack ${id}`); });

const reachable = new Set([...trig.core, ...Object.values(trig.frequency), ...Object.values(trig.sectors).flat()]);
packs.forEach((p) => { if (Object.keys(p.tr).length) reachable.add(p.id); });
packs.forEach((p) => { if (!reachable.has(p.id)) fail(`pack ${p.id} can only be found by search`); });

if (errors.length) {
  console.error(errors.join("\n"));
  console.error(`\n${errors.length} problem(s); nothing written.`);
  process.exit(1);
}

const catalogue = {
  v: VERSION, base: seed.catalog_version,
  vm: Object.fromEntries(Object.entries(seed.verification_methods).map(([k, v]) => [k, {l: v.label, h: v.help}])),
  src: sources, core: trig.core, freq: trig.frequency,
  packs: packs.map(({id, t, k, al, sr, ref, it, tr, nw}) => ({id, t, k, al, sr, ref, it, tr, nw})),
  sec: trig.sectors,
};
const text = JSON.stringify(catalogue);
const sha = crypto.createHash("sha256").update(text).digest("hex");
const target = path.join(root, OUT);

const counts = `packs=${packs.length} (new ${packs.filter((p) => p.nw).length}) items=${packs.reduce((n, p) => n + p.it.length, 0)} ` +
  `(new ${packs.filter((p) => p.nw).reduce((n, p) => n + p.it.length, 0)}) sectors=${Object.keys(trig.sectors).length} bytes=${text.length}`;
if (process.argv.includes("--check")) {
  const current = fs.existsSync(target) ? fs.readFileSync(target, "utf8") : "";
  if (current !== text) { console.error(`${OUT} is stale; run node scripts/isg/checklist_wizard/build.mjs`); process.exit(1); }
  console.log(`${OUT} up to date · ${counts} · sha256=${sha}`);
} else {
  fs.writeFileSync(target, text);
  console.log(`wrote ${OUT} · ${VERSION} · ${counts} · sha256=${sha}`);
}
