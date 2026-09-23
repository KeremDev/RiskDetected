package com.riskdetectedan.core.data.nova

import org.junit.Assert.*
import org.junit.Test

/** The create intent normalises exactly like iOS `NovaPilotCompanyIntent`, so a stored request replays unchanged. */
class NovaCompanyCreateIntentTest {
    private val owner = "11000000-0000-4000-8000-000000000001"

    @Test fun collapsesWhitespaceAndKeepsTheName() {
        val intent = NovaCompanyCreateIntent.contactProfile(owner, "  Koza \n Altın\tA.Ş  ", "high", " Maden ", "", "42", "Ayşe  Demir",
            "(0532) 000-00 00", "")
        assertEquals("Koza Altın A.Ş", intent.name)
        assertEquals("Maden", intent.sector)
        assertEquals(42, intent.employeeCount)
        assertEquals("Ayşe Demir", intent.responsibleName)
        assertEquals("05320000000", intent.responsiblePhone)
        assertEquals(3, intent.contactVersion)
        intent.validate()
    }

    @Test fun refusesAPhoneWithoutAResponsiblePerson() {
        assertThrows(NovaCompanyCreateException::class.java) {
            NovaCompanyCreateIntent.contactProfile(owner, "Koza", "medium", "Maden", "", "1", "", "05320000000", "")
        }
    }

    @Test fun refusesInvisibleCharactersAndUnknownHazards() {
        assertThrows(NovaCompanyCreateException::class.java) { NovaCompanyCreateIntent.base(owner, "Koza​", "medium") }
        assertThrows(NovaCompanyCreateException::class.java) { NovaCompanyCreateIntent.base(owner, "Koza", "extreme") }
    }

    @Test fun refusesAnEditedStoredIntent() {
        val intent = NovaCompanyCreateIntent.contactProfile(owner, "Koza", "medium", "Maden", "", "5", "", "", "")
        assertThrows(NovaCompanyCreateException::class.java) { intent.copy(employeeCount = -1).validate() }
    }
}
