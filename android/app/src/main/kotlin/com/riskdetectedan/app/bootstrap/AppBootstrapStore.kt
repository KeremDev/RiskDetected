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

    /**
     * A pending marker is written only for a genuinely fresh install. Its absence on an older
     * installation is deliberately treated as a returning-user signal: a signed-out member must
     * reach Login, not be forced through onboarding again after an app migration or long absence.
     */
    val shouldStartOnboarding: Boolean
        get() = preferences.getBoolean(KEY_ONBOARDING_PENDING, false) &&
            !hasCompletedOnboarding &&
            !preferences.getBoolean(KEY_EVER_AUTHENTICATED, false)

    /** Returns true only when this process successfully created a new-install marker. */
    fun initializeInstall(): Boolean {
        if (installMarker.exists()) return false
        val created = runCatching { installMarker.createNewFile() }.getOrDefault(false)
        if (created) {
            preferences.edit()
                .remove(KEY_ONBOARDING_COMPLETED)
                .remove(KEY_EVER_AUTHENTICATED)
                .putBoolean(KEY_ONBOARDING_PENDING, true)
                .apply()
        }
        return created
    }

    fun markOnboardingCompleted() {
        preferences.edit()
            .putBoolean(KEY_ONBOARDING_COMPLETED, true)
            .putBoolean(KEY_ONBOARDING_PENDING, false)
            .apply()
    }

    fun markAuthenticated() {
        preferences.edit()
            .putBoolean(KEY_EVER_AUTHENTICATED, true)
            .putBoolean(KEY_ONBOARDING_PENDING, false)
            .apply()
    }

    private companion object {
        const val PREFERENCES = "rd_bootstrap_v1"
        const val KEY_ONBOARDING_COMPLETED = "onboarding_completed"
        const val KEY_ONBOARDING_PENDING = "onboarding_pending"
        const val KEY_EVER_AUTHENTICATED = "ever_authenticated"
        const val INSTALL_MARKER = "rd_install_marker_v1"
    }
}
