package com.riskdetectedan.core.designsystem

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.FactCheck
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Android karşılığı iOS'taki koyu, erişilebilir ve ekran boyutuna uyarlanan paywall'dır. */
enum class RdPaywallDesignTier { Plus, Pro }

enum class RdPaywallDesignBilling { Yearly, Monthly }

data class RdPaywallDesignPlanOption(
    val title: String,
    val price: String,
    val caption: String,
    val trialNote: String? = null,
    val badgeLabel: String? = null,
    val badgeDiscount: String? = null,
)

data class RdPaywallDesignCta(
    val title: String,
    val isLoading: Boolean = false,
    val isDisabled: Boolean = false,
)

data class RdPaywallDesignCrossSell(
    val target: RdPaywallDesignTier,
    val prefix: String,
    val highlight: String,
    val suffix: String,
)

data class RdPaywallDesignState(
    val tier: RdPaywallDesignTier,
    val heroLabel: String,
    val tierName: String,
    val showsTrialTimeline: Boolean,
    val trialDays: Int,
    val timelineFeatures: List<RdPaywallDesignFeature>,
    val comparisonLeft: RdPaywallDesignColumn,
    val comparisonRight: RdPaywallDesignColumn,
    val comparisonRows: List<RdPaywallDesignRow>,
    val annual: RdPaywallDesignPlanOption,
    val monthly: RdPaywallDesignPlanOption,
    val selectedBilling: RdPaywallDesignBilling,
    val cta: RdPaywallDesignCta,
    val notice: String? = null,
    val errorMessage: String? = null,
    val purchaseDisclosure: String? = null,
    val crossSell: RdPaywallDesignCrossSell? = null,
)

val RdPaywallDesignTier.accent: Color
    get() = when (this) {
        RdPaywallDesignTier.Plus -> DarkPaywallColor.Gold
        RdPaywallDesignTier.Pro -> DarkPaywallColor.Green
    }

private object DarkPaywallColor {
    val Background = Color.Black
    val Sheet = Color(0xFF131316)
    val Cream = Color(0xFFF5F2EA)
    val Gold = Color(0xFFF5A524)
    val Green = Color(0xFF22C55E)
    val Primary = Color(0xFFEBEBF5).copy(alpha = 0.86f)
    val Secondary = Color(0xFFEBEBF5).copy(alpha = 0.60f)
    val Subtle = Color.White.copy(alpha = 0.08f)
    val Border = Color.White.copy(alpha = 0.13f)
}

private val MaxContentWidth = 520.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RdPaywallDesignScreen(
    state: RdPaywallDesignState,
    onClose: () -> Unit,
    onSelectBilling: (RdPaywallDesignBilling) -> Unit,
    onCta: () -> Unit,
    onRestore: () -> Unit,
    onTerms: () -> Unit,
    onPrivacy: () -> Unit,
    onManageSubscription: () -> Unit,
    onCrossSell: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scrollState = rememberScrollState()
    var showsComparison by remember { mutableStateOf(false) }
    LaunchedEffect(state.tier) { scrollState.scrollTo(0) }
    val screenTag = if (state.tier == RdPaywallDesignTier.Plus) {
        RdPaywallDesignTag.Plus
    } else {
        RdPaywallDesignTag.Pro
    }

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(DarkPaywallColor.Background)
            .testTag(screenTag),
        contentAlignment = Alignment.TopCenter,
    ) {
        val compact = maxHeight < 720.dp
        val accessibilityText = LocalDensity.current.fontScale >= 1.3f
        Column(
            modifier = Modifier
                .widthIn(max = MaxContentWidth)
                .fillMaxWidth()
                .fillMaxHeight(),
        ) {
            DarkPaywallTopBar(state.tier, state.cta.isLoading, onClose)
            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .verticalScroll(scrollState)
                    .padding(horizontal = 20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                DarkPaywallIntroduction(
                    tier = state.tier,
                    compact = compact,
                    onCompare = { showsComparison = true },
                )
                Spacer(Modifier.height(if (compact) 8.dp else 16.dp))
                DarkPaywallPlanRow(
                    option = state.annual,
                    selected = state.selectedBilling == RdPaywallDesignBilling.Yearly,
                    compact = compact,
                    enabled = !state.cta.isLoading,
                    testTag = RdPaywallDesignTag.PlanYearly,
                    onClick = { onSelectBilling(RdPaywallDesignBilling.Yearly) },
                )
                Spacer(Modifier.height(10.dp))
                DarkPaywallPlanRow(
                    option = state.monthly,
                    selected = state.selectedBilling == RdPaywallDesignBilling.Monthly,
                    compact = compact,
                    enabled = !state.cta.isLoading,
                    testTag = RdPaywallDesignTag.PlanMonthly,
                    onClick = { onSelectBilling(RdPaywallDesignBilling.Monthly) },
                )
                state.crossSell?.let {
                    Spacer(Modifier.height(10.dp))
                    DarkPaywallCrossSell(it, onCrossSell)
                }
                Spacer(Modifier.height(24.dp))
            }
            DarkPaywallFooter(
                state = state,
                accessibilityText = accessibilityText,
                onCta = onCta,
                onRestore = onRestore,
                onTerms = onTerms,
                onPrivacy = onPrivacy,
                onManageSubscription = onManageSubscription,
            )
        }
    }

    if (showsComparison) {
        DarkPaywallComparisonSheet(onDismiss = { showsComparison = false })
    }
}

@Composable
private fun DarkPaywallTopBar(
    tier: RdPaywallDesignTier,
    disabled: Boolean,
    onClose: () -> Unit,
) {
    val closeLabel = stringResource(R.string.rd_paywall_dark_close)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp)
            .padding(horizontal = 12.dp),
    ) {
        Box(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .size(44.dp)
                .clip(CircleShape)
                .clickable(enabled = !disabled, onClick = onClose)
                .semantics { contentDescription = closeLabel }
                .testTag(RdPaywallDesignTag.Close),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                modifier = Modifier
                    .size(30.dp)
                    .clip(CircleShape)
                    .background(DarkPaywallColor.Subtle),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Close, contentDescription = null, tint = DarkPaywallColor.Secondary, modifier = Modifier.size(17.dp))
            }
        }
        Row(
            modifier = Modifier
                .align(Alignment.Center)
                .clip(CircleShape)
                .background(tier.accent.copy(alpha = 0.12f))
                .border(1.dp, tier.accent.copy(alpha = 0.30f), CircleShape)
                .padding(horizontal = 11.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Icon(
                if (tier == RdPaywallDesignTier.Plus) Icons.Filled.WorkspacePremium else Icons.Filled.Star,
                contentDescription = null,
                tint = tier.accent,
                modifier = Modifier.size(13.dp),
            )
            Text(
                text = if (tier == RdPaywallDesignTier.Plus) "PLUS" else "PRO",
                color = tier.accent,
                fontSize = 11.5.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 1.3.sp,
            )
        }
    }
}

@Composable
private fun DarkPaywallIntroduction(
    tier: RdPaywallDesignTier,
    compact: Boolean,
    onCompare: () -> Unit,
) {
    val headline = stringResource(
        if (tier == RdPaywallDesignTier.Plus) R.string.rd_paywall_dark_plus_headline
        else R.string.rd_paywall_dark_pro_headline,
    )
    val features = if (tier == RdPaywallDesignTier.Plus) {
        listOf(
            stringResource(R.string.rd_paywall_dark_plus_feature_1),
            stringResource(R.string.rd_paywall_dark_plus_feature_2),
            stringResource(R.string.rd_paywall_dark_plus_feature_3),
            stringResource(R.string.rd_paywall_dark_plus_feature_4),
        )
    } else {
        listOf(
            stringResource(R.string.rd_paywall_dark_pro_feature_1),
            stringResource(R.string.rd_paywall_dark_pro_feature_2),
            stringResource(R.string.rd_paywall_dark_pro_feature_3),
            stringResource(R.string.rd_paywall_dark_pro_feature_4),
        )
    }
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(if (compact) 8.dp else 12.dp),
    ) {
        DarkPaywallAvatars(compact)
        Image(
            painter = painterResource(R.drawable.rd_paywall_users_badge),
            contentDescription = stringResource(R.string.rd_paywall_dark_users),
            contentScale = ContentScale.Fit,
            modifier = Modifier.width(if (compact) 200.dp else 220.dp).height(if (compact) 54.dp else 60.dp),
        )
        Text(
            text = headline,
            color = Color.White,
            fontSize = if (compact) 28.sp else 30.sp,
            fontWeight = FontWeight.ExtraBold,
            letterSpacing = (-0.7).sp,
            lineHeight = if (compact) 32.sp else 35.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().testTag(RdPaywallDesignTag.HeroLabel),
        )
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(if (compact) 6.dp else 7.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            features.forEach { feature ->
                Row(
                    verticalAlignment = Alignment.Top,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(
                        Icons.Filled.Check,
                        contentDescription = null,
                        tint = DarkPaywallColor.Primary,
                        modifier = Modifier.padding(top = 2.dp).size(14.dp),
                    )
                    Text(
                        text = feature,
                        color = DarkPaywallColor.Primary,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Normal,
                        lineHeight = 18.sp,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
        Row(
            modifier = Modifier
                .heightIn(min = 48.dp)
                .clip(RoundedCornerShape(12.dp))
                .clickable(onClick = onCompare)
                .padding(horizontal = 12.dp)
                .testTag(RdPaywallDesignTag.Compare),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(Icons.AutoMirrored.Filled.FactCheck, contentDescription = null, tint = DarkPaywallColor.Secondary, modifier = Modifier.size(17.dp))
            Text(
                text = stringResource(R.string.rd_paywall_dark_compare),
                color = DarkPaywallColor.Secondary,
                fontSize = 12.5.sp,
                fontWeight = FontWeight.SemiBold,
                textDecoration = androidx.compose.ui.text.style.TextDecoration.Underline,
            )
        }
    }
}

@Composable
private fun DarkPaywallAvatars(compact: Boolean) {
    val joinLabel = stringResource(R.string.rd_paywall_dark_join)
    val back = listOf(
        R.drawable.rd_paywall_join_avatar_back_1,
        R.drawable.rd_paywall_join_avatar_back_2,
        R.drawable.rd_paywall_join_avatar_back_3,
        R.drawable.rd_paywall_join_avatar_back_4,
    )
    val front = listOf(
        R.drawable.rd_paywall_join_avatar_1,
        R.drawable.rd_paywall_join_avatar_2,
        R.drawable.rd_paywall_join_avatar_3,
        R.drawable.rd_paywall_join_avatar_4,
    )
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(if (compact) 82.dp else 90.dp)
            .semantics(mergeDescendants = true) { contentDescription = joinLabel },
        contentAlignment = Alignment.TopCenter,
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy((-22).dp)) {
            back.forEach { avatar ->
                Image(
                    painter = painterResource(avatar),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.size(48.dp).clip(CircleShape).alpha(0.40f),
                )
            }
        }
        Row(
            modifier = Modifier.padding(top = 9.dp),
            horizontalArrangement = Arrangement.spacedBy((-14).dp),
        ) {
            front.forEach { avatar ->
                Image(
                    painter = painterResource(avatar),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.size(if (compact) 60.dp else 66.dp).clip(CircleShape),
                )
            }
        }
        Text(
            text = joinLabel,
            color = Color.White,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .clip(CircleShape)
                .background(Color(0xFF25252A).copy(alpha = 0.95f))
                .border(1.dp, Color.White.copy(alpha = 0.25f), CircleShape)
                .padding(horizontal = 14.dp, vertical = 5.dp),
        )
    }
}

@Composable
private fun DarkPaywallPlanRow(
    option: RdPaywallDesignPlanOption,
    selected: Boolean,
    compact: Boolean,
    enabled: Boolean,
    testTag: String,
    onClick: () -> Unit,
) {
    val description = listOfNotNull(option.title, option.price, option.caption, option.trialNote).joinToString(", ")
    val topInset = if (option.badgeLabel == null) 0.dp else 9.dp
    val shape = RoundedCornerShape(16.dp)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = topInset)
            .selectable(
                selected = selected,
                enabled = enabled,
                role = Role.RadioButton,
                onClick = onClick,
            )
            .semantics {
                contentDescription = description
                this.selected = selected
            }
            .testTag(testTag),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 58.dp)
                .clip(shape)
                .background(
                    if (selected) DarkPaywallColor.Cream.copy(alpha = 0.08f)
                    else Color.White.copy(alpha = 0.035f),
                )
                .border(
                    width = 1.5.dp,
                    color = if (selected) DarkPaywallColor.Cream else DarkPaywallColor.Border,
                    shape = shape,
                )
                .padding(horizontal = 16.dp, vertical = if (compact) 12.dp else 15.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                if (selected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                contentDescription = null,
                tint = if (selected) DarkPaywallColor.Cream else Color.White.copy(alpha = 0.30f),
                modifier = Modifier.size(22.dp),
            )
            Box(modifier = Modifier.weight(1f)) {
                // iOS only changes this HStack into a VStack for accessibility Dynamic Type.
                // Keeping the normal layout horizontal is what preserves the title-left / price-
                // right hierarchy on every phone width.
                val stacked = LocalDensity.current.fontScale >= 1.3f
                if (stacked) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        PlanTitle(option)
                        PlanPrice(option, Alignment.Start)
                    }
                } else {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(Modifier.weight(1f)) { PlanTitle(option) }
                        PlanPrice(option, Alignment.End)
                    }
                }
            }
        }
        option.badgeDiscount?.let { discount ->
            Text(
                text = discount,
                color = Color.Black,
                fontSize = 10.5.sp,
                fontWeight = FontWeight.ExtraBold,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .offset(y = (-10).dp)
                    .background(DarkPaywallColor.Green, CircleShape)
                    .padding(horizontal = 10.dp, vertical = 3.dp),
            )
        }
        option.badgeLabel?.let { badge ->
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .offset(x = (-12).dp, y = (-9).dp)
                    .height(18.dp)
                    .background(DarkPaywallColor.Gold, RoundedCornerShape(4.dp))
                    .padding(horizontal = 5.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = badge,
                    color = Color.Black,
                    fontSize = 7.25.sp,
                    lineHeight = 8.sp,
                    fontWeight = FontWeight.ExtraBold,
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
private fun PlanTitle(option: RdPaywallDesignPlanOption) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(option.title, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold)
        option.trialNote?.let {
            Text(it, color = DarkPaywallColor.Green, fontSize = 11.5.sp, fontWeight = FontWeight.Medium)
        }
    }
}

@Composable
private fun PlanPrice(option: RdPaywallDesignPlanOption, alignment: Alignment.Horizontal) {
    Column(horizontalAlignment = alignment, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(option.price, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.End)
        Text(option.caption, color = DarkPaywallColor.Secondary, fontSize = 11.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.End)
    }
}

@Composable
private fun DarkPaywallCrossSell(crossSell: RdPaywallDesignCrossSell, onClick: () -> Unit) {
    val color = if (crossSell.target == RdPaywallDesignTier.Pro) DarkPaywallColor.Green else DarkPaywallColor.Gold
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(color.copy(alpha = 0.07f))
            .border(1.dp, color.copy(alpha = 0.22f), RoundedCornerShape(14.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 13.dp, vertical = 11.dp)
            .testTag(if (crossSell.target == RdPaywallDesignTier.Pro) RdPaywallDesignTag.CrossSellPro else RdPaywallDesignTag.CrossSellPlus),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            modifier = Modifier.size(26.dp).clip(RoundedCornerShape(8.dp)).background(color.copy(alpha = 0.16f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (crossSell.target == RdPaywallDesignTier.Pro) Icons.Filled.Star else Icons.Filled.WorkspacePremium,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(14.dp),
            )
        }
        Text(
            text = crossSell.prefix + crossSell.highlight + crossSell.suffix,
            color = DarkPaywallColor.Primary,
            fontSize = 12.5.sp,
            fontWeight = FontWeight.SemiBold,
            lineHeight = 17.sp,
            modifier = Modifier.weight(1f),
        )
        Icon(Icons.Filled.ChevronRight, contentDescription = null, tint = DarkPaywallColor.Secondary, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun DarkPaywallFooter(
    state: RdPaywallDesignState,
    accessibilityText: Boolean,
    onCta: () -> Unit,
    onRestore: () -> Unit,
    onTerms: () -> Unit,
    onPrivacy: () -> Unit,
    onManageSubscription: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(DarkPaywallColor.Background)
            .padding(start = 20.dp, end = 20.dp, top = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.07f)))
        (state.errorMessage ?: state.notice)?.let { message ->
            Text(
                text = message,
                color = if (state.errorMessage == null) DarkPaywallColor.Primary else Color(0xFFFF8C8C),
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(8.dp)
                    .testTag(if (state.errorMessage == null) RdPaywallDesignTag.Notice else RdPaywallDesignTag.Error),
            )
        }
        if (state.tier == RdPaywallDesignTier.Plus &&
            state.selectedBilling == RdPaywallDesignBilling.Yearly &&
            state.showsTrialTimeline
        ) {
            Text(
                text = stringResource(R.string.rd_paywall_dark_no_charge),
                color = DarkPaywallColor.Green,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
            )
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 50.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(if (state.cta.isDisabled) Color.White.copy(alpha = 0.12f) else DarkPaywallColor.Cream)
                .clickable(enabled = !state.cta.isDisabled, onClick = onCta)
                .padding(horizontal = 12.dp, vertical = 10.dp)
                .testTag(RdPaywallDesignTag.Cta),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
        ) {
            if (state.cta.isLoading) {
                CircularProgressIndicator(
                    color = Color.Black,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.width(8.dp))
            }
            Text(
                text = state.cta.title,
                color = if (state.cta.isDisabled) Color.White.copy(alpha = 0.50f) else Color.Black,
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
            )
            if (!state.cta.isLoading) {
                Spacer(Modifier.width(8.dp))
                Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null, tint = if (state.cta.isDisabled) Color.White.copy(alpha = 0.50f) else Color.Black, modifier = Modifier.size(18.dp))
            }
        }
        state.purchaseDisclosure?.let { disclosure ->
            Text(
                text = disclosure,
                color = DarkPaywallColor.Secondary,
                fontSize = 10.5.sp,
                fontWeight = FontWeight.Medium,
                lineHeight = 14.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().testTag(RdPaywallDesignTag.AutoRenew),
            )
        }
        val links = listOf(
            Triple(stringResource(R.string.rd_gizlilik), RdPaywallDesignTag.Privacy, onPrivacy),
            Triple(stringResource(R.string.rd_paywall_design_footer_terms), RdPaywallDesignTag.Terms, onTerms),
            Triple(stringResource(R.string.rd_geri_yukle), RdPaywallDesignTag.Restore, onRestore),
            Triple(stringResource(R.string.rd_paywall_design_footer_manage), RdPaywallDesignTag.Manage, onManageSubscription),
        )
        if (accessibilityText) {
            Column {
                Row(Modifier.fillMaxWidth()) {
                    links.take(2).forEach { (label, tag, action) -> DarkFooterLink(label, tag, action, Modifier.weight(1f)) }
                }
                Row(Modifier.fillMaxWidth()) {
                    links.drop(2).forEach { (label, tag, action) -> DarkFooterLink(label, tag, action, Modifier.weight(1f)) }
                }
            }
        } else {
            Row(Modifier.fillMaxWidth()) {
                links.forEach { (label, tag, action) -> DarkFooterLink(label, tag, action, Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun DarkFooterLink(label: String, tag: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    TextButton(
        onClick = onClick,
        modifier = modifier.heightIn(min = 44.dp).testTag(tag),
    ) {
        Text(label, color = DarkPaywallColor.Secondary, fontSize = 10.5.sp, fontWeight = FontWeight.Medium, maxLines = 1)
    }
}

private data class DarkComparisonRow(
    val title: String,
    val free: RdPaywallDesignMark,
    val plus: RdPaywallDesignMark,
    val pro: RdPaywallDesignMark,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DarkPaywallComparisonSheet(onDismiss: () -> Unit) {
    val plusRows = RdPaywallDesignCopy.freeVersusPlusRows()
    val proRows = RdPaywallDesignCopy.plusVersusProRows()
    val rows = plusRows.map { row ->
        DarkComparisonRow(
            title = row.title,
            free = row.left,
            plus = row.right,
            pro = proRows.firstOrNull { it.title == row.title }?.right ?: row.right,
        )
    } + proRows.filter { pro -> plusRows.none { it.title == pro.title } }.map { row ->
        DarkComparisonRow(row.title, RdPaywallDesignMark.Cross, row.left, row.right)
    } + listOf(
        DarkComparisonRow(stringResource(R.string.rd_paywall_dark_expert), RdPaywallDesignMark.Cross, RdPaywallDesignMark.Check(DarkPaywallColor.Green), RdPaywallDesignMark.Check(DarkPaywallColor.Green)),
        DarkComparisonRow(stringResource(R.string.rd_paywall_dark_training), RdPaywallDesignMark.Cross, RdPaywallDesignMark.Check(DarkPaywallColor.Green), RdPaywallDesignMark.Check(DarkPaywallColor.Green)),
        DarkComparisonRow(stringResource(R.string.rd_paywall_dark_notebook), RdPaywallDesignMark.Cross, RdPaywallDesignMark.Check(DarkPaywallColor.Green), RdPaywallDesignMark.Check(DarkPaywallColor.Green)),
        DarkComparisonRow(stringResource(R.string.rd_paywall_dark_reports), RdPaywallDesignMark.Cross, RdPaywallDesignMark.Check(DarkPaywallColor.Green), RdPaywallDesignMark.Check(DarkPaywallColor.Green)),
    )
    val accessibilityText = LocalDensity.current.fontScale >= 1.3f
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = DarkPaywallColor.Sheet,
        contentColor = Color.White,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp)
                .testTag(RdPaywallDesignTag.ComparisonTable),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.AutoMirrored.Filled.FactCheck, contentDescription = null, tint = Color.White, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.rd_paywall_dark_compare), fontSize = 17.sp, fontWeight = FontWeight.ExtraBold)
            }
            if (!accessibilityText) {
                Row(modifier = Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(stringResource(R.string.rd_paywall_dark_feature), color = DarkPaywallColor.Secondary, fontSize = 10.5.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    ComparisonHeader("FREE", DarkPaywallColor.Secondary)
                    ComparisonHeader("PLUS", DarkPaywallColor.Gold)
                    ComparisonHeader("PRO", DarkPaywallColor.Green)
                }
            }
            rows.forEach { row ->
                if (accessibilityText) {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Text(row.title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                        DarkComparisonValue("FREE", row.free, DarkPaywallColor.Secondary)
                        DarkComparisonValue("PLUS", row.plus, DarkPaywallColor.Gold)
                        DarkComparisonValue("PRO", row.pro, DarkPaywallColor.Green)
                    }
                } else {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 5.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(row.title, color = DarkPaywallColor.Primary, fontSize = 12.5.sp, fontWeight = FontWeight.Medium, lineHeight = 16.sp, modifier = Modifier.weight(1f))
                        DarkComparisonMark(row.free, DarkPaywallColor.Secondary)
                        DarkComparisonMark(row.plus, DarkPaywallColor.Gold)
                        DarkComparisonMark(row.pro, DarkPaywallColor.Green)
                    }
                }
                Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.08f)))
            }
            TextButton(
                onClick = onDismiss,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .background(Color.White.copy(alpha = 0.10f), RoundedCornerShape(14.dp)),
            ) {
                Text(stringResource(R.string.rd_paywall_dark_close), color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun ComparisonHeader(title: String, color: Color) {
    Text(title, color = color, fontSize = 10.5.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.width(52.dp))
}

@Composable
private fun DarkComparisonValue(title: String, mark: RdPaywallDesignMark, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(title, color = color, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        DarkComparisonMark(mark, color, fixedWidth = false)
    }
}

@Composable
private fun DarkComparisonMark(mark: RdPaywallDesignMark, color: Color, fixedWidth: Boolean = true) {
    val included = stringResource(R.string.rd_paywall_dark_included)
    val unavailable = stringResource(R.string.rd_paywall_dark_unavailable)
    Box(
        modifier = if (fixedWidth) Modifier.width(52.dp) else Modifier,
        contentAlignment = Alignment.Center,
    ) {
        when (mark) {
            RdPaywallDesignMark.Cross -> Icon(
                Icons.Filled.Remove,
                contentDescription = unavailable,
                tint = color,
                modifier = Modifier.size(15.dp),
            )
            is RdPaywallDesignMark.Check -> Icon(
                Icons.Filled.Check,
                contentDescription = included,
                tint = color,
                modifier = Modifier.size(15.dp),
            )
            is RdPaywallDesignMark.Value -> Text(
                mark.text,
                color = color,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
            )
        }
    }
}
