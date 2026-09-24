package com.riskdetectedan.feature.profile

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.profile.UserProfile
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

private val SecurityBlue = Color(0xFF2679E8)
private val PreferencesGreen = Color(0xFF22B94F)
private val DataGray = Color(0xFF73777D)
private val SupportCyan = Color(0xFF22A7DA)
private val AchievementGold = Color(0xFFDDA830)
private val DeleteRed = Color(0xFFD64B4B)
private val DeleteInk = Color(0xFFC9393B)

/**
 * The İSGADA pilot profile (iOS `ProfileView.pilotProfileContent`, 1be96712 / 266f692c / 6576827c): the
 * avatar and handle, then grouped rows — account, security and settings, achievements, and a folded
 * "Diğer hesap seçenekleri" — with account deletion and sign-out at the bottom, on the standard canvas.
 */
@Composable
internal fun NovaPilotProfileSurface(
    profile: UserProfile,
    isSavingAvatar: Boolean,
    avatarErrorMessage: String?,
    restoreInProgress: Boolean,
    onAvatarBytes: (ByteArray) -> Unit,
    onEdit: () -> Unit,
    onNotificationSettings: () -> Unit,
    onManageCompanies: () -> Unit,
    onShowLegal: () -> Unit,
    onSubscription: () -> Unit,
    onAppearanceSettings: () -> Unit,
    onDataManagement: () -> Unit,
    onSupport: () -> Unit,
    onShowBadges: () -> Unit,
    onActivity: (() -> Unit)?,
    onNotebook: (() -> Unit)?,
    onReferrals: () -> Unit,
    onRestorePurchases: () -> Unit,
    onAnalyses: () -> Unit,
    onReports: () -> Unit,
    onDeleteAccount: () -> Unit,
    onSignOut: () -> Unit,
) {
    var showMore by rememberSaveable { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().background(NovaColorToken.canvas.color()).verticalScroll(rememberScrollState())
        .padding(horizontal = 20.dp).padding(top = 20.dp, bottom = 34.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(20.dp)) {
        PilotIdentity(profile, isSavingAvatar, avatarErrorMessage, onAvatarBytes, Modifier.padding(bottom = 6.dp))

        PilotGroup {
            PilotAction("Profil bilgileri", "person.crop.circle", Color.Gray, "profile.row.info", onEdit)
            PilotSeparator()
            PilotAction("Bildirimler", "bell", Color.Gray, "profile.row.notifications", onNotificationSettings)
            PilotSeparator()
            PilotAction("Firmalarım", "building.2", Color.Gray, "profile.row.companies", onManageCompanies)
        }
        PilotGroup {
            PilotAction("Güvenlik ve gizlilik", "shield.lefthalf.filled", SecurityBlue, "profile.row.security", onShowLegal)
            PilotSeparator()
            PilotAction("Abonelik ve ödeme", "creditcard", SecurityBlue, "profile.row.subscription", onSubscription)
            PilotSeparator()
            PilotAction("Görünüm ve tercihler", "slider.horizontal.3", PreferencesGreen, "profile.row.preferences", onAppearanceSettings)
            PilotSeparator()
            PilotAction("Verilerim", "externaldrive", DataGray, "profile.row.data", onDataManagement)
            PilotSeparator()
            PilotAction("Yardım ve destek", "questionmark.circle", SupportCyan, "profile.row.support", onSupport)
        }
        PilotGroup {
            PilotAction("Başarılarım", "rosette", AchievementGold, "profile.row.badges", onShowBadges)
            if (onActivity != null) {
                PilotSeparator()
                PilotAction("Aktivitem", "bolt", AchievementGold, "profile.row.activity", onActivity)
            }
        }
        PilotGroup(Modifier.animateContentSize(tween(200))) {
            PilotProfileRow("ellipsis", "Diğer hesap seçenekleri", DataGray, Modifier.testTag("profile.row.more"),
                trailingSymbol = if (showMore) "chevron.up" else "chevron.down") { showMore = !showMore }
            if (showMore) {
                PilotSeparator()
                if (onNotebook != null) {
                    PilotAction("Kişisel notlar", "note.text", PreferencesGreen, "profile.row.notebook", onNotebook)
                    PilotSeparator()
                }
                PilotAction("Arkadaşını davet et", "gift", AchievementGold, "profile.row.referral", onReferrals)
                PilotSeparator()
                PilotAction("Satın alımları geri yükle", "arrow.clockwise", SecurityBlue, "profile.row.restore_purchases",
                    onRestorePurchases, enabled = !restoreInProgress)
                PilotSeparator()
                PilotAction("Geçmiş analizler", "doc.text.magnifyingglass", DataGray, "profile.row.history", onAnalyses)
                PilotSeparator()
                PilotAction("Raporlarım", "doc.text", DataGray, "profile.row.reports", onReports)
            }
        }
        PilotProfileRow("trash", "Hesabımı sil", DeleteRed,
            Modifier.clip(RoundedCornerShape(20.dp)).background(NovaColorToken.surface.color(), RoundedCornerShape(20.dp))
                .border(1.dp, NovaColorToken.hairline.color(), RoundedCornerShape(20.dp)).testTag("profile.row.delete_account"),
            titleColor = DeleteInk, onClick = onDeleteAccount)
        Box(Modifier.fillMaxWidth().heightIn(min = 54.dp).novaRowPress(onClick = onSignOut).testTag("profile.row.sign_out"),
            contentAlignment = Alignment.Center) {
            NovaText("Çıkış yap", style = NovaTypeToken.bodyStrong, color = DeleteInk)
        }
    }
}

@Composable
private fun PilotIdentity(profile: UserProfile, isSavingAvatar: Boolean, avatarErrorMessage: String?,
                          onAvatarBytes: (ByteArray) -> Unit, modifier: Modifier) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var readError by remember { mutableStateOf<String?>(null) }
    val pickAvatar = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        readError = null
        scope.launch {
            try { onAvatarBytes(prepareAvatarJpeg(context, uri)) }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Throwable) { readError = "Fotoğraf okunamadı." }
        }
    }
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(100.dp).novaRowPress(enabled = !isSavingAvatar) {
            pickAvatar.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
        }.semantics { contentDescription = "Profil fotoğrafını değiştir" }.testTag("profile.avatar")) {
            Box(Modifier.fillMaxSize().clip(CircleShape).background(Color(0xFFD2FFD9)), contentAlignment = Alignment.Center) {
                val path = profile.avatarUrl
                if (!path.isNullOrBlank()) ProfileAvatarImage(path = path, modifier = Modifier.fillMaxSize().clip(CircleShape))
                else NovaSizedText(profile.displayInitials.ifBlank { "—" }, 32f, FontWeight.SemiBold, Color(0xFF15803D))
                if (isSavingAvatar) CircularProgressIndicator(Modifier.size(28.dp), color = Color(0xFF15803D), strokeWidth = 2.dp)
            }
            Box(Modifier.align(Alignment.BottomEnd).offset(1.dp, 1.dp).size(28.dp)
                .background(NovaColorToken.surface.color(), CircleShape).border(1.dp, NovaColorToken.hairline.color(), CircleShape),
                contentAlignment = Alignment.Center) {
                NovaIcon("camera", 13.dp, tint = NovaColorToken.textSecondary.color())
            }
        }
        NovaText(profile.displayName, Modifier.padding(top = 4.dp), NovaTypeToken.screenTitle, textAlign = TextAlign.Center)
        NovaText(pilotHandle(profile), style = NovaTypeToken.body, color = NovaColorToken.textSecondary.color(), maxLines = 1)
        (readError ?: avatarErrorMessage)?.let { NovaText(it, style = NovaTypeToken.meta, color = DeleteInk, textAlign = TextAlign.Center) }
    }
}

/** iOS `pilotHandle`: "@" and the e-mail's local part, else the professional title. */
private fun pilotHandle(profile: UserProfile): String {
    val local = profile.email?.substringBefore('@')?.takeIf { it.isNotBlank() }
    return if (local != null) "@$local" else profile.title?.trim()?.takeIf { it.isNotEmpty() } ?: "İSG Uzmanı"
}

@Composable
private fun PilotGroup(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(NovaColorToken.surface.color(), RoundedCornerShape(20.dp)),
        content = content)
}

@Composable
private fun PilotSeparator() {
    Box(Modifier.fillMaxWidth().padding(start = 62.dp, end = 16.dp).height(1.dp).background(NovaColorToken.hairline.color()))
}

@Composable
private fun PilotAction(title: String, icon: String, tint: Color, tag: String, onClick: () -> Unit, enabled: Boolean = true) {
    PilotProfileRow(icon, title, tint, Modifier.testTag(tag), enabled = enabled, onClick = onClick)
}

/** iOS `PilotProfileRow`: a 34pt tinted tile, the title and a trailing chevron in a 56pt row. */
@Composable
private fun PilotProfileRow(icon: String, title: String, tint: Color, modifier: Modifier = Modifier, trailingSymbol: String = "chevron.right",
                            titleColor: Color? = null, enabled: Boolean = true, onClick: () -> Unit) {
    Row(modifier.fillMaxWidth().heightIn(min = 56.dp).novaRowPress(enabled = enabled, onClick = onClick).padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        val tile = RoundedCornerShape(9.dp)
        Box(Modifier.size(34.dp).background(
            if (titleColor == null) Brush.verticalGradient(listOf(tint.copy(alpha = 0.72f), tint))
            else Brush.verticalGradient(listOf(tint.copy(alpha = 0.12f), tint.copy(alpha = 0.12f))), tile),
            contentAlignment = Alignment.Center) {
            NovaIcon(icon, 16.dp, tint = if (titleColor == null) Color.White else tint)
        }
        NovaText(title, Modifier.weight(1f), NovaTypeToken.body, titleColor ?: NovaColorToken.text.color())
        NovaIcon(trailingSymbol, 13.dp, tint = NovaColorToken.textSecondary.color())
    }
}
