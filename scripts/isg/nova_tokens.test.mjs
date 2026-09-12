import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import { ROOT } from './lib.mjs';
import { reference, renderTokens, tokenModel, rgba } from './nova_tokens.mjs';

const read = p => readFileSync(resolve(ROOT, p));
const sha = b => createHash('sha256').update(b).digest('hex');
test('both native token sources and test corpus exactly match the pinned expert reference', () => {
  for (const [path, expected] of Object.entries(renderTokens())) assert.equal(read(path).toString(), expected, path);
  const m = tokenModel();
  assert.deepEqual(Object.fromEntries(Object.entries(m).map(([k, v]) => [k, Object.keys(v).length])),
    { light: 40, dark: 40, typography: 17, dimensions: 26 });
});
test('other-role colors cannot enter the expert native token outputs', () => {
  const copy = structuredClone(reference);
  for (const role of ['osgb', 'company', 'assignee']) copy.tokens.roleAccent[role] = { light: 'invalid' };
  assert.deepEqual(renderTokens(copy), renderTokens());
});
test('source change changes native outputs; a stale generated file is detectable', () => {
  const copy = structuredClone(reference);
  copy.tokens.roleAccent.expert.light = '#123456';
  for (const [path, content] of Object.entries(renderTokens(copy))) assert.notEqual(content, read(path).toString());
});
test('RGBA conversion preserves transparent source colors and rejects unsupported formats', () => {
  assert.deepEqual(rgba('rgba(255,255,255,.62)'), [255,255,255,.62]);
  assert.deepEqual(rgba('#2ed256'), [46,210,86,1]);
  for (const bad of ['red', '#fff', 'rgba(256,0,0,.1)', 'rgba(1,2,3,2)']) assert.throws(() => rgba(bad));
});
test('all five licensed font binaries match across clients and iOS registers each file', () => {
  const manifest = JSON.parse(read('contracts/isg/v1/design/nova-font-assets.json'));
  assert.deepEqual(manifest.fonts.map(f => f.weight), [400,500,600,700,800]);
  const plist = read('Config/RiskDetectedInfo.plist').toString();
  const compose = read('android/core/designsystem/src/main/kotlin/com/riskdetectedan/core/designsystem/isg/NovaComponents.kt').toString();
  for (const f of manifest.fonts) {
    for (const path of [f.ios, f.android]) { assert.equal(sha(read(path)), f.sha256); assert.equal(read(path).length, f.bytes); }
    assert.ok(plist.includes(`<string>${f.postscript_name}.ttf</string>`));
    assert.ok(compose.includes(`R.font.${f.android.split('/').at(-1).replace('.ttf','')}`));
  }
  for (const path of ['App/Resources/Fonts/OFL-PlusJakartaSans.txt', 'android/core/designsystem/src/main/res/raw/ofl_plus_jakarta_sans.txt']) {
    assert.equal(sha(read(path)), manifest.license_sha256);
    assert.match(read(path).toString(), /SIL OPEN FONT LICENSE Version 1.1/);
  }
});
test('Gradle tracks design corpus changes and the Swift font probe checks Turkish glyphs', () => {
  assert.match(read('android/core/designsystem/build.gradle.kts').toString(), /inputs\.dir\(rootProject\.layout\.projectDirectory\.dir\("\.\.\/contracts\/isg\/v1\/design"\)\)/);
  assert.match(read('scripts/isg/NovaTokenCheck.swift').toString(), /CTFontGetGlyphsForCharacters/);
});
test('accessible primary label adaptation is explicit in both clients', () => {
  const luminance = rgb => rgb.map(v => v / 255).map(v => v <= .04045 ? v / 12.92 : ((v+.055)/1.055)**2.4)
    .reduce((s,v,i) => s+v*[.2126,.7152,.0722][i], 0);
  const contrast = (a,b) => (Math.max(luminance(a),luminance(b))+.05)/(Math.min(luminance(a),luminance(b))+.05);
  const green = tokenModel().light.accent.slice(0,3);
  assert.ok(contrast([255,255,255],green) < 3);
  assert.ok(contrast([17,17,17],green) > 7);
  assert.match(read('App/DesignSystem/ISG/NovaComponents.swift').toString(), /NovaRGBA\(red: 17, green: 17, blue: 17, alpha: 1\)/);
  assert.match(read('android/core/designsystem/src/main/kotlin/com/riskdetectedan/core/designsystem/isg/NovaComponents.kt').toString(), /Color\(0xFF111111\)/);
});
test('native iOS design harness is hostless, service-free and rejects blank renders', () => {
  const project = read('tests/isg/design-ios/ISGDesignTests.xcodeproj/project.pbxproj').toString();
  assert.equal((project.match(/TEST_HOST = ""/g) ?? []).length, 2);
  assert.ok(!/XCRemoteSwiftPackageReference|PBXShellScriptBuildPhase|App\/Services|product-type.application/.test(project));
  assert.ok(project.includes('../../../App/DesignSystem/ISG/NovaComponents.swift'));
  const harness = read('tests/isg/design-ios/NovaRenderTests.swift').toString();
  assert.equal((harness.match(/func test_/g) ?? []).length, 12);
  assert.match(harness, /NovaComponentGalleryContent/);
  assert.match(harness, /XCTAssertGreaterThan\(distinct.count, 12/);
  assert.match(harness, /CTFontManagerRegisterFontsForURL/);
});
test('expert navigation corpus covers every destination across availability and session freshness', () => {
  const catalog = JSON.parse(read('contracts/isg/v1/design/nova-navigation.json'));
  const fixtures = JSON.parse(read('contracts/isg/v1/fixtures/nova-navigation.json')).cases;
  const ids = fixtures.map(c => c.id);
  assert.equal(new Set(ids).size, ids.length);
  assert.deepEqual(catalog.tabs.map(t => t.id), ['home', 'findings', 'companies', 'profile']);
  assert.equal(catalog.drawer.length, 13);
  assert.equal(catalog.quickAdd.length, 4);
  assert.equal(catalog.destinations.length, 17);
  for (const d of catalog.destinations) for (const availability of ['enabled', 'locked']) for (const epoch of ['fresh', 'stale']) {
    assert.ok(ids.includes(`route-${d.id}-${availability}-${epoch}`));
  }
  for (const c of fixtures) for (const step of c.steps) {
    assert.deepEqual(Object.keys(step.expected.paths), catalog.tabs.map(t => t.id));
    assert.ok(!['quickAdd', 'drawer'].includes(step.expected.selected));
  }
  assert.match(read('android/core/designsystem/build.gradle.kts').toString(), /inputs\.file\(rootProject\.layout\.projectDirectory\.file\("\.\.\/contracts\/isg\/v1\/fixtures\/nova-navigation.json"\)\)/);
  assert.match(read('.github/workflows/isg-foundation.yml').toString(), /NovaNavigationCheck.swift/);
});
test('native shell has no live service dependency and remains outside legacy roots', () => {
  for (const path of ['App/DesignSystem/ISG/NovaExpertShell.swift', 'android/core/designsystem/src/main/kotlin/com/riskdetectedan/core/designsystem/isg/NovaExpertShell.kt']) {
    const source = read(path).toString();
    assert.doesNotMatch(source, /import (Supabase|RevenueCat)|URLSession|OkHttpClient|SupabaseClient|Purchases\.shared/);
    assert.match(source, /nova\.panel\.close/);
  }
  assert.doesNotMatch(read('App/Views/Home/MainTabView.swift').toString(), /NovaExpertShell/);
  const project = read('tests/isg/design-ios/ISGDesignTests.xcodeproj/project.pbxproj').toString();
  assert.match(project, /NovaNavigation.swift/);
  assert.match(project, /NovaShellTests.swift/);
});
test('hosted iOS shell target compiles only the real NOVA sources and synthetic harness', () => {
  const project = read('tests/isg/shell-ios/ISGShellHarness.xcodeproj/project.pbxproj').toString();
  const swiftFiles = [...project.matchAll(/path = ([A-Za-z]+\.swift);/g)].map(m => m[1]).sort();
  assert.deepEqual(swiftFiles, ['NovaComponents.swift', 'NovaExpertShell.swift', 'NovaNavigation.swift', 'NovaTokens.swift', 'ShellHarnessApp.swift', 'ShellUITests.swift']);
  assert.match(project, /path = \.\.\/\.\.\/\.\.\/App\/DesignSystem\/ISG;/);
  assert.match(project, /SUPPORTED_PLATFORMS = iphonesimulator;/);
  assert.match(project, /PRODUCT_BUNDLE_IDENTIFIER = com\.riskdetected\.isgshellharness;/);
  assert.doesNotMatch(project, /XCRemoteSwiftPackageReference|PBXShellScriptBuildPhase|App\/Services|RiskDetected\.xcodeproj|CODE_SIGN_ENTITLEMENTS/);
  for (const file of ['NovaComponents.swift', 'NovaExpertShell.swift', 'NovaNavigation.swift', 'NovaTokens.swift']) {
    const imports = [...read(`App/DesignSystem/ISG/${file}`).toString().matchAll(/^import (\w+)/gm)].map(m => m[1]);
    assert.ok(imports.every(name => ['Foundation', 'SwiftUI'].includes(name)));
  }
  const host = read('tests/isg/shell-ios/ShellHarnessApp.swift').toString();
  assert.match(host, /#if !targetEnvironment\(simulator\)/);
  assert.match(host, /#error\(/);
  assert.doesNotMatch(host, /URLSession|Keychain|Supabase|Purchases|UserDefaults|openURL|FileManager/);
  assert.doesNotMatch(read('RiskDetected.xcodeproj/project.pbxproj').toString(), /ShellHarnessApp|ISGShellHarness|ShellUITests/);
});
test('hosted UI tests assert actual content, fonts and hittability instead of only router state', () => {
  const test = read('tests/isg/shell-ios/ShellUITests.swift').toString();
  assert.match(test, /XCUIApplication\(bundleIdentifier: "com\.riskdetected\.isgshellharness"\)/);
  assert.match(test, /qa\.content/);
  assert.match(test, /node\.isHittable/);
  assert.match(test, /fonts=ok/);
  const info = read('tests/isg/shell-ios/HarnessInfo.plist').toString();
  assert.match(info, /<key>UIAppFonts<\/key>/);
  assert.equal((info.match(/\.ttf<\/string>/g) ?? []).length, 5);
  assert.doesNotMatch(info, /CFBundleURLTypes|NSCameraUsageDescription|NSPhotoLibraryUsageDescription|NSAppTransportSecurity/);
});
