package com.riskdetectedan.core.designsystem.isg

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.*
import androidx.compose.material.icons.filled.CheckBox
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RadioButtonChecked
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.ThumbDown
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.NotificationAdd
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Space a scrolling page owes the floating tab bar (iOS `novaTabBarInset`). */
val novaTabBarInset: Dp = (NovaDimensionToken.layoutScrollBottomInset.value - NovaDimensionToken.spaceScreenX.value).dp

/** Room a pinned bottom bar leaves above the floating tab bar (its 8dp top and 10dp bottom padding included). */
val novaTabBarClearance: Dp = (NovaDimensionToken.layoutTabBarHeight.value + 18).dp

/** True while content renders inside the centred İSGADA popup (iOS `isNovaPopup`). */
val LocalNovaPopup = staticCompositionLocalOf { false }

object NovaPopupStyle {
    const val materialOpacity = 0.60f
    const val dimOpacity = 0.18f
    val sourceBlur = 4.dp

    @Composable fun background(): Color = NovaColorToken.surface.color()
    @Composable fun controlBackground(inPopup: Boolean = LocalNovaPopup.current): Color =
        (if (inPopup) NovaColorToken.surfaceMuted else NovaColorToken.surface).color()
}

/** Popup cards/fields contrast with the white container; regular pages keep their surface. */
@Composable
fun Modifier.novaControlBackground(cornerRadius: Dp): Modifier =
    background(NovaPopupStyle.controlBackground(), RoundedCornerShape(cornerRadius))

/** Pilot presentation scale over the generated reference tokens (iOS `NovaFont`). */
object NovaFont {
    fun spec(role: NovaTypeToken): NovaTypeSpec = when (role) {
        NovaTypeToken.screenTitle -> NovaTypeSpec("PlusJakartaSans-SemiBold", 600, 20.0, -0.3, 27.0)
        NovaTypeToken.sheetTitle -> NovaTypeSpec("PlusJakartaSans-SemiBold", 600, 18.0, -0.25, 25.0)
        else -> role.spec
    }
    private val secondary = setOf(NovaTypeToken.meta, NovaTypeToken.metaQuiet, NovaTypeToken.micro, NovaTypeToken.overline)
    @Composable fun defaultInk(role: NovaTypeToken): Color =
        (if (role in secondary) NovaColorToken.textSecondary else NovaColorToken.text).color()
}

fun novaTextStyle(role: NovaTypeToken): TextStyle = NovaFont.spec(role).let {
    TextStyle(fontFamily = NovaFontFamilyPublic, fontWeight = FontWeight(it.weight),
        fontSize = it.size.sp, letterSpacing = it.tracking.sp, lineHeight = it.lineHeight.sp,
        platformStyle = PlatformTextStyle(includeFontPadding = false))
}

/** Free-size text in the product family (iOS `NovaSizedText`). */
@Composable
fun NovaSizedText(text: String, size: Float = 15f, weight: FontWeight = FontWeight.SemiBold,
                  color: Color = Color.Unspecified, modifier: Modifier = Modifier, maxLines: Int = Int.MAX_VALUE,
                  textAlign: TextAlign? = null) {
    val role = when {
        size <= 10.5f -> NovaTypeToken.badge
        size <= 12f -> NovaTypeToken.meta
        size <= 13.5f -> NovaTypeToken.body
        size <= 16f -> NovaTypeToken.cardTitle
        else -> NovaTypeToken.screenTitle
    }
    Text(text, modifier, color = if (color == Color.Unspecified) NovaFont.defaultInk(role) else color,
        style = TextStyle(fontFamily = NovaFontFamilyPublic, fontWeight = weight, fontSize = size.sp,
            lineHeight = (size * 1.3f).sp, platformStyle = PlatformTextStyle(includeFontPadding = false)),
        maxLines = maxLines, textAlign = textAlign)
}

/**
 * SF Symbol names used by the iOS screens, mapped to their Material Outlined
 * counterparts so ported screens keep the exact same symbol strings.
 */
object NovaSymbols {
    private val map: Map<String, ImageVector> by lazy {
        mapOf(
            "archivebox" to Icons.Outlined.Inventory2,
            "arrow.clockwise" to Icons.Outlined.Refresh,
            "arrow.counterclockwise" to Icons.Outlined.Replay,
            "arrow.down" to Icons.Outlined.ArrowDownward,
            "arrow.down.circle" to Icons.Outlined.ArrowCircleDown,
            "arrow.down.doc" to Icons.Outlined.FileDownload,
            "arrow.left.arrow.right" to Icons.Outlined.SwapHoriz,
            "arrow.right" to Icons.AutoMirrored.Outlined.ArrowForward,
            "arrow.triangle.2.circlepath" to Icons.Outlined.Sync,
            "arrow.triangle.branch" to Icons.Outlined.AltRoute,
            "arrow.up" to Icons.Outlined.ArrowUpward,
            "arrow.up.arrow.down" to Icons.Outlined.SwapVert,
            "arrow.up.circle" to Icons.Outlined.ArrowCircleUp,
            "arrow.up.doc" to Icons.Outlined.FileUpload,
            "arrow.up.right.square" to Icons.AutoMirrored.Outlined.OpenInNew,
            "arrow.uturn.backward" to Icons.AutoMirrored.Outlined.Undo,
            "arrow.uturn.left" to Icons.AutoMirrored.Outlined.Undo,
            "bell" to Icons.Outlined.Notifications,
            "bookmark" to Icons.Outlined.BookmarkBorder,
            "book" to Icons.AutoMirrored.Outlined.MenuBook,
            "book.closed" to Icons.Outlined.Book,
            "books.vertical" to Icons.Outlined.LibraryBooks,
            "briefcase" to Icons.Outlined.Work,
            "building" to Icons.Outlined.Apartment,
            "building.2" to Icons.Outlined.Business,
            "building.2.crop.circle" to Icons.Outlined.AddBusiness,
            "calendar" to Icons.Outlined.CalendarMonth,
            "calendar.badge.checkmark" to Icons.Outlined.EventAvailable,
            "calendar.badge.clock" to Icons.Outlined.PendingActions,
            "calendar.badge.exclamationmark" to Icons.Outlined.EventBusy,
            "calendar.badge.minus" to Icons.Outlined.EventBusy,
            "calendar.badge.plus" to Icons.Outlined.EditCalendar,
            "camera" to Icons.Outlined.PhotoCamera,
            "cameraLarge" to Icons.Outlined.PhotoCamera,
            "chart.bar" to Icons.Outlined.BarChart,
            "checklist" to Icons.Outlined.Checklist,
            "checkmark" to Icons.Outlined.Check,
            "checkmark.circle" to Icons.Outlined.CheckCircle,
            "checkmark.circle.badge.questionmark" to Icons.Outlined.HelpOutline,
            "checkmark.circle.fill" to Icons.Filled.CheckCircle,
            "checkmark.seal" to Icons.Outlined.Verified,
            "checkmark.shield" to Icons.Outlined.VerifiedUser,
            "chevron.down" to Icons.Outlined.KeyboardArrowDown,
            "chevron.up" to Icons.Outlined.KeyboardArrowUp,
            "flame" to Icons.Outlined.LocalFireDepartment,
            "doc.on.doc" to Icons.Outlined.ContentCopy,
            "exclamationmark.arrow.triangle.2.circlepath" to Icons.Outlined.SyncProblem,
            "icloud.slash" to Icons.Outlined.CloudOff,
            "questionmark" to Icons.AutoMirrored.Outlined.HelpOutline,
            "signature" to Icons.Outlined.Draw,
            "checkmark.square.fill" to Icons.Filled.CheckBox,
            "circle" to Icons.Outlined.RadioButtonUnchecked,
            "largecircle.fill.circle" to Icons.Filled.RadioButtonChecked,
            "square" to Icons.Outlined.CheckBoxOutlineBlank,
            "chevron.left" to Icons.AutoMirrored.Outlined.KeyboardArrowLeft,
            "chevron.right" to Icons.AutoMirrored.Outlined.KeyboardArrowRight,
            "chevron.up.chevron.down" to Icons.Outlined.UnfoldMore,
            "clock" to Icons.Outlined.Schedule,
            "clock.arrow.circlepath" to Icons.Outlined.History,
            "clock.badge.exclamationmark" to Icons.Outlined.AlarmOn,
            "cross.case" to Icons.Outlined.MedicalServices,
            "cross.case.fill" to Icons.Outlined.MedicalServices,
            "doc" to Icons.Outlined.Description,
            "doc.badge.checkmark" to Icons.Outlined.AssignmentTurnedIn,
            "doc.badge.clock" to Icons.Outlined.PendingActions,
            "doc.badge.gearshape" to Icons.Outlined.SettingsApplications,
            "doc.badge.plus" to Icons.Outlined.NoteAdd,
            "doc.fill" to Icons.Outlined.Description,
            "doc.plaintext" to Icons.Outlined.Article,
            "doc.richtext" to Icons.Outlined.Article,
            "doc.text" to Icons.Outlined.Description,
            "doc.text.magnifyingglass" to Icons.Outlined.FindInPage,
            "doc.viewfinder" to Icons.Outlined.DocumentScanner,
            "ellipsis" to Icons.Outlined.MoreHoriz,
            "ellipsis.circle" to Icons.Outlined.MoreHoriz,
            "envelope" to Icons.Outlined.Mail,
            "envelope.badge" to Icons.Outlined.MarkEmailUnread,
            "envelope.open" to Icons.Outlined.Drafts,
            "exclamationmark.bubble" to Icons.Outlined.Feedback,
            "exclamationmark.circle" to Icons.Outlined.ErrorOutline,
            "exclamationmark.shield" to Icons.Outlined.GppMaybe,
            "exclamationmark.triangle" to Icons.Outlined.WarningAmber,
            "exclamationmark.triangle.fill" to Icons.Filled.Warning,
            "camera.fill" to Icons.Filled.PhotoCamera,
            "arrow.left.and.right" to Icons.Outlined.SwapHoriz,
            "externaldrive" to Icons.Outlined.Storage,
            "eye" to Icons.Outlined.Visibility,
            "eyeglasses" to Icons.Outlined.Visibility,
            "figure.run" to Icons.AutoMirrored.Outlined.DirectionsRun,
            "figure.walk" to Icons.AutoMirrored.Outlined.DirectionsWalk,
            "figure.walk.departure" to Icons.Outlined.ExitToApp,
            "folder" to Icons.Outlined.Folder,
            "folder.badge.plus" to Icons.Outlined.CreateNewFolder,
            "gearshape" to Icons.Outlined.Settings,
            "hammer.fill" to Icons.Outlined.Construction,
            "bolt.fill" to Icons.Outlined.Bolt,
            "building.2.fill" to Icons.Outlined.Apartment,
            "gearshape.2.fill" to Icons.Outlined.Settings,
            "mountain.2.fill" to Icons.Outlined.Landscape,
            "shippingbox.fill" to Icons.Outlined.Inventory2,
            "flask.fill" to Icons.Outlined.Science,
            "fork.knife" to Icons.Outlined.Restaurant,
            "leaf.fill" to Icons.Outlined.Eco,
            "bag.fill" to Icons.Outlined.ShoppingBag,
            "signpost.right.fill" to Icons.Outlined.Signpost,
            "bed.double.fill" to Icons.Outlined.Hotel,
            "hand.thumbsup.fill" to Icons.Filled.ThumbUp,
            "hand.thumbsdown.fill" to Icons.Filled.ThumbDown,
            "gift" to Icons.Outlined.CardGiftcard,
            "graduationcap" to Icons.Outlined.School,
            "graduationcap.fill" to Icons.Outlined.School,
            "hammer" to Icons.Outlined.Handyman,
            "hand.raised" to Icons.Outlined.PanTool,
            "hand.raised.fill" to Icons.Outlined.PanTool,
            "hand.thumbsdown" to Icons.Outlined.ThumbDown,
            "hand.thumbsup" to Icons.Outlined.ThumbUp,
            "hand.wave" to Icons.Outlined.WavingHand,
            "helmet" to Icons.Outlined.Engineering,
            "hourglass" to Icons.Outlined.HourglassEmpty,
            "house" to Icons.Outlined.Home,
            "infinity" to Icons.Outlined.AllInclusive,
            "info.circle" to Icons.Outlined.Info,
            "light.beacon.max" to Icons.Outlined.EmergencyShare,
            "lightbulb" to Icons.Outlined.Lightbulb,
            "line.3.horizontal" to Icons.Outlined.Menu,
            "line.3.horizontal.decrease" to Icons.AutoMirrored.Outlined.Sort,
            "link" to Icons.Outlined.Link,
            "lock" to Icons.Outlined.Lock,
            "lock.shield" to Icons.Outlined.Lock,
            "list.bullet" to Icons.AutoMirrored.Outlined.List,
            "list.bullet.circle" to Icons.AutoMirrored.Outlined.FormatListBulleted,
            "list.bullet.clipboard" to Icons.Outlined.ContentPaste,
            "list.bullet.rectangle" to Icons.AutoMirrored.Outlined.ListAlt,
            "list.number" to Icons.Outlined.FormatListNumbered,
            "magnifyingglass" to Icons.Outlined.Search,
            "map" to Icons.Outlined.Map,
            "mappin" to Icons.Outlined.Place,
            "mappin.and.ellipse" to Icons.Outlined.PinDrop,
            "minus.circle" to Icons.Outlined.RemoveCircleOutline,
            "nosign" to Icons.Outlined.Block,
            "note.text" to Icons.AutoMirrored.Outlined.StickyNote2,
            "note.text.badge.plus" to Icons.AutoMirrored.Outlined.NoteAdd,
            "number" to Icons.Outlined.Tag,
            "number.square" to Icons.Outlined.Pin,
            "paperclip" to Icons.Outlined.AttachFile,
            "paperplane" to Icons.AutoMirrored.Outlined.Send,
            "party.popper" to Icons.Outlined.Celebration,
            "pause.circle" to Icons.Outlined.PauseCircle,
            "pencil" to Icons.Outlined.Edit,
            "pencil.line" to Icons.Outlined.EditNote,
            "person" to Icons.Outlined.Person,
            "person.2" to Icons.Outlined.People,
            "person.2.badge.gearshape" to Icons.Outlined.ManageAccounts,
            "person.3" to Icons.Outlined.Groups,
            "person.3.sequence" to Icons.Outlined.Groups,
            "person.badge.checkmark" to Icons.Outlined.HowToReg,
            "person.badge.clock" to Icons.Outlined.PersonSearch,
            "person.badge.minus" to Icons.Outlined.PersonRemove,
            "person.badge.plus" to Icons.Outlined.PersonAdd,
            "person.badge.shield.checkmark" to Icons.Outlined.AdminPanelSettings,
            "person.crop.circle" to Icons.Outlined.AccountCircle,
            "person.crop.circle.badge.checkmark" to Icons.Outlined.HowToReg,
            "person.crop.circle.badge.exclamationmark" to Icons.Outlined.PersonOff,
            "person.crop.circle.badge.xmark" to Icons.Outlined.PersonOff,
            "person.crop.rectangle" to Icons.Outlined.Badge,
            "person.crop.rectangle.stack" to Icons.Outlined.RecentActors,
            "person.crop.square" to Icons.Outlined.AccountBox,
            "person.fill" to Icons.Outlined.Person,
            "person.fill.checkmark" to Icons.Outlined.HowToReg,
            "person.text.rectangle" to Icons.Outlined.Badge,
            "phone" to Icons.Outlined.Phone,
            "photo" to Icons.Outlined.Image,
            "photo.on.rectangle.angled" to Icons.Outlined.PhotoLibrary,
            "play" to Icons.Outlined.PlayArrow,
            "play.circle" to Icons.Outlined.PlayCircle,
            "plus" to Icons.Outlined.Add,
            "plus.circle" to Icons.Outlined.AddCircleOutline,
            "point.3.connected.trianglepath.dotted" to Icons.Outlined.Hub,
            "questionmark.circle" to Icons.AutoMirrored.Outlined.HelpOutline,
            "rectangle.portrait.and.arrow.right" to Icons.AutoMirrored.Outlined.Logout,
            "risk" to Icons.Outlined.Shield,
            "shield" to Icons.Outlined.Shield,
            "shield.checkered" to Icons.Outlined.Security,
            "shield.fill" to Icons.Outlined.Shield,
            "shield.lefthalf.filled" to Icons.Outlined.Shield,
            "shippingbox" to Icons.Outlined.Inventory,
            "shippingbox.badge.plus" to Icons.Outlined.AddBox,
            "slider.horizontal.3" to Icons.Outlined.Tune,
            "sparkle" to Icons.Outlined.AutoAwesome,
            "sparkles" to Icons.Outlined.AutoAwesome,
            "square.and.arrow.up" to Icons.Outlined.IosShare,
            "square.and.arrow.down" to Icons.Outlined.Download,
            "printer" to Icons.Outlined.Print,
            "bell.badge" to Icons.Outlined.NotificationAdd,
            "bell.badge.fill" to Icons.Filled.NotificationAdd,
            "bell.fill" to Icons.Filled.Notifications,
            "bell.slash" to Icons.Outlined.NotificationsOff,
            "icloud" to Icons.Outlined.Cloud,
            "checkmark.icloud" to Icons.Outlined.CloudDone,
            "exclamationmark.icloud" to Icons.Outlined.SyncProblem,
            "info.circle.fill" to Icons.Filled.Info,
            "square.and.pencil" to Icons.Outlined.EditNote,
            "square.dashed" to Icons.Outlined.CropFree,
            "square.grid.2x2" to Icons.Outlined.GridView,
            "square.stack.3d.up" to Icons.Outlined.Layers,
            "stop.circle" to Icons.Outlined.StopCircle,
            "tablecells" to Icons.Outlined.TableChart,
            "text.alignleft" to Icons.AutoMirrored.Outlined.FormatAlignLeft,
            "text.badge.plus" to Icons.Outlined.PlaylistAdd,
            "text.book.closed" to Icons.Outlined.Book,
            "text.bubble" to Icons.Outlined.Comment,
            "text.cursor" to Icons.Outlined.TextFields,
            "text.justify.left" to Icons.AutoMirrored.Outlined.Notes,
            "text.quote" to Icons.Outlined.FormatQuote,
            "trash" to Icons.Outlined.Delete,
            "tray" to Icons.Outlined.Inbox,
            "tray.and.arrow.down" to Icons.Outlined.MoveToInbox,
            "viewfinder" to Icons.Outlined.CenterFocusWeak,
            "waveform.path.ecg" to Icons.Outlined.MonitorHeart,
            "wifi.exclamationmark" to Icons.Outlined.WifiOff,
            "wrench.and.screwdriver" to Icons.Outlined.Build,
            "wrench.and.screwdriver.fill" to Icons.Outlined.Build,
            "xmark" to Icons.Outlined.Close,
            "xmark.circle" to Icons.Outlined.Cancel,
            "xmark.circle.fill" to Icons.Outlined.Cancel,
            "xmark.octagon" to Icons.Outlined.Report,
            "xmark.seal" to Icons.Outlined.GppBad,
        )
    }

    /** Unknown names fall back through their parent symbol, then to a neutral mark. */
    fun resolve(name: String): ImageVector {
        var key = name
        while (true) {
            map[key]?.let { return it }
            val cut = key.lastIndexOf('.')
            if (cut <= 0) return Icons.Outlined.RadioButtonUnchecked
            key = key.substring(0, cut)
        }
    }
}

/** Tint-only glyph, never an icon tile background (iOS `NovaIcon`). */
@Composable
fun NovaIcon(symbol: String, size: Dp = 20.dp, modifier: Modifier = Modifier, tint: Color = Color.Unspecified) {
    Icon(NovaSymbols.resolve(symbol), null, modifier.size(size),
        tint = if (tint == Color.Unspecified) NovaColorToken.text.color() else tint)
}

/** Consistent 44dp target with a compact, theme-aware chevron. */
@Composable
fun NovaBackButton(modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    Box(modifier.size(44.dp).clip(RoundedCornerShape(14.dp))
        .background(NovaColorToken.surface.color(), RoundedCornerShape(14.dp))
        .novaPress(enabled = enabled, onClickLabel = "Geri", onClick = onClick)
        .semantics { contentDescription = "Geri" }.testTag("nova.back"),
        contentAlignment = Alignment.Center) {
        NovaIcon("chevron.left", 22.dp)
    }
}

/** Brief purpose copy with an outline lightbulb. */
@Composable
fun NovaHelpHint(text: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        NovaIcon("lightbulb", 15.dp, tint = NovaColorToken.statusWarningInk.color())
        NovaText(text, style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color())
    }
}

@Composable
fun NovaPageHeading(title: String, subtitle: String = "", backEnabled: Boolean = true,
                    modifier: Modifier = Modifier, onBack: () -> Unit) {
    val inPopup = LocalNovaPopup.current
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        if (!inPopup) NovaBackButton(enabled = backEnabled, onClick = onBack)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            NovaText(title, style = NovaTypeToken.screenTitle)
            if (subtitle.isNotEmpty()) NovaText(subtitle, style = NovaTypeToken.metaQuiet)
        }
    }
}

/** Small ring for busy buttons. Stops under Reduce Motion. */
@Composable
fun NovaSpinner(color: Color, modifier: Modifier = Modifier, size: Dp = 16.dp) {
    val reduceMotion = rememberNovaReduceMotion()
    val angle = if (reduceMotion) 0f else rememberInfiniteTransition(label = "novaSpinner")
        .animateFloat(0f, 360f, infiniteRepeatable(tween(1000, easing = LinearEasing), RepeatMode.Restart),
            label = "novaSpinnerAngle").value
    Canvas(modifier.size(size).rotate(angle).clearAndSetSemantics {}) {
        val stroke = Stroke(2.dp.toPx(), cap = StrokeCap.Round)
        drawArc(color.copy(alpha = 0.2f), 0f, 360f, false, style = stroke)
        drawArc(color, 72f, 252f, false, style = stroke)
    }
}

/** Shared loading state for İSGADA pages. */
@Composable
fun NovaLoadingView(message: String = "Yükleniyor…", modifier: Modifier = Modifier) {
    val reduceMotion = rememberNovaReduceMotion()
    val ink = NovaColorToken.text.color()
    val angle = if (reduceMotion) 0f else rememberInfiniteTransition(label = "novaLoading")
        .animateFloat(0f, 360f, infiniteRepeatable(tween(1800, easing = LinearEasing), RepeatMode.Restart),
            label = "novaLoadingAngle").value
    Column(modifier.fillMaxSize().padding(28.dp).semantics(mergeDescendants = true) {}.testTag("nova.loading"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp, Alignment.CenterVertically)) {
        Box(Modifier.size(64.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize().rotate(angle)) {
                val stroke = Stroke(2.dp.toPx(), cap = StrokeCap.Round)
                drawArc(ink.copy(alpha = 0.08f), 0f, 360f, false, style = stroke,
                    topLeft = Offset(1.dp.toPx(), 1.dp.toPx()), size = Size(size.width - 2.dp.toPx(), size.height - 2.dp.toPx()))
                drawArc(ink.copy(alpha = 0.65f), -90f, 79f, false, style = stroke,
                    topLeft = Offset(1.dp.toPx(), 1.dp.toPx()), size = Size(size.width - 2.dp.toPx(), size.height - 2.dp.toPx()))
            }
            NovaIcon("viewfinder", 24.dp)
        }
        NovaText(message, style = NovaTypeToken.metaQuiet, textAlign = TextAlign.Center)
    }
}

/** Initials for avatar fallbacks, Turkish-cased. */
fun novaInitialsOf(name: String): String = name.trim().split(Regex("\\s+")).take(2)
    .mapNotNull { it.firstOrNull()?.toString() }.joinToString("")
    .uppercase(java.util.Locale.forLanguageTag("tr-TR"))

@Composable
fun novaFontScaleIsAccessibility(): Boolean = LocalDensity.current.fontScale >= 1.5f
