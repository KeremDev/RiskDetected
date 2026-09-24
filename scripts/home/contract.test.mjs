// Keeps the "Senin İçin" card contract between the server and the clients:
// every card the server can send to a contract-1 client has words on iOS and
// Android, every route a client declares is handled by its router, and every
// local draft kind a client sends is one the server accepts and it can word.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, readdirSync} from 'node:fs';

// The newest migration that defines the feed is the one the server runs.
const sql = readdirSync('supabase/migrations').filter(name => /^\d+_isg_home_feed(_[a-z_]+)?\.sql$/.test(name)).sort()
  .map(name => readFileSync(`supabase/migrations/${name}`, 'utf8'))
  .filter(text => text.includes('FUNCTION private_isg.home_feed(')).at(-1);
const section = readFileSync('App/DesignSystem/ISG/NovaForYouSection.swift', 'utf8');
const service = readFileSync('App/Services/ISG/NovaForYouService.swift', 'utf8');
const root = readFileSync('App/Views/Components/NovaPilotMainGate.swift', 'utf8');
const androidNova = 'android/feature/nova/src/main/kotlin/com/riskdetectedan/feature/nova';
const androidSection = readFileSync(`${androidNova}/NovaForYouSection.kt`, 'utf8');
const androidRoot = readFileSync(`${androidNova}/NovaPilotRoot.kt`, 'utf8');
const androidService = readFileSync('android/core/data/src/main/kotlin/com/riskdetectedan/core/data/nova/NovaForYou.kt', 'utf8');

const KINDS = '(?:critical|continue|performance|discover|motivation)';
const localKinds = [...sql.match(/local_kind NOT IN \(([^)]*)\)/)[1].matchAll(/'([a-z_]+)'/g)].map(m => m[1]);
const discoverBlock = sql.match(/FOR rec IN SELECT d\.key, d\.route FROM \(VALUES([\s\S]*?)\) AS d\(key, route, eligible\)/)[1];
const discoverRows = [...discoverBlock.matchAll(/\('([a-z_]+)', '([a-z_]+)', /g)];
const discoverKeys = discoverRows.map(m => m[1]);

function serverKeys() {
  const literal = [...sql.matchAll(new RegExp(`'(${KINDS}\\.[a-z0-9_]+)'`, 'g'))].map(m => m[1]);
  return new Set([...literal, ...localKinds.map(kind => `continue.${kind}`), ...discoverKeys.map(key => `discover.${key}`)]);
}

// Local draft kinds the server accepts for later phases; this build never sends them.
const LATER = new Set(['continue.risk_wizard', 'continue.emergency_wizard', 'continue.emergency_plan_draft']);

function checkWords(worded, client) {
  const missing = [...serverKeys()].filter(key => !worded.has(key) && !LATER.has(key));
  assert.deepEqual(missing, [], `${client} has no words for these cards`);
  const stale = [...worded].filter(key => !serverKeys().has(key));
  assert.deepEqual(stale, [], `${client} words a card the server no longer sends`);
}

function serverRoutes() {
  return new Set([...sql.matchAll(/'route', '([a-z_]+)'/g)].map(m => m[1])
    .concat([...sql.matchAll(/THEN '([a-z_]+)' END/g)].map(m => m[1]))
    .concat(discoverRows.map(m => m[2])));
}

test('every card the server sends has iOS words', () => {
  checkWords(new Set([...section.matchAll(new RegExp(`case "(${KINDS}\\.[a-z0-9_]+)"`, 'g'))].map(m => m[1])), 'iOS');
});

test('every card the server sends has Android words', () => {
  checkWords(new Set([...androidSection.matchAll(new RegExp(`"(${KINDS}\\.[a-z0-9_]+)" ->`, 'g'))].map(m => m[1])), 'Android');
});

test('iOS sends only local draft kinds the server accepts and iOS can word', () => {
  const sent = [...service.matchAll(/kind: "([a-z_]+)"/g)].map(m => m[1]);
  assert.ok(sent.length > 0);
  for (const kind of sent) {
    assert.ok(localKinds.includes(kind), `server does not accept ${kind}`);
    assert.ok(!LATER.has(`continue.${kind}`), `${kind} is sent but has no words yet`);
  }
});

test('every route iOS declares is handled by its router', () => {
  const declared = [...root.match(/private var forYouRoutes: \[String\] \{[\s\S]*?\n    \}/)[0].matchAll(/\("([a-z_]+)", /g)].map(m => m[1]);
  const router = root.match(/private func openForYou\(_ card: NovaForYouCard\) \{[\s\S]*?\n    \}/)[0];
  const handled = new Set([...router.matchAll(/case ((?:"[a-z_]+"(?:, )?)+):/g)].flatMap(m => [...m[1].matchAll(/"([a-z_]+)"/g)].map(x => x[1])));
  assert.deepEqual(declared.filter(route => !handled.has(route)), []);
  assert.deepEqual(declared.filter(route => !serverRoutes().has(route)), [], 'iOS declares a route the server never sends');
});

test('Android sends only local draft kinds the server accepts and Android can word', () => {
  const sent = [...androidService.matchAll(/put\("kind", "([a-z_]+)"\)/g)].map(m => m[1]);
  assert.ok(sent.length > 0);
  for (const kind of sent) {
    assert.ok(localKinds.includes(kind), `server does not accept ${kind}`);
    assert.ok(!LATER.has(`continue.${kind}`), `${kind} is sent but has no words yet`);
  }
});

test('every route Android declares is handled by its router', () => {
  const declared = [...androidRoot.match(/internal fun forYouRoutes\([\s\S]*?\n\}\n/)[0].matchAll(/"([a-z_]+)" to /g)].map(m => m[1]);
  assert.ok(declared.length > 0);
  const router = androidRoot.match(/fun openForYou\(card: NovaForYouCard\) \{[\s\S]*?\n    \}\n/)[0];
  const handled = new Set([...router.matchAll(/^\s+((?:"[a-z_]+"(?:, )?)+) ->/gm)].flatMap(m => [...m[1].matchAll(/"([a-z_]+)"/g)].map(x => x[1])));
  assert.deepEqual(declared.filter(route => !handled.has(route)), []);
  assert.deepEqual(declared.filter(route => !serverRoutes().has(route)), [], 'Android declares a route the server never sends');
});
