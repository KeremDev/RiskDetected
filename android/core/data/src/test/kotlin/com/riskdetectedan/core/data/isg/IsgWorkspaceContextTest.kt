package com.riskdetectedan.core.data.isg

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

@RunWith(Parameterized::class)
class IsgWorkspaceContextTest(private val id: String, private val valid: Boolean, private val input: JsonElement) {
    @Test fun `workspace context matches the shared transport corpus`() {
        assertEquals(id, valid, IsgWorkspaceContext.parse(input) != null)
    }

    companion object {
        @JvmStatic @Parameterized.Parameters(name = "{0}")
        fun fixtures(): List<Array<Any>> {
            val fixture = generateSequence(File(requireNotNull(System.getProperty("user.dir")))) { it.parentFile }.take(7)
                .map { File(it, "contracts/isg/v2/fixtures/workspace-context.json") }.first { it.isFile }
            return Json.parseToJsonElement(fixture.readText()).jsonObject.getValue("cases").jsonArray.map { element ->
                val item = element.jsonObject
                arrayOf(item.getValue("id").jsonPrimitive.content, item.getValue("valid").jsonPrimitive.boolean, item.getValue("input"))
            }
        }
    }
}
