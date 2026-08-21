export type DispatchObservation =
  | "success_response"
  | "application_error"
  | "ambiguous_transport";

export type QueueReconciliationAction = "delete" | "keep" | "legacy";

export type QueueReconciliationDecision = {
  action: QueueReconciliationAction;
  reason: string;
};

export function forceCoverageQualityFallback(params: {
  repairKind: unknown;
  workerAttempt: number;
}): boolean {
  return params.repairKind === "coverage_quality_v2" &&
    Number.isFinite(params.workerAttempt) && params.workerAttempt > 1;
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
