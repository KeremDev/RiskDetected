package com.riskdetectedan.core.data.analysis

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class FindingPatchValidatorTest {
    @Test fun `valid FK and matrix rescore patch is accepted`() {
        assertNull(
            FindingPatchValidator.validate(
                FindingPatch(
                    title = "Güncel bulgu",
                    description = "Sahada doğrulandı",
                    fkProbability = 6.0,
                    fkFrequency = 3.0,
                    fkSeverity = 40.0,
                    m5Probability = 4,
                    m5Severity = 5,
                    recommendedMeasures = listOf(FindingMeasure(text = "Korkuluk kur")),
                ),
            ),
        )
    }

    @Test fun `blank required fields fail before backend mutation`() {
        assertEquals("validation_failed", FindingPatchValidator.validate(FindingPatch(title = " "))?.code)
        assertEquals("validation_failed", FindingPatchValidator.validate(FindingPatch(description = ""))?.code)
    }

    @Test fun `out of contract risk values are rejected`() {
        listOf(
            FindingPatch(fkProbability = 2.0),
            FindingPatch(fkFrequency = 7.0),
            FindingPatch(fkSeverity = 99.0),
            FindingPatch(m5Probability = 0),
            FindingPatch(m5Severity = 6),
        ).forEach { assertNotNull(FindingPatchValidator.validate(it)) }
    }

    @Test fun `blank measure list is rejected but omitted measures remain valid`() {
        assertNotNull(
            FindingPatchValidator.validate(
                FindingPatch(recommendedMeasures = listOf(FindingMeasure(text = "  "))),
            ),
        )
        assertNull(FindingPatchValidator.validate(FindingPatch(recommendedMeasures = null)))
    }
}
