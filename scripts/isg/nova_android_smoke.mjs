import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';
import { ROOT } from './lib.mjs';

// UI-tree-derived inputs only. Already-built offline QA package on one dedicated emulator.
// No production install, account, data reset, arbitrary device, or guessed tap coordinates.
const serial = process.argv[3];
assert.equal(process.argv.length, 4);
assert.equal(process.argv[2], '--serial');
assert.match(serial, /^emulator-\d+$/);
const pkg = 'com.riskdetectedan.isg.designpreview';
const adb = (...args) => execFileSync('adb', ['-s', serial, ...args], { timeout: 20000 });
assert.equal(adb('emu', 'avd', 'name').toString().split(/\r?\n/)[0], 'ISG_Contract_API33_20260912');
assert.equal(adb('shell', 'getprop', 'ro.kernel.qemu').toString().trim(), '1');
assert.equal(adb('shell', 'getprop', 'ro.build.version.sdk').toString().trim(), '33');
assert.match(adb('shell', 'wm', 'size').toString(), /440x956/);
assert.match(adb('shell', 'wm', 'density').toString().trim(), /density: 160$/);
const out = resolve(ROOT, 'output/isg/reference-redesign-20260913/android-device-smoke');
mkdirSync(out, { recursive: true });
let sequence = 0;
const checks = [];
function tree() {
  const xml = adb('exec-out', 'uiautomator', 'dump', '/dev/tty').toString();
  writeFileSync(resolve(out, `${++sequence}-ui.xml`), xml);
  // Launch/dismiss can briefly expose the launcher; wait for our target, never tap it.
  if (!xml.includes(`package="${pkg}"`)) return [];
  return [...xml.matchAll(/<node\b[^>]+/g)].map(([node]) => {
    const attr = name => node.match(new RegExp(`${name}="([^"]*)"`))?.[1] ?? '';
    return { text: attr('text'), label: attr('content-desc'), bounds: attr('bounds'), type: attr('class') };
  });
}
function find(text, partial = false) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const node = tree().find(n => [n.text, n.label].some(s => partial ? s.includes(text) : s === text));
    if (node) return node;
  }
  throw new Error(`Visible node missing: ${text}`);
}
function tap(text, partial = false) {
  const node = find(text, partial);
  const nums = node.bounds.match(/\d+/g).map(Number);
  assert.equal(nums.length, 4);
  adb('shell', 'input', 'tap', String(Math.round((nums[0] + nums[2]) / 2)), String(Math.round((nums[1] + nums[3]) / 2)));
}
function shot(name) {
  writeFileSync(resolve(out, `${name}.png`), adb('exec-out', 'screencap', '-p'));
}
function pass(name) { checks.push(name); console.log(`PASS ${name}`); }

adb('shell', 'am', 'force-stop', pkg);
adb('shell', 'am', 'start', '-n', `${pkg}/.DesignPreviewActivity`);
find('Merhaba, Kerem'); shot('home'); pass('home-visible');
tap('Menüyü aç'); find('İşletme Hafızası'); find('Rapor Arşivi'); shot('drawer'); pass('drawer-visible');
tap('Kapat'); find('Merhaba, Kerem');
tap('Bildirimler', true); find('Termini geçen aksiyonlar'); find('Aktif uygunsuzluklar');
const close = find('Kapat').bounds.match(/\d+/g).map(Number);
assert.ok(close[2] - close[0] >= 48 && close[3] - close[1] >= 48, 'Notification close must retain a 48dp target at mdpi');
shot('notifications'); pass('notification-popup-and-close-target');
tap('Tümünü oku'); find('Aktif uygunsuzluklar');
tap('Bildirimleri sil'); find('Yeni bildirim yok'); pass('read-and-clear-notifications');
tap('Kapat'); find('Merhaba, Kerem');
tap('Ekle'); for (const label of ['Uygunsuzluk Ekle', 'Dosya Ekle', 'Ziyaret Ekle', 'Eğitim Ekle']) find(label);
shot('quick-add'); pass('four-quick-actions-and-window-backdrop');
tap('Vazgeç'); find('Merhaba, Kerem');
tap('Firmalar'); find('Koza Altın A.Ş'); shot('companies'); pass('company-list');
tap('Firma ara'); adb('shell', 'input', 'text', 'bulunmayan'); find('Firma bulunamadı');
tap('Aramayı temizle'); find('Koza Altın A.Ş'); pass('company-search-empty-and-clear');
tap('Koza Altın A.Ş'); find('Sentetik hedef:', true); pass('company-row-navigation');
const pid = adb('shell', 'pidof', '-s', pkg).toString().trim();
assert.match(pid, /^\d+$/);
const crash = adb('logcat', '-d', '-b', 'crash', '--pid', pid).toString();
assert.ok(!crash.includes('FATAL EXCEPTION'));
writeFileSync(resolve(out, 'crash.log'), crash);
writeFileSync(resolve(out, 'result.json'), JSON.stringify({ date: new Date().toISOString(), serial,
  avd: 'ISG_Contract_API33_20260912', package: pkg, checks, result: 'passed',
  scope: 'offline synthetic window/UI smoke; not domain E2E, billing, live Auth, API26/37 or TalkBack proof' }, null, 2) + '\n');
