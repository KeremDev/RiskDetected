export type AnalysisEngineRoute = "legacy" | "vnext";
export type AnalysisEngineVariant = "vnext-v3" | "vnext-v4" | null;

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
