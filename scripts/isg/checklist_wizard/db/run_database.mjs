// Runs the checklist catalogue extension migration in a throwaway PostgreSQL cluster (local initdb/pg_ctl/psql).
// The base catalogue comes from the real migrations: 20260921072445_checklist_catalog_v1's table DDL and
// generated seed, then 20260921133000's approval, then the extension, which is replayed a second time to
// show it is idempotent. read_checklists_company_v3 is exercised on stand-in tables (fixture.sql).
//   node scripts/isg/checklist_wizard/db/run_database.mjs
import {spawnSync} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const read = p => readFileSync(p, 'utf8');
function run(command, args, input) {
  // PostgreSQL refuses to start under a locale it cannot resolve (macOS shells).
  const r = spawnSync(command, args, {input, encoding: 'utf8', maxBuffer: 64e6, env: {...process.env, LC_ALL: 'C', LANG: 'C'}});
  if (r.status !== 0) throw new Error(`${command} ${args.join(' ')}\n${r.stderr || r.stdout}`);
  return r.stdout;
}

const v1 = read('supabase/migrations/20260921072445_checklist_catalog_v1.sql');
const ddl = v1.slice(v1.indexOf('CREATE OR REPLACE FUNCTION private_isg.checklist_search_fold'),
  v1.indexOf('ALTER TABLE private_isg.checklist_catalogs ENABLE ROW LEVEL SECURITY;'));
const seed = v1.slice(v1.indexOf('-- BEGIN GENERATED CHECKLIST CATALOG SEED'), v1.indexOf('-- END GENERATED CHECKLIST CATALOG SEED'));
const extension = read('supabase/migrations/20260925002500_checklist_catalog_extension_v1.sql');
if (!ddl.includes('CREATE TABLE private_isg.checklist_catalog_items') || !seed.includes('DO $seed$')) throw new Error('v1 migration layout changed');

const dir = mkdtempSync(join(tmpdir(), 'nova-checklist-'));
const data = join(dir, 'data');
run('initdb', ['-D', data, '-U', 'postgres', '--auth=trust', '--no-sync', '-E', 'UTF8', '--locale=C']);
run('pg_ctl', ['-D', data, '-l', join(dir, 'log'), '-w', '-o', `-k ${dir} -c listen_addresses='' -c fsync=off`, 'start']);
const sql = (text, extra = []) => run('psql', ['-X', '-h', dir, '-U', 'postgres', '-v', 'ON_ERROR_STOP=1', '-At', ...extra], text);
try {
  sql(read('scripts/isg/checklist_wizard/db/fixture.sql'));
  sql(ddl, ['--single-transaction']);
  sql(seed, ['--single-transaction']);
  sql(read('supabase/migrations/20260921133000_checklist_catalog_professional_approval.sql'));
  // Before the extension exists the library reads the base catalogue alone.
  sql(read('supabase/migrations/20260921114500_checklist_catalog_completion.sql')
    .match(/CREATE OR REPLACE FUNCTION private_isg\.read_checklists\([\s\S]*?\nEND \$\$;/)[0]
    .replace('FUNCTION private_isg.read_checklists(', 'FUNCTION private_isg.read_checklists_company_v3('));
  const before = sql("SELECT private_isg.read_checklists_company_v3(NULL,'library',NULL,NULL,NULL,NULL,NULL,5,0)->>'total';").trim();
  if (before !== '200') throw new Error(`base library total ${before}`);
  sql(extension);
  console.log(sql(read('scripts/isg/checklist_wizard/db/checks.sql')).trim().split('\n').at(-1));
  sql(extension);
  console.log(sql(read('scripts/isg/checklist_wizard/db/checks.sql')).trim().split('\n').at(-1));
  console.log('PASS: extension catalogue seeded once, base untouched, library and starters read base plus extension');
} finally {
  spawnSync('pg_ctl', ['-D', data, '-m', 'immediate', 'stop'], {stdio: 'ignore'});
  rmSync(dir, {recursive: true, force: true});
}
