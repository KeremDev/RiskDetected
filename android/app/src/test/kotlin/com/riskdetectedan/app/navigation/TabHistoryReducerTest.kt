package com.riskdetectedan.app.navigation

import org.junit.Assert.assertEquals
import org.junit.Test

class TabHistoryReducerTest {
    @Test fun repeatedSelectionDoesNotDuplicateHistory() {
        val initial = TabHistorySnapshot(RdTab.Home, emptyList())
        assertEquals(initial, TabHistoryReducer.select(initial, RdTab.Home))
    }

    @Test fun backTraversesSelectedTabsInReverseOrder() {
        val home = TabHistorySnapshot(RdTab.Home, emptyList())
        val analyses = TabHistoryReducer.select(home, RdTab.Analyses)
        val reports = TabHistoryReducer.select(analyses, RdTab.Reports)
        assertEquals(RdTab.Analyses, TabHistoryReducer.back(reports).active)
        assertEquals(RdTab.Home, TabHistoryReducer.back(TabHistoryReducer.back(reports)).active)
    }
}
