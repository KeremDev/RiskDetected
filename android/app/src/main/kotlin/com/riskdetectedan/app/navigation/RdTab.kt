package com.riskdetectedan.app.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.ui.graphics.vector.ImageVector

/** Mirrors App/Views/Components/RDTabBar.swift's `RDTab` exactly — 4 real tabs, same order,
 * same SF-Symbol-mapped icons (house/clock.arrow.circlepath/doc.text/person). */
enum class RdTab(val label: String, val icon: ImageVector) {
    Home("Ana Sayfa", Icons.Filled.Home),
    Analyses("Analizler", Icons.Filled.History),
    Reports("Raporlar", Icons.Filled.Description),
    Profile("Profil", Icons.Filled.Person),
}
