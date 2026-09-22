package com.riskdetectedan.core.data.nova

import android.content.Context
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.isg.NovaExpertTicket
import com.riskdetectedan.core.data.isg.NovaExpertTransport
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.serialization.json.*
import java.security.MessageDigest
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * The iOS `isgada.records.changed` / `isgada.mutation.succeeded` notifications:
 * one account-scoped stream the root listens to for reloads and the success card.
 */
@Singleton
class NovaRecordEvents @Inject constructor() {
    data class Changed(val userId: String)
    data class Succeeded(val userId: String, val message: String)

    private val changedFlow = MutableSharedFlow<Changed>(extraBufferCapacity = 16)
    private val succeededFlow = MutableSharedFlow<Succeeded>(extraBufferCapacity = 16)
    val changed: SharedFlow<Changed> = changedFlow.asSharedFlow()
    val succeeded: SharedFlow<Succeeded> = succeededFlow.asSharedFlow()

    fun recordsChanged(userId: String) { changedFlow.tryEmit(Changed(userId)) }
    fun succeeded(userId: String, message: String) { succeededFlow.tryEmit(Succeeded(userId, message)) }
}

/**
 * Stable request identity across process death and interrupted responses
 * (iOS `NovaModuleMutationJournal`): the same company/action/payload reuses the
 * saved operation and mutation ids, and only a decoded, session-validated
 * answer removes them.
 */
@Singleton
class NovaModuleMutationJournal @Inject constructor(
    @ApplicationContext context: Context,
    private val transport: NovaExpertTransport,
    private val events: NovaRecordEvents,
) {
    private val preferences = context.getSharedPreferences("nova.module.pending", Context.MODE_PRIVATE)

    suspend fun <T> run(function: String, identity: IsgWorkspaceIdentity, company: String?, action: String,
                        payload: JsonObject, ticket: NovaExpertTicket? = transport.capture(),
                        decode: (JsonElement) -> T): T {
        if (transport.identityNow() != identity) throw com.riskdetectedan.core.data.isg.NovaExpertFailure("ACCESS_DENIED")
        val body = novaCanonicalJson(buildJsonObject {
            put("company", company?.let(::JsonPrimitive) ?: JsonNull); put("action", action); put("payload", payload)
        })
        val digest = MessageDigest.getInstance("SHA-256").digest(body.toByteArray()).joinToString("") { "%02x".format(it) }
        val key = "$function:${identity.userId}:$digest"
        val saved = preferences.getString(key, null)?.split('|')
        val operation = saved?.getOrNull(0) ?: UUID.randomUUID().toString()
        val mutation = saved?.getOrNull(1) ?: UUID.randomUUID().toString()
        if (saved == null) preferences.edit().putString(key, "$operation|$mutation").commit()
        val data = transport.execute(function, buildJsonObject {
            put("p_company", company?.let(::JsonPrimitive) ?: JsonNull); put("p_action", action)
            put("p_operation", operation); put("p_mutation", mutation); put("p_payload", payload)
        }, ticket)
        if (transport.identityNow() != identity) throw com.riskdetectedan.core.data.isg.NovaExpertFailure("ACCESS_DENIED")
        val answer = decode(data)
        preferences.edit().remove(key).apply()
        events.recordsChanged(identity.userId)
        successMessage(action)?.let { events.succeeded(identity.userId, it) }
        return answer
    }


    companion object {
        /** Terminal, user-requested saves only; drafts, autosaves and reads never celebrate. */
        fun successMessage(action: String): String? = when (action) {
            "record_appointment" -> NovaSuccessWords.recordSaved("Atama")
            "register_equipment" -> "Ekipman başarıyla eklendi!"
            "record_inspection" -> "Periyodik kontrol başarıyla kaydedildi!"
            "publish_plan" -> "Acil durum planı başarıyla kaydedildi!"
            "record_result" -> NovaSuccessWords.recordSaved("Tatbikat sonucu")
            "record_handover", "create_form" -> NovaSuccessWords.recordSaved("KKD zimmeti")
            "submit_run" -> NovaSuccessWords.recordSaved("Kontrol")
            "publish_template" -> NovaSuccessWords.recordSaved("Kontrol listesi")
            "record_contract" -> NovaSuccessWords.recordSaved("Sözleşme")
            "finalize_version" -> NovaSuccessWords.recordSaved("Risk analizi")
            "save", "create", "update", "update_equipment", "update_inspection", "rename_entry" -> NovaSuccessWords.recordSaved("Kayıt")
            else -> null
        }
    }
}

object NovaSuccessWords {
    fun recordSaved(name: String) = "$name başarıyla kaydedildi!"
}

/** Sorted keys, so the same request hashes and compares the same regardless of build order. */
internal fun novaCanonicalJson(element: JsonElement): String = when (element) {
    is JsonObject -> element.keys.sorted().joinToString(",", "{", "}") { "\"$it\":${novaCanonicalJson(element.getValue(it))}" }
    is JsonArray -> element.joinToString(",", "[", "]") { novaCanonicalJson(it) }
    else -> element.toString()
}
