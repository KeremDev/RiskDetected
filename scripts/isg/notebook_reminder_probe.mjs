import { randomUUID } from 'node:crypto';

const q=value=>"'"+String(value).replaceAll("'","''")+"'";

export async function probeNotebookReminders({request,sql,pass,ownerID}) {
  const mark=(name,ok)=>pass('notebook_reminder_'+name,ok);
  const read=(after=null,options={})=>request('/rpc/isg_notebook_reminders_v1',{
    method:'POST',body:{p_after:after},...options,
  });
  const mutate=(body,options={})=>request('/rpc/isg_notebook_reminder_mutate_v1',{method:'POST',body,...options});
  const installation=randomUUID(),tokenID=randomUUID();
  const local=sql("SELECT to_char((clock_timestamp()+interval '5 minutes') AT TIME ZONE 'Europe/Istanbul','YYYY-MM-DD|HH24:MI:SS');").split('|');
  const draft=(over={})=>({p_mutation:randomUUID(),p_action:'create',p_reminder:null,p_note:null,p_occurrence:null,
    p_expected:0,p_title:'Kişisel kontrol',p_recurrence:'daily',p_local_time:local[1],p_starts_on:local[0],
    p_timezone:'Europe/Istanbul',p_snoozed_until:null,p_installation:installation,...over});

  mark('api_defaults_closed',read().body.message==='FEATURE_UNAVAILABLE');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature IN ('personal_notes','notifications');");
  mark('missing_device_rejected',mutate(draft()).body.message==='DEVICE_UNAVAILABLE');
  sql(`INSERT INTO public.push_device_tokens(id,user_id,token,provider,platform,environment,notifications_enabled,
      application_id,provider_environment,installation_id,client_build)
    VALUES(${q(tokenID)},${q(ownerID)},'notebook-device-token','fcm','android','sandbox',true,
      'com.riskdetectedan.app','synthetic',${q(installation)},'120');
    INSERT INTO public.notification_preferences(user_id,enabled,app_reminders) VALUES(${q(ownerID)},false,false)
      ON CONFLICT(user_id) DO UPDATE SET enabled=false,app_reminders=false;`);
  const permission=request('/rpc/isg_notification_device_permission_v1',{method:'POST',body:{
    p_token:'notebook-device-token',p_provider:'fcm',p_build:120,p_authorized:true,
  }});
  mark('selected_installation_permission_recorded',permission.status===200&&permission.body.recorded===true);
  mark('disabled_reminder_category_rejected',mutate(draft()).body.message==='DEVICE_UNAVAILABLE');
  sql(`UPDATE public.notification_preferences SET enabled=true,app_reminders=true WHERE user_id=${q(ownerID)};`);
  const yesterday=sql("SELECT to_char((clock_timestamp()-interval '1 day') AT TIME ZONE 'Europe/Istanbul','YYYY-MM-DD');");
  mark('past_schedule_rejected_by_server',mutate(draft({p_starts_on:yesterday})).body.message==='VALIDATION_ERROR');

  const first=draft(),created=mutate(first);
  mark('active_session_creates_server_push_reminder',created.status===200&&created.body.state==='active'&&
    created.body.delivery_strategy==='server_push'&&created.body.projected_occurrences===8);
  mark('write_receipt_contains_no_title',!JSON.stringify(created.body).includes(first.p_title));
  mark('same_mutation_replays',mutate(first).body.replayed===true);
  mark('changed_retry_conflicts',mutate({...first,p_title:'Changed'}).body.message==='IDEMPOTENCY_CONFLICT');
  const reminder=created.body.reminder_id,page=read();
  mark('owner_reads_bounded_reminder_and_occurrence',page.status===200&&page.body.reminders.some(r=>
    r.reminder_id===reminder&&r.delivery_installation_id===installation&&r.next_occurrence?.occurrence_id));
  mark('anon_cannot_read_or_mutate',read(null,{authorization:null}).status>=400&&mutate(first,{authorization:null}).status>=400);

  sql(`UPDATE private_isg.notification_purposes SET caps_approved=true WHERE purpose='personal_reminder';
    SELECT private_isg.set_producer_ownership('personal_reminder','notebook.reminder','isg_engine','live',clock_timestamp());`);
  const due=sql(`SELECT coalesce(snoozed_until,due_at) FROM private_isg.reminder_occurrences
    WHERE reminder_id=${q(reminder)} ORDER BY occurrence_no LIMIT 1;`);
  const produced=JSON.parse(sql(`SELECT private_isg.enqueue_personal_reminder_notifications(${q(due)}::timestamptz,0,100,100);`));
  const job=sql(`SELECT j.job_id FROM private_isg.notification_jobs j JOIN private_isg.notification_episodes e USING(episode_id)
    WHERE e.owner_id=${q(ownerID)} AND split_part(e.source_ref,':',1)=(SELECT occurrence_id::text FROM private_isg.reminder_occurrences
      WHERE reminder_id=${q(reminder)} ORDER BY occurrence_no LIMIT 1);`);
  const snapshot=JSON.parse(sql(`SELECT private_isg.notification_job_snapshot(${q(job)},${q(due)}::timestamptz,3600);`));
  mark('occurrence_produces_private_p12_job_without_provider_call',produced.queued_jobs===1&&produced.provider_called===false&&snapshot.job_id===job);
  mark('snapshot_selects_only_claimed_installation',snapshot.device.installation_id===installation&&snapshot.device.category_enabled===true);
  const claim=JSON.parse(sql(`SELECT private_isg.dispatch_bound_notification(${q(job)},${q(JSON.stringify(snapshot.device))}::jsonb,${q(due)}::timestamptz);`));
  mark('claim_rechecks_occurrence_and_selected_installation',claim.allowed===true&&claim.state==='dispatching');

  const second=draft({p_mutation:randomUUID(),p_title:'Erteleme kontrolü'}),secondCreated=mutate(second);
  const secondReminder=secondCreated.body.reminder_id;
  const secondOccurrence=sql(`SELECT occurrence_id FROM private_isg.reminder_occurrences WHERE reminder_id=${q(secondReminder)} ORDER BY occurrence_no LIMIT 1;`);
  const secondDue=sql(`SELECT due_at FROM private_isg.reminder_occurrences WHERE occurrence_id=${q(secondOccurrence)};`);
  JSON.parse(sql(`SELECT private_isg.enqueue_personal_reminder_notifications(${q(secondDue)}::timestamptz,0,100,100);`));
  const snoozeUntil=new Date(Date.parse(secondDue)+10*60*1000).toISOString();
  const snoozed=mutate({p_mutation:randomUUID(),p_action:'snooze',p_reminder:secondReminder,p_note:null,
    p_occurrence:secondOccurrence,p_expected:1,p_title:null,p_recurrence:null,p_local_time:null,p_starts_on:null,
    p_timezone:null,p_snoozed_until:snoozeUntil,p_installation:null});
  mark('snooze_cancels_stale_job_without_closing_series',snoozed.body.state==='snoozed'&&snoozed.body.series_closed===false&&
    sql(`SELECT count(*) FROM private_isg.notification_jobs j JOIN private_isg.notification_episodes e USING(episode_id)
      WHERE split_part(e.source_ref,':',1)=${q(secondOccurrence)} AND j.state='cancelled' AND j.suppression_code='REMINDER_SETTLED';`)==='1');
  const requeued=JSON.parse(sql(`SELECT private_isg.enqueue_personal_reminder_notifications(${q(snoozeUntil)}::timestamptz,0,100,100);`));
  mark('snoozed_occurrence_gets_new_time_bound_job',requeued.queued_jobs===1&&
    sql(`SELECT count(DISTINCT e.source_ref) FROM private_isg.notification_jobs j JOIN private_isg.notification_episodes e USING(episode_id)
      WHERE split_part(e.source_ref,':',1)=${q(secondOccurrence)};`)==='2');

  const cancel=mutate({p_mutation:randomUUID(),p_action:'cancel',p_reminder:secondReminder,p_note:null,p_occurrence:null,
    p_expected:1,p_title:null,p_recurrence:null,p_local_time:null,p_starts_on:null,p_timezone:null,p_snoozed_until:null,p_installation:null});
  mark('cancel_stops_series_and_future_jobs',cancel.body.state==='cancelled'&&
    sql(`SELECT count(*) FROM private_isg.notification_jobs j JOIN private_isg.notification_episodes e USING(episode_id)
      JOIN private_isg.reminder_occurrences o ON split_part(e.source_ref,':',1)=o.occurrence_id::text
      WHERE o.reminder_id=${q(secondReminder)} AND j.state IN ('queued','failed');`)==='0');

  const foreign=sql(`SELECT id FROM public.profiles WHERE id<>${q(ownerID)} LIMIT 1;`);
  if (foreign) {
    const foreignReminder=JSON.parse(sql(`SELECT private_isg.create_personal_reminder(${q(foreign)},NULL,'Foreign','once','09:00','2027-01-01','Europe/Istanbul',clock_timestamp());`)).reminder_id;
    mark('foreign_reminder_is_absent_and_cannot_mutate',!read().body.reminders.some(r=>r.reminder_id===foreignReminder)&&
      mutate({p_mutation:randomUUID(),p_action:'cancel',p_reminder:foreignReminder,p_note:null,p_occurrence:null,p_expected:1,
        p_title:null,p_recurrence:null,p_local_time:null,p_starts_on:null,p_timezone:null,p_snoozed_until:null,p_installation:null}).body.message==='ACCESS_DENIED');
  }
  sql("UPDATE private_isg.notification_purposes SET caps_approved=false WHERE purpose='personal_reminder';UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature IN ('personal_notes','notifications');");
  return {afterLogout(){
    mark('revoked_session_cannot_read',read().body.message==='AUTH_REQUIRED');
    mark('revoked_session_cannot_mutate',mutate(first).body.message==='AUTH_REQUIRED');
    return {real_http:true,server_push_owner:true,p12_job_binding:true,provider_called:false,production_changed:false};
  }};
}
