import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {randomUUID} from 'node:crypto';
import {ROOT} from './lib.mjs';
import {verifyLocalSessionToken} from './auth_session_probe.mjs';
export const workspaceAvailabilityFiles = ['supabase/migrations/20260913084736_isg_workspace_availability.sql','scripts/isg/workspace_availability_probe.mjs'];
const q = v => "'" + String(v).replaceAll("'", "''") + "'";

export async function beginWorkspaceAvailabilityProbe({synthetic, sql, token, secret, companyID, request, waitReady, pass}) {
  if (synthetic !== true) throw Error('WORKSPACE_SYNTHETIC_REQUIRED');
  const claims = verifyLocalSessionToken(token, secret);
  const mark = (name, ok) => pass('workspace_' + name, ok);
  sql(readFileSync(resolve(ROOT, workspaceAvailabilityFiles[0]), 'utf8'));
  const read = (company = null, extra = {}) => request('/rpc/isg_workspace_availability_v1', {method:'POST', body:{p_company:company}, ...extra});
  await waitReady(() => read().status === 200);
  mark('global_identity_and_no_write', read().body.owner_id === claims.sub && read().body.can_read === true && read().body.can_write === false && read().body.company_id === null);
  const owned = read(companyID);
  mark('paid_owner_can_write', owned.status === 200 && owned.body.company_id === companyID && owned.body.can_write === true && typeof owned.body.company_name === 'string');
  mark('six_checked_private_entries', sql("SELECT count(*)=6 AND bool_and(prosecdef AND proconfig @> ARRAY['search_path=\"\"']) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND has_function_privilege('authenticated',p.oid,'EXECUTE');") === 't');
  mark('wrapper_invoker', sql("SELECT NOT prosecdef FROM pg_proc WHERE oid='public.isg_workspace_availability_v1(uuid)'::regprocedure;") === 't');
  mark('anon_service_revoked', sql("SELECT NOT has_function_privilege('anon','public.isg_workspace_availability_v1(uuid)','EXECUTE') AND NOT has_function_privilege('service_role','public.isg_workspace_availability_v1(uuid)','EXECUTE');") === 't');
  mark('foreign_company_denied', read(randomUUID()).status === 400 && read(randomUUID()).body.message === 'ACCESS_DENIED');
  mark('anonymous_denied', read(null, {authorization:null}).status === 401);
  mark('metadata_cannot_grant', read(companyID, {body:{p_company:companyID,can_write:true,role:'owner'}}).status >= 400);
  sql('UPDATE private_isg.rollout SET write_enabled=false;');
  mark('write_rollout_read_only', read(companyID).body.can_read === true && read(companyID).body.can_write === false);
  sql('UPDATE private_isg.rollout SET read_enabled=false;');
  mark('disabled_global', read().body.can_read === false && read().body.can_write === false);
  mark('disabled_hides_company', read(companyID).body.company_name === null && read(companyID).body.is_archived === null);
  sql('UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true;');
  sql(`UPDATE public.companies SET is_archived=true WHERE id=${q(companyID)};`);
  mark('archived_read_only', read(companyID).body.can_read === true && read(companyID).body.is_archived === true && read(companyID).body.can_write === false);
  sql(`UPDATE public.companies SET is_archived=false WHERE id=${q(companyID)};`);
  const subscription = JSON.parse(sql(`SELECT to_jsonb(s) FROM public.user_subscriptions s WHERE user_id=${q(claims.sub)};`));
  assert.ok(subscription);
  sql(`UPDATE public.user_subscriptions SET current_period_ends_at=clock_timestamp()-interval '1 day' WHERE user_id=${q(claims.sub)};`);
  mark('expired_read_only', read(companyID).body.can_read === true && read(companyID).body.can_write === false);
  sql(`UPDATE public.user_subscriptions s SET current_period_ends_at=r.current_period_ends_at FROM jsonb_populate_record(null::public.user_subscriptions,${q(JSON.stringify(subscription))}::jsonb) r WHERE s.user_id=r.user_id;`);
  mark('restored_paid', read(companyID).body.can_write === true);
  return { afterLogout() {
    mark('logout_global_rejected', read().status === 403);
    mark('logout_selected_rejected', read(companyID).status === 403);
    return {migration_applied:true, production_deployed:false, native_ui_e2e:false};
  }};
}
