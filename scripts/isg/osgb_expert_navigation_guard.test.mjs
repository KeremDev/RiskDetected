import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const gate = read('App/Views/Components/NovaPilotMainGate.swift');
const sharedRoot = gate.slice(gate.indexOf('struct NovaPilotRoot'));
const transport = read('App/Services/Company/NovaExpertTransport.swift');

test('workspace revalidation retains tenant routing and initial loading cannot mount personal transport', () => {
  const store = read('App/Services/ISG/IsgWorkspaceStore.swift');
  const refresh = store.slice(store.indexOf('    func refresh()'), store.indexOf('    func selectCompany('));
  assert.match(refresh, /invalidateContent\(\)/);
  assert.doesNotMatch(refresh, /\binvalidate\(\)/);
  assert.match(gate, /store.selection == nil && \(store.phase == .signedOut \|\| store.phase == .loading\)/);
});

test('both expert roles enter the actual normal expert root', () => {
  assert.match(gate, /membership\.role == "expert"[\s\S]*NovaPilotRoot\(identity: identity,[\s\S]*workspaceStore: store/);
  assert.doesNotMatch(sharedRoot, /NovaWorkspaceExpert|IsgWorkspace\w+Screen|workspaceDomain\(/);
  assert.doesNotMatch(gate, /struct NovaWorkspaceExpert/);
});

test('company detail, training and module routes use the original components', () => {
  for (const component of ['NovaCompanyWorkspace', 'NovaCompanyDestination', 'NovaTrainingHub',
    'NovaPilotFindingsGate', 'NovaPilotRiskGate', 'NovaPilotChecklistGate',
    'NovaPilotEquipmentGate', 'NovaPilotEmergencyGate', 'NovaPilotDrillGate',
    'NovaPilotPPEGate', 'NovaPilotAppointmentGate', 'NovaPilotFileGate',
    'NovaPilotDocumentGate', 'NovaPilotProcessGate']) {
    assert.ok(sharedRoot.includes(component), component);
  }
  assert.match(sharedRoot, /includeArchived: true, onSelect: controller.select/);
  assert.match(sharedRoot, /onBack: \{ controller.select\(nil\) \}/);
  assert.match(sharedRoot, /loadSummary: \{ try await loadNovaPilotOverview/);
});

test('both roles load the same dashboard; no company selection on home', () => {
  assert.doesNotMatch(sharedRoot, /aggregateExpertDashboard|workspaceMetrics|companySelector/);
  assert.match(sharedRoot, /NovaDashboardScreen/);
  assert.match(sharedRoot, /metrics: metrics/);
  assert.match(sharedRoot, /loadNovaPilotOverview/);
});

test('tenant access is selected in services, with no personal fallback on failure', () => {
  assert.match(transport, /isg_expert_rpc_v1/);
  assert.match(transport, /_expert_workspace_id/);
  assert.match(transport, /expected == ticket/);
  assert.match(transport, /try validate\(expected\)[\s\S]*let result: Data/);
  assert.match(transport, /try validate\(expected\)\s+return result/);
  assert.doesNotMatch(transport, /catch/);
  const controller = read('App/Services/Company/NovaWorkspaceController.swift');
  assert.match(controller, /NovaExpertTransport.shared.bind/);
  assert.match(controller, /NovaExpertTransport.shared.release/);
});

test('assigned experts operate records without inheriting company ownership', () => {
  const company = read('App/Views/Components/NovaCompanyManagementGate.swift');
  assert.match(company, /canManageCompany/);
  assert.match(company, /if canManageCompany \{/);
  assert.match(sharedRoot, /onCreate: isWorkspaceExpert \? nil/);
});

test('education continues through the original form service, scoped pending storage', () => {
  const service = read('App/Services/Company/NovaEducationService.swift');
  assert.match(service, /NovaExpertTransport/);
  assert.match(service, /storageNamespace/);
  assert.match(service, /isg_pilot_training_record_v3/);
});
