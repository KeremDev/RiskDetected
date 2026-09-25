package com.riskdetectedan.feature.nova

import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit

private const val saveFailed = "İşlem tamamlanamadı. Bilgileri kontrol edip yeniden deneyin."
private const val connectionRetry = "Bağlantınızı kontrol edip yeniden deneyin."

private fun memberRole(value: String) = when (value) { "owner" -> "OSGB sahibi"; "admin" -> "OSGB yöneticisi"; else -> "İSG uzmanı" }
private fun memberStatus(value: String) = when (value) { "active" -> "Aktif"; "suspended" -> "Askıda"; else -> "Sona erdi" }
private fun memberLabel(member: IsgWorkspaceMember) = memberRole(member.role) + " · " + (member.userId ?: member.id).take(8)
private fun assignmentRoleTitle(value: String) = when (value) { "primary" -> "Birincil uzman"; "support" -> "Destek uzmanı"; else -> memberRole(value) }
private fun weekFromNow() = Instant.now().plus(7, ChronoUnit.DAYS).truncatedTo(ChronoUnit.SECONDS).toString()

/**
 * Firma ekle / Firmayı düzenle for OSGB managers (iOS `IsgWorkspaceCompanyEditor`). The company and its profile
 * are two replay-safe mutations; a new company can take its first expert assignments in the same flow.
 */
@Composable
fun NovaOsgbCompanyEditor(context: IsgWorkspaceContext, repository: IsgWorkspaceRepository, company: NovaWorkspaceCompany?,
                          onClose: () -> Unit, onSaved: (String) -> Unit, onArchived: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    var name by remember { mutableStateOf(company?.name.orEmpty()) }
    // A new company starts with no class chosen; an edited one keeps its own.
    var hazard by remember { mutableStateOf(company?.hazardClass?.takeIf { it in setOf("low", "medium", "high") }) }
    var sector by remember { mutableStateOf(company?.sector.orEmpty()) }
    var email by remember { mutableStateOf(company?.email.orEmpty()) }
    var employeeCount by remember { mutableStateOf(company?.declaredEmployeeCount?.toString().orEmpty()) }
    var address by remember { mutableStateOf(company?.address.orEmpty()) }
    var addResponsible by remember { mutableStateOf(company?.responsibleName != null) }
    var responsibleName by remember { mutableStateOf(company?.responsibleName.orEmpty()) }
    var responsiblePhone by remember { mutableStateOf(company?.responsiblePhone.orEmpty()) }
    var responsibleEmail by remember { mutableStateOf(company?.responsibleEmail.orEmpty()) }
    var experts by remember { mutableStateOf<List<IsgWorkspaceMember>>(emptyList()) }
    var selectedExperts by remember { mutableStateOf<Set<String>>(emptySet()) }
    var assignmentRole by remember { mutableStateOf("support") }
    var membersLoading by remember { mutableStateOf(false) }
    var reason by remember { mutableStateOf("") }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var step by remember { mutableIntStateOf(0) }
    var saved by remember { mutableStateOf<String?>(null) }
    val companyAttempt = remember { IsgWorkspaceMutationAttempt() }
    val profileAttempt = remember { IsgWorkspaceMutationAttempt() }
    val archiveAttempt = remember { IsgWorkspaceMutationAttempt() }
    // A company can be created while a following assignment loses its response: keep the created id,
    // the receipt ids and the start instant so a retry replays instead of duplicating access.
    var createdId by remember { mutableStateOf<String?>(null) }
    val assignmentAttempts = remember { mutableMapOf<String, IsgWorkspaceMutationAttempt>() }
    var assignmentStart by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(company == null) {
        if (company != null) return@LaunchedEffect
        membersLoading = true
        experts = try { repository.members(context, "active").filter { it.isPracticingExpert } }
            catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { emptyList() }
        membersLoading = false
    }
    saved?.let { id ->
        NovaTaskSuccessView(if (company == null) "Firma oluşturuldu" else "Firma güncellendi",
            "Firma bilgileri kaydedildi ve sonraki modül işlemlerinde otomatik kullanılacak.", "Firmalara dön", { onSaved(id) })
        return
    }
    val total = if (company == null) 4 else 3
    val stepTitle = when { step == 0 -> "Temel bilgiler"; step == 1 -> "İletişim ve kapasite"; company == null && step == 2 -> "Uzman ataması"
        else -> "Kontrol ve kaydet" }
    val canSave = name.isNotBlank() && hazard != null && sector.isNotBlank() && (employeeCount.isEmpty() || employeeCount.toIntOrNull() != null) &&
        (!addResponsible || listOf(responsibleName, responsiblePhone, responsibleEmail).all { it.isNotBlank() })
    fun save() {
        if (!canSave || saving) return
        val chosenHazard = hazard ?: return
        val draft = IsgWorkspaceCompanyDraft(name, chosenHazard, sector, email, employeeCount.toIntOrNull(), address,
            if (addResponsible) responsibleName else "", if (addResponsible) responsiblePhone else "", if (addResponsible) responsibleEmail else "")
        val companyMutation = companyAttempt.id(if (company == null) "company.create" else "company.update", name, chosenHazard, (company?.version ?: 0).toString())
        val profileMutation = profileAttempt.id("company.profile", sector, email, employeeCount, address, draft.responsibleName,
            draft.responsiblePhone, draft.responsibleEmail, (company?.profileVersion ?: 0).toString())
        saving = true; error = null
        coroutines.launch {
            try {
                val id = if (company != null) repository.saveCompany(context, companyMutation, profileMutation, company.id, company.version,
                    company.profileVersion ?: 0, draft)
                else createdId ?: repository.saveCompany(context, companyMutation, profileMutation, null, 0, 0, draft).also { createdId = it }
                if (company == null) {
                    val starts = assignmentStart ?: Instant.now().truncatedTo(ChronoUnit.SECONDS).toString().also { assignmentStart = it }
                    selectedExperts.forEach { membership ->
                        val attempt = assignmentAttempts.getOrPut("$id:$membership:$assignmentRole") { IsgWorkspaceMutationAttempt() }
                        repository.mutateAssignment(context, attempt.id("assignment.create", id, membership, assignmentRole, starts), id, "create",
                            membershipId = membership, role = assignmentRole, startsAt = starts, reason = "Firma ekleme sırasında hızlı atama")
                    }
                }
                celebrate(if (company == null) "Firma başarıyla eklendi!" else "Firma bilgileri güncellendi.")
                saved = id
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { error = saveFailed }
            saving = false
        }
    }
    val goBack: () -> Unit = { if (!saving) { error = null; if (step > 0) step-- else onClose() } }
    NovaModuleTask(if (company == null) "Firma ekle" else "Firmayı düzenle", step + 1, total, stepTitle,
        if (step == total - 1) (if (company == null) "Firmayı kaydet" else "Değişiklikleri kaydet") else "Devam",
        if (step == total - 1) "checkmark" else "arrow.right", saving, goBack, {
            error = null
            when {
                step == 0 && (name.isBlank() || hazard == null || sector.isBlank()) -> error = "Firma adı, tehlike sınıfı ve sektör zorunludur."
                step == 1 && !canSave -> error = "Çalışan sayısı ve sorumlu personel bilgilerini kontrol edin."
                step < total - 1 -> step++
                else -> save()
            }
        }, error) {
        val editable = !saving
        when {
            step == 0 -> {
                NovaHelpHint("Firma ve sektör bilgisi bir kez kaydedilir; işyeri ve modül akışlarında yeniden kullanılır.")
                NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        NovaCompanyIconField("Firma adı *", "building.2", name, "osgb.name", editable) { name = it }
                        NovaDivider(); NovaCompanyHazardField("Tehlike sınıfı", hazard, editable, "osgb.company.hazard") { hazard = it; error = null }
                        NovaDivider(); NovaCompanyIconField("Sektör *", "square.grid.2x2", sector, "osgb.sector", editable) { sector = it }
                    }
                }
            }
            step == 1 -> NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    NovaCompanyIconField("Firma e-posta", "envelope", email, "osgb.email", editable, KeyboardType.Email) { email = it }
                    NovaDivider(); NovaCompanyIconField("Çalışan sayısı", "person.2", employeeCount, "osgb.employees", editable, KeyboardType.Number) {
                        employeeCount = it.filter(Char::isDigit)
                    }
                    NovaDivider(); NovaCompanyIconField("Adres", "mappin.and.ellipse", address, "osgb.address", editable, multiline = true) { address = it }
                    NovaDivider(); NovaCompanyToggleRow("Sorumlu personel ekle", addResponsible, editable) { addResponsible = it }
                    if (addResponsible) {
                        NovaCompanyIconField("Ad soyad *", "person", responsibleName, "osgb.responsible.name", editable) { responsibleName = it }
                        NovaCompanyIconField("Telefon *", "phone", responsiblePhone, "osgb.responsible.phone", editable, KeyboardType.Phone) { responsiblePhone = it }
                        NovaCompanyIconField("E-posta *", "envelope", responsibleEmail, "osgb.responsible.email", editable, KeyboardType.Email) {
                            responsibleEmail = it
                        }
                        NovaWhyDisclosure {
                            NovaText("Sorumlu kişi firma iletişim bilgisinde gösterilir. Personel kaydı ayrı personel ekranından oluşturulur.",
                                style = NovaTypeToken.metaQuiet)
                        }
                    }
                }
            }
            company == null && step == 2 -> {
                NovaHelpHint("Uzman ataması isteğe bağlıdır; firmayı şimdi kaydedip atamayı daha sonra da yapabilirsiniz.")
                when {
                    membersLoading -> NovaLoadingView("Uzmanlar yükleniyor…")
                    experts.isEmpty() -> NovaEmptyState("Atanabilir uzman yok", "Ekip yönetiminden uzman davet ettikten sonra atama yapabilirsiniz.")
                    else -> NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            NovaSegmentedControl(listOf("Destek uzmanı", "Birincil uzman"), if (assignmentRole == "primary") 1 else 0) {
                                if (editable) assignmentRole = if (it == 1) "primary" else "support"
                            }
                            experts.forEach { member ->
                                Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).novaRowPress(enabled = editable) {
                                    selectedExperts = if (member.id in selectedExperts) selectedExperts - member.id else selectedExperts + member.id
                                }.testTag("osgb.editor.expert.${member.id}"), horizontalArrangement = Arrangement.spacedBy(10.dp),
                                    verticalAlignment = Alignment.CenterVertically) {
                                    NovaIcon("person.badge.shield.checkmark", 17.dp)
                                    NovaText("İSG uzmanı · ${(member.userId ?: member.id).take(8)}", Modifier.weight(1f))
                                    NovaIcon(if (member.id in selectedExperts) "checkmark.circle.fill" else "circle", 18.dp)
                                }
                            }
                        }
                    }
                }
            }
            else -> {
                NovaCard(Modifier.fillMaxWidth(), padding = 15) {
                    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                        NovaText("Firma özeti", style = NovaTypeToken.bodyStrong)
                        NovaText(name, style = NovaTypeToken.cardTitle)
                        NovaText(listOfNotNull(hazard?.let(::hazardTitle), sector).joinToString(" · "), style = NovaTypeToken.metaQuiet)
                        if (address.isNotEmpty()) NovaText(address, style = NovaTypeToken.metaQuiet)
                        if (company == null) NovaText("${selectedExperts.size} uzman seçildi", style = NovaTypeToken.metaQuiet)
                    }
                }
                if (company != null) NovaWhyDisclosure("Arşivleme") {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        NovaTextField("Arşivleme gerekçesi", reason, { reason = it }, identifier = "osgb.company.archive.reason")
                        NovaButton("Firmayı arşivle", {
                            saving = true; error = null
                            val mutation = archiveAttempt.id("company.archive", company.id, company.version.toString(), reason.trim())
                            coroutines.launch {
                                try {
                                    repository.archiveCompany(context, mutation, company.id, company.version, reason)
                                    celebrate("Firma arşivlendi.")
                                    onArchived()
                                } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { error = saveFailed }
                                saving = false
                            }
                        }, variant = NovaButtonVariant.Danger, symbol = "archivebox", enabled = !saving && reason.isNotBlank())
                    }
                }
            }
        }
    }
}

/**
 * Uzman ve yönetici ekibi (iOS `IsgWorkspaceMemberManagement`): invitations with their one-time code, member
 * roles and access, and each member's usage history.
 */
@Composable
fun NovaOsgbMemberManagement(context: IsgWorkspaceContext, repository: IsgWorkspaceRepository, onBack: () -> Unit,
                             activity: @Composable (member: String, onClose: () -> Unit) -> Unit) {
    BackHandler(onBack = onBack)
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    val android = LocalContext.current
    var members by remember { mutableStateOf<List<IsgWorkspaceMember>>(emptyList()) }
    var invitations by remember { mutableStateOf<List<IsgWorkspaceInvitation>>(emptyList()) }
    var email by remember { mutableStateOf("") }
    var inviteRole by remember { mutableStateOf("expert") }
    var latestToken by remember { mutableStateOf<IsgWorkspaceInvitationToken?>(null) }
    var loading by remember { mutableStateOf(true) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var pendingExpiration by remember { mutableStateOf<String?>(null) }
    var memberActions by remember { mutableStateOf<IsgWorkspaceMember?>(null) }
    var invitationActions by remember { mutableStateOf<IsgWorkspaceInvitation?>(null) }
    var activityMember by remember { mutableStateOf<String?>(null) }
    val attempt = remember { IsgWorkspaceMutationAttempt() }
    LaunchedEffect(Unit) {
        loading = true; error = null
        try {
            coroutineScope {
                val loadedMembers = async { repository.members(context) }
                val loadedInvitations = async { repository.invitations(context) }
                members = loadedMembers.await(); invitations = loadedInvitations.await()
            }
        } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { error = connectionRetry }
        loading = false
    }
    activityMember?.let { member ->
        activity(member) { activityMember = null }
        return
    }
    fun run(work: suspend () -> Unit) {
        working = true; error = null
        coroutines.launch {
            try { work() } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { error = saveFailed }
            working = false
        }
    }
    fun mutate(member: IsgWorkspaceMember, action: String, value: String? = null, reason: String? = null) {
        memberActions = null
        val mutation = attempt.id("member.$action", member.id, member.version.toString(), value.orEmpty(), reason.orEmpty())
        run {
            val updated = repository.mutateMember(context, mutation, member, action, value, reason)
            members = members.map { if (it.id == updated.id) updated else it }
            celebrate("Üye erişimi güncellendi.")
        }
    }
    val reasonText = "Mobil ekip yönetimi"
    val canInvite = email.trim().let { it.contains('@') && it.contains('.') }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset)
        .testTag("osgb.members"), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        NovaPageHeading("Uzman ve yönetici ekibi", onBack = onBack)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaListStat("Aktif üye", "person.2", members.count { it.status == "active" }.toString(), Modifier.weight(1f))
            NovaListStat("Bekleyen davet", "envelope", invitations.count { it.status == "pending" }.toString(), Modifier.weight(1f))
        }
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                NovaText("Ekibe davet et", style = NovaTypeToken.bodyStrong)
                NovaTextField("E-posta adresi", email, { email = it }, identifier = "osgb.invite.email", keyboardType = KeyboardType.Email)
                NovaSegmentedControl(listOf("İSG uzmanı", "OSGB yöneticisi"), if (inviteRole == "admin") 1 else 0) {
                    inviteRole = if (it == 1) "admin" else "expert"
                }
                NovaCompactActionButton(if (working) "Kaydediliyor…" else "Davet oluştur", "paperplane", Modifier.width(IntrinsicSize.Max),
                    prominent = true, enabled = canInvite && !working, identifier = "osgb.invite.send") {
                    val target = email.trim()
                    val expiresAt = pendingExpiration ?: weekFromNow().also { pendingExpiration = it }
                    val mutation = attempt.id("member.invite", target, inviteRole, expiresAt)
                    run {
                        latestToken = repository.invite(context, mutation, target, inviteRole, expiresAt)
                        email = ""; pendingExpiration = null
                        invitations = repository.invitations(context)
                        celebrate("Davet oluşturuldu.")
                    }
                }
            }
        }
        latestToken?.let { token ->
            NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    NovaStatusPill("Davet hazır", NovaStatus.Success)
                    NovaText("Bu kod yalnız bu ekranda gösterilir. Davet edilen kişiyle güvenli biçimde paylaşın.", style = NovaTypeToken.metaQuiet)
                    SelectionContainer { NovaText(token.token, style = NovaTypeToken.meta) }
                    NovaCompactActionButton("Davet kodunu paylaş", "square.and.arrow.up", Modifier.width(IntrinsicSize.Max)) {
                        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, token.token)
                        runCatching { android.startActivity(Intent.createChooser(send, "Davet kodunu paylaş")) }
                    }
                }
            }
        }
        error?.let { NovaHelpHint(it) }
        if (loading) NovaLoadingView("Ekip yükleniyor…")
        else {
            NovaText("Ekip üyeleri", style = NovaTypeToken.sectionTitle)
            members.forEach { member ->
                NovaCard(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(enabled = member.userId != null) {
                    activityMember = member.userId
                }.testTag("osgb.member.${member.id}"), padding = 12) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        NovaIcon(if (member.role == "expert") "person.badge.shield.checkmark" else "person.crop.circle.badge.checkmark", 19.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            NovaText(memberRole(member.role), style = NovaTypeToken.bodyStrong)
                            NovaText((member.userId ?: member.id).take(8) + " · " + memberStatus(member.status), style = NovaTypeToken.metaQuiet)
                            NovaText("Kullanım ve işlem geçmişi", style = NovaTypeToken.metaQuiet)
                        }
                        if (member.role != "owner" && member.status != "ended") Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp))
                            .novaRowPress(enabled = !working) { memberActions = member }.testTag("osgb.member.${member.id}.actions"),
                            contentAlignment = Alignment.Center) { NovaIcon("ellipsis.circle", 20.dp) }
                    }
                }
            }
            NovaText("Davetler", style = NovaTypeToken.sectionTitle)
            val pending = invitations.filter { it.status == "pending" }
            if (pending.isEmpty()) NovaEmptyState("Bekleyen davet yok", "Yeni bir uzman veya yönetici davet edebilirsiniz.")
            pending.forEach { invitation ->
                NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        NovaIcon("envelope", 18.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            NovaText(invitation.email, style = NovaTypeToken.bodyStrong)
                            NovaText(memberRole(invitation.role), style = NovaTypeToken.metaQuiet)
                        }
                        Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).novaRowPress(enabled = !working) { invitationActions = invitation },
                            contentAlignment = Alignment.Center) { NovaIcon("ellipsis.circle", 20.dp) }
                    }
                }
            }
        }
    }
    val member = memberActions
    NovaPopup(member != null, { memberActions = null }, identifier = "osgb.member.menu") {
        if (member != null) Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaPopupHeading(memberLabel(member), "person.crop.circle")
            if (member.status == "active") {
                NovaPopupOption("Rolü değiştir", "arrow.triangle.2.circlepath") {
                    mutate(member, "change_role", value = if (member.role == "expert") "admin" else "expert")
                }
                NovaPopupOption("Erişimi askıya al", "pause.circle") { mutate(member, "suspend", reason = reasonText) }
                if (member.role == "expert") NovaPopupOption(if (member.isPracticingExpert) "Uzman pratiğini kapat" else "Uzman pratiğini aç",
                    if (member.isPracticingExpert) "person.badge.minus" else "person.badge.plus") {
                    mutate(member, "set_practicing", value = if (member.isPracticingExpert) "false" else "true")
                }
                NovaPopupOption("Üyeliği sonlandır", "person.crop.circle.badge.xmark") { mutate(member, "end", reason = reasonText) }
            } else if (member.status == "suspended") NovaPopupOption("Erişimi yeniden aç", "play.circle") { mutate(member, "reactivate", reason = reasonText) }
        }
    }
    val invitation = invitationActions
    NovaPopup(invitation != null, { invitationActions = null }, identifier = "osgb.invitation.menu") {
        if (invitation != null) Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaPopupHeading(invitation.email, "envelope")
            NovaPopupOption("Yeni kod oluştur", "arrow.clockwise") {
                invitationActions = null
                val expiresAt = pendingExpiration ?: weekFromNow().also { pendingExpiration = it }
                val mutation = attempt.id("invitation.resend", invitation.id, invitation.version.toString(), expiresAt)
                run {
                    latestToken = repository.resendInvitation(context, mutation, invitation, expiresAt)
                    pendingExpiration = null
                    invitations = repository.invitations(context)
                    celebrate("Yeni davet kodu oluşturuldu.")
                }
            }
            NovaPopupOption("Daveti iptal et", "xmark.circle") {
                invitationActions = null
                val mutation = attempt.id("invitation.revoke", invitation.id, invitation.version.toString())
                run {
                    repository.revokeInvitation(context, mutation, invitation)
                    invitations = invitations.filterNot { it.id == invitation.id }
                    celebrate("Davet iptal edildi.")
                }
            }
        }
    }
}

/**
 * Firma uzmanları (iOS `IsgWorkspaceAssignmentManagement`). Membership and company access stay separate: an
 * invited expert receives no company data until a manager creates an effective assignment here.
 */
@Composable
fun NovaOsgbAssignmentManagement(context: IsgWorkspaceContext, repository: IsgWorkspaceRepository, company: NovaWorkspaceCompany,
                                 onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    var members by remember { mutableStateOf<List<IsgWorkspaceMember>>(emptyList()) }
    var assignments by remember { mutableStateOf<List<IsgWorkspaceAssignment>>(emptyList()) }
    var membershipId by remember { mutableStateOf<String?>(null) }
    var role by remember { mutableStateOf("support") }
    var startDay by remember { mutableStateOf(LocalDate.now().toString()) }
    var startTime by remember { mutableStateOf(LocalTime.now().withSecond(0).withNano(0)) }
    var hasEnd by remember { mutableStateOf(false) }
    var endDay by remember { mutableStateOf(LocalDate.now().plusYears(1).toString()) }
    var endTime by remember { mutableStateOf(LocalTime.now().withSecond(0).withNano(0)) }
    var reason by remember { mutableStateOf("") }
    var ending by remember { mutableStateOf<IsgWorkspaceAssignment?>(null) }
    var endReason by remember { mutableStateOf("") }
    var endAt by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var expanded by remember { mutableStateOf(true) }
    var picking by remember { mutableStateOf(false) }
    var reload by remember { mutableIntStateOf(0) }
    val attempt = remember { IsgWorkspaceMutationAttempt() }
    val endAttempt = remember { IsgWorkspaceMutationAttempt() }
    val experts = members.filter { it.status == "active" && it.isPracticingExpert }
    LaunchedEffect(reload) {
        loading = true; error = null
        try {
            coroutineScope {
                val memberRows = async { repository.members(context, "active") }
                val assignmentRows = async { repository.assignments(context, company.id) }
                members = memberRows.await(); assignments = assignmentRows.await()
            }
            if (membershipId == null) membershipId = members.firstOrNull { it.status == "active" && it.isPracticingExpert }?.id
        } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { error = connectionRetry }
        loading = false
    }
    fun instant(day: String, time: LocalTime) = runCatching {
        LocalDate.parse(day).atTime(time).atZone(ZoneId.systemDefault()).toInstant().truncatedTo(ChronoUnit.SECONDS).toString()
    }.getOrNull()
    val starts = instant(startDay, startTime)
    val ends = if (hasEnd) instant(endDay, endTime) else null
    val canSave = membershipId != null && reason.isNotBlank() && starts != null &&
        (!hasEnd || (ends != null && Instant.parse(ends) > Instant.parse(starts)))
    fun assignmentLabel(assignment: IsgWorkspaceAssignment) = members.firstOrNull { it.id == assignment.membershipId }?.let(::memberLabel)
        ?: "Uzman · ${assignment.membershipId.take(8)}"

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset)
        .testTag("osgb.assignments"), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        NovaPageHeading("Firma uzmanları", onBack = onBack)
        NovaHelpHint("${company.name} firmasında işlem yapabilecek uzmanları ve görev sürelerini yönetin.")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaListStat("Aktif", "person.badge.checkmark", assignments.count { it.period() == IsgWorkspaceAssignment.Period.current }.toString(), Modifier.weight(1f))
            NovaListStat("Planlı", "calendar.badge.clock", assignments.count { it.period() == IsgWorkspaceAssignment.Period.future }.toString(), Modifier.weight(1f))
            NovaListStat("Sona eren", "clock.arrow.circlepath", assignments.count { it.period() == IsgWorkspaceAssignment.Period.ended }.toString(), Modifier.weight(1f))
        }
        if (loading) NovaLoadingView("Atamalar yükleniyor…")
        else {
            NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(Modifier.fillMaxWidth().heightIn(min = 38.dp).novaRowPress { expanded = !expanded }, verticalAlignment = Alignment.CenterVertically) {
                        NovaText("Uzman ata", Modifier.weight(1f), NovaTypeToken.bodyStrong)
                        NovaIcon(if (expanded) "chevron.up" else "chevron.down", 12.dp)
                    }
                    if (expanded) {
                        if (experts.isEmpty()) NovaHelpHint("Önce aktif ve operasyon yapabilen bir uzmanı çalışma alanına davet edin.")
                        else {
                            Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(14.dp)).novaControlBackground(14.dp)
                                .novaRowPress { picking = true }.padding(horizontal = 10.dp).testTag("osgb.assignment.expert"),
                                horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.CenterVertically) {
                                NovaIcon("person.badge.shield.checkmark", 17.dp)
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    NovaText("Uzman", style = NovaTypeToken.metaQuiet)
                                    NovaText(experts.firstOrNull { it.id == membershipId }?.let(::memberLabel) ?: "Uzman seçin")
                                }
                                NovaIcon("chevron.up.chevron.down", 11.dp)
                            }
                            NovaSegmentedControl(listOf("Destek uzmanı", "Birincil uzman"), if (role == "primary") 1 else 0) {
                                role = if (it == 1) "primary" else "support"
                            }
                            NovaDayField("Başlangıç", startDay, { startDay = it }, "osgb.assignment.start")
                            NovaTimeField("Başlangıç saati", startTime, "osgb.assignment.start.time") { startTime = it }
                            NovaCompanyToggleRow("Bitiş tarihi", hasEnd, !working) { hasEnd = it }
                            if (hasEnd) {
                                NovaDayField("Bitiş", endDay, { endDay = it }, "osgb.assignment.end")
                                NovaTimeField("Bitiş saati", endTime, "osgb.assignment.end.time") { endTime = it }
                            }
                            NovaTextField("Atama nedeni", reason, { reason = it }, identifier = "osgb.assignment.reason", multiline = true)
                            NovaCompactActionButton(if (working) "Kaydediliyor…" else "Atamayı kaydet", "checkmark", Modifier.width(IntrinsicSize.Max),
                                prominent = true, enabled = canSave && !working, identifier = "osgb.assignment.save") {
                                val member = membershipId ?: return@NovaCompactActionButton
                                val mutation = attempt.id("assignment.create", company.id, member, role, starts!!, ends.orEmpty(), reason)
                                working = true; error = null
                                coroutines.launch {
                                    try {
                                        repository.mutateAssignment(context, mutation, company.id, "create", membershipId = member, role = role,
                                            startsAt = starts, endsAt = ends, reason = reason)
                                        celebrate("Uzman ataması kaydedildi.")
                                        reason = ""; hasEnd = false; reload++
                                    } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { error = saveFailed }
                                    working = false
                                }
                            }
                        }
                    }
                }
            }
            if (assignments.isEmpty()) NovaEmptyState("Henüz uzman ataması yok",
                "Uzman atadığınızda firma operasyonlarına erişim başlangıç ve bitiş tarihine göre açılır.")
            assignments.forEach { assignment ->
                val period = assignment.period()
                NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        NovaIcon(if (assignment.assignmentRole == "primary") "person.badge.shield.checkmark" else "person.2", 19.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            NovaText(assignmentLabel(assignment), style = NovaTypeToken.bodyStrong)
                            NovaText(assignmentRoleTitle(assignment.assignmentRole), style = NovaTypeToken.metaQuiet)
                            NovaText(assignment.startsAt.take(10) + " → " + (assignment.endsAt?.take(10) ?: "∞"), style = NovaTypeToken.metaQuiet)
                            if (period != IsgWorkspaceAssignment.Period.ended)
                                NovaStatusPill(if (period == IsgWorkspaceAssignment.Period.future) "Planlı" else "Aktif", NovaStatus.Neutral)
                        }
                        if (period != IsgWorkspaceAssignment.Period.ended) Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp))
                            .novaRowPress { ending = assignment; endReason = ""; endAt = null }.testTag("osgb.assignment.${assignment.id}.end"),
                            contentAlignment = Alignment.Center) { NovaIcon("stop.circle", 20.dp) }
                        else NovaStatusPill("Sona eren", NovaStatus.Neutral)
                    }
                }
            }
        }
        error?.let { NovaHelpHint(it) }
    }
    NovaPopup(picking, { picking = false }, identifier = "osgb.assignment.experts") {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaPopupHeading("Uzman seçin", "person.badge.shield.checkmark")
            experts.forEach { member ->
                NovaPopupOption(memberLabel(member), if (member.id == membershipId) "checkmark.circle.fill" else "circle") {
                    membershipId = member.id; picking = false
                }
            }
        }
    }
    val closing = ending
    NovaPopup(closing != null, { if (!working) ending = null }, identifier = "osgb.assignment.end") {
        if (closing != null) Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            NovaPopupHeading("Atamayı bitir", "stop.circle")
            NovaHelpHint("Firma erişimi işlem tamamlandığında kesilir; geçmiş kayıtların yazarı değişmez.")
            NovaTextField("Sonlandırma nedeni", endReason, { endReason = it }, identifier = "osgb.assignment.end.reason", multiline = true)
            NovaCompactActionButton(if (working) "Kaydediliyor…" else "Atamayı bitir", "checkmark", Modifier.width(IntrinsicSize.Max),
                prominent = true, enabled = !working && endReason.isNotBlank()) {
                val at = endAt ?: Instant.now().truncatedTo(ChronoUnit.SECONDS).toString().also { endAt = it }
                val mutation = endAttempt.id("assignment.end", closing.id, closing.version.toString(), at, endReason)
                working = true; error = null
                coroutines.launch {
                    try {
                        repository.mutateAssignment(context, mutation, closing.companyId, "end", assignmentId = closing.id,
                            expectedVersion = closing.version, endsAt = at, reason = endReason)
                        celebrate("Uzman ataması kaydedildi.")
                        ending = null; reload++
                    } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { error = saveFailed }
                    working = false
                }
            }
        }
    }
}
