import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {ROOT} from './lib.mjs';

const [connectionFile,phase]=process.argv.slice(2);
if(!['prepare','complete','restore','catalogs','contexts','assignments','assignment_transition','foreground'].includes(phase)||!connectionFile?.startsWith('output/isg/runs/synthetic-auth-')||!connectionFile.endsWith('/native-connection.json')||connectionFile.includes('..'))throw Error('EXPLICIT_NATIVE_FIXTURE_REQUIRED');
const connection=JSON.parse(readFileSync(resolve(ROOT,connectionFile),'utf8')),url=new URL(connection.url);
if(url.hostname!=='127.0.0.1'||url.protocol!=='http:'||!/^\d+$/.test(url.port)||!/^[a-f0-9]{64}$/.test(connection.keys.android))throw Error('LOOPBACK_FIXTURE_REQUIRED');
const adb='/opt/homebrew/share/android-commandlinetools/platform-tools/adb',serial='emulator-5554',pkg='com.riskdetectedan.isg.nativecheck';
function run(args,timeout=30000){const r=spawnSync(adb,['-s',serial,...args],{encoding:'utf8',timeout,maxBuffer:4*1024*1024});if(r.status!==0)throw Error('NATIVE_ADB_FAILED');return r.stdout;}
if(!['ranchu','goldfish'].includes(run(['shell','getprop','ro.hardware']).trim()))throw Error('EMULATOR_REQUIRED');
for(const path of ['android/isg-native-check/build/outputs/apk/debug/isg-native-check-debug.apk','android/isg-native-check/build/outputs/apk/androidTest/debug/isg-native-check-debug-androidTest.apk'])run(['install','-r',resolve(ROOT,path)]);
run(['reverse',`tcp:${url.port}`,`tcp:${url.port}`]);
run(['shell','am','force-stop',pkg]);
const output=run(['shell','am','instrument','-w','-r','-e','url',connection.url,'-e','key',connection.keys.android,'-e','phase',phase,`${pkg}.test/androidx.test.runner.AndroidJUnitRunner`],300000);
const passed=/OK \(1 test\)/.test(output)&&!/(FAILURES!!!|INSTRUMENTATION_FAILED|Process crashed)/.test(output);
const log=resolve(ROOT,dirname(connectionFile),`native-android-${phase}.log`);
writeFileSync(log,output.replaceAll(connection.keys.android,'[EPHEMERAL_KEY]'),{mode:0o600});
run(['shell','am','force-stop',pkg]);
console.log(JSON.stringify({phase,passed,process_force_stopped:true,log}));
process.exitCode=passed?0:1;
