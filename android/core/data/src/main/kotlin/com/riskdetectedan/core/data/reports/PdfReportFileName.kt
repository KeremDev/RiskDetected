package com.riskdetectedan.core.data.reports

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Real port of `safeReportFileName` — Turkish-transliterating slugify + the same
 * `riskdetected_{title}_risk-analizi_{kind}_{method}_{shortId}_{timestamp}.pdf` component shape.
 * Not attempting the exact character-by-character Unicode-folding algorithm iOS uses
 * (`.folding(options: [.diacriticInsensitive, ...])`) — a simpler explicit Turkish-character map
 * plus a regex strip-to-ASCII gets the same practical result (a safe, readable Storage object
 * name), which is all this needs to be. */
object PdfReportFileName {
    fun build(title: String, analysisId: String, kind: String, method: String): String {
        val safeTitle = slugify(title).ifEmpty { "analysis" }.take(48)
        val shortId = analysisId.replace("-", "").take(8).lowercase()
        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date())
        return listOf("riskdetected", safeTitle, "risk-analizi", kind, method, shortId, timestamp)
            .joinToString("_") + ".pdf"
    }

    private fun slugify(input: String): String {
        val transliterated = input
            .replace("ı", "i").replace("İ", "I")
            .replace("ğ", "g").replace("Ğ", "G")
            .replace("ü", "u").replace("Ü", "U")
            .replace("ş", "s").replace("Ş", "S")
            .replace("ö", "o").replace("Ö", "O")
            .replace("ç", "c").replace("Ç", "C")
            .lowercase(Locale.US)
        val asciiOnly = transliterated.map { c -> if (c in 'a'..'z' || c in '0'..'9' || c == '-' || c == '_') c else '_' }
            .joinToString("")
        return asciiOnly.replace(Regex("_{2,}"), "_").trim('_', '-')
    }
}
