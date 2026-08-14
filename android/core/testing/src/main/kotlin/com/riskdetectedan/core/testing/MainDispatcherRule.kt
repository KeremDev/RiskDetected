package com.riskdetectedan.core.testing

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.rules.TestWatcher
import org.junit.runner.Description
import kotlinx.coroutines.Dispatchers

/**
 * Every ViewModel test in every feature module uses this rule instead of touching
 * [Dispatchers.Main] directly — required per this repo's Faz-2-onward DoD rule that
 * unknown-platform/async-timing tests must be deterministic (contracts §D.2.4).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class MainDispatcherRule(
    private val testDispatcher: TestDispatcher = StandardTestDispatcher(),
) : TestWatcher() {
    override fun starting(description: Description) {
        Dispatchers.setMain(testDispatcher)
    }

    override fun finished(description: Description) {
        Dispatchers.resetMain()
    }
}
