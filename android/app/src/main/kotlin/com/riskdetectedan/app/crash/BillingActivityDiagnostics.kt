package com.riskdetectedan.app.crash

import android.app.Activity
import android.app.Application
import android.os.Bundle
import com.google.firebase.crashlytics.FirebaseCrashlytics
import com.riskdetectedan.app.BuildConfig

/** Runs before the SDK's onCreate (API 29+), including the observed Android 11 crash.
 * Observes only argument presence; never changes Play intents or hides a fatal exception.
 */
class BillingActivityDiagnostics : Application.ActivityLifecycleCallbacks {
    override fun onActivityPreCreated(activity: Activity, savedInstanceState: Bundle?) {
        if (!BuildConfig.CRASHLYTICS_ENABLED || activity.javaClass.name != "com.android.billingclient.api.ProxyBillingActivity") return
        runCatching {
        val crash = FirebaseCrashlytics.getInstance()
        crash.setCustomKey("billing_proxy_restored", savedInstanceState != null)
        crash.setCustomKey("billing_proxy_has_buy_intent", activity.intent?.hasExtra("BUY_INTENT") == true)
        crash.setCustomKey("billing_proxy_has_subscription_intent", activity.intent?.hasExtra("SUBS_MANAGEMENT_INTENT") == true)
        crash.log("billing_proxy_pre_create")
        }
    }
    override fun onActivityCreated(activity: Activity, state: Bundle?) = Unit
    override fun onActivityStarted(activity: Activity) = Unit
    override fun onActivityResumed(activity: Activity) = Unit
    override fun onActivityPaused(activity: Activity) = Unit
    override fun onActivityStopped(activity: Activity) = Unit
    override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) = Unit
    override fun onActivityDestroyed(activity: Activity) = Unit
}
