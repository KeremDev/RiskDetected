package com.riskdetectedan.core.designsystem.isg

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

object NovaSuccessMessage {
    const val companyCreated = "Firma başarıyla eklendi!"
    const val companyUpdated = "Firma bilgileri başarıyla güncellendi!"
    const val companyLogoAdded = "Firma logosu başarıyla eklendi!"
    const val personnelCreated = "Personel başarıyla eklendi!"
    const val personnelUpdated = "Personel bilgileri başarıyla güncellendi!"
    const val personnelArchived = "Personel başarıyla arşivlendi!"
    const val findingCreated = "Uygunsuzluk başarıyla eklendi!"
    const val trainingSaved = "Eğitim başarıyla kaydedildi!"
    const val emergencyPlanSaved = "Acil durum planı başarıyla kaydedildi!"
    const val periodicInspectionSaved = "Periyodik kontrol başarıyla kaydedildi!"
    const val equipmentCreated = "Ekipman başarıyla eklendi!"
    const val fileAdded = "Dosya başarıyla eklendi!"
    fun recordSaved(name: String) = "$name başarıyla kaydedildi!"

    /** Server receipts carry stable keys so a mutation cannot inject presentation text. */
    fun serverKey(key: String) = when (key) {
        "analysis_finding_filed" -> findingCreated
        "analysis_finding_already_filed" -> "Bu uygunsuzluk firmada zaten kayıtlı."
        "ppe_handover_created" -> recordSaved("KKD zimmeti")
        else -> "İşlem başarıyla tamamlandı!"
    }

    fun normalized(text: String): String {
        val value = text.trim()
        if (value.isEmpty()) return "İşlem başarıyla tamamlandı!"
        return if (value.last() == '!' || value.last() == '.') value else "$value!"
    }
}

/** One session-owned event that survives a form closing and shows above an open popup. */
@Stable
class NovaSuccessStore {
    data class Event(val id: String = UUID.randomUUID().toString(), val text: String)
    var event by mutableStateOf<Event?>(null)
    fun show(text: String) { event = Event(text = NovaSuccessMessage.normalized(text)) }
}

val LocalNovaSuccessStore = staticCompositionLocalOf<NovaSuccessStore?> { null }

/** `novaCelebrate` — call after a record is committed. */
@Composable
fun rememberNovaCelebrate(): (String) -> Unit {
    val store = LocalNovaSuccessStore.current
    return remember(store) { { text: String -> store?.show(text) } }
}

/** Installs the store for a session and draws its overlay above [content]. */
@Composable
fun NovaSuccessPresentation(account: String?, content: @Composable () -> Unit) {
    val store = remember(account) { NovaSuccessStore() }
    CompositionLocalProvider(LocalNovaSuccessStore provides store) {
        Box(Modifier.fillMaxSize()) {
            content()
            NovaSuccessOverlay(store)
        }
    }
}

/**
 * The "Tebrikler" card. Arrives with the one overshoot spring, fires the one
 * success haptic on the same frame, leaves the way it arrived. The confetti
 * has its own one-shot trigger so the exit never plays it backwards.
 */
@Composable
fun NovaSuccessOverlay(store: NovaSuccessStore) {
    val event = store.event ?: return
    val reduceMotion = rememberNovaReduceMotion()
    val view = LocalView.current
    val appear = remember(event.id) { Animatable(0f) }
    val burst = remember(event.id) { Animatable(0f) }
    LaunchedEffect(event.id) {
        launch { appear.animateTo(1f, NovaMotion.gated(NovaMotion.celebrate(), reduceMotion)) }
        if (!reduceMotion) launch { burst.animateTo(1f, tween(1400, easing = NovaMotion.EaseOutCurve)) }
        NovaHaptics.success(view)
        view.announceForAccessibility(event.text)
        delay(2300)
        if (store.event?.id != event.id) return@LaunchedEffect
        appear.animateTo(0f, NovaMotion.easeOut(NovaMotion.Duration.popover))
        delay(20)
        if (store.event?.id == event.id) store.event = null
    }
    val shown = appear.value.coerceIn(0f, 1.2f)
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.30f * appear.value.coerceIn(0f, 1f)))
        .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Assertive }.testTag("nova.success"),
        contentAlignment = Alignment.Center) {
        NovaCard(Modifier.widthIn(max = 300.dp).padding(24.dp).graphicsLayer {
            val scale = if (reduceMotion) 1f else 0.9f + 0.1f * shown
            scaleX = scale; scaleY = scale
            alpha = appear.value.coerceIn(0f, 1f)
        }, padding = 24) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(contentAlignment = Alignment.Center) {
                    Row(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.CenterVertically) {
                        NovaIcon("sparkles", 18.dp, tint = Color(0xFFFF9500))
                        NovaIcon("checkmark.seal", 44.dp, tint = NovaColorToken.accentInk.color())
                        NovaIcon("party.popper", 18.dp, tint = Color(0xFFAF52DE))
                    }
                    if (!reduceMotion) {
                        val accent = NovaColorToken.accent.color()
                        val ink = NovaColorToken.text.color().copy(alpha = 0.3f)
                        repeat(12) { index ->
                            val stagger = (index % 3) * 0.06f
                            val t = ((burst.value - stagger) / (1f - stagger)).coerceIn(0f, 1f)
                            Box(Modifier.size(4.dp, 7.dp).graphicsLayer {
                                rotationZ = t * index * 37f
                                translationX = t * (index - 6) * 17f * density
                                translationY = t * (((index * 23) % 80) - 35f) * density
                                alpha = 0.9f * (1f - t)
                            }.background(if (index % 3 == 0) accent else ink, RoundedCornerShape(1.dp)))
                        }
                    }
                }
                NovaText("Tebrikler", style = NovaTypeToken.sectionTitle)
                NovaText(event.text, style = NovaTypeToken.cardTitle, textAlign = TextAlign.Center)
            }
        }
    }
}

