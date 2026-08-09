export const ANDROID_RUNTIME_GATE_SCHEMA_VERSION = 1;

export const ANDROID_RUNTIME_GATE_KEYS = {
  client: "android_client_enabled",
  auth: "android_auth_enabled",
  analysis_submit: "android_analysis_submit_enabled",
  payments: "android_payments_enabled",
  notifications: "android_notifications_enabled",
  pdf_reports: "android_pdf_reports_enabled",
} as const;

export type AndroidRuntimeGateName = keyof typeof ANDROID_RUNTIME_GATE_KEYS;

export type AndroidRuntimeGateDecision = {
  enabled: boolean;
  reason: string;
};

export type AndroidRuntimeGates = {
  schema_version: number;
  evaluated_version_code: number | null;
} & Record<AndroidRuntimeGateName, AndroidRuntimeGateDecision>;

function positiveInt(value: unknown): number | null {
  const parsed = Math.round(Number(value));
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function versionCodes(value: unknown): number[] {
  if (!Array.isArray(value)) return [];
  return value.map(positiveInt).filter((item): item is number => item != null);
}

export function evaluateAndroidRuntimeGate(
  raw: unknown,
  versionCode: number | null,
): AndroidRuntimeGateDecision {
  if (versionCode == null) {
    return { enabled: false, reason: "invalid_version_code" };
  }
  if (!raw || typeof raw !== "object") {
    return { enabled: false, reason: "missing_flag" };
  }

  const value = raw as Record<string, unknown>;
  if (value.kill_switch !== false) {
    return { enabled: false, reason: "kill_switch" };
  }

  const mode = typeof value.rollout_mode === "string"
    ? value.rollout_mode.trim().toLowerCase()
    : "off";
  const allowlist = versionCodes(value.enabled_android_version_codes);
  const minimum = positiveInt(value.min_android_version_code);

  if (mode === "all" || mode === "on") {
    if (minimum != null && versionCode < minimum) {
      return { enabled: false, reason: "below_minimum_version" };
    }
    return { enabled: true, reason: "all" };
  }
  if (
    mode === "version_allowlist" || mode === "build_allowlist" ||
    mode === "allowlist"
  ) {
    return allowlist.includes(versionCode)
      ? { enabled: true, reason: "version_allowlist" }
      : { enabled: false, reason: "version_not_allowed" };
  }
  if (mode === "min_version" || mode === "min_build") {
    return minimum != null && versionCode >= minimum
      ? { enabled: true, reason: "minimum_version" }
      : {
        enabled: false,
        reason: minimum == null
          ? "missing_minimum_version"
          : "below_minimum_version",
      };
  }
  return { enabled: false, reason: "rollout_off" };
}

function disabledGates(
  versionCode: number | null,
  reason: string,
): AndroidRuntimeGates {
  const disabled = { enabled: false, reason };
  return {
    schema_version: ANDROID_RUNTIME_GATE_SCHEMA_VERSION,
    evaluated_version_code: versionCode,
    client: disabled,
    auth: disabled,
    analysis_submit: disabled,
    payments: disabled,
    notifications: disabled,
    pdf_reports: disabled,
  };
}

export function evaluateAndroidRuntimeGates(
  values: Partial<Record<AndroidRuntimeGateName, unknown>>,
  versionCode: number | null,
): AndroidRuntimeGates {
  const names = Object.keys(
    ANDROID_RUNTIME_GATE_KEYS,
  ) as AndroidRuntimeGateName[];
  const evaluated = Object.fromEntries(names.map((name) => [
    name,
    evaluateAndroidRuntimeGate(values[name], versionCode),
  ])) as Record<AndroidRuntimeGateName, AndroidRuntimeGateDecision>;

  if (!evaluated.client.enabled) {
    for (const name of names) {
      if (name !== "client") {
        evaluated[name] = { enabled: false, reason: "client_disabled" };
      }
    }
  }

  return {
    schema_version: ANDROID_RUNTIME_GATE_SCHEMA_VERSION,
    evaluated_version_code: versionCode,
    ...evaluated,
  };
}

// deno-lint-ignore no-explicit-any
export async function readAndroidRuntimeGates(
  supabase: any | null,
  platform: string,
  versionCode: number | null,
): Promise<AndroidRuntimeGates | undefined> {
  if (platform !== "android") return undefined;
  if (!supabase) return disabledGates(versionCode, "configuration_unavailable");

  const names = Object.keys(
    ANDROID_RUNTIME_GATE_KEYS,
  ) as AndroidRuntimeGateName[];
  const keys = Object.values(ANDROID_RUNTIME_GATE_KEYS);
  const { data, error } = await supabase
    .from("app_feature_flags")
    .select("key,value")
    .in("key", keys);
  if (error || !Array.isArray(data)) {
    return disabledGates(versionCode, "flag_read_failed");
  }

  const rows = new Map<string, unknown>(
    data.map((row: Record<string, unknown>) => [String(row.key), row.value]),
  );
  return evaluateAndroidRuntimeGates(
    Object.fromEntries(
      names.map((name) => [name, rows.get(ANDROID_RUNTIME_GATE_KEYS[name])]),
    ),
    versionCode,
  );
}
