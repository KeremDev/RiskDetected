package com.riskdetectedan.core.data.nova

import org.junit.Assert.*
import org.junit.Test

/** The home section's arrangement and the unfinished items' turns; iOS `NovaForYouLayoutTests` checks the same cases. */
class NovaForYouLayoutTest {
    private fun kind(id: String) = id.substringBefore('.')
    private fun layout(vararg ids: String, continueId: String? = null) = NovaForYouLayout.of(ids.toList(), ::kind, { it }, continueId)

    private val screen = arrayOf("critical.expired", "continue.company_create", "continue.checklist_open",
        "performance.analyses_30d", "discover.risk_wizard", "discover.followup", "motivation.today_analysis")

    @Test fun suggestionsOnTopAttentionAndUnfinishedWorkInBoxesProgressAsStrip() {
        val result = layout(*screen)
        assertEquals(listOf("discover.risk_wizard", "discover.followup"), result.featured)
        assertEquals(listOf("critical.expired", "continue.company_create"), result.boxes)
        assertEquals("performance.analyses_30d", result.strip)
        assertEquals(listOf("critical.expired", "continue.checklist_open"), layout(*screen, continueId = "continue.checklist_open").boxes)
        assertEquals(listOf("critical.expired", "continue.company_create"), layout(*screen, continueId = "continue.gone").boxes)
    }

    @Test fun theMostUrgentAttentionCardWhateverTheRank() {
        val result = layout("continue.checklist_open", "critical.soon", "critical.nonconformity_overdue", "performance.analyses_7d")
        assertEquals(listOf("critical.soon", "continue.checklist_open"), result.boxes)
        assertEquals("performance.analyses_7d", result.strip)
    }

    @Test fun progressTakesAnEmptyBoxAndTheStripGoes() {
        val noAttention = layout("continue.risk_draft", "continue.checklist_open", "performance.analyses_7d", "discover.followup")
        assertEquals(listOf("continue.risk_draft", "performance.analyses_7d"), noAttention.boxes)
        assertNull(noAttention.strip)
        assertEquals(listOf("critical.expired", "performance.analyses_7d"),
            layout("critical.expired", "performance.analyses_7d", "motivation.statistics", "discover.followup").boxes)
        val noProgress = layout("critical.expired", "continue.risk_draft", "motivation.statistics", "discover.followup")
        assertEquals(listOf("critical.expired", "continue.risk_draft"), noProgress.boxes)
        assertNull(noProgress.strip)
    }

    @Test fun aFirstStepFillsABoxStillEmpty() {
        assertEquals(listOf("continue.risk_draft", "motivation.statistics"),
            layout("continue.risk_draft", "discover.checklist", "motivation.statistics").boxes)
        assertEquals(listOf("motivation.statistics", "performance.analyses_7d"),
            layout("performance.analyses_7d", "discover.checklist", "motivation.statistics").boxes)
        val fresh = layout("motivation.first_company", "motivation.first_personnel", "discover.risk_wizard")
        assertEquals(listOf("discover.risk_wizard"), fresh.featured)
        assertEquals(listOf("motivation.first_company"), fresh.boxes)
        assertNull(fresh.strip)
    }

    @Test fun firstStepsRotateWhenNoSuggestionIsLeft() {
        val result = layout("critical.expired", "performance.analyses_7d",
            "motivation.today_analysis", "motivation.statistics", "motivation.photo_analysis")
        assertEquals(listOf("motivation.today_analysis", "motivation.statistics", "motivation.photo_analysis"), result.featured)
        assertEquals(listOf("critical.expired", "performance.analyses_7d"), result.boxes)
    }

    @Test fun atMostFiveSuggestionsAndNothingForAnEmptyFeed() {
        assertEquals(5, layout(*Array(7) { "discover.f$it" }).featured.size)
        assertEquals(0, layout().size)
    }

    @Test fun noTwoPlacesShareAKind() {
        val pool = listOf("critical.expired", "continue.risk_draft", "performance.analyses_7d", "discover.followup", "motivation.statistics")
        for (mask in 0 until (1 shl pool.size)) {
            val ids = pool.indices.filter { mask and (1 shl it) != 0 }.flatMap { listOf(pool[it], pool[it] + "_2") }
            val result = NovaForYouLayout.of(ids, ::kind)
            val below = (result.boxes + listOfNotNull(result.strip)).map(::kind)
            val featuredKinds = result.featured.map(::kind).toSet()
            assertEquals(ids.toString(), below.toSet().size, below.size)
            assertTrue(ids.toString(), result.boxes.size <= 2)
            assertTrue(ids.toString(), featuredKinds.size <= 1 && featuredKinds.none { it in below })
        }
    }

    @Test fun unfinishedItemsTakeTurnsVisitByVisit() {
        val stored = mutableMapOf<String, String>()
        fun rotation(scope: String) = NovaForYouRotation({ stored[scope] }, { stored[scope] = it })
        val ids = listOf("a", "b", "c")
        val visit = rotation("me:personal")
        assertEquals("a", visit.pick(ids))
        assertEquals("a refresh keeps the visit's item", "a", visit.pick(ids))
        visit.newVisit()
        assertEquals("b", visit.pick(ids))
        assertEquals("the next visit's host", "c", rotation("me:personal").pick(ids))
        assertEquals("starts over", "a", rotation("me:personal").pick(ids))
        assertEquals("per user and workspace", "a", rotation("me:workspace").pick(ids))

        val done = rotation("me:personal")
        assertEquals("b", done.pick(ids))
        assertEquals("the visit's item was finished", "a", done.pick(listOf("a", "c")))
        assertNull(done.pick(emptyList()))
        assertNull(NovaForYouRotation.next(null, emptyList()))
    }
}
