import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const models=read('App/DesignSystem/ISG/NovaChecklists.swift');
const screens=read('App/DesignSystem/ISG/NovaChecklistScreens.swift');
const runFlow=read('App/DesignSystem/ISG/NovaChecklistRunFlow.swift');
const startFlow=read('App/DesignSystem/ISG/NovaChecklistStartFlow.swift');
const listFlow=read('App/DesignSystem/ISG/NovaChecklistListFlow.swift');
const listEditor=read('App/DesignSystem/ISG/NovaChecklistListEditor.swift');
const designSources=[models,screens,runFlow,startFlow,listFlow,listEditor];
const service=read('App/Services/Company/NovaChecklistService.swift');
const adapter=read('App/Services/Company/NovaChecklistLiveAdapter.swift');
const gate=read('App/Views/Components/NovaPilotChecklistGate.swift');
const navigation=read('App/DesignSystem/ISG/NovaNavigation.swift');
const main=read('App/Views/Components/NovaPilotMainGate.swift');
const offline=read('App/Services/Company/NovaChecklistOfflineQueue.swift');
const approval=read('supabase/migrations/20260921133000_checklist_catalog_professional_approval.sql');
const findingDetail=read('supabase/migrations/20260921103829_checklist_nonconformity_detail_origin.sql');
const findingDetailPreservation=read('supabase/migrations/20260921134500_checklist_nonconformity_preserve_manual_detail.sql');
const nonconformityModel=read('App/DesignSystem/ISG/NovaNonconformity.swift');
const nonconformityList=read('App/DesignSystem/ISG/NovaNonconformityListScreen.swift');
const nonconformityRecord=read('App/DesignSystem/ISG/NovaNonconformityRecordScreen.swift');
const expertShell=read('App/DesignSystem/ISG/NovaExpertShell.swift');

test('the design layer never imports the SDK',()=>{
  for(const source of designSources) assert.doesNotMatch(source,/^import Supabase$/m);
  assert.match(adapter,/^import Supabase$/m);
});

test('controls and reusable lists are separate full-screen destinations',()=>{
  assert.match(screens,/NovaListHeading\(title: headingOverride \?\? "Kontroller"/);
  assert.match(screens,/NovaText\(text: "Kontrol Listeleri"/);
  assert.match(screens,/NovaChecklistListsScreen\(client: client/);
  assert.match(listFlow,/case ready, mine/);
  assert.match(listFlow,/"Hazır listeler" : "Listelerim"/);
  assert.doesNotMatch(listFlow,/Denetimler/);
  assert.equal((screens.match(/NovaButton\(label: "Yeni kontrol"/g)||[]).length,1);
  assert.doesNotMatch(screens,/novaPopup/);
});

test('the controls screen is searchable, filterable and uses compact rows',()=>{
  assert.match(screens,/placeholder: "Kontrol ara"/);
  assert.match(screens,/NovaChecklistRunFilterSheet/);
  assert.match(screens,/Picker\("Kontrol durumu"/);
  assert.match(screens,/NovaChecklistRunRow/);
  assert.match(screens,/"\\\(run\.answered\) \/ \\\(run\.expected\)"/);
  assert.match(screens,/ProgressView\(value: Double\(run\.answered\)/);
  assert.match(screens,/nonconformitiesOpened > 0/);
});

test('loading, empty, error and offline states are explicit',()=>{
  assert.match(screens,/NovaChecklistRunSkeleton/);
  assert.match(screens,/Kontrol bilgileri yüklenemedi/);
  assert.match(screens,/Devam eden kontrol yok/);
  assert.match(screens,/Çevrimdışısınız/);
  assert.match(screens,/\.redacted\(reason: \.placeholder\)/);
});

test('the new-control flow is guided and full screen',()=>{
  assert.match(screens,/novaFullScreenCover\(isPresented: \$showingStart/);
  assert.match(startFlow,/private enum Step \{ case scope, list, details, information \}/);
  assert.match(startFlow,/Kontrol nerede yapılacak\?/);
  assert.match(startFlow,/Bağımsız kontrol/);
  assert.match(startFlow,/Kontrol listesini seç/);
  assert.match(startFlow,/placeholder: "Sektör, ekipman veya iş ara"/);
  assert.match(startFlow,/NovaFilterField\(label: "Sektör"/);
  assert.match(startFlow,/NovaFilterField\(label: "Liste türü"/);
  assert.match(startFlow,/NovaHelpHint\(text: "Sektör, ekipman, faaliyet veya tehlikeye göre arayın/);
  assert.match(startFlow,/Kontrol ayrıntıları/);
  assert.match(startFlow,/Saha ayrıntıları/);
  assert.match(startFlow,/safeAreaInset\(edge: \.bottom/);
  assert.match(startFlow,/"Kontrolü başlat"/);
  assert.doesNotMatch(startFlow,/novaPopup/);
});

test('field mode presents exactly one current question and one progress treatment',()=>{
  assert.match(runFlow,/private var currentAnswer: NovaChecklistAnswer\?/);
  assert.match(runFlow,/NovaText\(text: "Soru \\\(answer\.position\)"/);
  assert.equal((runFlow.match(/ProgressView\(value: Double\(run\.answered\)/g)||[]).length,1);
  assert.match(runFlow,/"\\\(run\.answered\) \/ \\\(run\.expected\)"/);
  assert.match(runFlow,/\.safeAreaInset\(edge: \.bottom, spacing: 0\) \{ answerBar\(answer\) \}/);
});

test('field answers are vertical, accessible and only allow not-applicable when permitted',()=>{
  const bar=runFlow.match(/private func answerBar\(_ answer:[\s\S]*?\n    \}/)[0];
  assert.match(bar,/NovaChecklistAnswerButton\(result: \.conform/);
  assert.match(bar,/NovaChecklistAnswerButton\(result: \.nonconform/);
  assert.match(bar,/if answer\.allowsNotApplicable/);
  assert.match(bar,/NovaChecklistAnswerButton\(result: \.notApplicable/);
  assert.match(runFlow,/frame\(maxWidth: \.infinity, minHeight: 48\)/);
  assert.match(runFlow,/accessibilityLabel\("Bu soruyu/);
});

test('answer history, previous and next navigation remain available',()=>{
  assert.match(runFlow,/case \.answers: answersPage/);
  assert.match(runFlow,/NovaText\(text: "Yanıtlar \\\(run\.answered\)"/);
  assert.match(runFlow,/Label\("Önceki", systemImage: "chevron\.left"\)/);
  assert.match(runFlow,/"Özete git" : "Sonraki"/);
  assert.match(runFlow,/currentIndex = index[\s\S]*?page = \.question/);
});

test('a conforming answer advances after a short confirmation delay',()=>{
  assert.match(runFlow,/saveDirect\(answer, result: \.conform\)/);
  assert.match(runFlow,/Task\.sleep\(nanoseconds: 350_000_000\)/);
  assert.match(runFlow,/if currentIndex < orderedAnswers\.count - 1/);
});

test('a failing answer opens a dedicated nonconformity flow',()=>{
  assert.match(runFlow,/openNonconformity\(answer\)/);
  assert.match(runFlow,/NovaChecklistNonconformityScreen/);
  assert.match(runFlow,/editor\(title: "Açıklama \*"/);
  assert.match(runFlow,/draft\.photoRequired \? "Fotoğraf ekle \*"/);
  assert.match(runFlow,/@State private var selectedSeverity: NovaChecklistSeverity\?/);
  assert.match(runFlow,/&& \(companyName == nil \|\| severity != nil\)/);
  assert.match(runFlow,/editor\(title: "Düzeltme önerisi"/);
  assert.match(runFlow,/"Kaydet ve devam et"/);
  assert.doesNotMatch(runFlow,/@State private var selectedSeverity: NovaChecklistSeverity =/);
});

test('not-applicable has its own reason step',()=>{
  assert.match(runFlow,/NovaChecklistNotApplicableScreen/);
  assert.match(runFlow,/Neden uygulanamaz\? \*/);
  assert.match(runFlow,/isEnabled: !draft\.note\.trimmingCharacters/);
});

test('notes and evidence are secondary actions and evidence stays separate',()=>{
  assert.match(runFlow,/secondaryActions\(answer\)/);
  assert.match(runFlow,/"Not ekle"/);
  assert.match(runFlow,/"Fotoğraf ekle"/);
  assert.match(runFlow,/IsgWorkspaceInlineAttachmentField/);
  assert.match(service,/evidence_asset_id/);
  assert.match(service,/draft\.result == \.nonconform && draft\.openNonconformity/);
  assert.match(gate,/NovaFileLibraryService\.live\(\)\.file/);
});

test('exit saves progress while cancellation is a separate destructive flow',()=>{
  assert.match(runFlow,/Kontrolden çıkmak istiyor musunuz\?/);
  assert.match(runFlow,/Cevaplarınız kaydedildi/);
  assert.match(runFlow,/private var cancelPage/);
  assert.match(runFlow,/İptal nedeni \*/);
  assert.match(runFlow,/variant: \.danger/);
  assert.match(runFlow,/failure = await onCancel\(\)/);
});

test('completion always passes through summary and result screens',()=>{
  assert.match(runFlow,/else if run\.remaining == 0 \{ page = \.summary \}/);
  assert.match(runFlow,/Kontrol tamamlanmaya hazır/);
  assert.match(runFlow,/summaryRow\("Uygunsuzluk kaydı"/);
  assert.match(runFlow,/isEnabled: run\.remaining == 0/);
  assert.match(runFlow,/guard run\.remaining == 0 else \{ return \}/);
  assert.match(runFlow,/Kontrol tamamlandı/);
  assert.match(runFlow,/Raporu görüntüle/);
  assert.match(runFlow,/Kontrollerime dön/);
});

test('technical run information is moved off the primary question screen',()=>{
  assert.match(runFlow,/case \.information: informationPage/);
  assert.match(runFlow,/taskHeader\(title: "Kontrol bilgileri"/);
  assert.match(runFlow,/informationRow\("Liste sürümü"/);
  assert.match(runFlow,/informationRow\("Kaynaklar"/);
});

test('ready lists use visible search, short filters, simple rows and a full-screen detail',()=>{
  assert.match(listFlow,/placeholder: "Sektör, ekipman veya iş ara"/);
  assert.match(listFlow,/NovaChecklistLibraryFilterSheet/);
  assert.match(listFlow,/activeFilterCount/);
  assert.match(listFlow,/private func libraryRow/);
  assert.match(listFlow,/NovaChecklistTemplateDetailScreen/);
  assert.match(listFlow,/novaFullScreenCover\(isPresented: detailPresentation/);
  assert.doesNotMatch(listFlow,/Kaynak ve sürüm bilgileri/);
  assert.match(listFlow,/Bu listeyle kontrol başlat/);
  assert.doesNotMatch(listFlow,/novaPopup/);
});

test('catalogue searches react while typing and professional approval is explicit',()=>{
  assert.match(listFlow,/\.task\(id: search\)/);
  assert.match(listEditor,/\.task\(id: query\)/);
  assert.match(listFlow,/Uzmanlık alanı incelemesi tamamlandı/);
  assert.match(approval,/professional_review_status='approved'/);
  assert.match(approval,/publication_status='pilot_approved'/);
  assert.match(approval,/CHECKLIST_APPROVAL_INCOMPLETE/);
});

test('my lists has full-screen create and edit flows',()=>{
  assert.match(listFlow,/NovaChecklistCreateListScreen/);
  assert.match(listFlow,/NovaChecklistMyListEditorScreen/);
  assert.match(listFlow,/"Yeni liste"/);
  assert.match(listEditor,/Hazır maddelerden seç/);
  assert.match(listEditor,/Kendi sorunu yaz/);
  assert.match(listEditor,/Listeyi yayımla/);
  assert.match(listEditor,/client\.copyItems/);
  assert.match(listEditor,/client\.reorderItems/);
  assert.match(adapter,/DUPLICATE_CHECKLIST_ITEM/);
});

test('checklist findings retain their real observation and show their origin',()=>{
  assert.match(findingDetail,/set_nonconformity_detail\(record_id,p_note/);
  assert.match(findingDetail,/WHERE n\.source_kind='checklist'/);
  assert.match(findingDetailPreservation,/SELECT \* INTO detail FROM private_isg\.nonconformity_details/);
  assert.match(findingDetailPreservation,/detail\.control_measure,detail\.legislation_ref,detail\.responsible_contact/);
  assert.match(nonconformityModel,/case "checklist": return RDLocalization\.string\("localizable\.nova\.nonconformity\.source\.checklist"/);
  assert.match(nonconformityList,/entry\.row\.sourceTitle/);
  assert.doesNotMatch(nonconformityList,/fact\("mappin", place\)/);
  assert.match(nonconformityRecord,/nonconformity\.detail\.edit/);
  assert.match(nonconformityRecord,/client\.saveDetail\(detail\)/);
  assert.match(nonconformityRecord,/current\.sourceTitle/);
});

test('the shared bottom navigation leaves the keyboard workspace entirely',()=>{
  assert.match(expertShell,/@StateObject private var keyboard = KeyboardObserver\(\)/);
  assert.match(expertShell,/if keyboard\.height == 0 \{/);
});

test('blank and completed checklists can be exported without formula cells',()=>{
  const exporter=read('App/DesignSystem/ISG/NovaChecklistExport.swift');
  assert.match(exporter,/static func pdf\(run:/);
  assert.match(exporter,/static func pdf\(template:/);
  assert.match(exporter,/static func xlsx\(run:/);
  assert.match(exporter,/static func xlsx\(template:/);
  assert.match(exporter,/t=\\"inlineStr\\"/);
  for(const sheet of ['Özet','Maddeler','Kaynaklar']) assert.ok(exporter.includes(sheet),sheet);
  assert.match(exporter,/autoFilter/);
  assert.ok(exporter.includes('state=\\"frozen\\"'));
  assert.doesNotMatch(exporter,/<f>/);
});

test('offline answers are device-only, replay in order and retain conflicts',()=>{
  assert.match(offline,/com\.riskdetected\.checklists\.pending\.v1/);
  assert.match(offline,/KeychainPersonnelPendingStorage/);
  assert.match(offline,/entries\[index\]\.conflict = true/);
  assert.match(offline,/expectedRevision = nextRevision/);
  assert.doesNotMatch(offline,/UserDefaults|iCloud|CloudKit/);
  assert.match(gate,/NovaChecklistOfflineQueue\.shared\.enqueue/);
  assert.match(screens,/NovaChecklistOptimisticAnswer\.apply/);
});

test('the shared expert screen supports company-free runs without company findings',()=>{
  assert.match(startFlow,/Bağımsız kontrol/);
  assert.match(models,/var isPersonal: Bool \{ companyID == nil \}/);
  assert.match(runFlow,/value\.openNonconformity = !run\.isPersonal/);
  assert.match(runFlow,/Bağımsız kontrolde firma uygunsuzluğu açılmaz/);
  assert.match(service,/company: UUID\?/);
});

test('every run mutation sends the server revision and submitted records revise instead of reopening',()=>{
  assert.match(service,/"expected_revision": \.number\(draft\.expectedRevision\)/);
  assert.match(service,/action: "revise_run"/);
  assert.match(runFlow,/Yeni doğrulama/);
  assert.match(adapter,/CHECKLIST_CONFLICT/);
});

test('the pinned version remains a fact about the run',()=>{
  assert.match(models,/let templateVersion: Int/);
  assert.match(runFlow,/informationRow\("Liste sürümü", "v\\\(run\.templateVersion\)"\)/);
});

test('every state carries a reason and every server refusal has a sentence',()=>{
  const explain=models.match(/static func explain\(_ run: NovaChecklistRun\) -> String \{[\s\S]*?\n    \}/)[0];
  for(const state of ['open','submitted','cancelled']) assert.ok(explain.includes(`case .${state}`),state);
  const cases=[...adapter.matchAll(/case "([A-Z_]+)"[^:]*: throw NovaChecklistFailure\.([a-zA-Z]+)/g)];
  const named=new Set(cases.map(match=>match[2]));
  for(const failure of ['runSubmitted','runIncomplete','templatePublished']) assert.ok(named.has(failure),failure);
  const messages=models.match(/var message: String \{[\s\S]*?\n    \}/)[0];
  for(const failure of named) assert.ok(messages.includes(`case .${failure}`),failure);
});

test('the route exists, is reachable and is wired to the real gate',()=>{
  assert.match(navigation,/case checklists/);
  assert.match(navigation,/case \.checklists: return RDLocalization\.string\("localizable\.nova\.navigation\.checklists"/);
  assert.match(navigation,/static let drawer: \[Self\] = \[[^\]]*\.checklists/);
  assert.match(main,/case \.checklists:\n\s+checklists/);
  assert.match(gate,/NovaChecklistScreen\(client: client/);
});
