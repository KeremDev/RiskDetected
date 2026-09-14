import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {setTimeout as delay} from 'node:timers/promises';
const root = new URL('../../', import.meta.url);
const container = `nova_katip_check_${process.pid}`;
function run(args, input) {
  const result = spawnSync('docker', args, {input, encoding:'utf8', maxBuffer:16*1024*1024});
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout + result.stderr;
}
const read = path => readFileSync(new URL(path, root), 'utf8');
let created = false;
try {
  run(['run','-d','--name',container,'--network','none','--label','nova.katip.synthetic=true',
    '-e','POSTGRES_PASSWORD=synthetic-local-only','postgres:17-alpine']);
  created = true;
  let ready = false;
  for (let i=0; i<40; i++) {
    if (spawnSync('docker',['exec',container,'pg_isready','-h','127.0.0.1','-U','postgres'],{stdio:'ignore'}).status===0) { ready=true; break; }
    await delay(250);
  }
  if (!ready) throw new Error('Disposable PostgreSQL did not become ready');
  const files = ['scripts/isg/module_slice_fixture.sql',
    'supabase/migrations/20260913230000_isg_module_core.sql',
    'scripts/isg/module_second_prelude.sql',
    'supabase/migrations/20260914010000_isg_module_core_second.sql',
    'supabase/migrations/20260915210000_isg_katip_contracts.sql',
    'scripts/isg/katip_contracts_check.sql',
    'scripts/katip/documents_fixture.sql',
    'supabase/migrations/20260915220000_isg_katip_documents.sql',
    'scripts/katip/documents_check.sql'];
  const output = run(['exec','-i',container,'psql','-U','postgres','-v','ON_ERROR_STOP=1','-X'],
    'CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;\n' + files.map(path => read(path) + (path.endsWith('module_second_prelude.sql') ? '\nCREATE TABLE private_isg.nonconformities(nonconformity_id uuid PRIMARY KEY);\n' : '')).join('\n'));
  console.log(output.split('\n').filter(line=>/NOTICE:.*ok|PASS/.test(line)).join('\n'));
  console.log('PASS: isolated KATIP database checks');
} finally {
  if (created) run(['rm','-f',container]);
}
