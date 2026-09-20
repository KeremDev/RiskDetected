import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const gate = read('App/Views/Components/NovaPilotMainGate.swift');
const store = read('App/Services/ISG/IsgWorkspaceStore.swift');
const domain = read('App/DesignSystem/ISG/IsgWorkspaceDomainScreen.swift');
const personnel = read('App/DesignSystem/ISG/IsgWorkspacePersonnelScreen.swift');
const navigation = read('App/DesignSystem/ISG/NovaNavigation.swift');
const shell = read('App/DesignSystem/ISG/NovaExpertShell.swift');

const osgbRoot = gate.slice(gate.indexOf('private struct IsgOSGBWorkspaceRoot'),
  gate.indexOf('private struct IsgWorkspaceMemberManagement'));
const destinationSwitch = osgbRoot.slice(osgbRoot.indexOf('switch destination {'),
  osgbRoot.indexOf('.preferredColorScheme'));

const sharedRoot = gate.slice(gate.indexOf('struct NovaPilotRoot'),
  gate.indexOf('// MARK: - OSGB expert data adapters'));

test('OSGB expert is routed into the normal expert root and home has no company selector', () => {
  assert.match(store, /func aggregateExpertDashboard\(\)/);
  assert.match(store, /func aggregateExpertPersonnelMetrics\(\)/);
  assert.match(store, /for company in assignedCompanies/);
  assert.match(gate, /membership\.role == "expert"[\s\S]*NovaPilotRoot\(identity: identity,[\s\S]*workspaceStore: store/);
  assert.match(sharedRoot, /dashboardMetrics/);
  assert.match(sharedRoot, /aggregateExpertDashboard\(\)/);
  assert.doesNotMatch(sharedRoot.slice(sharedRoot.indexOf('case .home:'), sharedRoot.indexOf('case .statistics:')), /companySelector/);
  assert.match(navigation, /osgbExpert:[\s\S]*subtracting\(\[\.newCompany\]\)/);
  assert.match(shell, /if showsPhotoCapture \{/);
  assert.match(sharedRoot, /Atandığınız firmalardaki toplam güncel kayıtlar\./);
});

test('company selection does not unmount the shared expert root while dashboard reloads', () => {
  const integrated = gate.slice(gate.indexOf('struct NovaIntegratedWorkspaceGate'),
    gate.indexOf('private struct IsgWorkspaceChooser'));
  const expertBranch = integrated.slice(integrated.indexOf('membership.role == "expert"'),
    integrated.indexOf('} else if store.phase == .ready'));
  assert.match(expertBranch, /NovaPilotRoot\(/);
  assert.doesNotMatch(expertBranch, /store\.phase == \.ready/);
  assert.match(sharedRoot, /if !isWorkspaceExpert && controller\.resolving/);
});

test('company rows open the shared-root tenant company detail instead of returning home', () => {
  assert.match(sharedRoot, /NovaWorkspaceExpertCompaniesGate/);
  assert.match(gate, /NovaWorkspaceExpertCompanyDetail/);
  assert.match(gate, /NovaCompanyAccordion/);
  const companyList = gate.slice(gate.indexOf('private struct NovaWorkspaceExpertCompaniesGate'),
    gate.indexOf('private struct NovaWorkspaceExpertCompanyDetail'));
  assert.doesNotMatch(companyList, /onSelect:[\s\S]{0,500}navigate\(\.home\)/);
});

test('shared expert destination switch connects OSGB workspace routes explicitly', () => {
  for (const marker of [
    'case .newFinding:', 'case .newAnalysis:', 'case .training, .newTraining:',
    'case .newDocument:', 'case .newVisit:', 'case .newCompany:',
    'case .memory:'
  ]) assert.ok(sharedRoot.includes(marker), marker);
  assert.match(sharedRoot, /workspaceDomain\(workspaceStore, \.visit, startInAddMode: true\)/);
});

test('quick-add routes present their editor and contractor route selects its own section', () => {
  assert.match(domain, /var startInAddMode = false/);
  assert.match(domain, /showingCreate = true/);
  assert.match(personnel, /initialSection: IsgPersonnelSection = \.employee/);
  assert.match(personnel, /_section = State\(initialValue: initialSection\)/);
});
