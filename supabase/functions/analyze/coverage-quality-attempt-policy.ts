export type CoverageQualityFallbackAttemptState = {
  enqueued: true;
  attempted: boolean;
  modelGenerationPassCount: number;
};

function boundedPassCount(value: unknown): number {
  return Math.max(1, Math.min(3, Math.round(Number(value)) || 1));
}

export function coverageQualityFallbackAttemptState(params: {
  queueReadCount: unknown;
  priorModelGenerationPassCount: unknown;
}): CoverageQualityFallbackAttemptState {
  const queueReadCount = Math.max(
    1,
    Math.round(Number(params.queueReadCount)) || 1,
  );
  const priorPassCount = boundedPassCount(
    params.priorModelGenerationPassCount,
  );
  const attempted = queueReadCount > 1;

  return {
    enqueued: true,
    attempted,
    modelGenerationPassCount: attempted
      ? Math.min(3, priorPassCount + 1)
      : priorPassCount,
  };
}
