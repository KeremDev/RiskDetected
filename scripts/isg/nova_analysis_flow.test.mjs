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
    'App/DesignSystem/ISG/NovaAnalysisSectionViews.swift',
    'App/DesignSystem/ISG/NovaAnalysisReportsScreen.swift',
    'App/DesignSystem/ISG/NovaManualNonconformityScreen.swift',
    'App/DesignSystem/ISG/NovaNonconformityTransitions.swift',
    'App/DesignSystem/ISG/NovaNonconformityListScreen.swift',
    'App/DesignSystem/ISG/NovaNonconformityRecordScreen.swift',
    'App/DesignSystem/ISG/NovaFolderTabs.swift']) {
    const source = read(path);
    assert.doesNotMatch(source, /import (Supabase|RevenueCat)|https?:|access_token|refresh_token|UserDefaults|Keychain/, path);
    assert.doesNotMatch(source, /AnalysisService|SupabaseService|PDFReportService/, path);
  }
});

test('every menu entry lands on exactly one page', () => {
  const gate = read('App/Views/Components/NovaPilotFindingsGate.swift');
  assert.match(gate, /enum NovaFindingsSurface: Equatable \{ case board, analyses, newAnalysis, addFinding \}/);
  const main = read('App/Views/Components/NovaPilotMainGate.swift');
  for (const [destination, surface] of [['findings', 'board'], ['analyses', 'analyses'],
    ['newAnalysis', 'newAnalysis'], ['newFinding', 'addFinding']]) {
    assert.match(main, new RegExp(`case \\.${destination}:\\s*\\n\\s*nonconformities\\(\\.${surface}\\)`), destination);
  }
  // The home picture card starts an analysis rather than a hub.
  assert.match(main, /onPhoto: \{ navigate\(\.newAnalysis\) \}/);
  const navigation = read('App/DesignSystem/ISG/NovaNavigation.swift');
  for (const id of ['analyses', 'newAnalysis', 'findings', 'newFinding']) {
    assert.ok(navigation.includes(`.${id},`) || navigation.includes(`.${id}]`), id);
  }
});

test('the manual flow asks every step the expert was promised', () => {
  assert.match(model, /case photo, company, hazard, scoring, legislation, responsible/);
  // Only the two steps the server refuses without are required to save.
  assert.match(model, /static let requiredSteps: \[NovaManualStep\] = \[\.company, \.hazard\]/);
  assert.match(model, /score\.isEmpty \|\| score\.isComplete/);
  const screen = read('App/DesignSystem/ISG/NovaManualNonconformityScreen.swift');
  for (const key of ['manual.step.photo', 'manual.step.firma', 'manual.step.hazard', 'manual.step.scoring',
    'manual.step.legislation', 'manual.step.responsible']) {
    assert.ok(screen.includes(key), `manual step missing: ${key}`);
  }
  // The progress bar counts finished steps, never opened ones.
  assert.match(model, /var completedCount: Int \{ NovaManualStep\.allCases\.filter \{ isComplete\(\$0\) \}\.count \}/);
  assert.match(screen, /width: max\(0, proxy\.size\.width \* draft\.progress\)/);
  // The picture is what the expert has in hand, so its step starts open.
  assert.match(screen, /@State private var open: NovaManualStep\? = \.photo/);
  // A record always lands on a real workplace and the screen names the one it used.
  assert.match(screen, /localizable\.nova\.manual\.workplace\.used/);
  assert.match(model, /case \.company: return companyID != nil && workplaceID != nil/);
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
  // The server refuses a reason under five characters; so does the popup.
  assert.match(screen, /reason\.trimmingCharacters\(in: \.whitespacesAndNewlines\)\.count < 5/);
  const core = read('supabase/migrations/20260913210000_isg_nonconformity_core.sql');
  assert.match(core, /length\(reason\) BETWEEN 5 AND 2000/);
});

test('the board reads every company through its own availability check', () => {
  const service = read('App/Services/Company/NovaAnalysisWorkspaceService.swift');
  assert.match(service, /static func board\(identity: NovaSessionIdentity\)/);
  assert.match(service, /guard novaCurrentSessionIdentity\(\) == identity else \{ throw NovaNonconformityFailure\.denied \}/);
  // A failed company read cannot be presented as a complete zero/count.
  const board = service.slice(service.indexOf('static func board(identity:'), service.indexOf('private struct ListEnvelope'));
  assert.match(board, /let list = try await read/);
  assert.match(board, /let places = try await read/);
  assert.doesNotMatch(board, /try\?|else \{ continue \}/);
});

test('filing a source uses server deduplication without reusing a key across companies', () => {
  const gate = read('App/Views/Components/NovaPilotFindingsGate.swift');
  assert.match(gate, /analysisFilingService\.open\(current, intent: intent\)/);
  const source = read('supabase/pilot-release/candidates/20260916143000_isg_pilot_finding_source.sql');
  assert.match(source, /pg_advisory_xact_lock/);
  assert.match(source, /open_nonconformity_record/);
  assert.match(source, /IF NOT coalesce\(\(outcome->>'replayed'\)::boolean,false\) THEN/);
  assert.match(gate, /result\.alreadyOpen \? \.alreadyOpen : \.opened/);
  // The analysis itself remains unchanged; the server saves a source snapshot.
  assert.doesNotMatch(gate, /deleteFinding|deleteAnalysis/);
});

test('filing only reports success after the company read path sees the record', () => {
  const gate = read('App/Views/Components/NovaPilotFindingsGate.swift');
  assert.match(gate, /let visible = try await analysisFilingService\.list\(current\)/);
  assert.match(gate, /let visible = try await service\.list\(target\)/);
  assert.match(gate, /visible\.contains\(where: \{ \$0\.id == filedRow\.id && \$0\.state == filedRow\.state \}\)/);
  assert.match(gate, /visible\.contains\(where: \{ \$0\.id == result\.row\.id \}\)/);
  assert.match(gate, /guard visible\.contains[\s\S]{0,500}?boardRevision = UUID\(\)/);
  const list = read('App/DesignSystem/ISG/NovaNonconformityListScreen.swift');
  assert.doesNotMatch(list, /catch let failure as NovaNonconformityFailure \{\s*entries = \[\]/);
  assert.doesNotMatch(list, /catch \{\s*entries = \[\]/);
});

test('analysis filing uses its selected company without racing the global company scope', () => {
  const gate = read('App/Views/Components/NovaPilotFindingsGate.swift');
  assert.match(gate, /analysisFilingService: NovaNonconformityService \{ \.live\(identity: identity\) \}/);
  assert.match(gate, /analysisFilingService\.workplaces\(analysisFilingScope\(company\)\)/);
  const fileBlock = gate.slice(gate.indexOf('private func file(_ request:'), gate.indexOf('// MARK: manual'));
  assert.match(fileBlock, /analysisFilingService\.open\(current, intent: intent\)/);
  assert.match(fileBlock, /analysisFilingService\.list\(current\)/);
  assert.doesNotMatch(fileBlock, /waitForScope/);
  const adapter = read('App/Services/Company/NovaNonconformityLiveAdapter.swift');
  assert.match(adapter, /static func live\(identity: NovaSessionIdentity\)/);
  assert.match(adapter, /novaCurrentSessionIdentity\(\) == identity/);
});

test('nonconformity rows open their popup without rebuilding company scope', () => {
  const gate = read('App/Views/Components/NovaPilotFindingsGate.swift');
  assert.match(gate, /open: \{ entry in record = entry \}/);
  const client = gate.slice(gate.indexOf('private func recordClient'), gate.indexOf('private func waitForScope'));
  assert.match(client, /let recordScope = analysisFilingScope\(entry\.companyID\)/);
  assert.match(client, /analysisFilingService\.detail\(recordScope/);
  assert.doesNotMatch(client, /select\(|waitForScope|service\./);
});

test('analysis findings enter the actionable queue as open, not draft', () => {
  const gate = read('App/Views/Components/NovaPilotFindingsGate.swift');
  const fileBlock = gate.slice(gate.indexOf('private func file(_ request:'), gate.indexOf('// MARK: manual'));
  assert.match(fileBlock, /result\.row\.state == NovaNonconformityState\.draft\.rawValue/);
  assert.match(fileBlock, /analysisFilingService\.transition\(current, id: result\.row\.id, to: \.open/);
  assert.match(fileBlock, /\$0\.id == filedRow\.id && \$0\.state == filedRow\.state/);
});

test('a filed finding reuses the analysis detail sheet without another filing action', () => {
  const gate = read('App/Views/Components/NovaPilotFindingsGate.swift');
  assert.match(gate, /if entry\.row\.camefromFinding \{[\s\S]{0,300}?NovaFiledFindingSheet/);
  const sheets = read('App/DesignSystem/ISG/NovaAnalysisSheets.swift');
  const filed = sheets.slice(sheets.indexOf('struct NovaFiledFindingSheet'), sheets.indexOf('/// Editing one scored finding'));
  assert.match(filed, /NovaAnalysisItemSheet\(item: source\.item/);
  assert.match(filed, /onEdit: \{ mode = \.edit \}, onDelete: \{ mode = \.delete \}, onFile: nil/);
  assert.doesNotMatch(filed, /Firmaya Uygunsuzluk Olarak Ekle/);
  const workspace = read('App/Services/Company/NovaAnalysisWorkspaceService.swift');
  const sourceLookup = workspace.slice(workspace.indexOf('static func recordFinding('), workspace.indexOf('/// Every picture of one analysis'));
  assert.match(sourceLookup, /section\.items\.first\(where: \{ \$0\.id == findingID \}\)/);
});

test('successful filing closes the popup and celebrates only after readback', () => {
  const sheet = read('App/DesignSystem/ISG/NovaAnalysisSheets.swift');
  assert.match(sheet, /case \.opened, \.alreadyOpen: succeeded = true/);
  assert.match(sheet, /if succeeded && !failed \{\s*celebrate\(NovaSuccessMessage\.findingCreated\)\s*onFinished\(\)/);
  assert.match(sheet, /loaded\.count == 1,[\s\S]{0,140}?ready\.count == items\.count[\s\S]{0,100}?await run\(target: only\.id\)/);
  const gate = read('App/Views/Components/NovaPilotFindingsGate.swift');
  assert.match(gate, /\.modifier\(NovaSuccessPresentation\(\)\)/);
});

test('the method toggle reads a band, it never converts one', () => {
  const model = read('App/DesignSystem/ISG/NovaAnalysisDetail.swift');
  // Each method keeps its own score. Nothing maps one scale onto the other.
  assert.match(model, /func score\(_ method: NovaRiskMethod\) -> NovaAnalysisScore\? \{\s*\n\s*method == \.fineKinney \? fineKinney : matrix/);
  assert.doesNotMatch(model, /fk.*(?:\*|\/)\s*\d+\s*(?:\/|\*).*m5/i);
  const service = read('App/Services/Company/NovaAnalysisWorkspaceService.swift');
  // A method's factors are printed only when the analysis recorded all of them.
  assert.match(service, /guard band != nil \|\| score != nil else \{ return nil \}/);
  assert.match(service, /if let probability, let frequency, let severity \{/);
  // The judgement sections are given no score at all, under either method.
  assert.match(service, /if kind\.isScored \{[\s\S]{0,400}?item\.fineKinney = fineKinney[\s\S]{0,300}?item\.matrix = matrix/);
});

test('the band that is filed is the band the expert was reading', () => {
  const model = read('App/DesignSystem/ISG/NovaAnalysisDetail.swift');
  // The request carries the band; the item alone no longer answers for one.
  assert.match(model, /struct NovaAnalysisFileRequest[\s\S]{0,700}?let band: String\?/);
  const sheets = read('App/DesignSystem/ISG/NovaAnalysisSheets.swift');
  assert.match(sheets, /band: section\.isScored \? item\.band\(method\) : nil/);
  const gate = read('App/Views/Components/NovaPilotFindingsGate.swift');
  assert.match(gate, /if request\.severity == nil \{ intent\.riskBand = request\.band \}/);
});

test('every count on the analysis pages is counted from the rows on screen', () => {
  const model = read('App/DesignSystem/ISG/NovaAnalysisDetail.swift');
  // The list card counts the rows it was handed; it never takes a total from
  // somewhere the page did not read.
  assert.match(model, /struct NovaAnalysisListStats[\s\S]{0,600}?init\(_ rows: \[NovaAnalysisSummary\]/);
  assert.match(model, /total = rows\.count/);
  assert.match(model, /struct NovaAnalysisReportStats[\s\S]{0,400}?init\(_ rows: \[NovaAnalysisReportEntry\]/);
  // The band distribution is counted over the section's own items, under the
  // method being read, not taken from anywhere else.
  assert.match(model, /items\.filter \{ \$0\.band\(method\) == band \}\.count/);
  const screen = read('App/DesignSystem/ISG/NovaAnalysisDetailScreens.swift');
  // Counts are now in the section navigation, after removal of the large summary card.
  assert.match(screen, /caption: NovaAnalysisWords\.unit\(entry\.kind, entry\.items\.count\)/);
});

test('the report archive page reads the photo analyses it claims to list', () => {
  const service = read('App/Services/Company/NovaAnalysisWorkspaceService.swift');
  assert.match(service, /listReports\(limit: limit, photoAnalysesOnly: true\)/);
  // A company the pilot list cannot name falls back to the archive's own
  // snapshot rather than being shown as if it had no company.
  assert.match(service, /companyName: row\.companyID\.flatMap \{ names\[\$0\] \} \?\? row\.companySnapshot\?\.name/);
  const gate = read('App/Views/Components/NovaPilotFindingsGate.swift');
  assert.match(gate, /NovaAnalysisReportsScreen\(/);
});

test('the analysis detail owns the bottom of its own page', () => {
  const screen = read('App/DesignSystem/ISG/NovaAnalysisDetailScreens.swift');
  // The bar is pinned, so scrolling never takes the two controls away.
  assert.match(screen, /\.safeAreaInset\(edge: \.bottom, spacing: 0\) \{ if data != nil \{ actionBar \} \}/);
  assert.match(screen, /accessibilityIdentifier\("analysis\.detail\.back"\)/);
  assert.match(screen, /symbol: "slider\.horizontal\.3", id: "report"/);
  assert.match(screen, /accessibilityIdentifier\("analysis\.detail\.\\\(id\)"\)/);
  // The page is presented over the shell, so the shell's tab bar is not under it.
  const gate = read('App/Views/Components/NovaPilotFindingsGate.swift');
  assert.match(gate, /\.novaFullScreenCover\(item: \$openAnalysis\) \{ target in\s+detail\(target\.id\)/);
  // Risk analysis is what the detail opens on.
  assert.match(screen, /@State private var section: NovaAnalysisSectionKind = \.riskAnalysis/);
});
