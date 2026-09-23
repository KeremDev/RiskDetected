package com.riskdetectedan.feature.onboarding.nova

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.isg.novaPress
import com.riskdetectedan.core.designsystem.isg.novaRowPress
import com.riskdetectedan.core.designsystem.isg.rememberNovaHaptics
import com.riskdetectedan.feature.onboarding.R
import kotlin.math.roundToInt

/** The eleven-step questionnaire: sticky progress header, one of five answer widgets, sticky footer. */
@Composable
internal fun NovaOBQuestionScreen(controller: NovaOnboardingController) {
    val focus = LocalFocusManager.current
    val question = controller.question
    Column(Modifier.fillMaxSize().background(NovaOB.surface)) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = obPadTop(60f), bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                ObBackButton(Modifier.offset(x = (-12).dp)) { controller.back() }
                val progress by animateFloatAsState(controller.progress, tween(280, easing = CubicBezierEasing(0.2f, 0.8f, 0.25f, 1f)),
                    label = "ob-progress")
                Box(Modifier.weight(1f).height(4.dp).clip(CircleShape).background(NovaOB.line)) {
                    Box(Modifier.fillMaxHeight().fillMaxWidth(progress).clip(CircleShape).background(NovaOB.ink))
                }
                ObText(controller.stepLabel, 13.5f, Modifier.widthIn(min = 44.dp), color = NovaOB.muted, align = TextAlign.End)
            }
            ObText(controller.sectionLabel, 11.5f, weight = 600, tracking = 1.495f)
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(top = 4.dp, bottom = 8.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ObText(question.title, 28f, weight = 700, lineHeight = 1.2f, tracking = -0.3f)
                if (question.desc.isNotEmpty()) ObText(question.desc, 15.5f, color = NovaOB.muted, lineHeight = 1.45f)
            }
            when (question.kind) {
                NovaOBQuestionKind.Text -> NovaOBNameWidget(controller)
                NovaOBQuestionKind.Single, NovaOBQuestionKind.Multi -> NovaOBChoiceWidget(controller)
                NovaOBQuestionKind.Slider -> NovaOBExperienceWidget(controller)
                NovaOBQuestionKind.Counter -> NovaOBCounterWidget(controller)
            }
        }
        Column(Modifier.fillMaxWidth().background(NovaOB.surface).padding(horizontal = 24.dp).padding(top = 10.dp, bottom = obPadBottom(34f)),
            verticalArrangement = Arrangement.spacedBy(6.dp)) {
            ObPrimaryButton(controller.primaryLabel, enabled = controller.canContinue) {
                focus.clearFocus()
                controller.next()
            }
            if (question.skippable) {
                Box(Modifier.fillMaxWidth().height(44.dp).novaPress { focus.clearFocus(); controller.skipQuestion() },
                    contentAlignment = Alignment.Center) {
                    ObText("Şimdilik geç", 15f, color = NovaOB.muted)
                }
            }
        }
    }
}

@Composable
private fun NovaOBNameWidget(controller: NovaOnboardingController) {
    val name = controller.answers.name.trim()
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        ObField(controller.answers.name, controller::setName, "Adın veya tercih ettiğin isim", height = 60f, radius = 18f, fontSize = 18f)
        Box(Modifier.padding(top = 64.dp, bottom = 20.dp)) {
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(NovaOB.fill).padding(horizontal = 18.dp, vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)) {
                ObText("ÖNİZLEME", 12f, tracking = 1.2f)
                ObText(if (name.isEmpty()) "Merhaba" else "Merhaba, $name", 20f, weight = 600)
            }
            Image(painterResource(R.drawable.nova_ob_mascot), null, Modifier.offset(x = 16.dp, y = (-54).dp).size(64.dp, 61.dp))
        }
    }
}

// MARK: - Choice widget (single + multi, list + grid)

@Composable
private fun NovaOBChoiceWidget(controller: NovaOnboardingController) {
    val question = controller.question
    val haptics = rememberNovaHaptics()
    val options = controller.visibleOptions
    val gridOptions = if (question.grid) options.filter { !it.small } else emptyList()
    val rowOptions = if (question.grid) options.filter { it.small } else options
    fun toggle(option: NovaOBOption) {
        haptics.selection()
        if (question.kind == NovaOBQuestionKind.Single) controller.pickSingle(option.value) else controller.toggleMulti(option.value)
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (question.searchable) ObField(controller.search, { controller.search = it }, "Sektör ara", height = 42f, fontSize = 16f,
            focusBorder = NovaOB.line)
        if (controller.selectionNote.isNotEmpty()) ObText(controller.selectionNote, 13.5f)
        if (gridOptions.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                gridOptions.chunked(question.gridColumns).forEach { row ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        row.forEach { option -> NovaOBGridCell(controller, option, Modifier.weight(1f)) { toggle(option) } }
                        repeat(question.gridColumns - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }
        rowOptions.forEach { option -> NovaOBListRow(controller, option) { toggle(option) } }
        if (controller.showsOtherField) {
            ObField(controller.answers.other(question.id), controller::setOther, "Kısaca yazabilirsin", height = 52f, fontSize = 16f,
                idleBorder = NovaOB.ink)
        }
    }
}

@Composable
private fun NovaOBGridCell(controller: NovaOnboardingController, option: NovaOBOption, modifier: Modifier, onClick: () -> Unit) {
    val selected = controller.isSelected(option.value)
    val shape = RoundedCornerShape(14.dp)
    val background by animateColorAsState(if (selected) NovaOB.fill else NovaOB.surface, tween(140), label = "ob-cell-bg")
    val border by animateColorAsState(if (selected) NovaOB.ink else NovaOB.line, tween(140), label = "ob-cell-border")
    Box(modifier.heightIn(min = 72.dp).alpha(if (controller.isBlocked(option.value)) 0.45f else 1f).clip(shape).background(background)
        .border(1.5.dp, border, shape).novaRowPress(pressedAlpha = 0.7f, onClick = onClick)) {
        Column(Modifier.fillMaxWidth().padding(11.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            ObIcon(option.icon, 23f, NovaOB.ink, lineWidth = 1.6f)
            ObText(option.label, 14f, Modifier.padding(end = 20.dp), weight = 600, lineHeight = 1.2f)
            if (option.sub.isNotEmpty()) ObText(option.sub, 12f, color = NovaOB.muted, lineHeight = 1.15f)
            if (controller.isSuggested(option)) ObText("Sana uygun olabilir", 11.5f)
        }
        NovaOBMark(selected, controller.question.kind == NovaOBQuestionKind.Multi, 18f, 12f, Modifier.align(Alignment.TopEnd).padding(8.dp))
    }
}

@Composable
private fun NovaOBListRow(controller: NovaOnboardingController, option: NovaOBOption, onClick: () -> Unit) {
    val selected = controller.isSelected(option.value)
    val shape = RoundedCornerShape(16.dp)
    val background by animateColorAsState(if (selected) NovaOB.fill else NovaOB.surface, tween(140), label = "ob-row-bg")
    val border by animateColorAsState(if (selected) NovaOB.ink else NovaOB.line, tween(140), label = "ob-row-border")
    Row(Modifier.fillMaxWidth().heightIn(min = 66.dp).alpha(if (controller.isBlocked(option.value)) 0.45f else 1f).clip(shape)
        .background(background).border(1.5.dp, border, shape).novaRowPress(pressedAlpha = 0.7f, onClick = onClick)
        .padding(horizontal = 16.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        ObIcon(option.icon, 30f, NovaOB.ink, lineWidth = 1.5f)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            ObText(option.label, 17f, weight = 600, lineHeight = 1.25f)
            if (option.sub.isNotEmpty()) ObText(option.sub, 13.5f, color = NovaOB.muted, lineHeight = 1.25f)
            if (controller.isSuggested(option)) ObText("Sana uygun olabilir", 12f)
        }
        NovaOBMark(selected, controller.question.kind == NovaOBQuestionKind.Multi, 24f, 15f)
    }
}

/** Radio (single) or rounded check box (multi) with the prototype's check glyph. */
@Composable
private fun NovaOBMark(selected: Boolean, multi: Boolean, size: Float, check: Float, modifier: Modifier = Modifier) {
    val shape = if (multi) RoundedCornerShape(8.dp) else CircleShape
    Box(modifier.size(size.dp).clip(shape).background(if (selected) NovaOB.ink else NovaOB.surface)
        .border(1.5.dp, if (selected) NovaOB.ink else NovaOB.line2, shape), contentAlignment = Alignment.Center) {
        if (selected) ObIcon(NovaOB.CHECK, check, Color.White, lineWidth = 2.2f, viewBox = 14f)
    }
}

// MARK: - Experience slider

@Composable
private fun NovaOBExperienceWidget(controller: NovaOnboardingController) {
    val answers = controller.answers
    var dragPosition by remember { mutableStateOf<Float?>(null) }
    val position = dragPosition ?: (answers.exp?.let { it / 3f } ?: 0f)
    val liveIndex = dragPosition?.let { (it * 3).roundToInt() } ?: answers.exp
    val tint = when {
        answers.expLess -> NovaOB.ink
        liveIndex == null -> NovaOB.line2
        else -> NovaOB.stopTint[liveIndex]
    }
    val valueLabel = when {
        answers.expLess -> "1 yıldan az"
        liveIndex == null -> "Henüz seçilmedi"
        else -> NovaOBCatalogue.experienceStops[liveIndex].first
    }
    val valueSub = when {
        answers.expLess -> "Mesleğe yeni başladın"
        liveIndex == null -> "Sürükle veya bir durağa dokun"
        else -> NovaOBCatalogue.experienceStops[liveIndex].second
    }
    Column(verticalArrangement = Arrangement.spacedBy(22.dp)) {
        val cardShape = RoundedCornerShape(22.dp)
        Column(Modifier.fillMaxWidth().clip(cardShape).background(NovaOB.surface).border(1.5.dp, NovaOB.line, cardShape)
            .padding(start = 22.dp, end = 22.dp, top = 24.dp, bottom = 26.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                ObText("DENEYİM ARALIĞIN", 12f, color = NovaOB.muted, tracking = 1.2f)
                ObText(valueLabel, 34f, weight = 700, tracking = -0.8f, color = when {
                    answers.expLess -> NovaOB.ink
                    liveIndex == null -> NovaOB.disabled
                    else -> NovaOB.stopTint[liveIndex]
                })
                ObText(valueSub, 14f, Modifier.heightIn(min = 20.dp), color = NovaOB.muted)
            }
            BoxWithConstraints(Modifier.fillMaxWidth().height(56.dp)) {
                val available = maxOf(1f, maxWidth.value - 16f)
                val pixelsPerDp = LocalDensity.current.density
                fun ratio(x: Float) = ((x / pixelsPerDp - 8f) / available).coerceIn(0f, 1f)
                Box(Modifier.fillMaxSize()
                    .pointerInput(available) {
                        detectTapGestures { offset -> controller.pickStop((ratio(offset.x) * 3).roundToInt()) }
                    }
                    .pointerInput(available) {
                        detectDragGestures(
                            onDragStart = { offset -> dragPosition = ratio(offset.x) },
                            onDragEnd = { dragPosition?.let { controller.pickStop((it * 3).roundToInt()) }; dragPosition = null },
                            onDragCancel = { dragPosition = null },
                        ) { change, _ -> dragPosition = ratio(change.position.x) }
                    }) {
                    Box(Modifier.align(Alignment.CenterStart).padding(horizontal = 8.dp).fillMaxWidth().height(8.dp).clip(CircleShape)
                        .background(NovaOB.fill))
                    Box(Modifier.align(Alignment.CenterStart).offset(x = 8.dp).width((position * available).dp).height(8.dp).clip(CircleShape)
                        .background(tint))
                    repeat(4) { index ->
                        val reached = !answers.expLess && liveIndex != null && index <= liveIndex
                        Box(Modifier.align(Alignment.CenterStart).offset(x = (8f + index / 3f * available - 5f).dp).size(10.dp).clip(CircleShape)
                            .background(if (reached) Color.White else NovaOB.stopTint[index]))
                    }
                    Box(Modifier.align(Alignment.CenterStart).offset(x = (8f + position * available - 16f).dp)
                        .shadow(6.dp, CircleShape, ambientColor = Color(0xFF1C292E).copy(alpha = 0.18f), spotColor = Color(0xFF1C292E).copy(alpha = 0.18f))
                        .size(32.dp).clip(CircleShape).background(NovaOB.surface).border(3.dp, tint, CircleShape))
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                listOf("1", "3", "7", "10+").forEach { ObText(it, 12.5f, color = NovaOB.muted) }
            }
        }
        val rowShape = RoundedCornerShape(18.dp)
        Row(Modifier.fillMaxWidth().heightIn(min = 60.dp).clip(rowShape).background(if (answers.expLess) NovaOB.fill else NovaOB.surface)
            .border(1.5.dp, if (answers.expLess) NovaOB.ink else NovaOB.line, rowShape)
            .novaRowPress(pressedAlpha = 0.7f) { controller.toggleLessThanYear() }.padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically) {
            ObText("1 yıldan az", 16.5f, Modifier.weight(1f), weight = 600)
            Box(Modifier.size(26.dp).clip(CircleShape).background(if (answers.expLess) NovaOB.ink else NovaOB.surface)
                .border(1.5.dp, if (answers.expLess) NovaOB.ink else NovaOB.line2, CircleShape), contentAlignment = Alignment.Center) {
                if (answers.expLess) ObIcon(NovaOB.CHECK, 14f, Color.White, lineWidth = 2.2f, viewBox = 14f)
            }
        }
    }
}

// MARK: - Inspection counter

@Composable
private fun NovaOBCounterWidget(controller: NovaOnboardingController) {
    val count = controller.answers.inspections
    var editing by remember { mutableStateOf(false) }
    var text by remember { mutableStateOf("") }
    val requester = remember { FocusRequester() }
    LaunchedEffect(editing) { if (editing) requester.requestFocus() }
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        val shape = RoundedCornerShape(22.dp)
        Column(Modifier.fillMaxWidth().clip(shape).background(NovaOB.surface).border(1.5.dp, NovaOB.line, shape)
            .padding(horizontal = 20.dp, vertical = 26.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaOBStepButton("M4 10h12", if (count == 0) Color(0xFFDCDCDC) else NovaOB.ink, if (count == 0) Color(0xFFC4C4C4) else NovaOB.ink,
                    if (count == 0) 0.6f else 1f) { controller.bumpInspections(-1) }
                if (editing) {
                    BasicTextField(text, { value ->
                        text = value.filter(Char::isDigit)
                        controller.setInspections(text.toIntOrNull() ?: 0)
                    }, Modifier.width(120.dp).height(72.dp).focusRequester(requester).onFocusChanged { if (!it.isFocused) editing = false },
                        textStyle = obStyle(56f, 700).copy(textAlign = TextAlign.Center), singleLine = true, cursorBrush = SolidColor(NovaOB.ink),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { editing = false }),
                        decorationBox = { inner ->
                            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                inner()
                                Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(2.dp).background(NovaOB.ink))
                            }
                        })
                } else {
                    ObText(count.toString(), 62f, Modifier.widthIn(min = 120.dp).novaPress(scale = 1f) { text = count.toString(); editing = true },
                        weight = 700, tracking = -2f, align = TextAlign.Center,
                        color = if ("inspections" in controller.skipped) NovaOB.disabled else NovaOB.ink)
                }
                NovaOBStepButton("M10 4v12M4 10h12", NovaOB.ink, NovaOB.ink, 1f) { controller.bumpInspections(1) }
            }
            ObText(if (count == 0) "Henüz teftiş deneyimim olmadı" else "Son 1 yılda $count teftiş", 15f, color = NovaOB.muted,
                align = TextAlign.Center)
        }
        ObText("Sayıya dokunarak doğrudan yazabilirsin. “0” da geçerli bir yanıttır.", 13f, color = NovaOB.muted, lineHeight = 1.4f)
    }
}

@Composable
private fun NovaOBStepButton(path: String, border: Color, color: Color, opacity: Float, onClick: () -> Unit) {
    Box(Modifier.size(60.dp).alpha(opacity).clip(CircleShape).border(1.5.dp, border, CircleShape).novaPress(onClick = onClick),
        contentAlignment = Alignment.Center) {
        ObIcon(path, 20f, color, lineWidth = 2.2f, viewBox = 20f)
    }
}
