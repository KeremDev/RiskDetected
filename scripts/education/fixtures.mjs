import {readFileSync} from 'node:fs';
export const content=JSON.parse(readFileSync(new URL('../../content/education/tr-isg-2026-v1.json',import.meta.url)));
export function fixture(code='initial_very_hazardous') {
 const p=content.presets.find(x=>x.code===code);
 const topics=content.topics.map(t=>({code:t.code,group:t.group_code,title:t.legal_label,instruction_minutes:p.topic_instruction_minutes[t.code],method:'face_to_face',trainer_ids:['expert']}));
 topics.push(...p.group4.topics.map(t=>({code:t.local_key,group:'G4',title:t.title,instruction_minutes:t.instruction_minutes,method:'face_to_face',trainer_ids:['expert']})));
 let i=0,left=topics[0].instruction_minutes;const lessons=[];
 for(let n=0;n<p.minimum_lesson_units;n++) {let remaining=45,allocations=[];while(remaining>0){const m=Math.min(remaining,left);allocations.push({topic_code:topics[i].code,minutes:m});remaining-=m;left-=m;if(left===0&&i<topics.length-1)left=topics[++i].instruction_minutes;}lessons.push({id:`lesson-${n}`,starts_at:new Date(Date.UTC(2026,8,10,6+n)).toISOString(),instruction_minutes:45,break_minutes:15,allocations});}
 return {action:'save',expected_version:0,title:'Temel İSG Eğitimi',provider_name:'Test Uzman',notes:'',trainers:[{id:'expert',name:'Test Eğitici',title:'İş Güvenliği Uzmanı'}],scopes:[{id:'50000000-0000-0000-0000-000000000001',company_id:'10000000-0000-0000-0000-000000000001',workplace_id:'40000000-0000-0000-0000-000000000001',group_name:'Atölye',cycle:p.cycle,context_note:'Bu atölyenin pres, forklift ve tahliye riskleri',legal_name:'Test Firma',employer_name:'Test İşveren',employer_capacity:'employer',location:'Atölye',topics,lessons,participants:[{id:'30000000-0000-0000-0000-000000000001',job_title:'Bakım teknisyeni'}]}]};
}
