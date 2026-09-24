#!/usr/bin/env python3
"""Rebuild/verify catalogue and its delivery manifest. No third-party packages or network."""
import argparse, hashlib, importlib.util, json, sys, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
CONTENT=ROOT/'content/isg/wizard'
ASSETS=ROOT/'App/WizardAssets/isg_wizard'
sys.dont_write_bytecode=True
sys.path.insert(0,str(CONTENT))
spec=importlib.util.spec_from_file_location('wizard_build',CONTENT/'build.py')
build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)
parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
with tempfile.TemporaryDirectory() as tmp:
 stage=Path(tmp);bundle=build.make(stage)
 assert len(bundle['questions'])<=15
 for category,entries in bundle['taxonomy'].items():
  ids=[x['id'] for x in entries]
  assert len(ids)==len(set(ids)),f'Duplicate {category} ID'
 for risk in bundle['risk_catalog']:
  assert 2<=len(risk['controls'])<=4
  assert isinstance(risk['potential_severe_harm'],bool)
 files={CONTENT/p.relative_to(stage):p.read_bytes() for p in stage.rglob('*') if p.is_file()}
 files[ASSETS/'isgada-catalog.json']=files[CONTENT/'data/bundle.json']
 for target,data in files.items():
  if args.check:
   if not target.exists() or target.read_bytes()!=data:raise SystemExit('Regenerate: '+str(target.relative_to(ROOT)))
  else:target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
tracked=[p for p in CONTENT.rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.name!='manifest.json']
tracked += list(ASSETS.glob('*.js'))+[ASSETS/'isgada-catalog.json']
manifest={'catalog_version':bundle['catalog_version'],'catalog_sha256':bundle['catalog_sha256'],'files':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(tracked)}}
manifest_data=(json.dumps(manifest,ensure_ascii=False,indent=2,sort_keys=True)+'\n').encode()
manifest_path=CONTENT/'manifest.json'
if args.check:
 if not manifest_path.exists() or manifest_path.read_bytes()!=manifest_data:raise SystemExit('Manifest differs; regenerate intentionally after changes.')
else:manifest_path.write_bytes(manifest_data)
print(json.dumps({'catalog':bundle['catalog_version'],'risks':len(bundle['risk_catalog']),'cards':len(bundle['cards']),'questions':len(bundle['questions']),'files':len(manifest['files']),'check':args.check}))
