import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginPersonalNotesProbe,personalNotesFiles} from './personal_notes_probe.mjs';

const migration=readFileSync(resolve(ROOT,personalNotesFiles[0]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginPersonalNotesProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginPersonalNotesProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('the notebook ships disabled, private and without a client grant',()=>{
  assert.match(migration,/INSERT INTO private_isg\.rollout\(feature\) VALUES\('personal_notes'\)/);
  assert.doesNotMatch(migration,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(migration,/GRANT (EXECUTE|SELECT|INSERT|UPDATE|DELETE|ALL)[\s\S]{0,400}?TO (anon|authenticated|service_role)/);
  const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  assert.equal(created.length,8);
  for(const table of created) assert.ok(secured.has(table),table);
});

test('no company domain can be reached and no paid plan is consulted',()=>{
  // Column definitions only: the file's prose may mention a company.
  assert.doesNotMatch(migration,/^\s*\w*(company|workplace|employee|entity)\w*\s+(uuid|text|jsonb)/mi);
  assert.doesNotMatch(migration,/require_company|user_plan_tier|user_subscriptions/);
  assert.doesNotMatch(migration,/REFERENCES private_isg\.file_assets/);
  assert.doesNotMatch(migration,/^\s*\w*attachment\w*\s+(uuid|text|jsonb)/mi);
});

test('a version clash keeps both texts',()=>{
  assert.match(migration,/CREATE TABLE private_isg\.note_conflicts/);
  assert.match(migration,/'both_texts_preserved',true/);
  assert.match(migration,/incoming_title text, incoming_body text,\n\s*server_title text, server_body text/);
});

test('a tombstone cannot be resurrected and clears its text',()=>{
  assert.match(migration,/MESSAGE='NOTE_TOMBSTONED'/);
  assert.match(migration,/CHECK\(NOT tombstone OR \(title IS NULL AND body IS NULL\)\)/);
});

test('an occurrence settles alone and delivery has exactly one owner',()=>{
  assert.match(migration,/UNIQUE\(reminder_id,occurrence_no\)/);
  assert.match(migration,/'series_closed',false/);
  assert.match(migration,/reminder_id uuid PRIMARY KEY REFERENCES private_isg\.personal_reminders/);
  assert.match(migration,/'exactly_once_promised',false/);
  assert.match(migration,/delivery_guarantee='at_most_once_per_installation'/);
});

test('occurrences keep the local wall clock across a daylight saving change',()=>{
  assert.match(migration,/local_stamp AT TIME ZONE entry\.timezone/);
  assert.match(migration,/local_due_at timestamp NOT NULL/);
});

test('the runner wires the probe and hashes the migration',()=>{
  assert.match(runner,/beginPersonalNotesProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? personalNotesFiles : \[\]\)/);
  assert.match(runner,/notesProbe\.afterLogout\(\)/);
});
