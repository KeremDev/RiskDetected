#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { ROOT } from './lib.mjs';

// Deliberately no arbitrary command, shell, live target, env fallback or cleanup.
const suites = {
  foundation: ['--test', 'scripts/isg/foundation.test.mjs', 'scripts/isg/function_map.test.mjs', 'scripts/isg/ios_contract_inventory.test.mjs', 'scripts/isg/backup_crypto.test.mjs', 'scripts/isg/auth_restore_guard.test.mjs', 'scripts/isg/storage_restore_probe.test.mjs', 'scripts/isg/auth_session_probe.test.mjs', 'scripts/isg/auth_mutation_probe.test.mjs', 'scripts/isg/android_contract_guard.test.mjs', 'scripts/client_flow_contract_test.mjs', 'scripts/isg/workplace_probe.test.mjs', 'scripts/isg/personnel_probe.test.mjs', 'scripts/isg/assignment_move.test.mjs'],
  'capacity-shadow': ['--test', 'scripts/isg/company_capacity_shadow.test.mjs'],
  'nova-design': ['--test', 'scripts/isg/nova_tokens.test.mjs', 'scripts/isg/nova_icons.test.mjs', 'scripts/isg/nova_session_host.test.mjs', 'scripts/isg/nova_company_list.test.mjs'],
  'password-auth': ['--test', 'scripts/isg/password_auth_probe.test.mjs'],
};
const [suite, ...extra] = process.argv.slice(2);
suites.foundation.push('scripts/isg/employee_intake.test.mjs');
suites.foundation.push('scripts/isg/personnel_directory.test.mjs');
suites.foundation.push('scripts/isg/directory_migration_guard.test.mjs');
suites.foundation.push('scripts/isg/dispatch_quota_guard.test.mjs');
suites.foundation.push('scripts/isg/file_core_guard.test.mjs');
suites.foundation.push('scripts/isg/rule_core_guard.test.mjs');
suites.foundation.push('scripts/isg/training_core_guard.test.mjs');
suites.foundation.push('scripts/isg/risk_core_guard.test.mjs');
suites.foundation.push('scripts/isg/nonconformity_core_guard.test.mjs');
suites.foundation.push('scripts/isg/module_core_guard.test.mjs');
suites.foundation.push('scripts/isg/module_second_guard.test.mjs');
suites.foundation.push('scripts/isg/document_import_guard.test.mjs');
suites.foundation.push('scripts/isg/notification_core_guard.test.mjs');
suites.foundation.push('scripts/isg/personal_notes_guard.test.mjs');
suites.foundation.push('scripts/isg/notification_dispatch_guard.test.mjs');
suites.foundation.push('scripts/isg/notification_worker.test.mjs');
suites.foundation.push('scripts/isg/notification_repository.test.mjs','scripts/isg/notification_repository_guard.test.mjs');
suites.foundation.push('scripts/isg/notification_journal.test.mjs');
suites.foundation.push('scripts/isg/notification_device_guard.test.mjs');
suites.foundation.push('scripts/isg/notebook_api_guard.test.mjs');
suites.foundation.push('scripts/isg/notebook_reminder_guard.test.mjs');
suites.foundation.push('scripts/isg/notebook_native.test.mjs');
suites.foundation.push('scripts/isg/billing_lifecycle_guard.test.mjs');
if (!Object.hasOwn(suites, suite) || extra.length) {
  console.error('Usage: node scripts/isg/run_suite.mjs foundation|capacity-shadow|nova-design|password-auth; only offline suites are enabled here.');
  process.exitCode = 1;
} else {
  const result = spawnSync(process.execPath, suites[suite], { cwd: ROOT, stdio: 'inherit', shell: false, timeout: 120_000,
    env: { PATH: process.env.PATH ?? '', TZ: 'Europe/Istanbul', LANG: 'C.UTF-8' } });
  process.exitCode = result.status ?? 1;
}
