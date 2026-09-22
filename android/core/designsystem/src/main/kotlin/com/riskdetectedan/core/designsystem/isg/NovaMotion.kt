package com.riskdetectedan.core.designsystem.isg

import android.provider.Settings
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.pow

/**
 * The one motion scale for every İSGADA surface — the Android counterpart of
 * iOS `NovaMotion.swift`, value for value.
 *
 * Nothing eases in, UI motion stays under 300 ms, and Reduce Motion means
 * gentler rather than none: travel and overshoot go, a short fade stays.
 */
object NovaMotion {
    object Duration {
        const val press = 0.16
        const val popover = 0.18
        const val dropdown = 0.22
        const val progress = 0.28
        const val modal = 0.32
        const val reduced = 0.12
        const val entranceWindow = 0.6
    }

    val EaseOutCurve = CubicBezierEasing(0.23f, 1f, 0.32f, 1f)
    val EaseInOutCurve = CubicBezierEasing(0.77f, 0f, 0.175f, 1f)
    val DrawerCurve = CubicBezierEasing(0.32f, 0.72f, 0f, 1f)

    fun <T> easeOut(duration: Double = Duration.dropdown, delay: Double = 0.0): FiniteAnimationSpec<T> =
        tween(millis(duration), millis(delay), EaseOutCurve)
    fun <T> easeInOut(duration: Double = Duration.dropdown): FiniteAnimationSpec<T> =
        tween(millis(duration), easing = EaseInOutCurve)
    fun <T> drawer(duration: Double = Duration.modal): FiniteAnimationSpec<T> =
        tween(millis(duration), easing = DrawerCurve)

    /** SwiftUI `spring(response:dampingFraction:)` has the same two-parameter model. */
    fun <T> spring(response: Double, dampingFraction: Double): FiniteAnimationSpec<T> =
        androidx.compose.animation.core.spring(dampingRatio = dampingFraction.toFloat(),
            stiffness = (2 * PI / response).pow(2).toFloat())

    fun <T> move(): FiniteAnimationSpec<T> = spring(0.4, 1.0)
    fun <T> press(): FiniteAnimationSpec<T> = spring(0.22, 1.0)
    fun <T> momentum(): FiniteAnimationSpec<T> = spring(0.34, 0.8)
    fun <T> sheet(): FiniteAnimationSpec<T> = spring(0.3, 0.8)
    fun <T> celebrate(): FiniteAnimationSpec<T> = spring(0.35, 0.72)

    fun <T> gated(spec: FiniteAnimationSpec<T>, reduceMotion: Boolean): FiniteAnimationSpec<T> =
        if (reduceMotion) tween(millis(Duration.reduced)) else spec

    fun <T> stopped(spec: FiniteAnimationSpec<T>, reduceMotion: Boolean): FiniteAnimationSpec<T> =
        if (reduceMotion) snap() else spec

    internal fun millis(seconds: Double) = (seconds * 1000).toInt()
}

/**
 * Android has no single "Reduce Motion" switch; "Remove animations" sets the
 * animator duration scale to zero, which is the closest equivalent and the one
 * TalkBack users are pointed to.
 */
val LocalNovaReduceMotion = compositionLocalOf<Boolean?> { null }

@Composable
fun rememberNovaReduceMotion(): Boolean {
    LocalNovaReduceMotion.current?.let { return it }
    val context = LocalContext.current
    return remember(context) {
        runCatching {
            Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
        }.getOrDefault(false)
    }
}

/** Haptics for the moments that earn one, fired on the same frame as the visual. */
object NovaHaptics {
    fun selection(view: View) { view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK) }
    fun impact(view: View) { view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY) }
    fun success(view: View) {
        view.performHapticFeedback(if (android.os.Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM
            else HapticFeedbackConstants.VIRTUAL_KEY)
    }
    fun warning(view: View) { view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS) }
    fun failure(view: View) {
        view.performHapticFeedback(if (android.os.Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.REJECT
            else HapticFeedbackConstants.LONG_PRESS)
    }
}

@Composable
fun rememberNovaHaptics(): NovaHapticsHandle {
    val view = LocalView.current
    return remember(view) { NovaHapticsHandle(view) }
}

class NovaHapticsHandle internal constructor(private val view: View) {
    fun selection() = NovaHaptics.selection(view)
    fun impact() = NovaHaptics.impact(view)
    fun success() = NovaHaptics.success(view)
    fun warning() = NovaHaptics.warning(view)
    fun failure() = NovaHaptics.failure(view)
}

/**
 * Press feedback for compact controls (`NovaPressStyle`): scale from touch-down,
 * dim a little. Reduce Motion keeps the dim and drops the scale.
 */
fun Modifier.novaPress(enabled: Boolean = true, scale: Float = 0.97f, pressedAlpha: Float = 0.85f,
                       role: Role? = Role.Button, onClickLabel: String? = null, onClick: () -> Unit): Modifier =
    composed {
        val source = remember { MutableInteractionSource() }
        novaPressFeedback(source, scale, pressedAlpha, 0L)
            .clickable(source, null, enabled = enabled, onClickLabel = onClickLabel, role = role, onClick = onClick)
    }

/**
 * Press feedback for full-width rows and tiles (`NovaRowPressStyle`): dim only,
 * held back 50 ms so a touch that becomes a scroll never flashes the row.
 */
fun Modifier.novaRowPress(enabled: Boolean = true, pressedAlpha: Float = 0.62f, pressDelayMillis: Long = 50,
                          role: Role? = Role.Button, onClickLabel: String? = null, onClick: () -> Unit): Modifier =
    composed {
        val source = remember { MutableInteractionSource() }
        novaPressFeedback(source, 1f, pressedAlpha, pressDelayMillis)
            .clickable(source, null, enabled = enabled, onClickLabel = onClickLabel, role = role, onClick = onClick)
    }

fun Modifier.novaPressFeedback(source: MutableInteractionSource, scale: Float, pressedAlpha: Float,
                               pressDelayMillis: Long): Modifier = composed {
    val reduceMotion = rememberNovaReduceMotion()
    var pressed by remember { mutableStateOf(false) }
    LaunchedEffect(source, pressDelayMillis) {
        var pressJob: Job? = null
        source.interactions.collect { interaction ->
            when (interaction) {
                is PressInteraction.Press -> {
                    pressJob?.cancel()
                    pressJob = launch {
                        if (pressDelayMillis > 0) delay(pressDelayMillis)
                        pressed = true
                    }
                }
                is PressInteraction.Release, is PressInteraction.Cancel -> {
                    pressJob?.cancel()
                    pressJob = null
                    pressed = false
                }
            }
        }
    }
    val progress by animateFloatAsState(if (pressed) 1f else 0f, NovaMotion.press(), label = "novaPress")
    graphicsLayer {
        val s = if (reduceMotion) 1f else 1f - (1f - scale) * progress
        scaleX = s; scaleY = s
        alpha = 1f - (1f - pressedAlpha) * progress
    }
}

/** True only during the short window after a list's first records land. */
val LocalNovaRowEntranceActive = staticCompositionLocalOf { false }

/**
 * Opens the entrance window once per screen. Later refreshes, pulls and saves
 * never re-deal the rows.
 */
@Composable
fun NovaListEntrance(hasRecords: Boolean, content: @Composable () -> Unit) {
    var open by remember { mutableStateOf(false) }
    var spent by remember { mutableStateOf(false) }
    LaunchedEffect(hasRecords) {
        if (hasRecords && !spent) {
            spent = true
            open = true
            delay(NovaMotion.millis(NovaMotion.Duration.entranceWindow).toLong())
            open = false
        }
    }
    CompositionLocalProvider(LocalNovaRowEntranceActive provides open, content = content)
}

/** A short rise and fade, staggered by position, for the first screenful only. */
fun Modifier.novaRowEntrance(index: Int): Modifier = composed {
    val active = LocalNovaRowEntranceActive.current
    val reduceMotion = rememberNovaReduceMotion()
    val staggered = remember { active && index < 8 }
    var shown by remember { mutableStateOf(!staggered) }
    LaunchedEffect(Unit) { if (staggered) shown = true }
    val spec: AnimationSpec<Float> = NovaMotion.gated(
        NovaMotion.easeOut(0.26, delay = index * 0.045), reduceMotion)
    val progress by animateFloatAsState(if (shown) 1f else 0f, spec, label = "novaRowEntrance")
    graphicsLayer {
        alpha = progress
        translationY = if (reduceMotion) 0f else (1f - progress) * 8f * density
    }
}
