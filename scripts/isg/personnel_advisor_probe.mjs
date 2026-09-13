import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {mkdtempSync,chmodSync,rmdirSync} from 'node:fs';
import {randomBytes} from 'node:crypto';

/** CLI gets only a private Unix socket into our owned network=none test container.
 * No TCP listener, published port, Docker mount, production URL or persistent secret.
 */
export async function probePersonnelAdvisors({synthetic,sql,guard,names,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_ADVISOR_SYNTHETIC_REQUIRED');
  guard('client');guard('db');
  const password=randomBytes(32).toString('hex');
  sql(`CREATE ROLE isg_local_advisor LOGIN PASSWORD '${password}'; ALTER ROLE isg_local_advisor SET default_transaction_read_only=on; GRANT pg_read_all_stats TO isg_local_advisor;`);
  const directory=mkdtempSync('/tmp/isg-advisor-');chmodSync(directory,0o700);
  const socket=directory+'/.s.PGSQL.5432',children=new Set(),connections=new Set();
  const bridge="const net=require('node:net');const s=net.connect({host:'127.0.0.1',port:5432});process.stdin.pipe(s);s.pipe(process.stdout);s.on('error',()=>process.exit(1));s.on('close',()=>process.exit(0));";
  const server=createServer(connection=>{
    try{guard('client');guard('db');}catch{connection.destroy();return;}
    connections.add(connection);
    const child=spawn('docker',['exec','-i',names.client,'node','-e',bridge],{stdio:['pipe','pipe','ignore'],timeout:45000});
    children.add(child);connection.pipe(child.stdin);child.stdout.pipe(connection);
    child.stdin.on('error',()=>connection.destroy());child.on('error',()=>connection.destroy());
    child.on('close',()=>{children.delete(child);connection.destroy();});
    connection.on('error',()=>child.kill());connection.on('close',()=>{connections.delete(connection);child.kill();});
  });
  try {
    await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(socket,resolve);});chmodSync(socket,0o600);
    const url=`postgresql://isg_local_advisor:${password}@localhost:5432/postgres?host=${encodeURIComponent(directory)}&sslmode=disable`;
    const result=await new Promise(resolve=>{
      const child=spawn('supabase',['db','advisors','--db-url',url,'--type','all','--level','info','--fail-on','none','--output','json'],{stdio:['ignore','pipe','pipe'],timeout:45000});
      let stdout='',stderr='';child.stdout.on('data',b=>{if(stdout.length<4*1024*1024)stdout+=b;else child.kill();});
      child.stderr.on('data',b=>{if(stderr.length<4096)stderr+=b;});child.on('error',()=>resolve({ok:false}));child.on('close',code=>resolve({ok:code===0,stdout,stderr}));
    });
    if(!result.ok)throw Error('AUTH_RESTORE_ADVISOR_CLI_FAILED: '+(result.stderr??'').replaceAll(password,'[redacted]').replace(/postgres(?:ql)?:\/\/\S+/g,'[local database]').slice(-1500));
    let parsed;try{parsed=JSON.parse(result.stdout);}catch{throw Error('AUTH_RESTORE_ADVISOR_OUTPUT_INVALID');}
    const findings=Array.isArray(parsed)?parsed:parsed.lints??parsed.advisors;
    if(!Array.isArray(findings))throw Error('AUTH_RESTORE_ADVISOR_OUTPUT_INVALID');
    const relevant=findings.filter(f=>JSON.stringify(f).includes('private_isg')||JSON.stringify(f).includes('isg_personnel_')||JSON.stringify(f).includes('companies_id_user_isg_unique'));
    pass('personnel_advisor_cli_completed',true);
    pass('personnel_advisor_new_schema_no_errors',!relevant.some(f=>String(f.level).toUpperCase()==='ERROR'));
    // Deliberate default-deny tables, with no client grants, are not missing policies.
    const denyTables=new Set(['rollout','workplaces','departments','employees','personnel_receipts','personnel_audit','personnel_outbox','workplace_initializations']);
    pass('personnel_advisor_no_unreviewed_findings',relevant.every(f=>f.name==='rls_enabled_no_policy'&&f.level==='INFO'&&f.metadata?.schema==='private_isg'&&denyTables.has(f.metadata?.name)));
    return {cli:true,read_only_role:true,private_unix_socket:true,full_schema_restore:false,
      total_findings:findings.length,relevant_findings:relevant};
  } finally {
    for(const connection of connections)connection.destroy();
    for(const child of children)child.kill();
    await new Promise(resolve=>server.close(resolve));
    rmdirSync(directory);
  }
}
