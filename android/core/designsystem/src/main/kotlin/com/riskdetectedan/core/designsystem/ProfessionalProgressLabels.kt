package com.riskdetectedan.core.designsystem

import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource

@StringRes
private fun professionalProgressTitleLabelRes(key: String): Int = when (key) {
    "field_observer" -> R.string.rd_title_field_observer
    "risk_hunter" -> R.string.rd_title_risk_hunter
    "hazard_analyst" -> R.string.rd_title_hazard_analyst
    "senior_risk_specialist" -> R.string.rd_title_senior_risk_specialist
    "safety_strategist" -> R.string.rd_title_safety_strategist
    "master_hse_specialist" -> R.string.rd_title_master_hse_specialist
    else -> R.string.rd_title_candidate
}

@Composable
fun professionalProgressTitleLabel(key: String): String =
    stringResource(professionalProgressTitleLabelRes(key))

@StringRes
private fun professionalProgressCompetencyLabelRes(key: String): Int = when (key) {
    "chemical" -> R.string.rd_competency_chemical
    "electrical" -> R.string.rd_competency_electrical
    "mechanical" -> R.string.rd_competency_mechanical
    "ergonomics" -> R.string.rd_competency_ergonomics
    "psychosocial" -> R.string.rd_competency_psychosocial
    "working_at_height" -> R.string.rd_competency_working_at_height
    "ppe" -> R.string.rd_competency_ppe
    "mining" -> R.string.rd_competency_mining
    "construction" -> R.string.rd_competency_construction
    "factory" -> R.string.rd_competency_factory
    else -> R.string.rd_competency_fire
}

@Composable
fun professionalProgressCompetencyLabel(key: String): String =
    stringResource(professionalProgressCompetencyLabelRes(key))
