package com.riskdetectedan.core.designsystem.isg

import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class NovaDirectoryFormRulesTest {
    private val root = UUID.fromString("11111111-1111-4111-8111-111111111111")
    private val child = UUID.fromString("22222222-2222-4222-8222-222222222222")
    private val grandchild = UUID.fromString("33333333-3333-4333-8333-333333333333")
    private val other = UUID.fromString("44444444-4444-4444-8444-444444444444")
    private fun row(id: UUID, vararg fields: Pair<String, String>) = NovaDirectoryRow(id, fields.toMap().mapValues { NovaDirectoryValue.Text(it.value) })

    @Test fun canonicalGregorianDatesRejectNormalizationAndUnicode() {
        listOf("0001-01-01", "9999-12-31", "2000-02-29", "2024-02-29", "2026-09-13", "1900-02-28").forEach { assertTrue(it, NovaDirectoryFormRules.isDate(it)) }
        listOf("", "2026-2-01", "2026-02-1", "2026-02-29", "1900-02-29", "2100-02-29", "2026-04-31", "2026-00-01", "2026-13-01", "2026-01-00", "2026-01-32", "0000-01-01", "10000-01-01", " 2026-01-01", "2026-01-01\n", "２０２６-01-01", "2026/01/01", "2026-01-01T00:00:00Z").forEach { assertFalse(it, NovaDirectoryFormRules.isDate(it)) }
    }
    @Test fun halfOpenEngagementIntervalAllowsOpenEndButNotEqualOrEarlierEnd() {
        fun check(end: String) = NovaDirectoryFormRules.validation(NovaDirectoryKind.engagements, mapOf("starts_on" to "2026-09-13", "ends_before" to end), emptyMap(), null)
        assertNull(check("")); assertNull(check("2026-09-14")); assertNotNull(check("2026-09-13")); assertNotNull(check("2026-09-12")); assertNotNull(check("2026-02-30"))
    }
    @Test fun priorClosedPeriodCanBeSplitOnlyInsideItsBoundsOnBothHistoryKinds() {
        val prior = row(root, "starts_on" to "2026-01-01", "ends_before" to "2026-12-31")
        for (kind in listOf(NovaDirectoryKind.contexts, NovaDirectoryKind.assignments)) {
            fun check(day: String, options: List<NovaDirectoryRow> = listOf(prior)) = NovaDirectoryFormRules.validation(kind, mapOf("starts_on" to day, "previous_id" to root.toString()), mapOf("previous_id" to options), null)
            assertNull(check("2026-06-01")); assertNotNull(check("2026-01-01")); assertNotNull(check("2026-12-31")); assertNotNull(check("2027-01-01")); assertNotNull(check("2026-06-01", emptyList()))
        }
    }
    @Test fun hierarchyExcludesSelfDescendantsAndForeignWorkplaceRegardlessOfRowOrder() {
        val rows = listOf(row(grandchild, "parent_id" to child.toString(), "workplace_id" to "a"), row(child, "parent_id" to root.toString(), "workplace_id" to "a"), row(root, "workplace_id" to "a"), row(other, "workplace_id" to "b"))
        assertTrue(NovaDirectoryFormRules.allowedOptions(rows, "parent_id", "a", root).isEmpty())
        assertEquals(listOf(other), NovaDirectoryFormRules.allowedOptions(rows, "parent_id", "b", root).map { it.id })
        assertEquals(3, NovaDirectoryFormRules.allowedOptions(rows, "department_id", "a", null).size)
        assertNotNull(NovaDirectoryFormRules.validation(NovaDirectoryKind.departments, mapOf("workplace_id" to "a", "parent_id" to child.toString()), mapOf("parent_id" to rows), root))
        // A corrupt cyclic read must terminate; authoritative server rejects such writes.
        val cycle = listOf(row(root, "parent_id" to child.toString(), "workplace_id" to "a"), row(child, "parent_id" to root.toString(), "workplace_id" to "a"))
        assertTrue(NovaDirectoryFormRules.allowedOptions(cycle, "parent_id", "a", root).isEmpty())
    }
    @Test fun reselectingSameWorkplacePreservesDepartmentButChangingItClearsBothLinks() {
        val fields = mapOf("workplace_id" to "a", "parent_id" to "p", "department_id" to "d", "name" to "Ada")
        assertEquals(fields, NovaDirectoryFormRules.selecting("workplace_id", "a", fields))
        val changed = NovaDirectoryFormRules.selecting("workplace_id", "b", fields)
        assertEquals("", changed["parent_id"]); assertEquals("", changed["department_id"]); assertEquals("Ada", changed["name"])
    }
}
