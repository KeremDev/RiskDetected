package com.riskdetectedan.core.designsystem.isg

import androidx.compose.runtime.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.util.UUID

/** The caller injects the existing repository adapter; this module knows no SDK or endpoint. */
@Composable
fun NovaCompanyDestination(host: NovaSessionHost, loadCompanies: suspend (Boolean) -> List<NovaOwnedCompany>,
                           includeArchived: Boolean = false, onSelect: (UUID) -> Unit, onBack: () -> Unit) {
    var state by remember { mutableStateOf(NovaCompanyListState()) }
    var refresh by remember { mutableStateOf(UUID.randomUUID()) }
    val currentHost by rememberUpdatedState(host)
    val currentLoader by rememberUpdatedState(loadCompanies)
    val currentArchiveScope by rememberUpdatedState(includeArchived)
    val content = state.content(host, includeArchived)
    val epoch = host.navigation.epoch
    LaunchedEffect(epoch, includeArchived, refresh) {
        state = state.begin(currentHost, includeArchived)
        val ticket = state.pending ?: return@LaunchedEffect
        try {
            val rows = currentLoader(includeArchived)
            currentCoroutineContext().ensureActive()
            state = state.complete(ticket, rows, currentHost)
        } catch (cancelled: CancellationException) {
            state = state.cancel(ticket, currentHost)
            throw cancelled
        } catch (_: Exception) {
            currentCoroutineContext().ensureActive()
            state = state.fail(ticket, currentHost)
        }
    }
    key(epoch) { // Reset rememberSaveable search/focus when the account/permission scope changes.
    NovaCompaniesScreen(companies = content.rows.map { NovaCompanyItem(it.id.toString(), it.name, it.detail) },
        isLoading = content.phase == NovaCompanyListPhase.loading || content.phase == NovaCompanyListPhase.idle,
        error = if (content.phase == NovaCompanyListPhase.failed) "Firmalar yüklenemedi. Lütfen tekrar deneyin." else null,
        isOwnedList = true,
        onSelect = { raw ->
            val id = runCatching { UUID.fromString(raw) }.getOrNull()
            val row = id?.let { state.select(it, content.requestID, currentHost, currentArchiveScope) }
            if (row != null) onSelect(row.id)
        }, onBack = { if (currentHost.isCurrent(epoch)) onBack() },
        onRetry = { if (currentHost.isCurrent(epoch)) refresh = UUID.randomUUID() })
    }
}
