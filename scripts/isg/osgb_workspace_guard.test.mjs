import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {ROOT} from './lib.mjs';

const migration = readFileSync(`${ROOT}/supabase/pilot-release/candidates/20260917090000_osgb_workspace_foundation.sql`, 'utf8');

test('OSGB workspace foundation remains additive, fail-closed and not a deployed ledger mirror', () => {
  assert.match(migration, /CREATE TABLE private_isg\.workspaces/);
  assert.match(migration, /CREATE TABLE private_isg\.workspace_memberships/);
  assert.match(migration, /CREATE TABLE private_isg\.workspace_invitations/);
  assert.match(migration, /CREATE TABLE private_isg\.workspace_audit/);
  assert.match(migration, /CREATE TABLE private_isg\.workspace_outbox/);
  assert.match(migration, /INSERT INTO private_isg\.workspace_rollout\(feature\) VALUES/);
  assert.doesNotMatch(migration, /read_enabled\s*,\s*write_enabled\)[^;]*true/is);
  assert.match(migration, /SEAT_AUTHORITY_UNAVAILABLE/);
  assert.match(migration, /VALUES\('osgb',clean_name,'pending_purchase'/);
  assert.match(migration, /token_persisted',false/);
  assert.match(migration, /REVOKE ALL ON private_isg\.workspace_rollout/);
  assert.doesNotMatch(migration, /service_role[^;]*GRANT/i);
  assert.doesNotMatch(migration, /ALTER TABLE public\.(companies|profiles)/);
  assert.doesNotMatch(migration, /UPDATE public\.(companies|profiles)/);
  assert.doesNotMatch(migration, /INSERT INTO public\.(companies|profiles)/);
});

test('workspace identity remains separate from the legacy company availability helper', () => {
  assert.match(migration, /isg_workspace_list_v1/);
  assert.match(migration, /isg_workspace_context_v1/);
  assert.doesNotMatch(migration, /CREATE OR REPLACE FUNCTION private_isg\.workspace_availability/);
  assert.doesNotMatch(migration, /CREATE OR REPLACE FUNCTION private_isg\.require_company/);
  assert.doesNotMatch(migration, /p05_pilot_can_read/);
});
