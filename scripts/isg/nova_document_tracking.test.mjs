import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(join(ROOT,path),'utf8');
const migration=read('supabase/migrations/20260914210000_isg_document_tracking.sql');
const model=read('App/DesignSystem/ISG/NovaDocumentTracking.swift');
const screen=read('App/DesignSystem/ISG/NovaDocumentTrackingScreens.swift');
const sheets=read('App/DesignSystem/ISG/NovaDocumentTrackingSheets.swift');
const service=read('App/Services/Company/NovaDocumentTrackingService.swift');
const gate=read('App/Views/Components/NovaPilotDocumentGate.swift');
const portfolio=read('supabase/migrations/20260914230000_isg_document_portfolio.sql');
// The ban is on what the product says and does, not on the word appearing in a
// comment that explains why it is banned.
const code=source=>source.split('\n').filter(line=>!/^\s*\/\//.test(line)).join('\n');

test('the tracker design layer stays free of the SDK and of legacy writes',()=>{
  for(const [path,source] of [['NovaDocumentTracking.swift',model],
    ['NovaDocumentTrackingScreens.swift',screen],['NovaDocumentTrackingSheets.swift',sheets]]){
    assert.doesNotMatch(source,/import (Supabase|RevenueCat)|https?:|access_token|refresh_token|UserDefaults|Keychain/,path);
    assert.doesNotMatch(source,/AnalysisService|SupabaseService|PDFReportService/,path);
  }
});

test('the client reads the status and never works one out for itself',()=>{
  // The status arrives as a word from the server and is only decoded.
  assert.match(service,/status: NovaDocumentStatus\(rawValue: row\.status\) \?\? \.missing/);
  // Nothing on this side compares a date to today to decide a status.
  for(const [path,source] of [['model',model],['screen',screen],['sheets',sheets],['service',service]]){
    assert.doesNotMatch(source,/status\s*=\s*[^\n]*(Date\(\)|today|timeIntervalSince)/,path);
    assert.doesNotMatch(source,/\.expired\s*:\s*\.valid|validUntil\s*<\s*/,path);
  }
  // An unknown word is not quietly downgraded to the calmest answer.
  assert.match(service,/\?\? \.missing/);
});

test('the tracker never states compliance and never claims a stored file',()=>{
  for(const source of [model,screen,sheets,service])
    assert.doesNotMatch(code(source),/uygunluk|compliance|compliant/i);
  // Both the list and the copy form say the file is not kept here.
  assert.match(screen,/localizable\.nova\.document\.hint/);
  assert.match(sheets,/localizable\.nova\.document\.copies\.hint/);
  assert.match(model,/var fileStored: Bool = false/);
});

test('a legal basis is never offered without the reference it relies on',()=>{
  assert.match(model,/if basis == \.legal && legalRef\.trimmingCharacters\(in: \.whitespaces\)\.isEmpty \{ return false \}/);
  // The server refuses the same thing, so the form and the schema agree.
  assert.match(migration,/CHECK\(basis<>'legal' OR \(legal_ref IS NOT NULL AND btrim\(legal_ref\)<>''\)\)/);
  assert.match(sheets,/localizable\.nova\.document\.basis\.legal\.hint/);
});

test('the kinds on screen are the server catalogue, not a list of their own',()=>{
  // The picker walks what the read returned; it never invents a code.
  assert.match(sheets,/ForEach\(kinds\) \{ kind in kindCell\(kind\) \}/);
  // The catalogue is read for the company the obligation will belong to.
  assert.match(screen,/let kinds: \(UUID\) async throws -> \[NovaDocumentKind\]/);
  // Every code the words file names is one the schema allows.
  const allowed=new Set([...migration.slice(migration.indexOf('kind_code text PRIMARY KEY CHECK'),
    migration.indexOf('ordinal integer NOT NULL')).matchAll(/'([a-z_]+)'/g)].map(m=>m[1]));
  const named=[...model.slice(model.indexOf('static func kind(_ code: String)'),
    model.indexOf('static func kindSymbol')).matchAll(/case "([a-z_]+)":/g)].map(m=>m[1]);
  assert.ok(named.length>0);
  for(const code of named) assert.ok(allowed.has(code),code);
  // A health record has no name on this side either.
  assert.doesNotMatch(code(model),/saglik|sağlık|health|muayene/i);
});

test('the service sends only what the server agreed to read',()=>{
  const allowlist=migration.slice(migration.indexOf('allowed:=CASE p_action'),migration.indexOf('IF allowed IS NULL'));
  const allowed=Object.fromEntries([...allowlist.matchAll(/WHEN '([a-z_]+)' THEN ARRAY\[([^\]]+)\]/g)]
    .map(([,action,keys])=>[action,new Set([...keys.matchAll(/'([a-z_]+)'/g)].map(m=>m[1]))]));
  assert.deepEqual(Object.keys(allowed).sort(),
    ['add_obligation','archive_obligation','record_copy','remove_copy','update_obligation']);
  // Every payload key the Swift writes is one of those, per action.
  const keys=source=>[...source.matchAll(/payload\["([a-z_]+)"\]|"([a-z_]+)": \./g)]
    .map(m=>m[1]??m[2]).filter(key=>!key.startsWith('p_'));
  const body=service.slice(service.indexOf('private static func body('),service.indexOf('func add('));
  for(const key of keys(body)) assert.ok(allowed.add_obligation.has(key),`add_obligation ${key}`);
  const copy=service.slice(service.indexOf('func recordCopy('),service.indexOf('func removeCopy('));
  for(const key of keys(copy)) assert.ok(allowed.record_copy.has(key),`record_copy ${key}`);
  // A status is never a key the client sends, under any action.
  assert.doesNotMatch(service,/payload\["status"\]|"status": \./);
});

test('every read and every write re-checks the scope it was given',()=>{
  // The check runs before the call and again after it, exactly like personnel.
  const calls=[...service.matchAll(/try check\(scope\)/g)].length;
  assert.ok(calls>=8,`expected both sides of every call, found ${calls}`);
  assert.match(service,/guard isCurrent\(scope\) else \{ throw NovaDocumentFailure\.denied \}/);
  // Selecting a company waits for the real availability check to land.
  assert.match(gate,/private func waitForScope\(_ target: UUID\) async throws -> NovaPersonnelScope/);
  assert.match(gate,/throw NovaDocumentFailure\.denied/);
});

test('the menu entry lands on the tracker and on nothing else',()=>{
  const main=read('App/Views/Components/NovaPilotMainGate.swift');
  assert.match(main,/case \.documentChecklist:\s*\n\s*documents/);
  assert.match(main,/NovaPilotDocumentGate\(identity: identity/);
  const navigation=read('App/DesignSystem/ISG/NovaNavigation.swift');
  assert.ok(navigation.includes('.documentChecklist,'));
  // The destination is offered rather than left disabled in the drawer.
  assert.match(main,/available: \[[^\]]*\.documentChecklist\]/);
});

test('the portfolio page reads the account once and shows ten at a time',()=>{
  const model=read('App/DesignSystem/ISG/NovaDocumentTracking.swift');
  assert.match(model,/struct NovaDocumentQuery[\s\S]{0,400}?var limit = 10/);
  // One call per page, never one per company.
  assert.match(gate,/portfolio: \{ request in[\s\S]{0,300}?service\.portfolio\(identity/);
  assert.doesNotMatch(gate,/for .* in companies|companies\.map \{[^}]*await/);
  // Asking for more re-reads the page rather than trimming what is on screen.
  assert.match(screen,/shown \+= NovaDocumentQuery\(\)\.limit/);
  // A company is chosen before anything is tracked, and the picker lists every
  // company before a single character is typed.
  assert.match(screen,/if company == nil \{ picker \} else \{ tracker \}/);
  assert.match(screen,/guard !needle\.isEmpty else \{ return companies \}/);
  assert.match(screen,/localizable\.nova\.document\.pick\.company/);
  // The counters follow what is on screen, not the account headline.
  assert.match(screen,/if let initialKinds \{ return board\.counts\(forKinds: initialKinds\) \}/);
  assert.match(screen,/if let selectedCompany \{ return selectedCompany\.counts \}/);
  assert.match(screen,/\.onChange\(of: status\)[\s\S]{0,120}?reload = UUID\(\)/);
  assert.match(screen,/\.onChange\(of: company\)[\s\S]{0,120}?reload = UUID\(\)/);
  // The headline counts the account, not the page that happens to be loaded.
  assert.match(portfolio,/FROM \(SELECT state,count\(\*\) AS total FROM page GROUP BY state\) tally/);
});

test('a company page heading reads the tracker, not a second list',()=>{
  const model=read('App/DesignSystem/ISG/NovaDocumentTracking.swift');
  const migration=read('supabase/migrations/20260914210000_isg_document_tracking.sql');
  // Every kind a heading claims is a kind the schema allows.
  const allowed=new Set([...migration.slice(migration.indexOf('kind_code text PRIMARY KEY CHECK'),
    migration.indexOf('ordinal integer NOT NULL')).matchAll(/'([a-z_]+)'/g)].map(m=>m[1]));
  const mapped=[...model.slice(model.indexOf('enum NovaDocumentSectionMap'),
    model.indexOf('/// What the portfolio page is asking for')).matchAll(/"([a-z_]+)"/g)].map(m=>m[1]);
  assert.ok(mapped.length>0);
  for(const kind of mapped) assert.ok(allowed.has(kind),kind);
  // Training documents stay with the training module, and the headings that are
  // not document obligations claim none.
  assert.match(model,/case \.training, \.logo, \.personnel, \.support, \.accidents: return nil/);
  // The company page reads one tally for every heading, not one call each.
  const company=read('App/Views/Components/NovaCompanyManagementGate.swift');
  assert.match(company,/service\.portfolio\(documentIdentity, company: scope\.companyID, limit: 1\)/);
  assert.match(company,/NovaDocumentSectionMap\.kinds\(for: section\)/);
  assert.match(company,/documents\?\.counts\(forKinds: kinds\)/);
  assert.match(portfolio,/\), scoped AS \(/);
  assert.match(portfolio,/'kind_counts',tally_kinds/);
});

test('a retry files one copy, not two',()=>{
  // The mutation identifier is what makes the retry replay, and the server
  // keys the copy on it too.
  assert.match(service,/func recordCopy\([^)]*mutationID: UUID = UUID\(\)\)/s);
  assert.match(service,/payload: payload, mutationID: mutationID/);
  assert.match(migration,/UNIQUE\(obligation_id,mutation_id\)/);
});
