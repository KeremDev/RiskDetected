package com.riskdetectedan.core.designsystem.isg

import java.io.File
import kotlinx.serialization.json.*
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

@RunWith(Parameterized::class)
class NovaTokenTest(private val group: String, private val name: String, private val expected: JsonElement) {
    @Test fun matchesPinnedExpertReference() {
        when (group) {
            "light", "dark" -> {
                val c = NovaColorToken.valueOf(name).rgba(group == "dark")
                assertEquals(expected.jsonArray.map { it.jsonPrimitive.double },
                    listOf(c.red.toDouble(), c.green.toDouble(), c.blue.toDouble(), c.alpha))
            }
            "dimensions" -> assertEquals(expected.jsonPrimitive.double, NovaDimensionToken.valueOf(name).value, 0.0)
            "typography" -> {
                val s = NovaTypeToken.valueOf(name).spec
                val e = expected.jsonObject
                assertEquals(e.getValue("fontName").jsonPrimitive.content, s.fontName)
                assertEquals(e.getValue("weight").jsonPrimitive.int, s.weight)
                assertEquals(e.getValue("size").jsonPrimitive.double, s.size, 0.0)
                assertEquals(e.getValue("tracking").jsonPrimitive.double, s.tracking, 0.0)
                assertEquals(e.getValue("lineHeight").jsonPrimitive.double, s.lineHeight, 0.0)
            }
            else -> error("Unknown fixture group")
        }
    }
    companion object {
        @JvmStatic @Parameterized.Parameters(name = "{0}:{1}") fun fixtures(): List<Array<Any>> {
            val fixture = generateSequence(File(requireNotNull(System.getProperty("user.dir")))) { it.parentFile }.take(6)
                .map { File(it, "contracts/isg/v1/design/nova-native-values.json") }.first { it.isFile }
            val root = Json.parseToJsonElement(fixture.readText()).jsonObject
            assertEquals(setOf("light", "dark", "typography", "dimensions"), root.keys)
            assertEquals(NovaColorToken.entries.map { it.name }.toSet(), root.getValue("light").jsonObject.keys)
            assertEquals(NovaColorToken.entries.map { it.name }.toSet(), root.getValue("dark").jsonObject.keys)
            assertEquals(NovaTypeToken.entries.map { it.name }.toSet(), root.getValue("typography").jsonObject.keys)
            assertEquals(NovaDimensionToken.entries.map { it.name }.toSet(), root.getValue("dimensions").jsonObject.keys)
            return root.flatMap { (group, values) -> values.jsonObject.map { (name, value) -> arrayOf(group, name, value) } }
        }
    }
}
