package com.riskdetectedan.core.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Presentation-only mirror of `core:data`'s `LegalDocument` — kept as its own tiny type here
 * (not a `project(":core:data")` dependency) so `core:designsystem` stays dependency-free of the
 * data layer, matching every other component in this module. Callers map their real
 * `LegalDocument` list into this with one `.map {}` at the call site. */
data class RdLegalDocument(val kind: String, val title: String, val text: String)

/**
 * Real in-app legal document reader — closes a genuine gap found in the 2026-08-09 gap sweep:
 * Android bundled counsel-reviewed Terms/Privacy/KVKK/Consent text (DEC-10,
 * `android/app/src/main/assets/legal`'s `.md` files) but only ever used it to compute an acceptance
 * checksum — every "Kullanım Koşulları"/"Gizlilik Politikası" label in the app was static,
 * non-clickable text, and there was no way to actually read these documents in-app anywhere
 * (iOS has 5 real trigger points for its equivalent `LegalInfoSheet`: RootView, AuthView,
 * ProfileView, InAppPaywallView, OnboardingViewV2). Mirrors `LegalDocumentReader`'s shape
 * (tab row across document kinds + scrollable plain-text body) — the bundled `.md` files are
 * plain prose with no markdown syntax to render, same as iOS's own plain `Text(document.text)`.
 *
 * [documents] empty means the caller's asset load failed or hasn't finished — shown as a
 * loading spinner rather than a hard error, since these are bundled app assets that should
 * always be present; a real failure here is closer to "still loading" than "server error".
 *
 * [topPadding] defaults to a small sheet-content gap (this composable's first and only current
 * caller is a `ModalBottomSheet`, which already renders below the status bar with its own drag
 * handle) — a full-screen-overlay caller (matching e.g. `OBTimelinePaywallScreen`'s own status-bar
 * clearance) should pass a larger value like `52.dp` instead.
 */
@Composable
fun RdLegalDocumentSheet(
    documents: List<RdLegalDocument>,
    initialKind: String?,
    onClose: () -> Unit,
    topPadding: Dp = RdSpacing.sm,
) {
    val colors = RdTheme.colors
    var selectedKind by remember(documents) {
        mutableStateOf(initialKind ?: documents.firstOrNull()?.kind)
    }
    val selected = documents.find { it.kind == selectedKind } ?: documents.firstOrNull()

    Box(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        if (documents.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.onyx)
            }
        } else {
            Column(modifier = Modifier.fillMaxSize().padding(top = topPadding)) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = RdSpacing.lg),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        "Yasal Bilgilendirme",
                        style = RdFontStyle.Title3.toTextStyle(),
                        color = colors.black,
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(onClick = onClose) {
                        Icon(Icons.Filled.Close, contentDescription = "Kapat", tint = colors.black)
                    }
                }

                Spacer(Modifier.height(RdSpacing.sm))
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = RdSpacing.lg),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    documents.forEach { doc ->
                        val active = doc.kind == selected?.kind
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(12.dp))
                                .background(if (active) colors.onyx else colors.white)
                                .border(
                                    1.dp,
                                    if (active) colors.onyx else colors.line,
                                    RoundedCornerShape(12.dp),
                                )
                                .clickable { selectedKind = doc.kind }
                                .padding(horizontal = 14.dp, vertical = 9.dp),
                        ) {
                            Text(
                                doc.title,
                                style = RdFontStyle.Caption.toTextStyle(),
                                color = if (active) colors.white else colors.black,
                            )
                        }
                    }
                }

                Spacer(Modifier.height(RdSpacing.md))
                if (selected != null) {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = RdSpacing.lg)
                            .verticalScroll(rememberScrollState()),
                    ) {
                        Text(
                            selected.text,
                            style = RdFontStyle.Caption.toTextStyle(),
                            color = colors.charcoal,
                            textAlign = TextAlign.Start,
                        )
                        Spacer(Modifier.height(RdSpacing.xl))
                    }
                }
            }
        }
    }
}
