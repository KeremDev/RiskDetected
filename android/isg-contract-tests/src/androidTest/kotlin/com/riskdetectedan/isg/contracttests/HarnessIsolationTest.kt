package com.riskdetectedan.isg.contracttests

import android.Manifest
import android.app.Application
import android.content.pm.PackageManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HarnessIsolationTest {
    @Test fun harnessCannotUseNetworkOrLaunchProductionApplication() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertEquals("com.riskdetectedan.isg.contracttests.test", context.packageName)
        assertEquals(PackageManager.PERMISSION_DENIED, context.checkSelfPermission(Manifest.permission.INTERNET))
        assertEquals(PackageManager.PERMISSION_DENIED, context.checkSelfPermission(Manifest.permission.ACCESS_NETWORK_STATE))
        assertEquals(Application::class.java, context.applicationContext.javaClass)
        assertFalse(context.applicationInfo.packageName == "com.riskdetectedan.app")
    }
}
