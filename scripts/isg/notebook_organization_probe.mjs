import { randomUUID } from 'node:crypto';
export async function probeNotebookOrganization({request,waitReady,pass,foreignNote}) {
  const mark=(name,ok)=>pass('notebook_organization_'+name,ok);
  const note=randomUUID(),mutation=randomUUID(),item={item_id:randomUUID(),text:'Kişisel yapılacak',done:false};
  const read=(id=note,options={})=>request('/rpc/isg_notebook_organization_v1',{method:'POST',body:{p_note:id},...options});
  const write=(body,options={})=>request('/rpc/isg_notebook_organize_v1',{method:'POST',body,...options});
  await waitReady(()=>read().body?.message==='ACCESS_DENIED');
  request('/rpc/isg_notebook_mutate_v1',{method:'POST',body:{p_mutation:randomUUID(),p_note:note,p_action:'sync',p_expected:0,p_title:'Organization',p_body:'Private',p_conflict:null}});
  const intent={p_mutation:mutation,p_note:note,p_expected:1,p_items:[item],p_tags:['Kişisel','  Todo  ']};
  const response=write(intent);
  mark('atomic_items_and_tags',response.status===200&&response.body.state==='organized'&&response.body.version===2&&read().body.items[0].text===item.text&&read().body.tags.includes('Todo'));
  mark('metadata_receipt_no_content',!JSON.stringify(response.body).includes(item.text));
  mark('exact_retry_replays',write(intent).body.replayed===true&&read().body.version===2);
  mark('changed_retry_rejected',write({...intent,p_tags:['Changed']}).body.message==='IDEMPOTENCY_CONFLICT');
  const next={...intent,p_mutation:randomUUID(),p_expected:2};
  for (const [name,patch] of [
    ['stale_version',{p_expected:1}],['unknown_nested_scope',{p_items:[{...item,company_id:randomUUID()}]}],
    ['duplicate_item',{p_items:[item,item]}],['bad_boolean',{p_items:[{...item,done:'true'}]}],
    ['blank_text',{p_items:[{...item,text:'  '}]}],['oversize_text',{p_items:[{...item,text:'a'.repeat(1001)}]}],
    ['duplicate_tag',{p_tags:['Todo',' todo ']}],['blank_tag',{p_tags:[' ']}],['bad_array',{p_tags:{label:'x'}}],
    ['oversize_tag',{p_tags:['a'.repeat(61)]}],['too_many_tags',{p_tags:Array.from({length:31},(_,i)=>String(i))}],
  ]) {
    const result=write({...next,...patch});
    mark(name+'_rejected_atomically',result.status>=400&&read().body.version===2&&read().body.items[0].done===false);
  }
  mark('foreign_read_denied',read(foreignNote).body.message==='ACCESS_DENIED');
  mark('foreign_write_denied',write({...next,p_note:foreignNote}).body.message==='ACCESS_DENIED');
  mark('anon_denied',read(note,{authorization:null}).status>=400&&write(next,{authorization:null}).status>=400);
  const done=write({...next,p_items:[{...item,done:true}],p_tags:[]});
  mark('check_and_detach_tags',done.body.version===3&&read().body.items[0].done===true&&read().body.tags.length===0);
  request('/rpc/isg_notebook_mutate_v1',{method:'POST',body:{p_mutation:randomUUID(),p_note:note,p_action:'delete',p_expected:3,p_title:null,p_body:null,p_conflict:null}});
  mark('tombstone_hides_metadata',read().body.tombstone===true&&read().body.items.length===0&&read().body.tags.length===0);
  mark('tombstone_rejects_edits',write({...next,p_mutation:randomUUID(),p_expected:4}).body.message==='NOTE_TOMBSTONED');
  return note;
}
