// Parsing must finish before any Docker, filesystem, Keychain or remote action.
export function parseRestoreMode(args) {
  if (!Array.isArray(args) || args[0] !== '--isolated-copy' || args.length > 3 ||
      args.slice(1).some(a => !['--with-storage','--with-session-guard'].includes(a)) ||
      new Set(args).size !== args.length) throw new Error('AUTH_RESTORE_EXPLICIT_MODE_REQUIRED');
  return { storage: args.includes('--with-storage'), sessionGuard: args.includes('--with-session-guard') };
}
