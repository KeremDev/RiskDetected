package com.riskdetectedan.core.data.analysis

/**
 * Kotlin mirror of App/Models/AnalysisSector.swift's `AnalysisSectorID` — same 15 raw values,
 * same set (review doc §16.1: sector/canvas IDs are "birebir doğru"). Titles are the Turkish fallback
 * strings iOS uses (RDLocalization fallback values) — hardcoded until Android's localization
 * pipeline exists, same interim state as every other hardcoded string in this app so far.
 */
/** [subtitleTr] added for [com.riskdetectedan.app.home.SectorPickerSheet] — real Turkish
 * fallback text from `AnalysisSectorID.subtitle` (Turkish branch), not present in the original
 * onboarding-only port since AnalysisScreen's old in-screen picker never showed it. Declaration
 * order matches iOS's `sortOrder` exactly (`General` first, then ascending `sortOrder`) — used
 * directly by [entries] in [AnalysisSectorPreferences.pickerItems], no separate sort field needed. */
enum class AnalysisSector(val id: String, val titleTr: String, val subtitleTr: String) {
    General("general", "Genel İSG", "Sektör bağlamı net olmayan genel saha taraması"),
    Construction("construction", "İnşaat", "Şantiye, yapı, hafriyat"),
    Manufacturing("manufacturing", "İmalat / Fabrika", "Fabrika, atölye, üretim hattı"),
    Mining("mining", "Maden", "Yeraltı, açık ocak, taşocağı"),
    Energy("energy", "Enerji", "Santral, rafineri, enerji tesisleri"),
    Office("office", "Ofis", "Banka, AVM, idari bina"),
    LogisticsWarehouse("logistics_warehouse", "Depo / Lojistik", "Depo, lojistik, yükleme alanları"),
    ChemicalLaboratory("chemical_laboratory", "Kimya / Laboratuvar", "Kimyasal işlem, laboratuvar"),
    Healthcare("healthcare", "Sağlık / Hastane", "Hastane, klinik, sağlık tesisi"),
    FoodProduction("food_production", "Gıda Üretimi", "Gıda üretimi, mutfak, hijyen alanları"),
    AgricultureLivestock("agriculture_livestock", "Tarım / Hayvancılık", "Tarım, hayvancılık, açık alan"),
    Retail("retail", "Perakende / Mağaza", "Mağaza, perakende, müşteri alanı"),
    MunicipalFieldServices("municipal_field_services", "Belediye / Kamu Saha İşleri", "Belediye, kamu saha işleri"),
    Education("education", "Eğitim Kurumu", "Okul, üniversite, atölye"),
    Hospitality("hospitality", "Otel / Konaklama", "Otel, konaklama, misafir alanları"),
    ;

    companion object {
        fun fromId(id: String): AnalysisSector? = entries.firstOrNull { it.id == id }
    }
}
