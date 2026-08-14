package com.riskdetectedan.core.data.analysis

import android.content.Context
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class InFlightAnalysisStoreTest {
    private lateinit var context: Context
    private lateinit var store: InFlightAnalysisStore

    @Before fun setUp() {
        context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("rd_analysis_in_flight", Context.MODE_PRIVATE).edit().clear().commit()
        store = InFlightAnalysisStore(context)
    }

    @After fun tearDown() {
        context.getSharedPreferences("rd_analysis_in_flight", Context.MODE_PRIVATE).edit().clear().commit()
    }

    @Test fun `in flight analysis survives store recreation for same user`() {
        val analysis = InFlightAnalysis("analysis-1", "user-1", 3, System.currentTimeMillis(), "Saha")
        store.save(analysis)

        assertEquals(analysis, InFlightAnalysisStore(context).load("user-1"))
    }

    @Test fun `cross account record is rejected and removed`() {
        store.save(InFlightAnalysis("analysis-1", "user-1", 1, System.currentTimeMillis(), "Saha"))

        assertNull(store.load("user-2"))
        assertNull(store.load())
    }

    @Test fun `expired record cannot resume`() {
        store.save(
            InFlightAnalysis(
                "analysis-old",
                "user-1",
                1,
                System.currentTimeMillis() - 31 * 60 * 1000,
                "Eski",
            ),
        )

        assertNull(store.load("user-1"))
    }

    @Test fun `pending submission is reused only for identical user and input`() {
        val pending = PendingAnalysisSubmission("submission-1", "user-1", "hash-1", System.currentTimeMillis())
        store.savePending(pending)
        assertEquals(pending, store.pendingFor("user-1", "hash-1"))

        assertNull(store.pendingFor("user-1", "different-hash"))
        assertNull(store.pendingFor("user-1", "hash-1"))
    }

    @Test fun `clear with another id preserves active analysis`() {
        val analysis = InFlightAnalysis("analysis-1", "user-1", 1, System.currentTimeMillis(), "Saha")
        store.save(analysis)
        store.clear("analysis-2")

        assertEquals(analysis, store.load("user-1"))
    }
}
