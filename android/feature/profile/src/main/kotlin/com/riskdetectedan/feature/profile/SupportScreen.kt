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
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Photo
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
import androidx.compose.ui.platform.LocalContext
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
 * per-attachment cap `support-contact` enforces), `OpenDocument` for arbitrary files (mime type +
 * display name read straight from the `ContentResolver`, no re-encoding — same as iOS's
 * `Data(contentsOf:)` passthrough). */
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

        Column(modifier = Modifier.fillMaxSize().padding(horizontal = RdSpacing.lg)) {
            RdSectionCard {
                Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.sm)) {
                    OutlinedTextField(
                        value = subject,
                        onValueChange = { subject = it },
                        label = { Text(stringResource(RdR.string.rd_konu)) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = message,
                        onValueChange = { message = it },
                        label = { Text(stringResource(RdR.string.rd_mesaj)) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    RdPrimaryButton(
                        text = stringResource(RdR.string.rd_gonder),
                        onClick = { viewModel.send(subject, message) },
                        enabled = subject.isNotBlank() && message.isNotBlank() && state !is SupportUiState.Sending,
                        style = RdButtonStyle.Onyx,
                        showArrow = false,
                    )
                }
            }

            Spacer(Modifier.height(RdSpacing.md))
            RdSectionCard {
                Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.sm)) {
                    Text(stringResource(RdR.string.rd_ek), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
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
                                Text(attachment.filename, style = RdFontStyle.Footnote.toTextStyle(), color = colors.onyx)
                                Text(
                                    stringResource(RdR.string.rd_dosya_boyutu_kb_format, attachment.sizeBytes / 1024),
                                    style = RdFontStyle.Caption.toTextStyle(),
                                    color = colors.slate,
                                )
                            }
                            IconButton(onClick = { viewModel.removeAttachment(attachment.id) }) {
                                Icon(Icons.Filled.Close, contentDescription = stringResource(RdR.string.rd_kaldir), tint = colors.onyx)
                            }
                        }
                    }
                    if (attachments.size >= 3) {
                        Text(stringResource(RdR.string.rd_en_fazla_3_ek_ekleyebilirsin), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                    } else {
                        Row(horizontalArrangement = Arrangement.spacedBy(RdSpacing.sm)) {
                            TextButton(onClick = { pickPhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) {
                                Icon(Icons.Filled.Photo, contentDescription = null, tint = colors.onyx)
                                Spacer(Modifier.width(RdSpacing.xs))
                                Text(stringResource(RdR.string.rd_fotograf))
                            }
                            TextButton(onClick = { pickFile.launch(arrayOf("*/*")) }) {
                                Icon(Icons.Filled.AttachFile, contentDescription = null, tint = colors.onyx)
                                Spacer(Modifier.width(RdSpacing.xs))
                                Text(stringResource(RdR.string.rd_dosya))
                            }
                        }
                    }
                    attachmentError?.let {
                        Text(it, style = RdFontStyle.Footnote.toTextStyle(), color = colors.critical)
                    }
                }
            }

            Spacer(Modifier.height(RdSpacing.md))
            when (val current = state) {
                is SupportUiState.Idle -> Unit
                is SupportUiState.Sending -> Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.onyx)
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
        }
    }
}
