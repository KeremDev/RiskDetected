// Parse before Docker, backup access, output writes, Keychain or remote action.
export function parseRestoreMode(args) {
  if (Array.isArray(args) && args.length === 2 && args[0] === '--synthetic-session' && args[1] === '--native-e2e') {
    return { storage:false, sessionGuard:true, synthetic:true, nativeE2E:true };
  }
  if (Array.isArray(args) && args.length === 2 && args[0] === '--isolated-copy' && args[1] === '--p05-upgrade') {
    return { storage:false, sessionGuard:false, synthetic:false, p05Upgrade:true };
  }
  if (Array.isArray(args) && args.length === 1 && args[0] === '--synthetic-session') {
    return { storage:false, sessionGuard:true, synthetic:true };
  }
  if (!Array.isArray(args) || args[0] !== '--isolated-copy' || args.length > 3 ||
      args.slice(1).some(a => !['--with-storage','--with-session-guard'].includes(a)) ||
      new Set(args).size !== args.length) throw new Error('AUTH_RESTORE_EXPLICIT_MODE_REQUIRED');
  return { storage: args.includes('--with-storage'), sessionGuard: args.includes('--with-session-guard'), synthetic:false };
}
