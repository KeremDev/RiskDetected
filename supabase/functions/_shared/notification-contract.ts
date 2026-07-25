export const MAX_PUSH_TITLE_LENGTH = 80;
export const MAX_PUSH_BODY_LENGTH = 240;
export const MAX_PUSH_DATA_BYTES = 2_500;
export const MAX_APNS_ATTEMPTS = 3;

export type NotificationPreferenceKey =
  | "analysis_complete"
  | "report_ready"
  | "account_updates"
  | "trial_reminder"
  | "progress_weekly_summary"
  | "progress_monthly_summary"
  | "progress_milestones"
  | "app_reminders";

export type NotificationSource =
  | "transactional"
  | "trial"
  | "progress"
  | "automation"
  | "manual";

export type NotificationDestination =
  | "home"
  | "history"
  | "new_analysis"
  | "profile"
  | "reports";

export type NotificationKindContract = {
  preferenceKey: NotificationPreferenceKey;
  requiresPreferenceRow: boolean;
  allowedDestinations: readonly NotificationDestination[];
  defaultSource: NotificationSource;
};

const KIND_CONTRACTS: Readonly<
  Record<string, NotificationKindContract>
> = Object.freeze({
  analysis_complete: {
    preferenceKey: "analysis_complete",
    requiresPreferenceRow: false,
    allowedDestinations: ["home", "history"],
    defaultSource: "transactional",
  },
  report_ready: {
    preferenceKey: "report_ready",
    requiresPreferenceRow: false,
    allowedDestinations: ["reports"],
    defaultSource: "transactional",
  },
  account_updates: {
    preferenceKey: "account_updates",
    requiresPreferenceRow: false,
    allowedDestinations: ["profile"],
    defaultSource: "transactional",
  },
  trial_reminder: {
    preferenceKey: "trial_reminder",
    requiresPreferenceRow: false,
    allowedDestinations: ["profile"],
    defaultSource: "trial",
  },
  progress_weekly_summary: {
    preferenceKey: "progress_weekly_summary",
    requiresPreferenceRow: false,
    allowedDestinations: ["profile"],
    defaultSource: "progress",
  },
  progress_monthly_summary: {
    preferenceKey: "progress_monthly_summary",
    requiresPreferenceRow: false,
    allowedDestinations: ["profile"],
    defaultSource: "progress",
  },
  progress_milestones: {
    preferenceKey: "progress_milestones",
    requiresPreferenceRow: false,
    allowedDestinations: ["profile"],
    defaultSource: "progress",
  },
  first_analysis_reminder: {
    preferenceKey: "app_reminders",
    requiresPreferenceRow: true,
    allowedDestinations: ["home", "new_analysis", "profile"],
    defaultSource: "automation",
  },
  inactivity_reminder: {
    preferenceKey: "app_reminders",
    requiresPreferenceRow: true,
    allowedDestinations: ["home", "new_analysis", "profile"],
    defaultSource: "automation",
  },
  manual_app_reminder: {
    preferenceKey: "app_reminders",
    requiresPreferenceRow: true,
    allowedDestinations: ["home", "new_analysis", "profile"],
    defaultSource: "manual",
  },
});

export function notificationKindContract(
  kind: unknown,
): NotificationKindContract | null {
  if (typeof kind !== "string") return null;
  return KIND_CONTRACTS[kind.trim()] ?? null;
}

export function notificationContentError(params: {
  title: unknown;
  body: unknown;
}): string | null {
  if (typeof params.title !== "string" || !params.title.trim()) {
    return "invalid_title";
  }
  if (typeof params.body !== "string" || !params.body.trim()) {
    return "invalid_body";
  }
  if (params.title.length > MAX_PUSH_TITLE_LENGTH) {
    return "title_too_long";
  }
  if (params.body.length > MAX_PUSH_BODY_LENGTH) {
    return "body_too_long";
  }
  return null;
}

const SENSITIVE_PUSH_DATA_KEYS = new Set([
  "api_key",
  "auth_token",
  "base64",
  "device_token",
  "email",
  "findings",
  "image",
  "image_data",
  "images",
  "phone",
  "photo_data",
  "prompt",
  "prompts",
  "raw_ai_response",
  "response_body",
]);

export function notificationPayloadError(data: unknown): string | null {
  if (
    typeof data !== "object" ||
    data === null ||
    Array.isArray(data)
  ) {
    return "data_must_be_object";
  }

  const encoded = new TextEncoder().encode(JSON.stringify(data));
  if (encoded.byteLength > MAX_PUSH_DATA_BYTES) {
    return "data_too_large";
  }

  const stack: unknown[] = [data];
  while (stack.length > 0) {
    const value = stack.pop();
    if (Array.isArray(value)) {
      stack.push(...value);
      continue;
    }
    if (typeof value !== "object" || value === null) continue;
    for (const [key, child] of Object.entries(value)) {
      if (SENSITIVE_PUSH_DATA_KEYS.has(key.trim().toLowerCase())) {
        return "sensitive_data_key_not_allowed";
      }
      stack.push(child);
    }
  }

  return null;
}

export function notificationDestinationError(params: {
  contract: NotificationKindContract;
  destination: unknown;
}): string | null {
  if (params.destination === undefined || params.destination === null) {
    return null;
  }
  if (typeof params.destination !== "string") {
    return "invalid_destination";
  }
  return params.contract.allowedDestinations.includes(
      params.destination as NotificationDestination,
    )
    ? null
    : "destination_not_allowed_for_kind";
}

export type APNsOutcome =
  | "accepted"
  | "transient"
  | "permanent"
  | "ambiguous";

export type APNsClassification = {
  outcome: APNsOutcome;
  retryable: boolean;
  disableToken: boolean;
  reason: string;
};

const PERMANENT_TOKEN_REASONS = new Set([
  "BadDeviceToken",
  "DeviceTokenNotForTopic",
  "Unregistered",
]);

export function parseAPNsReason(rawBody: string): string {
  try {
    const value = JSON.parse(rawBody) as { reason?: unknown };
    if (typeof value.reason === "string" && value.reason.trim()) {
      return value.reason.trim().slice(0, 120);
    }
  } catch {
    // APNs normally returns JSON. Keep a safe generic reason otherwise.
  }
  return "apns_error";
}

export function classifyAPNsResponse(
  status: number,
  rawBody = "",
): APNsClassification {
  if (status >= 200 && status < 300) {
    return {
      outcome: "accepted",
      retryable: false,
      disableToken: false,
      reason: "accepted",
    };
  }

  const reason = parseAPNsReason(rawBody);
  if (status === 410 || PERMANENT_TOKEN_REASONS.has(reason)) {
    return {
      outcome: "permanent",
      retryable: false,
      disableToken: true,
      reason,
    };
  }

  if (status === 429 || status >= 500) {
    return {
      outcome: "transient",
      retryable: true,
      disableToken: false,
      reason,
    };
  }

  return {
    outcome: "permanent",
    retryable: false,
    disableToken: false,
    reason,
  };
}

export function classifyAPNsTransportError(): APNsClassification {
  return {
    outcome: "ambiguous",
    retryable: false,
    disableToken: false,
    reason: "ambiguous_transport",
  };
}
