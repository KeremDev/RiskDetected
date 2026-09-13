// Pure Docker inspection predicate. Call before every DB/API operation and
// before deleting a disposable target; do not trust only NetworkMode='none'.
export function assertNoExposedRestoreContainer(i) {
  const record = v => v !== null && typeof v === 'object' && !Array.isArray(v);
  if (!i || i.HostConfig?.Privileged !== false || i.HostConfig?.PidMode === 'host' ||
      !Array.isArray(i.Mounts) || i.Mounts.length || !i.NetworkSettings ||
      !record(i.HostConfig.PortBindings) || !record(i.NetworkSettings.Ports) || !record(i.NetworkSettings.Networks) ||
      Object.values(i.NetworkSettings.Ports ?? {}).some(v => v?.length) ||
      Object.keys(i.HostConfig.PortBindings ?? {}).length ||
      Object.entries(i.NetworkSettings.Networks ?? {}).some(([name, network]) =>
        name !== 'none' || !record(network) || network.IPAddress !== '' || network.GlobalIPv6Address !== '')) {
    throw new Error('AUTH_RESTORE_ISOLATION_FAILED');
  }
}

// Docker's classic and containerd image stores may expose config or index IDs.
// Resolve the installed image ID from the approved immutable RepoDigest first;
// a container must match that ID, not assume its ID equals the registry digest.
export function resolvePinnedRestoreImage(info, reference) {
  if (!/^public\.ecr\.aws\/supabase\/(postgres|gotrue|storage-api|postgrest)@sha256:[a-f0-9]{64}$/.test(reference) ||
      !info || !/^sha256:[a-f0-9]{64}$/.test(info.Id ?? '') || !Array.isArray(info.RepoDigests) ||
      !info.RepoDigests.includes(reference) || info.Os !== 'linux' || !['arm64','amd64'].includes(info.Architecture)) {
    throw new Error('AUTH_RESTORE_PINNED_IMAGE_INVALID');
  }
  return { id:info.Id, architecture:info.Architecture, os:info.Os, reference };
}
