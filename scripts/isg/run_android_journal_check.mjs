import { execFileSync } from 'node:child_process';
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';

// Explicit emulator only; this command never clears, installs or opens the real application.
const [adb, serial] = process.argv.slice(2);
assert.equal(process.argv.length, 4, 'Usage: node scripts/isg/run_android_journal_check.mjs <adb> emulator-N');
assert.match(serial, /^emulator-\d+$/);
const call = (...args) => execFileSync(adb, ['-s', serial, ...args], { encoding: 'utf8', timeout: 30000 });
assert.equal(call('shell', 'getprop', 'ro.kernel.qemu').trim(), '1');
assert.equal(call('shell', 'getprop', 'sys.boot_completed').trim(), '1');
const app = 'com.riskdetectedan.isg.journalcheck';
const apk = resolve('android/isg-journal-check/build/outputs/apk/debug/isg-journal-check-debug.apk');
const source = 'android/core/data/src/main/kotlin/com/riskdetectedan/core/data/company/PersonnelPendingStorage.kt';
const generated = 'android/isg-journal-check/build/generated/journal/PersonnelPendingStorage.kt';
const hash = path => createHash('sha256').update(readFileSync(path)).digest('hex');
assert.equal(hash(source), hash(generated), 'QA must compile the actual current production journal');
call('install', '-r', apk);
const report = { schema_version: 1, started_at: new Date().toISOString(), serial,
  package: app, production_accessed: false, network_used: false,
  source_sha256: { [source]: hash(source), [apk]: hash(apk) }, checks: [] };
const expectations = [
  ['write', 'PASS write encryption randomized-iv size-bound aad namespace'],
  ['read', 'PASS restart durable-read tamper-rejected isolated-clear'],
];
try {
  for (const [phase, expected] of expectations) {
    call('shell', 'am', 'force-stop', app);
    call('shell', 'am', 'start', '-W', '-n', `${app}/.JournalActivity`, '--es', 'phase', phase);
    let found = false;
    for (let attempt = 0; attempt < 5; attempt++) {
      call('shell', 'uiautomator', 'dump', '/sdcard/isg-journal-check.xml');
      const xml = call('shell', 'cat', '/sdcard/isg-journal-check.xml');
      if (xml.includes(expected)) { found = true; break; }
      if (xml.includes('text="FAIL"')) throw new Error(`Journal ${phase} failed`);
      await new Promise(resolve => setTimeout(resolve, 500));
    }
    assert.ok(found, `Expected actual rendered result: ${expected}`);
    report.checks.push({ phase, result: expected });
  }
  report.ok = true;
} finally {
  call('shell', 'am', 'force-stop', app);
  report.finished_at = new Date().toISOString();
  mkdirSync('output/isg', { recursive: true });
  writeFileSync('output/isg/android-journal-check.json', JSON.stringify(report, null, 2) + '\n');
}
console.log(JSON.stringify(report, null, 2));
