import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const slice=read('supabase/migrations/20260915250000_isg_emergency_plan_support_staff.sql');
const checks=read('scripts/isg/emergency_plan_support_staff_check.sql');
const models=read('App/DesignSystem/ISG/NovaEmergencyPlans.swift');
const service=read('App/Services/Company/NovaEmergencyPlanService.swift');
const sheets=read('App/DesignSystem/ISG/NovaEmergencyPlanSheets.swift');
const appointmentSheets=read('App/DesignSystem/ISG/NovaAppointmentSheets.swift');
/** Comments explain the rule; they are not evidence that the rule is there. */
const code=source=>source.split('\n').filter(line=>!line.trimStart().startsWith('--')).join('\n');

test('the slice opens no switch and adds no table',()=>{
  assert.doesNotMatch(slice,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(slice,/UPDATE private_isg\.module_registry SET/);
  assert.doesNotMatch(slice,/CREATE TABLE/);
});

test('a closed appointment module empties the list, not the catalog',()=>{
  assert.match(code(slice),/appointment_module_open:=coalesce/);
  assert.match(code(slice),/ELSE '\[\]'::jsonb END/);
  assert.match(checks,/a closed appointment module suggests nothing/);
  assert.match(checks,/and the emergency plan catalog itself still answers/);
});

test('only support_staff appointments are suggested, company-wide, currently held',()=>{
  assert.match(code(slice),/a\.kind='support_staff'/);
  assert.match(code(slice),/a\.ends_before IS NULL OR a\.ends_before>=today/);
  assert.match(checks,/only the support staff appointment is suggested/);
  assert.match(checks,/an ended support staff appointment is not suggested/);
});

test('the suggestion is a name to borrow, not a link stored anywhere',()=>{
  assert.match(checks,/the picked name lands in the team exactly as any typed name would/);
  assert.match(checks,/the plan itself stores no pointer back to any appointment/);
  assert.match(models,/A suggestion only: picking one lends a name/);
});

test('the dev/live schema divergence is documented, not silently patched over',()=>{
  assert.doesNotMatch(code(slice),/is_deleted/);
  assert.match(slice,/pilot-release mirror of this\n-- file adds `AND NOT a\.is_deleted`/);
});

test('the client decodes an absent field rather than assuming the server always sends it',()=>{
  assert.match(service,/support_staff: \[SupportStaffRow\]\?/);
  assert.match(service,/envelope\.support_staff \?\? \[\]/);
});

test('the team editor offers the roster but never auto-submits a name',()=>{
  assert.match(sheets,/supportStaffPicker/);
  assert.match(sheets,/memberName = person\.fullName/);
  assert.doesNotMatch(sheets,/draft\.team\.append.*person\.fullName/);
});

test('the appointment person picker searches locally instead of listing everyone',()=>{
  assert.match(appointmentSheets,/NovaAnalysisSearchField\(text: \$personSearch/);
  assert.match(appointmentSheets,/localizedCaseInsensitiveContains\(needle\)/);
  assert.match(appointmentSheets,/matchingEmployees\.isEmpty/);
});
