import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ROOT } from './lib.mjs';

const read = path => readFileSync(resolve(ROOT, path), 'utf8');
const { icons } = JSON.parse(read('contracts/isg/v1/design/nova-icon-paths.json'));
test('all 48 original OSGB icons have template iOS assets and native Android vectors', () => {
  assert.equal(Object.keys(icons).length, 48);
  for (const [name, definition] of Object.entries(icons)) {
    const ios = `App/Resources/NovaIcons.xcassets/Nova_${name}.imageset`;
    const contents = JSON.parse(read(`${ios}/Contents.json`));
    assert.equal(contents.properties['template-rendering-intent'], 'template');
    assert.equal(contents.properties['preserves-vector-representation'], true);
    const svg = read(`${ios}/icon.svg`);
    const android = read(`android/core/designsystem/src/main/res/drawable/nova_${name.replace(/[A-Z]/g, c => `_${c.toLowerCase()}`)}.xml`);
    assert.ok(svg.includes(`viewBox="${definition.viewBox}"`), name);
    const [, , width, height] = definition.viewBox.split(' ');
    assert.ok(android.includes(`android:viewportWidth="${width}"`), name);
    assert.ok(android.includes(`android:viewportHeight="${height}"`), name);
    for (const element of definition.elements.filter(e => e.kind === 'path')) {
      assert.ok(svg.includes(`d="${element.d}"`), name);
      assert.ok(android.includes(`android:pathData="${element.d}"`), name);
    }
  }
});
test('iOS application and both independent harnesses include the original icon catalog', () => {
  assert.match(read('tests/isg/shell-ios/project.yml'), /App\/Resources\/NovaIcons.xcassets/);
  assert.match(read('tests/isg/design-ios/ISGDesignTests.xcodeproj/project.pbxproj'), /App\/Resources\/NovaIcons.xcassets/);
  assert.match(read('RiskDetected.xcodeproj/project.pbxproj'), /PBXFileSystemSynchronizedRootGroup/);
});
test('photo backdrop keeps the two mechanically extracted original Feather outlines', () => {
  const { paths, viewport } = JSON.parse(read('contracts/isg/v1/design/nova-photo-paths.json'));
  assert.equal(viewport, 24);
  assert.deepEqual(Object.keys(paths).sort(), ['camera', 'photo']);
  for (const [name, path] of Object.entries(paths)) {
    assert.ok(read(`App/Resources/NovaIcons.xcassets/Nova_backdrop_${name}.imageset/icon.svg`).includes(`d="${path}"`));
    assert.ok(read(`android/core/designsystem/src/main/res/drawable/nova_backdrop_${name}.xml`).includes(`android:pathData="${path}"`));
  }
  assert.match(read('contracts/isg/v1/design/FEATHER-LICENSE.txt'), /MIT License/);
});
test('Android visual host is debug-only, offline and outside the production dependency graph', () => {
  const build = read('android/isg-design-preview/build.gradle.kts');
  const manifest = read('android/isg-design-preview/src/main/AndroidManifest.xml');
  const host = read('android/isg-design-preview/src/main/kotlin/com/riskdetectedan/isg/designpreview/DesignPreviewActivity.kt');
  assert.match(build, /applicationId = "com\.riskdetectedan\.isg\.designpreview"/);
  assert.match(build, /withBuildType\("release"\)\) \{ it.enable = false/);
  assert.doesNotMatch(build, /project\(":(?:app|core:data)"\)/);
  assert.doesNotMatch(read('android/app/build.gradle.kts'), /isg-design-preview/);
  assert.match(manifest, /android.permission.INTERNET" tools:node="remove"/);
  assert.match(manifest, /android:allowBackup="false"/);
  assert.match(host, /Build.FINGERPRINT/);
  assert.doesNotMatch(host, /Supabase|RevenueCat|SharedPreferences|http[s]?:\/\//);
});
