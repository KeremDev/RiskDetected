#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { ROOT, policy } from './lib.mjs';

export function verifyIdentity(root = ROOT) {
  const project = readFileSync(resolve(root, 'RiskDetected.xcodeproj/project.pbxproj'), 'utf8');
  const android = readFileSync(resolve(root, 'android/app/build.gradle.kts'), 'utf8');
  const config = readFileSync(resolve(root, 'App/Services/RDConfig.swift'), 'utf8');
  return verifyIdentitySources({ project, android, config });
}

export function verifyIdentitySources({ project, android, config }) {
  const errors = [];
  const bundles = [...project.matchAll(/PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/g)].map(m => m[1].replaceAll('"', ''));
  // Test targets are allowed but the production app must occur in both build configs.
  const appBundles = bundles.filter(id => !/Tests|UITests|Snapshots/.test(id));
  if (appBundles.length < 2 || appBundles.some(id => id !== policy.ios_bundle_id)) errors.push('IOS_BUNDLE_DRIFT');
  if (android.match(/\bapplicationId\s*=\s*"([^"]+)"/)?.[1] !== policy.android_application_id) errors.push('ANDROID_APPLICATION_ID_DRIFT');
  if (android.match(/\bnamespace\s*=\s*"([^"]+)"/)?.[1] !== policy.android_namespace) errors.push('ANDROID_NAMESPACE_DRIFT');
  if (config.match(/static let redirectURL = URL\(string: "([^"]+)"/)?.[1] !== policy.auth_redirect_url) errors.push('AUTH_CALLBACK_DRIFT');
  for (const id of policy.entitlements) if (!config.includes(`static let ${id}EntitlementID = "${id}"`)) errors.push('ENTITLEMENT_DRIFT');
  return { ok: errors.length === 0, errors, checked: ['ios_bundle', 'android_application_id', 'android_namespace', 'auth_callback', 'entitlements'], limitation: 'Source assertion; signed binary, store record and keychain continuity require separate release evidence.' };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { const result = verifyIdentity(); console.log(JSON.stringify(result, null, 2)); process.exitCode = result.ok ? 0 : 1; }
  catch { console.error('IDENTITY_SOURCE_UNREADABLE'); process.exitCode = 1; }
}
