package com.riskdetectedan.isg.designpreview

import android.os.Bundle
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import com.riskdetectedan.core.designsystem.isg.*

/** Offline synthetic host. No Auth, network permission, persistence or real account. */
class DesignPreviewActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Do not run this QA executable on a physical device.
        if (!Build.FINGERPRINT.contains("generic") && !Build.MODEL.contains("sdk_gphone")) { finish(); return }
        enableEdgeToEdge()
        setContent {
            var state by remember { mutableStateOf(NovaNavigationState("offline-preview", NovaDestination.entries.toSet())) }
            var notices by remember { mutableStateOf(listOf(
                NovaNotice("overdue", "Termini geçen aksiyonlar", "Geciken düzeltmeleri önceliklendirerek inceleyin.", 1, Icons.Outlined.Warning, NovaColorToken.statusDangerInk),
                NovaNotice("active", "Aktif uygunsuzluklar", "Sorumluluğunuzdaki firmalarda halen açık bulunan kayıtlar.", 1, Icons.Outlined.Notifications, NovaColorToken.statusInfoInk))) }
            val navigate: (NovaDestination) -> Unit = { state = state.apply(NovaNavigationEvent.Navigate(it), state.epoch) }
            NovaTheme(false) {
                NovaExpertShell(state, "Kerem Kaya", Modifier.safeDrawingPadding(), hasUnread = notices.any { it.unread },
                    connectionLabel = "Çevrimdışı test", notices = notices,
                    onNoticeAction = { action, epoch -> if (epoch == state.epoch) notices = if (action == NovaNoticeAction.Clear) emptyList() else notices.map { it.copy(unread = false) } },
                    onLogout = { state = NovaNavigationState("signed-out-preview", emptySet()) },
                    onEvent = { event, epoch -> state = state.apply(event, epoch) }) { destination ->
                    when (destination) {
                        NovaDestination.home -> NovaDashboardScreen(dashboard, onNavigate = navigate,
                            onPhoto = { navigate(NovaDestination.newFinding) }, onAssistant = { navigate(NovaDestination.newFinding) })
                        NovaDestination.companies -> NovaCompaniesScreen(listOf(NovaCompanyItem("fixture", "Koza Altın A.Ş", "Kaymaz Mah. · Maden · Çok tehlikeli")),
                            onSelect = { navigate(NovaDestination.memory) }, onBack = { navigate(NovaDestination.home) }, onRetry = {})
                        else -> NovaText("Sentetik hedef: ${destination.title}")
                    }
                }
            }
        }
    }
}
private val dashboard = NovaDashboardData("Kerem", 1, listOf(
    NovaMetricItem("total", "1", "Toplam Uygunsuzluk", "+1 bu ay", Icons.Outlined.BookmarkBorder, NovaColorToken.statusInfoDot, NovaDestination.findings),
    NovaMetricItem("open", "1", "Açık Uygunsuzluk", "1 gecikmiş", Icons.Outlined.WarningAmber, NovaColorToken.statusDangerDot, NovaDestination.findings),
    NovaMetricItem("companies", "1", "Firma", "Atanmış firma", Icons.Outlined.Business, NovaColorToken.statusInfoDot, NovaDestination.companies),
    NovaMetricItem("visits", "1", "Ziyaret Sayısı", "1 bu ay", Icons.Outlined.Place, NovaColorToken.statusWarningDot, NovaDestination.visits),
    NovaMetricItem("training", "0", "Eğitim Süresi Geçen", "personel", Icons.Outlined.Schedule, NovaColorToken.statusDangerDot, NovaDestination.training)
), "Yeni firma atandı · Koza Altın A.Ş · Ahmet Bel · Uzman atandı", "Yaklaşan veya geçmiş eğitim uyarısı yok")
