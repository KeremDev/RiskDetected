package com.riskdetectedan.core.data.auth

import kotlinx.serialization.json.*
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.io.File

@RunWith(Parameterized::class)
class IsgPasswordRulesTest(private val id: String, private val password: String, private val expected: Boolean) {
    @Test fun sharedNewPasswordPolicy() { assertEquals(id, expected, IsgPasswordRules.evaluate(password).valid) }
    companion object {
        @JvmStatic @Parameterized.Parameters(name = "{0}")
        fun cases(): List<Array<Any>> {
            val corpus = Json.parseToJsonElement(File("../../../contracts/isg/v1/fixtures/password-rules.json").readText()).jsonObject
            return corpus.getValue("cases").jsonArray.map { value ->
                val row = value.jsonObject
                arrayOf(row.getValue("id").jsonPrimitive.content, row.getValue("password").jsonPrimitive.content, row.getValue("valid").jsonPrimitive.boolean)
            }
        }
    }
}
