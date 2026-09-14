export function assertUnchangedSources(before, after) {
  const keys = Object.keys(before);
  if (!keys.length || keys.length !== Object.keys(after).length || keys.some(key => before[key] !== after[key])) {
    throw new Error('AUTH_RESTORE_SOURCE_CHANGED_DURING_RUN');
  }
}

export function appendPassingCheck(checks, id, condition) {
  if (checks.some(check => check.id === id)) throw new Error('AUTH_RESTORE_DUPLICATE_CHECK_ID');
  if (!condition) throw new Error(`AUTH_RESTORE_CHECK_FAILED_${id}`);
  checks.push({ id, result: 'PASS' });
}
