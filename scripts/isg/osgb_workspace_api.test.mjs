import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {ROOT} from './lib.mjs';

test('Swift workspace API rejects stale responses around every await',()=>{
  const directory=mkdtempSync(join(tmpdir(),'isgada-workspace-api-'));
  try {
    const binary=join(directory,'workspace-api-check');
    const build=spawnSync('swiftc',['-parse-as-library','App/Services/ISG/IsgMutationContext.swift',
      'App/DesignSystem/ISG/NovaNavigation.swift','App/DesignSystem/ISG/NovaSessionHost.swift',
      'App/Services/ISG/IsgWorkspaceAPI.swift','scripts/isg/WorkspaceAPICheck.swift','-o',binary],
      {cwd:ROOT,encoding:'utf8',timeout:30000});
    assert.equal(build.status,0,build.stderr||build.stdout);
    const run=spawnSync(binary,[],{cwd:ROOT,encoding:'utf8',timeout:10000});
    assert.equal(run.status,0,run.stderr||run.stdout);
    assert.match(run.stdout,/PASS Swift workspace API/);
  } finally { rmSync(directory,{recursive:true,force:true}); }
});

test('iOS and Android use only workspace endpoints and recheck scope after transport',()=>{
  const files=['App/Services/ISG/IsgWorkspaceAPI.swift',
    'android/core/data/src/main/kotlin/com/riskdetectedan/core/data/isg/IsgWorkspaceGateway.kt'];
  for(const path of files){
    const source=readFileSync(resolve(ROOT,path),'utf8');
    for(const endpoint of ['isg_workspace_list_v1','isg_workspace_company_list_v1','isg_workspace_personnel_metrics_v1',
      'isg_workspace_assignment_list_v1','isg_workspace_assignment_mutate_v1',
      'isg_workspace_dashboard_v1','isg_workspace_search_v1','isg_workspace_analysis_list_v1','isg_workspace_analysis_read_v1',
      'isg_workspace_analysis_file_v1','isg_workspace_export_create_v1','isg_workspace_export_get_v1',
      'isg_workspace_change_read_v1'])
      assert.ok(source.includes(endpoint),`${path}: ${endpoint}`);
    assert.doesNotMatch(source,/isg_personnel_read_v1|from\("companies"\)/);
  }
  const ios=readFileSync(resolve(ROOT,files[0]),'utf8');
  assert.match(ios,/let data = try await rpc[\s\S]*try require\(selection\)/);
  const android=readFileSync(resolve(ROOT,files[1]),'utf8');
  assert.match(android,/val result = invoke[\s\S]*checkWorkspace\(workspaceId, membershipId, permissionRevision\)/);
  for(const method of ['fileAnalysisItem','createExport']){
    const block=android.slice(android.indexOf(`suspend fun ${method}`),android.indexOf('\n    suspend fun ',android.indexOf(`suspend fun ${method}`)+1));
    assert.match(block,/checkWorkspace\(workspaceId, membershipId, permissionRevision, canOperate\)/);
  }
});

test('session store exposes analysis filing, export and change flows with standard success copy',()=>{
  const store=readFileSync(resolve(ROOT,'App/Services/ISG/IsgWorkspaceStore.swift'),'utf8');
  const success=readFileSync(resolve(ROOT,'App/DesignSystem/ISG/NovaSuccessPresentation.swift'),'utf8');
  for(const method of ['personnelMetrics','search','analyses','analysis','fileAnalysisItem','createExport','export','changes'])
    assert.match(store,new RegExp(`func ${method}\\(`),method);
  for(const method of ['assignments','mutateAssignment'])
    assert.match(store,new RegExp(`func ${method}\\(`),method);
  assert.match(store,/expectedSelection\(operate: true\)/);
  assert.match(store,/NovaSuccessMessage\.serverKey\(result\.successMessageKey\)/);
  assert.match(success,/case "analysis_finding_filed": return findingCreated/);
  assert.match(success,/case "analysis_finding_already_filed"/);
});

test('iOS workspace setup and member management stay on scoped server operations',()=>{
  const api=readFileSync(resolve(ROOT,'App/Services/ISG/IsgWorkspaceAPI.swift'),'utf8');
  const store=readFileSync(resolve(ROOT,'App/Services/ISG/IsgWorkspaceStore.swift'),'utf8');
  for(const endpoint of ['isg_osgb_workspace_create_v1','isg_workspace_invitation_accept_v1',
    'isg_workspace_member_list_v1','isg_workspace_invitation_list_v1','isg_workspace_invite_v1',
    'isg_workspace_invitation_resend_v1','isg_workspace_invitation_mutate_v1','isg_workspace_member_mutate_v1',
    'isg_workspace_company_create_v1','isg_workspace_company_update_v1','isg_workspace_company_archive_v1'])
    assert.ok(api.includes(endpoint),endpoint);
  for(const method of ['createWorkspace','acceptInvitation','members','invitations','invite',
    'resendInvitation','revokeInvitation','mutateMember','createCompany','updateCompany','archiveCompany'])
    assert.match(store,new RegExp(`func ${method}\\(`),method);
  assert.match(store,/dashboard = try\? await api\.dashboard/,
    'a refresh failure must not report a committed company mutation as failed');
  assert.doesNotMatch(api,/isg_personnel_read_v1|from\("workspace_memberships"\)|from\("workspace_invitations"\)/);
});

test('company expert assignment UI uses scoped members, assignment history and reviewed mutations',()=>{
  const ui=readFileSync(resolve(ROOT,'App/DesignSystem/ISG/IsgWorkspaceAssignmentScreen.swift'),'utf8');
  const gate=readFileSync(resolve(ROOT,'App/Views/Components/NovaPilotMainGate.swift'),'utf8');
  assert.match(ui,/store\.members\(status: "active"\)/);
  assert.match(ui,/store\.assignments\(companyID: company\.id\)/);
  assert.match(ui,/store\.mutateAssignment[\s\S]*action: "create"/);
  assert.match(ui,/store\.mutateAssignment[\s\S]*action: "end"/);
  assert.match(ui,/\$0\.status == "active" && \$0\.isPracticingExpert/);
  assert.match(ui,/expectedVersion: assignment\.version/);
  assert.match(gate,/IsgWorkspaceAssignmentManagement\(store: store, company: company\)/);
});

test('live iOS adapter binds RPC calls to the current Supabase auth identity',()=>{
  const adapter=readFileSync(resolve(ROOT,'App/Services/ISG/IsgWorkspaceLiveAdapter.swift'),'utf8');
  assert.match(adapter,/import Supabase/);
  assert.match(adapter,/SupabaseService\.shared\.client/);
  assert.match(adapter,/client\.rpc\(function, params: arguments\)\.execute\(\)\.data/);
  assert.match(adapter,/novaCurrentSessionIdentity\(\) == currentIdentity\(\)/);
  assert.match(adapter,/currentSelection\(\) == expected/);
  assert.doesNotMatch(adapter,/service_role|anonKey|fallback/);
});

test('iOS operational modules use scoped D1-D8 reads and reviewed mutations',()=>{
  const api=readFileSync(resolve(ROOT,'App/Services/ISG/IsgWorkspaceAPI.swift'),'utf8');
  const store=readFileSync(resolve(ROOT,'App/Services/ISG/IsgWorkspaceStore.swift'),'utf8');
  const gate=readFileSync(resolve(ROOT,'App/Views/Components/NovaPilotMainGate.swift'),'utf8');
  const create=readFileSync(resolve(ROOT,'App/DesignSystem/ISG/IsgWorkspaceDomainCreateEditor.swift'),'utf8');
  const personnel=readFileSync(resolve(ROOT,'App/DesignSystem/ISG/IsgWorkspacePersonnelScreen.swift'),'utf8');
  const analyses=readFileSync(resolve(ROOT,'App/DesignSystem/ISG/IsgWorkspaceAnalysisScreen.swift'),'utf8');
  for(const endpoint of ['isg_workspace_personnel_read_v1','isg_workspace_directory_mutate_v1',
    'isg_workspace_employee_mutate_v1','isg_workspace_training_read_v1','isg_workspace_training_mutate_v1',
    'isg_workspace_risk_read_v1','isg_workspace_risk_mutate_v1','isg_workspace_nonconformity_read_v1',
    'isg_workspace_nonconformity_mutate_v1','isg_workspace_checklist_read_v1','isg_workspace_checklist_mutate_v1',
    'isg_workspace_safety_read_v1','isg_workspace_safety_mutate_v1','isg_workspace_equipment_read_v1',
    'isg_workspace_equipment_mutate_v1','isg_workspace_operations_read_v1',
    'isg_workspace_operations_mutate_v1','isg_workspace_file_read_v1'])
    assert.ok(api.includes(endpoint),endpoint);
  assert.match(store,/func mutateDomain\([\s\S]*expectedSelection\(operate: true\)/);
  assert.match(create,/selectedRiskAssessment[\s\S]*expected_current[\s\S]*"partial"/,
    'risk revisions must carry the current version instead of reopening version zero');
  assert.match(personnel,/mutateDirectory[\s\S]*mutateEmployee/);
  for(const domain of ['personnel','training','risk','nonconformity','checklist','emergencyPlan','drill',
    'appointment','ppe','equipment','katip','annualPlan','board','workPermit','visit','files'])
    assert.ok(gate.includes(`.${domain}`),`navigation route: ${domain}`);
  for(const source of [create,personnel])
    assert.doesNotMatch(source,/NovaPersonnelService|NovaTrainingService|NovaRiskAssessmentService|NovaFileLibraryService/);
  assert.match(analyses,/store\.analyses[\s\S]*store\.analysis[\s\S]*store\.fileAnalysisItem[\s\S]*store\.createExport/);
  assert.doesNotMatch(analyses,/NovaAnalysisWorkspace|AnalysisResultHubService/);
});
