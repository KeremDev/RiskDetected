export type DispatchObservation =
  | "success_response"
  | "application_error"
  | "ambiguous_transport";

export type QueueReconciliationAction = "delete" | "keep" | "legacy";

export type QueueReconciliationDecision = {
  action: QueueReconciliationAction;
  reason: string;
};

export function isProviderBackgroundPendingResponse(params: {
  httpStatus: number | null;
  responseBodyParsed: boolean;
  responseCode: string | null;
}): boolean {
  return params.httpStatus === 202 && params.responseBodyParsed &&
    params.responseCode === "provider_background_pending";
}

export function providerBackgroundRetrySeconds(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.max(5, Math.min(120, parsed)) : 15;
}

/**
 * A parsed vNext response with one of these codes proves that the nested
 * function finished and did not commit finalization. It is therefore not an
 * ambiguous transport loss: the worker may safely release the claim and
 * retry the checkpointed job without waiting for the full lease.
 */
export function isExplicitVNextFailure(params: {
  httpStatus: number | null;
  responseBodyParsed: boolean;
  responseCode: string | null;
}): boolean {
  if (
    !params.responseBodyParsed || params.httpStatus === null ||
    params.httpStatus < 500 || !params.responseCode
  ) return false;
  return /^(?:provider_|vnext_analysis_failed$|v4_analysis_failed$|photo_analysis_failed$)/
    .test(
      params.responseCode,
    );
}

export function forceCoverageQualityFallback(params: {
  repairKind: unknown;
  queueReadCount: number;
}): boolean {
  return params.repairKind === "coverage_quality_v2" &&
    Number.isFinite(params.queueReadCount) && params.queueReadCount > 1;
}

const TERMINAL_JOB_STATES = new Set(["completed", "failed", "superseded"]);

export function classifyDispatchObservation(params: {
  transportError: boolean;
  httpStatus: number | null;
  responseBodyParsed: boolean;
}): DispatchObservation {
  if (params.transportError || params.httpStatus === null) {
    return "ambiguous_transport";
  }
  if (
    !params.responseBodyParsed || params.httpStatus === 408 ||
    params.httpStatus >= 500
  ) {
    return "ambiguous_transport";
  }
  if (params.httpStatus >= 200 && params.httpStatus < 300) {
    return "success_response";
  }
  return "application_error";
}

export function reconcileQueueAfterDispatch(params: {
  claimGuardVersion: number;
  claimState: string | null;
  validationFailed: boolean;
}): QueueReconciliationDecision {
  if (params.claimGuardVersion !== 2) {
    return { action: "legacy", reason: "legacy_claim_guard" };
  }
  if (params.validationFailed) {
    return { action: "keep", reason: "claim_state_unavailable" };
  }
  const state = params.claimState ?? "unknown";
  if (TERMINAL_JOB_STATES.has(state)) {
    return { action: "delete", reason: state };
  }
  return { action: "keep", reason: state };
}

export async function reconcileWithAuthoritativeState(params: {
  claimGuardVersion: number;
  validateState: () => Promise<string>;
}): Promise<{
  decision: QueueReconciliationDecision;
  claimState: string | null;
  validationFailed: boolean;
}> {
  try {
    const claimState = await params.validateState();
    return {
      decision: reconcileQueueAfterDispatch({
        claimGuardVersion: params.claimGuardVersion,
        claimState,
        validationFailed: false,
      }),
      claimState,
      validationFailed: false,
    };
  } catch {
    return {
      decision: reconcileQueueAfterDispatch({
        claimGuardVersion: params.claimGuardVersion,
        claimState: null,
        validationFailed: true,
      }),
      claimState: null,
      validationFailed: true,
    };
  }
}
