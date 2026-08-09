package com.riskdetectedan.app.bootstrap

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/** Local root-flow state. The install marker lives in no-backup storage so a restored preference
 * or auth session can never silently turn a fresh install into an authenticated launch. */
@Singleton
class AppBootstrapStore @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    private val installMarker = File(context.noBackupFilesDir, INSTALL_MARKER)

    val hasCompletedOnboarding: Boolean
        get() = preferences.getBoolean(KEY_ONBOARDING_COMPLETED, false)

    /** Returns true only when this process successfully created a new-install marker. */
    fun initializeInstall(): Boolean {
        if (installMarker.exists()) return false
        val created = runCatching { installMarker.createNewFile() }.getOrDefault(false)
        if (created) preferences.edit().remove(KEY_ONBOARDING_COMPLETED).apply()
        return created
    }

    fun markOnboardingCompleted() {
        preferences.edit().putBoolean(KEY_ONBOARDING_COMPLETED, true).apply()
    }

    private companion object {
        const val PREFERENCES = "rd_bootstrap_v1"
        const val KEY_ONBOARDING_COMPLETED = "onboarding_completed"
        const val INSTALL_MARKER = "rd_install_marker_v1"
    }
}
