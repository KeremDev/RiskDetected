import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export const ROOT = resolve(import.meta.dirname, '../..');
export const policy = JSON.parse(readFileSync(resolve(ROOT, 'contracts/isg/v1/safety-policy.json'), 'utf8'));

export function isRecord(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

// Diagnostics only contain fixed codes and field names, never supplied values.
export function exactKeys(value, allowed, errors, prefix = '') {
  if (!isRecord(value)) {
    errors.push(`${prefix}OBJECT_REQUIRED`);
    return false;
  }
  if (Object.keys(value).some(key => !allowed.includes(key))) errors.push(`${prefix}UNKNOWN_FIELD`);
  return true;
}

export function parseCSV(text) {
  const rows = []; let row = []; let cell = ''; let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { cell += '"'; i++; }
      else if (c === '"') quoted = false;
      else cell += c;
    } else if (c === '"' && cell === '') quoted = true;
    else if (c === ',') { row.push(cell); cell = ''; }
    else if (c === '\n') { row.push(cell.replace(/\r$/, '')); rows.push(row); row = []; cell = ''; }
    else cell += c;
  }
  if (quoted) throw new Error('CSV_UNCLOSED_QUOTE');
  if (cell || row.length) { row.push(cell); rows.push(row); }
  return rows;
}
