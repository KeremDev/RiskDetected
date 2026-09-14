import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,readdirSync,mkdtempSync,cpSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {mergeCatalog} from '../localization_catalog_merge.mjs';
import {writeCatalogs} from '../migrate_swift_localization_catalogs.mjs';

test('catalog merge preserves every shipping key, value and metadata',()=>{
  for(const file of readdirSync(resolve(ROOT,'App/Localization')).filter(f=>f.endsWith('.xcstrings'))){
    const existing=JSON.parse(readFileSync(resolve(ROOT,'App/Localization',file),'utf8'));
    const generated={sourceLanguage:existing.sourceLanguage,version:'1.0',strings:{}};
    const merged=mergeCatalog(existing,generated);
    assert.deepEqual(merged,existing,file);
    assert.deepEqual(mergeCatalog(merged,generated),merged,'second run: '+file);
  }
});
test('generation fills missing locales but cannot replace human translations or plurals',()=>{
  const plural={localizations:{tr:{variations:{plural:{other:{stringUnit:{value:'%d kayıt'}}}}}}};
  const existing={sourceLanguage:'tr',version:'1.0',strings:{
    saved:{comment:'human reviewed',localizations:{en:{stringUnit:{value:'Saved',state:'translated'}}}},plural}};
  const generated={sourceLanguage:'tr',version:'1.0',strings:{saved:{comment:'machine draft',localizations:{en:{stringUnit:{value:'Wrong'}},tr:{stringUnit:{value:'Kaydedildi'}}}},fresh:{comment:'new key'}}};
  const result=mergeCatalog(existing,generated);
  assert.deepEqual(mergeCatalog(existing,{...generated,strings:{plural:{localizations:{tr:{stringUnit:{value:'bad'}}}}}}).strings.plural,plural);
  assert.deepEqual(result.strings.plural,existing.strings.plural);
  assert.equal(result.strings.saved.comment,'human reviewed');
  assert.equal(result.strings.saved.localizations.en.stringUnit.value,'Saved');
  assert.equal(result.strings.saved.localizations.tr.stringUnit.value,'Kaydedildi');
  assert.ok(result.strings.fresh);
  assert.deepEqual(mergeCatalog(result,generated),result);
  assert.equal(existing.strings.saved.localizations.tr,undefined,'input mutated');
});
test('invalid or mismatched existing catalogs fail before writing',()=>{
  assert.throws(()=>mergeCatalog({sourceLanguage:'en',strings:{}},{sourceLanguage:'tr',strings:{}}));
  assert.throws(()=>mergeCatalog({sourceLanguage:'tr',strings:[]},{sourceLanguage:'tr',strings:{}}));
});
test('the production writer uses the preserving merge',()=>{
  const source=readFileSync(resolve(ROOT,'scripts/migrate_swift_localization_catalogs.mjs'),'utf8');
  assert.match(source,/const merged = mergeCatalog\(existing, content\)/);
  assert.match(source,/JSON.stringify\(merged, null, 2\)/);
});
test('real catalog writer twice preserves shipping catalogs and is byte-idempotent',()=>{
  const directory=mkdtempSync(resolve(tmpdir(),'isg-catalog-merge-'));
  try {
    cpSync(resolve(ROOT,'App/Localization'),directory,{recursive:true});
    const files=readdirSync(directory).filter(f=>f.endsWith('.xcstrings'));
    const before=Object.fromEntries(files.map(file=>[file,JSON.parse(readFileSync(resolve(directory,file),'utf8'))]));
    const store=JSON.parse(readFileSync(resolve(ROOT,'localization/translations/ios-machine-draft.json'),'utf8'));
    writeCatalogs([],store,{directory});
    const first=Object.fromEntries(files.map(file=>[file,readFileSync(resolve(directory,file),'utf8')]));
    for(const file of files){
      const after=JSON.parse(first[file]);
      for(const [key,value] of Object.entries(before[file].strings)){
        assert.ok(Object.hasOwn(after.strings,key),file+':'+key);
        for(const [locale,translation] of Object.entries(value.localizations??{})){
          assert.deepEqual(after.strings[key].localizations[locale],translation,file+':'+key+':'+locale);
        }
      }
    }
    writeCatalogs([],store,{directory});
    for(const file of files)assert.equal(readFileSync(resolve(directory,file),'utf8'),first[file],file);
  } finally { rmSync(directory,{recursive:true,force:true}); }
});
