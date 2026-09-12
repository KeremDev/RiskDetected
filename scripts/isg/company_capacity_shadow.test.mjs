import assert from 'node:assert/strict';
import { test } from 'node:test';
import { proposeCompanyCapacity } from './company_capacity_shadow.mjs';

const finite = value => ({ kind: 'finite', value });
const fixture = { billing_state: 'verified_paid', eligibility: 'eligible', legacy_contract: finite(5), existing_floor: finite(0),
  candidate_capacity: finite(3), active_company_count: 1, protected_active_company_count: 1 };

for (const usage of [0, 1, 3, 5]) test(`old Plus entitlement 5 is preserved when actual company usage is ${usage}`, () => {
  const result = proposeCompanyCapacity({ ...fixture, active_company_count: usage, protected_active_company_count: usage });
  assert.equal(result.status, 'proposal'); assert.deepEqual(result.proposed_preserved_floor, finite(5));
  assert.equal(result.can_create_company, usage < 5); assert.equal(result.publishable, false);
});
test('Pro 25 to candidate 30 increases capacity only in the shadow proposal', () => {
  assert.deepEqual(proposeCompanyCapacity({ ...fixture, legacy_contract: finite(25), candidate_capacity: finite(30) }).effective_capacity, finite(30));
});
test('previous floor and protected valid usage cannot shrink', () => {
  assert.deepEqual(proposeCompanyCapacity({ ...fixture, existing_floor: finite(9) }).proposed_preserved_floor, finite(9));
  assert.deepEqual(proposeCompanyCapacity({ ...fixture, active_company_count: 7, protected_active_company_count: 7 }).proposed_preserved_floor, finite(7));
});
test('unlimited remains explicit, never null or an arbitrary large number', () => {
  for (const key of ['legacy_contract', 'existing_floor', 'candidate_capacity']) {
    const result = proposeCompanyCapacity({ ...fixture, [key]: { kind: 'unlimited' } });
    assert.deepEqual(result.proposed_preserved_floor, { kind: 'unlimited' }); assert.equal(result.can_create_company, true);
  }
});
test('verified free keeps earned floor but never gains paid access or deletes companies', () => {
  const result = proposeCompanyCapacity({ ...fixture, billing_state: 'verified_free', candidate_capacity: finite(0) });
  assert.deepEqual(result.proposed_preserved_floor, finite(5)); assert.deepEqual(result.effective_capacity, finite(0));
  assert.equal(result.can_create_company, false); assert.equal(result.read_only_excess_count, 1);
  assert.equal(result.would_grant_paid_access, false); assert.equal(result.would_delete_companies, false);
});
test('sync pending is not Free and cannot erase the previous floor or create a gift', () => {
  const result = proposeCompanyCapacity({ ...fixture, billing_state: 'sync_pending', existing_floor: { kind: 'unlimited' } });
  assert.equal(result.status, 'deferred'); assert.deepEqual(result.effective_capacity, { kind: 'unknown' });
  assert.deepEqual(result.retained_floor, { kind: 'unlimited' }); assert.equal(Object.hasOwn(result, 'can_create_company'), false);
});
test('Free cannot bank a paid candidate capacity as a newly earned floor', () => {
  const result = proposeCompanyCapacity({ ...fixture, billing_state: 'verified_free', candidate_capacity: finite(30) });
  assert.deepEqual(result.proposed_preserved_floor, finite(5)); assert.deepEqual(result.effective_capacity, finite(0));
});
test('missing cutoff eligibility or required capacity evidence requires review', () => {
  for (const change of [{ eligibility: 'unknown' }, { existing_floor: { kind: 'unknown' } }, { candidate_capacity: { kind: 'unknown' } }, { legacy_contract: { kind: 'unknown' } }]) {
    assert.equal(proposeCompanyCapacity({ ...fixture, ...change }).status, 'review_required');
  }
});
test('new ineligible customer does not gain a legacy contract floor', () => {
  assert.deepEqual(proposeCompanyCapacity({ ...fixture, eligibility: 'ineligible' }).proposed_preserved_floor, finite(3));
  assert.equal(proposeCompanyCapacity({ ...fixture, eligibility: 'ineligible', legacy_contract: { kind: 'unknown' } }).status, 'proposal');
});
test('unverified excess usage is not silently converted into an earned floor', () => {
  const result = proposeCompanyCapacity({ ...fixture, active_company_count: 7, protected_active_company_count: 1 });
  assert.deepEqual(result.proposed_preserved_floor, finite(5)); assert.equal(result.read_only_excess_count, 2); assert.equal(result.would_delete_companies, false);
});
test('late app update does not affect explicitly supplied cutoff eligibility', () => {
  assert.deepEqual(proposeCompanyCapacity(fixture).proposed_preserved_floor, finite(5));
  // The model intentionally accepts no app-update timestamp; only reviewed eligibility.
  assert.equal(proposeCompanyCapacity({ ...fixture, client_updated_at: '2030-01-01' }).status, 'invalid');
});
test('malformed values, client owner/tier and gift fields are rejected without leaking them', () => {
  const invalid = [null, [], {}, { ...fixture, owner: 'sentinel-private' }, { ...fixture, gift: true }, { ...fixture, profile_tier: 'pro' },
    { ...fixture, active_company_count: -1 }, { ...fixture, active_company_count: 1.5 }, { ...fixture, active_company_count: Infinity },
    { ...fixture, active_company_count: Number.MAX_SAFE_INTEGER + 1 }, { ...fixture, protected_active_company_count: 2 },
    { ...fixture, legacy_contract: null }, { ...fixture, legacy_contract: { kind: 'finite', value: '5' } },
    { ...fixture, legacy_contract: { kind: 'unlimited', value: 999 } }, { ...fixture, billing_state: 'profile_plus' }];
  for (const input of invalid) { const result = proposeCompanyCapacity(input); assert.equal(result.status, 'invalid'); assert.equal(JSON.stringify(result).includes('sentinel-private'), false); }
});
test('returned values are detached from mutable caller input', () => {
  const input = structuredClone(fixture), result = proposeCompanyCapacity(input); input.legacy_contract.value = 999;
  assert.deepEqual(result.proposed_preserved_floor, finite(5));
});
test('finite capacity matrix is monotone, side-effect-free and preserves all justified minima', () => {
  let combinations = 0;
  for (const old of [0, 3, 5, 25]) for (const previous of [0, 5, 30]) for (const candidate of [0, 3, 30])
    for (const usage of [0, 1, 3, 5, 25, 30]) for (const eligibility of ['eligible', 'ineligible']) for (const billing_state of ['verified_paid', 'verified_free']) {
      const input = { ...fixture, legacy_contract: finite(old), existing_floor: finite(previous), candidate_capacity: finite(candidate),
        active_company_count: usage, protected_active_company_count: usage, eligibility, billing_state };
      const before = JSON.stringify(input), result = proposeCompanyCapacity(input);
      const expected = Math.max(previous, billing_state === 'verified_paid' ? candidate : 0, usage, eligibility === 'eligible' ? old : 0);
      assert.deepEqual(result.proposed_preserved_floor, finite(expected));
      assert.deepEqual(result.effective_capacity, finite(billing_state === 'verified_paid' ? expected : 0));
      assert.equal(result.writes_performed, false); assert.equal(result.would_grant_paid_access, false); assert.equal(JSON.stringify(input), before);
      combinations++;
    }
  assert.equal(combinations, 864);
});
