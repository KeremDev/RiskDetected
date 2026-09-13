import {randomUUID,createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const fileCoreFiles=[
  'supabase/migrations/20260913130000_isg_file_core.sql',
  'scripts/isg/file_core_probe.mjs',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
const json=v=>quote(JSON.stringify(v))+'::jsonb';
const T0=Date.UTC(2026,8,13,12,0,0);
const at=seconds=>new Date(T0+seconds*1000).toISOString();
const digest=text=>createHash('sha256').update(text).digest('hex');

const MIB=1048576;
const matrix={company_document:{extensions:['pdf','doc','docx','xls','xlsx'],max:50*MIB},
  evidence_photo:{extensions:['jpg','jpeg','png','heic','heif','webp','avif'],max:50*MIB},
  structured_import:{extensions:['xls','xlsx','csv'],max:10*MIB},
  company_logo:{extensions:['jpg','jpeg','png','webp'],max:5*MIB}};
const allExtensions=['pdf','jpg','jpeg','png','heic','heif','webp','avif','doc','docx','xls','xlsx','csv'];

export async function beginFileCoreProbe({synthetic,sql,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_FILE_CORE_SYNTHETIC_REQUIRED');
  if(!companyID||!ownerID)throw Error('AUTH_RESTORE_FILE_CORE_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('file_core_'+name,ok);
  sql(read(fileCoreFiles[0]));
  mark('migration_applied',sql("SELECT count(*) FROM private_isg.rollout WHERE feature='file_core';")==='1');
  mark('rollout_defaults_off',sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='file_core';")==='t');

  sql(["CREATE SCHEMA isg_file_test;",
    "CREATE FUNCTION isg_file_test.observe(kind text,a jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $probe$",
    "DECLARE r jsonb; code text; BEGIN",
    "IF kind='accept' THEN r:=private_isg.file_acceptance(a->>'purpose',a->>'extension',(a->>'bytes')::bigint);",
    "ELSIF kind='open' THEN r:=private_isg.open_upload_intent((a->>'owner')::uuid,(a->>'company')::uuid,a->>'purpose',a->>'extension',(a->>'bytes')::bigint,decode(a->>'sha256','hex'),(a->>'operation')::uuid,(a->>'mutation')::uuid,(a->>'storage_limit')::bigint,(a->>'storage_unlimited')::boolean,(a->>'ttl')::integer,(a->>'now')::timestamptz);",
    "ELSIF kind='received' THEN r:=private_isg.mark_upload_received((a->>'intent')::uuid,(a->>'bytes')::bigint,decode(a->>'sha256','hex'),a->>'detected_type',(a->>'now')::timestamptz);",
    "ELSIF kind='scan' THEN r:=private_isg.record_scan_result((a->>'intent')::uuid,a->>'scanner',a->>'version',a->>'verdict',a->>'finding',decode(a->>'sha256','hex'),a->'evidence',(a->>'now')::timestamptz);",
    "ELSIF kind='promote' THEN r:=private_isg.promote_clean_upload((a->>'intent')::uuid,a->>'bucket',decode(a->>'sha256','hex'),(a->>'bytes')::bigint,(a->>'now')::timestamptz);",
    "ELSIF kind='reject' THEN r:=private_isg.reject_upload_intent((a->>'intent')::uuid,a->>'code',(a->>'now')::timestamptz);",
    "ELSIF kind='expire' THEN r:=to_jsonb(private_isg.expire_upload_intents((a->>'now')::timestamptz));",
    "ELSIF kind='derivative' THEN r:=private_isg.record_derivative((a->>'asset')::uuid,a->>'kind',a->>'renderer',a->>'state',a->>'path',(a->>'bytes')::bigint,a->>'failure',(a->>'now')::timestamptz);",
    "ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;",
    "RETURN jsonb_build_object('result',r);",
    "EXCEPTION WHEN SQLSTATE '23505' THEN RETURN jsonb_build_object('error','UNIQUE_VIOLATION');",
    "WHEN SQLSTATE '23514' THEN RETURN jsonb_build_object('error','CHECK_VIOLATION');",
    "WHEN SQLSTATE 'P0001' THEN GET STACKED DIAGNOSTICS code=MESSAGE_TEXT;",
    "IF code NOT IN ('FEATURE_UNAVAILABLE','VALIDATION_ERROR','ACCESS_DENIED','UNSUPPORTED_FORMAT','SIZE_LIMIT','IDEMPOTENCY_CONFLICT','CAPACITY_EXCEEDED') THEN RAISE; END IF;",
    "RETURN jsonb_build_object('error',code); END $probe$;"].join('\n'));
  const call=(kind,args)=>JSON.parse(sql("SELECT isg_file_test.observe("+quote(kind)+","+json(args)+");").split('\n').at(-1));
  const ok=(kind,args)=>{const r=call(kind,args);if(r.error)throw Error('AUTH_RESTORE_FILE_CORE_UNEXPECTED_'+r.error);return r.result;};

  const anyOpen={owner:ownerID,company:companyID,purpose:'company_document',extension:'pdf',bytes:1024,
    sha256:digest('gate'),operation:randomUUID(),mutation:randomUUID(),storage_limit:null,storage_unlimited:true,ttl:3600,now:at(0)};
  // The matrix is a pure policy read; only the write path is behind the rollout.
  mark('acceptance_matrix_reads_without_the_rollout',ok('accept',{purpose:'company_document',extension:'pdf',bytes:1024}).accepted===true);
  mark('gate_blocks_intent_while_rollout_off',call('open',anyOpen).error==='FEATURE_UNAVAILABLE');
  const privileges=sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC'); SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND NOT rowsecurity; SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('file_gate','file_acceptance','open_upload_intent','mark_upload_received','record_scan_result','promote_clean_upload','reject_upload_intent','expire_upload_intents','record_derivative','quota_ledger_open') AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE'));").split('\n');
  mark('file_tables_have_rls_and_no_client_grant',privileges[0]==='0'&&privileges[1]==='0'&&privileges[2]==='0');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='file_core';");

  // Every purpose/extension pair in the 13-format matrix, both directions.
  let acceptedPairs=0,rejectedPairs=0,boundaryOK=true;
  for(const [purpose,policy] of Object.entries(matrix)) {
    for(const extension of allExtensions) {
      const expected=policy.extensions.includes(extension);
      const verdict=ok('accept',{purpose,extension,bytes:1024});
      if(verdict.accepted!==expected||(!expected&&verdict.reason!=='UNSUPPORTED_FORMAT')){boundaryOK=false;}
      expected?acceptedPairs++:rejectedPairs++;
    }
    const sizes=[[0,false],[1,true],[policy.max-1,true],[policy.max,true],[policy.max+1,false]];
    for(const [bytes,expected] of sizes) {
      const verdict=ok('accept',{purpose,extension:policy.extensions[0],bytes});
      if(verdict.accepted!==expected||(!expected&&verdict.reason!=='SIZE_LIMIT'))boundaryOK=false;
    }
  }
  mark('purpose_matrix_accepts_and_rejects_every_pair',boundaryOK&&acceptedPairs===19&&rejectedPairs===33);
  mark('csv_is_import_only_and_heic_is_never_a_logo',ok('accept',{purpose:'structured_import',extension:'csv',bytes:1024}).accepted===true&&
    ok('accept',{purpose:'company_document',extension:'csv',bytes:1024}).accepted===false&&
    ok('accept',{purpose:'company_logo',extension:'heic',bytes:1024}).accepted===false&&
    ok('accept',{purpose:'evidence_photo',extension:'heic',bytes:1024}).accepted===true);
  mark('extension_case_is_normalized_but_unknown_purpose_is_refused',ok('accept',{purpose:'company_document',extension:'PDF',bytes:1024}).accepted===true&&
    ok('accept',{purpose:'personal_note',extension:'pdf',bytes:1024}).accepted===false);
  mark('candidate_size_limits_are_marked_unapproved',sql("SELECT bool_and(NOT limit_approved AND limit_source='v5_candidate') FROM private_isg.file_purposes;")==='t');

  const bytesOf=text=>Buffer.byteLength(text);
  const open=(over={})=>({owner:ownerID,company:companyID,purpose:'company_document',extension:'pdf',
    bytes:bytesOf('clean-document'),sha256:digest('clean-document'),operation:randomUUID(),mutation:randomUUID(),
    storage_limit:null,storage_unlimited:true,ttl:3600,now:at(0),...over});
  const happy=open();
  const intent=ok('open',happy);
  mark('intent_opens_in_quarantine_with_a_unique_path',intent.state==='pending'&&
    intent.quarantine_path===`quarantine/${ownerID}/${intent.intent_id}`&&intent.storage_authority==='legacy');
  mark('intent_replays_the_same_mutation',ok('open',happy).replayed===true&&sql("SELECT count(*) FROM private_isg.upload_intents;")==='1');
  mark('intent_conflicts_on_a_changed_body',call('open',{...happy,bytes:99}).error==='IDEMPOTENCY_CONFLICT');
  mark('unsupported_format_never_creates_an_intent',call('open',open({extension:'exe',mutation:randomUUID()})).error==='UNSUPPORTED_FORMAT'&&
    call('open',open({extension:'csv',mutation:randomUUID()})).error==='UNSUPPORTED_FORMAT'&&sql("SELECT count(*) FROM private_isg.upload_intents;")==='1');
  mark('oversized_declaration_never_creates_an_intent',call('open',open({bytes:50*MIB+1,mutation:randomUUID()})).error==='SIZE_LIMIT'&&sql("SELECT count(*) FROM private_isg.upload_intents;")==='1');

  const received={intent:intent.intent_id,bytes:bytesOf('clean-document'),sha256:digest('clean-document'),detected_type:'application/pdf',now:at(10)};
  mark('a_different_hash_than_declared_is_rejected',(()=>{
    const other=ok('open',open({mutation:randomUUID(),sha256:digest('declared')}));
    const result=ok('received',{intent:other.intent_id,bytes:bytesOf('declared'),sha256:digest('actually-other'),detected_type:'application/pdf',now:at(11)});
    return result.state==='rejected'&&result.rejection_code==='HASH_MISMATCH';})());
  mark('a_different_size_than_declared_is_rejected',(()=>{
    const other=ok('open',open({mutation:randomUUID(),sha256:digest('sized'),bytes:bytesOf('sized')}));
    const result=ok('received',{intent:other.intent_id,bytes:bytesOf('sized')+1,sha256:digest('sized'),detected_type:'application/pdf',now:at(11)});
    return result.state==='rejected'&&result.rejection_code==='SIZE_LIMIT';})());
  mark('an_unusable_media_type_is_rejected',(()=>{
    const other=ok('open',open({mutation:randomUUID(),sha256:digest('mime'),bytes:bytesOf('mime')}));
    const result=ok('received',{intent:other.intent_id,bytes:bytesOf('mime'),sha256:digest('mime'),detected_type:'not-a-media-type',now:at(11)});
    return result.state==='rejected'&&result.rejection_code==='MIME_MISMATCH';})());
  mark('a_matching_upload_becomes_uploaded_and_replays',ok('received',received).state==='uploaded'&&ok('received',{...received,now:at(12)}).replayed===true);
  mark('promotion_requires_a_clean_scan',call('promote',{intent:intent.intent_id,bucket:'isg-private',sha256:digest('clean-document'),bytes:bytesOf('clean-document'),now:at(13)}).error==='VALIDATION_ERROR');

  const scan={intent:intent.intent_id,scanner:'probe-av',version:'av-1.0.0',verdict:'clean',finding:null,
    sha256:digest('clean-document'),evidence:{engine:'probe'},now:at(20)};
  mark('a_scan_of_different_bytes_is_a_hash_mismatch',(()=>{
    const other=ok('open',open({mutation:randomUUID(),sha256:digest('swapped'),bytes:bytesOf('swapped')}));
    ok('received',{intent:other.intent_id,bytes:bytesOf('swapped'),sha256:digest('swapped'),detected_type:'application/pdf',now:at(21)});
    const result=ok('scan',{...scan,intent:other.intent_id,sha256:digest('swapped-after-upload'),now:at(22)});
    return result.state==='rejected'&&result.rejection_code==='HASH_MISMATCH';})());
  mark('a_rejecting_scanner_verdict_stops_the_file',(()=>{
    const other=ok('open',open({mutation:randomUUID(),sha256:digest('macro'),bytes:bytesOf('macro')}));
    ok('received',{intent:other.intent_id,bytes:bytesOf('macro'),sha256:digest('macro'),detected_type:'application/msword',now:at(23)});
    const result=ok('scan',{...scan,intent:other.intent_id,verdict:'rejected',finding:'MACRO_DETECTED',sha256:digest('macro'),now:at(24)});
    return result.state==='rejected'&&result.rejection_code==='SCAN_REJECTED'&&
      sql("SELECT count(*) FROM private_isg.file_assets WHERE source_intent_id="+quote(other.intent_id)+";")==='0';})());
  mark('a_scanner_outage_is_never_clean',(()=>{
    const other=ok('open',open({mutation:randomUUID(),sha256:digest('outage'),bytes:bytesOf('outage')}));
    ok('received',{intent:other.intent_id,bytes:bytesOf('outage'),sha256:digest('outage'),detected_type:'application/pdf',now:at(25)});
    const result=ok('scan',{...scan,intent:other.intent_id,verdict:'failed',finding:'SCANNER_TIMEOUT',sha256:digest('outage'),now:at(26)});
    return result.state==='scan_failed'&&result.rejection_code==='SCAN_UNAVAILABLE';})());
  mark('a_clean_scan_marks_the_intent_clean',ok('scan',scan).state==='clean');
  mark('promotion_reverifies_the_scanned_bytes',(()=>{
    const before=sql("SELECT count(*) FROM private_isg.file_assets;");
    const result=ok('promote',{intent:intent.intent_id,bucket:'isg-private',sha256:digest('swapped-after-scan'),bytes:bytesOf('clean-document'),now:at(30)});
    return result.state==='rejected'&&result.rejection_code==='HASH_MISMATCH'&&sql("SELECT count(*) FROM private_isg.file_assets;")===before;})());

  const clean=ok('open',open({mutation:randomUUID()}));
  ok('received',{intent:clean.intent_id,bytes:bytesOf('clean-document'),sha256:digest('clean-document'),detected_type:'application/pdf',now:at(40)});
  ok('scan',{...scan,intent:clean.intent_id,now:at(41)});
  const asset=ok('promote',{intent:clean.intent_id,bucket:'isg-private',sha256:digest('clean-document'),bytes:bytesOf('clean-document'),now:at(42)});
  mark('only_a_clean_reverified_original_becomes_an_asset',!!asset.asset_id&&
    asset.immutable_path===`assets/${ownerID}/${digest('clean-document')}`&&
    sql("SELECT scan_status||':'||preview_status FROM private_isg.file_assets WHERE asset_id="+quote(asset.asset_id)+";")==='clean:none');
  mark('promotion_replays_without_a_second_asset',ok('promote',{intent:clean.intent_id,bucket:'isg-private',sha256:digest('clean-document'),bytes:bytesOf('clean-document'),now:at(43)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.file_assets;")==='1');
  mark('a_promoted_intent_can_not_be_rejected',call('reject',{intent:clean.intent_id,code:'SCAN_REJECTED',now:at(44)}).error==='VALIDATION_ERROR');
  mark('an_immutable_path_can_not_be_overwritten',(()=>{
    const twin=ok('open',open({mutation:randomUUID()}));
    ok('received',{intent:twin.intent_id,bytes:bytesOf('clean-document'),sha256:digest('clean-document'),detected_type:'application/pdf',now:at(45)});
    ok('scan',{...scan,intent:twin.intent_id,now:at(46)});
    return call('promote',{intent:twin.intent_id,bucket:'isg-private',sha256:digest('clean-document'),bytes:bytesOf('clean-document'),now:at(47)}).error==='UNIQUE_VIOLATION';})());

  mark('a_failed_preview_leaves_the_original_clean_and_readable',(()=>{
    const failed=ok('derivative',{asset:asset.asset_id,kind:'preview',renderer:'render-1.0.0',state:'failed',path:null,bytes:null,failure:'RENDER_FAILED',now:at(50)});
    return failed.state==='failed'&&sql("SELECT scan_status||':'||preview_status FROM private_isg.file_assets WHERE asset_id="+quote(asset.asset_id)+";")==='clean:failed';})());
  mark('a_derivative_is_upserted_per_renderer_version',(()=>{
    const path='derivatives/'+asset.asset_id+'/preview/'+digest('preview-bytes');
    const ready=ok('derivative',{asset:asset.asset_id,kind:'preview',renderer:'render-1.0.0',state:'ready',path,bytes:12,failure:null,now:at(51)});
    return ready.state==='ready'&&sql("SELECT count(*) FROM private_isg.file_derivatives WHERE source_asset_id="+quote(asset.asset_id)+";")==='1'&&
      sql("SELECT preview_status FROM private_isg.file_assets WHERE asset_id="+quote(asset.asset_id)+";")==='ready';})());
  mark('a_derivative_needs_a_real_asset',call('derivative',{asset:randomUUID(),kind:'preview',renderer:'render-1.0.0',state:'pending',path:null,bytes:null,failure:null,now:at(52)}).error==='ACCESS_DENIED');

  mark('an_expired_intent_is_closed_not_left_open',(()=>{
    const stale=ok('open',open({mutation:randomUUID(),ttl:60,now:at(60)}));
    const expired=ok('expire',{now:at(200)});
    return expired>=1&&sql("SELECT state||':'||rejection_code FROM private_isg.upload_intents WHERE intent_id="+quote(stale.intent_id)+";")==='expired:EXPIRED';})());

  // Storage ledger stays shadow: it records, it does not deny an upload.
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='quota_ledger';");
  const metered=ok('open',open({mutation:randomUUID(),sha256:digest('metered'),bytes:bytesOf('metered'),storage_limit:1000000,storage_unlimited:false,now:at(300)}));
  mark('an_open_intent_reserves_storage_in_the_shadow_ledger',!!metered.reservation_id&&metered.storage_shadow_denied===false&&
    sql("SELECT amount||':'||state FROM private_isg.quota_reservations WHERE reservation_id="+quote(metered.reservation_id)+";")===bytesOf('metered')+':reserved');
  const settling=ok('open',open({mutation:randomUUID(),sha256:digest('settling'),bytes:bytesOf('settling'),storage_limit:1000000,storage_unlimited:false,now:at(310)}));
  ok('received',{intent:settling.intent_id,bytes:bytesOf('settling'),sha256:digest('settling'),detected_type:'application/pdf',now:at(311)});
  ok('scan',{...scan,intent:settling.intent_id,sha256:digest('settling'),now:at(312)});
  ok('promote',{intent:settling.intent_id,bucket:'isg-private',sha256:digest('settling'),bytes:bytesOf('settling'),now:at(313)});
  mark('promotion_settles_and_rejection_releases_the_reservation',
    sql("SELECT state FROM private_isg.quota_reservations WHERE reservation_id="+quote(settling.reservation_id)+";")==='settled'&&(()=>{
      const released=ok('open',open({mutation:randomUUID(),sha256:digest('released'),bytes:bytesOf('released'),storage_limit:1000000,storage_unlimited:false,now:at(320)}));
      ok('reject',{intent:released.intent_id,code:'SCAN_REJECTED',now:at(321)});
      return sql("SELECT state FROM private_isg.quota_reservations WHERE reservation_id="+quote(released.reservation_id)+";")==='released';})());
  const denied=ok('open',open({mutation:randomUUID(),sha256:digest('over-quota'),bytes:bytesOf('over-quota'),storage_limit:0,storage_unlimited:false,now:at(330)}));
  mark('a_shadow_storage_denial_does_not_block_the_upload',denied.state==='pending'&&denied.storage_shadow_denied===true&&denied.reservation_id===null&&
    sql("SELECT storage_shadow_denied FROM private_isg.upload_intents WHERE intent_id="+quote(denied.intent_id)+";")==='t');
  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='quota_ledger';");
  const unmetered=ok('open',open({mutation:randomUUID(),sha256:digest('unmetered'),bytes:bytesOf('unmetered'),now:at(340)}));
  mark('a_closed_ledger_does_not_block_the_file_core',unmetered.state==='pending'&&unmetered.reservation_id===null&&
    ok('reject',{intent:unmetered.intent_id,code:'SCAN_REJECTED',now:at(341)}).state==='rejected');

  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='file_core';");
  mark('kill_switch_stops_every_file_entry_point',call('open',open({mutation:randomUUID()})).error==='FEATURE_UNAVAILABLE'&&
    call('promote',{intent:clean.intent_id,bucket:'isg-private',sha256:digest('clean-document'),bytes:1,now:at(400)}).error==='FEATURE_UNAVAILABLE');
  return {afterLogout(){
    return {migration_file:fileCoreFiles[0],exact_migration_executed:true,rollout_left_disabled:true,
      client_grant_added:false,storage_bucket_created:false,real_scanner_connected:false,
      document_parser_spike_done:false,production_deployed:false};
  }};
}
