package com.riskdetectedan.feature.nova

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.company.CompanyProfile
import com.riskdetectedan.core.data.company.CompanyResponsibleContact
import com.riskdetectedan.core.data.company.CompanyWorkplaceProfile
import com.riskdetectedan.core.data.nova.NovaCompanyCreateIntent
import com.riskdetectedan.core.data.nova.NovaCompanyCreateService
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.launch

/** Company creation bound to one owner; the design preview supplies its own. */
class NovaCompanyCreateClient(
    val ownerId: String,
    val pending: () -> NovaCompanyCreateIntent?,
    val create: suspend (NovaCompanyCreateIntent) -> String,
    val saveProfile: suspend (String, CompanyProfile) -> Unit,
)

private val contactRoles = listOf("Firma Sahibi", "Firma Müdürü", "Bölüm Sorumlusu", "İş Güvenliği Uzmanı", "İnsan Kaynakları", "İdari İşler", "Diğer")
private val hazards = listOf("low" to "Az Tehlikeli", "medium" to "Tehlikeli", "high" to "Çok Tehlikeli")
private fun hazardName(id: String) = hazards.firstOrNull { it.first == id }?.second ?: "Tehlikeli"

/**
 * Firma ekle (iOS `NovaPilotCompanyCreateView`): a short, resumable five-step wizard. The secure create RPC
 * makes the base row; the richer profile is saved on it right after, under the same owner.
 */
@Composable
fun NovaCompanyCreateScreen(client: NovaCompanyCreateClient, onClose: () -> Unit, onCreated: (String) -> Unit) {
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    var step by remember { mutableIntStateOf(0) }
    var name by remember { mutableStateOf("") }
    var address by remember { mutableStateOf("") }
    var city by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }
    // Nothing is chosen until the user picks a class.
    var hazard by remember { mutableStateOf<String?>(null) }
    var sector by remember { mutableStateOf("") }
    var employees by remember { mutableStateOf("") }
    var nace by remember { mutableStateOf("") }
    var registry by remember { mutableStateOf("") }
    var workplaces by remember { mutableStateOf<List<CompanyWorkplaceProfile>>(emptyList()) }
    var departments by remember { mutableStateOf<List<String>>(emptyList()) }
    var addResponsible by remember { mutableStateOf(false) }
    var contacts by remember { mutableStateOf<List<CompanyResponsibleContact>>(emptyList()) }
    var pending by remember { mutableStateOf<NovaCompanyCreateIntent?>(null) }
    var loaded by remember { mutableStateOf(false) }
    var storageFailed by remember { mutableStateOf(false) }
    var submitting by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var created by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        try {
            client.pending()?.let { staged ->
                pending = staged
                name = staged.name; hazard = staged.hazard.takeIf { id -> NovaHazardChoice.options.any { it.value == id } }; sector = staged.sector.orEmpty(); employees = staged.employeeCount?.toString().orEmpty()
                staged.responsibleName?.let { person ->
                    addResponsible = true
                    contacts = listOf(CompanyResponsibleContact(name = person, phone = staged.responsiblePhone.orEmpty(),
                        email = staged.responsibleEmail.orEmpty(), role = "Diğer"))
                }
            }
            loaded = true
        } catch (_: Exception) {
            storageFailed = true
            error = "Bekleyen kayıt güvenle okunamadı. Kaydı çoğaltmamak için işlem durduruldu."
        }
    }
    val done = created
    if (done != null) {
        NovaTaskSuccessView("Firma oluşturuldu", "Firma bilgileri kaydedildi ve ilgili modüllerde kullanılmaya hazır.", "Firmaya git", { onCreated(done) })
        return
    }
    val titles = listOf("Firma bilgileri", "İşletme bilgileri", "İşyeri ve departman", "Sorumlu & iletişim", "Firma özeti")
    val canAdvance = when (step) {
        0 -> name.isNotBlank()
        1 -> hazard != null && sector.isNotBlank() && employees.trim().toIntOrNull() != null
        2 -> workplaces.all { it.name.isNotBlank() } && departments.all { it.isNotBlank() }
        3 -> !addResponsible || contacts.isEmpty() || contacts.all { it.name.isNotBlank() && it.phone.isNotBlank() && it.role.isNotBlank() }
        else -> true
    }
    fun submit() = coroutines.launch {
        submitting = true; error = null
        try {
            val contact = contacts.firstOrNull()
            val fresh = NovaCompanyCreateIntent.contactProfile(client.ownerId, name, hazard.orEmpty(), sector, "", employees,
                if (addResponsible) contact?.name.orEmpty() else "", if (addResponsible) contact?.phone.orEmpty() else "",
                if (addResponsible) contact?.email.orEmpty() else "")
            // A staged request is reconciled first: it reuses its own server row, and the edited profile follows.
            val company = client.create(pending ?: fresh)
            pending = null
            runCatching { client.saveProfile(company, CompanyProfile(address, city, phone, nace, registry, workplaces, departments,
                if (addResponsible) contacts else emptyList())) }
            celebrate("Firma başarıyla eklendi!")
            created = company
        } catch (failure: Exception) { error = NovaCompanyCreateService.message(failure) }
        submitting = false
    }
    val goBack: () -> Unit = { if (!submitting) { error = null; if (step > 0) step-- else onClose() } }
    val editable = loaded && !submitting && !storageFailed
    NovaModuleTask("Firma ekle", step + 1, titles.size, titles[step], if (step == titles.lastIndex) "Firma Ekle" else "Devam",
        if (step == titles.lastIndex) "checkmark" else "arrow.right", submitting, goBack, {
            error = null
            when {
                !loaded || storageFailed -> error = "Kayıt durumu doğrulanamadı. Lütfen tekrar deneyin."
                !canAdvance -> error = if (step == 1) "Tehlike sınıfı, sektör ve çalışan sayısı zorunludur." else "Bu adımdaki zorunlu alanları tamamlayın."
                step < titles.lastIndex -> step++
                else -> submit()
            }
        }, error) {
        when (step) {
            0 -> {
                NovaHelpHint("Firma bilgileri bir kez seçilir; sonraki modül kayıtlarına otomatik taşınır.")
                NovaCard(Modifier.fillMaxWidth(), padding = 16) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        NovaCompanyIconField("Firma adı *", "building.2", name, "name", editable) { name = it }
                        NovaDivider(); NovaCompanyIconField("Adres", "mappin.and.ellipse", address, "address", editable, multiline = true) { address = it }
                        NovaDivider(); NovaCompanyIconField("Şehir", "map", city, "city", editable) { city = it }
                        NovaDivider(); NovaCompanyIconField("Firma telefonu", "phone", phone, "phone", editable, KeyboardType.Phone) { phone = it }
                    }
                }
            }
            1 -> NovaCard(Modifier.fillMaxWidth(), padding = 16) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    NovaCompanyHazardField("Tehlike sınıfı *", hazard, editable, "nova.pilot.company.hazard") {
                        // The step's error was about the missing class; a pick answers it.
                        hazard = it; error = null
                    }
                    NovaDivider(); NovaCompanyIconField("Sektör *", "square.grid.2x2", sector, "sector", editable) { sector = it }
                    NovaDivider(); NovaCompanyIconField("Çalışan sayısı *", "person.2", employees, "employeeCount", editable, KeyboardType.Number) { employees = it }
                    NovaDivider(); NovaCompanyIconField("NACE kodu", "number", nace, "nace", editable) { nace = it }
                    NovaDivider(); NovaCompanyIconField("İşyeri sicil no", "doc.text", registry, "registry", editable) { registry = it }
                }
            }
            2 -> {
                NovaCard(Modifier.fillMaxWidth(), padding = 16) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        NovaCompanyToggleRow("Aynı firmaya ait farklı işyeri var mı?", workplaces.isNotEmpty(), editable) { on ->
                            workplaces = if (on) workplaces.ifEmpty { listOf(CompanyWorkplaceProfile(hazardClass = hazard ?: "medium")) } else emptyList()
                        }
                        workplaces.forEachIndexed { index, workplace ->
                            fun update(value: CompanyWorkplaceProfile) { workplaces = workplaces.toMutableList().also { it[index] = value } }
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    NovaText("İşyeri ${index + 1}", Modifier.weight(1f), NovaTypeToken.label)
                                    if (index > 0) RemoveButton("İşyeri ${index + 1} kaldır") { workplaces = workplaces.filterIndexed { i, _ -> i != index } }
                                }
                                NovaCompanyIconField("İşyeri adı *", "building.2", workplace.name, "workplace-$index-name", editable) { update(workplace.copy(name = it)) }
                                NovaCompanyHazardField("İşyeri tehlike sınıfı *", workplace.hazardClass, editable, "nova.pilot.company.workplace-$index.hazard") {
                                    update(workplace.copy(hazardClass = it))
                                }
                                NovaCompanyIconField("İşyeri adresi", "mappin.and.ellipse", workplace.address, "workplace-$index-address", editable, multiline = true) {
                                    update(workplace.copy(address = it))
                                }
                                NovaCompanyIconField("İşyeri şehri", "map", workplace.city, "workplace-$index-city", editable) { update(workplace.copy(city = it)) }
                            }
                            if (index < workplaces.lastIndex) NovaDivider()
                        }
                        // A new workplace starts from the company's class.
                        if (workplaces.isNotEmpty()) AddRow("plus", "Başka işyeri ekle", editable) { workplaces = workplaces + CompanyWorkplaceProfile(hazardClass = hazard ?: "medium") }
                    }
                }
                NovaCard(Modifier.fillMaxWidth(), padding = 16) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        NovaCompanyToggleRow("Firmaya departman eklemek ister misiniz?", departments.isNotEmpty(), editable) { on ->
                            departments = if (on) departments.ifEmpty { listOf("") } else emptyList()
                        }
                        NovaText("Örn. boyahane, imalat", style = NovaTypeToken.metaQuiet)
                        departments.forEachIndexed { index, department ->
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                Box(Modifier.weight(1f)) {
                                    NovaCompanyIconField("Departman adı *", "square.grid.2x2", department, "department-$index", editable) { value ->
                                        departments = departments.toMutableList().also { it[index] = value }
                                    }
                                }
                                if (index > 0) RemoveButton("Departman ${index + 1} kaldır") { departments = departments.filterIndexed { i, _ -> i != index } }
                            }
                        }
                        if (departments.isNotEmpty()) AddRow("plus", "Başka departman ekle", editable) { departments = departments + "" }
                    }
                }
            }
            3 -> NovaCard(Modifier.fillMaxWidth(), padding = 16) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    NovaCompanyToggleRow("Sorumlu & iletişim personeli eklemek ister misiniz?", addResponsible, editable) { on ->
                        addResponsible = on
                        if (on && contacts.isEmpty()) contacts = listOf(CompanyResponsibleContact())
                    }
                    if (addResponsible) {
                        contacts.forEachIndexed { index, contact ->
                            fun update(value: CompanyResponsibleContact) { contacts = contacts.toMutableList().also { it[index] = value } }
                            Column(Modifier.padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    NovaText("Sorumlu ${index + 1}", Modifier.weight(1f), NovaTypeToken.label)
                                    if (index > 0) RemoveButton("Sorumlu ${index + 1} kaldır") { contacts = contacts.filterIndexed { i, _ -> i != index } }
                                }
                                NovaCompanyIconField("Ad soyad *", "person", contact.name, "contact-$index-name", editable) { update(contact.copy(name = it)) }
                                NovaCompanyIconField("Telefon *", "phone", contact.phone, "contact-$index-phone", editable, KeyboardType.Phone) { update(contact.copy(phone = it)) }
                                NovaCompanyIconField("Mail adresi", "envelope", contact.email, "contact-$index-email", editable, KeyboardType.Email) { update(contact.copy(email = it)) }
                                NovaChoiceField("Görevi *", "Görev seçin", "briefcase", contactRoles.map { NovaChoiceOption(it, it) },
                                    contact.role.ifEmpty { null }, { picked -> update(contact.copy(role = picked.orEmpty())) },
                                    "nova.pilot.company.contact-$index-role", enabled = editable)
                            }
                            if (index < contacts.lastIndex) NovaDivider()
                        }
                        AddRow("person.badge.plus", "Ek personel ekle", editable) { contacts = contacts + CompanyResponsibleContact() }
                    }
                }
            }
            else -> {
                NovaCard(Modifier.fillMaxWidth(), padding = 16) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            NovaText("Firma özeti", Modifier.weight(1f), NovaTypeToken.bodyStrong)
                            NovaText("Bilgileri düzenle", Modifier.novaRowPress { error = null; step = 0 }, NovaTypeToken.meta,
                                color = NovaColorToken.accentInk.color())
                        }
                        SummaryRow("Firma", name, "building.2")
                        SummaryRow("İletişim", listOf(address, city, phone).filter { it.isNotBlank() }.joinToString(" · "), "mappin.and.ellipse")
                        SummaryRow("İşletme", listOfNotNull(hazard?.let(::hazardName), sector, employees.ifBlank { null }?.let { "$it çalışan" }).joinToString(" · "), "shield")
                        if (nace.isNotBlank() || registry.isNotBlank())
                            SummaryRow("NACE / sicil", listOf(nace, registry).filter { it.isNotBlank() }.joinToString(" · "), "doc.text")
                        workplaces.forEachIndexed { index, workplace ->
                            SummaryRow("İşyeri ${index + 1}", listOf(workplace.name, hazardName(workplace.hazardClass), workplace.address, workplace.city)
                                .filter { it.isNotBlank() }.joinToString(" · "), "building.2")
                        }
                        departments.forEachIndexed { index, department -> SummaryRow("Departman ${index + 1}", department, "square.grid.2x2") }
                        if (addResponsible) contacts.forEachIndexed { index, contact ->
                            SummaryRow("Sorumlu ${index + 1}", listOf(contact.name, contact.role, contact.phone, contact.email).filter { it.isNotBlank() }
                                .joinToString(" · "), "person")
                        }
                    }
                }
                NovaHelpHint("Firma Ekle ile kayıt tamamlanır; bilgiler sonraki modüllerde hazır olur.")
            }
        }
        if (pending != null) NovaText("Bekleyen işlem bulundu. Aynı kayıt tekrar gönderilebilir; yeni bir firma oluşturulmaz.", style = NovaTypeToken.metaQuiet)
    }
}

@Composable
internal fun NovaCompanyIconField(title: String, symbol: String, value: String, id: String, enabled: Boolean, keyboard: KeyboardType = KeyboardType.Text,
                      multiline: Boolean = false, onChange: (String) -> Unit) {
    val ink = NovaColorToken.text.color()
    Row(Modifier.fillMaxWidth().heightIn(min = 40.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, 17.dp, Modifier.width(22.dp))
        Box(Modifier.weight(1f)) {
            if (value.isEmpty()) NovaText(title, color = NovaColorToken.textPlaceholder.color())
            BasicTextField(value, onChange, Modifier.fillMaxWidth().semantics { contentDescription = title }.testTag("nova.pilot.company.$id"),
                enabled = enabled, singleLine = !multiline, maxLines = if (multiline) 3 else 1,
                textStyle = novaTextStyle(NovaTypeToken.body).copy(color = ink), cursorBrush = SolidColor(ink),
                keyboardOptions = KeyboardOptions(keyboardType = keyboard,
                    capitalization = if (keyboard == KeyboardType.Email) KeyboardCapitalization.None else KeyboardCapitalization.Words))
        }
    }
}

/** The hazard class, picked from a sheet of described classes (iOS `NovaChoiceField` + `NovaHazardChoice`). */
@Composable
internal fun NovaCompanyHazardField(title: String, value: String?, enabled: Boolean, identifier: String, onChange: (String) -> Unit) {
    NovaChoiceField(title, NovaHazardChoice.placeholder, "exclamationmark.triangle", NovaHazardChoice.options,
        value?.takeIf { id -> NovaHazardChoice.options.any { it.value == id } }, { picked -> picked?.let(onChange) }, identifier,
        message = NovaHazardChoice.message, enabled = enabled)
}

@Composable
internal fun NovaCompanyToggleRow(title: String, on: Boolean, enabled: Boolean, onChange: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        NovaText(title, Modifier.weight(1f), NovaTypeToken.body)
        Switch(on, onChange, enabled = enabled, colors = SwitchDefaults.colors(checkedTrackColor = NovaColorToken.accent.color()))
    }
}

@Composable
private fun AddRow(symbol: String, title: String, enabled: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 42.dp).novaRowPress(enabled = enabled, onClick = onClick), horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, 15.dp)
        NovaText(title, Modifier.weight(1f), NovaTypeToken.bodyStrong)
        NovaIcon("chevron.right", 11.dp)
    }
}

@Composable
private fun RemoveButton(label: String, onClick: () -> Unit) {
    Box(Modifier.size(32.dp).clip(CircleShape).novaRowPress(onClick = onClick).semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        NovaIcon("trash", 14.dp, tint = NovaColorToken.statusDangerInk.color())
    }
}

@Composable
private fun SummaryRow(title: String, value: String, symbol: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, 17.dp)
        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            NovaText(title, style = NovaTypeToken.metaQuiet)
            NovaText(value.ifEmpty { "Belirtilmedi" })
        }
    }
}
