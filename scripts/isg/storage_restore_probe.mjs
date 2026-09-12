import { createHash, randomBytes } from 'node:crypto';
import { readFileSync, lstatSync, realpathSync } from 'node:fs';
import { resolve, sep } from 'node:path';
import { ROOT } from './lib.mjs';

// Not a standalone restore command. Called only after the parent has created
// and fingerprinted its disposable DB and restored all data, ACLs and ledgers.
const backup = resolve(ROOT, 'backups/riskdetected-change-point-20260912-182850');
const hash = value => createHash('sha256').update(value).digest('hex');
const layout = { reports: ['reports','reports'], photos: ['photos','photos'], logos: ['logos','logos'], avatars: ['avatars','avatars'], 'legal-documents': ['legal-documents'] };
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;

export function validateStorageObject(object) {
  if (!object || !Object.hasOwn(layout, object.bucket) || typeof object.name !== 'string' ||
      object.name.split('/').some(p => !p || p === '.' || p === '..') || /[\\\x00-\x1f]/.test(object.name) ||
      (object.version !== null && (typeof object.version !== 'string' || !uuid.test(object.version))) ||
      !Number.isSafeInteger(object.bytes) || object.bytes < 0 || object.bytes > 50 * 1024 * 1024 ||
      typeof object.mime !== 'string' || !object.mime || /[\r\n]/.test(object.mime) ||
      typeof object.cache !== 'string' || /[\r\n]/.test(object.cache)) throw new Error('AUTH_RESTORE_STORAGE_OBJECT_INVALID');
}

export function signedStoragePath(value) {
  if (typeof value !== 'string' || !value.startsWith('/object/sign/') || value.includes('#') || value.includes('\\')) {
    throw new Error('AUTH_RESTORE_STORAGE_SIGNED_PATH_INVALID');
  }
  const u = new URL(value, 'http://127.0.0.1:5000');
  if (u.origin !== 'http://127.0.0.1:5000' || !u.pathname.startsWith('/object/sign/') ||
      [...u.searchParams.keys()].some(k => k !== 'token') || u.searchParams.getAll('token').length !== 1 ||
      !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(u.searchParams.get('token') ?? '')) {
    throw new Error('AUTH_RESTORE_STORAGE_SIGNED_PATH_INVALID');
  }
  return u.pathname + u.search;
}

// Byte payloads and paths never leave the local isolated container via logs.
// The installed image's FileBackend writes both the versioned key and xattrs;
// no storage.objects INSERT/UPDATE or service upload API is used for old files.
const hydrateProgram = `let raw='';process.stdin.on('data',c=>raw+=c);process.stdin.on('end',async()=>{try{
const {FileBackend}=require('./dist/storage/backend/file');const {TenantLocation}=require('./dist/storage/locator');
const {Readable}=require('node:stream');const crypto=require('node:crypto');const backend=new FileBackend();
const location=new TenantLocation('isg-restore-root');let count=0,bytes=0;
for(const o of JSON.parse(raw)){const b=Buffer.from(o.data,'base64');if(crypto.createHash('sha256').update(b).digest('hex')!==o.sha)throw Error('hash');
await backend.uploadObject(location.getRootLocation(),location.getKeyLocation({tenantId:'isg-restore',bucketId:o.bucket,objectName:o.name}),o.version??undefined,Readable.from(b),o.mime,o.cache);
count++;bytes+=b.length;}process.stdout.write(JSON.stringify({count,bytes}));process.exit(0);
}catch{process.stderr.write('STORAGE_HYDRATE_FAILED');process.exit(1);}});`;

const httpProgram = `const http=require('node:http'),crypto=require('node:crypto');let raw='';process.stdin.on('data',c=>raw+=c);process.stdin.on('end',async()=>{try{
const queries=JSON.parse(raw),results=[];for(const q of queries){
if(!/^\\/(health|object)([/?]|$)/.test(q.path)||q.path.includes('\\\\'))throw Error('path');
const r=await new Promise((resolve,reject)=>{const req=http.request({host:'127.0.0.1',port:5000,path:q.path,method:q.method??'GET',headers:{'Content-Type':'application/json',...(q.token?{Authorization:'Bearer '+q.token}:{}),...(q.headers??{})}},res=>{
const hash=crypto.createHash('sha256');let bytes=0,raw='';res.on('data',c=>{hash.update(c);bytes+=c.length;if(q.json&&raw.length<65536)raw+=c;});res.on('end',()=>{let body;try{if(q.json)body=JSON.parse(raw)}catch{}resolve({status:res.statusCode,bytes,sha:hash.digest('hex'),headers:res.headers,body});});res.on('error',reject);});req.setTimeout(10000,()=>req.destroy(Error('timeout')));req.on('error',reject);if(q.body)req.write(JSON.stringify(q.body));req.end();});results.push(r);}process.stdout.write(JSON.stringify(results));
}catch{process.stderr.write('STORAGE_HTTP_FAILED');process.exit(1);}});`;

export async function probeStorageRestore({ sql, start, guard, docker, checked, names, secret, sign, waitReady, pass, foreignSubject }) {
  const report = { all_bytes_tested: false, private_bucket_rls: [], public_bucket_tested: false,
    original_etag_and_mtime_preserved: false, live_credentials_used: false, original_user_login_tested: false };
  if (!uuid.test(foreignSubject ?? '') || sql(`select count(*) from auth.users where id='${foreignSubject}';`) !== '1') {
    throw new Error('AUTH_RESTORE_STORAGE_FOREIGN_FIXTURE_MISSING');
  }
  const manifestBytes = readFileSync(resolve(backup, 'storage-file-sha256sums.txt'));
  if (hash(manifestBytes) !== 'ee23f3c9ba4f21d30028a4659737cfce0cb6f4d503616a906edf91d2071e23cc') throw new Error('AUTH_RESTORE_STORAGE_MANIFEST_DRIFT');
  const manifest = new Map(manifestBytes.toString('utf8').trim().split('\n').map(line => {
    const m = line.match(/^([a-f0-9]{64})\s+(.+)$/);
    if (!m) throw new Error('AUTH_RESTORE_STORAGE_MANIFEST_INVALID');
    return [resolve(ROOT, m[2]), m[1]];
  }));
  const before = sql("select md5(string_agg(row_to_json(o)::text, '' order by id)) from storage.objects o;");
  const objects = JSON.parse(sql("select jsonb_agg(jsonb_build_object('bucket',o.bucket_id,'name',o.name,'version',o.version,'bytes',(o.metadata->>'size')::bigint,'mime',o.metadata->>'mimetype','cache',o.metadata->>'cacheControl','public',b.public) order by o.id) from storage.objects o join storage.buckets b on b.id=o.bucket_id;"));
  if (objects.length !== 588 || manifest.size !== 588) throw new Error('AUTH_RESTORE_STORAGE_COUNT_DRIFT');
  const fileRoot = realpathSync(resolve(backup, 'storage'));
  for (const object of objects) {
    validateStorageObject(object);
    object.file = resolve(fileRoot, ...layout[object.bucket], object.name);
    if (!object.file.startsWith(fileRoot + sep) || !realpathSync(object.file).startsWith(fileRoot + sep) ||
        !lstatSync(object.file).isFile() || lstatSync(object.file).isSymbolicLink() || !manifest.has(object.file)) throw new Error('AUTH_RESTORE_STORAGE_FILE_UNSAFE');
    object.sha = manifest.get(object.file);
  }
  const password = randomBytes(32).toString('hex');
  sql(`ALTER ROLE supabase_storage_admin PASSWORD '${password}';`);
  const admin = sign(secret, 'service_role');
  start('storage', { HOST: '127.0.0.1', PORT: '5000', ADMIN_PORT: '5001',
    DATABASE_URL: `postgres://supabase_storage_admin:${password}@127.0.0.1:5432/postgres`, DATABASE_MAX_CONNECTIONS: '4',
    AUTH_JWT_SECRET: secret, ANON_KEY: sign(secret, 'anon'), SERVICE_KEY: admin,
    STORAGE_BACKEND: 'file', FILE_STORAGE_BACKEND_PATH: '/var/lib/storage', GLOBAL_S3_BUCKET: 'isg-restore-root',
    TENANT_ID: 'isg-restore', REGION: 'local', STORAGE_PUBLIC_URL: 'http://127.0.0.1:5000',
    TUS_USE_FILE_VERSION_SEPARATOR: 'false', FILE_SIZE_LIMIT: '52428800',
    PG_QUEUE_ENABLE: 'false', PG_QUEUE_WORKERS_ENABLE: 'false', ENABLE_IMAGE_TRANSFORMATION: 'false', LOG_LEVEL: 'error' });
  function requests(queries, timeout = 45_000) {
    guard('storage'); guard('client');
    return JSON.parse(checked(docker(['exec','-i',names.client,'node','-e',httpProgram], { input: JSON.stringify(queries), timeout }), 'AUTH_RESTORE_STORAGE_HTTP_FAILED'));
  }
  await waitReady(() => { try { const [r] = requests([{ path: '/health', token: admin, json: true }]); return r.status === 200 && r.body?.healthy === true; } catch { return false; } });
  pass('storage_health', true);
  let bytes = 0;
  // Bound each in-memory/cross-container batch; never write a plaintext host tar.
  for (let i = 0; i < objects.length;) {
    const batch = []; let batchBytes = 0;
    do {
      const o = objects[i++], data = readFileSync(o.file);
      if (data.length !== o.bytes || hash(data) !== o.sha) throw new Error('AUTH_RESTORE_STORAGE_HASH_MISMATCH');
      batch.push({ bucket:o.bucket,name:o.name,version:o.version,mime:o.mime,cache:o.cache,sha:o.sha,data:data.toString('base64') });
      batchBytes += data.length;
    } while (i < objects.length && batch.length < 16 && batchBytes + objects[i].bytes < 24 * 1024 * 1024);
    guard('storage');
    const result = JSON.parse(checked(docker(['exec','-i',names.storage,'node','-e',hydrateProgram], { input: JSON.stringify(batch) }), 'AUTH_RESTORE_STORAGE_HYDRATE_FAILED'));
    if (result.count !== batch.length || result.bytes !== batchBytes) throw new Error('AUTH_RESTORE_STORAGE_HYDRATE_COUNT');
    bytes += batchBytes;
  }
  pass('storage_588_blobs_hydrated_from_verified_backup', bytes === 512280146);
  const path = o => encodeURIComponent(o.bucket) + '/' + o.name.split('/').map(encodeURIComponent).join('/');
  let downloaded = 0;
  for (let i = 0; i < objects.length; i += 32) {
    const batch = objects.slice(i, i+32);
    const results = requests(batch.map(o => ({ path: '/object/authenticated/' + path(o), token: admin })), 60_000);
    if (results.length !== batch.length) throw new Error('AUTH_RESTORE_STORAGE_DOWNLOAD_COUNT');
    for (let j = 0; j < batch.length; j++) {
      const o = batch[j], r = results[j];
      if (r.status !== 200 || r.bytes !== o.bytes || r.sha !== o.sha || r.headers['content-type']?.split(';')[0] !== o.mime.split(';')[0] || r.headers['cache-control'] !== o.cache) {
        throw new Error(`AUTH_RESTORE_STORAGE_DOWNLOAD_MISMATCH_${i+j}_${r.status}`);
      }
      downloaded++;
    }
  }
  pass('storage_588_api_download_hash_size_mime_cache_match', downloaded === 588);
  report.all_bytes_tested = true; report.objects = downloaded; report.bytes = bytes;
  // Match existing folder-based ownership policy, not user-editable metadata.
  // These JWTs are signed with a fresh local-only secret; this is NOT login as a
  // real account and does not prove portability of the live session/signatures.
  for (const bucket of ['photos','reports','logos','avatars']) {
    const o = objects.find(o => o.bucket === bucket && !o.public && uuid.test(o.name.split('/')[0]));
    if (!o) throw new Error('AUTH_RESTORE_STORAGE_OWNER_FIXTURE_MISSING');
    const owner = o.name.split('/')[0].toLowerCase();
    if (sql(`select count(*) from auth.users where id='${owner}';`) !== '1') throw new Error('AUTH_RESTORE_STORAGE_OWNER_NOT_RESTORED');
    const ownerToken = sign(secret,'authenticated',3600,{ sub: owner, aud: 'authenticated' });
    if (owner === foreignSubject) throw new Error('AUTH_RESTORE_STORAGE_FIXTURE_COLLISION');
    const foreignToken = sign(secret,'authenticated',3600,{ sub: foreignSubject, aud: 'authenticated' });
    const p = '/object/authenticated/' + path(o), s = '/object/sign/' + path(o);
    const [own,foreign,anon,signed,foreignSign,anonSign] = requests([
      {path:p,token:ownerToken},{path:p,token:foreignToken},{path:p},
      {path:s,method:'POST',token:ownerToken,body:{expiresIn:60},json:true},
      {path:s,method:'POST',token:foreignToken,body:{expiresIn:60},json:true},
      {path:s,method:'POST',body:{expiresIn:60},json:true},
    ]);
    const denied = r => [400,401,403,404].includes(r.status);
    pass(`storage_${bucket}_owner_read_foreign_anon_denied`, own.status === 200 && own.sha === o.sha && denied(foreign) && denied(anon));
    pass(`storage_${bucket}_only_owner_can_sign`, signed.status === 200 && denied(foreignSign) && denied(anonSign));
    const signedPath = signedStoragePath(signed.body?.signedURL);
    const tampered = new URL(signedPath,'http://127.0.0.1:5000');
    const token = tampered.searchParams.get('token'); const parts = token.split('.');
    parts[2] = (parts[2][0] === 'a' ? 'b' : 'a') + parts[2].slice(1); tampered.searchParams.set('token',parts.join('.'));
    const [valid,invalid] = requests([{path:signedPath},{path:tampered.pathname+tampered.search}]);
    pass(`storage_${bucket}_signed_download_hash_and_tamper_rejection`, valid.status === 200 && valid.sha === o.sha && denied(invalid));
    const wrongPath = new URL(signedPath,'http://127.0.0.1:5000'); wrongPath.pathname += '.different-object';
    const [wrongObject,missingSignature,shortLived] = requests([
      {path:wrongPath.pathname+wrongPath.search},{path:s},
      {path:s,method:'POST',token:ownerToken,body:{expiresIn:1},json:true},
    ]);
    pass(`storage_${bucket}_signature_bound_to_object_and_required`, denied(wrongObject) && denied(missingSignature));
    if (shortLived.status !== 200) throw new Error('AUTH_RESTORE_STORAGE_SHORT_SIGN_FAILED');
    const shortPath = signedStoragePath(shortLived.body?.signedURL);
    // Exercise real service expiry, not a forged or locally fabricated token.
    await new Promise(r => setTimeout(r, 2100));
    const [expired] = requests([{path:shortPath}]);
    pass(`storage_${bucket}_expired_signature_rejected`, denied(expired));
    report.private_bucket_rls.push({ bucket, checks: 'PASS', fixture_count: 1 });
  }
  const publicObjects = objects.filter(o => o.public);
  const publicResults = requests(publicObjects.map(o => ({path:'/object/public/'+path(o)})));
  pass('storage_5_public_legal_documents_without_token', publicObjects.length === 5 && publicResults.every((r,i) => r.status === 200 && r.sha === publicObjects[i].sha));
  report.public_bucket_tested = true;
  pass('storage_object_rows_unchanged_after_hydration_and_download', sql("select md5(string_agg(row_to_json(o)::text, '' order by id)) from storage.objects o;") === before);
  return report;
}
