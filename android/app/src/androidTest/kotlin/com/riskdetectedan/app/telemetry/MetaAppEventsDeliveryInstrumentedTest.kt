package com.riskdetectedan.app.telemetry

import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.facebook.FacebookSdk
import com.facebook.LoggingBehavior
import com.facebook.appevents.AppEventsLogger
import com.riskdetectedan.app.MainActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/**
 * Explicit, opt-in transport smoke for Meta Events Manager.
 *
 * It is skipped during normal instrumentation suites and only sends a fixed synthetic event when
 * `rdMetaDeliveryTest=1` is supplied. No account, device advertising ID, purchase, or safety data
 * is attached to the event.
 */
@RunWith(AndroidJUnit4::class)
class MetaAppEventsDeliveryInstrumentedTest {
    @Test
    fun sendsSyntheticEventToMetaEventsManager() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        assumeTrue(InstrumentationRegistry.getArguments().getString("rdMetaDeliveryTest") == "1")
        val context = instrumentation.targetContext.applicationContext

        FacebookSdk.setAutoLogAppEventsEnabled(false)
        FacebookSdk.setAdvertiserIDCollectionEnabled(false)
        FacebookSdk.setLimitEventAndDataUsage(context, true)
        FacebookSdk.sdkInitialize(context)
        FacebookSdk.addLoggingBehavior(LoggingBehavior.APP_EVENTS)
        FacebookSdk.addLoggingBehavior(LoggingBehavior.REQUESTS)
        FacebookSdk.fullyInitialize()
        AppEventsLogger.activateApp(context as Application)

        val initializationDeadline = System.currentTimeMillis() + 10_000L
        while (!FacebookSdk.isFullyInitialized() && System.currentTimeMillis() < initializationDeadline) {
            Thread.sleep(100L)
        }

        assertTrue(FacebookSdk.isInitialized())
        assertTrue("Meta SDK did not finish initialization", FacebookSdk.isFullyInitialized())
        assertEquals("1704205447330558", FacebookSdk.getApplicationId())

        val flushLatch = CountDownLatch(1)
        val flushedEventCount = AtomicInteger(-1)
        val flushResult = AtomicReference<String>()
        val localBroadcasts = LocalBroadcastManager.getInstance(context)
        val flushReceiver = object : BroadcastReceiver() {
            override fun onReceive(receiverContext: Context?, intent: Intent?) {
                flushedEventCount.set(
                    intent?.getIntExtra(AppEventsLogger.APP_EVENTS_EXTRA_NUM_EVENTS_FLUSHED, -1) ?: -1,
                )
                flushResult.set(
                    intent?.getSerializableExtra(AppEventsLogger.APP_EVENTS_EXTRA_FLUSH_RESULT)
                        ?.toString(),
                )
                flushLatch.countDown()
            }
        }
        localBroadcasts.registerReceiver(
            flushReceiver,
            IntentFilter(AppEventsLogger.ACTION_APP_EVENTS_FLUSHED),
        )

        try {
            ActivityScenario.launch(MainActivity::class.java).use {
                val parameters = Bundle().apply {
                    putString("test_channel", "events_manager")
                    putString("app_platform", "android")
                }
                AppEventsLogger.newLogger(context).apply {
                    logEvent("rd_meta_integration_test", parameters)
                    flush()
                }

                assertTrue("Meta App Events flush did not finish", flushLatch.await(20, TimeUnit.SECONDS))
                assertTrue("Meta flush did not contain the synthetic event", flushedEventCount.get() >= 1)
                assertEquals("SUCCESS", flushResult.get())
            }
        } finally {
            localBroadcasts.unregisterReceiver(flushReceiver)
        }
    }
}
