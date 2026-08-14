package com.riskdetectedan.feature.profile

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.SupportAgent
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdScreenHeader
import com.riskdetectedan.core.designsystem.RdSectionCard
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import java.io.ByteArrayOutputStream
import kotlin.math.min

/** Port of SupportService.swift's send() contract (2026-08-08 visual pass, Faz K of the
 * core-flow redesign; App/Views/Profile/SupportContactSheet.swift's layout wasn't read pixel-for-
 * pixel — kept minimal/functional per that pass's scope). Attachments (2026-08-08, closes the
 * "not ported" gap): real port of [SupportContactSheet.swift]'s `PhotosPicker`+`fileImporter`
 * pair — `PickVisualMedia` for photos (resized/compressed client-side, same 1600px-max-dimension/
 * 0.78-quality budget as iOS's `supportJPEG`, since a raw camera photo would blow the 5MB
 * per-attachment cap `support-contact` enforces), `OpenDocument` for the server-approved JPEG,
 * PNG and PDF types (mime type + display name read from the `ContentResolver`). */
@Composable
fun SupportScreen(onBack: (() -> Unit)? = null, viewModel: SupportViewModel = hiltViewModel()) {
    val colors = RdTheme.colors
    val context = LocalContext.current
    val state by viewModel.state.collectAsState()
    val attachments by viewModel.attachments.collectAsState()
    val attachmentError by viewModel.attachmentError.collectAsState()
    var subject by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }

    val pickPhoto = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        context.contentResolver.openInputStream(uri)?.use { stream ->
            val bitmap = BitmapFactory.decodeStream(stream)
            if (bitmap != null) {
                val scale = min(1f, 1600f / maxOf(bitmap.width, bitmap.height))
                val scaled = if (scale < 1f) {
                    Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true)
                } else {
                    bitmap
                }
                val output = ByteArrayOutputStream()
                scaled.compress(Bitmap.CompressFormat.JPEG, 78, output)
                viewModel.addAttachment(output.toByteArray(), "destek-fotograf.jpg", "image/jpeg")
            }
        }
    }
    val pickFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return@rememberLauncherForActivityResult
        val mimeType = context.contentResolver.getType(uri) ?: "application/octet-stream"
        var name = "dosya"
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (nameIndex >= 0 && cursor.moveToFirst()) name = cursor.getString(nameIndex) ?: name
        }
        viewModel.addAttachment(bytes, name, mimeType)
    }

    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(title = stringResource(RdR.string.rd_destek), onBack = onBack)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = RdSpacing.lg)
                .padding(bottom = RdSpacing.xl),
            verticalArrangement = Arrangement.spacedBy(RdSpacing.md),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(24.dp))
                    .background(Brush.linearGradient(listOf(colors.greenSoft, colors.white)))
                    .border(1.dp, colors.green.copy(alpha = 0.22f), RoundedCornerShape(24.dp))
                    .padding(18.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier.size(52.dp).clip(RoundedCornerShape(17.dp)).background(colors.green.copy(alpha = 0.13f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Filled.SupportAgent, contentDescription = null, tint = colors.greenDark, modifier = Modifier.size(27.dp))
                }
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        stringResource(RdR.string.rd_riskdetected_destek),
                        style = RdFontStyle.Title3.toTextStyle().copy(fontWeight = FontWeight.Bold),
                        color = colors.black,
                    )
                    Text(
                        stringResource(RdR.string.rd_destek_aciklama),
                        style = RdFontStyle.Footnote.toTextStyle(),
                        color = colors.slate,
                    )
                }
            }

            RdSectionCard {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        stringResource(RdR.string.rd_talep_upper),
                        style = RdFontStyle.Caption.toTextStyle().copy(fontWeight = FontWeight.Bold),
                        color = colors.greenDark,
                    )
                    OutlinedTextField(
                        value = subject,
                        onValueChange = { subject = it },
                        label = { Text(stringResource(RdR.string.rd_konu)) },
                        placeholder = { Text(stringResource(RdR.string.rd_destek_konu_ornek)) },
                        shape = RoundedCornerShape(16.dp),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = message,
                        onValueChange = { message = it },
                        label = { Text(stringResource(RdR.string.rd_mesaj)) },
                        placeholder = { Text(stringResource(RdR.string.rd_destek_mesaj_ornek)) },
                        minLines = 5,
                        maxLines = 9,
                        shape = RoundedCornerShape(16.dp),
                        modifier = Modifier.fillMaxWidth().height(170.dp),
                    )
                }
            }

            RdSectionCard {
                Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.sm)) {
                    Text(
                        stringResource(RdR.string.rd_ek_upper),
                        style = RdFontStyle.Caption.toTextStyle().copy(fontWeight = FontWeight.Bold),
                        color = colors.greenDark,
                    )
                    attachments.forEach { attachment ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(colors.fog)
                                .padding(horizontal = RdSpacing.sm, vertical = RdSpacing.xs),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                if (attachment.mimeType.startsWith("image/")) Icons.Filled.Photo else Icons.Filled.AttachFile,
                                contentDescription = null,
                                tint = colors.greenDark,
                            )
                            Spacer(Modifier.width(RdSpacing.xs))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(attachment.filename, style = RdFontStyle.Footnote.toTextStyle(), color = colors.black)
                                Text(
                                    stringResource(RdR.string.rd_dosya_boyutu_kb_format, attachment.sizeBytes / 1024),
                                    style = RdFontStyle.Caption.toTextStyle(),
                                    color = colors.slate,
                                )
                            }
                            IconButton(onClick = { viewModel.removeAttachment(attachment.id) }) {
                                Icon(Icons.Filled.Close, contentDescription = stringResource(RdR.string.rd_kaldir), tint = colors.black)
                            }
                        }
                    }
                    if (attachments.size >= 3) {
                        Text(stringResource(RdR.string.rd_en_fazla_3_ek_ekleyebilirsin), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                    } else {
                        Row(horizontalArrangement = Arrangement.spacedBy(RdSpacing.sm)) {
                            SupportAttachmentButton(
                                label = stringResource(RdR.string.rd_fotograf),
                                icon = Icons.Filled.Photo,
                                modifier = Modifier.weight(1f),
                                onClick = { pickPhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                            )
                            SupportAttachmentButton(
                                label = stringResource(RdR.string.rd_dosya),
                                icon = Icons.Filled.AttachFile,
                                modifier = Modifier.weight(1f),
                                onClick = { pickFile.launch(arrayOf("image/jpeg", "image/png", "application/pdf")) },
                            )
                        }
                    }
                    attachmentError?.let {
                        Text(it, style = RdFontStyle.Footnote.toTextStyle(), color = colors.critical)
                    }
                }
            }

            when (val current = state) {
                is SupportUiState.Idle -> Unit
                is SupportUiState.Sending -> Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.black)
                }
                is SupportUiState.Sent -> Text(
                    stringResource(
                        RdR.string.rd_destek_gonderildi_format,
                        current.supportId ?: stringResource(RdR.string.rd_emdash),
                    ),
                    style = RdFontStyle.Footnote.toTextStyle(),
                    color = colors.greenDark,
                )
                is SupportUiState.Failed -> Text(current.error.message, style = RdFontStyle.Footnote.toTextStyle(), color = colors.critical)
            }

            RdPrimaryButton(
                text = stringResource(RdR.string.rd_destek_talebi_gonder),
                onClick = { viewModel.send(subject.trim(), message.trim()) },
                enabled = subject.trim().length >= 3 && message.trim().length >= 10 && state !is SupportUiState.Sending,
                style = RdButtonStyle.Onyx,
                showArrow = false,
            )
        }
    }
}

@Composable
private fun SupportAttachmentButton(
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val colors = RdTheme.colors
    Row(
        modifier = modifier
            .height(50.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(colors.fog)
            .border(1.dp, colors.line, RoundedCornerShape(16.dp))
            .clickable(onClick = onClick),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = colors.greenDark, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
        Text(label, style = RdFontStyle.Footnote.toTextStyle().copy(fontWeight = FontWeight.SemiBold), color = colors.black)
    }
}
