import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const personalNotesFiles=[
  'supabase/migrations/20260914070000_isg_personal_notes.sql',
  'scripts/isg/personal_notes_probe.mjs',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
const json=v=>quote(JSON.stringify(v))+'::jsonb';
const now=seconds=>new Date(Date.UTC(2026,8,14,7,0,0)+seconds*1000).toISOString();

export async function beginPersonalNotesProbe({synthetic,sql,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_NOTES_SYNTHETIC_REQUIRED');
  if(!ownerID)throw Error('AUTH_RESTORE_NOTES_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('personal_notes_'+name,ok);
  sql(read(personalNotesFiles[0]));
  mark('migration_applied_with_closed_rollout',sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='personal_notes';")==='t');

  sql(["CREATE SCHEMA isg_notes_test;",
    "CREATE FUNCTION isg_notes_test.observe(kind text,a jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $probe$",
    "DECLARE r jsonb; code text; BEGIN",
    "IF kind='sync' THEN r:=private_isg.sync_personal_note((a->>'owner')::uuid,(a->>'note')::uuid,a->>'title',a->>'body',(a->>'expected')::bigint,(a->>'client_updated_at')::timestamptz,(a->>'now')::timestamptz);",
    "ELSIF kind='resolve' THEN r:=private_isg.resolve_note_conflict((a->>'conflict')::uuid,(a->>'owner')::uuid,a->>'title',a->>'body',(a->>'now')::timestamptz);",
    "ELSIF kind='delete' THEN r:=private_isg.delete_personal_note((a->>'owner')::uuid,(a->>'note')::uuid,(a->>'expected')::bigint,(a->>'now')::timestamptz);",
    "ELSIF kind='reminder' THEN r:=private_isg.create_personal_reminder((a->>'owner')::uuid,(a->>'note')::uuid,a->>'title',a->>'recurrence',(a->>'local_time')::time,(a->>'starts_on')::date,a->>'timezone',(a->>'now')::timestamptz);",
    "ELSIF kind='project' THEN r:=private_isg.project_reminder_occurrences((a->>'reminder')::uuid,(a->>'count')::integer,(a->>'now')::timestamptz);",
    "ELSIF kind='settle' THEN r:=private_isg.settle_reminder_occurrence((a->>'occurrence')::uuid,a->>'action',(a->>'until')::timestamptz,(a->>'now')::timestamptz);",
    "ELSIF kind='cancel' THEN r:=private_isg.cancel_reminder_series((a->>'reminder')::uuid,a->>'reason',(a->>'now')::timestamptz);",
    "ELSIF kind='claim' THEN r:=private_isg.claim_reminder_delivery((a->>'reminder')::uuid,(a->>'installation')::uuid,a->>'strategy',(a->>'now')::timestamptz);",
    "ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;",
    "RETURN jsonb_build_object('result',r);",
    "EXCEPTION WHEN SQLSTATE '23514' THEN RETURN jsonb_build_object('error','CHECK_VIOLATION');",
    "WHEN SQLSTATE '23505' THEN RETURN jsonb_build_object('error','UNIQUE_VIOLATION');",
    "WHEN SQLSTATE 'P0001' THEN GET STACKED DIAGNOSTICS code=MESSAGE_TEXT;",
    "IF code NOT IN ('FEATURE_UNAVAILABLE','VALIDATION_ERROR','ACCESS_DENIED','VERSION_CONFLICT','NOTE_TOMBSTONED','SERIES_CANCELLED') THEN RAISE; END IF;",
    "RETURN jsonb_build_object('error',code); END $probe$;"].join('\n'));
  const call=(kind,args)=>JSON.parse(sql("SELECT isg_notes_test.observe("+quote(kind)+","+json(args)+");").split('\n').at(-1));
  const ok=(kind,args)=>{const r=call(kind,args);if(r.error)throw Error('AUTH_RESTORE_NOTES_UNEXPECTED_'+r.error);return r.result;};

  const noteID=randomUUID();
  const syncArgs=(over={})=>({owner:ownerID,note:noteID,title:'Alışveriş',body:'Kalem al',expected:0,
    client_updated_at:now(0),now:now(0),...over});
  mark('gate_blocks_the_notebook_while_rollout_off',call('sync',syncArgs()).error==='FEATURE_UNAVAILABLE');
  const privileges=sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC'); SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND NOT rowsecurity; SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('notes_gate','sync_personal_note','resolve_note_conflict','delete_personal_note','create_personal_reminder','project_reminder_occurrences','settle_reminder_occurrence','cancel_reminder_series','claim_reminder_delivery') AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE'));").split('\n');
  mark('note_tables_have_rls_and_no_client_grant',privileges[0]==='0'&&privileges[1]==='0'&&privileges[2]==='0');
  // The notebook must not be able to reach a company domain even by accident.
  mark('no_company_or_entity_column_exists_at_any_level',
    sql("SELECT count(*) FROM information_schema.columns WHERE table_schema='private_isg' AND table_name IN ('personal_notes','note_conflicts','note_items','note_tags','note_tag_links','personal_reminders','reminder_occurrences','device_delivery_claims') AND column_name ~ '(company|workplace|employee|entity|analysis|risk|training|attachment|asset)';")==='0');
  mark('the_notebook_needs_no_paid_plan',
    sql("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('sync_personal_note','create_personal_reminder','project_reminder_occurrences') AND (p.prosrc LIKE '%require_company%' OR p.prosrc LIKE '%user_plan_tier%' OR p.prosrc LIKE '%user_subscriptions%');")==='0');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='personal_notes';");

  const created=ok('sync',syncArgs());
  mark('a_note_is_created_at_version_one',created.version===1&&created.state==='created');
  mark('an_unchanged_sync_is_not_a_new_version',ok('sync',syncArgs({expected:1,now:now(1)})).state==='unchanged'&&
    sql("SELECT version FROM private_isg.personal_notes WHERE note_id="+quote(noteID)+";")==='1');
  const updated=ok('sync',syncArgs({expected:1,body:'Kalem ve defter al',now:now(2)}));
  mark('an_edit_moves_the_version',updated.version===2&&updated.state==='updated');
  const conflict=ok('sync',syncArgs({expected:1,title:'Alışveriş',body:'Telefondan yazılan başka metin',now:now(3)}));
  mark('a_stale_device_never_overwrites_in_silence',conflict.state==='conflict'&&conflict.both_texts_preserved===true&&
    conflict.server_version===2&&
    sql("SELECT body FROM private_isg.personal_notes WHERE note_id="+quote(noteID)+";")==='Kalem ve defter al'&&
    sql("SELECT incoming_body||'|'||server_body FROM private_isg.note_conflicts WHERE conflict_id="+quote(conflict.conflict_id)+";")==='Telefondan yazılan başka metin|Kalem ve defter al');
  const resolved=ok('resolve',{conflict:conflict.conflict_id,owner:ownerID,title:'Alışveriş',
    body:'Kalem ve defter al / Telefondan yazılan başka metin',now:now(4)});
  mark('a_resolution_keeps_both_texts_and_bumps_the_version',resolved.resolved_version===3&&
    resolved.kept_incoming==='Telefondan yazılan başka metin'&&resolved.kept_server==='Kalem ve defter al'&&
    ok('resolve',{conflict:conflict.conflict_id,owner:ownerID,title:'x',body:'y',now:now(5)}).replayed===true&&
    sql("SELECT version FROM private_isg.personal_notes WHERE note_id="+quote(noteID)+";")==='3');
  mark('another_account_can_not_touch_the_note',call('sync',syncArgs({owner:randomUUID(),expected:3,now:now(6)})).error==='ACCESS_DENIED');

  const reminder=ok('reminder',{owner:ownerID,note:noteID,title:'Kalem al',recurrence:'daily',local_time:'09:00',
    starts_on:'2027-03-27',timezone:'Europe/Berlin',now:now(10)});
  const projected=ok('project',{reminder:reminder.reminder_id,count:3,now:now(11)});
  const instants=sql("SELECT string_agg(to_char(due_at AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI')||'@'||to_char(local_due_at,'YYYY-MM-DD HH24:MI'),',' ORDER BY occurrence_no) FROM private_isg.reminder_occurrences WHERE reminder_id="+quote(reminder.reminder_id)+";");
  // 2027-03-28 is the European DST switch: the local 09:00 stays, the UTC instant moves.
  mark('daylight_saving_moves_the_instant_not_the_local_time',projected.created===3&&
    instants==='2027-03-27 08:00@2027-03-27 09:00,2027-03-28 07:00@2027-03-28 09:00,2027-03-29 07:00@2027-03-29 09:00');
  mark('an_unknown_timezone_is_refused',call('reminder',{owner:ownerID,note:noteID,title:'x',recurrence:'daily',
    local_time:'09:00',starts_on:'2027-03-27',timezone:'Mars/Olympus',now:now(12)}).error==='VALIDATION_ERROR');
  const occurrences=sql("SELECT string_agg(occurrence_id::text,',' ORDER BY occurrence_no) FROM private_isg.reminder_occurrences WHERE reminder_id="+quote(reminder.reminder_id)+";").split(',');
  const completed=ok('settle',{occurrence:occurrences[0],action:'complete',until:null,now:now(13)});
  mark('completing_one_occurrence_does_not_close_the_series',completed.state==='completed'&&
    completed.series_state==='active'&&completed.series_closed===false&&completed.remaining_open_occurrences===2);
  const snoozed=ok('settle',{occurrence:occurrences[1],action:'snooze',until:'2027-03-28T10:00:00Z',now:now(14)});
  mark('snoozing_one_occurrence_leaves_the_rest_scheduled',snoozed.state==='snoozed'&&
    sql("SELECT state FROM private_isg.reminder_occurrences WHERE occurrence_id="+quote(occurrences[2])+";")==='scheduled');
  mark('a_snooze_must_move_forward',call('settle',{occurrence:occurrences[2],action:'snooze',
    until:'2020-01-01T00:00:00Z',now:now(15)}).error==='VALIDATION_ERROR');
  mark('a_settled_occurrence_replays',ok('settle',{occurrence:occurrences[0],action:'complete',until:null,now:now(16)}).replayed===true);

  const install=randomUUID(),otherInstall=randomUUID();
  const claim=ok('claim',{reminder:reminder.reminder_id,installation:install,strategy:'local',now:now(20)});
  mark('exactly_one_installation_owns_the_delivery',claim.exactly_once_promised===false&&
    claim.delivery_guarantee==='at_most_once_per_installation'&&
    ok('claim',{reminder:reminder.reminder_id,installation:install,strategy:'local',now:now(21)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.device_delivery_claims WHERE reminder_id="+quote(reminder.reminder_id)+";")==='1');
  const moved=ok('claim',{reminder:reminder.reminder_id,installation:otherInstall,strategy:'server_push',now:now(22)});
  mark('a_new_installation_takes_over_instead_of_doubling',moved.previous_installation_id===install&&
    sql("SELECT installation_id||':'||strategy FROM private_isg.device_delivery_claims WHERE reminder_id="+quote(reminder.reminder_id)+";")===otherInstall+':server_push');

  const deleted=ok('delete',{owner:ownerID,note:noteID,expected:3,now:now(30)});
  mark('deleting_a_note_cancels_future_reminders_and_keeps_history',deleted.tombstone===true&&
    deleted.cancelled_future_occurrences===2&&deleted.kept_completed_occurrences===1&&
    sql("SELECT state||':'||cancelled_reason FROM private_isg.personal_reminders WHERE reminder_id="+quote(reminder.reminder_id)+";")==='cancelled:NOTE_DELETED'&&
    sql("SELECT count(*) FROM private_isg.reminder_occurrences WHERE reminder_id="+quote(reminder.reminder_id)+" AND state='completed';")==='1');
  mark('a_tombstone_clears_the_text_but_keeps_the_marker',
    sql("SELECT title IS NULL AND body IS NULL AND deleted_at IS NOT NULL FROM private_isg.personal_notes WHERE note_id="+quote(noteID)+";")==='t');
  mark('an_old_offline_device_can_not_resurrect_a_deleted_note',
    call('sync',syncArgs({expected:3,body:'Çevrimdışı cihazdan geri geldi',now:now(31)})).error==='NOTE_TOMBSTONED'&&
    call('sync',syncArgs({expected:0,now:now(32)})).error==='NOTE_TOMBSTONED');
  mark('deleting_twice_is_a_replay',ok('delete',{owner:ownerID,note:noteID,expected:4,now:now(33)}).replayed===true);
  mark('a_cancelled_series_projects_nothing_new',call('project',{reminder:reminder.reminder_id,count:1,now:now(34)}).error==='SERIES_CANCELLED');

  const standalone=ok('reminder',{owner:ownerID,note:null,title:'Bağımsız hatırlatıcı',recurrence:'once',
    local_time:'08:30',starts_on:'2027-01-10',timezone:'Europe/Istanbul',now:now(40)});
  mark('a_once_reminder_projects_a_single_occurrence',ok('project',{reminder:standalone.reminder_id,count:5,now:now(41)})&&
    sql("SELECT count(*) FROM private_isg.reminder_occurrences WHERE reminder_id="+quote(standalone.reminder_id)+";")==='1');
  const cancelled=ok('cancel',{reminder:standalone.reminder_id,reason:'USER_CANCELLED',now:now(42)});
  mark('cancelling_a_series_stops_the_future_and_keeps_the_past',cancelled.cancelled_future===1&&cancelled.kept_completed===0&&
    ok('cancel',{reminder:standalone.reminder_id,reason:'USER_CANCELLED',now:now(43)}).replayed===true);

  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='personal_notes';");
  mark('kill_switch_stops_the_notebook',call('sync',syncArgs({note:randomUUID(),now:now(50)})).error==='FEATURE_UNAVAILABLE'&&
    call('project',{reminder:standalone.reminder_id,count:1,now:now(50)}).error==='FEATURE_UNAVAILABLE');
  return {afterLogout(){
    return {migration_file:personalNotesFiles[0],exact_migration_executed:true,rollout_left_disabled:true,
      client_grant_added:false,company_domain_linked:false,paid_plan_required:false,
      exactly_once_delivery_promised:false,device_sync_client_implemented:false,production_deployed:false};
  }};
}
