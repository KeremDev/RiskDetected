package com.riskdetectedan.core.data.isg
import java.io.File
import kotlinx.serialization.json.*
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

@RunWith(Parameterized::class)
class IsgMutationOutcomeTest(private val kind: String, private val id: String, private val c: JsonObject) {
    @Test fun sharedOutcomeAndTransitionCorpus() {
        if (kind == "response") {
            val value = IsgMutationOutcome.parse(c.getValue("status").jsonPrimitive.int,c.getValue("input"))
            assertEquals(id,c.getValue("valid").jsonPrimitive.boolean,value != null)
            if (value != null) assertEquals(id,c.getValue("summary").jsonPrimitive.content,
                listOf(value.outcome,value.code ?: "",value.version?.toString() ?: "",value.currentVersion?.toString() ?: "",value.projection ?: "",value.retryAfterSeconds?.toString() ?: "").joinToString("|"))
        } else {
            val value = IsgMutationTransition.next(IsgMutationPhase.valueOf(c.getValue("phase").jsonPrimitive.content),IsgMutationEvent.valueOf(c.getValue("event").jsonPrimitive.content),c.getValue("same_context").jsonPrimitive.boolean)
            assertEquals(id,c.getValue("next_phase").jsonPrimitive.content,value.phase.name)
            assertEquals(id,c.getValue("effect").jsonPrimitive.content,value.effect)
        }
    }
    companion object {
        @JvmStatic @Parameterized.Parameters(name="{0}:{1}") fun fixtures(): List<Array<Any>> {
            val fixture = generateSequence(File(requireNotNull(System.getProperty("user.dir")))) { it.parentFile }.take(6)
                .map { File(it,"contracts/isg/v1/fixtures/mutation-outcome.json") }.first { it.isFile }
            val root = Json.parseToJsonElement(fixture.readText()).jsonObject
            return listOf("cases" to "response","transitions" to "transition").flatMap { (key,kind) -> root.getValue(key).jsonArray.map { e -> arrayOf(kind,e.jsonObject.getValue("id").jsonPrimitive.content,e.jsonObject) } }
        }
    }
}
