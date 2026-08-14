package com.riskdetectedan.core.data.company

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Kotlin mirror of App/Models/Company.swift's CompanyHazardClass — same raw values. */
enum class CompanyHazardClass(val id: String, val title: String) {
    Low("low", "Az Tehlikeli"),
    Medium("medium", "Tehlikeli"),
    High("high", "Çok Tehlikeli"),
}

/** Kotlin mirror of App/Models/Company.swift's Company — same table (`companies`), same columns. */
@Serializable
data class Company(
    val id: String,
    @SerialName("user_id") val userId: String,
    val name: String,
    @SerialName("hazard_class") val hazardClassId: String,
    @SerialName("logo_path") val logoPath: String? = null,
    val address: String? = null,
    @SerialName("contact_person") val contactPerson: String? = null,
    val department: String? = null,
    @SerialName("default_responsible") val defaultResponsible: String? = null,
    @SerialName("default_due_days") val defaultDueDays: Int? = null,
    @SerialName("is_archived") val isArchived: Boolean = false,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
) {
    val hazardClass: CompanyHazardClass
        get() = CompanyHazardClass.entries.firstOrNull { it.id == hazardClassId }
            ?: CompanyHazardClass.Medium
}

/** Kotlin mirror of App/Models/Company.swift's CompanyDraft — same validity rule
 * (name required, defaultDueDays either empty or 1-365). */
data class CompanyDraft(
    val id: String? = null,
    val name: String = "",
    val hazardClass: CompanyHazardClass = CompanyHazardClass.Medium,
    val logoPath: String? = null,
    val address: String = "",
    val contactPerson: String = "",
    val department: String = "",
    val defaultResponsible: String = "",
    val defaultDueDaysText: String = "",
) {
    val trimmedName: String get() = name.trim()

    val defaultDueDays: Int?
        get() = defaultDueDaysText.trim().takeIf { it.isNotEmpty() }?.toIntOrNull()

    val isValid: Boolean
        get() {
            val dueText = defaultDueDaysText.trim()
            val dueIsValid = dueText.isEmpty() || (defaultDueDays?.let { it in 1..365 } ?: false)
            return trimmedName.isNotEmpty() && dueIsValid
        }
}
