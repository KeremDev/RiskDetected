package com.riskdetectedan.app.home

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

/**
 * Real port of `HomeView.swift`'s `photoUploadCard` — "Saha fotoğrafları" header with a live
 * count, then either [emptyPhotoUploadDropZone] (dashed square, "+") or
 * [selectedPhotoUploadSummaryRow] (first-photo thumbnail + "N fotoğraf eklendi" + chevron-up) once
 * `photoPaths` is non-empty, plus a horizontal preview strip of every added photo below it (each
 * with an index badge + remove X, matching iOS's `photoUploadPreviewStrip`).
 *
 * Simplified vs iOS, documented: tapping the empty drop-zone here opens the full [PhotoTraySheet]
 * (camera/gallery chooser + grid) rather than iOS's asymmetric behavior (empty state jumps
 * straight to the system gallery picker, only a *non-empty* re-tap opens the tray sheet) — one
 * consistent entry point instead of replicating that first-tap special case. Photo-markup
 * (per-tile "annotate" tap) not ported, same as [PhotoTraySheet]'s own doc comment.
 */
@Composable
fun PhotoUploadCard(photoPaths: List<String>, maxPhotoCount: Int, onOpenTray: () -> Unit, onRemove: (String) -> Unit) {
    val colors = RdTheme.colors
    val shape = RoundedCornerShape(18.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .rdHomeCardShadow(shape)
            .clip(shape)
            .background(colors.white)
            .border(1.dp, colors.line, shape)
            .padding(RdSpacing.sm),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.PhotoLibrary, contentDescription = null, tint = colors.black, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(RdSpacing.xs))
            Text(stringResource(RdR.string.rd_saha_fotograflari), style = RdFontStyle.Callout.toTextStyle(), color = colors.black)
            Spacer(Modifier.weight(1f))
            Text(stringResource(RdR.string.rd_fotograf_orani_format, photoPaths.size, maxPhotoCount), style = RdFontStyle.Data.toTextStyle(), color = colors.slate)
        }
        Spacer(Modifier.height(RdSpacing.sm))

        if (photoPaths.isEmpty()) {
            EmptyPhotoUploadDropZone(onClick = onOpenTray)
        } else {
            SelectedPhotoUploadSummaryRow(firstPhotoPath = photoPaths.first(), count = photoPaths.size, onClick = onOpenTray)
            Spacer(Modifier.height(RdSpacing.sm))
            PhotoUploadPreviewStrip(photoPaths = photoPaths, maxPhotoCount = maxPhotoCount, onAddMore = onOpenTray, onRemove = onRemove)
        }
    }
}

@Composable
private fun EmptyPhotoUploadDropZone(onClick: () -> Unit) {
    val colors = RdTheme.colors
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .height(178.dp)
            .clip(RoundedCornerShape(RdRadius.lg))
            .background(colors.white)
            .border(1.dp, colors.line, RoundedCornerShape(RdRadius.lg))
            .clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            modifier = Modifier
                .size(82.dp)
                .clip(RoundedCornerShape(RdRadius.lg))
                .background(colors.white)
                .border(1.5.dp, colors.slate.copy(alpha = 0.45f), RoundedCornerShape(RdRadius.lg)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = colors.greenDark, modifier = Modifier.size(32.dp))
        }
        Spacer(Modifier.height(RdSpacing.sm))
        Text(stringResource(RdR.string.rd_saha_fotografi_yukle), style = RdFontStyle.Callout.toTextStyle(), color = colors.black)
        Text(stringResource(RdR.string.rd_jpg_png_heic), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate.copy(alpha = 0.78f))
    }
}

@Composable
private fun SelectedPhotoUploadSummaryRow(firstPhotoPath: String, count: Int, onClick: () -> Unit) {
    val colors = RdTheme.colors
    val bitmap = remember(firstPhotoPath) {
        runCatching { BitmapFactory.decodeFile(firstPhotoPath)?.asImageBitmap() }.getOrNull()
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(RdRadius.lg))
            .background(colors.fog)
            .border(1.dp, colors.line, RoundedCornerShape(RdRadius.lg))
            .clickable(onClick = onClick)
            .padding(RdSpacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(modifier = Modifier.size(54.dp).clip(RoundedCornerShape(RdRadius.md)).background(colors.white)) {
            if (bitmap != null) {
                Image(bitmap = bitmap, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxWidth().height(54.dp))
            }
        }
        Spacer(Modifier.width(RdSpacing.sm))
        Column(modifier = Modifier.weight(1f)) {
            Text(stringResource(RdR.string.rd_fotograf_eklendi_format, count), style = RdFontStyle.Callout.toTextStyle(), color = colors.black)
            Text(stringResource(RdR.string.rd_fotograflari_duzenle), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate.copy(alpha = 0.78f))
        }
        Box(
            modifier = Modifier.size(34.dp).clip(CircleShape).background(colors.fog),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.KeyboardArrowUp, contentDescription = null, tint = colors.slate, modifier = Modifier.size(16.dp))
        }
    }
}

@Composable
private fun PhotoUploadPreviewStrip(
    photoPaths: List<String>,
    maxPhotoCount: Int,
    onAddMore: () -> Unit,
    onRemove: (String) -> Unit,
) {
    val colors = RdTheme.colors
    Row(
        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(RdSpacing.xs),
    ) {
        photoPaths.forEachIndexed { index, path ->
            val bitmap = remember(path) {
                runCatching { BitmapFactory.decodeFile(path)?.asImageBitmap() }.getOrNull()
            }
            Box(modifier = Modifier.size(62.dp)) {
                Box(modifier = Modifier.size(62.dp).clip(RoundedCornerShape(RdRadius.md)).background(colors.fog)) {
                    if (bitmap != null) {
                        Image(bitmap = bitmap, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxWidth().height(62.dp))
                    }
                }
                Text(
                    "${index + 1}",
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.onyx,
                    modifier = Modifier
                        .padding(5.dp)
                        .size(22.dp)
                        .clip(CircleShape)
                        .background(colors.white.copy(alpha = 0.92f)),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(4.dp)
                        .size(22.dp)
                        .clip(CircleShape)
                        .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.62f))
                        .clickable { onRemove(path) },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Filled.Close, contentDescription = stringResource(RdR.string.rd_fotografi_sil), tint = androidx.compose.ui.graphics.Color.White, modifier = Modifier.size(9.dp))
                }
            }
        }
        if (photoPaths.size < maxPhotoCount) {
            Box(
                modifier = Modifier
                    .size(62.dp)
                    .clip(RoundedCornerShape(RdRadius.md))
                    .background(colors.fog)
                    .border(1.3.dp, colors.slate.copy(alpha = 0.38f), RoundedCornerShape(RdRadius.md))
                    .clickable(onClick = onAddMore),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Add, contentDescription = null, tint = colors.slate, modifier = Modifier.size(20.dp))
            }
        }
    }
}

/** Locked-state variant of [PhotoUploadCard] — free-quota-exhausted, tap opens the paywall
 * (`onUpgrade`). Port of iOS's `lockedPhotoUploadContent`, simplified to a solid card instead of
 * a gradient + dashed border (same decoration-simplified pattern as everywhere else). */
@Composable
fun LockedPhotoUploadCard(onClick: () -> Unit) {
    val colors = RdTheme.colors
    val shape = RoundedCornerShape(RdRadius.xl)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .height(220.dp)
            .rdHomeCardShadow(shape)
            .clip(shape)
            .background(colors.criticalBg.copy(alpha = 0.5f))
            .border(1.7.dp, colors.critical.copy(alpha = 0.3f), shape)
            .clickable(onClick = onClick)
            .padding(RdSpacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            modifier = Modifier.size(74.dp).clip(CircleShape).background(colors.white),
            contentAlignment = Alignment.Center,
        ) {
            Box(modifier = Modifier.size(56.dp).clip(CircleShape).border(6.dp, colors.critical, CircleShape))
            Icon(Icons.Filled.Lock, contentDescription = null, tint = colors.critical, modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.height(RdSpacing.sm))
        Text(stringResource(RdR.string.rd_ucretsiz_hak_doldu), style = RdFontStyle.Callout.toTextStyle(), color = colors.criticalText)
        Text(
            stringResource(RdR.string.rd_ucretsiz_hak_doldu_aciklama),
            style = RdFontStyle.Caption.toTextStyle(),
            color = colors.criticalText.copy(alpha = 0.85f),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
        Spacer(Modifier.height(RdSpacing.xs))
        Text(stringResource(RdR.string.rd_yukselt_1bfd44dd), style = RdFontStyle.Caption.toTextStyle(), color = colors.critical)
    }
}
