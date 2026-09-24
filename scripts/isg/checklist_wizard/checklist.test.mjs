// Checklist wizard: catalogue, suggestions, save plan and documents, run against the bundled V6 scripts.
//   node --test scripts/isg/checklist_wizard/checklist.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {createRequire} from "node:module";

const root = path.resolve(import.meta.dirname, "../../..");
const assets = path.join(root, "App/WizardAssets/isg_wizard_v6");
const require = createRequire(import.meta.url);
for (const name of ["rd-xlsx", "rd-report", "rd-engine", "rd-emergency", "rd-bridge", "rd-checklist"]) require(path.join(assets, name + ".js"));
const B = globalThis.RDBridge;
const dataText = fs.readFileSync(path.join(assets, "rd-data.json"), "utf8");
const checklistText = fs.readFileSync(path.join(assets, "rd-checklist.json"), "utf8");
const CK = JSON.parse(checklistText);
const seed = JSON.parse(fs.readFileSync(path.join(root, "docs/isg/checklists/ISG_ADASI_CHECKLIST_SEED.json"), "utf8"));
const info = B.init(dataText, checklistText);

const start = () => B.start({name: "Deneme Lojistik A.Ş.", date: "24.09.2026", mode: "checklist"});
const ids = (v) => v.checklist.topics.map((x) => x.id);
const topic = (v, id) => v.checklist.topics.find((x) => x.id === id);
function profile(actions) {
  let v = start();
  for (const a of actions) v = B.act(a);
  return v;
}
const warehouse = [{type: "sector", id: "S127"}, {type: "pick", kind: "equipment", id: "E041"}, {type: "pick", kind: "equipment", id: "E051"}];

test("init reports both catalogues", () => {
  assert.equal(info.checklistVersion, CK.v);
  assert.equal(info.checklistPacks, 156);
  assert.ok(info.risks > 1000);
});

test("risk and emergency modes stay untouched by the wrapper", () => {
  const risk = B.start({name: "", date: "24.09.2026"});
  assert.equal(risk.mode, "risk");
  assert.ok(risk.steps.includes("mgmt") && risk.steps.includes("method"));
  assert.equal(risk.checklist, undefined);
  assert.equal(B.act({type: "sector", id: "S127"}).checklist, undefined);
  assert.ok(Array.isArray(B.result().rows));
  const em = B.start({name: "", date: "24.09.2026", mode: "emergency"});
  assert.equal(em.mode, "emergency");
  assert.ok(em.emergency && em.emergency.cards.length > 0);
  assert.deepEqual(B.topics("forklift"), []);
});

test("checklist steps replace the risk method pages", () => {
  const v = start();
  assert.equal(v.mode, "checklist");
  assert.deepEqual(v.steps.slice(-4), ["purpose", "topics", "items", "summary"]);
  for (const s of ["mgmt", "method", "cols"]) assert.ok(!v.steps.includes(s));
  assert.ok(v.checklist.texts["title"]);
});

test("a warehouse with a forklift and racks gets its own topics with reasons", () => {
  const v = profile(warehouse);
  for (const id of ["WAREHOUSE", "FORK", "RACK", "TRAFFIC", "FIRE", "EVAC", "FIRST", "ELEC"]) assert.ok(ids(v).includes(id), id);
  assert.ok(topic(v, "FORK").reasons.includes("Denge ağırlıklı forklift"));
  assert.ok(topic(v, "WAREHOUSE").reasons.includes("Genel depo"));
  assert.ok(topic(v, "FIRE").core);
  for (const id of ["HOT", "KITCHENHOT", "LOTO", "GUARD", "CHEMSTORE"]) assert.ok(!ids(v).includes(id), id);
});

test("a question shared by two topics is saved once", () => {
  profile([{type: "sector", id: "S077"}, {type: "ckTopic", id: "LAUNDRY"}]);
  const r = B.result();
  const codes = r.sections.flatMap((s) => s.items.map((i) => i.code)).filter(Boolean);
  assert.ok(codes.includes("ACI-LAUNDRY-04"));
  assert.equal(new Set(codes).size, codes.length);
  assert.equal(r.lists[0].items.length, r.total);
});

test("an office gets office topics and no machinery", () => {
  const v = profile([{type: "sector", id: "S172"}]);
  for (const id of ["OFFICE", "DESK"]) assert.ok(ids(v).includes(id), id);
  for (const id of ["FORK", "GUARD", "LOTO", "HOT", "PRESS"]) assert.ok(!ids(v).includes(id), id);
});

test("purpose narrows the kinds that are offered", () => {
  let v = profile(warehouse.concat([{type: "ckPurpose", id: "preuse"}]));
  assert.ok(v.checklist.topics.length > 0);
  assert.ok(v.checklist.topics.every((x) => x.kind === "equipment"));
  assert.ok(ids(v).includes("FORK") && ids(v).includes("RACK"));
  v = profile([{type: "sector", id: "S054"}, {type: "pick", kind: "tasks", id: "T113"}, {type: "ckPurpose", id: "task"}]);
  assert.ok(v.checklist.topics.every((x) => x.kind === "activity"));
  assert.ok(ids(v).includes("HOT") && ids(v).includes("PERMIT"));
  assert.deepEqual(B.topics("forklift").filter((x) => x.kind !== "activity"), []);
});

test("a frequency adds the general round first", () => {
  const v = profile(warehouse.concat([{type: "ckFreq", id: "weekly"}]));
  assert.equal(v.checklist.topics[0].id, "WEEKLY");
  assert.match(v.checklist.title, /Haftalık/);
});

test("topics can be turned off, searched and added by hand", () => {
  let v = profile(warehouse.concat([{type: "ckTopic", id: "TRAFFIC"}]));
  assert.equal(topic(v, "TRAFFIC").selected, false);
  assert.ok(!v.checklist.groups.some((g) => g.id === "TRAFFIC"));
  const hits = B.topics("iskele");
  assert.ok(hits.some((x) => x.id === "SCAFFOLD"));
  v = B.act({type: "ckTopic", id: "SCAFFOLD"});
  assert.ok(topic(v, "SCAFFOLD").selected && !topic(v, "SCAFFOLD").suggested);
  v = B.act({type: "ckTopic", id: "SCAFFOLD"});
  assert.ok(!ids(v).includes("SCAFFOLD"));
});

test("items can be removed one by one or per topic, and own questions are kept", () => {
  let v = profile(warehouse);
  const before = v.checklist.itemCount;
  v = B.act({type: "ckItem", id: "FORK:0"});
  assert.equal(v.checklist.itemCount, before - 1);
  v = B.act({type: "ckItems", id: "RACK"});
  assert.equal(v.checklist.groups.find((g) => g.id === "RACK").on, 0);
  v = B.act({type: "ckItems", id: "RACK"});
  assert.equal(v.checklist.groups.find((g) => g.id === "RACK").on, 10);
  v = B.act({type: "ckCustom", op: "add", pack: "FORK", text: "Forklift anahtarları vardiya sonunda teslim ediliyor mu?"});
  v = B.act({type: "ckCustom", op: "add", pack: "", text: "Depo girişindeki kantar alanı işaretli mi?"});
  v = B.act({type: "ckCustom", op: "add", pack: "", text: "   "});
  assert.equal(v.checklist.itemCount, before + 1);
  const r = B.result();
  const own = r.sections.find((s) => s.id === "OWN");
  assert.equal(own.items.length, 1);
  assert.ok(r.sections.find((s) => s.id === "FORK").items.some((i) => i.own));
  assert.equal(r.own, 2);
});

test("the save plan copies server items by reference and writes the rest as own questions", () => {
  let v = profile(warehouse.concat([{type: "ckTopic", id: "FORK"}, {type: "ckTopic", id: "FORK"}, {type: "ckTopic", id: "BATTERY"}]));
  assert.ok(topic(v, "BATTERY").isNew);
  const r = B.result();
  assert.equal(r.lists.length, 1);
  const list = r.lists[0];
  assert.equal(list.items.length, r.total);
  assert.equal(list.title, "Deneme Lojistik A.Ş. — İSG saha kontrol listesi");
  const fork = list.items.filter((i) => i.section === "Forklift kullanım öncesi kontrolü");
  assert.deepEqual(fork[0].ref, {template: "catalog_dpo_02", item: "dpo_02_01"});
  assert.ok(list.items.filter((i) => i.section === "Akü şarj alanı, UPS ve lityum batarya").every((i) => i.ref === null));
  assert.equal(r.fromCatalog + r.newCatalog + r.own, r.total);
  for (const i of list.items) assert.ok(i.text.length <= 500);
  v = B.act({type: "ckLayout", id: "perTopic"});
  const split = B.result();
  assert.equal(split.lists.length, split.sections.length);
  assert.ok(split.lists.every((l) => l.title.length <= 190 && l.items.length > 0));
});

test("every catalogue reference points at a real product template item", () => {
  const byRuntime = new Map();
  seed.templates.forEach((t) => t.items.forEach((i) => byRuntime.set("catalog_" + t.template_code.toLowerCase().replace(/-/g, "_") + "/" +
    i.item_code.toLowerCase().replace(/-/g, "_"), i.text_tr)));
  let refs = 0;
  CK.packs.forEach((p) => p.it.forEach(([, text, , db]) => {
    if (!db) { assert.equal(p.nw, 1, p.id); return; }
    refs++;
    assert.equal(byRuntime.get(p.ref + "/" + db), text, p.id + " " + db);
  }));
  assert.equal(refs, 1170);
});

test("every V6 sector gets at least one topic for a site audit", () => {
  const D = JSON.parse(dataText);
  const empty = [];
  for (const s of D.sectors) {
    const v = profile([{type: "sector", id: s.id}]);
    const own = v.checklist.topics.filter((x) => !x.core);
    if (!own.length) empty.push(s.id + " " + s.n);
  }
  assert.deepEqual(empty, []);
});

test("sector specific extensions reach their sectors", () => {
  const cases = {S139: "FUEL", S248: "ADR", S182: "DRILLRIG", S223: "SALON", S232: "DATACENTER", S048: "FOUNDRY", S201: "LINEWORK", S181: "MOTO"};
  for (const [sector, pack] of Object.entries(cases)) assert.ok(ids(profile([{type: "sector", id: sector}])).includes(pack), sector + " → " + pack);
});

test("Word, Excel and PDF outputs are built from the same list", () => {
  profile(warehouse.concat([{type: "ckFreq", id: "monthly"}]));
  for (const format of ["docx", "xlsx"]) {
    const f = B.file(format);
    const bytes = Buffer.from(f.base64, "base64");
    assert.equal(bytes.subarray(0, 2).toString(), "PK", format);
    assert.match(f.name, new RegExp("^Deneme_Lojistik_A_Ş_Kontrol_Listesi_24-09-2026\\." + format + "$"));
    const text = bytes.toString("latin1");
    assert.ok(text.includes(format === "docx" ? "word/document.xml" : "xl/worksheets/sheet1.xml"));
  }
  const blocks = B.blocks();
  assert.equal(blocks[0].type, "title");
  assert.match(blocks[0].text, /Aylık İSG saha kontrol listesi/);
  assert.ok(blocks.some((b) => b.type === "heading" && /Forklift/.test(b.text)));
  B.act({type: "ckLayout", id: "perTopic"});
  assert.equal(Buffer.from(B.file("docx").base64, "base64").subarray(0, 2).toString(), "PK");
});

test("state survives a restore", () => {
  profile(warehouse.concat([{type: "ckPurpose", id: "preuse"}, {type: "ckTitle", value: "Forklift ve raf kontrolü"}]));
  const saved = B.state();
  B.start({name: "", date: "", mode: "checklist"});
  const v = B.restore(saved);
  assert.equal(v.checklist.purpose, "preuse");
  assert.equal(v.checklist.title, "Forklift ve raf kontrolü");
  assert.ok(ids(v).includes("FORK"));
});

test("a checklist session without its catalogue fails clearly", () => {
  B.init(dataText);
  assert.throws(() => B.start({mode: "checklist"}), /Kontrol listesi kataloğu/);
  assert.equal(B.start({name: "", date: ""}).mode, "risk");
  B.init(dataText, checklistText);
});
