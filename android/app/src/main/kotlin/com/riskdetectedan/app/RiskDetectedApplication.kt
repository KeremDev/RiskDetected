package com.riskdetectedan.app

import android.app.Application
import com.riskdetectedan.app.crash.RdCrashReporter
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
        installAttributionRepository.collectOnce()
    }
}
