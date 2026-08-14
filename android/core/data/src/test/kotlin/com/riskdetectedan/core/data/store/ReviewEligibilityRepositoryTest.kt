package com.riskdetectedan.core.data.store

import android.content.Context
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
class ReviewEligibilityRepositoryTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()

    @Before
    @After
    fun clearState() {
        context.getSharedPreferences("rd_store_review", Context.MODE_PRIVATE).edit().clear().commit()
    }

    @Test
    fun `third successful report after seven days becomes eligible`() {
        val repository = ReviewEligibilityRepository(context)
        val firstOpen = context.getSharedPreferences("rd_store_review", Context.MODE_PRIVATE)
            .getLong("first_open_at", 0L)
        val eligibleAt = firstOpen + TimeUnit.DAYS.toMillis(7)

        repository.recordSuccessfulReport("report-1", eligibleAt)
        repository.recordSuccessfulReport("report-2", eligibleAt)
        assertFalse(repository.requestPending.value)

        repository.recordSuccessfulReport("report-3", eligibleAt)
        assertTrue(repository.requestPending.value)
    }

    @Test
    fun `three reports before seven days stay ineligible`() {
        val repository = ReviewEligibilityRepository(context)
        repeat(3) { repository.recordSuccessfulReport("report-$it", System.currentTimeMillis()) }
        assertFalse(repository.requestPending.value)
    }

    @Test
    fun `existing third report becomes eligible when app reopens after seven days`() {
        context.getSharedPreferences("rd_store_review", Context.MODE_PRIVATE).edit()
            .putLong("first_open_at", System.currentTimeMillis() - TimeUnit.DAYS.toMillis(8))
            .putInt("successful_report_count", 3)
            .commit()

        val repository = ReviewEligibilityRepository(context)

        assertTrue(repository.requestPending.value)
    }

    @Test
    fun `the same successful report is counted only once`() {
        val repository = ReviewEligibilityRepository(context)
        val firstOpen = context.getSharedPreferences("rd_store_review", Context.MODE_PRIVATE)
            .getLong("first_open_at", 0L)
        val eligibleAt = firstOpen + TimeUnit.DAYS.toMillis(7)

        repeat(3) { repository.recordSuccessfulReport("same-report", eligibleAt) }

        assertFalse(repository.requestPending.value)
    }

    @Test
    fun `review is requested at most once per version`() {
        val repository = ReviewEligibilityRepository(context)
        repository.markRequested(1)
        assertTrue(repository.wasRequestedForVersion(1))
        assertFalse(repository.wasRequestedForVersion(2))
        assertFalse(repository.requestPending.value)
    }
}
