package com.riskdetectedan.feature.profile

import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class NovaDirectoryAdapterTest {
    private val scope = NovaPersonnelScope(UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID(), "generation-1")
    private fun intent(kind: NovaDirectoryKind, expected: Long = 0) = NovaDirectoryIntent(scope, kind, UUID.randomUUID(), UUID.randomUUID(), null, expected,
        mapOf("name" to NovaDirectoryValue.Text("İşyeri"), "parent_id" to NovaDirectoryValue.Null, "is_archived" to NovaDirectoryValue.Flag(false)))
    @Test fun everyKindUsesFixedRPCShapeAndScope() {
        NovaDirectoryKind.entries.forEach { kind ->
            val i = intent(kind); val a = i.directoryArgs()
            assertEquals(setOf("p_company", "p_kind", "p_operation", "p_mutation", "p_id", "p_expected", "p_body"), a.keys)
            assertEquals(JsonPrimitive(scope.companyID.toString()), a["p_company"])
            assertEquals(JsonPrimitive(kind.name), a["p_kind"])
            assertEquals(JsonNull, a["p_id"])
            assertEquals(JsonPrimitive(i.operationID.toString()), a["p_operation"])
            assertEquals(JsonPrimitive(i.mutationID.toString()), a["p_mutation"])
            assertEquals(JsonPrimitive(0), a["p_expected"])
            assertEquals(JsonNull, a.getValue("p_body").jsonObject["parent_id"])
            assertEquals(JsonPrimitive(false), a.getValue("p_body").jsonObject["is_archived"])
            assertFalse(a.toString().contains(scope.sessionID.toString()))
            assertFalse(a.toString().contains(scope.epoch))
        }
    }
    @Test fun stableRetryDoesNotAllocateNewKeys() {
        val i = intent(NovaDirectoryKind.departments)
        assertEquals(i.directoryArgs(), i.directoryArgs())
        assertEquals(i.directoryArgs(), i.copy(scope = scope.copy(epoch = "generation-2", sessionID = UUID.randomUUID())).directoryArgs())
    }
    @Test fun preciseCodeAndUnicodeArePreserved() {
        val i = intent(NovaDirectoryKind.workplaces).copy(body = mapOf("code" to NovaDirectoryValue.Text("001"), "name" to NovaDirectoryValue.Text("İş Sağlığı")))
        assertEquals("001", i.directoryArgs().getValue("p_body").jsonObject.getValue("code").jsonPrimitive.content)
        assertEquals("İş Sağlığı", i.directoryArgs().getValue("p_body").jsonObject.getValue("name").jsonPrimitive.content)
    }
    @Test fun versionsCannotOverflowOrBecomeNegative() {
        for (bad in listOf(-1L, Long.MIN_VALUE, 9007199254740991L, Long.MAX_VALUE)) {
            assertTrue(runCatching { intent(NovaDirectoryKind.jobs, bad).directoryArgs() }.isFailure)
        }
        assertEquals(JsonPrimitive(9007199254740990L), intent(NovaDirectoryKind.jobs, 9007199254740990L).directoryArgs()["p_expected"])
    }
    @Test fun rowSnapshotsRemainIndependentFromCatalogChanges() {
        val snapshot = NovaDirectoryRow(UUID.randomUUID(), mapOf("job_title_snapshot" to NovaDirectoryValue.Text("Operatör"), "version" to NovaDirectoryValue.Number(2)))
        val changed = NovaDirectoryRow(UUID.randomUUID(), mapOf("title" to NovaDirectoryValue.Text("Yeni Unvan")))
        assertEquals("Operatör", snapshot.title); assertEquals("Yeni Unvan", changed.title); assertEquals(2L, snapshot.version)
    }
}
