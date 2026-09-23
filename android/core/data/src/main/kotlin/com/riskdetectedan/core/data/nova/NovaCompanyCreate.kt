package com.riskdetectedan.core.data.nova

import android.content.Context
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.isg.NovaExpertFailure
import com.riskdetectedan.core.data.isg.NovaExpertTransport
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*
import java.text.Normalizer
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

class NovaCompanyCreateException(val code: String) : Exception(code)

/**
 * A durable, account-owned create intent (iOS `NovaPilotCompanyIntent`). The session is deliberately
 * not kept: after signing in again the same owner may retry explicitly, with fresh authorization.
 */
@Serializable data class NovaCompanyCreateIntent(
    val ownerID: String, val mutationID: String, val name: String, val hazard: String, val sector: String? = null, val email: String? = null,
    val employeeCount: Int? = null, val responsibleName: String? = null, val responsiblePhone: String? = null,
    val responsibleEmail: String? = null, val contactVersion: Int? = null,
) {
    /** A stored intent must normalise to itself, or it is refused rather than replayed. */
    fun validate() {
        if (contactVersion != null) {
            if (contactVersion != 3 || sector == null) throw NovaCompanyCreateException("VALIDATION_ERROR")
            val normalized = contactProfile(ownerID, name, hazard, sector, email.orEmpty(), employeeCount?.toString().orEmpty(),
                responsibleName.orEmpty(), responsiblePhone.orEmpty(), responsibleEmail.orEmpty())
            if (normalized.responsiblePhone != responsiblePhone || normalized.responsibleEmail != responsibleEmail) throw NovaCompanyCreateException("VALIDATION_ERROR")
        } else if (responsiblePhone != null || responsibleEmail != null) throw NovaCompanyCreateException("VALIDATION_ERROR")
        if (sector != null) {
            val normalized = profile(ownerID, name, hazard, sector, email.orEmpty(), employeeCount?.toString().orEmpty(), responsibleName.orEmpty())
            if (normalized.name != name || normalized.sector != sector || normalized.email != email || normalized.employeeCount != employeeCount ||
                normalized.responsibleName != responsibleName) throw NovaCompanyCreateException("VALIDATION_ERROR")
        } else if (base(ownerID, name, hazard).name != name || email != null || employeeCount != null || responsibleName != null)
            throw NovaCompanyCreateException("VALIDATION_ERROR")
    }

    companion object {
        private val mail = Regex("^[^\\s@]+@[^\\s@]+[.][^\\s@]+$")

        fun base(ownerID: String, name: String, hazard: String): NovaCompanyCreateIntent {
            val value = Normalizer.normalize(name, Normalizer.Form.NFC).replace(Regex("[ \\t\\r\\n]+"), " ").trim(' ')
            if (value.isEmpty() || value.toByteArray().size > 200 || hazard !in setOf("low", "medium", "high") ||
                value.any { it.code < 32 || it.code == 127 || it.code == 0x200B || it.code == 0xFEFF }) throw NovaCompanyCreateException("VALIDATION_ERROR")
            return NovaCompanyCreateIntent(ownerID, UUID.randomUUID().toString(), value, hazard)
        }

        fun profile(ownerID: String, name: String, hazard: String, sector: String, email: String, employeeCount: String,
                    responsibleName: String): NovaCompanyCreateIntent {
            var intent = base(ownerID, name, hazard)
            val normalizedSector = base(ownerID, sector, hazard).name
            if (normalizedSector.toByteArray().size > 120) throw NovaCompanyCreateException("VALIDATION_ERROR")
            intent = intent.copy(sector = normalizedSector)
            val address = email.trim()
            if (address.isNotEmpty()) {
                if (address.toByteArray().size > 254 || !mail.matches(address)) throw NovaCompanyCreateException("VALIDATION_ERROR")
                intent = intent.copy(email = address)
            }
            val count = employeeCount.trim()
            if (count.isNotEmpty()) {
                val number = count.takeIf { text -> text.all { it in '0'..'9' } }?.toIntOrNull()?.takeIf { it in 0..10_000_000 }
                    ?: throw NovaCompanyCreateException("VALIDATION_ERROR")
                intent = intent.copy(employeeCount = number)
            }
            if (responsibleName.isNotBlank()) intent = intent.copy(responsibleName = base(ownerID, responsibleName, hazard).name)
            return intent
        }

        fun contactProfile(ownerID: String, name: String, hazard: String, sector: String, email: String, employeeCount: String,
                           responsibleName: String, responsiblePhone: String, responsibleEmail: String): NovaCompanyCreateIntent {
            var intent = profile(ownerID, name, hazard, sector, email, employeeCount, responsibleName).copy(contactVersion = 3)
            if (intent.responsibleName != null) {
                val phone = responsiblePhone.replace(Regex("[ ()-]"), "")
                val address = responsibleEmail.trim()
                if (!Regex("^[+]?[0-9]{7,15}$").matches(phone) ||
                    (address.isNotEmpty() && (address.toByteArray().size > 254 || !mail.matches(address)))) throw NovaCompanyCreateException("VALIDATION_ERROR")
                intent = intent.copy(responsiblePhone = phone, responsibleEmail = address.ifEmpty { null })
            } else if (responsiblePhone.isNotEmpty() || responsibleEmail.isNotEmpty()) throw NovaCompanyCreateException("VALIDATION_ERROR")
            return intent
        }
    }
}

/**
 * Company creation (iOS `NovaPilotCompanyService`). The intent is stored before the request and removed
 * only after a validated receipt, so a retry reuses the same mutation and never creates a second company.
 */
@Singleton
class NovaCompanyCreateService @Inject constructor(@ApplicationContext context: Context, private val transport: NovaExpertTransport,
                                                   private val events: NovaRecordEvents) {
    private val storage = context.getSharedPreferences("nova.company.pending.v1", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true; explicitNulls = false }
    private var inFlight = false

    @Serializable private data class Receipt(@SerialName("schema_version") val schemaVersion: Int, val company: Row, val replayed: Boolean = false) {
        @Serializable data class Row(val id: String, @SerialName("user_id") val userId: String, val name: String,
                                     @SerialName("hazard_class") val hazardClass: String, @SerialName("is_archived") val isArchived: Boolean)
    }

    private fun check(identity: IsgWorkspaceIdentity) {
        if (transport.identityNow() != identity) throw NovaCompanyCreateException("ACCESS_DENIED")
    }

    fun pending(identity: IsgWorkspaceIdentity): NovaCompanyCreateIntent? {
        check(identity)
        val raw = storage.getString(identity.userId.lowercase(), null) ?: return null
        val intent = json.decodeFromString(NovaCompanyCreateIntent.serializer(), raw)
        intent.validate()
        if (!intent.ownerID.equals(identity.userId, true) || NovaCompanyCreateIntent.base(intent.ownerID, intent.name, intent.hazard).name != intent.name)
            throw NovaCompanyCreateException("ACCESS_DENIED")
        return intent
    }

    /** Never falls back to a direct insert and never mints a new mutation on retry. */
    suspend fun create(identity: IsgWorkspaceIdentity, intent: NovaCompanyCreateIntent): String {
        check(identity)
        intent.validate()
        if (!intent.ownerID.equals(identity.userId, true)) throw NovaCompanyCreateException("ACCESS_DENIED")
        synchronized(this) { if (inFlight) throw NovaCompanyCreateException("UNAVAILABLE"); inFlight = true }
        try {
            pending(identity)?.let { if (it != intent) throw NovaCompanyCreateException("IDEMPOTENCY_CONFLICT") }
            val account = identity.userId.lowercase()
            storage.edit().putString(account, json.encodeToString(NovaCompanyCreateIntent.serializer(), intent)).commit()
            val version = intent.contactVersion ?: if (intent.sector == null) 1 else 2
            val data = try {
                transport.execute("isg_pilot_company_create_v$version", buildJsonObject {
                    put("p_mutation", intent.mutationID); put("p_name", intent.name); put("p_hazard_class", intent.hazard)
                    if (intent.sector != null) {
                        put("p_sector", intent.sector); put("p_email", intent.email?.let(::JsonPrimitive) ?: JsonNull)
                        put("p_employee_count", intent.employeeCount?.let(::JsonPrimitive) ?: JsonNull)
                        put("p_responsible_name", intent.responsibleName?.let(::JsonPrimitive) ?: JsonNull)
                    }
                    if (intent.contactVersion == 3) {
                        put("p_responsible_phone", intent.responsiblePhone?.let(::JsonPrimitive) ?: JsonNull)
                        put("p_responsible_email", intent.responsibleEmail?.let(::JsonPrimitive) ?: JsonNull)
                    }
                }, maxBytes = 16_384)
            } catch (failure: NovaExpertFailure) {
                currentCoroutineContext().ensureActive(); throw NovaCompanyCreateException(failure.code)
            }
            check(identity)
            val receipt = runCatching { json.decodeFromJsonElement(Receipt.serializer(), data) }.getOrNull() ?: throw NovaCompanyCreateException("UNAVAILABLE")
            if (receipt.schemaVersion != version || !receipt.company.userId.equals(identity.userId, true) || receipt.company.isArchived ||
                receipt.company.name.isEmpty() || receipt.company.hazardClass !in setOf("low", "medium", "high")) throw NovaCompanyCreateException("UNAVAILABLE")
            storage.edit().remove(account).apply()
            events.recordsChanged(identity.userId)
            return receipt.company.id
        } finally { synchronized(this) { inFlight = false } }
    }

    companion object {
        fun message(error: Throwable): String = when ((error as? NovaCompanyCreateException)?.code) {
            "company_limit_exceeded" -> "Firma limitinize ulaştınız."
            "PAID_PLAN_REQUIRED" -> "Firma oluşturma erişimi doğrulanamadı. Lütfen tekrar deneyin."
            "FEATURE_UNAVAILABLE", "ACCESS_DENIED" -> "Pilot yazma erişimi açık değil veya süresi dolmuş."
            "IDEMPOTENCY_CONFLICT" -> "Bekleyen işlemin içeriği uyuşmuyor. Yeni kayıt açılmadı."
            else -> "İşlemin sonucu doğrulanamadı. Bağlantınızı kontrol edip aynı kaydı tekrar deneyin."
        }
    }
}
