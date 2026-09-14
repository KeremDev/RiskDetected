import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, rmSync, readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {ROOT} from './lib.mjs';

const read = path => readFileSync(join(ROOT, path), 'utf8');
const migration = read('supabase/migrations/20260914190000_isg_nonconformity_detail.sql');
const model = read('App/DesignSystem/ISG/NovaNonconformity.swift');

test('the sector matcher keeps a company suggestion honest', {skip: process.platform !== 'darwin'}, t => {
  const directory = mkdtempSync(join(tmpdir(), 'isg-intake-check-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const binary = join(directory, 'check');
  const compiled = spawnSync('swiftc', ['-parse-as-library',
    'App/DesignSystem/ISG/NovaAnalysisIntake.swift', 'scripts/isg/NovaAnalysisIntakeCheck.swift', '-o', binary],
    {cwd: ROOT, encoding: 'utf8', timeout: 120000});
  assert.equal(compiled.status, 0, compiled.stderr);
  const result = spawnSync(binary, [], {encoding: 'utf8', timeout: 10000});
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /31 analysis intake checks PASS/);
});

test('the check exercises the sectors the product actually ships', () => {
  const source = read('App/Models/AnalysisSector.swift');
  const block = source.slice(source.indexOf('enum AnalysisSectorID'), source.indexOf('var id: String'));
  const cases = [...block.matchAll(/case ([a-zA-Z]+)(?: = "([a-z_]+)")?/g)]
    .map(match => match[2] ?? match[1]);
  const check = read('scripts/isg/NovaAnalysisIntakeCheck.swift');
  const covered = [...check.matchAll(/\.init\(id: "([a-z_]+)"/g)].map(match => match[1]);
  assert.deepEqual([...cases].sort(), [...new Set(covered)].sort().filter(id => id !== 'site_services'));
});

test('the published scales and bands are one set of numbers, not two', () => {
  // Client-side scoring only ever previews the rule the server enforces, so
  // the two must carry the same numbers. A drift here is a wrong band on screen.
  for (const [swift, sql] of [
    ['static let probabilityScale: [Double] = [0.2, 0.5, 1, 3, 6, 10]', 'fk_probability IN (0.2,0.5,1,3,6,10)'],
    ['static let frequencyScale: [Double] = [0.5, 1, 2, 3, 6, 10]', 'fk_frequency IN (0.5,1,2,3,6,10)'],
    ['static let severityScale: [Double] = [1, 3, 7, 15, 40, 100]', 'fk_severity IN (1,3,7,15,40,100)'],
  ]) {
    assert.ok(model.includes(swift), `swift scale missing: ${swift}`);
    assert.ok(migration.includes(sql), `sql scale missing: ${sql}`);
  }
  assert.match(model, /m5_probability BETWEEN 1 AND 5|matrixScale: \[Int\] = \[1, 2, 3, 4, 5\]/);
  assert.match(migration, /m5_probability BETWEEN 1 AND 5/);
  assert.match(migration, /m5_severity BETWEEN 1 AND 5/);
  const swiftBands = [...model.matchAll(/if score <= (\d+) \{ return \.(low|medium|high) \}/g)]
    .map(match => `${match[1]}:${match[2]}`);
  assert.deepEqual(swiftBands, ['70:low', '200:medium', '400:high', '4:low', '9:medium', '19:high']);
  for (const bound of ['<=70 THEN', '<=200 THEN', '<=400 THEN', '<=4 THEN', '<=9 THEN', '<=19 THEN']) {
    assert.ok(migration.includes(bound), `sql band missing: ${bound}`);
  }
});

test('the client never states a score or maps an unscored item', () => {
  const service = read('App/Services/Company/NovaNonconformityService.swift');
  // A score is never a key the client sends; only the inputs the server scores.
  assert.doesNotMatch(service, /payload\["risk_score"\]|payload\["fk_score"\]|payload\["m5_score"\]/);
  // A band is sent exactly once, from the one path that has a real band to map.
  assert.equal(service.match(/payload\["risk_band"\]/g)?.length, 1);
  // Only the scored-finding path may carry a band, and only when the expert
  // has not chosen a severity.
  assert.match(service, /case \.finding:[\s\S]{0,800}?payload\["risk_band"\] = \.string\(band\)/);
  assert.match(service, /case \.expertItem:[\s\S]{0,800}?guard intent\.severity != nil else \{ throw NovaNonconformityFailure\.severityUnknown \}/);
  const expert = service.slice(service.indexOf('case .expertItem:'), service.indexOf('case .detailed:'));
  assert.doesNotMatch(expert, /risk_band/);
  // The scale values travel as text so no float rendering can miss the scale.
  assert.match(service, /payload\["fk_probability"\] = \.string\(scaleText/);
});

test('the intake leaves an unrecognised company sector to the expert', () => {
  const intake = read('App/DesignSystem/ISG/NovaAnalysisIntake.swift');
  assert.match(intake, /return matches\.count == 1 \? matches\[0\]\.id : nil/);
  const screens = read('App/DesignSystem/ISG/NovaAnalysisIntakeScreens.swift');
  // The note is shown only while the pre-selection is still the company's.
  assert.match(screens, /if draft\.sectorCameFromCompany, let name = draft\.owner\.companyName \{/);
  assert.match(screens, /localizable\.nova\.intake\.owner\.sector\.unknown/);
  // Continuing without a company is a listed answer, not a missing one.
  assert.match(screens, /localizable\.nova\.intake\.owner\.none/);
});

test('the design layer stays free of the SDK and of legacy writes', () => {
  for (const path of ['App/DesignSystem/ISG/NovaAnalysisIntake.swift',
    'App/DesignSystem/ISG/NovaAnalysisIntakeScreens.swift',
    'App/DesignSystem/ISG/NovaAnalysisDetail.swift',
    'App/DesignSystem/ISG/NovaAnalysisDetailScreens.swift',
    'App/DesignSystem/ISG/NovaAnalysisSheets.swift',
    'App/DesignSystem/ISG/NovaAnalysisListScreen.swift',
    'App/DesignSystem/ISG/NovaManualNonconformityScreen.swift',
    'App/DesignSystem/ISG/NovaNonconformityTransitions.swift',
    'App/DesignSystem/ISG/NovaNonconformityListScreen.swift',
    'App/DesignSystem/ISG/NovaNonconformityRecordScreen.swift',
    'App/DesignSystem/ISG/NovaNonconformitySheets.swift']) {
    const source = read(path);
    assert.doesNotMatch(source, /import (Supabase|RevenueCat)|https?:|access_token|refresh_token|UserDefaults|Keychain/, path);
    assert.doesNotMatch(source, /AnalysisService|SupabaseService|PDFReportService/, path);
  }
});

test('the manual flow asks every step the expert was promised', () => {
  assert.match(model, /case photo, company, hazard, scoring, legislation, responsible/);
  // Only the two steps the server refuses without are required to save.
  assert.match(model, /static let requiredSteps: \[NovaManualStep\] = \[\.company, \.hazard\]/);
  assert.match(model, /score\.isEmpty \|\| score\.isComplete/);
  const screen = read('App/DesignSystem/ISG/NovaManualNonconformityScreen.swift');
  for (const key of ['manual.step.photo', 'manual.step.company', 'manual.step.hazard', 'manual.step.scoring',
    'manual.step.legislation', 'manual.step.responsible']) {
    assert.ok(screen.includes(key), `manual step missing: ${key}`);
  }
  // The progress bar counts finished steps, never opened ones.
  assert.match(model, /var completedCount: Int \{ NovaManualStep\.allCases\.filter \{ isComplete\(\$0\) \}\.count \}/);
  assert.match(screen, /width: max\(0, proxy\.size\.width \* draft\.progress\)/);
});

test('the state machine on screen is the state machine in the database', () => {
  const core = read('supabase/migrations/20260913210000_isg_nonconformity_core.sql');
  const block = core.slice(core.indexOf("INSERT INTO private_isg.nonconformity_state_edges"),
    core.indexOf("CREATE TABLE private_isg.nonconformities"));
  const server = [...block.matchAll(/\('([a-z_]+)','([a-z_]+)',(true|false),(true|false),(true|false)\)/g)]
    .map(m => `${m[1]}>${m[2]}:${m[3]}:${m[4]}:${m[5]}`);
  const swift = read('App/DesignSystem/ISG/NovaNonconformityTransitions.swift');
  const client = [...swift.matchAll(
    /\.init\(from: \.([a-z_]+), to: \.([a-z_]+), requiresReason: (true|false), requiresAssignee: (true|false), requiresVerification: (true|false)\)/g)]
    .map(m => `${m[1]}>${m[2]}:${m[3]}:${m[4]}:${m[5]}`);
  assert.equal(server.length, 16);
  // Offering a move the server refuses, or hiding one it accepts, is the same
  // defect. Both directions are compared.
  assert.deepEqual([...client].sort(), [...server].sort());
});

test('the record screen only offers what the server will accept', () => {
  const screen = read('App/DesignSystem/ISG/NovaNonconformityRecordScreen.swift');
  // Closing asks for the verification first instead of failing at the server.
  assert.match(screen, /edge\.requiresVerification && !hasAcceptedVerification/);
  assert.match(screen, /contains \{ \$0\.outcome == "accepted" \}/);
  const sheets = read('App/DesignSystem/ISG/NovaNonconformitySheets.swift');
  // The server refuses a reason under five characters; so does the popup.
  assert.match(sheets, /trimmedReason\.count < 5/);
  const core = read('supabase/migrations/20260913210000_isg_nonconformity_core.sql');
  assert.match(core, /length\(reason\) BETWEEN 5 AND 2000/);
});

test('the board reads every company through its own availability check', () => {
  const service = read('App/Services/Company/NovaAnalysisWorkspaceService.swift');
  assert.match(service, /static func board\(identity: NovaSessionIdentity\)/);
  assert.match(service, /guard novaCurrentSessionIdentity\(\) == identity else \{ throw NovaNonconformityFailure\.denied \}/);
  // A company whose own read fails is left out of the board, never faked.
  assert.match(service, /else \{ continue \}/);
});

test('filing an item is keyed by that item, so a second press replays', () => {
  const gate = read('App/Views/Components/NovaPilotFindingsGate.swift');
  assert.match(gate, /service\.open\(current, intent: intent, mutationID: request\.item\.id\)/);
  assert.match(gate, /result\.alreadyOpen \? \.alreadyOpen : \.opened/);
  // The analysis and its findings are referenced, never copied or rewritten.
  assert.doesNotMatch(gate, /deleteFinding|deleteAnalysis/);
});
