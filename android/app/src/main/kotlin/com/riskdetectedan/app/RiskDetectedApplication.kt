package com.riskdetectedan.app

import android.app.Application
import com.riskdetectedan.app.crash.RdCrashReporter
import com.riskdetectedan.app.push.RdNotificationChannel
import com.riskdetectedan.core.data.attribution.InstallAttributionRepository
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject

@HiltAndroidApp
class RiskDetectedApplication : Application() {
    @Inject lateinit var crashReporter: RdCrashReporter
    @Inject lateinit var installAttributionRepository: InstallAttributionRepository

    override fun onCreate() {
        super.onCreate()
        crashReporter.configure()
        // Registered before any message can arrive: FCM renders background notifications itself
        // and drops them on a fallback channel when the declared default channel doesn't exist.
        RdNotificationChannel.ensure(this)
        installAttributionRepository.collectOnce()
    }
}
