package com.riskdetectedan.feature.profile

import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.referral.ReferralDashboard
import com.riskdetectedan.core.data.referral.ReferralDeepLinkStore
import com.riskdetectedan.core.data.referral.ReferralRewardsRepository
import com.riskdetectedan.core.designsystem.RdTheme
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import javax.inject.Inject

data class ReferralMessage(val title: String, val detail: String)

/** The invite page's state (iOS `ReferralRewardsView`). */
@HiltViewModel
class ReferralRewardsViewModel @Inject constructor(
    private val repository: ReferralRewardsRepository,
    private val deepLinks: ReferralDeepLinkStore,
) : ViewModel() {
    private val _dashboard = MutableStateFlow<ReferralDashboard?>(null)
    val dashboard: StateFlow<ReferralDashboard?> = _dashboard.asStateFlow()
    private val _loading = MutableStateFlow(true)
    val loading: StateFlow<Boolean> = _loading.asStateFlow()
    private val _working = MutableStateFlow(false)
    val working: StateFlow<Boolean> = _working.asStateFlow()
    private val _message = MutableStateFlow<ReferralMessage?>(null)
    val message: StateFlow<ReferralMessage?> = _message.asStateFlow()
    val openRequested: StateFlow<Boolean> = deepLinks.openRequested

    /** A code that arrived through an invite link fills the claim field. */
    val pendingCode: String get() = deepLinks.pendingCode.orEmpty()

    fun consumeOpen() = deepLinks.consumeOpen()

    fun requestOpen() = deepLinks.requestOpen()

    fun load() {
        viewModelScope.launch {
            _loading.value = _dashboard.value == null
            try {
                _dashboard.value = repository.dashboard()
                repository.track("screen_viewed")
            } catch (error: Exception) {
                _message.value = ReferralMessage("Davet programı açılamadı", ReferralRewardsRepository.message(error))
            }
            _loading.value = false
        }
    }

    fun track(event: String) { viewModelScope.launch { repository.track(event) } }

    fun copied() {
        track("code_copied")
        _message.value = ReferralMessage("Kod kopyalandı", "Davet kodunu istediğin yerde paylaşabilirsin.")
    }

    fun claim(code: String) {
        if (!ReferralRewardsRepository.isValidCode(code) || _working.value) return
        _working.value = true
        viewModelScope.launch {
            try {
                val result = repository.claim(code)
                deepLinks.clear()
                _dashboard.value = repository.dashboard()
                _message.value = ReferralMessage(if (result.replayed) "Davet zaten bağlı" else "Davet kabul edildi",
                    "${result.qualificationDays ?: 2} farklı günde gerçek bir işlem yaptığında iki tarafın da ödülü hazır olacak.")
            } catch (error: Exception) {
                _message.value = ReferralMessage("Kod kullanılamadı", ReferralRewardsRepository.message(error))
            }
            _working.value = false
        }
    }

    /** [onPlanChanged] rereads the account's plan once a reward has started. */
    fun activate(reward: ReferralDashboard.Reward, onPlanChanged: () -> Unit) {
        if (_working.value) return
        _working.value = true
        viewModelScope.launch {
            repository.track("reward_activation_started")
            try {
                val result = repository.activate(reward.instanceId)
                when {
                    result.activated -> {
                        onPlanChanged()
                        _dashboard.value = repository.dashboard()
                        _message.value = ReferralMessage("Plus ödülün başladı", "7 günlük Plus erişimin otomatik yenileme olmadan etkinleştirildi.")
                    }
                    result.reason == "PAID_ACCESS_ACTIVE" -> _message.value = ReferralMessage("Ödülün güvende",
                        "Aktif ücretli planın varken süreyi başlatmıyoruz. Planın sona erdiğinde bu ekrandan kullanabilirsin.")
                    result.reason == "GIFT_ALREADY_ACTIVE" -> _message.value = ReferralMessage("Aktif bir ödülün var",
                        "Mevcut hediye süren bittikten sonra sıradaki ödülü başlatabilirsin.")
                }
            } catch (error: Exception) {
                _message.value = ReferralMessage("Ödül başlatılamadı", ReferralRewardsRepository.message(error))
            }
            _working.value = false
        }
    }

    fun dismissMessage() { _message.value = null }
}

/** "Arkadaşını davet et" (iOS `ReferralRewardsView`): the code, its share link, rewards and invite progress. */
@Composable
fun ReferralRewardsScreen(onClose: () -> Unit, onPlanChanged: () -> Unit, viewModel: ReferralRewardsViewModel = hiltViewModel()) {
    BackHandler(onBack = onClose)
    val colors = RdTheme.colors
    val dashboard by viewModel.dashboard.collectAsState()
    val loading by viewModel.loading.collectAsState()
    val working by viewModel.working.collectAsState()
    val message by viewModel.message.collectAsState()
    var claimCode by remember { mutableStateOf(viewModel.pendingCode) }
    var termsExpanded by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    LaunchedEffect(Unit) { viewModel.load() }
    Column(Modifier.fillMaxSize().background(colors.paper).testTag("referral.root")) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.size(48.dp).clip(RoundedCornerShape(16.dp)).background(colors.white).clickable(onClick = onClose),
                contentAlignment = Alignment.Center) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, "Kapat", tint = colors.ink)
            }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Arkadaşını davet et", style = TextStyle(fontSize = 25.sp, fontWeight = FontWeight.Bold), color = colors.ink)
                Text("Birlikte Plus kazanın", style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium), color = colors.slate)
            }
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 112.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            val value = dashboard
            when {
                loading -> Card {
                    Column(Modifier.fillMaxWidth().padding(vertical = 32.dp), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        CircularProgressIndicator(color = colors.green)
                        Text("Davet programı hazırlanıyor", style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold), color = colors.slate)
                    }
                }
                value == null -> Card {
                    Column(Modifier.fillMaxWidth().padding(vertical = 26.dp), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        Icon(Icons.Filled.WifiOff, null, Modifier.size(30.dp), tint = colors.critical)
                        Text("Davet bilgileri alınamadı", style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Bold), color = colors.ink)
                        PrimaryButton("Tekrar dene", colors.green, enabled = true, modifier = Modifier) { viewModel.load() }
                    }
                }
                else -> {
                    Hero(value)
                    Card {
                        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            Text("Davet kodun", style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold), color = colors.slate)
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(value.referralCode, Modifier.weight(1f).testTag("referral.code"),
                                    style = TextStyle(fontSize = 29.sp, fontWeight = FontWeight.Black, letterSpacing = 3.sp), color = colors.ink)
                                Row(Modifier.height(42.dp).clip(CircleShape).background(colors.fog).clickable {
                                    clipboard.setText(AnnotatedString(value.referralCode)); viewModel.copied()
                                }.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Icon(Icons.Filled.ContentCopy, null, Modifier.size(16.dp), tint = colors.ink)
                                    Text("Kopyala", style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold), color = colors.ink)
                                }
                            }
                            PrimaryButton("Davet bağlantısını paylaş", colors.green, enabled = true, modifier = Modifier.fillMaxWidth().testTag("referral.share"),
                                icon = Icons.Filled.Share) {
                                viewModel.track("share_started")
                                context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                                    type = "text/plain"; putExtra(Intent.EXTRA_TEXT, value.shareMessage)
                                }, null))
                            }
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Metric("Gönderilen", value.counts.invited, Icons.AutoMirrored.Filled.Send, Modifier.weight(1f))
                        Metric("Tamamlayan", value.counts.qualified, Icons.Filled.CheckCircle, Modifier.weight(1f))
                        Metric("Ödül", value.counts.rewarded, Icons.Filled.CardGiftcard, Modifier.weight(1f))
                    }
                    if (value.rewards.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        SectionTitle("Ödüllerin")
                        value.rewards.forEach { reward -> RewardCard(reward, working) { viewModel.activate(reward, onPlanChanged) } }
                    }
                    Card {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            SectionTitle("Bir davet kodun mu var?")
                            Text("Kodu bir kez kabul edebilirsin. Kendi kodun kullanılamaz.", style = TextStyle(fontSize = 14.sp), color = colors.slate)
                            val canClaim = ReferralRewardsRepository.isValidCode(claimCode)
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                                androidx.compose.foundation.text.BasicTextField(claimCode, { typed ->
                                    claimCode = typed.uppercase().filter { it.isLetterOrDigit() }.take(12)
                                }, Modifier.weight(1f).height(52.dp).clip(RoundedCornerShape(15.dp)).background(colors.fog).padding(horizontal = 14.dp)
                                    .wrapContentHeight(Alignment.CenterVertically).testTag("referral.code.input"), singleLine = true,
                                    textStyle = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, color = colors.ink),
                                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, autoCorrectEnabled = false),
                                    decorationBox = { inner ->
                                        if (claimCode.isEmpty()) Text("Davet kodu", style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Bold,
                                            fontFamily = FontFamily.Monospace), color = colors.slate)
                                        inner()
                                    })
                                PrimaryButton("Kullan", if (canClaim) colors.ink else colors.slate.copy(alpha = 0.4f), enabled = canClaim && !working,
                                    modifier = Modifier.testTag("referral.claim"), ink = colors.paper) { viewModel.claim(claimCode) }
                            }
                            value.acceptedInvites.firstOrNull()?.let { accepted ->
                                val rewarded = accepted.state == "rewarded"
                                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(colors.fog).padding(12.dp),
                                    horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Icon(if (rewarded) Icons.Filled.Verified else Icons.Filled.Schedule, null, Modifier.size(18.dp),
                                        tint = if (rewarded) colors.green else colors.planPlus)
                                    Text(acceptedInviteText(accepted), style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold), color = colors.charcoal)
                                }
                            }
                        }
                    }
                    if (value.sentInvites.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        SectionTitle("Davetlerin")
                        value.sentInvites.forEach { invite ->
                            val tone = statusColor(invite.state)
                            Card {
                                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Box(Modifier.size(10.dp).background(tone, CircleShape))
                                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                        Text(statusTitle(invite.state), style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Bold), color = colors.ink)
                                        Text("Kabul: ${formatted(invite.claimedAt)}", style = TextStyle(fontSize = 12.sp), color = colors.slate)
                                    }
                                    Text(statusBadge(invite.state), Modifier.height(28.dp).clip(CircleShape).background(tone.copy(alpha = 0.10f))
                                        .padding(horizontal = 9.dp).wrapContentHeight(Alignment.CenterVertically),
                                        style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Bold), color = tone)
                                }
                            }
                        }
                    }
                    Card(Modifier.animateContentSize()) {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Row(Modifier.fillMaxWidth().clickable { termsExpanded = !termsExpanded }, verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Icon(Icons.Filled.Info, null, Modifier.size(18.dp), tint = colors.ink)
                                Text("Nasıl çalışır?", Modifier.weight(1f), style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Bold), color = colors.ink)
                                Icon(if (termsExpanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null, tint = colors.slate)
                            }
                            if (termsExpanded) Text("Davet edilen kişi kodu kabul ettikten sonra ${value.campaign.qualificationWindowDays} gün içinde iki farklı " +
                                "günde personel, işyeri, departman, eğitim, risk değerlendirmesi, rapor veya tamamlanmış kontrol listesi işlemi yapmalıdır. " +
                                "Görüntüleme ve başarısız işlemler sayılmaz. Ödül mağaza aboneliği değildir; otomatik yenilenmez ve kotayı sıfırlamaz.",
                                style = TextStyle(fontSize = 13.sp), color = colors.slate)
                        }
                    }
                }
            }
        }
    }
    message?.let { shown ->
        AlertDialog(onDismissRequest = viewModel::dismissMessage, title = { Text(shown.title) }, text = { Text(shown.detail) },
            confirmButton = { TextButton(onClick = viewModel::dismissMessage) { Text("Tamam") } })
    }
}

@Composable
private fun Card(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val colors = RdTheme.colors
    Box(modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(colors.white)
        .border(1.dp, colors.line, RoundedCornerShape(20.dp)).padding(16.dp)) { content() }
}

@Composable
private fun SectionTitle(value: String) =
    Text(value, style = TextStyle(fontSize = 19.sp, fontWeight = FontWeight.Bold), color = RdTheme.colors.ink)

@Composable
private fun PrimaryButton(title: String, fill: Color, enabled: Boolean, modifier: Modifier, icon: ImageVector? = null, ink: Color = Color.White,
                          onClick: () -> Unit) {
    Row(modifier.height(52.dp).clip(RoundedCornerShape(15.dp)).background(fill).clickable(enabled = enabled, onClick = onClick).padding(horizontal = 18.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
        icon?.let { Icon(it, null, Modifier.size(18.dp), tint = ink) }
        Text(title, style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Bold), color = ink)
    }
}

@Composable
private fun Hero(value: ReferralDashboard) {
    val colors = RdTheme.colors
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp))
        .background(Brush.linearGradient(listOf(colors.planPlusSoft, colors.white)))
        .border(1.dp, colors.planPlus.copy(alpha = 0.25f), RoundedCornerShape(22.dp)).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(48.dp).clip(RoundedCornerShape(15.dp)).background(colors.planPlusSoft), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.CardGiftcard, null, Modifier.size(25.dp), tint = colors.planPlusDark)
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("İkiniz de ${value.campaign.rewardDays} gün Plus kazanın", style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Bold), color = colors.ink)
                Text("Arkadaşın kodunu kabul edip ${value.campaign.qualificationWindowDays} gün içinde, iki farklı günde gerçek bir işlem yaptığında " +
                    "ödülleriniz hazır olur.", style = TextStyle(fontSize = 15.sp), color = colors.charcoal)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            StepPill("1", "Kodu paylaş", Modifier.weight(1f))
            Icon(Icons.Filled.ChevronRight, null, tint = colors.slate)
            StepPill("2", "2 gün kullan", Modifier.weight(1f))
            Icon(Icons.Filled.ChevronRight, null, tint = colors.slate)
            StepPill("3", "Ödülü aç", Modifier.weight(1f))
        }
    }
}

@Composable
private fun StepPill(number: String, title: String, modifier: Modifier) {
    val colors = RdTheme.colors
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(number, Modifier.size(24.dp).background(colors.ink, CircleShape).wrapContentHeight(Alignment.CenterVertically),
            style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center), color = colors.paper)
        Text(title, style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center), color = colors.charcoal, maxLines = 2)
    }
}

@Composable
private fun Metric(title: String, value: Int, icon: ImageVector, modifier: Modifier) {
    val colors = RdTheme.colors
    Column(modifier.clip(RoundedCornerShape(18.dp)).background(colors.white).padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, null, Modifier.size(18.dp), tint = colors.greenDark)
        Text("$value", style = TextStyle(fontSize = 24.sp, fontWeight = FontWeight.Bold), color = colors.ink)
        Text(title, style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold), color = colors.slate, maxLines = 1)
    }
}

@Composable
private fun RewardCard(reward: ReferralDashboard.Reward, working: Boolean, onActivate: () -> Unit) {
    val colors = RdTheme.colors
    Card {
        Row(horizontalArrangement = Arrangement.spacedBy(13.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(colors.planPlusSoft), contentAlignment = Alignment.Center) {
                Icon(if (reward.state == "active") Icons.Filled.AutoAwesome else Icons.Filled.CardGiftcard, null, Modifier.size(20.dp), tint = colors.planPlusDark)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(when (reward.state) { "active" -> "Plus ödülün aktif"; "expired" -> "Plus ödülü kullanıldı"; else -> "7 günlük Plus hazır" },
                    style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Bold), color = colors.ink)
                Text(when {
                    reward.state == "active" && reward.expiresAt != null -> "${formatted(reward.expiresAt!!)} tarihine kadar"
                    reward.state == "expired" -> "Bu ödülün süresi tamamlandı"
                    else -> "Hazır olduğunda süreyi sen başlat"
                }, style = TextStyle(fontSize = 13.sp), color = colors.slate)
            }
            if (reward.state == "earned" || reward.state == "available")
                PrimaryButton("Başlat", colors.green, enabled = !working, modifier = Modifier.height(40.dp).testTag("referral.reward.activate"), onClick = onActivate)
        }
    }
}

private fun acceptedInviteText(invite: ReferralDashboard.Invite) = when (invite.state) {
    "rewarded" -> "Koşulları tamamladın; ödülün hazır."
    "qualified" -> "İşlemlerin doğrulandı; ödül hazırlanıyor."
    else -> "İlerleme: ${invite.distinctDays ?: 0}/${invite.requiredDays ?: 2} farklı gün"
}

private fun statusTitle(state: String) = when (state) {
    "rewarded" -> "Ödül kazanıldı"; "qualified" -> "Koşul tamamlandı"; "rejected", "expired" -> "Davet tamamlanmadı"; else -> "Kodu kabul etti"
}

private fun statusBadge(state: String) = when (state) {
    "rewarded" -> "Kazanıldı"; "qualified" -> "Tamamlandı"; "rejected", "expired" -> "Kapandı"; else -> "Bekliyor"
}

@Composable
private fun statusColor(state: String): Color = when (state) {
    "rewarded", "qualified" -> RdTheme.colors.green
    "rejected", "expired" -> RdTheme.colors.critical
    else -> RdTheme.colors.planPlus
}

private fun formatted(value: String): String = runCatching {
    DateTimeFormatter.ofPattern("d MMM yyyy", Locale.forLanguageTag("tr-TR")).withZone(ZoneId.systemDefault()).format(Instant.parse(value))
}.getOrElse {
    runCatching {
        DateTimeFormatter.ofPattern("d MMM yyyy", Locale.forLanguageTag("tr-TR")).format(java.time.OffsetDateTime.parse(value))
    }.getOrDefault(value)
}
