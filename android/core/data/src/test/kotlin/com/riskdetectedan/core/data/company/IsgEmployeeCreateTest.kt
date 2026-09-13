package com.riskdetectedan.core.data.company
import java.io.File
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
@RunWith(Parameterized::class)
class IsgEmployeeCreateTest(private val id: String, private val fixture: JsonObject) {
    @Test fun sharedCorpus() {
        val result=IsgEmployeeCreate.parse(fixture.getValue("input"))
        assertEquals(id,fixture.getValue("valid").jsonPrimitive.boolean,result!=null)
        if(result!=null)assertEquals(id,fixture.getValue("normalized_name").jsonPrimitive.content,result.fullName)
    }
    companion object {
        @JvmStatic @Parameterized.Parameters(name="{0}") fun fixtures(): List<Array<Any>> {
            val file=generateSequence(File(requireNotNull(System.getProperty("user.dir")))) { it.parentFile }.take(6)
                .map { File(it,"contracts/isg/v1/fixtures/employee-create.json") }.first { it.isFile }
            return Json.parseToJsonElement(file.readText()).jsonObject.getValue("cases").jsonArray.map { item ->
                val c=item.jsonObject;arrayOf(c.getValue("id").jsonPrimitive.content,c)
            }
        }
    }
}
