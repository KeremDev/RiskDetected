package com.riskdetectedan.core.designsystem

import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource

/** Localized presentation labels for stable analysis wire IDs. */
@Composable
fun rdAnalysisCanvasTitle(canvasId: String, fallback: String = canvasId): String {
    val resource = rdAnalysisCanvasTitleResource(canvasId) ?: return fallback
    return stringResource(resource)
}

@Composable
fun rdAnalysisSectorTitle(sectorId: String, fallback: String = sectorId): String {
    val resource = rdAnalysisSectorTitleResource(sectorId) ?: return fallback
    return stringResource(resource)
}

@StringRes
fun rdAnalysisCanvasTitleResource(id: String): Int? = when (id) {
    "general" -> R.string.rd_canvas_general
    "ppe" -> R.string.rd_canvas_ppe
    "machine" -> R.string.rd_canvas_machine
    "warning_signs" -> R.string.rd_canvas_warning_signs
    "electrical" -> R.string.rd_canvas_electrical
    "sector" -> R.string.rd_canvas_sector
    "fire" -> R.string.rd_canvas_fire
    "ergonomics" -> R.string.rd_canvas_special_equipment
    "environment_measurement" -> R.string.rd_canvas_environment_measurement
    "explosion" -> R.string.rd_canvas_explosion
    "environment" -> R.string.rd_canvas_environment
    "legislation" -> R.string.rd_canvas_legislation
    "working_at_height" -> R.string.rd_canvas_working_at_height
    "mobile_equipment" -> R.string.rd_canvas_mobile_equipment
    "general_premium" -> R.string.rd_canvas_general_premium
    "construction_machinery" -> R.string.rd_canvas_construction_machinery
    else -> null
}

@StringRes
fun rdAnalysisSectorTitleResource(id: String): Int? = when (id) {
    "general" -> R.string.rd_genel
    "construction" -> R.string.rd_sector_construction
    "manufacturing" -> R.string.rd_sector_manufacturing
    "mining" -> R.string.rd_sector_mining
    "energy" -> R.string.rd_sector_energy
    "office" -> R.string.rd_sector_office
    "logistics_warehouse" -> R.string.rd_sector_logistics
    "chemical_laboratory" -> R.string.rd_sector_chemical
    "healthcare" -> R.string.rd_sector_healthcare
    "food_production" -> R.string.rd_sector_food
    "agriculture_livestock" -> R.string.rd_sector_agriculture
    "retail" -> R.string.rd_sector_retail
    "municipal_field_services" -> R.string.rd_sector_municipal
    "education" -> R.string.rd_sector_education
    "hospitality" -> R.string.rd_sector_hospitality
    "other" -> R.string.rd_sector_other
    else -> null
}
