#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve, relative } from 'node:path';
import { ROOT } from './lib.mjs';
import { CONTRACT_TEST_PACKAGE, validateContractEmulator, validateContractApkManifest, parseContractInstrumentation } from './android_contract_guard.mjs';

const apk = resolve(ROOT,'android/isg-contract-tests/build/outputs/apk/androidTest/debug/isg-contract-tests-debug-androidTest.apk');
const files = ['android/isg-contract-tests/build.gradle.kts','android/isg-contract-tests/src/main/AndroidManifest.xml',
  'android/isg-contract-tests/src/androidTest/AndroidManifest.xml',
  'android/isg-contract-tests/src/androidTest/kotlin/com/riskdetectedan/isg/contracttests/MutationContextInstrumentedTest.kt',
  'android/isg-contract-tests/src/androidTest/kotlin/com/riskdetectedan/isg/contracttests/HarnessIsolationTest.kt',
  'android/core/data/src/main/kotlin/com/riskdetectedan/core/data/isg/IsgMutationContext.kt',
  'contracts/isg/v1/fixtures/mutation-context.json','scripts/isg/run_android_contract.mjs','scripts/isg/android_contract_guard.mjs'];
const sha = b=>createHash('sha256').update(b).digest('hex');
const sources = ()=>Object.fromEntries(files.map(p=>[p,sha(readFileSync(resolve(ROOT,p)))]));
let serial, identity, folder, installed=false;
const report = {schema_version:1,started_at:new Date().toISOString(),mode:'isolated_android_instrumentation',production_app_installed:false,
  live_services_tested:false,ui_flow_tested:false,cleanup:'NOT_NEEDED'};
const run = (cmd,args,options={})=>spawnSync(cmd,args,{cwd:ROOT,encoding:'utf8',timeout:15000,maxBuffer:16*1024*1024,...options});
function ok(r,code) { if(r.status!==0) throw new Error(code); return r.stdout.trim(); }
function adb(args,options={}) { return run('adb',['-s',serial,...args],options); }
function guard() {
  const avd = ok(adb(['emu','avd','name']),'ANDROID_CONTRACT_DEVICE_MISSING').split(/\r?\n/)[0];
  const sdk = ok(adb(['shell','getprop','ro.build.version.sdk']),'ANDROID_CONTRACT_DEVICE_MISSING');
  const qemu = ok(adb(['shell','getprop','ro.kernel.qemu']),'ANDROID_CONTRACT_DEVICE_MISSING');
  validateContractEmulator(serial,avd,sdk,qemu);
  if(identity && (identity.avd!==avd || identity.sdk!==sdk)) throw new Error('ANDROID_CONTRACT_DEVICE_CHANGED');
  if(ok(adb(['shell','getprop','sys.boot_completed']),'ANDROID_CONTRACT_NOT_BOOTED')!=='1') throw new Error('ANDROID_CONTRACT_NOT_BOOTED');
  return {avd,sdk};
}
function installedHash() {
  guard();
  const path=ok(adb(['shell','pm','path',CONTRACT_TEST_PACKAGE]),'ANDROID_CONTRACT_PACKAGE_MISSING');
  if(!/^package:\/data\/app\/[A-Za-z0-9_+=.~/-]+\/base\.apk$/.test(path)) throw new Error('ANDROID_CONTRACT_PACKAGE_PATH_REJECTED');
  const result=adb(['exec-out','cat',path.slice('package:'.length)],{encoding:null});
  if(result.status!==0)throw new Error('ANDROID_CONTRACT_INSTALLED_HASH_FAILED');
  return sha(result.stdout);
}
try {
  if(process.argv.length!==4 || process.argv[2]!=='--serial' || !/^emulator-[0-9]{4,5}$/.test(process.argv[3])) throw new Error('ANDROID_CONTRACT_EXPLICIT_SERIAL_REQUIRED');
  serial=process.argv[3];identity=guard();report.device={serial,...identity};
  // Do not overwrite even a pre-existing harness installation; the caller must
  // first establish ownership and remove its own old disposable test package.
  if(ok(adb(['shell','pm','list','packages',CONTRACT_TEST_PACKAGE]),'ANDROID_CONTRACT_PACKAGE_CHECK_FAILED')) throw new Error('ANDROID_CONTRACT_EXISTING_PACKAGE_REFUSED');
  const output=resolve(ROOT,'output/isg/runs');mkdirSync(output,{recursive:true,mode:0o700});
  folder=mkdtempSync(resolve(output,'android-contract-'));chmodSync(folder,0o700);
  report.source_sha256=sources();
  const build=run('./gradlew',[':isg-contract-tests:assembleDebugAndroidTest','--offline','--console=plain'],{cwd:resolve(ROOT,'android'),timeout:120000});
  writeFileSync(resolve(folder,'build.log'),(build.stdout??'')+(build.stderr??''),{mode:0o600});
  ok(build,'ANDROID_CONTRACT_BUILD_FAILED');
  report.manifest_permissions=validateContractApkManifest(ok(run('apkanalyzer',['manifest','print',apk]),'ANDROID_CONTRACT_MANIFEST_FAILED'));
  report.apk_sha256=sha(readFileSync(apk));
  const fixture=readFileSync(resolve(ROOT,'contracts/isg/v1/fixtures/mutation-context.json'));
  const asset=run('unzip',['-p',apk,'assets/mutation-context.json'],{encoding:null});
  if(asset.status!==0 || sha(asset.stdout)!==sha(fixture))throw new Error('ANDROID_CONTRACT_APK_FIXTURE_DRIFT');
  const fixtureIds=JSON.parse(fixture).cases.map(c=>c.id);
  guard();ok(adb(['install',apk],{timeout:60000}),'ANDROID_CONTRACT_INSTALL_FAILED');installed=true;
  if(installedHash()!==report.apk_sha256)throw new Error('ANDROID_CONTRACT_INSTALLED_APK_DRIFT');
  guard();
  const tests=adb(['shell','am','instrument','-w','-r',`${CONTRACT_TEST_PACKAGE}/androidx.test.runner.AndroidJUnitRunner`],{timeout:60000});
  writeFileSync(resolve(folder,'instrumentation.txt'),(tests.stdout??'')+(tests.stderr??''),{mode:0o600});
  report.tests=parseContractInstrumentation(ok(tests,'ANDROID_CONTRACT_INSTRUMENTATION_FAILED'),fixtureIds);
  if(JSON.stringify(report.source_sha256)!==JSON.stringify(sources()) || sha(readFileSync(apk))!==report.apk_sha256)throw new Error('ANDROID_CONTRACT_SOURCE_CHANGED_DURING_RUN');
  report.ok=true;
} catch(error) {
  report.ok=false;report.error_code=/^ANDROID_CONTRACT_/.test(error.message)?error.message:'ANDROID_CONTRACT_FAILED';
} finally {
  if(installed) {
    try {
      if(installedHash()!==report.apk_sha256)throw new Error('changed');
      ok(adb(['uninstall',CONTRACT_TEST_PACKAGE]),'ANDROID_CONTRACT_UNINSTALL_FAILED');
      report.cleanup='PASS';
    } catch {report.cleanup='REQUIRES_REVIEW';report.ok=false;}
  }
  report.finished_at=new Date().toISOString();
  if(folder)writeFileSync(resolve(folder,'REPORT.json'),JSON.stringify(report,null,2)+'\n',{mode:0o600});
}
console.log(JSON.stringify({...report,evidence_directory:folder?relative(ROOT,folder):null},null,2));
process.exitCode=report.ok?0:1;
