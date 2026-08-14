export type PushResultLike = {
  status?: unknown;
  event_id?: unknown;
  retryable?: unknown;
  ambiguous?: unknown;
  reason?: unknown;
  error?: unknown;
};

export type JobCompletionDecision = {
  result: "sent" | "skipped" | "failed" | "ambiguous";
  retryable: boolean;
  eventID: string | null;
  errorCode: string | null;
};

export function notificationJobCompletionDecision(
  responseOK: boolean,
  payload: PushResultLike,
): JobCompletionDecision {
  const eventID = typeof payload.event_id === "string"
    ? payload.event_id
    : null;
  if (responseOK && payload.status === "sent") {
    return {
      result: "sent",
      retryable: false,
      eventID,
      errorCode: null,
    };
  }
  if (responseOK && payload.status === "skipped") {
    return {
      result: "skipped",
      retryable: false,
      eventID,
      errorCode: typeof payload.reason === "string"
        ? payload.reason
        : "push_skipped",
    };
  }
  if (
    (typeof payload.ambiguous === "number" && payload.ambiguous > 0) ||
    payload.error === "ambiguous_transport"
  ) {
    return {
      result: "ambiguous",
      retryable: false,
      eventID,
      errorCode: "ambiguous_transport",
    };
  }
  return {
    result: "failed",
    retryable: payload.retryable === true,
    eventID,
    errorCode: typeof payload.error === "string"
      ? payload.error
      : `push_http_${responseOK ? "200" : "error"}`,
  };
}

export function ambiguousNestedTransportDecision(): JobCompletionDecision {
  return {
    result: "ambiguous",
    retryable: false,
    eventID: null,
    errorCode: "nested_sender_transport_ambiguous",
  };
}
