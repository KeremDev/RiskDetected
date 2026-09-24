// Runs the home feed migration against synthetic stand-in tables in a throwaway
// PostgreSQL cluster. Uses local PostgreSQL binaries when present (initdb,
// pg_ctl, psql), otherwise a Docker postgres:17-alpine container.
import {spawnSync} from 'node:child_process';
import {mkdtempSync, readFileSync, readdirSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const read = p => readFileSync(p, 'utf8');
const has = bin => spawnSync('sh', ['-c', `command -v ${bin}`], {stdio: 'ignore'}).status === 0;
function run(command, args, input, env) {
  // PostgreSQL refuses to start under a locale it cannot resolve (macOS shells).
  const r = spawnSync(command, args, {input, encoding: 'utf8', maxBuffer: 16e6,
    env: {...process.env, LC_ALL: 'C', LANG: 'C', ...env}});
  if (r.status !== 0) throw new Error(`${command} ${args.join(' ')}\n${r.stderr || r.stdout}`);
  return r.stdout;
}

let sql, stop;
if (has('initdb') && has('pg_ctl') && has('psql')) {
  const dir = mkdtempSync(join(tmpdir(), 'nova-home-'));
  const data = join(dir, 'data');
  run('initdb', ['-D', data, '-U', 'postgres', '--auth=trust', '--no-sync', '-E', 'UTF8', '--locale=C']);
  run('pg_ctl', ['-D', data, '-l', join(dir, 'log'), '-w', '-o', `-k ${dir} -c listen_addresses='' -c fsync=off`, 'start']);
  sql = (text, extra = []) => run('psql', ['-X', '-h', dir, '-U', 'postgres', '-v', 'ON_ERROR_STOP=1', '-At', ...extra], text);
  stop = () => { spawnSync('pg_ctl', ['-D', data, '-m', 'immediate', 'stop'], {stdio: 'ignore'}); rmSync(dir, {recursive: true, force: true}); };
} else {
  const container = `nova_home_${process.pid}`;
  run('docker', ['run', '-d', '--name', container, '--network', 'none', '-e', 'POSTGRES_PASSWORD=synthetic-local-only', 'postgres:17-alpine']);
  for (let i = 0; i < 80 && spawnSync('docker', ['exec', container, 'pg_isready', '-h', '127.0.0.1', '-U', 'postgres'], {stdio: 'ignore'}).status !== 0; i++) {
    await new Promise(resolve => setTimeout(resolve, 250));
  }
  sql = (text, extra = []) => run('docker', ['exec', '-i', container, 'psql', '-X', '-U', 'postgres', '-v', 'ON_ERROR_STOP=1', '-At', ...extra], text);
  stop = () => spawnSync('docker', ['rm', '-f', container], {stdio: 'ignore'});
}

try {
  sql("SET TIME ZONE 'UTC';" + read('scripts/home/fixture.sql'));
  // Migrations run as one transaction each, in order, as they do on Supabase.
  for (const name of readdirSync('supabase/migrations').filter(n => /^\d+_isg_home_feed(_[a-z_]+)?\.sql$/.test(n)).sort()) {
    sql(read(`supabase/migrations/${name}`), ['--single-transaction']);
  }
  console.log(sql(read('scripts/home/checks.sql')).trim().split('\n').at(-1));
  // Replaying the allowlist step must not add the names twice.
  const again = read('supabase/migrations/20260924183727_isg_home_feed.sql').match(/DO \$\$\nDECLARE definition text;[\s\S]*?END \$\$;/)[0];
  sql(again);
  const count = sql("SELECT count(*) FROM regexp_matches(pg_get_functiondef('private_isg.expert_rpc(uuid,text,jsonb)'::regprocedure), 'isg_home_feed_v1', 'g');").trim();
  if (count !== '1') throw new Error(`allowlist replay added a duplicate (${count})`);
  console.log('PASS: home feed scope, windows, drafts, ranking, dismissals, rotation, feature use, grants and allowlist');
} finally {
  stop();
}
