#!/usr/bin/env python3
"""Independently validate the WRITTEN Markdown against the WRITTEN seed.
Usage: python validate_checklists.py --md path.md --seed path.json --report report.md
No database, internet, or third-party libraries are used.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument('--md',type=Path,required=True)
p.add_argument('--seed',type=Path,required=True)
p.add_argument('--report',type=Path,required=True)
a=p.parse_args()
raw=a.md.read_bytes()
text=raw.decode('utf-8')
lines=text.splitlines()
seed=json.loads(a.seed.read_text(encoding='utf-8'))
checks=[]
def check(label: str, condition: bool):
    checks.append((label, bool(condition)))
    if not condition: raise AssertionError(label)

# Parse human-readable headings and the ACTUAL answer-table rows, not the declared counts.
checklists=[]
current=None
sector=None
sector_heading_count=0
for line_number,line in enumerate(lines,1):
    if re.match(r'^## S\d{2}\. ',line):
        sector_heading_count+=1
        sector=line.split('. ',1)[1]
    elif line=='## Sektörler arası ek kontrol listeleri':
        sector=None
    m=re.match(r'^### ([A-Z]{3}-\d{2}) — (.+)$',line)
    if m:
        current={'code':m.group(1),'title':m.group(2),'sector':sector,'start_line':line_number,'rows':[]}
        checklists.append(current)
    if re.match(r'^\| \d+ \| `[A-Z]{3}-\d{2}-\d{2}` \|',line):
        check('Tablo satırı bir checklist başlığına bağlı',current is not None)
        cells=[c.strip() for c in line.strip().strip('|').split('|')]
        check('Her madde satırında 8 sütun var',len(cells)==8)
        current['rows'].append({'order':int(cells[0]),'code':cells[1].strip('`'),
           'question':cells[2],'method':cells[3],'boxes':cells[4:7],
           'note':cells[7],'line':line_number})
        current['end_line']=line_number

check('24 gerçek sektör başlığı',sector_heading_count==24)
check('200 gerçek checklist başlığı',len(checklists)==200)
check('192 sektör checklisti',sum(t['sector'] is not None for t in checklists)==192)
check('8 sektörler arası checklist',sum(t['sector'] is None for t in checklists)==8)
check('Checklist kodları tekil',len({t['code'] for t in checklists})==200)
sector_counts=Counter(t['sector'] for t in checklists if t['sector'])
check('Her sektörde tam 8 checklist',len(sector_counts)==24 and set(sector_counts.values())=={8})
check('Her checklistte tam 10 gerçek madde',all(len(t['rows'])==10 for t in checklists))
rows=[r for t in checklists for r in t['rows']]
check('2.000 gerçek madde satırı',len(rows)==2000)
check('Madde satırı kodları tekil',len({r['code'] for r in rows})==2000)
check('Soru metinleri boş değil, en az 20 karakter ve soru işaretiyle bitiyor',
      all(len(r['question'])>=20 and r['question'].endswith('?') for r in rows))
check('Madde metinlerinde yer tutucu yok',not any(re.search(r'\b(TODO|TBD|PLACEHOLDER)\b|madde eklenecek|buraya yazılacak|\.{3}',r['question'],re.I) for r in rows))
check('Her listede sıralama 1–10',all([r['order'] for r in t['rows']]==list(range(1,11)) for t in checklists))
check('Bir liste içinde soru metni tekrarı yok',all(len({r['question'] for r in t['rows']})==10 for t in checklists))
check('Her maddede üç boş cevap kutusu var',all(r['boxes']==['☐','☐','☐'] for r in rows))
check('Her maddede ayrı boş açıklama alanı var',all(r['note']=='' for r in rows))
check('Doğrulama kodları G/K/Y',all(r['method'] in {'G','K','Y'} for r in rows))
check('JSON ve Markdown liste sırası aynı',[t['code'] for t in checklists]==[t['template_code'] for t in seed['templates']])
for md,j in zip(checklists,seed['templates']):
    check(f'{md["code"]}: JSON–Markdown soru, sıra, yöntem, kimlik eşitliği',
          [(r['code'],r['order'],r['question'],r['method']) for r in md['rows']]==
          [(r['item_code'],r['order'],r['text_tr'],r['verification_method']) for r in j['items']])
    check(f'{md["code"]}: başlık ve sektör eşitliği',md['title']==j['title_tr'] and md['sector']==j['sector_name'])
atomics={r['atomic_item_code']:r for r in seed['atomic_items']}
sourceids={s['source_id'] for s in seed['sources']}
check('Her seed sorusunun atomik metni eşleşiyor',all(
 atomics[i['atomic_item_code']]['text_tr']==i['text_tr'] for t in seed['templates'] for i in t['items']))
check('Her sorunun kaynak kodu kayıtlı',all(
 set(i['source_ids'])<=sourceids for t in seed['templates'] for i in t['items']))
check('Tüm konu paketleri gerçekten bir listede kullanılmış',
 {t['pack_code'] for t in seed['templates']}=={x['code'] for x in seed['topic_packs']})
check('117 konu paketi, her birinde 10 soru',len(seed['topic_packs'])==117 and all(len(x['items'])==10 for x in seed['topic_packs']))
distinct=len({r['question'] for r in rows})
check('1.169 farklı metin ve aynı sayıda atomik kayıt',distinct==1169 and len(atomics)==1169)
check('Bütün kaynak bağlantıları Markdown içinde tanımlı',all(f'id="kaynak-{s.lower()}"' in text for s in sourceids))
check('Soru kaynak statüsü hukuki zorunluluk değil ürün taslağı',all(not x['legal_binding_claim'] and x['content_status']=='product_template' for x in atomics.values()))

# Internal links in the written Markdown must resolve.
anchors=set(re.findall(r'<a id="([^"]+)"></a>',text))
link_targets=set(re.findall(r'\]\(#([^)]+)\)',text))
check('İçindekiler ve bütün iç bağlantılar çözümleniyor',link_targets<=anchors)
sha=hashlib.sha256(raw).hexdigest()
seed_sha=hashlib.sha256(a.seed.read_bytes()).hexdigest()
summary={
 'result':'PASS','markdown_file':a.md.name,'markdown_bytes':len(raw),'markdown_lines':len(lines),
 'markdown_sha256':sha,'seed_file':a.seed.name,'seed_sha256':seed_sha,
 'sector_count':sector_heading_count,'sector_templates':192,'supplemental_templates':8,
 'templates':len(checklists),'visible_rows':len(rows),'distinct_question_texts':distinct,
 'topic_packs':117,'pack_item_occurrences':1170,'source_records':len(sourceids),
 'structural_assertions_passed':len(checks),
 'every_template_has_10':True,'no_placeholder_questions':True,
 'md_seed_question_equality':True,'domain_expert_approval':False,
 'checklists':[{k:t[k] for k in ['code','title','sector','start_line','end_line']}|{'item_count':len(t['rows'])} for t in checklists],
}
report=['# İSG Adası — Yazılmış kontrol listesi dosyasının doğrulama raporu','',
 '**Sonuç: GEÇTİ.** Bu rapor, son Markdown dosyasının başlıkları ve cevap tablo satırları yeniden okunarak üretildi; dosyanın kendi yazdığı toplam sayıya güvenilerek hazırlanmadı.','',
 f'Kontrol edilen dosya: `{a.md.name}`',f'Boyut: **{len(raw):,} bayt** · Satır: **{len(lines):,}**','',
 '| Denetim | Sonuç |','|---|---:|',
 '| Sektör sayısı | 24 |','| Her sektördeki gerçek checklist sayısı | 8 |',
 '| Sektörlere ait checklist | 192 |','| Sektörler arası ek checklist | 8 |',
 '| Toplam gerçek checklist | 200 |','| Her checklistte gerçek madde | 10 |',
 '| Toplam görünür madde satırı | 2.000 |','| Konu paketi | 117 |',
 '| Paketlerde madde kullanımı | 1.170 |','| Farklı soru metni | 1.169 |',
 '| Eksik sorulu checklist | 0 |','| Boş / yer tutucu soru | 0 |','| Mükerrer checklist veya satır kodu | 0 |',
 '| Markdown–JSON soru/sıra farkı | 0 |',f'| Geçen yapısal doğrulama | {len(checks)} |','',
 '**Sayıların anlamı:** Ortak konu paketleri farklı sektörlerde tekrar kullanılmaktadır. 2.000 görünür satırın tamamı birbirinden farklı metin değildir. Bir sektör içindeki sekiz checklist farklı konu paketidir.','',
 '**Bu raporun sınırı:** Sayım, metin varlığı, kimlik ve eşleşme kontrolüdür. Hukuki doğruluk, sahaya yeterlilik, uzman teknik onayı veya canlı uygulama testi yapıldığı anlamına gelmez.','',
 '## Sektör bazında fiziksel içerik sayımı','',
 '| Sektör | Checklist | Gerçek madde satırı | Her listede 10? |','|---|---:|---:|---|']
for s in seed['sectors']:
    ts=[t for t in checklists if t['sector']==s['name']]
    report.append(f'| {s["name"]} | {len(ts)} | {sum(len(t["rows"]) for t in ts)} | Evet |')
report+=['| Sektörler arası ek grup | 8 | 80 | Evet |','',
 '## Her checklistin dosyadaki gerçek konumu','',
 'Satır numaraları yukarıda adı ve SHA-256 özeti belirtilen Markdown içindir. Örneğin `DPO-02` forklift listesidir. MD dosyasında bu kodu aratınca başlık ve on soru birlikte bulunur.','',
 '| Kod | Checklist | Başlık satırı | Son madde satırı | Madde |','|---|---|---:|---:|---:|']
for t in checklists:
    report.append(f'| {t["code"]} | {t["title"]} | {t["start_line"]} | {t["end_line"]} | {len(t["rows"])} |')
report+=['','## Dosya özetleri','',f'`{a.md.name}` SHA-256:','',f'```text\n{sha}\n```','',
 f'`{a.seed.name}` SHA-256:','',f'```text\n{seed_sha}\n```','',
 '## Yeniden çalıştırma','',
 '```bash',f'python validate_checklists.py --md "{a.md.name}" --seed "{a.seed.name}" --report "{a.report.name}"','```','']
a.report.write_text('\n'.join(report),encoding='utf-8')
a.report.with_suffix('.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in summary.items() if k!='checklists'},ensure_ascii=False,indent=2))
