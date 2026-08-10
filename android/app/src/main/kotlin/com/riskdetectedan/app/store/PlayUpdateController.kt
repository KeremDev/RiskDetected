package com.riskdetectedan.app.store

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Backend decides hard/soft; Play Core supplies the native update surface when available. */
class PlayUpdateController(
    private val activity: Activity,
    private val launcher: ActivityResultLauncher<IntentSenderRequest>,
) {
    private val manager: AppUpdateManager = AppUpdateManagerFactory.create(activity)
    private val _flexibleUpdateReady = MutableStateFlow(false)
    val flexibleUpdateReady: StateFlow<Boolean> = _flexibleUpdateReady.asStateFlow()

    private val installListener = InstallStateUpdatedListener { state ->
        if (state.installStatus() == InstallStatus.DOWNLOADED) {
            _flexibleUpdateReady.value = true
        }
    }

    init {
        manager.registerListener(installListener)
    }

    fun request(immediate: Boolean, storeUrl: String) {
        val updateType = if (immediate) AppUpdateType.IMMEDIATE else AppUpdateType.FLEXIBLE
        manager.appUpdateInfo
            .addOnSuccessListener { info ->
                if (info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE && info.isUpdateTypeAllowed(updateType)) {
                    start(info, updateType, storeUrl)
                } else {
                    openStore(storeUrl)
                }
            }
            .addOnFailureListener { openStore(storeUrl) }
    }

    fun resumeInterruptedImmediateUpdate() {
        manager.appUpdateInfo.addOnSuccessListener { info ->
            if (info.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS) {
                start(info, AppUpdateType.IMMEDIATE, defaultStoreUrl())
            }
            if (info.installStatus() == InstallStatus.DOWNLOADED) {
                _flexibleUpdateReady.value = true
            }
        }
    }

    fun completeFlexibleUpdate() {
        _flexibleUpdateReady.value = false
        manager.completeUpdate()
    }

    fun postponeFlexibleUpdate() {
        _flexibleUpdateReady.value = false
    }

    fun close() {
        manager.unregisterListener(installListener)
    }

    private fun start(info: AppUpdateInfo, updateType: Int, storeUrl: String) {
        runCatching {
            manager.startUpdateFlowForResult(
                info,
                launcher,
                AppUpdateOptions.newBuilder(updateType).build(),
            )
        }.onFailure { openStore(storeUrl) }
    }

    private fun defaultStoreUrl(): String =
        "https://play.google.com/store/apps/details?id=${activity.packageName}"

    private fun openStore(url: String) {
        val safeUrl = url.takeIf { it.startsWith("https://play.google.com/") || it.startsWith("market://") }
            ?: defaultStoreUrl()
        runCatching { activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(safeUrl))) }
    }
}
