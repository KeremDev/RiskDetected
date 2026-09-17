package com.riskdetectedan.core.designsystem.isg

import java.util.UUID

/** Trusted Auth-owner input, never profile metadata or URL fields; contains no credentials. */
data class NovaSessionIdentity(val userID: UUID, val sessionID: UUID)
data class NovaWorkspaceSelection(
    val workspaceID: UUID,
    val membershipID: UUID,
    val userID: UUID,
    val kind: String,
    val permissionRevision: Long,
    val workspaceVersion: Long,
    val canRead: Boolean,
    val canOperate: Boolean,
) {
    val isStructurallyValid: Boolean get() = kind in setOf("personal", "osgb") &&
        permissionRevision in 0..9007199254740991L && workspaceVersion in 0..9007199254740991L
}
enum class NovaHostPhase { signedOut, resolving, ready, failed }

// Opaque tokens: only the host issues these; do not serialize them or log identity fields.
class NovaAvailabilityTicket internal constructor(internal val epoch: String, internal val identity: NovaSessionIdentity,
    internal val workspace: NovaWorkspaceSelection?)
class NovaScopedValue<Value> internal constructor(internal val epoch: String, internal val value: Value)

/** Immutable presentation owner; assign results to the CURRENT UI state on the UI thread.
 * No Auth/billing/role inference, persistence, network or server authorization is provided.
 */
class NovaSessionHost private constructor(
    val identity: NovaSessionIdentity?,
    val workspace: NovaWorkspaceSelection?,
    val phase: NovaHostPhase,
    val navigation: NovaNavigationState,
    val pending: NovaAvailabilityTicket?,
    private val implemented: Set<NovaDestination>,
) {
    constructor(implemented: Set<NovaDestination>) : this(null, null, NovaHostPhase.signedOut,
        NovaNavigationState(UUID.randomUUID().toString(), emptySet()), null, implemented.toSet())

    /** Same session / token refresh is a no-op, including during an in-flight request. */
    fun adopt(next: NovaSessionIdentity?): NovaSessionHost = if (identity == next) this else
        NovaSessionHost(next, null, if (next == null) NovaHostPhase.signedOut else NovaHostPhase.resolving,
            freshNavigation(), null, implemented)

    /** Revalidation and retries invalidate old content/callbacks even for the same session. */
    fun beginAvailabilityRefresh(): NovaSessionHost {
        val actor = identity ?: return this
        val next = freshNavigation()
        return NovaSessionHost(actor, workspace, NovaHostPhase.resolving, next,
            NovaAvailabilityTicket(next.epoch, actor, workspace), implemented)
    }

    /** Workspace selection is a cache boundary and still requires server availability resolution. */
    fun beginWorkspaceSwitch(nextWorkspace: NovaWorkspaceSelection): NovaSessionHost {
        val actor = identity ?: return this
        if (!nextWorkspace.isStructurallyValid || !nextWorkspace.canRead || nextWorkspace.userID != actor.userID ||
            workspace == nextWorkspace) return this
        val next = freshNavigation()
        return NovaSessionHost(actor, nextWorkspace, NovaHostPhase.resolving, next,
            NovaAvailabilityTicket(next.epoch, actor, nextWorkspace), implemented)
    }

    fun resolve(ticket: NovaAvailabilityTicket, ownerID: UUID, enabled: Set<NovaDestination>): NovaSessionHost {
        if (!matches(ticket)) return this
        if (ownerID != identity?.userID) return NovaSessionHost(identity, workspace, NovaHostPhase.failed, navigation, null, implemented)
        return NovaSessionHost(identity, workspace, NovaHostPhase.ready,
            navigation.updateAvailability(enabled.intersect(implemented), navigation.epoch), null, implemented)
    }

    fun fail(ticket: NovaAvailabilityTicket): NovaSessionHost = if (!matches(ticket)) this else
        NovaSessionHost(identity, workspace, NovaHostPhase.failed, navigation, null, implemented)

    fun apply(event: NovaNavigationEvent, from: String): NovaSessionHost = if (!isCurrent(from)) this else
        NovaSessionHost(identity, workspace, phase, navigation.apply(event, from), pending, implemented)

    fun isCurrent(epoch: String) = phase == NovaHostPhase.ready && epoch == navigation.epoch
    fun isCurrent(epoch: String, workspaceID: UUID, permissionRevision: Long) = isCurrent(epoch) &&
        workspace?.workspaceID == workspaceID && workspace.permissionRevision == permissionRevision

    // Same-epoch company/query/request races still require a feature-specific request guard.
    fun <Value> scope(value: Value, from: String): NovaScopedValue<Value>? =
        if (isCurrent(from)) NovaScopedValue(from, value) else null
    fun <Value> value(snapshot: NovaScopedValue<Value>?): Value? =
        if (snapshot != null && isCurrent(snapshot.epoch)) snapshot.value else null

    private fun matches(ticket: NovaAvailabilityTicket) = phase == NovaHostPhase.resolving && pending === ticket &&
        identity == ticket.identity && workspace == ticket.workspace && navigation.epoch == ticket.epoch
    private fun freshNavigation() = NovaNavigationState(UUID.randomUUID().toString(), emptySet())
}
