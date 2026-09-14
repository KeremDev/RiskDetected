import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(join(ROOT,path),'utf8');
const migration=read('supabase/migrations/20260915030000_isg_equipment_checks.sql');
const periods=read('supabase/migrations/20260915050000_isg_equipment_periods.sql');
const model=read('App/DesignSystem/ISG/NovaEquipmentChecks.swift');
const screen=read('App/DesignSystem/ISG/NovaEquipmentCheckScreens.swift');
const sheets=read('App/DesignSystem/ISG/NovaEquipmentCheckSheets.swift');
const service=read('App/Services/Company/NovaEquipmentCheckService.swift');
const adapter=read('App/Services/Company/NovaEquipmentCheckLiveAdapter.swift');
const gate=read('App/Views/Components/NovaPilotEquipmentGate.swift');
const company=read('App/Views/Components/NovaCompanyManagementGate.swift');
const main=read('App/Views/Components/NovaPilotMainGate.swift');
const catalogue=JSON.parse(read('App/Localization/Localizable.xcstrings'));
const code=source=>source.split('\n').filter(line=>!/^\s*\/\//.test(line)).join('\n');

test('the module design layer stays free of the SDK and of legacy writes',()=>{
  for(const [path,source] of [['NovaEquipmentChecks.swift',model],
    ['NovaEquipmentCheckScreens.swift',screen],['NovaEquipmentCheckSheets.swift',sheets]]){
    assert.doesNotMatch(source,/import (Supabase|RevenueCat)|https?:|access_token|refresh_token|UserDefaults|Keychain/,path);
    assert.doesNotMatch(source,/AnalysisService|SupabaseService|PDFReportService/,path);
  }
  assert.match(adapter,/^import Supabase$/m);
});

test('the client reads the state and never works one out for itself',()=>{
  assert.match(service,/state: NovaEquipmentState\(rawValue: row\.state\) \?\? \.neverInspected/);
  // Nothing on this side compares a date to today or produces a due date.
  for(const [path,source] of [['model',model],['screen',screen],['sheets',sheets],['service',service]]){
    assert.doesNotMatch(code(source),/nextDueOn\s*=\s*[^\n]*(Date\(\)|addingTimeInterval|byAdding)/,path);
    assert.doesNotMatch(code(source),/state\s*=\s*\.(valid|overdue|dueSoon)/,path);
  }
  // An unknown word reads as untracked, never as the calmest answer.
  assert.match(service,/\?\? \.neverInspected/);
});

test('a default period is never dressed up as a confirmed one',()=>{
  // The expert cannot pick the product's own label from the source list.
  assert.match(model,/static var choosable: \[NovaEquipmentPeriodSource\] \{ \[\.manufacturer, \.ruleVersion, \.unapprovedFixture\] \}/);
  assert.match(sheets,/ForEach\(NovaEquipmentPeriodSource\.choosable\)/);
  // A default says it is one, in its own words rather than the expert's.
  assert.match(sheets,/localizable\.nova\.equipment\.period\.default\.review/);
  const label=catalogue.strings['localizable.nova.equipment.source.default'];
  assert.match(label.localizations.tr.stringUnit.value,/ürün varsayılanı/);
  // And the flag on it is the server's, not something this side decides.
  assert.match(model,/self == \.unapprovedFixture \|\| self == \.regulationDefault/);
  assert.match(code(periods),/CHECK\(period_source<>'regulation_default' OR needs_review\)/);
});

test('the next date is filled from the period and stays the expert’s to change',()=>{
  // The form prints the date the server would produce, as a default.
  assert.match(sheets,/private func fillNextDue\(\)/);
  assert.match(sheets,/localizable\.nova\.equipment\.due\.auto/);
  assert.match(sheets,/\.onChange\(of: draft\.performedOn\) \{ _ in fillNextDue\(\) \}/);
  // What the saved date MEANS is still the server's call, and the popup shows
  // that answer rather than assuming the field it came from.
  assert.match(service,/dueSource: row\.due_source\.flatMap\(NovaEquipmentDueSource\.init\(rawValue:\)\)/);
  assert.match(sheets,/detail: NovaEquipmentWords\.due\(row\.dueSource\)/);
  assert.match(code(periods),/WHEN chosen IS NULL OR chosen=derived THEN 'period' ELSE 'expert' END/);
  // A failed check has no next date to fill.
  assert.match(sheets,/if draft\.result == "fail" \{/);
});

test('the İSG-KATİP mark is optional and never claims a verification',()=>{
  assert.match(model,/var katipDeclared = false/);
  assert.match(sheets,/localizable\.nova\.equipment\.katip\.mark/);
  assert.match(sheets,/localizable\.nova\.equipment\.katip\.hint/);
  // The sentence beside it says what the product does not do.
  const hint=catalogue.strings['localizable.nova.equipment.katip.hint'];
  assert.match(hint.localizations.tr.stringUnit.value,/sorgulama veya işlem yapmaz/);
  assert.match(hint.localizations.en.stringUnit.value,/no query or transaction/);
  // Nothing on this side can raise the verification flag, and nothing reaches
  // the official system.
  for(const [path,source] of [['model',model],['screen',screen],['sheets',sheets],['service',service],
    ['adapter',adapter],['gate',gate]]){
    assert.doesNotMatch(code(source),/katipOfficialVerification\s*=\s*true/,path);
    assert.doesNotMatch(code(source),/isgkatip|csgb\.gov/i,path);
  }
  assert.match(code(periods),/CHECK\(NOT katip_official_verification\)/);
});

test('no period is ever shown without where it came from',()=>{
  // The one string that prints a period also prints its source.
  const value=catalogue.strings['localizable.nova.equipment.period.value'];
  assert.match(value.localizations.tr.stringUnit.value,/%1\$d ay · %2\$@/);
  assert.match(value.localizations.en.stringUnit.value,/%1\$d months · %2\$@/);
  // Every place a period is printed uses that string.
  const printed=[...sheets.matchAll(/localizable\.nova\.equipment\.period\.value/g)].length;
  assert.ok(printed>=2,`a period is printed ${printed} times through the paired string`);
  // And an unapproved period is called the expert's own decision, not a rule.
  const expert=catalogue.strings['localizable.nova.equipment.source.expert'];
  assert.equal(expert.localizations.tr.stringUnit.value,'Uzman tarafından belirlenen');
  assert.match(sheets,/localizable\.nova\.equipment\.period\.review/);
});

test('a missing date is shown as missing, never as a blank or a guess',()=>{
  assert.match(screen,/localizable\.nova\.equipment\.no\.due/);
  assert.match(sheets,/row\.nextDueOn \?\? RDLocalization\.string\("localizable\.nova\.equipment\.no\.due"/);
  // And the row always says why it says what it says.
  assert.match(model,/static func explain\(_ item: NovaEquipmentItem\) -> String/);
  assert.match(sheets,/NovaText\(text: NovaEquipmentWords\.explain\(row\), style: \.meta\)/);
  for(const state of ['never','unknown','failed','overdue','due','valid','late.rule'])
    assert.match(model,new RegExp(`localizable\\.nova\\.equipment\\.explain\\.${state.replace('.','\\.')}`),state);
});

test('a counter and the filter it carries are the same set of rows',()=>{
  const groups=[...model.matchAll(/case \.(overdue|failed|untracked|dueSoon|current): return \[([^\]]*)\]/g)]
    .map(match=>match[2].split(',').map(value=>value.trim()));
  const states=groups.flat();
  assert.equal(states.length,new Set(states).size,'a state is counted twice');
  assert.equal(states.length,6,'a state is not counted at all');
  assert.match(screen,/state: group\?\.rawValue/);
  // The server accepts the same five words.
  assert.match(code(migration),/'current','untracked'\) THEN/);
  assert.match(code(migration),/private_isg\.equipment_check_group\(entry_state\)=p_state/);
});

test('the filters are two choosers, not strips that run off the screen',()=>{
  assert.match(screen,/@State private var openChooser: String\?/);
  assert.match(screen,/isOpen: openChooser == "state"/);
  assert.match(screen,/isOpen: openChooser == "type"/);
  for(const [path,source] of [['screen',screen],['sheets',sheets]])
    assert.doesNotMatch(code(source),/NovaAnalysisFilterChip/,path);
});

test('the inspection points at a filed report instead of carrying a copy',()=>{
  // Only files the archive really cleared are offered.
  assert.match(gate,/state: NovaFileState\.promoted\.rawValue/);
  assert.match(gate,/category: "inspection_report"/);
  assert.match(gate,/\.filter\(\\\.canDownload\)/);
  // The server refuses an asset that was never cleared, so this cannot lie.
  assert.match(read('supabase/migrations/20260913230000_isg_module_core.sql'),
    /WHERE asset_id=p_asset AND scan_status='clean' FOR SHARE;/);
});

test('the company page reads the module from the same tally the module uses',()=>{
  assert.match(company,/NovaEquipmentSectionStrip\(counts: equipment\?\.counts \?\? \[:\]/);
  assert.match(company,/NovaEquipmentCheckService\.live\(\)\.board\(documentIdentity,\n?\s*query: \.init\(company: scope\.companyID, limit: 1\)\)/);
  assert.match(company,/NovaPilotEquipmentGate\(identity: documentIdentity, canWrite: canWrite,/);
});

test('Periyodik Kontroller is reachable from the menu and the home summary',()=>{
  assert.match(main,/case \.periodicChecks:\n\s*equipment/);
  assert.match(main,/NovaPilotEquipmentGate\(identity: identity, canWrite: controller\.canWrite/);
  assert.match(main,/available: \[[^\]]*\.periodicChecks[,\]]/);
  // The home card counts records and lands on this page; it states no verdict.
  assert.match(main,/id: "equipment", value: equipmentBoard\.map \{ String\(\$0\.needsAttention\) \} \?\? "—"/);
  assert.match(main,/destination: \.periodicChecks/);
  assert.match(model,/count\(NovaEquipmentState\.overdue\) \+ count\(NovaEquipmentState\.failed\)/);
});

test('the warning window is the server’s and is never invented here',()=>{
  assert.match(service,/noticeDays: envelope\.notice_days/);
  assert.match(screen,/@State private var noticeDays = 30/);
  assert.match(screen,/noticeDays = answer\.noticeDays/);
  // The sentence that states it reads the value rather than hard-coding one.
  assert.match(screen,/String\(format: RDLocalization\.string\("localizable\.nova\.equipment\.hint"[\s\S]{0,400}?noticeDays\)/);
  assert.match(code(migration),/CREATE FUNCTION private_isg\.equipment_notice_days\(\) RETURNS integer/);
});

test('every word the screens use is in the shipping catalogue in both languages',()=>{
  const keys=new Set();
  for(const source of [model,screen,sheets,gate])
    for(const match of source.matchAll(/RDLocalization\.string\("(localizable\.nova\.equipment[^"]*)"/g))
      keys.add(match[1]);
  assert.ok(keys.size>=80,`only ${keys.size} equipment keys are referenced`);
  for(const key of keys){
    const entry=catalogue.strings[key];
    assert.ok(entry,`${key} is missing from the catalogue`);
    for(const language of ['tr','en'])
      assert.equal(entry.localizations[language]?.stringUnit?.state,'translated',`${key} ${language}`);
  }
});

test('the module never claims to hold a health record',()=>{
  for(const source of [model,screen,sheets,service])
    assert.doesNotMatch(code(source),/health|saglik|sağlık|muayene/i);
  assert.match(code(migration),/'health_records_tracked',false/);
});
