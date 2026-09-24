package com.riskdetectedan.feature.nova

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.zip.ZipInputStream
import java.io.ByteArrayInputStream

@RunWith(AndroidJUnit4::class)
class NovaDocumentWizardRuntimeTest {
    @Test fun bundledWebViewProducesSnapshotsAndRealExportsWithoutCompany() = runBlocking {
        withContext(Dispatchers.Main) {
            val context = InstrumentationRegistry.getInstrumentation().context
            val runtime = NovaDocumentWizardRuntime(context)
            try {
                runtime.ready()
                val first = runtime.generate(buildJsonObject {}, "risk")
                assertTrue(first.wArray("rows").isNotEmpty())
                assertEquals(JsonNull, first.wObject("answers").wObject("scope")["company_id"])
                assertEquals(13, runtime.questions.size)
                for (format in listOf("docx", "xlsx")) {
                    val file = runtime.download(format)
                    val parts = mutableMapOf<String, String>()
                    ZipInputStream(ByteArrayInputStream(file.bytes)).use { zip ->
                        var entry = zip.nextEntry
                        while (entry != null) { parts[entry.name] = zip.readBytes().toString(Charsets.UTF_8); entry = zip.nextEntry }
                    }
                    assertTrue(parts.containsKey("[Content_Types].xml"))
                    val frozen = Json.parseToJsonElement(parts.getValue("customXml/isgada-snapshot.json")).jsonObject
                    assertEquals(first, frozen)
                }
                val pdf = runtime.download("pdf")
                assertTrue(pdf.bytes.take(4).toByteArray().toString(Charsets.US_ASCII) == "%PDF")
                val path = java.io.File(context.cacheDir, "wizard-android-qa.pdf").apply { writeBytes(pdf.bytes) }
                android.graphics.pdf.PdfRenderer(android.os.ParcelFileDescriptor.open(path, android.os.ParcelFileDescriptor.MODE_READ_ONLY)).use { document -> assertTrue(document.pageCount > 1) }
                val scoped = runtime.generate(buildJsonObject {
                    putJsonObject("scope") { put("company_id", "test"); put("company_name", "İşletme <Ş> & 😀") }
                    put("energy", JsonArray(listOf(JsonPrimitive("hydraulic"))))
                    put("processes", JsonArray(listOf(JsonPrimitive("gas_evolving_battery_charge"))))
                }, "emergency")
                assertEquals(JsonNull, scoped.wObject("answers").wObject("scope")["workplace_id"])
                val ids = scoped.wArray("rows").map { it.jsonObject.wString("id") }
                assertTrue("R-16-08" in ids); assertTrue("R-21-09" in ids)
                assertTrue(scoped.wArray("cards").any { it.jsonObject.wString("id") == "AD-040" })
            } finally { runtime.close() }
        }
    }
}
