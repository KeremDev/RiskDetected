package com.riskdetectedan.isg.designpreview

import com.riskdetectedan.core.data.company.Company
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.feature.nova.NovaCompanyWorkspaceClient

/** A synthetic company page; nothing leaves the process. */
internal val PreviewCompanyClient = NovaCompanyWorkspaceClient(
    summary = { NovaCompanySummary("c1", "u1", "Koza Altın A.Ş", "high", false, "Maden", personnelCount = 42, workplaceCount = 3, departmentCount = 4) },
    record = { Company("c1", "u1", "Koza Altın A.Ş", "high", contactPerson = "Ayşe Demir") },
    logo = { null },
    saveLogo = { company, _ -> company },
    saveCompany = { draft -> Company("c1", "u1", draft.name, draft.hazardClass.id, contactPerson = draft.contactPerson) },
    nonconformities = { emptyList() },
    completedTrainings = { 1 },
    tracking = { PreviewStatisticsClient.tracking("c1") },
    equipment = { PreviewEquipmentClient.board(NovaEquipmentQuery(company = "c1", limit = 5)) },
    risk = { PreviewRiskClient.board(NovaRiskQuery(company = "c1", limit = 1)) },
    appointments = { NovaAppointmentBoard(emptyList(), emptyMap(), emptyList(), 0, false, 0) },
    fileCategories = { emptyList() },
    files = { NovaFileLibraryPage() },
)

/** Synthetic personnel kept in memory for the company page preview. */
internal object PreviewPersonnel {
    private val owner = java.util.UUID.fromString("11000000-0000-4000-8000-000000000001")
    val scope = com.riskdetectedan.core.designsystem.isg.NovaPersonnelScope(owner, java.util.UUID.randomUUID(),
        java.util.UUID.fromString("24000000-0000-4000-8000-000000000001"), "preview")
    private val rows = mutableListOf(
        com.riskdetectedan.core.designsystem.isg.NovaEmployeeRow(java.util.UUID.fromString("00000000-0000-4000-8000-000000000001"), owner, scope.companyID,
            "Mehmet Kaya", null, "Bakım", 0, false, "Elektrik teknisyeni"),
        com.riskdetectedan.core.designsystem.isg.NovaEmployeeRow(java.util.UUID.fromString("00000000-0000-4000-8000-000000000002"), owner, scope.companyID,
            "Elif Şahin", null, "Kırma eleme", 0, false))
    val client = com.riskdetectedan.core.designsystem.isg.NovaPersonnelClient(
        employees = { _, query, _, _ -> com.riskdetectedan.core.designsystem.isg.NovaEmployeePage(rows.filter { it.name.contains(query, true) }, null) },
        departments = { _, _, _ -> com.riskdetectedan.core.designsystem.isg.NovaDepartmentPage(emptyList(), null) },
        detail = { _, id -> rows.first { it.id == id } },
        save = { throw com.riskdetectedan.core.designsystem.isg.NovaPersonnelFailure(com.riskdetectedan.core.designsystem.isg.NovaPersonnelFailure.Kind.denied) },
    )
}
