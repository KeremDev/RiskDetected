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
