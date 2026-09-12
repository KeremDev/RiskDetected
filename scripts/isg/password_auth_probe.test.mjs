import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { probePasswordAuth } from './password_auth_probe.mjs';
import { probeSignupRecovery } from './signup_recovery_probe.mjs';

test('password boundary probe refuses non-synthetic callers before any HTTP request', () => {
  let calls = 0;
  for (const synthetic of [false, null, undefined, 'true', 1]) {
    assert.throws(() => probePasswordAuth({synthetic, request:()=>calls++}), /SYNTHETIC_REQUIRED/);
  }
  assert.equal(calls, 0);
});
test('confirmation and recovery probe refuses non-synthetic input before HTTP or mailbox access', () => {
  let calls = 0;
  for (const synthetic of [false, null, undefined, 'true', 1]) {
    assert.throws(() => probeSignupRecovery({synthetic, request:()=>calls++, mailbox:()=>calls++}), /SYNTHETIC_REQUIRED/);
  }
  assert.equal(calls, 0);
});
test('SMTP and mailbox are loopback-only, bounded memory, and not a production mail service', () => {
  const sink = readFileSync(new URL('./auth_mail_sink.cjs', import.meta.url), 'utf8');
  assert.match(sink, /listen\(2525, '127\.0\.0\.1'\)/);
  assert.match(sink, /listen\(10000, '127\.0\.0\.1'\)/);
  assert.match(sink, /messages\.length > 32/);
  assert.match(sink, /128 \* 1024/);
  assert.doesNotMatch(sink, /require\(['"](?:node:)?(?:fs|child_process)|console\.|writeFile|fetch\(/);
  const runner = readFileSync(new URL('./run_auth_restore.mjs', import.meta.url), 'utf8');
  assert.match(runner, /synthetic \? readFileSync\(resolve\(ROOT,'scripts\/isg\/auth_mail_sink.cjs'\)/);
  assert.match(runner, /function mailbox\(\) \{\s*if \(!synthetic\) throw/);
  assert.match(runner, /probeSignupRecovery\(\{synthetic:true,request,mailbox,admin,pass\}\)/);
});
test('shared password corpus has unique IDs and documents the server Unicode-minimum gap', () => {
  const corpus = JSON.parse(readFileSync(new URL('../../contracts/isg/v1/fixtures/password-rules.json', import.meta.url), 'utf8'));
  assert.equal(corpus.cases.length, 20);
  assert.equal(new Set(corpus.cases.map(c=>c.id)).size, corpus.cases.length);
  assert.ok(corpus.cases.some(c=>c.password === 'Ab1🔐🔐' && c.valid === false));
  for (const path of ['../../App/Services/Auth/IsgPasswordRules.swift', '../../android/core/data/src/main/kotlin/com/riskdetectedan/core/data/auth/IsgPasswordRules.kt']) {
    const source = readFileSync(new URL(path,import.meta.url),'utf8');
    assert.match(source,/72/);
    assert.match(source,/8/);
  }
});
test('password settings and probe are confined to the disposable synthetic lane', () => {
  const source = readFileSync(new URL('./run_auth_restore.mjs', import.meta.url), 'utf8');
  assert.match(source, /synthetic \? \{ GOTRUE_PASSWORD_MIN_LENGTH:'8'/);
  assert.match(source, /if \(mode.synthetic\) \{\s*stage = 'password-auth-boundaries'/);
  assert.match(source, /probePasswordAuth\(\{synthetic:true, request, admin, pass\}\)/);
  assert.match(source, /'scripts\/isg\/password_auth_probe.mjs'/);
});
test('password adapter preserves raw input and cancellation and does not serialize SDK failures', () => {
  const source = readFileSync(new URL('../../android/core/data/src/main/kotlin/com/riskdetectedan/core/data/auth/PasswordSignIn.kt', import.meta.url), 'utf8');
  assert.match(source, /this.password = password/);
  assert.match(source, /catch \(cancelled: CancellationException\) \{\s*throw cancelled/);
  assert.doesNotMatch(source, /password\.(trim|lowercase|uppercase|take|substring|normalize)|cause\s*=|\.message|print|logger/i);
});
test('SDK Auth diagnostics are disabled and autoconfirm checks actual SDK session state', () => {
  const module = readFileSync(new URL('../../android/core/data/src/main/kotlin/com/riskdetectedan/core/data/SupabaseModule.kt', import.meta.url),'utf8');
  assert.match(module,/install\(Auth\) \{[\s\S]*?logLevel = LogLevel.NONE/);
  const enrollment = readFileSync(new URL('../../android/core/data/src/main/kotlin/com/riskdetectedan/core/data/auth/PasswordEnrollment.kt', import.meta.url),'utf8');
  assert.match(enrollment,/response == null \|\| client.auth.currentSessionOrNull\(\) != null/);
  assert.doesNotMatch(enrollment,/password\.(trim|lowercase|uppercase|normalize)|\.message|cause\s*=/);
});
