package com.riskdetectedan.core.designsystem.isg

import java.util.UUID

/** Service-authorized display data; defensive ownership checks are not backend authorization. */
data class NovaOwnedCompany(val id: UUID, val ownerID: UUID, val name: String, val detail: String, val isArchived: Boolean)
enum class NovaCompanyListPhase { idle, loading, loaded, failed }
data class NovaCompanyListContent(val phase: NovaCompanyListPhase, val requestID: UUID?, val rows: List<NovaOwnedCompany>, val includeArchived: Boolean = false) {
    companion object { val Idle = NovaCompanyListContent(NovaCompanyListPhase.idle, null, emptyList()) }
}
class NovaCompanyListTicket internal constructor(internal val id: UUID, internal val epoch: String,
    internal val ownerID: UUID, internal val includeArchived: Boolean)

/** Immutable, UI-thread-owned state. Supply the current host after suspension and at render. */
class NovaCompanyListState private constructor(val pending: NovaCompanyListTicket?, private val snapshot: NovaScopedValue<NovaCompanyListContent>?) {
    constructor() : this(null, null)

    fun begin(host: NovaSessionHost, includeArchived: Boolean = false): NovaCompanyListState {
        val owner = host.identity?.userID
        if (!allowed(host) || owner == null) return NovaCompanyListState()
        val ticket = NovaCompanyListTicket(UUID.randomUUID(), host.navigation.epoch, owner, includeArchived)
        return NovaCompanyListState(ticket, host.scope(NovaCompanyListContent(NovaCompanyListPhase.loading, ticket.id, emptyList(), ticket.includeArchived), ticket.epoch))
    }

    fun complete(ticket: NovaCompanyListTicket, rows: List<NovaOwnedCompany>, host: NovaSessionHost): NovaCompanyListState {
        if (!matches(ticket, host)) return this
        val valid = rows.map { it.id }.toSet().size == rows.size && rows.all { it.ownerID == ticket.ownerID && it.name.isNotBlank() }
        val content = NovaCompanyListContent(if (valid) NovaCompanyListPhase.loaded else NovaCompanyListPhase.failed,
            ticket.id, if (valid) rows.filter { ticket.includeArchived || !it.isArchived }.toList() else emptyList(), ticket.includeArchived)
        return NovaCompanyListState(null, host.scope(content, ticket.epoch))
    }

    fun fail(ticket: NovaCompanyListTicket, host: NovaSessionHost): NovaCompanyListState = if (!matches(ticket, host)) this else
        NovaCompanyListState(null, host.scope(NovaCompanyListContent(NovaCompanyListPhase.failed, ticket.id, emptyList(), ticket.includeArchived), ticket.epoch))

    fun cancel(ticket: NovaCompanyListTicket, host: NovaSessionHost): NovaCompanyListState =
        if (matches(ticket, host)) NovaCompanyListState() else this

    fun content(host: NovaSessionHost, includeArchived: Boolean = false): NovaCompanyListContent =
        if (allowed(host)) host.value(snapshot)?.takeIf { it.includeArchived == includeArchived } ?: NovaCompanyListContent.Idle else NovaCompanyListContent.Idle

    fun select(id: UUID, requestID: UUID?, host: NovaSessionHost, includeArchived: Boolean = false): NovaOwnedCompany? {
        val current = content(host, includeArchived)
        if (current.phase != NovaCompanyListPhase.loaded || requestID == null || current.requestID != requestID) return null
        return current.rows.firstOrNull { it.id == id }
    }

    private fun allowed(host: NovaSessionHost) = host.phase == NovaHostPhase.ready && NovaDestination.companies in host.navigation.available
    private fun matches(ticket: NovaCompanyListTicket, host: NovaSessionHost) = pending === ticket && allowed(host) &&
        host.isCurrent(ticket.epoch) && host.identity?.userID == ticket.ownerID
}
