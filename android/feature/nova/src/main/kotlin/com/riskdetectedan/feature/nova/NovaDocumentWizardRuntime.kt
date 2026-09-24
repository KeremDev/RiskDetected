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
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import kotlin.coroutines.resume

internal fun JsonObject.wString(key: String) = (get(key) as? JsonPrimitive)?.contentOrNull.orEmpty()
internal fun JsonObject.wArray(key: String) = get(key) as? JsonArray ?: JsonArray(emptyList())
internal fun JsonObject.wObject(key: String) = get(key) as? JsonObject ?: JsonObject(emptyMap())
internal data class NovaWizardChoice(val id: String, val label: String, val aliases: List<String> = emptyList())
internal data class NovaWizardQuestion(val id: String, val field: String, val title: String, val help: String)
internal data class NovaWizardDownload(val name: String, val bytes: ByteArray)
data class NovaWizardWorkplace(val id: String, val name: String)

/** Bundled JavaScript only. This WebView is a disposable computation context, never a visible web page.
 * There is no JavaScript interface, no external URL, no persistent storage, no file/content access.
 * All asynchronous calls are bounded, and dispose completes/cancels waiting calls via owner scope.
 */
@SuppressLint("SetJavaScriptEnabled")
internal class NovaDocumentWizardRuntime(context: Context) {
    private val json = Json
    private val loaded = CompletableDeferred<Unit>()
    private val view = WebView(context)
    private var closed = false
    private var initialized = false
    private val initialization = Mutex()
    private val scripts = listOf("engine", "export").map { name -> context.assets.open("isg_wizard/$name.js").bufferedReader().use { it.readText() } }
    private val bundle = json.parseToJsonElement(context.assets.open("isg_wizard/isgada-catalog.json").bufferedReader().use { it.readText() }).jsonObject
    val questions = bundle.wArray("questions").map { it.jsonObject.let { q -> NovaWizardQuestion(q.wString("id"), q.wString("field"), q.wString("text_tr"), q.wString("help_tr")) } }
    val options = bundle.wObject("options")
    val choices: Map<String, List<NovaWizardChoice>> = questions.filter { it.field !in listOf("scope", "method", "preset") }.associate { q ->
        val taxonomy = bundle.wObject("taxonomy")[q.field] as? JsonArray
        q.field to (taxonomy?.map { it.jsonObject.let { leaf -> NovaWizardChoice(leaf.wString("id"), leaf.wString("name_tr"), leaf.wArray("aliases_tr").map { a -> a.jsonPrimitive.content }) } }
            ?: options.wObject(q.field).map { (key, value) -> NovaWizardChoice(key, value.jsonPrimitive.content) })
    }
    init {
        view.settings.javaScriptEnabled = true
        view.settings.blockNetworkLoads = true
        view.settings.allowFileAccess = false
        view.settings.allowContentAccess = false
        view.settings.domStorageEnabled = false
        view.settings.databaseEnabled = false
        view.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?) = true
            override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?) = WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream(ByteArray(0)))
            override fun onPageFinished(view: WebView?, url: String?) { if (!closed) loaded.complete(Unit) }
        }
        // Keep the initial data URL small. Large catalogs exceed WebView's data-URL limit.
        view.loadData("<!doctype html><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'unsafe-inline'\">", "text/html", "UTF-8")
    }
    private suspend fun evaluate(expression: String): JsonElement = withTimeout(20_000) {
        check(!closed) { "Sihirbaz kapatıldı." }
        loaded.await()
        val reply = suspendCancellableCoroutine<String> { continuation ->
            view.evaluateJavascript("JSON.stringify((function(){try{return {value:($expression)}}catch(e){return {error:String(e.message||e)}}})())") { value ->
                if (continuation.isActive) continuation.resume(value)
            }
        }
        val encoded = (json.parseToJsonElement(reply) as? JsonPrimitive)?.contentOrNull ?: error("Sihirbaz içeriği yüklenemedi.")
        val result = json.parseToJsonElement(encoded).jsonObject
        if (result["error"] != null) error(result.wString("error"))
        result["value"] ?: error("Belge oluşturulamadı.")
    }
    suspend fun ready() = initialization.withLock {
        if (!initialized) {
            for (source in scripts) evaluate("(function(){\n$source\nreturn true;})()")
            evaluate("globalThis.catalogText = ''")
            for (chunk in bundle.toString().chunked(32_000)) evaluate("(globalThis.catalogText += ${JsonPrimitive(chunk)}, true)")
            evaluate("(globalThis.wizard = ISGWizard.create(JSON.parse(globalThis.catalogText)), globalThis.catalogText = null, true)")
            initialized = true
        }
    }
    suspend fun generate(answers: JsonObject, domain: String): JsonObject {
        ready()
        return evaluate("globalThis.snapshot = wizard.generate($answers, ${JsonPrimitive(domain)})").jsonObject
    }
    suspend fun download(format: String): NovaWizardDownload {
        ready()
        if (format == "pdf") {
            val blocks = evaluate("wizard.blocks(snapshot)").jsonArray
            val hash = evaluate("snapshot.content_sha256").jsonPrimitive.content.take(10)
            return NovaWizardDownload("ISGADA_$hash.pdf", pdf(blocks))
        }
        val file = evaluate("ISGWizard.exportFile(wizard, snapshot, ${JsonPrimitive(format)})").jsonObject
        return NovaWizardDownload(file.wString("name"), Base64.decode(file.wString("base64"), Base64.DEFAULT))
    }
    fun close() {
        closed = true; loaded.cancel(); view.stopLoading(); view.destroy()
    }
    private fun pdf(blocks: JsonArray): ByteArray {
        val pdf = PdfDocument()
        var pageNumber = 0
        var page: PdfDocument.Page? = null
        var y = 42f
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.BLACK }
        fun nextPage() {
            page?.let { current ->
                val footer = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 8f; color = android.graphics.Color.DKGRAY }
                current.canvas.drawText("İSGADA · $pageNumber", 42f, 775f, footer); pdf.finishPage(current)
            }
            pageNumber++; page = pdf.startPage(PdfDocument.PageInfo.Builder(612, 792, pageNumber).create()); y = 42f
        }
        try {
            nextPage()
            for (item in blocks) {
                val block = item.jsonObject
                val text = (block["rows"] as? JsonArray)?.joinToString("\n") { row -> row.jsonArray.joinToString("  ·  ") { it.jsonPrimitive.content } } ?: block.wString("text")
                val heading = block.wString("type") in listOf("title", "heading", "subheading")
                paint.textSize = if (block.wString("type") == "title") 20f else if (heading) 13f else 10.5f
                paint.typeface = if (heading) Typeface.create("sans-serif", Typeface.BOLD) else Typeface.create("sans-serif", Typeface.NORMAL)
                val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, 528).setAlignment(Layout.Alignment.ALIGN_NORMAL).setLineSpacing(2f, 1f).setIncludePad(false).build()
                for (line in 0 until layout.lineCount) {
                    val height = (layout.getLineBottom(line) - layout.getLineTop(line)).toFloat()
                    if (y + height > 740) nextPage()
                    val canvas = checkNotNull(page).canvas
                    canvas.save(); canvas.clipRect(42f, y, 570f, y + height)
                    canvas.translate(42f, y - layout.getLineTop(line)); layout.draw(canvas); canvas.restore(); y += height
                }
                y += if (heading) 9f else 6f
            }
            page?.let { pdf.finishPage(it) }; page = null
            return ByteArrayOutputStream().use { pdf.writeTo(it); it.toByteArray() }
        } finally { page?.let { pdf.finishPage(it) }; pdf.close() }
    }
}
