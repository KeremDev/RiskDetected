#!/usr/bin/env node
import { spawn, spawnSync } from 'node:child_process';
import { createHmac, randomBytes, randomUUID, createHash } from 'node:crypto';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve, relative } from 'node:path';
import { ROOT } from './lib.mjs';
import { assertNoExposedRestoreContainer, resolvePinnedRestoreImage } from './auth_restore_guard.mjs';
import { probeStorageRestore } from './storage_restore_probe.mjs';
import { parseRestoreMode } from './restore_mode.mjs';
import { beginSessionProbe } from './auth_session_probe.mjs';
import { beginAuthMutationProbe } from './auth_mutation_probe.mjs';
import { beginAuthPersonnelProbe, personnelAuthFiles } from './auth_personnel_probe.mjs';
import { beginPersonnelMigrationProbe, personnelMigrationFiles } from './personnel_migration_probe.mjs';
import { beginPersonnelHTTPProbe } from './personnel_http_probe.mjs';
import { probePersonnelAdvisors } from './personnel_advisor_probe.mjs';
import { probePasswordAuth } from './password_auth_probe.mjs';
import { probeSignupRecovery } from './signup_recovery_probe.mjs';

// Restore drill only. The proven source container is read-only; all API writes
// target a new disposable copy with a shared NONE network namespace. No ports,
// mounts, SMTP/OAuth credentials, production JWT secrets or external endpoints.
const source = 'isg_restore_20260912_db';
const names = { db: 'isg_auth_restore_20260912_db', auth: 'isg_auth_restore_20260912_auth', client: 'isg_auth_restore_20260912_client' };
const withStorage = process.argv.includes('--with-storage');
const synthetic = process.argv.length === 3 && process.argv[2] === '--synthetic-session';
if (synthetic) for (const kind of Object.keys(names)) names[kind] = `isg_test_auth_session_${kind}`;
if (synthetic) names.rest = 'isg_test_auth_session_rest';
if (withStorage) names.storage = 'isg_auth_restore_20260912_storage';
const images = {
  db: 'public.ecr.aws/supabase/postgres@sha256:3866d94d8426927e8db3f1c5d790752292bfbe27b5f1f46e199ae1b7d3c1710b',
  auth: 'public.ecr.aws/supabase/gotrue@sha256:362659ca70eaa75ba05bbaf963caa84c1c5afe5e8fbf0777e17b830dd5f0f60a',
  client: 'public.ecr.aws/supabase/storage-api@sha256:28424184c9f699790cc190f78ddf7d6abfb5c87af78af260529a394d12c135e9',
};
if (withStorage) images.storage = images.client;
if (synthetic) images.rest = 'public.ecr.aws/supabase/postgrest@sha256:2f8e7b656f09db697a8875177694b417b35cb76c21370de07fc54e711e902326';
const owned = new Map(), run = randomUUID(), label = 'com.riskdetected.isg-auth-restore';
const resolvedImages = new Map();
const report = { schema_version: 1, run_id: run, started_at: new Date().toISOString(), mode: synthetic ? 'synthetic_auth_session' : 'isolated_restored_copy',
  images, checks: [], external_egress: false, ports_published: false, source_database_changed: false,
  storage_api_tested: false, mobile_e2e_tested: false, full_application_restore_proven: false };
let target, stage = 'preflight';
const digest = b => createHash('sha256').update(b).digest('hex');
function docker(args, options = {}) {
  return spawnSync('docker', args, { encoding: 'utf8', timeout: 45_000, maxBuffer: 128 * 1024 * 1024, ...options });
}
function inspect(name) {
  const r = docker(['inspect', name]);
  if (r.status !== 0) throw new Error('AUTH_RESTORE_CONTAINER_MISSING');
  return JSON.parse(r.stdout)[0];
}
function commonGuard(i) {
  assertNoExposedRestoreContainer(i);
}
function imageId(kind) {
  if (!resolvedImages.has(kind)) {
    const r = docker(['image','inspect',images[kind]]);
    if (r.status !== 0) throw new Error('AUTH_RESTORE_PINNED_IMAGE_MISSING');
    resolvedImages.set(kind,resolvePinnedRestoreImage(JSON.parse(r.stdout)[0],images[kind]));
    report.image_resolution = Object.fromEntries(resolvedImages);
  }
  return resolvedImages.get(kind).id;
}
function sourceGuard() {
  if (synthetic) throw new Error('AUTH_RESTORE_SOURCE_FORBIDDEN_IN_SYNTHETIC_MODE');
  const i = inspect(source); commonGuard(i);
  if (i.Name !== `/${source}` || i.Config.Labels?.['com.riskdetected.isg-restore'] !== '20260912' ||
      i.HostConfig.NetworkMode !== 'none' || !i.State.Running || i.Image !== imageId('db')) throw new Error('AUTH_RESTORE_SOURCE_INVALID');
}
function guard(kind, running = true) {
  const i = inspect(names[kind]); commonGuard(i);
  if (i.Id !== owned.get(kind) || i.Name !== `/${names[kind]}` || i.Config.Labels?.[label] !== run ||
      i.Image !== imageId(kind) || (running && !i.State.Running) ||
      i.HostConfig.NetworkMode !== (kind === 'db' ? 'none' : `container:${owned.get('db')}`)) throw new Error('AUTH_RESTORE_OWNERSHIP_FAILED');
  if (kind !== 'db') guard('db');
}
function checked(result, code) {
  if (result.status !== 0) {
    if (target) writeFileSync(resolve(target, `${stage}-diagnostic.txt`), result.stderr || 'Process failed', { mode: 0o600 });
    throw new Error(code);
  }
  return result.stdout;
}
function sql(query, original = false) {
  original ? sourceGuard() : guard('db');
  return checked(docker(['exec', '-i', original ? source : names.db, 'psql', '-X', '-U', 'supabase_admin', '-d', 'postgres',
    '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate', '-Atq'], { input: query, timeout: 90_000 }), 'AUTH_RESTORE_SQL_FAILED').trim();
}
async function concurrentSql(query) {
  guard('db');
  return await new Promise(resolve => {
    const child = spawn('docker', ['exec','-i',owned.get('db'),'psql','-X','-U','supabase_admin','-d','postgres',
      '-v','ON_ERROR_STOP=1','-v','VERBOSITY=sqlstate','-Atq'], { stdio:['pipe','pipe','pipe'], timeout:10_000 });
    let output = '';
    child.stdout.on('data', c => { if (output.length < 4096) output += c; });
    child.stderr.on('data', () => {}); // Auth/SQL diagnostics never enter stdout.
    child.on('error', () => resolve({ ok:false }));
    child.on('close', code => resolve({ ok:code === 0, output:output.trim() }));
    child.stdin.on('error', () => {});
    child.stdin.end(`SET statement_timeout='7s'; SET lock_timeout='3s'; ${query}`);
  });
}
function start(kind, env, command = []) {
  const args = ['run', '-d', '--name', names[kind], '--label', `${label}=${run}`, '--network',
    kind === 'db' ? 'none' : `container:${owned.get('db')}`, '--memory', kind === 'db' ? '1g' : '512m', '--cpus', '2', '--pids-limit', '128', '--pull', 'never'];
  for (const key of Object.keys(env)) args.push('--env', key);
  if (kind === 'client') args.push('--entrypoint', 'node');
  const id = checked(docker([...args, images[kind], ...command], { env: { PATH: process.env.PATH, ...env } }), 'AUTH_RESTORE_START_FAILED').trim();
  if (!/^[a-f0-9]{64}$/.test(id)) throw new Error('AUTH_RESTORE_CONTAINER_ID_INVALID');
  owned.set(kind, id); guard(kind);
}
const httpProgram = `const http = require('node:http'); let raw=''; process.stdin.on('data',c=>raw+=c); process.stdin.on('end',()=>{
const q=JSON.parse(raw); if(q.port!==9999 || !/^\\/(health|admin\\/users|token|user|logout|signup|verify|recover)([/?]|$)/.test(q.path))process.exit(2);
const req=http.request({host:'127.0.0.1',port:q.port,path:q.path,method:q.method,headers:{'Content-Type':'application/json',...(q.token?{Authorization:'Bearer '+q.token}:{})}},res=>{
let body='';res.on('data',c=>body+=c);res.on('end',()=>{let value;try{value=JSON.parse(body)}catch{value={}};process.stdout.write(JSON.stringify({status:res.statusCode,body:value}));});});
req.setTimeout(10000,()=>req.destroy());req.on('error',()=>process.exit(3));if(q.body)req.write(JSON.stringify(q.body));req.end();});`;
function request(path, { method = 'GET', token, body } = {}) {
  guard('auth'); guard('client');
  const r = docker(['exec', '-i', names.client, 'node', '-e', httpProgram], { input: JSON.stringify({ port: 9999, path, method, token, body }) });
  if (r.status !== 0) throw new Error('AUTH_RESTORE_HTTP_UNAVAILABLE');
  return JSON.parse(r.stdout);
}
function pass(id, condition) {
  if (!condition) throw new Error(`AUTH_RESTORE_CHECK_FAILED_${id}`);
  report.checks.push({ id, result: 'PASS' });
}
function mailbox() {
  if (!synthetic) throw new Error('AUTH_RESTORE_EMAIL_SYNTHETIC_REQUIRED');
  guard('client');
  const program = "require('node:http').get('http://127.0.0.1:10000/messages',r=>{let b='';r.on('data',c=>b+=c);r.on('end',()=>process.stdout.write(b));}).on('error',()=>process.exit(1));";
  const result = docker(['exec', '-i', names.client, 'node', '-e', program]);
  if (result.status !== 0) throw new Error('AUTH_RESTORE_MAILBOX_UNAVAILABLE');
  return JSON.parse(result.stdout);
}
function sign(secret, role, expiry = 3600, claims = {}) {
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const payload = `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({ ...claims, role, iss: 'supabase', iat: Math.floor(Date.now()/1000), exp: Math.floor(Date.now()/1000)+expiry })}`;
  return `${payload}.${createHmac('sha256', secret).update(payload).digest('base64url')}`;
}
async function waitReady(check) {
  for (let i = 0; i < 80; i++) {
    if (check()) return;
    await new Promise(r => setTimeout(r, 250));
  }
  throw new Error('AUTH_RESTORE_STARTUP_TIMEOUT');
}
async function startDatabase() {
  start('db', { POSTGRES_PASSWORD: randomBytes(32).toString('hex') }, ['postgres', '-D', '/etc/postgresql', '-c', 'listen_addresses=localhost',
    '-c', 'cron.launch_active_jobs=off', '-c', 'logging_collector=off', '-c', 'log_statement=none', '-c', 'log_min_error_statement=panic']);
  await waitReady(() => {
    guard('db');
    return docker(['exec', names.db, 'sh', '-c', 'test "$(cat /proc/1/comm)" = ".postgres-wrapp" && pg_isready -h 127.0.0.1 -U supabase_admin -d postgres']).status === 0;
  });
}
async function cleanup() {
  let ok = true;
  for (const kind of [...owned.keys()].reverse()) {
    try {
      guard(kind, false);
      if (docker(['rm', '-f', owned.get(kind)]).status !== 0) ok = false;
    } catch { ok = false; }
  }
  report.disposable_container_cleanup = ok ? 'PASS' : 'REQUIRES_REVIEW';
  if (!ok) report.ok = false;
}
function saveReport() {
  report.finished_at = new Date().toISOString();
  if (target) writeFileSync(resolve(target, 'REPORT.json'), JSON.stringify(report, null, 2) + '\n', { mode: 0o600 });
}
for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => {
  report.ok = false; report.failed_stage = stage; report.error_code = 'AUTH_RESTORE_INTERRUPTED';
  cleanup().then(() => { saveReport(); process.exit(130); });
});
try {
  const mode = parseRestoreMode(process.argv.slice(2));
  report.data_class = mode.synthetic ? 'synthetic' : 'restored_private_backup';
  report.original_source_accessed = !mode.synthetic;
  if (!mode.synthetic) sourceGuard();
  for (const name of Object.values(names)) if (docker(['inspect', name]).status === 0) throw new Error('AUTH_RESTORE_TARGET_ALREADY_EXISTS');
  for (const kind of Object.keys(images)) imageId(kind);
  if (!mode.synthetic) {
  const ledgerPath = resolve(ROOT, 'backups/isg-managed-migrations-20260912-osigPE/managed-migration-data.sql');
  const ledger = readFileSync(ledgerPath);
  if (digest(ledger) !== 'e027928e0d920f3cd616991af4a48378adb63daf33e53790c04bb90d4f384fe5') throw new Error('AUTH_RESTORE_LEDGER_DRIFT');
  target = mkdtempSync(resolve(ROOT, 'backups/isg-auth-service-restore-20260912-')); chmodSync(target, 0o700);
  report.source_before = sql("BEGIN READ ONLY; SELECT jsonb_build_object('users',(select count(*) from auth.users),'identities',(select count(*) from auth.identities),'profiles',(select count(*) from public.profiles),'objects',(select count(*) from storage.objects),'auth_migrations',(select count(*) from auth.schema_migrations),'storage_migrations',(select count(*) from storage.migrations)); COMMIT;", true);
  stage = 'logical-clone'; sourceGuard();
  const dump = checked(docker(['exec', source, 'pg_dump', '-U', 'supabase_admin', '-d', 'postgres', '-Fc'], { encoding: null, timeout: 90_000 }), 'AUTH_RESTORE_DUMP_FAILED');
  report.clone_dump_sha256 = digest(dump);
  pass('source_queue_payloads_empty', sql('BEGIN READ ONLY; select count(*) from pgmq.q_analysis_jobs; select count(*) from pgmq.a_analysis_jobs; COMMIT;', true) === '0\n0');
  // pg_dump excludes global roles. Inspect the whole non-system role inventory
  // up front, without password hashes, instead of patching individual ACL errors.
  const roles = JSON.parse(sql("BEGIN READ ONLY; SELECT jsonb_agg(jsonb_build_object('name',rolname,'inherit',rolinherit,'superuser',rolsuper,'bypassrls',rolbypassrls,'login',rolcanlogin,'createdb',rolcreatedb,'createrole',rolcreaterole,'replication',rolreplication)) FROM pg_roles WHERE rolname !~ '^pg_'; COMMIT;", true));
  await startDatabase();
  stage = 'clone-import';
  const existingRoles = new Set(JSON.parse(sql('select jsonb_agg(rolname) from pg_roles;')));
  const missingRoles = roles.filter(r => !existingRoles.has(r.name));
  const quoteName = s => '"' + s.replaceAll('"', '""') + '"';
  for (const role of missingRoles) {
    if (typeof role.name !== 'string' || role.name.length > 63) throw new Error('AUTH_RESTORE_ROLE_INVALID');
    const flags = [['superuser','SUPERUSER'],['inherit','INHERIT'],['bypassrls','BYPASSRLS'],['login','LOGIN'],['createdb','CREATEDB'],['createrole','CREATEROLE'],['replication','REPLICATION']]
      .map(([key,flag]) => (role[key] === true ? '' : 'NO') + flag).join(' ');
    sql(`CREATE ROLE ${quoteName(role.name)} ${flags};`);
  }
  report.source_only_roles_created_without_passwords = missingRoles.map(r => r.name);
  // Only this newly created, fingerprinted disposable DB. The image supplies
  // empty managed schemas which pg_restore's CREATE SCHEMA would collide with.
  sql('DROP SCHEMA IF EXISTS auth, storage, extensions, graphql, graphql_public, pgbouncer, pgmq, private, realtime, vault CASCADE;');
  sql('DROP PUBLICATION IF EXISTS supabase_realtime;');
  // PGMQ queue relations are extension members: pg_dump includes their ACLs but
  // not CREATE TABLE or payloads. Recreate the known empty queue after pre-data,
  // before data/post-data ACLs. Refuse above if any original queue payload exists.
  for (const section of ['pre-data', 'data', 'post-data']) {
    stage = `clone-import-${section}`; guard('db');
    checked(docker(['exec', '-i', names.db, 'pg_restore', '-U', 'supabase_admin', '-d', 'postgres', '--exit-on-error', '--no-privileges', `--section=${section}`],
      { input: dump, encoding: null, timeout: 90_000 }), 'AUTH_RESTORE_IMPORT_FAILED');
    if (section === 'pre-data') sql("SELECT pgmq.create('analysis_jobs');");
  }
  // ACL entries for extension-owned relations are emitted even in pre-data.
  // Replay ALL ACL/default-ACL entries explicitly after queue and schema exist;
  // never leave the no-privileges intermediate state as a successful restore.
  stage = 'clone-import-acls'; guard('db');
  const toc = checked(docker(['exec', '-i', names.db, 'pg_restore', '--list'], { input: dump }), 'AUTH_RESTORE_TOC_FAILED');
  const aclEntries = toc.split('\n').filter(line => /^\d+;/.test(line) && /\bACL\b/.test(line));
  if (!aclEntries.length) throw new Error('AUTH_RESTORE_ACL_INVENTORY_EMPTY');
  const aclPath = resolve(target, 'acl-restore.list');
  writeFileSync(aclPath, aclEntries.join('\n') + '\n', { mode: 0o600 });
  checked(docker(['cp', aclPath, `${owned.get('db')}:/tmp/isg-restore-acl.list`]), 'AUTH_RESTORE_ACL_LIST_COPY_FAILED');
  guard('db'); checked(docker(['exec', '-i', names.db, 'pg_restore', '-U', 'supabase_admin', '-d', 'postgres', '--exit-on-error', '--use-list=/tmp/isg-restore-acl.list'],
    { input: dump, encoding: null, timeout: 90_000 }), 'AUTH_RESTORE_ACL_IMPORT_FAILED');
  report.acl_entries_replayed = aclEntries.length;
  report.empty_analysis_queue_regenerated = true;
  pass('original_user_counts_restored', sql('select count(*) from auth.users; select count(*) from public.profiles; select count(*) from storage.objects;') === '208\n208\n588');
  stage = 'service-ledgers';
  pass('service_ledgers_empty_before_supplement', sql('select count(*) from auth.schema_migrations; select count(*) from storage.migrations;') === '0\n0');
  sql(ledger.toString('utf8'));
  pass('service_ledgers_restored', sql('select count(*) from auth.schema_migrations; select count(*) from storage.migrations;') === '77\n68');
  } else {
    stage = 'synthetic-bootstrap';
    const outputRoot = resolve(ROOT,'output/isg/runs');
    mkdirSync(outputRoot,{recursive:true,mode:0o700});
    target = mkdtempSync(resolve(outputRoot,'synthetic-auth-')); chmodSync(target,0o700);
    await startDatabase();
    // The pinned image includes an EMPTY Auth bootstrap schema. GoTrue applies
    // its remaining managed migrations; never import customer snapshots.
    pass('synthetic_database_has_no_auth_users',sql('select count(*) from auth.users;') === '0');
    pass('synthetic_database_has_no_application_profile_table',sql("select to_regclass('public.profiles') is null;") === 't');
  }
  const secret = randomBytes(48).toString('hex'), dbPassword = randomBytes(32).toString('hex');
  sql(`ALTER ROLE supabase_auth_admin PASSWORD '${dbPassword}';`);
  stage = 'auth-boot';
  start('client', {}, ['-e', synthetic ? readFileSync(resolve(ROOT,'scripts/isg/auth_mail_sink.cjs'),'utf8') : 'setInterval(()=>{},1000)']);
  start('auth', { GOTRUE_API_HOST: '127.0.0.1', GOTRUE_API_PORT: '9999',
    API_EXTERNAL_URL: 'http://127.0.0.1:9999/auth/v1', GOTRUE_SITE_URL: 'http://127.0.0.1:9999',
    GOTRUE_DB_DRIVER: 'postgres', GOTRUE_DB_DATABASE_URL: `postgres://supabase_auth_admin:${dbPassword}@127.0.0.1:5432/postgres?sslmode=disable`,
    GOTRUE_DB_MAX_POOL_SIZE: '4', GOTRUE_JWT_SECRET: secret, GOTRUE_JWT_EXP: '3600', GOTRUE_JWT_AUD: 'authenticated',
    GOTRUE_JWT_ISSUER: 'http://127.0.0.1:9999/auth/v1',
    GOTRUE_JWT_DEFAULT_GROUP_NAME: 'authenticated', GOTRUE_JWT_ADMIN_ROLES: 'service_role',
    GOTRUE_EXTERNAL_EMAIL_ENABLED: 'true', GOTRUE_EXTERNAL_PHONE_ENABLED: 'false', GOTRUE_MAILER_AUTOCONFIRM: 'true',
    GOTRUE_DISABLE_SIGNUP: 'true', GOTRUE_SECURITY_REFRESH_TOKEN_ROTATION_ENABLED: 'true',
    ...(synthetic ? { GOTRUE_PASSWORD_MIN_LENGTH:'8', GOTRUE_PASSWORD_REQUIRED_CHARACTERS:'abcdefghijklmnopqrstuvwxyz:ABCDEFGHIJKLMNOPQRSTUVWXYZ:0123456789',
      GOTRUE_MAILER_AUTOCONFIRM:'false', GOTRUE_DISABLE_SIGNUP:'false', GOTRUE_SMTP_HOST:'127.0.0.1', GOTRUE_SMTP_PORT:'2525',
      GOTRUE_SMTP_ADMIN_EMAIL:'test@example.invalid', GOTRUE_SMTP_SENDER_NAME:'Isolated QA', GOTRUE_SMTP_MAX_FREQUENCY:'1s',
      GOTRUE_RATE_LIMIT_EMAIL_SENT:'100', GOTRUE_MAILER_TEMPLATES_CONFIRMATION:'http://127.0.0.1:10000/template',
      GOTRUE_MAILER_TEMPLATES_RECOVERY:'http://127.0.0.1:10000/template' } : {}),
    GOTRUE_TRACING_ENABLED: 'false', GOTRUE_METRICS_ENABLED: 'false', LOG_LEVEL: 'error' });
  await waitReady(() => { try { return request('/health').status === 200; } catch { return false; } });
  pass('auth_health', true);
  report.auth_health = request('/health').body;
  stage = 'auth-contract';
  const admin = sign(secret, 'service_role');
  pass('admin_endpoint_rejects_no_token', [401,403].includes(request('/admin/users').status));
  pass('admin_endpoint_rejects_expired_service_token', [401,403].includes(request('/admin/users', { token: sign(secret, 'service_role', -30) }).status));
  const email = `isg-restore-${run}@example.invalid`, password = 'Aa1' + randomBytes(24).toString('base64url');
  const created = request('/admin/users', { method: 'POST', token: admin, body: { email, password, email_confirm: true } });
  pass('synthetic_user_created_by_local_admin', [200,201].includes(created.status) && /^[a-f0-9-]{36}$/.test(created.body.id ?? ''));
  const id = created.body.id;
  if (!mode.synthetic) pass('existing_profile_bootstrap_trigger', sql(`select count(*) from public.profiles where id='${id}';`) === '1');
  else pass('synthetic_auth_contains_only_one_fixture_user',sql('select count(*) from auth.users;') === '1');
  pass('wrong_password_rejected', request('/token?grant_type=password', { method: 'POST', body: { email, password: 'incorrect-test-only' } }).status === 400);
  const login = request('/token?grant_type=password', { method: 'POST', body: { email, password } });
  pass('password_login_same_uuid', login.status === 200 && login.body.user?.id === id && typeof login.body.access_token === 'string');
  const session = login.body;
  pass('authenticated_user_read', request('/user', { token: session.access_token }).body.id === id);
  pass('user_token_cannot_admin_list', [401,403].includes(request('/admin/users', { token: session.access_token }).status));
  const refresh = request('/token?grant_type=refresh_token', { method: 'POST', body: { refresh_token: session.refresh_token } });
  pass('refresh_keeps_same_uuid', refresh.status === 200 && refresh.body.user?.id === id && !!refresh.body.access_token);
  let sessionProbe;
  let mutationProbe;
  let personnelProbe;
  let personnelMigrationProbe;
  let personnelHTTPProbe;
  if (mode.sessionGuard) {
    stage = 'session-guard';
    sessionProbe = await beginSessionProbe({ sql, concurrentSql, token: refresh.body.access_token, secret, pass });
  }
  if (mode.synthetic) {
    stage = 'auth-mutation-composition';
    mutationProbe = await beginAuthMutationProbe({ synthetic:true, sql, concurrentSql, token:refresh.body.access_token, secret, pass });
    stage = 'auth-personnel-composition';
    personnelProbe = beginAuthPersonnelProbe({ synthetic:true, sql, token:refresh.body.access_token, secret, pass });
    stage = 'personnel-production-migration';
    personnelMigrationProbe = await beginPersonnelMigrationProbe({ synthetic:true, sql, concurrentSql, token:refresh.body.access_token, secret, pass });
    stage = 'personnel-http';
    personnelHTTPProbe = await beginPersonnelHTTPProbe({synthetic:true,token:refresh.body.access_token,secret,companyID:personnelMigrationProbe.companyID,sql,start,guard,docker,names,waitReady,pass});
    stage = 'personnel-advisors';
    report.personnel_advisors=await probePersonnelAdvisors({synthetic:true,sql,guard,names,pass});
  }
  pass('logout_succeeds', request('/logout', { method: 'POST', token: refresh.body.access_token }).status === 204);
  pass('logged_out_refresh_rejected', request('/token?grant_type=refresh_token', { method: 'POST', body: { refresh_token: refresh.body.refresh_token } }).status === 400);
  if (sessionProbe) report.session_guard = sessionProbe.afterLogout();
  if (mutationProbe) report.auth_mutation = mutationProbe.afterLogout();
  if (personnelProbe) report.auth_personnel = personnelProbe.afterLogout();
  if (personnelMigrationProbe) report.personnel_migration = personnelMigrationProbe.afterLogout();
  if (personnelHTTPProbe) report.personnel_http = personnelHTTPProbe.afterLogout();
  if (mode.synthetic) {
    stage = 'password-auth-boundaries';
    report.password_auth = probePasswordAuth({synthetic:true, request, admin, pass});
    stage = 'signup-recovery-mail';
    report.signup_recovery = probeSignupRecovery({synthetic:true,request,mailbox,admin,pass});
  }
  if (withStorage) {
    stage = 'storage-service';
    report.storage = await probeStorageRestore({ sql, start, guard, docker, checked, names, secret, sign, waitReady, pass, foreignSubject: id });
    report.storage_api_tested = true;
  }
  report.service_ledger_counts_after_boot = sql(mode.synthetic ? 'select count(*) from auth.schema_migrations;' : 'select count(*) from auth.schema_migrations; select count(*) from storage.migrations;');
  if (!mode.synthetic) {
  report.source_after = sql("BEGIN READ ONLY; SELECT jsonb_build_object('users',(select count(*) from auth.users),'identities',(select count(*) from auth.identities),'profiles',(select count(*) from public.profiles),'objects',(select count(*) from storage.objects),'auth_migrations',(select count(*) from auth.schema_migrations),'storage_migrations',(select count(*) from storage.migrations)); COMMIT;", true);
  pass('source_counts_unchanged', report.source_before === report.source_after);
  } else pass('synthetic_no_backup_or_storage_lane_used',!withStorage && report.original_source_accessed === false);
  report.source_sha256 = Object.fromEntries(['scripts/isg/run_auth_restore.mjs','scripts/isg/password_auth_probe.mjs','scripts/isg/signup_recovery_probe.mjs','scripts/isg/auth_mail_sink.cjs','scripts/isg/auth_session_probe.mjs','scripts/isg/auth_mutation_probe.mjs','scripts/isg/sql/auth_mutation_fixture.sql','scripts/isg/sql/transaction_fixture.sql','scripts/isg/restore_mode.mjs','scripts/isg/sql/auth_session_fixture.sql','scripts/isg/auth_restore_guard.mjs']
    .concat(personnelAuthFiles, ['scripts/isg/auth_personnel_probe.mjs','supabase/functions/_shared/personnel/directory-request.ts','supabase/functions/_shared/personnel/employee-create.ts','supabase/functions/_shared/isg/mutation-context.ts'])
    .concat(personnelMigrationFiles)
    .map(path=>[path,digest(readFileSync(resolve(ROOT,path)))]));
  report.ok = true;
} catch (error) {
  report.ok = false; report.failed_stage = stage;
  report.error_code = /^AUTH_RESTORE_/.test(error.message) ? error.message : 'AUTH_RESTORE_FAILED';
  if (target && owned.has('auth')) {
    const logs = docker(['logs', '--tail', '80', owned.get('auth')]);
    writeFileSync(resolve(target, 'auth-diagnostic.txt'), (logs.stdout ?? '') + (logs.stderr ?? ''), { mode: 0o600 });
  }
  if (target && owned.has('storage')) {
    const logs = docker(['logs', '--tail', '80', owned.get('storage')]);
    writeFileSync(resolve(target, 'storage-diagnostic.txt'), (logs.stdout ?? '') + (logs.stderr ?? ''), { mode: 0o600 });
  }
} finally {
  await cleanup(); saveReport();
}
console.log(JSON.stringify({ ...report, evidence_directory: target ? relative(ROOT, target) : null }, null, 2));
process.exitCode = report.ok ? 0 : 1;
