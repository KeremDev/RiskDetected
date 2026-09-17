// Offline Phase A discovery. No DB connection, credentials, mutations or deployment.
// This is a lexical source index, not the effective PostgreSQL schema/RLS catalog.
// Usage: node scripts/isg/osgb_repo_inventory.mjs > /tmp/osgb-source-index.json
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root = resolve(import.meta.dirname, '../..');
const git = (...args) => execFileSync('git', args, {cwd: root, encoding: 'utf8'}).trimEnd();
const paths = git('ls-files', '-z').split('\0').filter(Boolean).sort();
const lane = path => path.startsWith('supabase/pilot-release/supabase/migrations/')
  ? 'pilot-ledger-mirror-not-live-verified'
  : path.startsWith('supabase/pilot-release/candidates/') ? 'pilot-candidate'
  : 'root-migration-mixed-history-and-candidates';
const tables = [];
const clientCalls = [];
const sqlPaths = paths.filter(path => /^supabase\/(migrations|pilot-release\/(candidates|supabase\/migrations))\/.*\.sql$/.test(path));
for (const path of sqlPaths) {
  const source = readFileSync(resolve(root, path), 'utf8');
  for (const match of source.matchAll(/^[ \t]*CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([\w.\"]+)\s*\(/gmi)) {
    const line = source.slice(0, match.index).split('\n').length;
    tables.push({symbol: match[1], path, line, lane: lane(path)});
  }
}
for (const path of paths.filter(path => /^(App\/Services\/|android\/core\/data\/src\/main\/)/.test(path) && /\.(swift|kt)$/.test(path))) {
  const source = readFileSync(resolve(root, path), 'utf8');
  // Dynamic endpoint variables and indirect calls require manual review.
  for (const match of source.matchAll(/\b(rpc|from|invoke)\s*\(\s*"([a-z][a-z0-9_-]+)"/g)) {
    clientCalls.push({kind: match[1], symbol: match[2], path, line: source.slice(0, match.index).split('\n').length});
  }
}
const edgeEntrypoints = paths.filter(path => /^supabase\/functions\/[^/]+\/index\.ts$/.test(path));
const uniqueTables = [...new Set(tables.map(row => row.symbol))].sort();
console.log(JSON.stringify({
  formatVersion: 1,
  head: git('rev-parse', 'HEAD'),
  branch: git('branch', '--show-current'),
  method: 'Tracked source files in the working tree; lexical declarations and literal callsites only. Comments/dynamic SQL/indirect calls may require manual review. Repeated migrations are not distinct deployed tables. No remote schema or access proof.',
  counts: {sqlFiles: sqlPaths.length, tableDeclarations: tables.length, uniqueTableNames: uniqueTables.length, literalClientCalls: clientCalls.length, edgeEntrypoints: edgeEntrypoints.length},
  sqlFiles: sqlPaths.map(path => ({path, lane: lane(path)})),
  uniqueTableNames: uniqueTables, tableDeclarations: tables, clientCalls, edgeEntrypoints
}, null, 2));
