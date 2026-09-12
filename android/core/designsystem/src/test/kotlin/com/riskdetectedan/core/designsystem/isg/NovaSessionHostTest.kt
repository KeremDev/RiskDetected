package com.riskdetectedan.core.designsystem.isg

import java.io.File
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

@RunWith(Parameterized::class)
class NovaSessionHostTest(private val id: String, private val fixture: JsonObject) {
    @Test fun sharedLifecycle() {
        var host = NovaSessionHost(destinations(fixture.getValue("implemented")))
        val tickets = mutableMapOf<String, NovaAvailabilityTicket>()
        val epochs = mutableMapOf<String, String>()
        var value: NovaScopedValue<String>? = null
        fixture.getValue("steps").jsonArray.forEachIndexed { index, raw ->
            val action = raw.jsonObject
            fun str(key: String) = action.getValue(key).jsonPrimitive.content
            val previousEpoch = host.navigation.epoch
            val from = action["from"]?.jsonPrimitive?.content?.let { epochs.getValue(it) } ?: previousEpoch
            host = when (str("op")) {
                "adopt" -> host.adopt(action["identity"]?.jsonPrimitive?.contentOrNull?.let { identities.getValue(it) })
                "request" -> host.beginAvailabilityRefresh().also {
                    it.pending?.let { ticket -> tickets[str("key")] = ticket }
                    epochs[str("key")] = it.navigation.epoch
                }
                "resolve" -> host.resolve(tickets.getValue(str("key")), identities.getValue(str("owner")).userID, destinations(action.getValue("enabled")))
                "fail" -> host.fail(tickets.getValue(str("key")))
                "navigate" -> host.apply(NovaNavigationEvent.Navigate(NovaDestination.valueOf(str("destination"))), from)
                "open" -> host.apply(NovaNavigationEvent.Open(NovaOverlay.valueOf(str("panel"))), from)
                "publish" -> host.also { it.scope(str("text"), from)?.let { next -> value = next } }
                else -> error("Unknown operation")
            }
            val actual = buildJsonObject {
                put("phase", host.phase.name); put("current", host.navigation.current.name)
                put("overlay", host.navigation.overlay?.name?.let(::JsonPrimitive) ?: JsonNull)
                put("available", JsonArray(host.navigation.available.map { it.name }.sorted().map(::JsonPrimitive)))
                put("pending", host.pending != null)
                put("value", host.value(value)?.let(::JsonPrimitive) ?: JsonNull)
                put("epochChanged", previousEpoch != host.navigation.epoch)
            }
            assertEquals("$id step $index", action.getValue("expected"), actual)
        }
    }

    companion object {
        private fun destinations(raw: JsonElement) = raw.jsonArray.map { NovaDestination.valueOf(it.jsonPrimitive.content) }.toSet()
        private val corpus: JsonObject by lazy {
            val file = generateSequence(File(requireNotNull(System.getProperty("user.dir")))) { it.parentFile }.take(6)
                .map { File(it, "contracts/isg/v1/fixtures/nova-session-host.json") }.first { it.isFile }
            Json.parseToJsonElement(file.readText()).jsonObject
        }
        private val identities by lazy { corpus.getValue("identities").jsonObject.mapValues { (_, raw) ->
            val item = raw.jsonObject
            NovaSessionIdentity(UUID.fromString(item.getValue("userID").jsonPrimitive.content), UUID.fromString(item.getValue("sessionID").jsonPrimitive.content))
        } }
        @JvmStatic @Parameterized.Parameters(name = "{0}") fun fixtures(): List<Array<Any>> =
            corpus.getValue("cases").jsonArray.map { arrayOf(it.jsonObject.getValue("id").jsonPrimitive.content, it.jsonObject) }
    }
}
