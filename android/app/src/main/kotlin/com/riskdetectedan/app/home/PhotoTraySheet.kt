package com.riskdetectedan.app.home

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.NavigateBefore
import androidx.compose.material.icons.filled.NavigateNext
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import java.io.File

/**
 * Port of HomeView.swift's inline `PhotoMediaTraySheet` (Faz O — the real multi-photo picker,
 * not a single-shot capture). 3-column grid of photo slots (filled/empty/locked), source buttons
 * (Kamera/Galeri), locked-slot upgrade prompt, dynamic primary button ("Fotoğraf ekle" when
 * empty, "Analize geç" once at least one photo is in). `maxPhotoCount`/`visibleSlotCount` default
 * to the fail-closed Android contract (1 photo, 1 visible slot); Home passes the live
 * `PlanCapabilities` values after the Android-specific rollout gate resolves, including the
 * optional locked Free slots.
 *
 * Every photo added here (camera or gallery) is routed through [com.riskdetectedan.app.annotate
 * .AnnotateScreen] before it lands in a tile — real port of `appendPickedPhotos(shouldAnnotate:
 * true)`, wired at the nav layer (`RdNavHost`'s `Annotate` destination + `HomeScreen`'s
 * `onAnnotatePhotos`), not inside this sheet. NOT ported: a per-tile "re-annotate this photo
 * again" button (iOS's `pencil.tip.crop.circle` tile control) — tile controls here stay
 * move-left/move-right/remove, matching this sheet's existing scope; markup happens once at
 * add-time on both platforms in the common case anyway.
 */
@Composable
fun PhotoTraySheet(
    photoPaths: List<String>,
    maxPhotoCount: Int = 1,
    visibleSlotCount: Int = 1,
    onCamera: () -> Unit,
    onGallery: () -> Unit,
    onRemove: (String) -> Unit,
    onMove: (String, Int) -> Unit,
    onLockedSlot: () -> Unit,
    onStartAnalysis: () -> Unit,
    onClose: () -> Unit,
) {
    val colors = RdTheme.colors
    val canAddMore = photoPaths.size < maxPhotoCount
    val slotCount = maxOf(visibleSlotCount, minOf(maxPhotoCount, photoPaths.size + 1))
    val hasLockedSlots = slotCount > maxPhotoCount

    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = RdSpacing.lg).padding(top = RdSpacing.md, bottom = RdSpacing.lg)) {
        Row(verticalAlignment = Alignment.Top) {
            Column(modifier = Modifier.weight(1f)) {
                Text(stringResource(RdR.string.rd_fotograflar), style = RdFontStyle.Title2.toTextStyle(), color = colors.onyx)
                Text(stringResource(RdR.string.rd_fotograf_orani_format, photoPaths.size, maxPhotoCount), style = RdFontStyle.Data.toTextStyle(), color = colors.slate)
            }
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(colors.fog)
                    .clickable(onClick = onClose),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Close, contentDescription = stringResource(RdR.string.rd_kapat), tint = colors.slate, modifier = Modifier.size(15.dp))
            }
        }

        Spacer(Modifier.height(RdSpacing.md))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            SourceButton(title = stringResource(RdR.string.rd_kamera), icon = Icons.Filled.CameraAlt, enabled = canAddMore, onClick = onCamera, modifier = Modifier.weight(1f))
            SourceButton(title = stringResource(RdR.string.rd_galeri), icon = Icons.Filled.PhotoLibrary, enabled = canAddMore, onClick = onGallery, modifier = Modifier.weight(1f))
        }

        Spacer(Modifier.height(RdSpacing.sm))
        LazyVerticalGrid(
            columns = GridCells.Fixed(3),
            modifier = Modifier.fillMaxWidth().height((((slotCount + 2) / 3) * 108).dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(slotCount) { index ->
                when {
                    index < photoPaths.size -> PhotoTile(
                        path = photoPaths[index],
                        index = index,
                        canMoveLeft = index > 0,
                        canMoveRight = index < photoPaths.size - 1,
                        onRemove = { onRemove(photoPaths[index]) },
                        onMove = { delta -> onMove(photoPaths[index], delta) },
                    )
                    index >= maxPhotoCount -> LockedTile(onClick = onLockedSlot)
                    else -> EmptyTile(enabled = canAddMore, onClick = onGallery)
                }
            }
        }

        if (hasLockedSlots) {
            Spacer(Modifier.height(RdSpacing.sm))
            UpgradePrompt(onClick = onLockedSlot)
        }

        Spacer(Modifier.height(RdSpacing.md))
        PrimaryButton(
            hasPhotos = photoPaths.isNotEmpty(),
            onClick = { if (photoPaths.isEmpty()) onGallery() else onStartAnalysis() },
        )
    }
}

@Composable
private fun SourceButton(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, enabled: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = RdTheme.colors
    Row(
        modifier = modifier
            .height(46.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(colors.fog)
            .border(1.dp, colors.line, RoundedCornerShape(16.dp))
            .clickable(enabled = enabled, onClick = onClick),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = if (enabled) colors.black else colors.slate, modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(8.dp))
        Text(title, style = RdFontStyle.Footnote.toTextStyle(), color = if (enabled) colors.black else colors.slate)
    }
}

@Composable
private fun PhotoTile(path: String, index: Int, canMoveLeft: Boolean, canMoveRight: Boolean, onRemove: () -> Unit, onMove: (Int) -> Unit) {
    val colors = RdTheme.colors
    val bitmap = remember(path) {
        runCatching { BitmapFactory.decodeFile(path)?.asImageBitmap() }.getOrNull()
    }
    Box(modifier = Modifier.size(108.dp).clip(RoundedCornerShape(17.dp)).background(colors.fog)) {
        if (bitmap != null) {
            Image(bitmap = bitmap, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxWidth().height(108.dp))
        }
        Column(modifier = Modifier.padding(7.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Box(
                    modifier = Modifier.size(24.dp).clip(CircleShape).background(colors.white.copy(alpha = 0.92f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(stringResource(RdR.string.rd_sayi_format, index + 1), style = RdFontStyle.Data.toTextStyle(), color = colors.onyx)
                }
                Box(
                    modifier = Modifier
                        .size(24.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.56f))
                        .clickable(onClick = onRemove),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Filled.Close, contentDescription = stringResource(RdR.string.rd_fotografi_sil), tint = Color.White, modifier = Modifier.size(10.dp))
                }
            }
            Spacer(Modifier.weight(1f))
            Row(
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .clip(CircleShape)
                    .background(colors.white.copy(alpha = 0.90f))
                    .padding(4.dp),
            ) {
                Icon(
                    Icons.Filled.NavigateBefore,
                    contentDescription = stringResource(RdR.string.rd_sola_tasi),
                    tint = if (canMoveLeft) colors.onyx else colors.slate.copy(alpha = 0.38f),
                    modifier = Modifier.size(18.dp).clickable(enabled = canMoveLeft) { onMove(-1) },
                )
                Icon(
                    Icons.Filled.NavigateNext,
                    contentDescription = stringResource(RdR.string.rd_saga_tasi),
                    tint = if (canMoveRight) colors.onyx else colors.slate.copy(alpha = 0.38f),
                    modifier = Modifier.size(18.dp).clickable(enabled = canMoveRight) { onMove(1) },
                )
            }
        }
    }
}

@Composable
private fun EmptyTile(enabled: Boolean, onClick: () -> Unit) {
    val colors = RdTheme.colors
    Box(
        modifier = Modifier
            .size(108.dp)
            .clip(RoundedCornerShape(17.dp))
            .background(colors.white)
            .border(1.5.dp, colors.slate.copy(alpha = 0.34f), RoundedCornerShape(17.dp))
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.Filled.Add, contentDescription = stringResource(RdR.string.rd_fotograf_ekle), tint = colors.slate.copy(alpha = 0.58f), modifier = Modifier.size(31.dp))
    }
}

@Composable
private fun LockedTile(onClick: () -> Unit) {
    val colors = RdTheme.colors
    Box(
        modifier = Modifier
            .size(108.dp)
            .clip(RoundedCornerShape(17.dp))
            .background(colors.fog)
            .border(1.dp, colors.line, RoundedCornerShape(17.dp))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.Filled.Lock, contentDescription = stringResource(RdR.string.rd_kilitli_slot), tint = colors.black, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun UpgradePrompt(onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(38.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(Color(0xFFFFF1B8))
            .border(1.2.dp, Color(0xFFF0C24A), RoundedCornerShape(14.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = RdSpacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Lock, contentDescription = null, tint = Color(0xFF8A5A00), modifier = Modifier.size(12.dp))
        Spacer(Modifier.width(9.dp))
        Text(
            stringResource(RdR.string.rd_coklu_fotograf_yukselt),
            style = RdFontStyle.Caption.toTextStyle(),
            color = Color(0xFF8A5A00),
            modifier = Modifier.weight(1f),
        )
        Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null, tint = Color(0xFF8A5A00), modifier = Modifier.size(12.dp))
    }
}

@Composable
private fun PrimaryButton(hasPhotos: Boolean, onClick: () -> Unit) {
    val colors = RdTheme.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(58.dp)
            .clip(RoundedCornerShape(24.dp))
            .background(colors.onyx)
            .clickable(onClick = onClick),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(if (hasPhotos) Icons.Filled.AutoAwesome else Icons.Filled.Add, contentDescription = null, tint = colors.white, modifier = Modifier.size(17.dp))
        Spacer(Modifier.width(9.dp))
        Text(
            stringResource(if (hasPhotos) RdR.string.rd_analize_gec else RdR.string.rd_fotograf_ekle),
            style = RdFontStyle.Callout.toTextStyle(),
            color = colors.white,
        )
    }
}
