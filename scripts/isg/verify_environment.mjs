#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { exactKeys, policy } from './lib.mjs';

const fields = ['schema_version', 'environment', 'project_id', 'supabase_url', 'database_host',
  'database_port', 'database_container', 'outbound_mode', 'data_class', 'store_mode', 'push_mode', 'email_mode', 'ai_mode'];

export function validateEnvironment(config, safety = policy) {
  const errors = [];
  if (!exactKeys(config, fields, errors)) return { ok: false, errors };
  if (config.schema_version !== 1) errors.push('SCHEMA_VERSION_UNSUPPORTED');
  // Network/staging/store lanes must not become enabled just by supplying a new URL.
  if (config.environment !== 'local') errors.push('ENVIRONMENT_NOT_ENABLED');
  if (typeof config.project_id !== 'string' || !/^isg_test_[a-z0-9_]{1,40}$/.test(config.project_id)) errors.push('PROJECT_SCOPE_INVALID');
  if (typeof config.project_id === 'string' && safety.production_project_refs.some(ref => config.project_id.includes(ref))) errors.push('PRODUCTION_PROJECT_FORBIDDEN');
  let url;
  try { url = new URL(config.supabase_url); } catch { errors.push('API_URL_INVALID'); }
  if (url) {
    if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' || !safety.local_api_ports.includes(Number(url.port)) ||
      url.username || url.password || url.search || url.hash || url.pathname !== '/' ||
      config.supabase_url !== `http://127.0.0.1:${url.port}`) errors.push('API_TARGET_NOT_APPROVED');
  }
  if (config.database_host !== '127.0.0.1' || !Number.isInteger(config.database_port) || !safety.local_database_ports.includes(config.database_port)) errors.push('DATABASE_TARGET_NOT_APPROVED');
  if (config.database_container !== `${config.project_id}_db`) errors.push('DATABASE_CONTAINER_SCOPE_INVALID');
  for (const [key, expected] of Object.entries({outbound_mode: 'disabled', data_class: 'synthetic', store_mode: 'mock', push_mode: 'sink', email_mode: 'sink', ai_mode: 'mock'})) {
    if (config[key] !== expected) errors.push(`${key.toUpperCase()}_NOT_SAFE`);
  }
  return { ok: errors.length === 0, errors: [...new Set(errors)] };
}

// A declaration is not evidence of Docker isolation. DB runners must call this too.
export function validateContainerInspection(info, config, networks = []) {
  const errors = [];
  if (!validateEnvironment(config).ok) return { ok: false, errors: ['ENVIRONMENT_INVALID'] };
  if (info?.Name !== `/${config.database_container}`) errors.push('CONTAINER_NAME_MISMATCH');
  if (info?.Config?.Labels?.['com.riskdetected.isg-test-project'] !== config.project_id) errors.push('CONTAINER_LABEL_MISMATCH');
  if (info?.State?.Running !== true) errors.push('CONTAINER_NOT_RUNNING');
  const mode = info?.HostConfig?.NetworkMode;
  const attached = Object.keys(info?.NetworkSettings?.Networks ?? {});
  const isolated = mode === 'none' ? attached.every(n => n === 'none') : attached.length > 0 &&
    attached.every(name => networks.some(n => n.Name === name && n.Internal === true && n.Labels?.['com.riskdetected.isg-test-project'] === config.project_id));
  if (!isolated || mode === 'host') errors.push('CONTAINER_EGRESS_NOT_ISOLATED');
  if (Object.values(info?.HostConfig?.PortBindings ?? {}).some(bindings => (bindings ?? []).some(b => b.HostIp !== '127.0.0.1' || !policy.local_database_ports.includes(Number(b.HostPort))))) errors.push('CONTAINER_PORT_NOT_APPROVED');
  if (info?.HostConfig?.Privileged || info?.HostConfig?.PidMode === 'host') errors.push('CONTAINER_PRIVILEGE_FORBIDDEN');
  // No user's host folders, Docker socket, or old stack volumes in a test database.
  if ((info?.Mounts ?? []).some(m => m.Type !== 'volume' || !m.Name?.startsWith(`${config.project_id}_`))) errors.push('CONTAINER_MOUNT_NOT_APPROVED');
  return { ok: errors.length === 0, errors };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const args = process.argv.slice(2);
    if (args.length !== 1) throw new Error('usage');
    const result = validateEnvironment(JSON.parse(readFileSync(args[0], 'utf8')));
    console.log(JSON.stringify({ ...result, check: 'declaration_only', network_or_database_contacted: false }, null, 2));
    process.exitCode = result.ok ? 0 : 1;
  } catch {
    console.error('ENVIRONMENT_FILE_INVALID: supply one JSON manifest; no environment fallback is allowed.');
    process.exitCode = 1;
  }
}
