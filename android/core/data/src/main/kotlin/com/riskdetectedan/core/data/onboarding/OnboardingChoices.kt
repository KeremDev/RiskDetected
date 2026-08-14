package com.riskdetectedan.core.data.onboarding

/**
 * Kotlin mirrors of the OB* enums in App/Views/Onboarding/V2/OnboardingV2State.swift — same
 * raw values (what gets sent to upsert_onboarding_v2_answers), same Turkish labels (the only
 * language Android's onboarding supports so far — see OnboardingAnswersDraft's doc comment).
 * English-language cases (OBProfessionalRole, OBSafetyProfileSelection) exist on iOS as
 * alternates to Certificate/HazardClass for non-Turkish users; not ported since Android is
 * Turkish-only right now — would be dead code.
 */
enum class OnboardingCertificate(val id: String, val label: String) {
    A("A", "A Sınıfı"),
    B("B", "B Sınıfı"),
    C("C", "C Sınıfı"),
    Doctor("doctor", "İşyeri Hekimi"),
    OtherHealth("otherHealth", "Sağlık personeli"),
}

enum class OnboardingHazardClass(val id: String, val label: String) {
    Critical("critical", "Çok Tehlikeli"),
    High("high", "Tehlikeli"),
    Low("low", "Az Tehlikeli"),
}

/** Same 15 raw values as OBSector.swift — deliberately a separate type from
 * core.data.analysis.AnalysisSector (14 sectors, no "other"): different domain, different
 * source enum on iOS too. */
enum class OnboardingSector(val id: String, val label: String) {
    Construction("construction", "İnşaat"),
    Manufacturing("manufacturing", "İmalat / Fabrika"),
    Energy("energy", "Enerji"),
    Mining("mining", "Maden"),
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
    Other("other", "Diğer"),
}

enum class OnboardingFrequency(val id: String, val title: String, val sub: String) {
    One("1", "Tek odak", "Bir işyerine derin denetim"),
    TwoToFive("2-5", "Standart yoğunluk", "Birden çok OSGB sözleşmesi"),
    SixToFifteen("6-15", "Yüksek tempo", "Sürekli saha rotasyonu"),
    FifteenPlus("15+", "Yoğun saha", "Yoğun OSGB / endüstri grubu"),
}

enum class OnboardingPlan(val id: String, val label: String) {
    Yearly("yearly", "Yıllık"),
    Monthly("monthly", "Aylık"),
}
