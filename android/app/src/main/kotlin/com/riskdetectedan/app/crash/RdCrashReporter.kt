package com.riskdetectedan.app.crash

import com.google.firebase.crashlytics.FirebaseCrashlytics
import com.riskdetectedan.app.BuildConfig
import javax.inject.Inject
import javax.inject.Singleton

enum class RdCrashClass(val wireValue: String) {
    Startup("startup"),
    Auth("auth"),
    Analysis("analysis"),
    Report("report"),
    Billing("billing"),
    Notification("notification"),
}

/** PII-free Crashlytics boundary. Raw backend/user messages must never cross this type. */
@Singleton
class RdCrashReporter @Inject constructor() {
    private val crashlytics by lazy { FirebaseCrashlytics.getInstance() }

    fun configure() {
        if (!BuildConfig.CRASHLYTICS_ENABLED) return
        crashlytics.setCrashlyticsCollectionEnabled(true)
        crashlytics.setCustomKey("client_platform", "android")
        crashlytics.setCustomKey("version_name", BuildConfig.VERSION_NAME)
        crashlytics.setCustomKey("version_code", BuildConfig.VERSION_CODE)
        crashlytics.setCustomKey("build_sha", BuildConfig.BUILD_SHA.take(40))
    }

    fun recordSafe(crashClass: RdCrashClass, throwable: Throwable) {
        if (!BuildConfig.CRASHLYTICS_ENABLED) return
        crashlytics.setCustomKey("safe_error_class", crashClass.wireValue)
        val sanitized = IllegalStateException("${crashClass.wireValue}:${throwable.javaClass.name}")
        sanitized.stackTrace = throwable.stackTrace
        crashlytics.recordException(sanitized)
    }
}
