import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');

test('every Nova record writer invalidates account and company summaries',()=>{
  const writers=[
    'App/Services/Company/NovaModuleMutationJournal.swift',
    'App/Services/Company/NovaNonconformityService.swift',
    'App/Services/Company/NovaEquipmentCheckService.swift',
    'App/Services/Company/NovaDocumentTrackingService.swift',
    'App/Services/Company/NovaKatipService.swift',
    'App/Services/Company/NovaTrainingService.swift',
    'App/Services/Company/NovaTrainingSessionService.swift',
    'App/Services/Company/NovaPersonnelService.swift',
    'App/Services/Company/NovaDirectoryService.swift',
    'App/Services/Company/NovaRiskAssessmentService.swift',
    'App/Services/Company/NovaEducationService.swift',
    'App/Services/Company/NovaFileLibraryService.swift',
  ];
  for(const path of writers)
    assert.match(read(path),/NotificationCenter\.default\.post\(name: Notification\.Name\("isgada\.records\.changed"\), object: (?:identity\.userID|scope\.ownerID|intent\.scope\.ownerID)\)/,path);
});

test('both the root dashboard and open company page reload only for their account',()=>{
  const root=read('App/Views/Components/NovaPilotMainGate.swift');
  const company=read('App/Views/Components/NovaCompanyManagementGate.swift');
  assert.match(root,/publisher\(for: Notification\.Name\("isgada\.records\.changed"\)\)[\s\S]{0,180}?event\.object as\? UUID == identity\.userID[\s\S]{0,80}?listRevision = UUID\(\)/);
  assert.match(company,/publisher\(for: Notification\.Name\("isgada\.records\.changed"\)\)[\s\S]{0,180}?event\.object as\? UUID == scope\.ownerID[\s\S]{0,80}?summaryRevision = UUID\(\)/);
});
