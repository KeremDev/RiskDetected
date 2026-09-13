import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import { ROOT } from './lib.mjs';
const q=v=>"'"+String(v).replaceAll("'","''")+"'";
export const notificationDeviceFiles=['supabase/migrations/20260914070003_isg_device_notification_permission.sql','scripts/isg/notification_device_probe.mjs'];
export function beginNotificationDeviceProbe({synthetic,sql,ownerID,companyID,pass}) {
  if(synthetic!==true||!ownerID||!companyID)throw Error('DEVICE_PERMISSION_SYNTHETIC_SCOPE_REQUIRED');
  const mark=(id,value)=>pass('notification_device_'+id,value);
  // The synthetic runner intentionally starts without legacy app tables. This
  // minimal token fixture is not a production migration; the separate full-copy
  // upgrade verifies the migration against the actual legacy table and helpers.
  sql(`CREATE TABLE public.push_device_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid NOT NULL REFERENCES auth.users(id),
    token text NOT NULL,provider text NOT NULL,platform text NOT NULL,environment text NOT NULL,
    notifications_enabled boolean NOT NULL,application_id text,provider_environment text,
    UNIQUE(user_id,token));
    ALTER TABLE public.push_device_tokens ENABLE ROW LEVEL SECURITY;
    REVOKE ALL ON public.push_device_tokens FROM PUBLIC,anon,authenticated,service_role;`);
  sql(readFileSync(resolve(ROOT,notificationDeviceFiles[0]),'utf8'));
  const session=sql(`SELECT id FROM auth.sessions WHERE user_id=${q(ownerID)} ORDER BY created_at DESC LIMIT 1;`);
  const claims=JSON.stringify({sub:ownerID,session_id:session,role:'authenticated',exp:Math.floor(Date.now()/1000)+3600});
  sql(`CREATE SCHEMA isg_device_test;
    CREATE FUNCTION isg_device_test.record(t text,p text,b integer,a boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
    BEGIN RETURN public.isg_notification_device_permission_v1(t,p,b,a);
    EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error',SQLSTATE); END $$;
    GRANT USAGE ON SCHEMA isg_device_test TO authenticated; GRANT EXECUTE ON FUNCTION isg_device_test.record(text,text,integer,boolean) TO authenticated;`);
  const record=(token,provider='fcm',build=120,authorized=true,c=claims)=>{
    const result=sql(`BEGIN;SET LOCAL ROLE authenticated;SELECT set_config('request.jwt.claims',${q(c)},true);
      SELECT isg_device_test.record(${q(token)},${q(provider)},${build===null?'NULL':build},${authorized===null?'NULL':authorized});COMMIT;`);
    return JSON.parse(result.split('\n').filter(line=>line.startsWith('{')).at(-1));
  };
  mark('default_gate_closed',record('synthetic-token').error==='P0001');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='notifications';");
  const tokenID=randomUUID();
  sql(`INSERT INTO public.push_device_tokens(id,user_id,token,provider,platform,environment,notifications_enabled) VALUES(${q(tokenID)},${q(ownerID)},'synthetic-device-token','fcm','android','sandbox',true);`);
  mark('owner_device_records',record('synthetic-device-token').recorded===true);
  mark('client_cannot_read_table',sql("SELECT NOT has_table_privilege('authenticated','private_isg.notification_device_permissions','SELECT');")==='t');
  mark('anon_cannot_call',sql("SELECT NOT has_function_privilege('anon','public.isg_notification_device_permission_v1(text,text,integer,boolean)','EXECUTE');")==='t');
  mark('missing_token_rejected',record('not-owned').error==='P0001');
  mark('wrong_provider_rejected',record('synthetic-device-token','apns').error==='P0001');
  mark('invalid_build_rejected',record('synthetic-device-token','fcm',0).error==='P0001');
  mark('null_permission_rejected',record('synthetic-device-token','fcm',120,null).error==='P0001');
  mark('fake_session_rejected',record('synthetic-device-token','fcm',120,true,JSON.stringify({...JSON.parse(claims),session_id:randomUUID()})).error==='28000');
  sql(`SELECT private_isg.set_producer_ownership('obligation','device.test','isg_engine','shadow',clock_timestamp());`);
  const episode=JSON.parse(sql(`SELECT private_isg.open_notification_episode(${q(ownerID)},${q(companyID)},'obligation','device.test','device-source',1,NULL,'isg_engine',false,clock_timestamp());`)).episode_id;
  const job=JSON.parse(sql(`SELECT private_isg.enqueue_notification(${q(episode)},'push','home','home',100,clock_timestamp(),'Europe/Istanbul',clock_timestamp());`)).job_id;
  const read=()=>JSON.parse(sql(`SELECT private_isg.notification_registered_device(${q(job)},clock_timestamp(),3600);`));
  mark('trusted_read_uses_recorded_device',read().device?.token_id===tokenID&&read().device?.app_build===120);
  record('synthetic-device-token','fcm',121,false);
  mark('revocation_and_build_are_device_scoped',read().device?.os_authorized===false&&read().device?.app_build===121);
  sql(`UPDATE private_isg.notification_device_permissions SET observed_at=clock_timestamp()-interval '2 hours' WHERE token_id=${q(tokenID)};`);
  mark('stale_permission_not_eligible',read().device===null);
  record('synthetic-device-token');
  sql(`UPDATE public.push_device_tokens SET token='rotated-device-token' WHERE id=${q(tokenID)};`);
  mark('token_rotation_invalidates_old_observation',read().device===null);
  record('rotated-device-token');
  mark('new_token_observation_restores_read',read().device?.token==='rotated-device-token');
  const second=randomUUID();
  sql(`INSERT INTO public.push_device_tokens(id,user_id,token,provider,platform,environment,notifications_enabled) VALUES(${q(second)},${q(ownerID)},'second-device-token','apns','ios','sandbox',true);`);
  record('second-device-token','apns');
  mark('multiple_devices_require_strategy',read().reason==='DEVICE_STRATEGY_REQUIRED'&&read().device===null);
  sql(`DELETE FROM public.push_device_tokens WHERE id=${q(second)};`);
  mark('deleted_token_cascades_permission',sql(`SELECT count(*) FROM private_isg.notification_device_permissions WHERE token_id=${q(second)};`)==='0');
  sql(`UPDATE public.push_device_tokens SET notifications_enabled=false WHERE id=${q(tokenID)};`);
  mark('legacy_disabled_token_not_eligible',read().device===null);
  sql(`DELETE FROM public.push_device_tokens WHERE id=${q(tokenID)};UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='notifications';`);
  mark('rollout_restored_closed',sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='notifications';")==='t');
  return {native_rpc_contract:true,real_auth_session:true,provider_called:false,production_changed:false};
}
