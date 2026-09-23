package com.riskdetectedan.feature.profile

import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.company.CompanyHazardClass
import com.riskdetectedan.core.data.company.Company
import com.riskdetectedan.core.data.company.CompanyRepository
import com.riskdetectedan.core.designsystem.isg.NovaOwnedCompany
import java.util.UUID

/** No alternate query, tier inference, sector fabrication, or swallowed request cancellation. */
internal suspend fun CompanyRepository.loadNovaOwnedCompanies(includeArchived: Boolean): List<NovaOwnedCompany> =
    when (val result = listCompanies(includeArchived)) {
        is RdResult.Failure -> throw NovaCompanyReadFailure()
        is RdResult.Success -> result.value.map { it.toNovaOwnedCompany() }
    }

internal fun Company.toNovaOwnedCompany(): NovaOwnedCompany {
    // Do not use Company's legacy unknown-to-medium fallback for this new projection.
    val hazard = CompanyHazardClass.entries.firstOrNull { it.id == hazardClassId } ?: throw NovaCompanyReadFailure()
    // Filled profile fields out of eight, as the iOS list shows them.
    val progress = listOf(address, city, phone, naceCode, workplaceRegistryNo, department, contactPerson, defaultResponsible)
        .count { !it.isNullOrBlank() }
    return NovaOwnedCompany(canonicalCompanyUUID(id), canonicalCompanyUUID(userId), name,
        listOfNotNull(address?.trim()?.takeIf { it.isNotEmpty() }, hazard.title).joinToString(" · "), isArchived,
        progressCompleted = progress, progressTotal = 8, logoPath = logoPath)
}

private fun canonicalCompanyUUID(raw: String): UUID {
    val id = runCatching { UUID.fromString(raw) }.getOrNull() ?: throw NovaCompanyReadFailure()
    if (!id.toString().equals(raw, ignoreCase = true)) throw NovaCompanyReadFailure()
    return id
}
private class NovaCompanyReadFailure : Exception("company_list_failed")
