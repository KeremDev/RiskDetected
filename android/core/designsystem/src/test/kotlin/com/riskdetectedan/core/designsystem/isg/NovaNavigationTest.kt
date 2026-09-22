package com.riskdetectedan.core.designsystem.isg

import java.io.File
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

@RunWith(Parameterized::class)
class NovaNavigationTest(private val id: String, private val fixture: JsonObject) {
    @Test fun sameStateTransitionsAsSwift() {
        var state = NovaNavigationState("account-a", values(fixture.getValue("available")))
        fixture.getValue("steps").jsonArray.forEachIndexed { index, element ->
            val action = element.jsonObject
            val from = action.getValue("from").jsonPrimitive.content
            val arg = action["arg"]
            state = when (action.getValue("op").jsonPrimitive.content) {
                "select" -> state.apply(NovaNavigationEvent.Select(NovaTab.valueOf(arg!!.jsonPrimitive.content)), from)
                "open" -> state.apply(NovaNavigationEvent.Open(NovaOverlay.valueOf(arg!!.jsonPrimitive.content)), from)
                "navigate" -> state.apply(NovaNavigationEvent.Navigate(NovaDestination.valueOf(arg!!.jsonPrimitive.content)), from)
                "back" -> state.apply(NovaNavigationEvent.Back, from)
                "dismiss" -> state.apply(NovaNavigationEvent.Dismiss, from)
                "availability" -> state.updateAvailability(values(arg!!), from)
                "reset" -> state.resetAccount(arg!!.jsonObject.getValue("epoch").jsonPrimitive.content, values(arg.jsonObject.getValue("available")))
                "path" -> state.acceptBackPath(arg!!.jsonObject.getValue("path").jsonArray.map { NovaDestination.valueOf(it.jsonPrimitive.content) }, NovaTab.valueOf(arg.jsonObject.getValue("tab").jsonPrimitive.content), from)
                else -> error("Unknown fixture operation")
            }
            val actual = buildJsonObject {
                put("epoch", state.epoch); put("selected", state.selected.name)
                put("overlay", state.overlay?.let { JsonPrimitive(it.name) } ?: JsonNull)
                put("current", state.current.name); put("canGoBack", state.canGoBack)
                putJsonObject("paths") { NovaTab.entries.forEach { tab -> putJsonArray(tab.name) { state.paths.getValue(tab).forEach { add(it.name) } } } }
            }
            assertEquals("$id step $index", action.getValue("expected"), actual)
            assertTrue("Current destination must remain available", state.canOpen(state.current))
        }
    }

    companion object {
        private fun values(raw: JsonElement) = raw.jsonArray.map { NovaDestination.valueOf(it.jsonPrimitive.content) }.toSet()
        private fun read(relative: String): JsonObject {
            val file = generateSequence(File(requireNotNull(System.getProperty("user.dir")))) { it.parentFile }.take(6)
                .map { File(it, "contracts/isg/v1/$relative") }.first { it.isFile }
            return Json.parseToJsonElement(file.readText()).jsonObject
        }
        @JvmStatic @Parameterized.Parameters(name = "{0}") fun fixtures(): List<Array<Any>> {
            val catalog = read("design/nova-navigation.json")
            val destinations = catalog.getValue("destinations").jsonArray.map { it.jsonObject }
            assertEquals(destinations.map { it.getValue("id").jsonPrimitive.content }, NovaDestination.entries.map { it.name })
            destinations.forEach { item ->
                val d = NovaDestination.valueOf(item.getValue("id").jsonPrimitive.content)
                assertEquals(item.getValue("title").jsonPrimitive.content, d.title)
                assertEquals(item.getValue("tab").jsonPrimitive.content, d.tab.name)
                // Android resolves the same SF Symbol names through NovaSymbols.
                assertEquals(item.getValue("iosSymbol").jsonPrimitive.content, d.symbol)
            }
            assertEquals(catalog.getValue("tabs").jsonArray.map { it.jsonObject.getValue("id").jsonPrimitive.content to it.jsonObject.getValue("title").jsonPrimitive.content }, NovaTab.entries.map { it.name to it.title })
            assertEquals(catalog.getValue("drawer").jsonArray.map { it.jsonPrimitive.content }, NovaDestination.drawer.map { it.name })
            assertEquals(catalog.getValue("quickAdd").jsonArray.map { it.jsonPrimitive.content }, NovaDestination.quickAdd.map { it.name })
            return read("fixtures/nova-navigation.json").getValue("cases").jsonArray.map { arrayOf(it.jsonObject.getValue("id").jsonPrimitive.content, it.jsonObject) }
        }
    }
}
