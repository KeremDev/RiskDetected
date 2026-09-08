package com.riskdetectedan.app

import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(application = Application::class, sdk = [35])
class MetaManifestContractTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

    @Test
    fun `debug manifest is inert and contains no advertising identifiers or audiences`() {
        val appInfo = context.packageManager.getApplicationInfo(
            context.packageName,
            PackageManager.ApplicationInfoFlags.of(PackageManager.GET_META_DATA.toLong()),
        )
        assertEquals("1704205447330558", context.getString(R.string.facebook_app_id))
        assertEquals("f6f4965c24873f6bff7d961a5aa79e38", context.getString(R.string.facebook_client_token))
        assertFalse(appInfo.metaData.getBoolean("com.facebook.sdk.AutoInitEnabled"))
        assertFalse(appInfo.metaData.getBoolean("com.facebook.sdk.AutoLogAppEventsEnabled"))
        assertFalse(appInfo.metaData.getBoolean("com.facebook.sdk.AdvertiserIDCollectionEnabled"))

        val packageInfo = context.packageManager.getPackageInfo(
            context.packageName,
            PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong()),
        )
        val permissions = packageInfo.requestedPermissions.orEmpty().toSet()
        assertFalse("com.google.android.gms.permission.AD_ID" in permissions)
        assertFalse("android.permission.ACCESS_ADSERVICES_AD_ID" in permissions)
        assertFalse("android.permission.ACCESS_ADSERVICES_CUSTOM_AUDIENCE" in permissions)
        assertFalse("android.permission.ACCESS_ADSERVICES_TOPICS" in permissions)
        // Privacy Sandbox attribution is the aggregate/no-runtime-prompt counterpart to iOS
        // SKAN/AEM and is retained for install campaign attribution.
        assertTrue("android.permission.ACCESS_ADSERVICES_ATTRIBUTION" in permissions)
    }
}
