package com.riskdetectedan.core.designsystem.isg

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.io.File
import java.util.UUID

@RunWith(Parameterized::class)
class NovaCompanyListStateTest(private val name: String, private val test: JsonObject) {
    companion object {
        private val corpus = Json.parseToJsonElement(File("../../../contracts/isg/v1/fixtures/nova-company-list.json").readText()).jsonObject
        private val rows = corpus.getValue("rows").jsonObject
        private val responses = corpus.getValue("responses").jsonObject
        @JvmStatic @Parameterized.Parameters(name = "{0}") fun cases() = corpus.getValue("cases").jsonArray.map { arrayOf(it.jsonObject.getValue("id").jsonPrimitive.content, it.jsonObject) }
    }
    private fun actor(key: String): NovaSessionIdentity? = if (key == "out") null else NovaSessionIdentity(
        UUID.fromString(if (key == "b") "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" else "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
        UUID.fromString(if (key == "a") "aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa" else "bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb"))
    private fun row(raw: JsonObject) = NovaOwnedCompany(UUID.fromString(raw.getValue("id").jsonPrimitive.content),
        UUID.fromString(raw.getValue("ownerID").jsonPrimitive.content), raw.getValue("name").jsonPrimitive.content,
        raw.getValue("detail").jsonPrimitive.content, raw.getValue("isArchived").jsonPrimitive.boolean)

    @Test fun sharedScenario() {
        var host = NovaSessionHost(setOf(NovaDestination.companies))
        fun ready(next: NovaSessionIdentity?, enabled: Boolean = true) {
            host = host.adopt(next).beginAvailabilityRefresh()
            if (next != null) host = host.resolve(requireNotNull(host.pending), next.userID, if (enabled) setOf(NovaDestination.companies) else emptySet())
        }
        ready(actor("a"))
        var state = NovaCompanyListState()
        val tickets = mutableMapOf<String, NovaCompanyListTicket>()
        val captured = mutableMapOf<String, UUID>()
        var selected = false
        var archiveScope = false
        for (raw in test.getValue("steps").jsonArray) {
            val step = raw.jsonObject
            val key = step["key"]?.jsonPrimitive?.content.orEmpty()
            when (step.getValue("op").jsonPrimitive.content) {
                "begin" -> { archiveScope = step["archived"]?.jsonPrimitive?.boolean ?: false; state = state.begin(host, archiveScope); state.pending?.let { tickets[key] = it } }
                "filter" -> archiveScope = step.getValue("archived").jsonPrimitive.boolean
                "complete" -> {
                    val values = responses.getValue(step.getValue("rows").jsonPrimitive.content).jsonArray.map { row(if (it is JsonPrimitive) rows.getValue(it.content).jsonObject else it.jsonObject) }
                    state = state.complete(tickets.getValue(key), values, host)
                }
                "fail" -> state = state.fail(tickets.getValue(key), host)
                "cancel" -> state = state.cancel(tickets.getValue(key), host)
                "ready" -> ready(actor(step.getValue("actor").jsonPrimitive.content))
                "adopt" -> host = host.adopt(actor(step.getValue("actor").jsonPrimitive.content))
                "tokenRefresh" -> host = host.adopt(host.identity)
                "hostRefresh" -> host = host.beginAvailabilityRefresh()
                "revoke" -> ready(host.identity, false)
                "capture" -> state.content(host, archiveScope).requestID?.let { captured[key] = it }
                "select" -> selected = state.select(row(rows.getValue(step.getValue("row").jsonPrimitive.content).jsonObject).id, captured[key], host, archiveScope) != null
                else -> error("Unknown company fixture operation: $name")
            }
        }
        val expected = test.getValue("expected").jsonObject
        val actual = state.content(host, archiveScope)
        assertEquals(name, expected.getValue("phase").jsonPrimitive.content, actual.phase.name)
        assertEquals(name, expected.getValue("rows").jsonArray.map { row(rows.getValue(it.jsonPrimitive.content).jsonObject).id }, actual.rows.map { it.id })
        assertEquals(name, expected.getValue("pending").jsonPrimitive.boolean, state.pending != null)
        assertEquals(name, expected.getValue("selected").jsonPrimitive.boolean, selected)
    }
}
