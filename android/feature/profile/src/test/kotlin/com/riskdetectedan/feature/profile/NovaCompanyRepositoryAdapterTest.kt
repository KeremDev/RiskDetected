package com.riskdetectedan.feature.profile

import com.riskdetectedan.core.data.company.Company
import org.junit.Assert.*
import org.junit.Test

class NovaCompanyRepositoryAdapterTest {
    private val company = Company("11111111-1111-4111-8111-111111111111", "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA", "Firma", "high", address = " Adres ", department = "Not a sector")

    @Test fun realCompanyModelProjectsOnlyExistingDisplayFields() {
        for (hazard in listOf("low", "medium", "high")) {
            val source = company.copy(hazardClassId = hazard)
            val row = source.toNovaOwnedCompany()
            assertEquals("Firma", row.name)
            assertEquals("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", row.ownerID.toString())
            assertEquals("Adres · ${source.hazardClass.title}", row.detail)
            assertFalse(row.detail.contains("Not a sector"))
            assertFalse(row.isArchived)
        }
    }
    @Test fun blankAddressDoesNotLeaveSeparatorsAndArchiveFlagSurvives() {
        for (address in listOf(null, "", " \n ")) {
            val source = company.copy(address = address, isArchived = true)
            assertEquals(source.hazardClass.title, source.toNovaOwnedCompany().detail)
            assertTrue(source.toNovaOwnedCompany().isArchived)
        }
    }
    @Test fun malformedIdentityAndUnknownHazardNeverBecomeDefaultMedium() {
        for (source in listOf(company.copy(id = "1-1-1-1-1"), company.copy(userId = "bad-owner"), company.copy(hazardClassId = "unrecognized"))) {
            val error = runCatching { source.toNovaOwnedCompany() }.exceptionOrNull()
            assertNotNull(error)
            assertEquals("company_list_failed", error?.message)
            assertNull(error?.cause)
        }
    }
}
