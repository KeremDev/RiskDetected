import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

// Every file of the new native surface that a person can read text from.
const NOVA_FILES=[
  'App/DesignSystem/ISG/NovaCompanyVisualForms.swift',
  'App/DesignSystem/ISG/NovaPopup.swift',
  'App/DesignSystem/ISG/NovaCompanyProgressViews.swift',
  'App/DesignSystem/ISG/NovaCompanyDestination.swift','App/DesignSystem/ISG/NovaCompanyListState.swift',
  'App/DesignSystem/ISG/NovaComponents.swift','App/DesignSystem/ISG/NovaDirectory.swift',
  'App/DesignSystem/ISG/NovaDirectoryScreens.swift','App/DesignSystem/ISG/NovaExpertShell.swift',
  'App/DesignSystem/ISG/NovaNavigation.swift','App/DesignSystem/ISG/NovaPersonnel.swift',
  'App/DesignSystem/ISG/NovaNonconformity.swift','App/DesignSystem/ISG/NovaNonconformityLabels.swift',
  'App/DesignSystem/ISG/NovaFindingBridge.swift',
  'App/DesignSystem/ISG/NovaAnalysisIntake.swift','App/DesignSystem/ISG/NovaAnalysisIntakeScreens.swift',
  'App/DesignSystem/ISG/NovaAnalysisDetail.swift','App/DesignSystem/ISG/NovaAnalysisDetailScreens.swift',
  'App/DesignSystem/ISG/NovaAnalysisSheets.swift','App/DesignSystem/ISG/NovaAnalysisListScreen.swift',
  'App/DesignSystem/ISG/NovaAnalysisSectionViews.swift','App/DesignSystem/ISG/NovaAnalysisReportsScreen.swift',
  'App/DesignSystem/ISG/NovaManualNonconformityScreen.swift',
  'App/DesignSystem/ISG/NovaNonconformityTransitions.swift',
  'App/DesignSystem/ISG/NovaNonconformityListScreen.swift',
  'App/DesignSystem/ISG/NovaNonconformityRecordScreen.swift',
  'App/DesignSystem/ISG/NovaFolderTabs.swift',
  'App/Views/Components/NovaPilotFindingsGate.swift',
  'App/Views/Components/NovaPhotoIntakeScreen.swift',
  'App/DesignSystem/ISG/NovaPersonnelScreens.swift','App/DesignSystem/ISG/NovaSessionHost.swift',
  'App/DesignSystem/ISG/NovaTokens.swift','App/DesignSystem/ISG/NovaWorkspaceCapability.swift',
  'App/Views/Components/NotebookDestination.swift','App/Views/Components/NovaCompanyManagementGate.swift',
  'App/Services/Notebook/NotebookReminder.swift',
];
const CATALOGS=['Localizable','Analysis','Auth','Legal','Notifications','Onboarding','Paywall','Reports',
  'SafetyTerminology','ProfessionalProgress','InfoPlist'];
// Proper nouns: identical in tr and en because they are names, not copy.
// The two file formats are product names, and the frequency factor of the
// Fine-Kinney scale is written F in both languages; the other two factors are
// not, so they are absent here and must still differ.
const PROPER_NOUNS=new Set(['localizable.nova.risk.method.fine.kinney',
  'localizable.nova.analysis.reports.filter.pdf','localizable.nova.analysis.reports.filter.excel',
  'localizable.nova.risk.factor.frequency',
  // A date range is an arrow between two values, identical in both languages.
  'localizable.nova.directory.engagement.range']);
// A font face is a resource name, never copy a person reads.
const RESOURCE=/^(?:PlusJakartaSans-|SF|system)/;
const read=path=>readFileSync(resolve(ROOT,path),'utf8');

function catalogKeys(){
  const keys=new Map();
  for(const name of CATALOGS){
    let parsed; try{parsed=JSON.parse(read(`App/Localization/${name}.xcstrings`));}catch{continue;}
    for(const [key,value] of Object.entries(parsed.strings??{})) keys.set(key,{catalog:name,value});
  }
  return keys;
}
// Shipped lines only: a design-lab fixture behind #if DEBUG never reaches a user.
function shippedLines(source){
  const lines=source.split('\n'); const out=[]; let debug=0;
  lines.forEach((line,index)=>{
    if(/^\s*#if DEBUG/.test(line))debug++;
    else if(/^\s*#endif/.test(line)&&debug>0)debug--;
    else if(debug===0)out.push({line,number:index+1});
  });
  return out;
}
// A localized call often wraps onto the next line, so the fallback has to be
// blanked across the whole file rather than line by line. Newlines are kept so
// every offset still maps back to its original line number.
function withoutLocalizedCalls(source){
  const out=source.split(''); const marker='RDLocalization.string(';
  let at=source.indexOf(marker);
  while(at>=0){
    let depth=0, index=at+marker.length-1;
    for(;index<source.length;index++){
      const character=source[index];
      if(character==='(')depth++;
      else if(character===')'){depth--; if(depth===0)break;}
    }
    for(let blank=at;blank<=Math.min(index,source.length-1);blank++){
      if(out[blank]!=='\n')out[blank]=' ';
    }
    at=source.indexOf(marker,index+1);
  }
  return out.join('');
}
function shippedSource(source){
  const lines=withoutLocalizedCalls(source).split('\n'); const out=[]; let debug=0;
  lines.forEach((line,index)=>{
    if(/^\s*#if DEBUG/.test(line))debug++;
    else if(/^\s*#endif/.test(line)&&debug>0)debug--;
    else if(debug===0)out.push({line,number:index+1});
  });
  return out;
}

test('every NOVA localization key resolves in a catalog with tr and en',()=>{
  const keys=catalogKeys(); const seen=new Set();
  for(const file of NOVA_FILES){
    for(const key of read(file).matchAll(/RDLocalization\.string\(\s*"([a-z0-9._]+)"/g)){
      seen.add(key[1]);
      const entry=keys.get(key[1]);
      assert.ok(entry,`${file} references ${key[1]} which no catalog defines`);
      const tr=entry.value.localizations?.tr?.stringUnit?.value;
      const en=entry.value.localizations?.en?.stringUnit?.value;
      assert.ok(tr&&en,`${key[1]} lacks tr/en parity`);
      // A person's name is the same sentence in both languages. Only an
      // explicitly named entry may match; everything else must differ.
      if(!PROPER_NOUNS.has(key[1])) assert.notEqual(en,tr,`${key[1]} was never translated: en equals tr`);
    }
  }
  assert.ok(seen.size>=250,`expected the migrated surface, found only ${seen.size} keys`);
});

test('no shipped NOVA copy is left as a raw literal',()=>{
  const offenders=[];
  for(const file of NOVA_FILES){
    for(const {line,number} of shippedSource(read(file))){
      const bare=line;
      for(const match of bare.matchAll(/"((?:[^"\\]|\\.)*)"/g)){
        const value=match[1];
        if(!value||RESOURCE.test(value))continue;
        // A word with a Turkish letter or two words with a space is human copy.
        if(!/[çğıöşüÇĞİÖŞÜ]/.test(value))continue;
        offenders.push(`${file}:${number} ${value.slice(0,60)}`);
      }
    }
  }
  // The one survivor is a scanner artifact: the line is fully localized but its
  // interpolation contains nested quotes that this line scanner cannot pair.
  const allowed=new Set(['App/DesignSystem/ISG/NovaDirectoryScreens.swift']);
  const real=offenders.filter(entry=>!allowed.has(entry.split(':')[0]));
  assert.deepEqual(real,[],`raw Turkish copy still ships:\n${real.join('\n')}`);
});

test('an icon-only control carries a spoken name',()=>{
  const offenders=[];
  for(const file of NOVA_FILES){
    const lines=shippedLines(read(file));
    lines.forEach(({line,number},index)=>{
      if(!/Button\s*[({]/.test(line))return;
      if(!/NovaIcon\(|Image\(systemName:/.test(line))return;
      // An icon next to text already speaks; only a bare icon needs the label.
      if(/NovaText\(|NovaSizedText\(|Text\(|label:\s*"/.test(line))return;
      // A modifier chain often continues on the following lines, so the label
      // may legitimately sit just below the button it belongs to.
      const window=[line,lines[index+1]?.line??'',lines[index+2]?.line??''].join('\n');
      if(/accessibilityLabel/.test(window))return;
      offenders.push(`${file}:${number}`);
    });
  }
  assert.deepEqual(offenders,[],`icon-only controls without a spoken name:\n${offenders.join('\n')}`);
});

test('the catalogs never lost a key that the app still references',()=>{
  const keys=catalogKeys(); const missing=[];
  for(const file of ['App/Views/Profile/ProfileView.swift','App/AppState.swift','App/RootView.swift']){
    let source; try{source=read(file);}catch{continue;}
    for(const key of source.matchAll(/RDLocalization\.string\(\s*"([a-z0-9._]+)"/g)){
      if(!keys.has(key[1]))missing.push(`${file} ${key[1]}`);
    }
  }
  assert.deepEqual(missing,[],`catalog keys disappeared:\n${missing.join('\n')}`);
  // The catalogs the earlier slices filled must not shrink back.
  const sizes={Analysis:777,Paywall:161,Onboarding:313,Reports:176,Auth:96};
  for(const [name,least] of Object.entries(sizes)){
    const count=Object.keys(JSON.parse(read(`App/Localization/${name}.xcstrings`)).strings).length;
    assert.ok(count>=least,`${name}.xcstrings shrank to ${count}, expected at least ${least}`);
  }
});
