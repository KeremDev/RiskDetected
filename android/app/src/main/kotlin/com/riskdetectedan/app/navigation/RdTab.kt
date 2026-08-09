package com.riskdetectedan.app.navigation

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.annotation.StringRes

/** Mirrors App/Views/Components/RDTabBar.swift's `RDTab` exactly — 4 real tabs, same order,
 * same SF-Symbol-mapped icons (house/clock.arrow.circlepath/doc.text/person). */
enum class RdTab(@StringRes val labelRes: Int, val icon: ImageVector) {
    Home(RdR.string.rd_ana_sayfa, Icons.Filled.Home),
    Analyses(RdR.string.rd_analizler, Icons.Filled.History),
    Reports(RdR.string.rd_raporlar, Icons.Filled.Description),
    Profile(RdR.string.rd_profil, Icons.Filled.Person),
}
