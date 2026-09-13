package com.riskdetectedan.core.data.company
import java.io.File
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
@RunWith(Parameterized::class)
class IsgAssignmentMoveTest(private val id: String,private val valid: Boolean,private val input: JsonElement) {
    @Test fun sharedCorpus() {
        val result=IsgAssignmentMove.parse(input)
        assertEquals(id,valid,result!=null)
        if(result!=null) assertNotEquals(result.context.operationId,result.context.clientMutationId)
    }
    companion object {
        @JvmStatic @Parameterized.Parameters(name="{0}") fun fixtures(): List<Array<Any>> {
            val file=generateSequence(File(requireNotNull(System.getProperty("user.dir")))) { it.parentFile }.take(6)
                .map { File(it,"contracts/isg/v1/fixtures/assignment-move.json") }.first { it.isFile }
            return Json.parseToJsonElement(file.readText()).jsonObject.getValue("cases").jsonArray.map { item ->
                val c=item.jsonObject;arrayOf(c.getValue("id").jsonPrimitive.content,c.getValue("valid").jsonPrimitive.boolean,c.getValue("input"))
            }
        }
    }
}
