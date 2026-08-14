package com.riskdetectedan.feature.profile

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MilitaryTech
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.res.stringResource
import com.riskdetectedan.core.data.progress.ProfessionalProgressSummary
import com.riskdetectedan.core.data.progress.ProfessionalProgressTitle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.professionalProgressTitleLabel
import com.riskdetectedan.core.designsystem.toTextStyle

/** Android counterpart of iOS `ProfessionalProgressTitlesSheet`. */
@Composable
fun ProfessionalProgressTitlesSheet(summary: ProfessionalProgressSummary, onDismiss: () -> Unit) {
    val colors = RdTheme.colors
    Column(modifier = Modifier.fillMaxWidth().background(colors.white).padding(bottom = 24.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth().height(58.dp).border(width = 0.5.dp, color = colors.line),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onDismiss) {
                Icon(Icons.Filled.Close, contentDescription = stringResource(RdR.string.rd_kapat), tint = colors.black)
            }
            Text(
                stringResource(RdR.string.rd_mesleki_unvanlar),
                modifier = Modifier.weight(1f),
                style = RdFontStyle.Callout.toTextStyle().copy(fontWeight = FontWeight.SemiBold),
                color = colors.black,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.size(48.dp))
        }

        Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 14.dp)) {
            Text(
                stringResource(RdR.string.rd_unvan_ilerleme_format, summary.profile.totalMdp),
                style = RdFontStyle.Title3.toTextStyle(),
                color = colors.black,
            )
            Text(
                summary.nextTitle?.let {
                    stringResource(RdR.string.rd_siradaki_unvan_format, professionalProgressTitleLabel(it.key))
                } ?: stringResource(RdR.string.rd_en_yuksek_unvan),
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.slate,
            )
        }

        LazyVerticalGrid(
            columns = GridCells.Fixed(3),
            modifier = Modifier.fillMaxWidth().height(330.dp).padding(horizontal = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(ProfessionalProgressTitle.entries, key = { it.key }) { title ->
                ProfessionalTitleTile(title = title, summary = summary)
            }
        }
    }
}

@Composable
private fun ProfessionalTitleTile(title: ProfessionalProgressTitle, summary: ProfessionalProgressSummary) {
    val colors = RdTheme.colors
    val earned = summary.profile.totalMdp >= title.threshold
    val current = title == summary.currentTitle
    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Box(modifier = Modifier.size(62.dp), contentAlignment = Alignment.Center) {
            Box(
                modifier = Modifier
                    .size(if (current) 58.dp else 50.dp)
                    .clip(CircleShape)
                    .background(if (earned) colors.onyx else colors.fog)
                    .border(if (current) 3.dp else 1.dp, if (current) colors.planPlus else colors.line, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.MilitaryTech,
                    contentDescription = null,
                    tint = if (earned) androidx.compose.ui.graphics.Color.White else colors.slate.copy(alpha = 0.55f),
                    modifier = Modifier.size(22.dp),
                )
            }
            if (current || !earned) {
                Icon(
                    if (current) Icons.Filled.CheckCircle else Icons.Filled.Lock,
                    contentDescription = null,
                    tint = if (current) colors.planPlus else colors.slate,
                    modifier = Modifier.align(Alignment.TopEnd).size(if (current) 18.dp else 15.dp),
                )
            }
        }
        Text(
            professionalProgressTitleLabel(title.key),
            style = RdFontStyle.Caption.toTextStyle().copy(fontWeight = FontWeight.SemiBold, fontSize = 10.5.sp),
            color = if (earned) colors.black else colors.slate,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            stringResource(RdR.string.rd_mdp_format, title.threshold),
            style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 9.sp),
            color = colors.slate,
        )
    }
}
