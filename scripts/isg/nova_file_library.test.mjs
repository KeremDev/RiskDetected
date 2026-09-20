import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(join(ROOT,path),'utf8');
const migration=read('supabase/migrations/20260915010000_isg_file_library.sql');
const model=read('App/DesignSystem/ISG/NovaFileLibrary.swift');
const screen=read('App/DesignSystem/ISG/NovaFileLibraryScreens.swift');
const sheets=read('App/DesignSystem/ISG/NovaFileLibrarySheets.swift');
const service=read('App/Services/Company/NovaFileLibraryService.swift');
const adapter=read('App/Services/Company/NovaFileLibraryLiveAdapter.swift');
const gate=read('App/Views/Components/NovaPilotFileGate.swift');
const company=read('App/Views/Components/NovaCompanyManagementGate.swift');
const main=read('App/Views/Components/NovaPilotMainGate.swift');
const navigation=read('App/DesignSystem/ISG/NovaNavigation.swift');
const catalogue=JSON.parse(read('App/Localization/Localizable.xcstrings'));
// The ban is on what the product says and does, not on the word appearing in a
// comment that explains why it is banned.
const code=source=>source.split('\n').filter(line=>!/^\s*\/\//.test(line)).join('\n');

test('the archive design layer stays free of the SDK and of legacy writes',()=>{
  for(const [path,source] of [['NovaFileLibrary.swift',model],
    ['NovaFileLibraryScreens.swift',screen],['NovaFileLibrarySheets.swift',sheets]]){
    assert.doesNotMatch(source,/import (Supabase|RevenueCat)|https?:|access_token|refresh_token|UserDefaults|Keychain/,path);
    assert.doesNotMatch(source,/AnalysisService|SupabaseService|PDFReportService/,path);
  }
  // The SDK lives in the adapter alone.
  assert.match(adapter,/^import Supabase$/m);
});

test('the client reads the state and never works one out for itself',()=>{
  assert.match(service,/state: NovaFileState\(rawValue: row\.state\) \?\? \.scanFailed/);
  // Nothing on this side decides that a file is filed.
  for(const [path,source] of [['model',model],['screen',screen],['sheets',sheets],['service',service]]){
    assert.doesNotMatch(code(source),/state\s*=\s*\.promoted/,path);
    assert.doesNotMatch(code(source),/downloadPath\s*=\s*"/,path);
  }
  // An unknown word is not quietly downgraded to the calmest answer: it reads
  // as an upload that did not finish, so the expert looks at it.
  assert.match(service,/\?\? \.scanFailed/);
});

test('the archive never claims a malware scan it did not run',()=>{
  // The flag is the server's, and the popup says so out loud when it is false.
  assert.match(model,/var malwareScanned: Bool = false/);
  assert.match(sheets,/if !row\.malwareScanned \{/);
  assert.match(sheets,/localizable\.nova\.file\.assurance\.no\.malware/);
  assert.match(screen,/localizable\.nova\.file\.hint\b/);
  assert.match(sheets,/if !assurance\.malwareScanningAvailable/);
  assert.match(sheets,/virüs taraması yapılmaz/);
  // Nothing on this side sets the flag or invents an assurance level.
  for(const [path,source] of [['model',model],['screen',screen],['sheets',sheets],['service',service]]){
    assert.doesNotMatch(code(source),/malwareScanned\s*=\s*true/,path);
    assert.doesNotMatch(code(source),/assurance\s*=\s*"malware_scan"/,path);
  }
  // The scanned wording exists but is only reachable when the server says so.
  assert.match(screen,/assurance\.malwareScanningAvailable\n?\s*\?/);
});

test('the archive never states compliance about a company or a person',()=>{
  for(const source of [model,screen,sheets,service])
    assert.doesNotMatch(code(source),/uygunluk|compliance|compliant/i);
  assert.match(code(migration),/'compliance_verdict',NULL/);
});

test('the upload is three separate steps and none of them is skipped',()=>{
  const file=service.slice(service.indexOf('func file('),service.indexOf('func rename('));
  // Open the intent, put the bytes, then ask the worker. In that order.
  assert.ok(file.indexOf('open_upload')<file.indexOf('try await upload('),'open before put');
  assert.ok(file.indexOf('try await upload(')<file.indexOf('try await inspect('),'put before inspect');
  // What comes back is read from the server, not assembled on this side.
  assert.match(file,/let filed = try await detail\(identity, entry: opened\.id\)/);
  assert.match(file,/return filed/);
  // The bucket has no update policy, so a replayed open never puts again.
  assert.match(file,/guard let bucket = opened\.uploadBucket, let path = opened\.uploadPath else \{/);
  assert.match(adapter,/upsert: false/);
});

test('the device fingerprints the bytes it is about to send',()=>{
  assert.match(sheets,/SHA256\.hash\(data: data\)\.map \{ String\(format: "%02x", \$0\) \}\.joined\(\)/);
  assert.match(model,/sha256\.count == 64/);
  // The server re-computes it and refuses bytes that disagree.
  assert.match(code(migration),/\(p_payload->>'sha256'\) !~ '\^\[0-9a-f\]\{64\}\$'/);
});

test('the device never reports a verdict and the service has no way to',()=>{
  for(const [path,source] of [['service',service],['gate',gate],['adapter',adapter],['sheets',sheets]]){
    assert.doesNotMatch(code(source),/isg_file_inspection_v1|record_scan_result|promote_clean_upload/,path);
    assert.doesNotMatch(code(source),/"verdict"|verdict:/,path);
  }
  // The worker is asked to look; it is never told what it will find.
  assert.match(adapter,/let entry_id: String/);
  assert.doesNotMatch(adapter,/service_role|SERVICE_ROLE/);
});

test('an inspection that could not run leaves the file where it really is',()=>{
  assert.match(adapter,/throw NovaFileFailure\.inspectionUnavailable/);
  assert.match(screen,/case \.inspectionUnavailable:/);
  // The sentence says the file was not archived, not that something went wrong.
  const value=catalogue.strings['localizable.nova.file.failure.inspection'];
  assert.match(value.localizations.tr.stringUnit.value,/arşive alınmadı/);
  assert.match(value.localizations.en.stringUnit.value,/not archived/);
});

test('a counter and the filter it carries are the same set of rows',()=>{
  // The four groups cover every state exactly once.
  const groups=[...model.matchAll(/case \.(filed|working|rejected|unchecked): return \[([^\]]*)\]/g)]
    .map(match=>match[2].split(',').map(value=>value.trim()));
  const states=groups.flat();
  assert.equal(states.length,new Set(states).size,'a state is counted twice');
  assert.equal(states.length,8,'a state is not counted at all');
  // The same word is what the page sends, and the server accepts it.
  assert.match(screen,/state: group\?\.rawValue/);
  assert.match(code(migration),/'filed','working','unchecked'\) THEN/);
  assert.match(code(migration),/OR \(p_state='working' AND entry_state IN \('pending','uploaded','scanning','clean'\)\)/);
});

test('the company page reads the archive from the same tally the archive uses',()=>{
  assert.match(company,/NovaFileSectionStrip\(counts: files\?\.counts\(forCategories: categories\)/);
  // One call for every heading, not one call per heading.
  assert.match(company,/service\.library\(documentIdentity,\n?\s*query: \.init\(company: scope\.companyID, limit: 1\)\)/);
  // The heading-to-category mapping is the server's, not a second list here.
  assert.match(model,/catalogue\.filter \{ \$0\.section == section\.rawValue \}\.map\(\\\.code\)/);
  assert.doesNotMatch(code(model),/case \.risk: return \["risk_assessment"\]/);
});

test('Diğer Dosyalar is reachable from the menu and from the company page',()=>{
  assert.match(main,/case \.documents:\n\s+if let workspaceStore \{ workspaceDomain\(workspaceStore, \.files\) \} else \{ files\(\) \}/);
  assert.match(main,/NovaPilotFileGate\(identity: identity, canWrite: ready/);
  // Its position in the drawer list belongs to whichever slice added the
  // newest entry, so only its presence is pinned here.
  assert.match(navigation,/sharedDestinations:[\s\S]*\.documents/);
  // Company detail opens the relevant file heading directly in add mode; the
  // removed global button must not return and bypass that context.
  assert.match(company,/startInAddMode: fileSectionAdding/);
  assert.match(company,/fileSectionAdding = true; fileSection = \.accidents/);
  assert.doesNotMatch(company,/fallback: "Dosya Ekle"\), symbol: "folder\.badge\.plus", isEnabled: canWrite/);
  assert.match(company,/initialCompany: scope\.companyID,/);
});

test('every word the screens use is in the shipping catalogue in both languages',()=>{
  const keys=new Set();
  for(const source of [model,screen,sheets,gate])
    for(const match of source.matchAll(/RDLocalization\.string\("(localizable\.nova\.file[^"]*)"/g))
      keys.add(match[1]);
  assert.ok(keys.size>=60,`only ${keys.size} archive keys are referenced`);
  for(const key of keys){
    const entry=catalogue.strings[key];
    assert.ok(entry,`${key} is missing from the catalogue`);
    for(const language of ['tr','en'])
      assert.equal(entry.localizations[language]?.stringUnit?.state,'translated',`${key} ${language}`);
  }
});

test('the filters are two choosers, not strips that run off the screen',()=>{
  // One panel open at a time, opened under the button that was tapped.
  assert.match(screen,/@State private var openChooser: String\?/);
  assert.match(screen,/isOpen: openChooser == "state"/);
  assert.match(screen,/isOpen: openChooser == "category"/);
  assert.match(screen,/if openChooser == "state" \{/);
  assert.match(screen,/if openChooser == "category" \{/);
  // The horizontal chip strips they replaced are gone from every archive screen.
  for(const [path,source] of [['screen',screen],['sheets',sheets]])
    assert.doesNotMatch(code(source),/NovaAnalysisFilterChip/,path);
  // Each option still carries the count it filters to.
  assert.match(screen,/count: count\(value\)/);
});

test('a heading is asked for rather than defaulted to whatever comes first',()=>{
  // Picking a file opens the chooser instead of silently filing the document
  // under the first entry in the catalogue.
  assert.match(sheets,/if draft\.category == nil \{ choosingCategory = true \}/);
  assert.doesNotMatch(code(sheets),/draft\.category = categories\.first/);
  // And the form stays unsendable until the expert has chosen one.
  assert.match(model,/guard category != nil, !title\.trimmingCharacters\(in: \.whitespaces\)\.isEmpty else \{ return false \}/);
});

test('the picker offers what the server declared, not a list of its own',()=>{
  assert.match(screen,/static func contentTypes\(_ accepts: \[NovaFileAcceptance\]\) -> \[UTType\]/);
  assert.match(sheets,/allowedContentTypes: NovaFileScreenWords\.contentTypes\(accepts\)/);
  assert.match(sheets,/guard allExtensions\.contains\(fileExtension\) else \{/);
  // Compact details still show the server-declared formats and actual upload limit.
  assert.match(sheets,/allExtensions\.joined/);
  assert.match(sheets,/NovaFileWords\.size\(maxBytes\)/);
});
