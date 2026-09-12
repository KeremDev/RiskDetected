export const CONTRACT_TEST_PACKAGE = 'com.riskdetectedan.isg.contracttests.test';
export function validateContractEmulator(serial, avd, sdk, qemu) {
  if (!/^emulator-[0-9]{4,5}$/.test(serial) || !/^ISG_Contract_API(26|33|37)_20260912$/.test(avd) ||
      sdk !== avd.match(/API(\d+)_/)?.[1] || qemu !== '1') throw new Error('ANDROID_CONTRACT_EMULATOR_REJECTED');
}
export function validateContractApkManifest(xml) {
  const permissions = [...xml.matchAll(/<uses-permission\b[^>]*android:name="([^"]+)"/g)].map(m=>m[1]);
  if (!xml.includes(`package="${CONTRACT_TEST_PACKAGE}"`) || !xml.includes(`android:targetPackage="${CONTRACT_TEST_PACKAGE}"`) ||
      !xml.includes('android:name="androidx.test.runner.AndroidJUnitRunner"') ||
      !xml.includes('android:minSdkVersion="26"') || !xml.includes('android:targetSdkVersion="37"') ||
      permissions.some(p=>p !== 'android.permission.REORDER_TASKS') ||
      /<application\b[^>]*android:name=/.test(xml) || !xml.includes('android:usesCleartextTraffic="false"')) {
    throw new Error('ANDROID_CONTRACT_APK_REJECTED');
  }
  return permissions;
}
export function parseContractInstrumentation(output, fixtureIds) {
  const completed = []; let state = {};
  for (const line of output.split(/\r?\n/)) {
    const field = line.match(/^INSTRUMENTATION_STATUS: (class|test|numtests)=(.*)$/);
    if (field) state[field[1]]=field[2];
    const status = line.match(/^INSTRUMENTATION_STATUS_CODE: (-?\d+)$/);
    if (status) {
      if (status[1] !== '1') completed.push({...state,status:Number(status[1])});
      state={};
    }
  }
  const expected = new Set([
    'com.riskdetectedan.isg.contracttests.HarnessIsolationTest#harnessCannotUseNetworkOrLaunchProductionApplication',
    ...fixtureIds.map(id=>'com.riskdetectedan.isg.contracttests.MutationContextInstrumentedTest#sharedMutationContextCorpus['+id+']'),
  ]);
  const names = completed.map(t=>`${t.class}#${t.test}`);
  if (expected.size !== fixtureIds.length+1 || completed.length !== expected.size || new Set(names).size !== expected.size ||
      completed.some(t=>t.status !== 0 || Number(t.numtests) !== expected.size) || names.some(n=>!expected.has(n)) ||
      !output.includes(`OK (${expected.size} tests)`) || !/^INSTRUMENTATION_CODE: -1\s*$/m.test(output) ||
      /INSTRUMENTATION_FAILED|FAILURES!!!|Process crashed/.test(output)) throw new Error('ANDROID_CONTRACT_TESTS_FAILED');
  return completed.map(t=>({class:t.class,test:t.test,result:'PASS'}));
}
