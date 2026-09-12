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
