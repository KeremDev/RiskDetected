import {createServer} from 'node:http';
import {randomBytes} from 'node:crypto';
import {writeFileSync} from 'node:fs';
import {resolve} from 'node:path';

// Explicit synthetic mode only. No arbitrary proxy target, SQL/admin endpoint,
// host-wide listener, production credentials or browser CORS support.
export async function nativeE2EBridge({synthetic, target, fixture, auth, rest, control, verify}) {
  if (synthetic !== true) throw Error('AUTH_RESTORE_NATIVE_SYNTHETIC_REQUIRED');
  const keys = Object.fromEntries(['ios','android'].map(p => [p,randomBytes(32).toString('hex')]));
  const completed = {}, dropped = {}, armed = {}, requests = {ios:0,android:0};
  let done, fail;
  const finished = new Promise((resolve,reject) => { done=resolve; fail=reject; });
  const rpc = new Set(['isg_personnel_read_v1','isg_personnel_mutate_v1','isg_directory_read_v1','isg_directory_mutate_v1','isg_context_at_v1','isg_workspace_availability_v1']);
  const server = createServer(async (req,res) => {
    const platform = Object.keys(keys).find(p => keys[p] === req.headers.apikey);
    const reply=(status,body)=>{res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(status===204?'':JSON.stringify(body));};
    if (!platform || req.headers.origin || req.headers.host !== `127.0.0.1:${server.address().port}`) return reply(403,{});
    try {
      let raw='';for await (const data of req) {raw+=data;if(Buffer.byteLength(raw)>32768)return reply(413,{});}
      const body=raw?JSON.parse(raw):undefined;
      const path=req.url, token=req.headers.authorization?.replace(/^Bearer /,'');
      if(path==='/qa/bootstrap'&&req.method==='GET')return reply(200,{...fixture,platform,synthetic:true});
      if(path==='/qa/control'&&req.method==='POST') {
        if(body?.action==='drop_next') {armed[platform]=true;return reply(200,{ok:true});}
        if(!['write_off','read_off','paid_off','reset'].includes(body?.action))return reply(400,{});
        if(body.action==='reset')armed[platform]=false;
        control(body.action);return reply(200,{ok:true});
      }
      if(path==='/qa/finish'&&req.method==='POST') {
        completed[platform]=verify(platform);
        if(!completed[platform]?.ok)return reply(409,completed[platform]);
        reply(200,completed[platform]);
        if(completed.ios&&completed.android)done({platforms:completed,dropped,requests,loopback_only:true,synthetic:true});
        return;
      }
      let result;
      if(req.method==='POST'&&['/auth/v1/token?grant_type=password','/auth/v1/token?grant_type=refresh_token','/auth/v1/logout?scope=local'].includes(path))
        result=auth(path.replace('/auth/v1',''),{method:'POST',token,body});
      else if(req.method==='GET'&&path==='/auth/v1/user')result=auth('/user',{token});
      else if(req.method==='POST'&&path.startsWith('/rest/v1/rpc/')&&rpc.has(path.slice('/rest/v1/rpc/'.length))) {
        requests[platform]++;
        result=rest(path.replace('/rest/v1',''),{method:'POST',authorization:token??null,body});
        if(armed[platform]&&path.endsWith('_mutate_v1')&&result.status===200){dropped[platform]=(dropped[platform]??0)+1;res.destroy();return;}
      } else return reply(404,{});
      reply(result.status,result.body);
    } catch {if(!res.destroyed)reply(500,{code:'SYNTHETIC_BRIDGE_FAILED'});}
  });
  server.requestTimeout=15000;server.headersTimeout=10000;
  await new Promise((r,j)=>{server.once('error',j);server.listen(0,'127.0.0.1',r);});
  const url=`http://127.0.0.1:${server.address().port}`;
  writeFileSync(resolve(target,'native-connection.json'),JSON.stringify({url,keys}),{mode:0o600});
  console.log(JSON.stringify({native_fixture_ready:true,connection_file:resolve(target,'native-connection.json')}));
  const timeout=setTimeout(()=>fail(Error('AUTH_RESTORE_NATIVE_TIMEOUT')),60*60*1000);
  try {return await finished;} finally {clearTimeout(timeout);server.closeAllConnections();await new Promise(r=>server.close(r));}
}
