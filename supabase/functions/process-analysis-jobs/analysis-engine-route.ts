export type AnalysisEngineRoute = "legacy" | "vnext";
export type AnalysisEngineVariant = "vnext-v3" | "vnext-v4" | null;

/**
 * iOS 2.0.0 and newer are fail-closed V4 clients. The value is read only from
 * the server-normalized queue snapshot written by analyze/index.ts; raw
 * client request fields are overwritten before enqueueing.
 */
export function requiresV4ForIOSRelease(clientRouting: unknown): boolean {
  if (!clientRouting || typeof clientRouting !== "object") return false;
  const routing = clientRouting as Record<string, unknown>;
  if (
    routing.source !== "trusted_analyze_enqueue" ||
    routing.client_platform !== "ios" ||
    routing.safety_claim_v4_scoreless !== true
  ) return false;
  const apiContract = Number(routing.api_contract_version);
  const build = Number.parseInt(String(routing.client_app_build ?? ""), 10);
  return Number.isFinite(apiContract) && apiContract >= 3 &&
    Number.isFinite(build) && build >= 87;
}

export function analysisFunctionForJob(params: {
  pipelineV2: boolean;
  repairJob: boolean;
  resolvedEngine: AnalysisEngineRoute | null;
  resolvedVariant?: AnalysisEngineVariant;
}): "analyze" | "analyze-vnext" | "analyze-v4" {
  if (
    params.pipelineV2 && !params.repairJob &&
    params.resolvedEngine === "vnext" &&
    params.resolvedVariant === "vnext-v4"
  ) return "analyze-v4";
  if (
    params.pipelineV2 && !params.repairJob && params.resolvedEngine === "vnext"
  ) return "analyze-vnext";
  return "analyze";
}
