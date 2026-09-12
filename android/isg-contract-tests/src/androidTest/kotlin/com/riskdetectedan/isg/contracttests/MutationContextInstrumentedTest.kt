package com.riskdetectedan.isg.contracttests

import androidx.test.platform.app.InstrumentationRegistry
import com.riskdetectedan.core.data.isg.IsgMutationContext
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
class MutationContextInstrumentedTest(private val id: String, private val valid: Boolean, private val input: JsonElement) {
    @Test fun sharedMutationContextCorpus() {
        assertEquals(id, valid, IsgMutationContext.parse(input) != null)
    }

    companion object {
        @JvmStatic @Parameterized.Parameters(name = "{0}")
        fun fixtures(): List<Array<Any>> {
            val json = InstrumentationRegistry.getInstrumentation().context.assets
                .open("mutation-context.json").bufferedReader().use { it.readText() }
            return Json.parseToJsonElement(json).jsonObject.getValue("cases").jsonArray.map { element ->
                val case = element.jsonObject
                arrayOf(case.getValue("id").jsonPrimitive.content, case.getValue("valid").jsonPrimitive.boolean, case.getValue("input"))
            }
        }
    }
}
