/** Additive v1 transport only. Not wired to legacy endpoints or a UI/network loop. */
const codes: Readonly<Record<string, number>> = Object.freeze({
  AUTH_REQUIRED:401, COMPANY_ACCESS_DENIED:403, CAPABILITY_DISABLED:403,
  CROSS_COMPANY_REFERENCE:403, VERSION_CONFLICT:409, VALIDATION_FAILED:422,
  RULE_REVIEW_REQUIRED:409, DOCUMENT_NOT_READY:409, QUOTA_EXCEEDED:409,
  IDEMPOTENCY_CONFLICT:409, SCAN_PENDING:423, UNSUPPORTED_FORMAT:415,
});
export interface IsgMutationOutcome {
  schema_version:1; operation_id:string; request_id:string; support_id:string;
  outcome:"committed"|"pending"|"rejected"|"indeterminate";
  code?:string; current_version?:number; version?:number;
  projection?:"ready"|"pending"|"failed"; retry_after_seconds?:number;
}
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const record=(v:unknown):v is Record<string,unknown>=>v!==null && typeof v==='object' && !Array.isArray(v);
const integer=(v:unknown,min=0,max=9007199254740991)=>Number.isSafeInteger(v) && (v as number)>=min && (v as number)<=max;
export function parseIsgMutationOutcome(status:number,input:unknown):IsgMutationOutcome|null {
  if(!record(input)||input.schema_version!==1||
    typeof input.operation_id!=='string'||input.operation_id.length!==36||!uuid.test(input.operation_id)||
    typeof input.request_id!=='string'||input.request_id.length!==36||!uuid.test(input.request_id)||
    typeof input.support_id!=='string'||input.support_id.length!==16||!/^ISG-[A-F0-9]{12}$/.test(input.support_id))return null;
  const fields=['schema_version','operation_id','request_id','support_id','outcome'];
  switch(input.outcome) {
    case 'committed':
      if(status!==200||!integer(input.version)||typeof input.projection!=='string'||!['ready','pending','failed'].includes(input.projection))return null;
      fields.push('version','projection');break;
    case 'pending': case 'indeterminate':
      if(status!==(input.outcome==='pending'?202:503)||input.code!==(input.outcome==='pending'?'JOB_PENDING':'RETRYABLE_FAILURE')||!integer(input.retry_after_seconds,1,300))return null;
      fields.push('code','retry_after_seconds');break;
    case 'rejected':
      if(typeof input.code!=='string'||!Object.hasOwn(codes,input.code)||status!==codes[input.code])return null;
      fields.push('code');
      if(input.code==='VERSION_CONFLICT') {if(!integer(input.current_version))return null;fields.push('current_version');}
      break;
    default:return null;
  }
  if(Object.keys(input).length!==fields.length||Object.keys(input).some(k=>!fields.includes(k)))return null;
  // Flat allowlist, detached from the response object. No free text/details/PII.
  return Object.fromEntries(fields.map(k=>[k,input[k]])) as unknown as IsgMutationOutcome;
}

export type MutationPhase='prepared'|'submitting'|'reconciling'|'committed'|'blocked'|'detached';
export type MutationEvent='submit'|'transport_loss'|'committed'|'pending'|'indeterminate'|'rejected'|'account_changed';
export interface MutationTransition {phase:MutationPhase;effect:'none'|'submit_same_key'|'reconcile_same_operation'|'show_committed'|'show_blocked'|'detach';}
/** sameContext is computed by a coordinator from operation ID AND session epoch.
 * No automatic retry, new key, authentication decision or background effect here.
 * A changed draft/new intent must create a new state outside this reducer. */
export function transitionIsgMutation(phase:MutationPhase,event:MutationEvent,sameContext:boolean):MutationTransition {
  if(!sameContext||phase==='detached')return {phase,effect:'none'};
  if(event==='account_changed')return {phase:'detached',effect:'detach'};
  if(phase==='prepared'&&event==='submit')return {phase:'submitting',effect:'submit_same_key'};
  if(phase!=='submitting'&&phase!=='reconciling')return {phase,effect:'none'};
  if(event==='committed')return {phase:'committed',effect:'show_committed'};
  if(event==='rejected')return {phase:'blocked',effect:'show_blocked'};
  if(['transport_loss','pending','indeterminate'].includes(event))return {phase:'reconciling',effect:'reconcile_same_operation'};
  return {phase,effect:'none'};
}
