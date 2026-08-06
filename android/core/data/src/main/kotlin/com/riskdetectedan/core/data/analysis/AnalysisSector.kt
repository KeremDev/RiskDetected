package com.riskdetectedan.core.data.analysis

/**
 * Kotlin mirror of App/Models/AnalysisSector.swift's `AnalysisSectorID` — same 15 raw values,
 * same set (review doc §16.1: sector/canvas IDs are "birebir doğru"). Titles are the Turkish fallback
 * strings iOS uses (RDLocalization fallback values) — hardcoded until Android's localization
 * pipeline exists, same interim state as every other hardcoded string in this app so far.
 */
enum class AnalysisSector(val id: String, val titleTr: String) {
    General("general", "Genel İSG"),
    Construction("construction", "İnşaat"),
    Manufacturing("manufacturing", "İmalat / Fabrika"),
    Mining("mining", "Maden"),
    Energy("energy", "Enerji"),
    Office("office", "Ofis"),
    LogisticsWarehouse("logistics_warehouse", "Depo / Lojistik"),
    ChemicalLaboratory("chemical_laboratory", "Kimya / Laboratuvar"),
    Healthcare("healthcare", "Sağlık / Hastane"),
    FoodProduction("food_production", "Gıda Üretimi"),
    AgricultureLivestock("agriculture_livestock", "Tarım / Hayvancılık"),
    Retail("retail", "Perakende / Mağaza"),
    MunicipalFieldServices("municipal_field_services", "Belediye / Kamu Saha İşleri"),
    Education("education", "Eğitim Kurumu"),
    Hospitality("hospitality", "Otel / Konaklama"),
    ;

    companion object {
        fun fromId(id: String): AnalysisSector? = entries.firstOrNull { it.id == id }
    }
}
