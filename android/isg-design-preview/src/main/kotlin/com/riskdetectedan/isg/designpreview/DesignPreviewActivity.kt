package com.riskdetectedan.isg.designpreview

import android.os.Bundle
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.unit.dp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import com.riskdetectedan.core.designsystem.isg.*
import java.util.UUID

/** Offline synthetic host. No Auth, network permission, persistence or real account. */
class DesignPreviewActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Do not run this QA executable on a physical device.
        if (!Build.FINGERPRINT.contains("generic") && !Build.MODEL.contains("sdk_gphone")) { finish(); return }
        enableEdgeToEdge()
        setContent {
            var host by remember { mutableStateOf(readyHost()) }
            var noticeSnapshot by remember { mutableStateOf(host.scope(listOf(
                NovaNotice("overdue", "Termini geçen aksiyonlar", "Geciken düzeltmeleri önceliklendirerek inceleyin.", 1, Icons.Outlined.Warning, NovaColorToken.statusDangerInk),
                NovaNotice("active", "Aktif uygunsuzluklar", "Sorumluluğunuzdaki firmalarda halen açık bulunan kayıtlar.", 1, Icons.Outlined.Notifications, NovaColorToken.statusInfoInk)), host.navigation.epoch)) }
            val state = host.navigation
            val notices = host.value(noticeSnapshot).orEmpty()
            val navigate: (NovaDestination) -> Unit = { host = host.apply(NovaNavigationEvent.Navigate(it), state.epoch) }
            NovaTheme(false) {
                if (host.phase != NovaHostPhase.ready) {
                    NovaText("QA · ${host.phase.name}")
                    return@NovaTheme
                }
                NovaExpertShell(state, "Kerem Kaya", Modifier.safeDrawingPadding(), hasUnread = notices.any { it.unread },
                    connectionLabel = "Çevrimdışı test", notices = notices,
                    onNoticeAction = { action, epoch -> if (host.isCurrent(epoch)) noticeSnapshot = host.scope(if (action == NovaNoticeAction.Clear) emptyList() else host.value(noticeSnapshot).orEmpty().map { it.copy(unread = false) }, epoch) },
                    onLogout = { epoch -> if (host.isCurrent(epoch)) host = host.adopt(null) },
                    onEvent = { event, epoch -> host = host.apply(event, epoch) }) { destination ->
                    when (destination) {
                        NovaDestination.home -> NovaDashboardScreen(dashboard, onNavigate = navigate,
                            onPhoto = { navigate(NovaDestination.newFinding) }, onAssistant = { navigate(NovaDestination.newFinding) })
                        NovaDestination.companies -> NovaCompaniesScreen(listOf(NovaCompanyItem("fixture", "Koza Altın A.Ş", "Kaymaz Mah. · Maden · Çok tehlikeli")),
                            onSelect = { navigate(NovaDestination.memory) }, onBack = { navigate(NovaDestination.home) }, onRetry = {})
                        else -> Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                            NovaPageTitle(destination)
                            NovaCard(Modifier.fillMaxWidth(), padding = 20) {
                                NovaText("Sentetik hedef: ${destination.title}")
                                NovaText("Canlı veri veya işlem yok.", style = NovaTypeToken.meta)
                            }
                        }
                    }
                }
            }
        }
    }
}
private fun readyHost(): NovaSessionHost {
    val actor = NovaSessionIdentity(UUID.fromString("11111111-1111-4111-8111-111111111111"), UUID.fromString("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"))
    val loading = NovaSessionHost(NovaDestination.entries.toSet()).adopt(actor).beginAvailabilityRefresh()
    return loading.resolve(requireNotNull(loading.pending), actor.userID, NovaDestination.entries.toSet())
}
private val dashboard = NovaDashboardData("Kerem", 1, listOf(
    NovaMetricItem("total", "1", "Toplam Uygunsuzluk", "+1 bu ay", Icons.Outlined.BookmarkBorder, NovaColorToken.statusInfoDot, NovaDestination.findings),
    NovaMetricItem("open", "1", "Açık Uygunsuzluk", "1 gecikmiş", Icons.Outlined.WarningAmber, NovaColorToken.statusDangerDot, NovaDestination.findings),
    NovaMetricItem("companies", "1", "Firma", "Atanmış firma", Icons.Outlined.Business, NovaColorToken.statusInfoDot, NovaDestination.companies),
    NovaMetricItem("visits", "1", "Ziyaret Sayısı", "1 bu ay", Icons.Outlined.Place, NovaColorToken.statusWarningDot, NovaDestination.visits),
    NovaMetricItem("training", "0", "Eğitim Süresi Geçen", "personel", Icons.Outlined.Schedule, NovaColorToken.statusDangerDot, NovaDestination.training)
), "Yeni firma atandı · Koza Altın A.Ş · Ahmet Bel · Uzman atandı", "Yaklaşan veya geçmiş eğitim uyarısı yok")
