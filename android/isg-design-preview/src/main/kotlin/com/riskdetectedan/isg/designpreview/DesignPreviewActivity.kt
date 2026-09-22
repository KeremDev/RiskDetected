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
                NovaNotice("overdue", "Termini geçen aksiyonlar", "Geciken düzeltmeleri önceliklendirerek inceleyin.", "1 gün gecikti", "exclamationmark.triangle", NovaColorToken.statusDangerInk),
                NovaNotice("active", "Aktif uygunsuzluklar", "Sorumluluğunuzdaki firmalarda halen açık bulunan kayıtlar.", "2 kayıt", "bell", NovaColorToken.statusInfoInk)), host.navigation.epoch)) }
            val state = host.navigation
            val notices = host.value(noticeSnapshot).orEmpty()
            val navigate: (NovaDestination) -> Unit = { host = host.apply(NovaNavigationEvent.Navigate(it), state.epoch) }
            NovaTheme(false) {
                if (host.phase != NovaHostPhase.ready) {
                    NovaText("QA · ${host.phase.name}")
                    return@NovaTheme
                }
                NovaExpertShell(state, "Kerem Kaya", modifier = Modifier.safeDrawingPadding(), hasUnread = notices.any { it.unread },
                    connectionLabel = "Çevrimdışı test", notices = notices,
                    actions = NovaShellActions(
                        onReadAll = { if (host.isCurrent(state.epoch)) noticeSnapshot = host.scope(host.value(noticeSnapshot).orEmpty().map { it.copy(unread = false) }, state.epoch) },
                        onClearNotifications = { if (host.isCurrent(state.epoch)) noticeSnapshot = host.scope(emptyList(), state.epoch) },
                        onLogout = { if (host.isCurrent(state.epoch)) host = host.adopt(null) }),
                    onEvent = { event, epoch -> host = host.apply(event, epoch) }) { destination ->
                    when (destination) {
                        NovaDestination.home -> NovaDashboardScreen(dashboard, onNavigate = navigate,
                            onPhoto = { navigate(NovaDestination.newFinding) }, onAssistant = { navigate(NovaDestination.newFinding) })
                        NovaDestination.findings -> PreviewFindings(board = true, navigate)
                        NovaDestination.newFinding -> PreviewFindings(board = false, navigate)
                        NovaDestination.riskAssessments -> com.riskdetectedan.feature.nova.NovaRiskScreen(PreviewRiskClient, true,
                            onBack = { navigate(NovaDestination.home) })
                        NovaDestination.periodicChecks -> com.riskdetectedan.feature.nova.NovaEquipmentScreen(PreviewEquipmentClient, true,
                            onBack = { navigate(NovaDestination.home) })
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
    NovaMetricItem("total", "1", "Toplam Uygunsuzluk", "+1 bu ay", "bookmark", NovaColorToken.statusInfoDot, NovaDestination.findings),
    NovaMetricItem("open", "1", "Açık Uygunsuzluk", "1 gecikmiş", "exclamationmark.triangle", NovaColorToken.statusDangerDot, NovaDestination.findings),
    NovaMetricItem("companies", "1", "Firma", "Atanmış firma", "building.2", NovaColorToken.statusInfoDot, NovaDestination.companies),
    NovaMetricItem("visits", "1", "Ziyaret Sayısı", "1 bu ay", "mappin", NovaColorToken.statusWarningDot, NovaDestination.visits),
    NovaMetricItem("training", "0", "Eğitim Süresi Geçen", "personel", "clock", NovaColorToken.statusDangerDot, NovaDestination.training)
), "Yeni firma atandı · Koza Altın A.Ş · Ahmet Bel · Uzman atandı", "Yaklaşan veya geçmiş eğitim uyarısı yok")

private val previewCompanies = listOf(
    com.riskdetectedan.core.data.nova.NovaCompanyOption("c1", "Koza Altın A.Ş", "2 işyeri · 48 personel", "Maden"),
    com.riskdetectedan.core.data.nova.NovaCompanyOption("c2", "Işık Lojistik", "1 işyeri · 12 personel", "Lojistik"))

private val previewEntries = listOf(
    com.riskdetectedan.core.data.nova.NovaNonconformityEntry(com.riskdetectedan.core.data.nova.NovaNonconformityRow(
        "11111111-0000-4000-8000-000000000001", "w1", "Korkuluksuz platform kenarı", "high", "open", 1, "2026-09-18",
        "2026-09-20", "analysis_finding", detail = com.riskdetectedan.core.data.nova.NovaNonconformityDetail(
            "Yükleme rampasında korkuluk yok.", "Geçici korkuluk ve uyarı levhası takılsın.", "Yapı İşlerinde İSG Yön. Ek-4",
            "Vardiya amiri", "fine_kinney", 3.0, 6.0, 15.0, riskScore = 270.0, riskBand = "high")),
        "c1", "Koza Altın A.Ş", "Merkez Tesis"),
    com.riskdetectedan.core.data.nova.NovaNonconformityEntry(com.riskdetectedan.core.data.nova.NovaNonconformityRow(
        "11111111-0000-4000-8000-000000000002", "w2", "Yangın tüpü dolum tarihi geçmiş", "medium", "in_progress", 3, "2026-09-10",
        null, "manual", recordKind = "nonconformity"), "c2", "Işık Lojistik", "Depo"),
    com.riskdetectedan.core.data.nova.NovaNonconformityEntry(com.riskdetectedan.core.data.nova.NovaNonconformityRow(
        "11111111-0000-4000-8000-000000000003", "w1", "Kurul toplantılarına saha temsilcisi eklensin", "low", "draft", 0,
        "2026-09-05", null, "manual", recordKind = "improvement"), "c1", "Koza Altın A.Ş", "Koza Altın A.Ş"))

@Composable
private fun PreviewFindings(board: Boolean, navigate: (NovaDestination) -> Unit) {
    var manual by remember { mutableStateOf(false) }
    var record by remember { mutableStateOf<com.riskdetectedan.core.data.nova.NovaNonconformityEntry?>(null) }
    when {
        manual -> com.riskdetectedan.feature.nova.NovaManualNonconformityScreen(previewCompanies,
            workplaces = { listOf(com.riskdetectedan.core.data.nova.NovaNonconformityWorkplace("w1", "Merkez Tesis", false),
                com.riskdetectedan.core.data.nova.NovaNonconformityWorkplace("w3", "Kırma Eleme", false)) },
            save = { _, _ -> "Önizleme: kayıt sunucuya gönderilmedi." }, onBack = { manual = false })
        board -> com.riskdetectedan.feature.nova.NovaNonconformityBoardScreen({ previewEntries }, previewCompanies, "2026-09-22", 0,
            onOpen = { record = it }, onCreate = { navigate(NovaDestination.newFinding) }, onBack = { navigate(NovaDestination.home) })
        else -> com.riskdetectedan.feature.nova.NovaAddFindingScreen(true, {}, { manual = true }, {}, {}, { navigate(NovaDestination.findings) })
    }
    val entry = record
    NovaPopup(entry != null, { record = null }) {
        if (entry != null) com.riskdetectedan.feature.nova.NovaNonconformityRecordSheet(entry,
            com.riskdetectedan.feature.nova.NovaRecordClient({ entry.row }, { _, _, _ -> entry.row }, { _, _ -> entry.row },
                { _, _ -> entry.row }, { entry.row }, { _, _ -> ByteArray(0) }), canWrite = true)
    }
}
