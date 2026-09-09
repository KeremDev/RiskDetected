export type ProviderFailureShape = {
  schemaError: boolean;
  code: string;
};

/**
 * Safe local syntax repair and tolerant record-level salvage run first. If a
 * response is still unusable, one bounded technical retry is allowed with the
 * lower retry thinking budget. This is distinct from a new primary attempt.
 */
export function shouldRetrySameProvider(
  failure: ProviderFailureShape,
): boolean {
  if (
    failure.schemaError &&
    (
      failure.code.startsWith("provider_schema_invalid__") ||
      failure.code === "provider_schema_invalid" ||
      failure.code === "provider_json_invalid"
    )
  ) return true;
  return !failure.schemaError && [
    "provider_transport_error",
    "provider_timeout",
  ].includes(failure.code);
}

/**
 * A timeout is usually a slow request, not evidence that the provider cannot
 * satisfy the contract. Cross-provider fallback after waiting the full timeout
 * created the observed 55s Gemini + 65s Luna dead path. Reserve Luna for a
 * contract/provider incompatibility or an explicit availability response.
 */
export function shouldUseFallbackProvider(
  failure: ProviderFailureShape,
): boolean {
  return failure.schemaError || [
    "provider_transport_error",
    "provider_schema_invalid",
    "provider_json_invalid",
    "provider_output_missing",
    "provider_rate_limited",
    "provider_http_error",
  ].some((code) => failure.code.startsWith(code));
}

/**
 * Economy keeps the same Gemini model and may make one Standard-tier attempt
 * when Flex capacity/transport cannot complete. Schema/content failures do not
 * justify buying the same semantic response again.
 */
export function shouldUseEconomyStandardFallback(
  failure: ProviderFailureShape,
): boolean {
  return !failure.schemaError && [
    "provider_timeout",
    "provider_transport_error",
    "provider_rate_limited",
    "provider_unavailable",
  ].includes(failure.code);
}
