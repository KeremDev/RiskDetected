package com.riskdetectedan.feature.profile

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Construction
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.EventAvailable
import androidx.compose.material.icons.filled.Factory
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Height
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.MilitaryTech
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Terrain
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Warning
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import com.riskdetectedan.core.data.progress.ProfessionalProgressCompetency
import com.riskdetectedan.core.designsystem.RdColors

/**
 * SF Symbol name -> Material icon lookup for real `professional_progress_badges.icon_name`
 * values (see `private.pp_unlock_badges_for_user` in
 * `supabase/migrations/20260526093512_professional_progress_module.sql` — the actual server-side
 * badge catalog is much larger than [ProfessionalProgressBadgesSheet]'s curated 6-item display
 * catalog, e.g. `reports:1`/`reports:1000`/`competency:11`/`report_kind:first_risk_analysis` all
 * unlock real rows a user can earn and get celebrated for). Covers every `icon_name` literal
 * actually used by that function; unknown names fall back to a generic rosette so a future
 * server-side badge never renders blank.
 */
fun sfIconToImageVector(name: String): ImageVector = when (name) {
    "medal.fill" -> Icons.Filled.MilitaryTech
    "trophy.fill" -> Icons.Filled.EmojiEvents
    "square.grid.2x2.fill", "square.grid.3x2.fill", "square.grid.3x3.fill" -> Icons.Filled.GridView
    "sparkles" -> Icons.Filled.AutoAwesome
    "exclamationmark.triangle.fill" -> Icons.Filled.Warning
    "doc.richtext.fill" -> Icons.Filled.Description
    "calendar.badge.checkmark" -> Icons.Filled.EventAvailable
    "checkmark.seal.fill" -> Icons.Filled.Verified
    "rosette" -> Icons.Filled.MilitaryTech
    else -> Icons.Filled.MilitaryTech
}

/** Real port of `ProfessionalProgressCompetency`'s `icon`/`accent` extension (kept out of
 * core:data, same reason [com.riskdetectedan.core.data.analysis.AnalysisSector]'s icon lookup
 * lives in the UI layer — core:data shouldn't depend on Compose). */
fun competencyIcon(competency: ProfessionalProgressCompetency): ImageVector = when (competency) {
    ProfessionalProgressCompetency.Fire -> Icons.Filled.LocalFireDepartment
    ProfessionalProgressCompetency.Chemical -> Icons.Filled.Science
    ProfessionalProgressCompetency.Electrical -> Icons.Filled.Bolt
    ProfessionalProgressCompetency.Mechanical -> Icons.Filled.Settings
    ProfessionalProgressCompetency.Ergonomics -> Icons.Filled.FitnessCenter
    ProfessionalProgressCompetency.Psychosocial -> Icons.Filled.Psychology
    ProfessionalProgressCompetency.WorkingAtHeight -> Icons.Filled.Height
    ProfessionalProgressCompetency.Ppe -> Icons.Filled.Shield
    ProfessionalProgressCompetency.Mining -> Icons.Filled.Terrain
    ProfessionalProgressCompetency.Construction -> Icons.Filled.Construction
    ProfessionalProgressCompetency.Factory -> Icons.Filled.Factory
}

fun competencyAccent(competency: ProfessionalProgressCompetency, colors: RdColors): Color = when (competency) {
    ProfessionalProgressCompetency.Fire -> colors.high
    ProfessionalProgressCompetency.Chemical -> colors.info
    ProfessionalProgressCompetency.Electrical -> colors.medium
    ProfessionalProgressCompetency.Mechanical -> colors.charcoal
    ProfessionalProgressCompetency.Ergonomics -> colors.low
    ProfessionalProgressCompetency.Psychosocial -> Color(0xFF7C3AED)
    ProfessionalProgressCompetency.WorkingAtHeight -> colors.critical
    ProfessionalProgressCompetency.Ppe -> colors.green
    ProfessionalProgressCompetency.Mining -> Color(0xFF475569)
    ProfessionalProgressCompetency.Construction -> colors.planPlus
    ProfessionalProgressCompetency.Factory -> Color(0xFF0F766E)
}
