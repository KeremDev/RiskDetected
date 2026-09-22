import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const start = read('App/DesignSystem/ISG/NovaChecklistStartFlow.swift');
const lists = read('App/DesignSystem/ISG/NovaChecklistListFlow.swift');
const process = read('App/Views/Components/NovaPilotProcessGate.swift');
const reports = read('App/Views/Components/NovaReportCenter.swift');
const archive = read('App/Views/Components/NovaProcessArchive.swift');
const main = read('App/Views/Components/NovaPilotMainGate.swift');
const training = read('App/DesignSystem/ISG/NovaTrainingScreens.swift');
const emergency = read('App/DesignSystem/ISG/IsgWorkspaceEmergencyPlanCreateFlow.swift');
const appointments = read('App/DesignSystem/ISG/NovaAppointmentSheets.swift');
const drills = read('App/DesignSystem/ISG/NovaDrillSheets.swift');
const company = read('App/Views/Components/NovaPilotCompanyCreateView.swift');
const workspaceEditor = read('App/DesignSystem/ISG/IsgWorkspaceDomainCreateEditor.swift');
const workspaceStore = read('App/Services/ISG/IsgWorkspaceStore.swift');
const sharedExpertAnalysis = read('supabase/migrations/20260920200146_expert_shared_analysis.sql');
const companyProgress = read('App/DesignSystem/ISG/NovaCompanyProgressViews.swift');
const companyManagement = read('App/Views/Components/NovaCompanyManagementGate.swift');

test('checklist catalogue keeps technical provenance out of the customer UI', () => {
  for (const source of [start, lists]) assert.doesNotMatch(source, /Kaynak ve sürüm bilgileri/);
  assert.match(start, /NovaFilterField\(label: "Sektör"/);
  assert.match(start, /NovaFilterField\(label: "Liste türü"/);
  assert.match(start, /Sektör, ekipman veya iş ara/);
});

test('site visit is a four-stage task with a result state', () => {
  for (const label of ['İşyeri', 'Tarih ve süre', 'Ziyaret ayrıntıları', 'Dosya ve kontrol']) assert.ok(process.includes(label), label);
  assert.match(process, /NovaTaskSuccessView\(title: record == nil \? "Saha ziyareti kaydedildi"/);
  assert.match(process, /duration_minutes/);
});

test('report center creates and archives customer-selected reports', () => {
  for (const kind of ['Firma raporu', 'Eğitim raporu', 'Bekleyen işler', 'Tamamlanan işler', 'Ziyaret raporu', 'Tüm süreçler']) assert.ok(reports.includes(kind), kind);
  for (const step of ['Rapor türü', 'Kapsam ve dönem', 'Çıktı biçimi', 'Kontrol ve oluştur']) assert.ok(reports.includes(step), step);
  assert.match(reports, /UIGraphicsPDFRenderer/);
  assert.match(reports, /Excel/);
  for (const section of ['Süreç belgeleri', 'Analiz raporları', 'Uygunsuzluk raporları', 'Özel raporlarım']) assert.ok(archive.includes(section), section);
  assert.match(main, /case \.reports: reportCenter/);
  assert.match(main, /case \.reports:\s*NovaReportCenter/);
  assert.match(main, /case \.reportArchive: NovaProcessArchive/);
  assert.match(reports, /createRoute = \.init\(kind: kind, skipsTypeSelection: true\)/);
  assert.match(reports, /_step = State\(initialValue: skipsTypeSelection \? 1 : 0\)/);
  assert.match(reports, /Raporda neler yer alsın\?/);
  assert.match(reports, /Özel alan ekle/);
  assert.match(reports, /selectedContent\.contains\(row\.kind\)/);
});

test('workspace company list survives navigation and logo management is visible', () => {
  assert.match(main, /if let workspaceStore \{/);
  assert.match(main, /companies: workspaceStore\.companies\.map/);
  assert.match(main, /onRetry: \{ workspaceStore\.refresh\(\) \}/);
  assert.match(main, /companyLogoRow\(company\)/);
  assert.match(main, /company\.logo\.picker/);
  assert.match(main, /"action": \.string\("set_company_logo"\)/);
});

test('company detail uses the interactive ten-heading readiness ring in every workspace', () => {
  for (const heading of ['Firma Bilgileri', 'Risk Analizi', 'Acil Durum Planı', 'Eğitim', 'Personel',
    'Uygunsuzluk', 'Periyodik Kontrol', 'Logo', 'Sorumlu Kişi', 'Ziyaretler']) {
    assert.ok(main.includes(`title: "${heading}"`) || companyManagement.includes(`title: "${heading}"`), heading);
  }
  assert.match(companyProgress, /struct NovaCompanyReadinessCard/);
  assert.match(companyProgress, /NovaCompanyRingSegment/);
  assert.match(companyProgress, /company\.progress\.segment/);
  assert.match(companyProgress, /\.onHover/);
  assert.match(main, /NovaCompanyReadinessCard\(items: companyReadinessItems\(company\)\)/);
  assert.match(companyManagement, /NovaCompanyReadinessCard\(items: readinessItems\)/);
  assert.match(main, /domain: \.visit/);
});

test('zero or one workplace is automatic while multiple workplaces remain selectable', () => {
  assert.match(workspaceEditor, /if workplaces\.isEmpty \{[\s\S]*try await store\.initializePersonnel\(\)/);
  assert.match(workspaceEditor, /workplaceID = workplaces\.count == 1 \? workplaces\.first\?\.id : nil/);
  assert.match(workspaceEditor, /private var minimumWizardStep: Int \{ scopeNeedsInput \? 0 : 1 \}/);
  assert.match(workspaceStore, /try\? await api\.initializePersonnel\(selection: selection, companyID: company\.id\)/);
  assert.match(sharedExpertAnalysis, /CREATE TRIGGER expert_company_default_workplace AFTER INSERT ON public\.companies/);
  assert.match(sharedExpertAnalysis, /PERFORM private_isg\.ensure_default\(NEW\.id\)/);
});

test('training create is attached to the page heading', () => {
  assert.match(training, /HStack \{[\s\S]*NovaText\(text: "Eğitimler", style: \.screenTitle\)[\s\S]*NovaButton\(label: "Eğitim Ekle"/);
  assert.match(training, /training\.add\.header/);
});

test('emergency team selection is optional', () => {
  assert.match(emergency, /Ekip eklemek isteğe bağlıdır/);
  assert.match(emergency, /case \.team: return true/);
  assert.doesNotMatch(emergency, /guard teamReady/);
});

test('appointment drill and company create use shared full-screen wizard feedback', () => {
  for (const source of [appointments, drills, company]) {
    assert.match(source, /NovaTaskHeader/);
    assert.match(source, /NovaTaskStickyActions/);
    assert.match(source, /NovaTaskSuccessView/);
  }
  assert.match(main, /novaFullScreenCover\(item: \$editor\)/);
  assert.match(main, /novaFullScreenCover\(isPresented: \$showingCreate\)/);
});
