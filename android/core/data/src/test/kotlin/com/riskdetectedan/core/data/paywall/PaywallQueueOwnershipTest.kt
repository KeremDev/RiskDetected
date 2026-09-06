package com.riskdetectedan.core.data.paywall

import org.junit.Assert.*
import org.junit.Test

class PaywallQueueOwnershipTest {
    private data class Event(val id: String, val user: String)
    private val queue = listOf(Event("a1", "A"), Event("b1", "B"), Event("a2", "A"), Event("b2", "B"))

    @Test fun `old account at head does not block current account`() {
        assertEquals("b1", nextPaywallEventForUser(queue, "B") { it.user }?.id)
        assertEquals("a1", nextPaywallEventForUser(queue, "A") { it.user }?.id)
        assertEquals(4, queue.size)
    }

    @Test fun `logout and unknown account do not upload or spin on retained events`() {
        for (user in listOf(null, "", "C")) {
            assertNull(nextPaywallEventForUser(queue, user) { it.user })
        }
    }

    @Test fun `acknowledgement and retry preserve ownership and per account order`() {
        val first = nextPaywallEventForUser(queue, "B") { it.user }!!
        assertEquals(first, nextPaywallEventForUser(queue, "B") { it.user })
        val remaining = queue.filterNot { it.id == first.id }
        assertEquals("b2", nextPaywallEventForUser(remaining, "B") { it.user }?.id)
        assertEquals(listOf("a1", "a2"), remaining.filter { it.user == "A" }.map { it.id })
        assertNull(nextPaywallEventForUser(remaining.filterNot { it.user == "B" }, "B") { it.user })
    }
}
