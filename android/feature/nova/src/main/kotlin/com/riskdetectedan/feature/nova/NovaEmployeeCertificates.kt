package com.riskdetectedan.feature.nova

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.nova.NovaTrainingService
import com.riskdetectedan.core.data.nova.NovaTrainingSession
import com.riskdetectedan.core.data.nova.NovaTrainingWords
import com.riskdetectedan.core.data.nova.sameId
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** What the certificate list reads: one company's training sessions, page by page, and the training client itself. */
class NovaEmployeeCertificatesClient(
    internal val sessions: suspend (company: String, after: String?) -> NovaTrainingService.Page,
    internal val training: NovaTrainingClient,
)

/**
 * Sertifika ve belgeler (iOS `NovaEmployeeCertificatesScreen`): only the training records this person took part in,
 * each opening its certificate; the other personnel documents keep their own destination through [otherDocuments].
 */
@Composable
internal fun NovaEmployeeCertificatesScreen(client: NovaEmployeeCertificatesClient, company: String, employee: String, canWrite: Boolean,
                                            onBack: () -> Unit, otherDocuments: @Composable (onBack: () -> Unit) -> Unit) {
    class Entry(val session: NovaTrainingSession, val scopeId: String)
    class Selection(val session: NovaTrainingSession, val scopeId: String, val documentId: String?, val revision: Int?)
    val coroutines = rememberCoroutineScope()
    var entries by remember { mutableStateOf(emptyList<Entry>()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var selection by remember { mutableStateOf<Selection?>(null) }
    var others by remember { mutableStateOf(false) }
    LaunchedEffect(company, employee) {
        loading = true; error = null
        try {
            val rows = mutableListOf<Entry>()
            var after: String? = null
            val seen = mutableSetOf<String>()
            do {
                val page = client.sessions(company, after)
                page.rows.forEach { session ->
                    session.education?.scopes.orEmpty().filter { scope ->
                        scope.companyId.sameId(company) && scope.participants.any { it.id.sameId(employee) }
                    }.forEach { rows += Entry(session, it.id) }
                }
                after = page.nextId
                if (after != null && !seen.add(after)) throw IllegalStateException("Repeated training page")
            } while (after != null)
            entries = rows.sortedByDescending { it.session.heldOn }
        } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) {
            error = NovaTrainingWords.message(failure)
        }
        loading = false
    }
    val chosen = selection
    if (chosen != null) {
        NovaEducationCertificateScreen(client.training, chosen.session, chosen.scopeId, employee, canWrite, chosen.documentId, chosen.revision) {
            selection = null
        }
        return
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            NovaText("Sertifika ve belgeler", Modifier.weight(1f), NovaTypeToken.screenTitle)
            NovaText("Bitti", Modifier.novaPress(onClick = onBack).padding(horizontal = 6.dp, vertical = 10.dp), NovaTypeToken.bodyStrong,
                color = NovaColorToken.accentInk.color())
        }
        if (loading) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { NovaSpinner(NovaColorToken.text.color(), size = 22.dp) }
        error?.let { NovaHelpHint(it) }
        if (!loading && entries.isEmpty() && error == null) NovaEmptyState("Eğitim sertifikası yok",
            "Bu personelin yer aldığı bir eğitim kaydı henüz bulunamadı.")
        entries.forEach { entry ->
            NovaCard(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress {
                coroutines.launch {
                    try {
                        val context = client.training.context(entry.session.id)
                        val session = context.row ?: throw IllegalStateException("Training record unavailable")
                        val document = context.certificates.firstOrNull {
                            it.scopeId.sameId(entry.scopeId) && it.personId.sameId(employee) && it.sourceSessionRevision == session.version
                        }
                        selection = Selection(session, entry.scopeId, document?.documentId, document?.revision)
                    } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) {
                        error = NovaTrainingWords.message(failure)
                    }
                }
            }.testTag("personnel.certificate.${entry.session.id}.${entry.scopeId}"), padding = 14) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("graduationcap", 18.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        NovaText(entry.session.title, style = NovaTypeToken.bodyStrong)
                        NovaText(entry.session.heldOn, style = NovaTypeToken.metaQuiet)
                    }
                    NovaIcon("chevron.right", 12.dp)
                }
            }
        }
        NovaCompactActionButton("Diğer belgeler", "doc.text", identifier = "personnel.certificates.other") { others = true }
    }
    NovaPopup(others, { others = false }, identifier = "personnel.certificates.other.popup", scrollable = false) {
        Box(Modifier.fillMaxWidth().heightIn(min = 420.dp, max = 680.dp)) { otherDocuments { others = false } }
    }
}
