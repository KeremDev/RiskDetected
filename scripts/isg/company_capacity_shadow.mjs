// P03 dry-run model only. No imports, database writes, network, identity lookup or
// production authorization. Eligibility and capacities must come from reviewed
// server evidence; profiles.tier, client claims and current usage are not proof.
const fields = ['billing_state', 'eligibility', 'legacy_contract', 'existing_floor', 'candidate_capacity', 'active_company_count', 'protected_active_company_count'];
const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const count = value => Number.isSafeInteger(value) && value >= 0;
function capacity(value) {
  return record(value) && ((value.kind === 'finite' && Object.keys(value).length === 2 && count(value.value)) ||
    (['unlimited', 'unknown'].includes(value.kind) && Object.keys(value).length === 1));
}
const copy = value => value.kind === 'finite' ? { kind: 'finite', value: value.value } : { kind: value.kind };
function maximum(values) {
  if (values.some(v => v.kind === 'unlimited')) return { kind: 'unlimited' };
  return { kind: 'finite', value: Math.max(...values.map(v => v.value)) };
}
export function proposeCompanyCapacity(input) {
  const unchanged = { writes_performed: false, would_delete_companies: false, would_grant_paid_access: false, publishable: false };
  if (!record(input) || Object.keys(input).length !== fields.length || fields.some(key => !Object.hasOwn(input, key)) ||
      !['verified_paid', 'verified_free', 'sync_pending'].includes(input.billing_state) ||
      !['eligible', 'ineligible', 'unknown'].includes(input.eligibility) ||
      ![input.legacy_contract, input.existing_floor, input.candidate_capacity].every(capacity) ||
      !count(input.active_company_count) || !count(input.protected_active_company_count) || input.protected_active_company_count > input.active_company_count) {
    return { ...unchanged, status: 'invalid', reason: 'VALIDATION_ERROR' };
  }
  if (input.billing_state === 'sync_pending') {
    return { ...unchanged, status: 'deferred', reason: 'SUBSCRIPTION_SYNC_PENDING', retained_floor: copy(input.existing_floor), effective_capacity: { kind: 'unknown' } };
  }
  if (input.eligibility === 'unknown' || input.existing_floor.kind === 'unknown' || input.candidate_capacity.kind === 'unknown' ||
      (input.eligibility === 'eligible' && input.legacy_contract.kind === 'unknown')) {
    return { ...unchanged, status: 'review_required', reason: 'CAPACITY_EVIDENCE_INCOMPLETE', retained_floor: copy(input.existing_floor), effective_capacity: { kind: 'unknown' } };
  }
  // A known previously earned floor survives regardless of current subscription.
  const proposed = maximum([input.existing_floor,
    // A currently Free account cannot bank a new paid candidate limit for later.
    ...(input.billing_state === 'verified_paid' ? [input.candidate_capacity] : []),
    { kind: 'finite', value: input.protected_active_company_count },
    ...(input.eligibility === 'eligible' ? [input.legacy_contract] : [])]);
  // A capacity floor is NOT a paid entitlement or a sponsor gift. Downgrade never
  // deletes records, and preserving a floor does not grant new paid operations.
  const effective = input.billing_state === 'verified_paid' ? copy(proposed) : { kind: 'finite', value: 0 };
  return { ...unchanged, status: 'proposal', proposed_preserved_floor: proposed, effective_capacity: effective,
    can_create_company: input.billing_state === 'verified_paid' && (effective.kind === 'unlimited' || input.active_company_count < effective.value),
    read_only_excess_count: effective.kind === 'unlimited' ? 0 : Math.max(0, input.active_company_count - effective.value) };
}
