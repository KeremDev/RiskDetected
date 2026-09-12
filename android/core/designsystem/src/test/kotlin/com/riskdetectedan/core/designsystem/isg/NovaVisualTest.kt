package com.riskdetectedan.core.designsystem.isg

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.inspector.WindowInspector
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/** Real Compose/Skia pixels in a JVM test, NOT emulator/device evidence. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], qualifiers = "w440dp-h956dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class NovaVisualTest {
    @get:Rule val compose = createComposeRule()
    @Test fun captureHomeCompaniesAndModalContent() {
        var state by mutableStateOf(NovaNavigationState("visual-fixture", NovaDestination.entries.toSet()))
        val data = NovaDashboardData("Kerem", 1, listOf(
            NovaMetricItem("total", "1", "Toplam Uygunsuzluk", "+1 bu ay", Icons.Outlined.BookmarkBorder, NovaColorToken.statusInfoDot, NovaDestination.findings),
            NovaMetricItem("open", "1", "Açık Uygunsuzluk", "1 gecikmiş", Icons.Outlined.WarningAmber, NovaColorToken.statusDangerDot, NovaDestination.findings),
            NovaMetricItem("companies", "1", "Firma", "Atanmış firma", Icons.Outlined.Business, NovaColorToken.statusInfoDot, NovaDestination.companies),
            NovaMetricItem("visits", "1", "Ziyaret Sayısı", "1 bu ay", Icons.Outlined.Place, NovaColorToken.statusWarningDot, NovaDestination.visits),
            NovaMetricItem("training", "0", "Eğitim Süresi Geçen", "personel", Icons.Outlined.Schedule, NovaColorToken.statusDangerDot, NovaDestination.training)
        ), "Yeni firma atandı · Koza Altın A.Ş · Ahmet Bel · Uzman atandı", "Yaklaşan veya geçmiş eğitim uyarısı yok")
        compose.setContent { NovaTheme(false) {
            NovaExpertShell(state, "Kerem Kaya", hasUnread = true, connectionLabel = "Çevrimiçi",
                notices = listOf(
                    NovaNotice("overdue", "Termini geçen aksiyonlar", "Geciken düzeltmeleri önceliklendirerek inceleyin.", 1, Icons.Outlined.Warning, NovaColorToken.statusDangerInk),
                    NovaNotice("active", "Aktif uygunsuzluklar", "Sorumluluğunuzdaki firmalarda halen açık bulunan kayıtlar.", 1, Icons.Outlined.Notifications, NovaColorToken.statusInfoInk)),
                onNoticeAction = { _, _ -> }, onLogout = {},
                onEvent = { event, epoch -> state = state.apply(event, epoch) }) { destination ->
                if (destination == NovaDestination.companies) NovaCompaniesScreen(listOf(NovaCompanyItem("fixture", "Koza Altın A.Ş", "Kaymaz Mah. · Maden · Çok tehlikeli")), onSelect = {}, onBack = {}, onRetry = {})
                else NovaDashboardScreen(data, onNavigate = {}, onPhoto = {}, onAssistant = {})
            }
        } }
        capture("home")
        compose.onNodeWithTag("nova.tab.companies").performClick()
        capture("companies")
        compose.onNodeWithTag("nova.add").performClick()
        capture("add-dialog", dialog = true)
        compose.onNodeWithTag("nova.panel.close").performClick()
        compose.onNodeWithTag("nova.menu").performClick()
        capture("drawer-dialog", dialog = true)
        compose.onNodeWithTag("nova.panel.close").performClick()
        compose.onNodeWithTag("nova.notifications").performClick()
        capture("notifications-dialog", dialog = true)
    }
    private fun capture(name: String, dialog: Boolean = false) {
        compose.waitForIdle()
        // PixelCopy captureToImage requires a hardware redraw callback unavailable in Robolectric.
        // Draw the real window's view tree into native Skia instead; blank pixels fail below.
        val bitmap = compose.runOnIdle {
            val windows = WindowInspector.getGlobalWindowViews().filter { it.width > 0 && it.height > 0 }
            val view = if (dialog) windows.last() else windows.first()
            Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888).also { view.draw(Canvas(it)) }
        }
        assertTrue(bitmap.width >= 320 && bitmap.height >= 400)
        val colors = mutableSetOf<Int>()
        for (y in 0 until bitmap.height step 7) for (x in 0 until bitmap.width step 7) colors.add(bitmap.getPixel(x, y))
        assertTrue("Reject blank or unrendered screenshots", colors.size > 20)
        val file = File("build/reports/nova-visual/$name.png")
        requireNotNull(file.parentFile).mkdirs()
        file.outputStream().use { assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
    }
}
