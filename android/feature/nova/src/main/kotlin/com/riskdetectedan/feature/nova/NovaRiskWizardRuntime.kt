package com.riskdetectedan.feature.nova

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.util.Base64
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import kotlin.coroutines.resume

// View models decoded from RDBridge (App/WizardAssets/isg_wizard_v6/rd-bridge.js).
internal data class RiskWizardFirm(val name: String, val address: String, val employees: String, val date: String)
internal data class RiskWizardSector(val id: String, val title: String, val hazardClass: String?)
internal data class RiskWizardOption(val id: String, val title: String, val badges: List<String>, val selected: Boolean)
internal data class RiskWizardFollowup(val id: String, val question: String, val help: String, val multi: Boolean, val context: String, val options: List<RiskWizardOption>)
internal data class RiskWizardPick(val id: String, val title: String, val subtitle: String, val reasons: List<String>, val badges: List<String>, val selected: Boolean, val detail: String)
internal data class RiskWizardPicks(val suggested: List<RiskWizardPick>, val added: List<RiskWizardPick>, val generic: List<RiskWizardPick>, val allSelected: Boolean, val count: Int)
internal data class RiskWizardItem(val id: String, val title: String, val subtitle: String, val selected: Boolean)
internal data class RiskWizardColumn(val id: String, val title: String, val required: Boolean, val residual: Boolean, val selected: Boolean)
internal data class RiskWizardView(
    val steps: List<String>, val firm: RiskWizardFirm, val hazardClass: String?, val hazardClassLabel: String, val hazardClassManual: Boolean,
    val sectors: List<RiskWizardSector>, val followups: List<RiskWizardFollowup>, val picks: Map<String, RiskWizardPicks>,
    val conditions: List<RiskWizardItem>, val management: List<RiskWizardItem>, val method: String, val preset: String,
    val columns: List<RiskWizardColumn>, val rowCount: Int, val counts: Map<String, Map<String, Int>>,
    val mode: String = "risk", val emergency: EmergencyWizardView? = null,
)

/** Acil durum planı modu: bütün metinler ve hesaplar köprüden gelir (iOS `NovaRiskWizardView.Emergency`). */
internal data class EmergencyWizardView(
    val texts: Map<String, String>, val employees: Int?, val site: List<EmergencySite>, val cards: List<EmergencyCard>, val teams: EmergencyTeams,
    val members: List<EmergencyMember>, val fields: List<EmergencyField>, val contacts: List<EmergencyContact>, val gaps: List<String>, val validUntil: String,
) { fun text(key: String) = texts[key].orEmpty() }
internal data class EmergencySite(val id: String, val title: String, val help: String, val selected: Boolean)
internal data class EmergencyCard(val id: String, val title: String, val trigger: String, val mode: String, val core: Boolean, val suggested: Boolean,
                                  val selected: Boolean, val reasons: List<String>)
internal data class EmergencyRole(val id: String, val label: String, val duty: String, val required: Int?, val assigned: Int, val basis: String)
internal data class EmergencyTeams(val hazardClassLabel: String, val employees: Int?, val validYears: Int?, val small: Boolean, val roles: List<EmergencyRole>,
                                   val combinedRequired: Int?, val note: String)
internal data class EmergencyMember(val index: Int, val role: String, val name: String, val title: String, val area: String, val contact: String,
                                    val backup: Boolean, val ref: String?)
internal data class EmergencyField(val key: String, val label: String, val value: String, val general: Boolean, val card: String)
internal data class EmergencyContact(val index: Int, val label: String, val number: String)
internal data class EmergencyPlanCard(val id: String, val title: String, val trigger: String, val mode: String, val core: Boolean, val why: List<String>,
                                      val before: List<String>, val worker: List<String>, val team: List<String>, val prohibited: List<String>,
                                      val after: List<String>, val reentry: String, val siteFields: List<Pair<String, String>>)
internal data class EmergencyPlanMember(val roleId: String, val name: String, val contact: String, val backup: Boolean)
internal data class EmergencyPlan(val name: String, val date: String, val validUntil: String, val sector: String, val hazardClass: String,
                                  val cards: List<EmergencyPlanCard>, val teams: EmergencyTeams, val members: List<EmergencyPlanMember>, val gaps: List<String>)
internal data class RiskWizardSectorHit(val id: String, val title: String, val subtitle: String, val hazardClassLabel: String)
internal data class RiskWizardScore(val p: Double?, val f: Double?, val l: Double?, val s: Double, val score: Double, val label: String, val level: String)
internal data class RiskWizardControl(val hierarchy: String, val label: String, val text: String, val owner: String)
internal data class RiskWizardRow(
    val id: String, val number: Int, val section: String, val hazard: String, val risk: String, val consequence: String, val affected: String,
    val check: String, val reasons: List<String>, val owner: String, val legal: List<String>, val controls: List<RiskWizardControl>,
    val fk: RiskWizardScore, val rfk: RiskWizardScore, val m5: RiskWizardScore, val rm5: RiskWizardScore,
    val m5Manual: Boolean, val rm5Manual: Boolean, val edited: Boolean, val removed: Boolean, val isNew: Boolean, val severe: Boolean,
)
internal data class RiskWizardResult(val counts: Map<String, Map<String, Int>>, val total: Int, val removedCount: Int, val method: String, val rows: List<RiskWizardRow>)

private fun JsonObject.bool(key: String) = (get(key) as? JsonPrimitive)?.booleanOrNull ?: false
private fun JsonObject.int(key: String) = (get(key) as? JsonPrimitive)?.intOrNull ?: 0
private fun JsonObject.double(key: String) = (get(key) as? JsonPrimitive)?.doubleOrNull
private fun JsonObject.optString(key: String) = (get(key) as? JsonPrimitive)?.contentOrNull
private fun JsonObject.strings(key: String) = wArray(key).mapNotNull { (it as? JsonPrimitive)?.contentOrNull }
private fun JsonObject.objects(key: String) = wArray(key).mapNotNull { it as? JsonObject }
private fun JsonObject.counts(key: String) = wObject(key).mapValues { (_, v) -> (v as? JsonObject)?.mapValues { (_, n) -> (n as? JsonPrimitive)?.intOrNull ?: 0 } ?: emptyMap() }
private fun JsonObject.pick() = RiskWizardPick(wString("id"), wString("title"), wString("subtitle"), strings("reasons"), strings("badges"), bool("selected"), wString("detail"))
private fun JsonObject.score() = RiskWizardScore(double("p"), double("f"), double("l"), double("s") ?: 0.0, double("score") ?: 0.0, wString("label"), wString("level"))
private fun JsonObject.item() = RiskWizardItem(wString("id"), wString("title"), wString("subtitle"), bool("selected"))
private fun JsonObject.optInt(key: String) = (get(key) as? JsonPrimitive)?.intOrNull
private fun JsonObject.teams() = EmergencyTeams(wString("hazardClassLabel"), optInt("employees"), optInt("validYears"), bool("small"),
    objects("roles").map { EmergencyRole(it.wString("id"), it.wString("label"), it.wString("duty"), it.optInt("required"), it.int("assigned"), it.wString("basis")) },
    (get("combined") as? JsonObject)?.optInt("required"), wString("note"))

internal fun emergencyWizardView(o: JsonObject) = EmergencyWizardView(
    texts = o.wObject("texts").mapValues { (_, v) -> (v as? JsonPrimitive)?.contentOrNull.orEmpty() }, employees = o.optInt("employees"),
    site = o.objects("site").map { EmergencySite(it.wString("id"), it.wString("title"), it.wString("help"), it.bool("selected")) },
    cards = o.objects("cards").map { EmergencyCard(it.wString("id"), it.wString("title"), it.wString("trigger"), it.wString("mode"), it.bool("core"),
        it.bool("suggested"), it.bool("selected"), it.strings("reasons")) },
    teams = o.wObject("teams").teams(),
    members = o.objects("members").map { EmergencyMember(it.int("index"), it.wString("role"), it.wString("name"), it.wString("title"), it.wString("area"),
        it.wString("contact"), it.bool("backup"), it.optString("ref")) },
    fields = o.objects("fields").map { EmergencyField(it.wString("key"), it.wString("label"), it.wString("value"), it.bool("general"), it.wString("card")) },
    contacts = o.objects("contacts").map { EmergencyContact(it.int("index"), it.wString("label"), it.wString("number")) },
    gaps = o.strings("gaps"), validUntil = o.wString("validUntil"),
)
internal fun emergencyPlan(o: JsonObject) = o.wObject("firm").let { firm ->
    EmergencyPlan(firm.wString("name"), firm.wString("date"), firm.wString("validUntil"), firm.wString("sector"), firm.wString("hazardClass"),
        o.objects("cards").map { c -> EmergencyPlanCard(c.wString("id"), c.wString("title"), c.wString("trigger"), c.wString("mode"), c.bool("core"),
            c.strings("why"), c.strings("before"), c.strings("worker"), c.strings("team"), c.strings("prohibited"), c.strings("after"), c.wString("reentry"),
            c.objects("siteFields").map { it.wString("label") to it.wString("value") }) },
        o.wObject("teams").teams(),
        o.objects("members").map { EmergencyPlanMember(it.wString("roleId"), it.wString("name"), it.wString("contact"), it.bool("backup")) },
        o.strings("gaps"))
}

internal fun riskWizardView(o: JsonObject) = RiskWizardView(
    steps = o.strings("steps"),
    firm = o.wObject("firm").let { RiskWizardFirm(it.wString("name"), it.wString("address"), it.wString("employees"), it.wString("date")) },
    hazardClass = o.optString("hazardClass"), hazardClassLabel = o.wString("hazardClassLabel"), hazardClassManual = o.bool("hazardClassManual"),
    sectors = o.objects("sectors").map { RiskWizardSector(it.wString("id"), it.wString("title"), it.optString("hazardClass")) },
    followups = o.objects("followups").map { f ->
        RiskWizardFollowup(f.wString("id"), f.wString("question"), f.wString("help"), f.bool("multi"), f.wString("context"),
            f.objects("options").map { RiskWizardOption(it.wString("id"), it.wString("title"), it.strings("badges"), it.bool("selected")) })
    },
    picks = o.wObject("picks").mapValues { (_, v) ->
        val p = v as JsonObject
        RiskWizardPicks(p.objects("suggested").map { it.pick() }, p.objects("added").map { it.pick() }, p.objects("generic").map { it.pick() }, p.bool("allSelected"), p.int("count"))
    },
    conditions = o.objects("conditions").map { it.item() }, management = o.objects("management").map { it.item() },
    method = o.wString("method"), preset = o.wString("preset"),
    columns = o.objects("columns").map { RiskWizardColumn(it.wString("id"), it.wString("title"), it.bool("required"), it.bool("residual"), it.bool("selected")) },
    rowCount = o.int("rowCount"), counts = o.counts("counts"),
    mode = o.optString("mode") ?: "risk", emergency = (o["emergency"] as? JsonObject)?.let { emergencyWizardView(it) },
)
internal fun riskWizardResult(o: JsonObject) = RiskWizardResult(o.counts("counts"), o.int("total"), o.int("removedCount"), o.wString("method"),
    o.objects("rows").map { r ->
        RiskWizardRow(r.wString("id"), r.int("number"), r.wString("section"), r.wString("hazard"), r.wString("risk"), r.wString("consequence"),
            r.wString("affected"), r.wString("check"), r.strings("reasons"), r.wString("owner"), r.strings("legal"),
            r.objects("controls").map { RiskWizardControl(it.wString("hierarchy"), it.wString("label"), it.wString("text"), it.wString("owner")) },
            r.wObject("fk").score(), r.wObject("rfk").score(), r.wObject("m5").score(), r.wObject("rm5").score(),
            r.bool("m5Manual"), r.bool("rm5Manual"), r.bool("edited"), r.bool("removed"), r.bool("isNew"), r.bool("severe"))
    })

/** Bundled, offline V6 risk wizard. A disposable WebView only computes: no JavaScript interface, network,
 * storage, file or content access. The bridge keeps the answers; Compose sends actions and draws views. */
@SuppressLint("SetJavaScriptEnabled")
internal class NovaRiskWizardRuntime(context: Context) {
    private val json = Json
    private val loaded = CompletableDeferred<Unit>()
    private val view = WebView(context)
    private var closed = false
    private var initialized = false
    private val initialization = Mutex()
    private val calls = Mutex()
    private val scripts = listOf("rd-xlsx", "rd-report", "rd-engine", "rd-emergency", "rd-bridge").map { name ->
        context.assets.open("isg_wizard_v6/$name.js").bufferedReader().use { it.readText() }
    }
    private val data = context.assets.open("isg_wizard_v6/rd-data.json").bufferedReader().use { it.readText() }

    init {
        view.settings.javaScriptEnabled = true
        view.settings.blockNetworkLoads = true
        view.settings.allowFileAccess = false
        view.settings.allowContentAccess = false
        view.settings.domStorageEnabled = false
        view.settings.databaseEnabled = false
        view.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?) = true
            override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?) =
                WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream(ByteArray(0)))
            override fun onPageFinished(view: WebView?, url: String?) { if (!closed) loaded.complete(Unit) }
        }
        view.loadData("<!doctype html><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'unsafe-inline'\">", "text/html", "UTF-8")
    }

    private suspend fun evaluate(expression: String): JsonElement = withTimeout(30_000) {
        check(!closed) { "Sihirbaz kapatıldı." }
        loaded.await()
        val reply = suspendCancellableCoroutine<String> { continuation ->
            view.evaluateJavascript("JSON.stringify((function(){try{return {value:($expression)}}catch(e){return {error:String(e.message||e)}}})())") { value ->
                if (continuation.isActive) continuation.resume(value)
            }
        }
        val encoded = (json.parseToJsonElement(reply) as? JsonPrimitive)?.contentOrNull ?: error("Sihirbaz içeriği yüklenemedi.")
        val result = json.parseToJsonElement(encoded).jsonObject
        (result["error"] as? JsonPrimitive)?.contentOrNull?.let { error(it) }
        result["value"] ?: error("Sihirbaz işlemi tamamlanamadı.")
    }

    suspend fun ready() = initialization.withLock {
        if (!initialized) {
            for (source in scripts) evaluate("(function(){\n$source\nreturn true;})()")
            evaluate("(globalThis.rdDataText = '', true)")
            // Large catalogues exceed a single evaluateJavascript payload comfortably; send the text in slices.
            for (chunk in data.chunked(32_000)) evaluate("(globalThis.rdDataText += ${JsonPrimitive(chunk)}, true)")
            evaluate("(RDBridge.init(globalThis.rdDataText), globalThis.rdDataText = null, true)")
            initialized = true
        }
    }

    private suspend fun call(expression: String): JsonElement = calls.withLock { ready(); evaluate(expression) }

    suspend fun start(firmName: String, date: String, mode: String = "risk"): RiskWizardView =
        riskWizardView(call("RDBridge.start(${JsonObject(mapOf("name" to JsonPrimitive(firmName), "date" to JsonPrimitive(date), "mode" to JsonPrimitive(mode)))})").jsonObject)
    suspend fun plan(): EmergencyPlan = emergencyPlan(call("RDBridge.result()").jsonObject)
    suspend fun cards(query: String): List<EmergencyCard> = call("RDBridge.cards(${JsonPrimitive(query)})").jsonArray.map {
        val c = it.jsonObject
        EmergencyCard(c.wString("id"), c.wString("title"), c.wString("trigger"), c.wString("mode"), false, false, false, emptyList())
    }
    suspend fun act(action: Map<String, Any?>): RiskWizardView = riskWizardView(call("RDBridge.act(${encode(action)})").jsonObject)
    suspend fun result(): RiskWizardResult = riskWizardResult(call("RDBridge.result()").jsonObject)
    suspend fun sectors(query: String): List<RiskWizardSectorHit> = call("RDBridge.sectors(${JsonPrimitive(query)})").jsonArray.map {
        val o = it.jsonObject; RiskWizardSectorHit(o.wString("id"), o.wString("title"), o.wString("subtitle"), o.wString("hazardClassLabel"))
    }
    suspend fun search(kind: String, query: String): List<RiskWizardPick> =
        call("RDBridge.search(${JsonPrimitive(kind)}, ${JsonPrimitive(query)})").jsonArray.map { it.jsonObject.pick() }

    /** Excel and Word come from rd-report.js (emergency: rd-emergency.js, "cards" = action cards); PDF is drawn natively from the same blocks. */
    suspend fun download(format: String): NovaWizardDownload {
        if (format == "pdf") {
            val blocks = call("RDBridge.blocks()").jsonArray.map { it.jsonObject.wString("type") to it.jsonObject.wString("text") }
            val name = (call("RDBridge.fileName('pdf')") as? JsonPrimitive)?.contentOrNull ?: "Risk_Degerlendirmesi.pdf"
            return NovaWizardDownload(name, pdf(blocks, blocks.firstOrNull()?.second?.substringBefore(" — ").orEmpty()))
        }
        val file = call("RDBridge.file(${JsonPrimitive(format)})").jsonObject
        return NovaWizardDownload(file.wString("name"), Base64.decode(file.wString("base64"), Base64.DEFAULT))
    }

    fun close() { closed = true; loaded.cancel(); view.stopLoading(); view.destroy() }

    private fun encode(value: Any?): JsonElement = when (value) {
        null -> kotlinx.serialization.json.JsonNull
        is String -> JsonPrimitive(value)
        is Number -> JsonPrimitive(value)
        is Boolean -> JsonPrimitive(value)
        is Map<*, *> -> JsonObject(value.entries.associate { (k, v) -> k.toString() to encode(v) })
        else -> JsonPrimitive(value.toString())
    }

    private fun pdf(blocks: List<Pair<String, String>>, title: String): ByteArray {
        val document = PdfDocument()
        var number = 0
        var page: PdfDocument.Page? = null
        var y = 42f
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.BLACK }
        fun nextPage() {
            page?.let { current ->
                val footer = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 8f; color = android.graphics.Color.DKGRAY }
                current.canvas.drawText("$title · $number", 42f, 775f, footer); document.finishPage(current)
            }
            number++; page = document.startPage(PdfDocument.PageInfo.Builder(612, 792, number).create()); y = 42f
        }
        try {
            nextPage()
            for ((type, text) in blocks) {
                val heading = type in listOf("title", "heading", "subheading")
                paint.textSize = if (type == "title") 18f else if (type == "heading") 13f else if (heading) 11.5f else 9.5f
                paint.typeface = Typeface.create("sans-serif", if (heading) Typeface.BOLD else Typeface.NORMAL)
                val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, 528).setAlignment(Layout.Alignment.ALIGN_NORMAL)
                    .setLineSpacing(2f, 1f).setIncludePad(false).build()
                for (line in 0 until layout.lineCount) {
                    val height = (layout.getLineBottom(line) - layout.getLineTop(line)).toFloat()
                    if (y + height > 740) nextPage()
                    val canvas = checkNotNull(page).canvas
                    canvas.save(); canvas.clipRect(42f, y, 570f, y + height)
                    canvas.translate(42f, y - layout.getLineTop(line)); layout.draw(canvas); canvas.restore(); y += height
                }
                y += if (heading) 7f else 5f
            }
            page?.let { document.finishPage(it) }; page = null
            return ByteArrayOutputStream().use { document.writeTo(it); it.toByteArray() }
        } finally { page?.let { document.finishPage(it) }; document.close() }
    }
}
