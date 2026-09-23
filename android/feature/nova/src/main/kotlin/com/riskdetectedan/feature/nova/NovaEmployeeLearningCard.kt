package com.riskdetectedan.feature.nova

import androidx.compose.foundation.layout.*
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.nova.NovaEmployeeLearning
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow

private fun lessonHours(minutes: Int) = String.format(java.util.Locale.US, "%.1f", minutes / 45.0).removeSuffix(".0")

/**
 * Eğitim durumu (iOS `NovaEmployeeLearningCard`): actual instruction and missing topics for one person,
 * independent of certificates. [certificates] opens that person's certificate records.
 */
@Composable
fun NovaEmployeeLearningCard(load: suspend () -> NovaEmployeeLearning, changes: Flow<Unit> = emptyFlow(),
                             certificates: @Composable (onBack: () -> Unit) -> Unit) {
    var result by remember { mutableStateOf<NovaEmployeeLearning?>(null) }
    var failed by remember { mutableStateOf(false) }
    var revision by remember { mutableIntStateOf(0) }
    var showCertificates by remember { mutableStateOf(false) }
    LaunchedEffect(changes) { changes.collect { revision++ } }
    LaunchedEffect(revision) {
        result = null; failed = false
        try { result = load() } catch (_: Exception) { failed = true }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaCard(Modifier.fillMaxWidth().testTag("personnel.learning"), padding = 16) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("graduationcap", 16.dp); NovaText("Eğitim durumu", style = NovaTypeToken.cardTitle)
                }
                NovaHelpHint("Gerçekleşen dersler, aynı işyeri ve eğitim kapsamı içinde toplanır. Aralar öğretim süresine eklenmez.")
                val value = result
                when {
                    value != null -> {
                        if (value.groups.isEmpty()) NovaText("Güncel, konu bazlı temel eğitim kaydı yok.")
                        value.groups.forEach { group -> LearningGroup(group) }
                        if (value.expiredScopes > 0) NovaText("Süresi dolan ${value.expiredScopes} kapsam güncel süreye dahil edilmedi.", style = NovaTypeToken.meta)
                        if (value.legacyCompanyRecords > 0) NovaText("Firmanın eski kayıtlarında konu dökümü bulunmuyor; bu kayıtlardan süre aktarılmadı.",
                            style = NovaTypeToken.meta)
                    }
                    failed -> {
                        NovaText("Eğitim durumu alınamadı.", style = NovaTypeToken.meta)
                        NovaText("Yeniden dene", Modifier.novaRowPress { revision++ }, NovaTypeToken.buttonSm, color = NovaColorToken.accentInk.color())
                    }
                    else -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        NovaSpinner(NovaColorToken.text.color(), size = 16.dp); NovaText("Eğitim durumu yükleniyor…", style = NovaTypeToken.meta)
                    }
                }
                NovaText("Bu özet sertifika veya sınav sonucu oluşturmaz.", style = NovaTypeToken.meta)
            }
        }
        NovaButton("Sertifika ve belgeleri", { showCertificates = true }, Modifier.fillMaxWidth().testTag("personnel.certificates"),
            variant = NovaButtonVariant.Surface, symbol = "doc.text")
    }
    NovaPopup(showCertificates, { showCertificates = false }, identifier = "personnel.certificates.popup", scrollable = false) {
        Box(Modifier.fillMaxWidth().heightIn(min = 420.dp, max = 680.dp)) { certificates { showCertificates = false } }
    }
}

@Composable
private fun LearningGroup(group: NovaEmployeeLearning.Group) {
    var topicsOpen by remember { mutableStateOf(false) }
    Column(Modifier.padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        NovaText(group.profile, style = NovaTypeToken.label)
        NovaText(listOfNotNull(group.workplaceName, group.groupName).filter { it.isNotEmpty() }.joinToString(" · "), style = NovaTypeToken.meta)
        LinearProgressIndicator({ minOf(group.receivedMinutes, group.requiredMinutes).toFloat() / maxOf(1, group.requiredMinutes) }, Modifier.fillMaxWidth(),
            color = NovaColorToken.text.color(), trackColor = NovaColorToken.surfaceMuted.color(), drawStopIndicator = {})
        NovaText("${lessonHours(group.receivedMinutes)} / ${lessonHours(group.requiredMinutes)} ders saati · ${lessonHours(group.remainingMinutes)} saat eksik",
            style = NovaTypeToken.label)
        NovaText("${group.receivedMinutes} dk net öğretim. Bir ders saati 45 dk öğretimdir; ara ayrıca tutulur.", style = NovaTypeToken.meta)
        if (group.complete) NovaText("Süre ve konu kapsamı tamam · takip: ${group.validUntil ?: "—"}", style = NovaTypeToken.meta)
        else {
            if (group.group4RemainingMinutes > 0) NovaText("İşyerine özgü konularda ${group.group4RemainingMinutes} dk eksik", style = NovaTypeToken.meta)
            if (group.commonRemainingMinutes > 0) NovaText("Genel, sağlık ve teknik konularda ${group.commonRemainingMinutes} dk eksik", style = NovaTypeToken.meta)
            if (group.missingTopics.isNotEmpty()) {
                Row(Modifier.novaRowPress { topicsOpen = !topicsOpen }, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaText("Eksik konular · ${group.missingTopics.size}", style = NovaTypeToken.meta)
                    NovaIcon(if (topicsOpen) "chevron.up" else "chevron.down", 11.dp)
                }
                if (topicsOpen) Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    group.missingTopics.forEach { NovaText("${it.code} · ${it.title}", style = NovaTypeToken.meta) }
                }
            }
        }
        if (group.excludedSessions > 0) NovaText("${group.excludedSessions} kaydın ders dağılımı düzeltilmeli; süreye katılmadı.", style = NovaTypeToken.meta)
        if (group.contextMissing) NovaText("İşyerine özgü içerik veya eğitim yöntemi eksik; ilgili G4 dakikaları sayılmadı.", style = NovaTypeToken.meta)
    }
}
