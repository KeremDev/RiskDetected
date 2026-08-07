package com.riskdetectedan.core.data.company

import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.storage.storage
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import javax.inject.Inject
import javax.inject.Singleton

@Serializable
private data class CompanyUpsertPayload(
    @SerialName("user_id") val userId: String? = null,
    val name: String,
    @SerialName("hazard_class") val hazardClass: String,
    @SerialName("logo_path") val logoPath: String? = null,
    val address: String? = null,
    @SerialName("contact_person") val contactPerson: String? = null,
    val department: String? = null,
    @SerialName("default_responsible") val defaultResponsible: String? = null,
    @SerialName("default_due_days") val defaultDueDays: Int? = null,
)

/**
 * Mirrors CompanyService.swift's contract exactly: same table, same insert/update payload
 * shape, same DB-error-message-substring-to-user-facing-message normalization (the backend
 * enforces plan-tier company limits/paid-plan gating via constraint/trigger errors with these
 * specific substrings — matches backend-is-the-authority: this repository doesn't decide
 * whether a user can add a company, it just translates the server's rejection reason).
 */
@Singleton
class CompanyRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    suspend fun listCompanies(includeArchived: Boolean = false): RdResult<List<Company>> = try {
        val companies = client.postgrest.from("companies")
            .select {
                if (!includeArchived) filter { eq("is_archived", false) }
                order("created_at", Order.DESCENDING)
            }
            .decodeList<Company>()
        RdResult.Success(companies)
    } catch (t: Throwable) {
        RdResult.Failure("company_list_failed", "Firmalar yüklenemedi.", t)
    }

    suspend fun saveCompany(userId: String, draft: CompanyDraft): RdResult<Company> {
        if (!draft.isValid) {
            return RdResult.Failure("company_invalid_input", "Firma adı zorunlu.")
        }
        return try {
            val company = if (draft.id != null) {
                client.postgrest.from("companies")
                    .update(
                        CompanyUpsertPayload(
                            name = draft.trimmedName,
                            hazardClass = draft.hazardClass.id,
                            logoPath = draft.logoPath,
                            address = draft.address.trim().ifEmpty { null },
                            contactPerson = draft.contactPerson.trim().ifEmpty { null },
                            department = draft.department.trim().ifEmpty { null },
                            defaultResponsible = draft.defaultResponsible.trim().ifEmpty { null },
                            defaultDueDays = draft.defaultDueDays,
                        ),
                    ) {
                        filter { eq("id", draft.id) }
                        select(Columns.ALL)
                    }
                    .decodeSingle<Company>()
            } else {
                client.postgrest.from("companies")
                    .insert(
                        CompanyUpsertPayload(
                            userId = userId,
                            name = draft.trimmedName,
                            hazardClass = draft.hazardClass.id,
                            logoPath = draft.logoPath,
                            address = draft.address.trim().ifEmpty { null },
                            contactPerson = draft.contactPerson.trim().ifEmpty { null },
                            department = draft.department.trim().ifEmpty { null },
                            defaultResponsible = draft.defaultResponsible.trim().ifEmpty { null },
                            defaultDueDays = draft.defaultDueDays,
                        ),
                    ) {
                        select(Columns.ALL)
                    }
                    .decodeSingle<Company>()
            }
            RdResult.Success(company)
        } catch (t: Throwable) {
            RdResult.Failure(
                code = "company_save_failed",
                message = normalizedCompanyErrorMessage(t.message),
                cause = t,
            )
        }
    }

    /** Mirrors CompanyService.swift's `uploadLogo(_:companyID:)` — same bucket ("logos"), same
     * storage path convention (`{userId}/companies/{companyId}/logo.jpg`). The caller (feature
     * layer, which has an Android `Context`/`ContentResolver` for reading a picked gallery
     * image) is responsible for decoding/re-encoding to JPEG bytes before calling this — this
     * repository stays platform-storage-only, matching [PhotoRepository]/[ReportsRepository]. */
    suspend fun uploadLogo(userId: String, companyId: String, jpegBytes: ByteArray): RdResult<String> = try {
        val path = "${userId.lowercase()}/companies/${companyId.lowercase()}/logo.jpg"
        client.storage.from(LOGO_BUCKET).upload(path, jpegBytes) {
            upsert = true
        }
        RdResult.Success(path)
    } catch (t: Throwable) {
        RdResult.Failure("company_logo_upload_failed", "Firma logosu yüklenemedi.", t)
    }

    suspend fun archiveCompany(companyId: String): RdResult<Unit> = try {
        client.postgrest.from("companies")
            .update(mapOf("is_archived" to true)) {
                filter { eq("id", companyId) }
            }
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure("company_archive_failed", "Firma arşivlenemedi.", t)
    }

    private fun normalizedCompanyErrorMessage(raw: String?): String {
        val message = raw.orEmpty()
        return when {
            message.contains("company_feature_requires_paid_plan", ignoreCase = true) ->
                "Firma eklemek için Plus veya Pro plana geçmelisin."
            message.contains("company_limit_exceeded", ignoreCase = true) ->
                "Planındaki firma limitine ulaştın."
            message.contains("company_default_due_days_invalid", ignoreCase = true) ->
                "Varsayılan termin 1-365 gün arasında olmalı."
            message.contains("duplicate", ignoreCase = true) ||
                message.contains("companies_user_active_name_idx", ignoreCase = true) ->
                "Bu firma adı zaten listende var."
            else -> "Firma kaydedilemedi."
        }
    }

    private companion object {
        const val LOGO_BUCKET = "logos"
    }
}
