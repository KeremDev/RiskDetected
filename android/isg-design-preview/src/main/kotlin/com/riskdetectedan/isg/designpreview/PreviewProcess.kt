package com.riskdetectedan.isg.designpreview

import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.feature.nova.NovaFileClient
import com.riskdetectedan.feature.nova.NovaProcessClient
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Synthetic process records; nothing leaves the process. */
internal object PreviewProcessClient : NovaProcessClient {
    private val row = NovaProcessRow("v1", "c1", "Koza Altın A.Ş", "Kırma Eleme ziyareti", "2026-09-20", "e1",
        mapOf("workplace_id" to JsonPrimitive("w1"), "visited_on" to JsonPrimitive("2026-09-20"), "expert_note" to JsonPrimitive("Kırıcı bandında koruyucu eksik."),
            "duration_minutes" to JsonPrimitive("90"), "responsible_contact" to JsonPrimitive("Ahmet Yılmaz")), workplaceName = "Kırma Eleme")
    override val companies: suspend () -> List<NovaCompanyOption> = { listOf(NovaCompanyOption("c1", "Koza Altın A.Ş", "Maden · Çok tehlikeli", null)) }
    override val files: NovaFileClient get() = error("The design preview has no file library.")
    override suspend fun page(kind: String, company: String?, parent: String?, query: String, offset: Int) = NovaProcessPage(listOf(row), false,
        listOf(NovaProcessOption("w1", "Merkez Tesis"), NovaProcessOption("w2", "Kırma Eleme")), listOf(NovaProcessOption("e1", "Ayşe Demir")))
    override suspend fun record(kind: String, company: String, id: String) = row
    override suspend fun visitSummary(company: String?) = NovaVisitSummary(1, "owner", company, 12, 840, 9, "2026-09-20")
    private fun refuse(): Nothing = throw NovaProcessException("UNAVAILABLE")
    override suspend fun attachment(kind: String, record: String, field: String): NovaFileEntry = refuse()
    override suspend fun contents(entry: NovaFileEntry): ByteArray = refuse()
    override suspend fun references(kind: String, company: String, id: String?, query: String, offset: Int) = NovaProcessPage()
    override suspend fun mutate(company: String, action: String, payload: JsonObject): NovaProcessRow? = refuse()
}
