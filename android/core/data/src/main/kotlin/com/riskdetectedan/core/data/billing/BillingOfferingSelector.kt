package com.riskdetectedan.core.data.billing

/** Match iOS: an explicit offering is pinned, even when it is unavailable.
 * Falling back to current is allowed only when no identifier was configured.
 * This chooses a catalogue, never an entitlement or purchase authorization.
 */
internal fun <T> selectBillingOffering(
    configuredIdentifier: String,
    current: T?,
    findByIdentifier: (String) -> T?,
): T? {
    val identifier = configuredIdentifier.trim()
    return if (identifier.isEmpty()) current else findByIdentifier(identifier)
}
