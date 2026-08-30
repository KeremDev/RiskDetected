package com.riskdetectedan.app.reports

import android.app.Application
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performTextInput
import com.github.takahirom.roborazzi.captureRoboImage
import com.riskdetectedan.core.data.company.Company
import com.riskdetectedan.core.designsystem.RiskDetectedTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(application = Application::class, sdk = [35], qualifiers = "tr-rTR-w393dp-h852dp-xxhdpi")
class ReportCompanySearchTest {

    @get:Rule
    val composeRule = createComposeRule()

    private val companies = listOf(
        company("izmir", "İzmir İnşaat", address = "Bornova İzmir"),
        company("gebze", "Gebze Üretim", contact = "Ayşe Demir", department = "Bakım Ekibi"),
        company("ankara", "Ankara Lojistik", address = "Sincan Ankara"),
    ) + (1..12).map { index ->
        company(
            id = "saha-$index",
            name = "Saha Firması ${index.toString().padStart(2, '0')}",
            address = "Organize Sanayi Bölgesi $index",
            contact = "Sorumlu $index",
            department = if (index % 2 == 0) "Üretim" else "Operasyon",
        )
    }

    @Test
    fun search_matches_turkish_company_details_and_keeps_selected_company_first() {
        assertEquals(listOf("izmir"), filterReportCompanies(companies, "IZMIR").map { it.id })
        assertEquals(listOf("gebze"), filterReportCompanies(companies, "ayse").map { it.id })
        assertEquals(listOf("gebze"), filterReportCompanies(companies, "bakim").map { it.id })
        val allCompanies = filterReportCompanies(companies, query = "", selectedCompanyId = "gebze")
        assertEquals(15, allCompanies.size)
        assertEquals("gebze", allCompanies.first().id)
    }

    @Test
    fun typing_filters_the_open_company_list_and_selects_the_result() {
        var selectedId: String? = null
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                ReportCompanySearchSheet(
                    companies = companies,
                    selected = null,
                    onSelect = { selectedId = it?.id },
                    onClose = {},
                )
            }
        }

        composeRule.onNodeWithText("15 firma").assertIsDisplayed()
        composeRule.onNodeWithTag("report-company-results").performScrollToIndex(14)
        composeRule.onNodeWithText("Saha Firması 12").assertIsDisplayed()
        composeRule.onNodeWithTag("report-company-search").performTextInput("geb")
        composeRule.onNodeWithText("1 firma").assertIsDisplayed()
        composeRule.onNodeWithText("Gebze Üretim").assertIsDisplayed().performClick()
        composeRule.onAllNodesWithText("İzmir İnşaat").assertCountEquals(0)
        composeRule.runOnIdle { assertEquals("gebze", selectedId) }
    }

    @Test
    fun company_picker_with_15_companies_light() {
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                ReportCompanySearchSheet(
                    companies = companies,
                    selected = companies.first { it.id == "gebze" },
                    onSelect = {},
                    onClose = {},
                )
            }
        }

        composeRule.onNodeWithText("15 firma").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage()
    }

    @Test
    fun no_search_result_still_allows_continuing_without_a_company() {
        var selectedId: String? = "izmir"
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                ReportCompanySearchSheet(
                    companies = companies,
                    selected = companies.first { it.id == "izmir" },
                    onSelect = { selectedId = it?.id },
                    onClose = {},
                )
            }
        }

        composeRule.onNodeWithTag("report-company-search").performTextInput("bulunmayan firma")
        composeRule.onNodeWithText("0 firma").assertIsDisplayed()
        composeRule.onNodeWithText("Aramana uygun firma bulunamadı").assertIsDisplayed()
        composeRule.onNodeWithText("Firma seçmeden devam et").assertIsDisplayed().performClick()
        composeRule.runOnIdle { assertNull(selectedId) }
    }

    private fun company(
        id: String,
        name: String,
        address: String? = null,
        contact: String? = null,
        department: String? = null,
    ) = Company(
        id = id,
        userId = "user",
        name = name,
        hazardClassId = "high",
        address = address,
        contactPerson = contact,
        department = department,
    )
}
