import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
import { ROOT } from './lib.mjs';
import { CONTRACT_TEST_PACKAGE, validateContractEmulator, validateContractApkManifest, parseContractInstrumentation } from './android_contract_guard.mjs';

test('Android contract lane accepts only its dedicated API26/33/37 emulator identities', () => {
  for(const api of ['26','33','37'])assert.doesNotThrow(()=>validateContractEmulator('emulator-5554',`ISG_Contract_API${api}_20260912`,api,'1'));
  for(const args of [['real-device','ISG_Contract_API33_20260912','33','1'],['emulator-5554','RiskDetected_API33_Standard','33','1'],
    ['emulator-5554','ISG_Contract_API33_20260912','37','1'],['emulator-5554','ISG_Contract_API33_20260912','33','0']]) {
    assert.throws(()=>validateContractEmulator(...args),/ANDROID_CONTRACT_EMULATOR_REJECTED/);
  }
});
test('Android runner refuses absent, physical, arbitrary and extra targets before ADB/build/output', () => {
  for(const args of [[],['--serial','physical-device'],['--serial','emulator-5554','extra'],['--device','emulator-5554']]) {
    const r=spawnSync(process.execPath,['scripts/isg/run_android_contract.mjs',...args],{cwd:ROOT,encoding:'utf8',timeout:5000,env:{PATH:'/no-tools-available'}});
    const report=JSON.parse(r.stdout);
    assert.equal(r.status,1);assert.equal(report.error_code,'ANDROID_CONTRACT_EXPLICIT_SERIAL_REQUIRED');
    assert.equal(report.evidence_directory,null);assert.equal(report.cleanup,'NOT_NEEDED');
  }
});
const manifest = () => `<manifest package="${CONTRACT_TEST_PACKAGE}"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="37"/>
<instrumentation android:targetPackage="${CONTRACT_TEST_PACKAGE}" android:name="androidx.test.runner.AndroidJUnitRunner"/>
<uses-permission android:name="android.permission.REORDER_TASKS"/><application android:usesCleartextTraffic="false"/></manifest>`;
test('Android APK gate permits no network permission, production target or custom Application', () => {
  assert.deepEqual(validateContractApkManifest(manifest()),['android.permission.REORDER_TASKS']);
  for(const xml of [manifest().replace(CONTRACT_TEST_PACKAGE,'com.riskdetectedan.app'),
    manifest().replace('android.permission.REORDER_TASKS','android.permission.INTERNET'),
    manifest().replace('android.permission.REORDER_TASKS','android.permission.CAMERA'),
    manifest().replace('<application ','<application android:name="ProductionApplication" '),
    manifest().replace('android:usesCleartextTraffic="false"','android:usesCleartextTraffic="true"'),
    manifest().replace('android:targetSdkVersion="37"','android:targetSdkVersion="33"')]) {
    assert.throws(()=>validateContractApkManifest(xml),/ANDROID_CONTRACT_APK_REJECTED/);
  }
});
function result() {
  return [['HarnessIsolationTest','harnessCannotUseNetworkOrLaunchProductionApplication'],['MutationContextInstrumentedTest','sharedMutationContextCorpus[one]']]
    .map(([c,t])=>`INSTRUMENTATION_STATUS: class=com.riskdetectedan.isg.contracttests.${c}\nINSTRUMENTATION_STATUS: test=${t}\nINSTRUMENTATION_STATUS: numtests=2\nINSTRUMENTATION_STATUS_CODE: 0\n`).join('')+'OK (2 tests)\nINSTRUMENTATION_CODE: -1\n';
}
test('instrumentation gate requires every distinct corpus test and isolation test, no silent skip', () => {
  assert.equal(parseContractInstrumentation(result(),['one']).length,2);
  for(const output of [result().replace('INSTRUMENTATION_STATUS_CODE: 0','INSTRUMENTATION_STATUS_CODE: -2'),
    result().replace('INSTRUMENTATION_STATUS_CODE: 0','INSTRUMENTATION_STATUS_CODE: -3'),
    result().replace('[one]','[unknown]'),result().replace('numtests=2','numtests=3'),
    result().replace('OK (2 tests)','OK (1 tests)'),result().replace('INSTRUMENTATION_CODE: -1','INSTRUMENTATION_CODE: 0'),
    result()+result(),result()+'INSTRUMENTATION_FAILED: crash']) {
    assert.throws(()=>parseContractInstrumentation(output,['one']),/ANDROID_CONTRACT_TESTS_FAILED/);
  }
  assert.throws(()=>parseContractInstrumentation(result(),['one','one']),/ANDROID_CONTRACT_TESTS_FAILED/);
});
test('test library references the actual parser and shared corpus without :app or network SDK dependencies', () => {
  const build=readFileSync(resolve(ROOT,'android/isg-contract-tests/build.gradle.kts'),'utf8');
  assert.match(build,/alias\(libs\.plugins\.android\.library\)/);
  assert.match(build,/getByName\("main"\)\.kotlin\.directories\.add\("\.\.\/core\/data\/src\/main\/kotlin\/com\/riskdetectedan\/core\/data\/isg"\)/);
  assert.match(build,/getByName\("androidTest"\)\.assets\.directories\.add\("\.\.\/\.\.\/contracts\/isg\/v1\/fixtures"\)/);
  assert.doesNotMatch(build,/implementation\(project|libs\.(supabase|revenuecat|firebase|facebook|hilt|ktor)/);
  const app=readFileSync(resolve(ROOT,'android/app/build.gradle.kts'),'utf8');
  assert.doesNotMatch(app, /project\(":isg-contract-tests"\)/);
  assert.match(readFileSync(resolve(ROOT,'.github/workflows/android-ci.yml'),'utf8'),/run: \.\/gradlew :isg-contract-tests:assembleDebugAndroidTest --stacktrace/);
});
