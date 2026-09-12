package com.riskdetectedan.core.designsystem.isg

import java.util.UUID

/** Trusted Auth-owner input, never profile metadata or URL fields; contains no credentials. */
data class NovaSessionIdentity(val userID: UUID, val sessionID: UUID)
enum class NovaHostPhase { signedOut, resolving, ready, failed }

// Opaque tokens: only the host issues these; do not serialize them or log identity fields.
class NovaAvailabilityTicket internal constructor(internal val epoch: String, internal val identity: NovaSessionIdentity)
class NovaScopedValue<Value> internal constructor(internal val epoch: String, internal val value: Value)

/** Immutable presentation owner; assign results to the CURRENT UI state on the UI thread.
 * No Auth/billing/role inference, persistence, network or server authorization is provided.
 */
class NovaSessionHost private constructor(
    val identity: NovaSessionIdentity?,
    val phase: NovaHostPhase,
    val navigation: NovaNavigationState,
    val pending: NovaAvailabilityTicket?,
    private val implemented: Set<NovaDestination>,
) {
    constructor(implemented: Set<NovaDestination>) : this(null, NovaHostPhase.signedOut,
        NovaNavigationState(UUID.randomUUID().toString(), emptySet()), null, implemented.toSet())

    /** Same session / token refresh is a no-op, including during an in-flight request. */
    fun adopt(next: NovaSessionIdentity?): NovaSessionHost = if (identity == next) this else
        NovaSessionHost(next, if (next == null) NovaHostPhase.signedOut else NovaHostPhase.resolving,
            freshNavigation(), null, implemented)

    /** Revalidation and retries invalidate old content/callbacks even for the same session. */
    fun beginAvailabilityRefresh(): NovaSessionHost {
        val actor = identity ?: return this
        val next = freshNavigation()
        return NovaSessionHost(actor, NovaHostPhase.resolving, next, NovaAvailabilityTicket(next.epoch, actor), implemented)
    }

    fun resolve(ticket: NovaAvailabilityTicket, ownerID: UUID, enabled: Set<NovaDestination>): NovaSessionHost {
        if (!matches(ticket)) return this
        if (ownerID != identity?.userID) return NovaSessionHost(identity, NovaHostPhase.failed, navigation, null, implemented)
        return NovaSessionHost(identity, NovaHostPhase.ready,
            navigation.updateAvailability(enabled.intersect(implemented), navigation.epoch), null, implemented)
    }

    fun fail(ticket: NovaAvailabilityTicket): NovaSessionHost = if (!matches(ticket)) this else
        NovaSessionHost(identity, NovaHostPhase.failed, navigation, null, implemented)

    fun apply(event: NovaNavigationEvent, from: String): NovaSessionHost = if (!isCurrent(from)) this else
        NovaSessionHost(identity, phase, navigation.apply(event, from), pending, implemented)

    fun isCurrent(epoch: String) = phase == NovaHostPhase.ready && epoch == navigation.epoch

    // Same-epoch company/query/request races still require a feature-specific request guard.
    fun <Value> scope(value: Value, from: String): NovaScopedValue<Value>? =
        if (isCurrent(from)) NovaScopedValue(from, value) else null
    fun <Value> value(snapshot: NovaScopedValue<Value>?): Value? =
        if (snapshot != null && isCurrent(snapshot.epoch)) snapshot.value else null

    private fun matches(ticket: NovaAvailabilityTicket) = phase == NovaHostPhase.resolving && pending === ticket &&
        identity == ticket.identity && navigation.epoch == ticket.epoch
    private fun freshNavigation() = NovaNavigationState(UUID.randomUUID().toString(), emptySet())
}
