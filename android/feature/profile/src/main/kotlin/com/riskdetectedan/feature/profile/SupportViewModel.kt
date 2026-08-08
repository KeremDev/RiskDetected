package com.riskdetectedan.feature.profile

import android.util.Base64
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.error.AppErrorMessage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.data.support.SupportAttachmentPayload
import com.riskdetectedan.core.data.support.SupportRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject

sealed interface SupportUiState {
    data object Idle : SupportUiState
    data object Sending : SupportUiState
    data class Sent(val supportId: String?) : SupportUiState
    data class Failed(val error: AppErrorMessage) : SupportUiState
}

/** Real port of `SupportAttachmentDraft` — [bytes] stays in memory only (same as iOS's `Data`
 * held in `@State`), base64-encoded lazily in [SupportViewModel.send] rather than on add, so a
 * removed-before-send attachment never pays that cost. */
data class SupportAttachmentDraft(
    val id: String = UUID.randomUUID().toString(),
    val filename: String,
    val mimeType: String,
    val bytes: ByteArray,
) {
    val sizeBytes: Int get() = bytes.size
}

private const val MAX_ATTACHMENT_COUNT = 3
private const val MAX_ATTACHMENT_BYTES = 5_000_000

@HiltViewModel
class SupportViewModel @Inject constructor(
    private val supportRepository: SupportRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<SupportUiState>(SupportUiState.Idle)
    val state: StateFlow<SupportUiState> = _state.asStateFlow()

    private val _attachments = MutableStateFlow<List<SupportAttachmentDraft>>(emptyList())
    val attachments: StateFlow<List<SupportAttachmentDraft>> = _attachments.asStateFlow()

    private val _attachmentError = MutableStateFlow<String?>(null)
    val attachmentError: StateFlow<String?> = _attachmentError.asStateFlow()

    /** Real port of `setAttachment(data:filename:mimeType:)` — same count/size guards as the
     * server (`MAX_ATTACHMENT_COUNT`/`MAX_ATTACHMENT_BYTES`, checked directly in
     * `support-contact/index.ts`), same [uniqueAttachmentName] de-dupe suffixing. */
    fun addAttachment(bytes: ByteArray, filename: String, mimeType: String) {
        if (_attachments.value.size >= MAX_ATTACHMENT_COUNT) {
            _attachmentError.value = "En fazla $MAX_ATTACHMENT_COUNT ek ekleyebilirsin."
            return
        }
        if (bytes.size > MAX_ATTACHMENT_BYTES) {
            _attachmentError.value = "Ek dosya 5 MB'dan küçük olmalı."
            return
        }
        _attachments.value = _attachments.value + SupportAttachmentDraft(
            filename = uniqueAttachmentName(filename),
            mimeType = mimeType,
            bytes = bytes,
        )
        _attachmentError.value = null
    }

    fun removeAttachment(id: String) {
        _attachments.value = _attachments.value.filterNot { it.id == id }
    }

    fun clearAttachmentError() {
        _attachmentError.value = null
    }

    private fun uniqueAttachmentName(filename: String): String {
        val existing = _attachments.value
        if (existing.none { it.filename == filename }) return filename
        val dotIndex = filename.lastIndexOf('.')
        val base = if (dotIndex > 0) filename.substring(0, dotIndex) else filename
        val ext = if (dotIndex > 0) filename.substring(dotIndex + 1) else ""
        val suffix = existing.size + 1
        return if (ext.isEmpty()) "$base-$suffix" else "$base-$suffix.$ext"
    }

    fun send(subject: String, message: String) {
        _state.value = SupportUiState.Sending
        val payloads = _attachments.value.map { draft ->
            SupportAttachmentPayload(
                filename = draft.filename,
                mimeType = draft.mimeType,
                data = Base64.encodeToString(draft.bytes, Base64.NO_WRAP),
                sizeBytes = draft.sizeBytes,
            )
        }
        viewModelScope.launch {
            _state.value = when (val result = supportRepository.send(subject, message, payloads)) {
                is RdResult.Success -> {
                    _attachments.value = emptyList()
                    SupportUiState.Sent(result.value.supportId)
                }
                is RdResult.Failure -> SupportUiState.Failed(
                    AppErrorMessages.make(result.message, context = "Destek talebi gönderilemedi"),
                )
            }
        }
    }
}
