#!/usr/bin/env python3
"""AI/ağ bağlantısı olmadan V5 JSON ve katalog Markdown üretimi."""
from __future__ import annotations
import argparse, hashlib, importlib.util, json
from pathlib import Path
from source.site_labels_authoring import label as site_label
ROOT=Path(__file__).resolve().parent

def load_config():
 s=importlib.util.spec_from_file_location('authoring',ROOT/'source/config_authoring.py')
 m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m

def read_json(name): return json.loads((ROOT/'source'/name).read_text(encoding='utf-8'))
def dump(value):return json.dumps(value,ensure_ascii=False,indent=2,sort_keys=True)+'\n'
def rows(name,n):
 out=[]
 for line in (ROOT/'source'/name).read_text(encoding='utf-8').splitlines():
  if not line or line.startswith('#'):continue
  r=line.split('|')
  if len(r)!=n:raise ValueError(f'{name}: {r[0]} sütun sayısı {len(r)} != {n}')
  out.append(r)
 return out

LEGAL_TOPICS={
'TR6331':'6331 sayılı İş Sağlığı ve Güvenliği Kanunu',
'TR-RISK':'İş Sağlığı ve Güvenliği Risk Değerlendirmesi Yönetmeliği',
'TR-EQUIPMENT':'İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği',
'TR-CONSTRUCTION':'Yapı İşlerinde İş Sağlığı ve Güvenliği Yönetmeliği',
'TR-CHEMICAL':'Kimyasal Maddelerle Çalışmalarda Sağlık ve Güvenlik Önlemleri Hakkında Yönetmelik',
'TR-SCREEN':'Ekranlı Araçlarla Çalışmalarda Sağlık ve Güvenlik Önlemleri Hakkında Yönetmelik',
'TR-NOISE':'Çalışanların Gürültü ile İlgili Risklerden Korunmalarına Dair Yönetmelik',
'TR-VIBRATION':'Çalışanların Titreşimle İlgili Risklerden Korunmalarına Dair Yönetmelik',
'TR-BUILDINGS':'İşyeri Bina ve Eklentilerinde Alınacak Sağlık ve Güvenlik Önlemlerine İlişkin Yönetmelik',
'TR-FIREBUILD':'Binaların Yangından Korunması Hakkında Yönetmelik',
'TR-EMERGENCY':'İşyerlerinde Acil Durumlar Hakkında Yönetmelik',
'TR-FIRSTAID':'İlkyardım Yönetmeliği',
'TR-TRAINING2026':'Çalışanların İş Sağlığı ve Güvenliği Eğitimlerinin Usul ve Esasları Hakkında Yönetmelik (02.04.2026)',
'TR-ATEX':'Çalışanların Patlayıcı Ortamların Tehlikelerinden Korunması Hakkında Yönetmelik',
'TR-PPE':'Kişisel Koruyucu Donanımların İşyerlerinde Kullanılması Hakkında Yönetmelik',
'TR-HANDLING':'Elle Taşıma İşleri Yönetmeliği',
'TR-BIO':'Biyolojik Etkenlere Maruziyet Risklerinin Önlenmesi Hakkında Yönetmelik',
'TR-ASBESTOS':'Asbestle Çalışmalarda Sağlık ve Güvenlik Önlemleri Hakkında Yönetmelik',
'TR-DUST':'Tozla Mücadele Yönetmeliği',
'TR-SIGNS':'Sağlık ve Güvenlik İşaretleri Yönetmeliği',
'TR-MINING':'Maden İşyerlerinde İş Sağlığı ve Güvenliği Yönetmeliği',
'TR-WORKTIME':'4857 sayılı İş Kanunu ve uygulanabilir çalışma süresi düzenlemeleri',
'TR-PREGNANT':'Gebe veya Emziren Kadınların Çalıştırılma Şartlarıyla Emzirme Odaları ve Çocuk Bakım Yurtlarına Dair Yönetmelik',
'TR-YOUNG':'Çocuk ve Genç İşçilerin Çalıştırılma Usul ve Esasları Hakkında Yönetmelik',
'TR-RADIATION':'Nükleer Düzenleme Kurumu düzenlemeleri — uygulamaya özgü yetkilendirme kapsamı',
'TR-TRAFFIC':'2918 sayılı Karayolları Trafik Kanunu ve ilgili düzenlemeler',
'TR-KVKK':'6698 sayılı Kişisel Verilerin Korunması Kanunu'
}
FAMILY_TOPICS={
 'G01':['TR-BUILDINGS'], 'G02':['TR-EQUIPMENT','TR-BUILDINGS'],
 'G03':['TR-EQUIPMENT'],'G04':['TR-EQUIPMENT','TR-PPE'],
 'G05':['TR-CONSTRUCTION','TR-EQUIPMENT'],'G06':['TR-CONSTRUCTION','TR-EQUIPMENT'],
 'G07':['TR-EQUIPMENT'],'G08':['TR-EQUIPMENT'],'G09':['TR-TRAFFIC','TR-EQUIPMENT'],
 'G10':['TR-BUILDINGS','TR-EQUIPMENT'],'G11':['TR-EQUIPMENT'],'G12':['TR-CHEMICAL','TR-EMERGENCY'],
 'G13':['TR-CONSTRUCTION'],'G14':['TR-CONSTRUCTION','TR-ASBESTOS'],
 'G15':['TR-FIREBUILD','TR-CHEMICAL'],'G16':['TR-EQUIPMENT'],'G17':['TR-CHEMICAL','TR-EQUIPMENT'],
 'G18':['TR-CHEMICAL'],'G19':['TR-CHEMICAL','TR-ATEX'],'G20':['TR-FIREBUILD','TR-EMERGENCY'],
 'G21':['TR-ATEX'],'G22':['TR-DUST','TR-CHEMICAL'],'G23':['TR-NOISE','TR-VIBRATION','TR-BUILDINGS'],
 'G24':['TR-HANDLING','TR-SCREEN'],'G25':['TR-BIO'],'G26':['TR-WORKTIME'],
 'G27':['TR-TRAINING2026','TR-EQUIPMENT'],'G28':['TR-YOUNG','TR-PREGNANT','TR-EMERGENCY'],
 'G29':['TR-EQUIPMENT','TR-DUST','TR-CHEMICAL'],'G30':['TR-EQUIPMENT','TR-CHEMICAL'],
 'G31':['TR-EQUIPMENT','TR-CHEMICAL'],'G32':['TR-EQUIPMENT','TR-DUST','TR-ATEX'],
 'G33':['TR-EQUIPMENT','TR-CHEMICAL'],'G34':['TR-EQUIPMENT','TR-CHEMICAL'],
 'G35':['TR-BIO','TR-CHEMICAL'],'G36':['TR-CHEMICAL','TR-BIO'],
 'G37':['TR-EQUIPMENT','TR-CHEMICAL'],'G38':['TR-MINING'],
 'G39':['TR-EQUIPMENT'],'G40':['TR-BIO','TR-CHEMICAL'],'G41':['TR-BUILDINGS','TR-CHEMICAL'],
 'G42':['TR-SCREEN','TR-BUILDINGS'],'G43':['TR-CONSTRUCTION'],
 'G44':['TR-EQUIPMENT','TR-CHEMICAL'],'G45':['TR-EQUIPMENT','TR-CHEMICAL'],
 'G46':['TR-EQUIPMENT','TR-CHEMICAL'],'G47':['TR-EQUIPMENT','TR-EMERGENCY'],
 'G48':['TR-TRAFFIC','TR-BIO'],'G49':['TR-EMERGENCY','TR-FIREBUILD','TR-TRAINING2026'],
 'G50':['TR-EQUIPMENT'],'G51':['TR-EQUIPMENT','TR-BUILDINGS','TR-FIRSTAID','TR-FIREBUILD'],
 'G52':['TR-TRAFFIC','TR-EQUIPMENT','TR-PPE','TR-WORKTIME']
}
HIERARCHY={'elimination':'Ortadan kaldırma','substitution':'İkame','engineering':'Mühendislik/toplu koruma',
'administrative':'İdari düzenleme','ppe':'Kişisel koruyucu donanım'}

def make_methods():
 specs={
 'fk':([20,70,200,400,None],['Önemsiz','Olası risk','Önemli risk','Yüksek risk','Tolerans dışı'],
 ['İzleme yeterli','Gözetim altında izle','Düzeltici plan gerekli','Kısa vadede önlem','Çalışma derhal durdurulmalı']),
 'm5':([2,4,9,19,25],['Önemsiz','Düşük risk','Orta risk','Yüksek risk','Tolerans dışı'],
 ['İzleme yeterli','Gözetim altında izle','Plan dahilinde önlem','En kısa sürede önlem','Çalışma derhal durdurulmalı'])}
 methods={}
 for method,(upper,labels,actions) in specs.items():
  bands=[];lower=0
  for i,(hi,label,act) in enumerate(zip(upper,labels,actions)):
   bands.append({'code':f'{method}_b{i+1}','lower_exclusive':lower,'upper_inclusive':hi,
   'label_tr':label,'action_tr':act,'display_level':['low','low','medium','high','critical'][i],
   'color_token':['rdLow','rdLow','rdMedium','rdHigh','rdCritical'][i],
   'deadline_policy_code':['monitor','monitor','planned','urgent','stop_exposure'][i],
   'deadline_is_legal_period':False})
   lower=hi
  methods[method]={'id':f'isgada.{method}.2026.2','version':2,'bands':bands,'normative_status':'product_profile_not_statutory_scale',
  'score_origin_default':'unscored','factors':{'p':[0.2,0.5,1,3,6,10],'f':[0.5,1,2,3,6,10],'s':[1,3,7,15,40,100]} if method=='fk' else {'p':[1,2,3,4,5],'s':[1,2,3,4,5]}}
 return methods

def make(output:Path):
 c=load_config();(output/'data').mkdir(parents=True,exist_ok=True)
 enrich={r[0]:r[1:] for r in rows('enrichment.tsv',5)}
 risk=[]
 for old in read_json('risk_v3_input.json'):
  harm,l1,l2,second=enrich[old['id']]
  controls=[{'id':old['id']+'-C1','hierarchy':l1,'text_tr':old['specific_control_tr'].rstrip('.')+'.'},
            {'id':old['id']+'-C2','hierarchy':l2,'text_tr':second}]
  risk.append({'id':old['id'],'family_id':old['family_id'],'context_tr':old['hazard_context_tr'],
  'scenario_tr':old['possible_event_tr'],'consequences_tr':harm,'controls':controls,
  'suggested_owner_role_tr':old['suggested_responsible_role'],'content_version':4})
 for rid,fam,ctx,event,harm,owner,l1,a1,l2,a2 in rows('additions.tsv',10):
  risk.append({'id':rid,'family_id':fam,'context_tr':ctx,'scenario_tr':event,'consequences_tr':harm,
  'controls':[{'id':rid+'-C1','hierarchy':l1,'text_tr':a1},{'id':rid+'-C2','hierarchy':l2,'text_tr':a2}],
  'suggested_owner_role_tr':owner,'content_version':4})
 # Ağır zarar olasılığı puan değildir; yalnız kısa listenin kapsam önceliğidir.
 for r in risk:
  r.update({'potential_severe_harm':any(w in r['consequences_tr'].casefold() for w in ['ölüm','uzuv kaybı','kalıcı','çoklu']),
  'current_state':None,'score':None,'score_origin':'unscored','planned_residual':None,'verified_residual':None,
  'statement_kind':'possible_scenario_not_observation','legal_topic_ids':['TR6331','TR-RISK']+FAMILY_TOPICS[r['family_id']],
  'requires_any_features':c.RISK_REQUIRE_ANY.get(r['id'],[]),
  'family_requires_any_features':c.FAMILY_FEATURE_GATE.get(r['family_id'],[]),
  'review_status':'editorial_not_independent_expert_reviewed','dedup_key':r['id']})
  for control in r['controls']:
   if control['hierarchy'] not in HIERARCHY:raise ValueError(control)
   control['hierarchy_label_tr']=HIERARCHY[control['hierarchy']]
   # İşverenin yükümlülüğü devam eder; bu adlar kişi ataması değildir.
   control['suggested_executor_tr']=r['suggested_owner_role_tr'] if control['hierarchy']!='ppe' else 'Bölüm sorumlusu ve KKD tedarik sorumlusu'
 # Aile konu referansları ilgisiz alt satıra otomatik yığılmaz.
 precise_topics={
 'R-23-01':['TR-NOISE'],'R-23-02':['TR-NOISE'],'R-23-03':['TR-VIBRATION'],
 'R-23-04':['TR-BUILDINGS'],'R-23-05':['TR-BUILDINGS'],'R-23-06':['TR-BUILDINGS'],
 'R-23-07':['TR-BUILDINGS','TR-SCREEN'],'R-23-08':['TR-EQUIPMENT','TR-BUILDINGS'],
 'R-23-09':['TR-EQUIPMENT','TR-PPE'],'R-23-10':['TR-EQUIPMENT','TR-PPE'],
 'R-23-11':['TR6331'],'R-23-12':['TR-RADIATION'],
 'R-24-06':['TR-SCREEN'],
 'R-28-01':['TR-YOUNG','TR-TRAINING2026'],'R-28-02':['TR-PREGNANT','TR-CHEMICAL'],
 'R-28-03':['TR-PREGNANT','TR-HANDLING'],
 'R-28-04':['TR-EMERGENCY','TR-BUILDINGS'],'R-28-05':['TR-EMERGENCY','TR-SIGNS'],
 'R-28-06':['TR-EMERGENCY','TR-BUILDINGS'],'R-28-07':['TR-TRAINING2026'],
 'R-28-08':['TR-TRAINING2026'],'R-28-09':['TR6331'],'R-28-10':['TR6331'],
 'R-28-11':['TR-HANDLING'],'R-28-12':['TR-TRAINING2026'],
 'R-51-01':['TR-FIREBUILD','TR-EMERGENCY'],
 'R-51-02':['TR-EQUIPMENT','TR-BUILDINGS'],'R-51-03':['TR-EQUIPMENT','TR-BUILDINGS'],
 'R-51-04':['TR-EQUIPMENT','TR-BUILDINGS'],'R-51-05':['TR-FIRSTAID','TR-EMERGENCY'],
 'R-51-06':['TR-BUILDINGS'],'R-51-07':['TR-BUILDINGS'],
 'R-51-08':['TR-BUILDINGS'],'R-51-09':['TR-EQUIPMENT'],'R-51-10':['TR-EQUIPMENT'],
 'R-51-11':['TR-BUILDINGS','TR-CHEMICAL'],'R-51-12':['TR-FIRSTAID','TR-EMERGENCY']}
 executor_by_family={'G01':'Tesis teknik bakım görevlisi','G02':'Yetkili elektrik teknik personeli',
 'G03':'Makine bakım ve güvenlik teknik personeli','G07':'Kaldırma teknik sorumlusu',
 'G11':'Enerji izolasyonundan sorumlu teknik görevli','G16':'Basınçlı sistem teknik personeli',
 'G18':'Kimyasal proses teknik sorumlusu','G19':'Proses güvenliği teknik sorumlusu',
 'G23':'İş hijyeni/teknik tesis sorumlusu','G24':'İş istasyonu düzenleme sorumlusu',
 'G42':'Bina ve iş istasyonu teknik sorumlusu','G49':'Acil durum teknik altyapı sorumlusu',
 'G51':'İlgili güvenlik altyapısının teknik sorumlusu','G52':'Filo/operasyon teknik sorumlusu'}
 for r in risk:
  if r['id']=='R-19-05':r['family_requires_any_features']=['hazardous_chemicals','corrosives','flammable_liquids']
  if r['id'] in precise_topics:r['legal_topic_ids']=list(dict.fromkeys(['TR6331','TR-RISK']+precise_topics[r['id']]))
  r['legal_reference_scope']='topic_link_not_article_level_compliance_assertion'
  for control in r['controls']:
   if control['hierarchy']=='engineering':control['suggested_executor_tr']=executor_by_family.get(r['family_id'],r['suggested_owner_role_tr'])
 # Karşılığı olmayan kaynak fikrini özensizce bütün şirkete yaymayın.
 tax={}
 valid={r['id'] for r in risk}
 for kind,entries in read_json('taxonomy_v3_input.json').items():
  tax[kind]=[]
  for old in entries:
   ids=sorted((set(old['risk_ids'])-set(c.LEAF_REMOVE.get(old['id'],[])))|set(c.LEAF_ADD.get(old['id'],[])))
   if not set(ids)<=valid:raise ValueError(old['id'])
   tax[kind].append({'id':old['id'],'name_tr':old['name_tr'],'display_group':old['display_group'],
   'risk_ids':ids,'features':c.LEAF_FEATURES.get(old['id'],[]),'nace_code':None,
   'mapping_basis':'explicit_leaf_ids_plus_separate_feature_gates',
   'evidence_effect':'sector_typical_scope' if kind=='sectors' else 'declared_activity_not_control_effectiveness',
   'review_status':'editorial_not_independent_expert_reviewed'})
 # Gerçek ayrı seçenekler; önceki ID'ler değişmeden kalır.
 tax['sectors'].append({'id':'S181','name_tr':'Moto kurye / motosikletli dağıtım','display_group':'Dağıtım ve kurye',
 'risk_ids':[f'R-52-{i:02d}' for i in range(1,9)],'features':['motorcycle','vehicle','mobile_work'],
 'nace_code':None,'mapping_basis':'explicit_leaf_ids_plus_separate_feature_gates','evidence_effect':'sector_typical_scope',
 'review_status':'editorial_not_independent_expert_reviewed'})
 additions=[('E301','Taşınabilir yangın söndürücü','R-51-01',[]),('E302','İlkyardım dolabı/çantası','R-51-05',[]),
 ('E303','Kaçak akım koruma cihazı','R-51-04',[]),('E304','OED/AED','R-51-12',['oed_present']),
 ('E305','Otomatik sulu söndürme sistemi','R-20-10',['sprinkler','fire_water_system'])]
 for rid,name,rr,feats in additions:
  tax['equipment'].append({'id':rid,'name_tr':name,'display_group':'Ortak güvenlik altyapısı','risk_ids':[rr],
  'features':feats,'nace_code':None,'mapping_basis':'explicit_leaf_ids_plus_separate_feature_gates',
  'evidence_effect':'declared_activity_not_control_effectiveness','review_status':'editorial_not_independent_expert_reviewed'})
 extra_tasks=[('T241','Dönen parçaları yapay aydınlatmada izleme',['R-23-08'],['stroboscopic_rotating']),
 ('T242','Elektrik tesisatı periyodik kontrol ve bulgu takibi',['R-51-02'],['electrical_work']),
 ('T243','İlkyardım malzemesi kontrol ve tamamlama',['R-51-05'],[]),
 ('T244','Kaldırma ekipmanı periyodik kontrol takibi',['R-51-10'],['lifting']),
 ('T245','Basınçlı kap periyodik kontrol takibi',['R-51-09'],['pressure']),
 ('T246','Kirli iş giysisi ayırma ve soyunma',['R-51-11'],['changing_required'])]
 for rid,name,rr,feats in extra_tasks:
  tax['tasks'].append({'id':rid,'name_tr':name,'display_group':'Özel kontrol ve çalışma bağlamları',
  'risk_ids':rr,'features':feats,'nace_code':None,'mapping_basis':'explicit_leaf_ids_plus_separate_feature_gates',
  'evidence_effect':'declared_activity_not_control_effectiveness','review_status':'editorial_not_independent_expert_reviewed'})
 cards=[];extra={v[0]:v[1:] for v in rows('card_enrichment.tsv',8)}
 for old in read_json('cards_v3_input.json'):
  before,during,team,after,prohibited,reentry,fields=extra[old['id']]
  mode='MEDICAL_RESPONSE' if old['id'] in ['AD-023','AD-044','AD-052','AD-054','AD-055'] else old['mode']
  entry={'id':old['id'],'title_tr':old['title_tr'],'trigger_tr':old['trigger_tr'],'mode':mode,
  'mode_label_tr':c.MODES[mode],'core':old['id'] in c.CORE_CARDS,
  'requires_any_features':c.CARD_FEATURES.get(old['id'],[]),
  'before':before.split('~'),'during_worker':during.split('~'),'during_team':team.split('~'),
  'after':after.split('~'),'prohibited':prohibited.split('~'),'reentry_tr':reentry,
  'site_field_keys':fields.split('~'),'site_field_labels_tr':{k:site_label(k) for k in fields.split('~')},'content_version':4,'review_status':'editorial_site_adaptation_required',
  'source_scope':'original_editorial_synthesis_not_verbatim_standard','legal_topic_ids':['TR6331','TR-EMERGENCY']}
  if old['id']=='AD-069':entry['trigger_tr']='Tahliye alarmı, yetkili tahliye talimatı veya bulunduğu yerde kalmayı tehlikeli kılan olay.'
  if mode=='MEDICAL_RESPONSE':entry['legal_topic_ids'].append('TR-FIRSTAID')
  cards.append(entry)
 options={'areas':c.AREAS,'hazards':c.HAZARDS,'conditions':c.CONDITIONS,
 'method':{'fk':'Fine–Kinney','m5':'5×5 L-Tipi Matris'},'reuse':{'yes':'Kayıtları aktar','no':'Yalnız seçtiklerimi kullan'},
 'preset':{k:v['label_tr'] for k,v in c.PRESETS.items()}}
 questions=[{'id':qid,'field':field,'text_tr':text,'kind':kind,'help_tr':help,
 'required':False,'unknown_label_tr':'Bilmiyorum / sonra tamamlayacağım' if kind.startswith('multi_') else None,
 'empty_selection_means':'unknown_not_absent','children':[], 'max_initial_suggestions':8 if kind.startswith('multi_') else None}
 for qid,field,text,kind,help in c.QUESTIONS]
 legal={'id':'tr-numeric-reference-2026-09-24','status':'reference_arithmetic_not_compliance_verdict',
 'primary_text_chain_confirmed':False,'renewal_years':{'low':6,'medium':4,'high':2},
 'support_divisors':{'low':50,'medium':40,'high':30},
 'firstaid_divisors':{'low':20,'medium':15,'high':10},
 'combined_support_below':10,'distinct_person_minimum':None,
 'firstaid_amendment_date':'2025-12-27','training_regulation_date':'2026-04-02',
 'normative_release_enabled':False}
 bundle={'schema_version':4,'catalog_version':'isgada-v4.0-editorial','risk_catalog':risk,'taxonomy':tax,'cards':cards,
 'questions':questions,'options':options,'presets':c.PRESETS,'family_names':c.FAMILY_NAMES,
 'equivalence_groups':{'protective_earthing':['R-02-05','R-51-03']},
 'core_risk_ids':c.CORE_RISKS,'core_card_ids':c.CORE_CARDS,'area_risks':c.AREA_RISKS,
 'condition_risks':c.CONDITION_RISKS,'hazard_family_risks':c.HAZARD_FAMILY_RISKS,
 'feature_implications':{
 'oxygen':['compressed_gas'],'acetylene':['compressed_gas','flammable_gas'],
 'lpg':['compressed_gas','flammable_gas'],'nitrogen':['compressed_gas'],'co2':['compressed_gas'],
 'corrosives':['hazardous_chemicals'],'flammable_liquids':['hazardous_chemicals'],
 'peroxide_formers':['reactive_chemicals','hazardous_chemicals'],
 'water_reactive':['reactive_chemicals','hazardous_chemicals'],
 'oxidizers':['reactive_chemicals','hazardous_chemicals'],
 'pyrophoric':['reactive_chemicals','hazardous_chemicals'],
 'polymerizing':['reactive_chemicals','hazardous_chemicals'],
 'molten_glass':['glass'],'molten_metal':['foundry']},
 'methods':make_methods(),'modes':c.MODES,'legal_topics':LEGAL_TOPICS,'numeric_reference_rules':legal}
 # Versioned authoring extensions are data, never executable downloaded code.
 extensions=read_json('extensions.json')
 severity=read_json('severity.json')
 bundle['schema_version']=5
 bundle['catalog_version']=extensions['version']
 bundle['card_dependencies']=extensions['card_dependencies']
 bundle['roles']=extensions['roles']
 bundle['options'].update(extensions['extra_options'])
 bundle['options'].pop('reuse',None)
 bundle['feature_implications'].update(extensions['feature_implications'])
 for r in risk:
  r['potential_severe_harm']=severity[r['id']]
  r['owner_role_code']=extensions['family_roles'].get(r['family_id'],'operations')
  r['owner_role_detail_tr']=r['suggested_owner_role_tr']
  r['suggested_owner_role_tr']=extensions['roles'][r['owner_role_code']]
  r['content_version']=5
  r.pop('review_status',None)
  for ct in r['controls']:
   ct['hierarchy']=extensions['control_overrides'].get(r['id'],{}).get(ct['id'].split('-')[-1],ct['hierarchy'])
   ct['hierarchy_label_tr']=HIERARCHY[ct['hierarchy']]
   ct['suggested_executor_tr']=r['suggested_owner_role_tr']
 for entries in tax.values():
  for leaf in entries:
   leaf['aliases_tr']=extensions['aliases'].get(leaf['id'],[])
   leaf.pop('review_status',None)
 for card in cards:
  card.pop('review_status',None)
  card['content_version']=5
 # The digest identifies all content except its own digest field.
 bundle['catalog_sha256']=hashlib.sha256(json.dumps(bundle,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
 for name,value in [('bundle',bundle),('risk_catalog',risk),('taxonomy',tax),('emergency_cards',cards),
 ('questions',questions),('method_profiles',bundle['methods']),('legal_topics',LEGAL_TOPICS),('numeric_reference_rules',legal)]:
  (output/'data'/f'{name}.json').write_text(dump(value),encoding='utf-8')
 risk_md=['# Risk maddeleri — V5\n',f'{len(risk)} ayrı kayıt; her birinde olası zarar ve kayıt-özel kontroller vardır. Bunlar saha tespiti değildir. Puanlar, mevcut kontrol ve atanmış kişi otomatik uydurulmaz.\n']
 for r in risk:
  risk_md += [f"## {r['id']} — {r['scenario_tr']}\n",f"**Bağlam:** {r['context_tr']}  \n**Olası zarar:** {r['consequences_tr']}  \n**Önerilen sorumlu rol:** {r['suggested_owner_role_tr']}\n"]
  for ct in r['controls']:risk_md.append(f"- **{ct['hierarchy_label_tr']}:** {ct['text_tr']}")
  risk_md.append('\nKonu dayanakları: '+', '.join(r['legal_topic_ids'])+'. Sayısal kural veya uygunluk hükmü değildir.\n')
 (output/'06_RISK_KATALOGU.md').write_text('\n'.join(risk_md),encoding='utf-8')
 card_md=['# Acil durum eylem kartları — V5\n','72 özgün olay kartı. Her kartta 2 hazırlık, 3 genel çalışan, 3 görevli ekip ve 2 olay sonrası adım bulunur. Yer bilgisi uydurulmaz; belirtilen alanlar kayıtlı plandan alınır veya boş bırakılır.\n']
 for r in cards:
  card_md.extend([f"## {r['id']} — {r['title_tr']}\n",f"**Tetikleyici:** {r['trigger_tr']}  \n**Birincil hareket:** {r['mode_label_tr']}\n"])
  for key,title in [('before','Önce'),('during_worker','Sırasında — herkes'),('during_team','Sırasında — görevli/eğitimli ekip'),('after','Sonrasında'),('prohibited','Yapılmayacaklar')]:
   card_md.append(f'### {title}\n');card_md.extend(f'{i+1}. {s}' for i,s in enumerate(r[key]));card_md.append('')
  card_md.extend([f"**Geri giriş / hizmete dönüş:** {r['reentry_tr']}\n",'**Saha alanları:** '+', '.join(r['site_field_labels_tr'][key] for key in r['site_field_keys'])+'\n'])
 (output/'07_ACIL_DURUM_KARTLARI.md').write_text('\n'.join(card_md),encoding='utf-8')
 taxmd=['# Taksonomi ve açık eşlemeler — V5\n','Risk kimlikleri aday içeriktir; özellik koşulları ayrıca uygulanır. Sayısı kadar bağımsız doğrulanmış sektör raporu olduğu anlamına gelmez. NACE kodu tahmin edilmez.\n']
 for kind,entries in tax.items():
  taxmd += [f'## {kind} — {len(entries)} seçenek\n','| Kimlik | Seçenek | Özellikler | Aday risk kimlikleri |','|---|---|---|---|']
  for x in entries:taxmd.append('| '+' | '.join([x['id'],x['name_tr'],', '.join(x['features']),', '.join(x['risk_ids'])])+' |')
 (output/'08_TAKSONOMI_VE_ESLEMELER.md').write_text('\n'.join(taxmd)+'\n',encoding='utf-8')
 return bundle

def main():
 p=argparse.ArgumentParser();p.add_argument('--out',type=Path,default=ROOT);p.add_argument('--check',action='store_true');a=p.parse_args()
 if a.check:
  import tempfile
  with tempfile.TemporaryDirectory() as tmp:
   out=Path(tmp);make(out);wrong=[]
   for file in out.rglob('*'):
    if file.is_file():
     target=a.out/file.relative_to(out)
     if not target.exists() or target.read_bytes()!=file.read_bytes():wrong.append(str(file.relative_to(out)))
   if wrong:raise SystemExit('Yeniden üretim farkı: '+', '.join(wrong))
  print('JSON ve katalog Markdown yeniden üretimi: aynı')
 else:
  b=make(a.out);print(json.dumps({'risk_records':len(b['risk_catalog']),'cards':len(b['cards']),'questions':len(b['questions'])}))
if __name__=='__main__':main()
