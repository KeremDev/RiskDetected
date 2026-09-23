package com.riskdetectedan.isg.designpreview

import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.feature.nova.NovaPersonOption
import com.riskdetectedan.feature.nova.NovaTrainingClient

/** Synthetic trainings; drafts stay in memory and nothing leaves the process. */
internal object PreviewTrainingClient : NovaTrainingClient {
    private val drafts = mutableMapOf<String, NovaEducationDraft>()
    private val packageTopics = listOf(
        NovaEducationPackage.Topic("G1.1", "G1", "Çalışma mevzuatı ile ilgili bilgiler"),
        NovaEducationPackage.Topic("G1.2", "G1", "Çalışanların yasal hak ve sorumlulukları"),
        NovaEducationPackage.Topic("G2.1", "G2", "Meslek hastalıklarının sebepleri"),
        NovaEducationPackage.Topic("G3.1", "G3", "Kimyasal, fiziksel ve ergonomik risk etmenleri"),
        NovaEducationPackage.Topic("G3.2", "G3", "Yangın, patlama ve acil durumlar"),
    )
    private fun preset(hazard: String, minutes: Int) = NovaEducationPackage.Preset("initial-$hazard", "İlk temel eğitim · $hazard", "initial", hazard,
        packageTopics.associate { it.code to minutes }, NovaEducationPackage.Preset.G4(listOf(NovaEducationPackage.Preset.G4Topic("G4.1", "Kırma eleme tesisi riskleri", 60))))
    private val context = NovaEducationContext(schemaVersion = 3, ownerId = "u1",
        `package` = NovaEducationPackage(packageTopics, listOf(preset("low", 60), preset("hazardous", 75), preset("very_hazardous", 90))),
        workplaces = listOf(NovaEducationContext.Workplace("w1", "c1", "Merkez Tesis", "high"), NovaEducationContext.Workplace("w2", "c2", "Depo", "low")),
        certificateEnabled = true)
    private val session = NovaTrainingSession("s1", "u1", "İlk Temel Eğitim", "Ayşe Demir", "face_to_face", "2026-09-10", "Toplantı salonu", "", 3,
        listOf(NovaTrainingSession.Company("sc1", "c1", "u1", "Koza Altın A.Ş", "high", 960, "2027-09-10", "completed",
            listOf(NovaTrainingParticipant("e1", "Mehmet Kaya", true), NovaTrainingParticipant("e2", "Elif Şahin", true)))))

    override val companies: suspend () -> List<NovaCompanyOption> = {
        listOf(NovaCompanyOption("c1", "Koza Altın A.Ş", "Maden · Çok tehlikeli", null), NovaCompanyOption("c2", "Ege Lojistik", "Depolama · Az tehlikeli", null))
    }
    override val userName = "Kerem Kayalar"
    override suspend fun page(after: String?) = NovaTrainingService.Page(listOf(session), null, setOf("c1", "c2"))
    override suspend fun employees(company: String) = listOf(NovaPersonOption("e1", "Mehmet Kaya"), NovaPersonOption("e2", "Elif Şahin"),
        NovaPersonOption("e3", "Can Yıldız"))
    override suspend fun context(id: String?) = context
    override fun draft(id: String?) = drafts[id ?: "new"]
    override fun preserve(draft: NovaEducationDraft) { drafts[draft.id ?: "new"] = draft }
    override fun discardDraft(id: String?) { drafts.remove(id ?: "new") }
    override fun pending(): NovaEducationDraft? = null
    override suspend fun save(draft: NovaEducationDraft): NovaTrainingService.Receipt = throw NovaTrainingException("FEATURE_UNAVAILABLE")
    override suspend fun certificate(request: NovaEducationCertificateRequest): NovaEducationCertificate = throw NovaTrainingException("FEATURE_UNAVAILABLE")
    override suspend fun logo(path: String?): String? = null
}
