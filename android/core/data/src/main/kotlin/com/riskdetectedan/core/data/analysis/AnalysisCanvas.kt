package com.riskdetectedan.core.data.analysis

import com.riskdetectedan.core.data.profile.SubscriptionTier

/**
 * Mirrors App/Models/AnalysisCanvas.swift exactly — "canvas" = which AI prompt focus an analysis
 * runs with (a different axis from [AnalysisSector], which is *what kind of workplace* it is).
 * `icon` carries the same SF-Symbol-style string key as [AnalysisSector]/etc. (this module has no
 * Compose dependency — the feature module maps the string to a Material `ImageVector`, same
 * established pattern).
 */
data class AnalysisCanvas(
    val id: String,
    val title: String,
    val body: String,
    val icon: String,
    val minTier: SubscriptionTier,
) {
    val isPaid: Boolean get() = minTier != SubscriptionTier.Free
    val isPro: Boolean get() = minTier == SubscriptionTier.Pro

    companion object {
        val general = AnalysisCanvas(
            id = "general", title = "Genel", icon = "sparkles", minTier = SubscriptionTier.Free,
            body = "Standart saha taraması yap; ana risk alanlarını dengeli şekilde değerlendir.",
        )
        val ppe = AnalysisCanvas(
            id = "ppe", title = "KKD", icon = "shield.lefthalf.filled", minTier = SubscriptionTier.Free,
            body = "Baret, gözlük, eldiven, emniyet kemeri ve yelek kontrolüne odaklan.",
        )
        val machine = AnalysisCanvas(
            id = "machine", title = "Makine", icon = "gearshape.2.fill", minTier = SubscriptionTier.Plus,
            body = "Makine koruyucuları, döner parçalar, sıkışma ve bakım-kilit risklerine odaklan.",
        )
        val warningSigns = AnalysisCanvas(
            id = "warning_signs", title = "Uyarı levhaları", icon = "exclamationmark.triangle.fill", minTier = SubscriptionTier.Free,
            body = "Uyarı levhaları, yönlendirme, işaretleme ve görünürlük eksiklerini analiz et.",
        )
        val electrical = AnalysisCanvas(
            id = "electrical", title = "Elektrik", icon = "bolt.fill", minTier = SubscriptionTier.Free,
            body = "Elektrik panosu, kablo, kaçak akım, izolasyon ve elektrik çarpması risklerine odaklan.",
        )
        val sector = AnalysisCanvas(
            id = "sector", title = "Sektör", icon = "building.2.fill", minTier = SubscriptionTier.Plus,
            body = "İnşaat, üretim, depo veya ofis bağlamına göre sektöre özgü risklere odaklan.",
        )
        val fire = AnalysisCanvas(
            id = "fire", title = "Yangın", icon = "flame.fill", minTier = SubscriptionTier.Free,
            body = "Yanıcı maddeler, yangın söndürme erişimi, sıcak çalışma ve tahliye risklerine odaklan.",
        )
        val ergonomics = AnalysisCanvas(
            id = "ergonomics", title = "Özel Ekipman", icon = "wrench.and.screwdriver.fill", minTier = SubscriptionTier.Pro,
            body = "Fotoğraftaki ekipmanı tanımla ve İSG açısından değerlendir. Emin değilsen olasılıkları belirt, varsayım yapma. Kısa başlıklarla şunları ver: ekipman adı, tehlikeler, riskler, önlemler, gerekli KKD, kullanım öncesi kontroller ve durdurma kriterleri. Kritik risk varsa en başta uyar. Eksik bilgi varsa ek fotoğraf veya marka/model iste.",
        )
        val environmentMeasurement = AnalysisCanvas(
            id = "environment_measurement", title = "Ortam Ölçümü", icon = "gauge.with.dots.needle.67percent", minTier = SubscriptionTier.Plus,
            body = "Gürültü, aydınlatma, toz, gaz, sıcaklık ve ortam ölçümü gerektiren riskleri değerlendir.",
        )
        val explosion = AnalysisCanvas(
            id = "explosion", title = "Patlama", icon = "burst.fill", minTier = SubscriptionTier.Free,
            body = "Patlayıcı atmosfer, basınçlı kaplar, gaz birikimi ve kıvılcım kaynaklarına odaklan.",
        )
        val environment = AnalysisCanvas(
            id = "environment", title = "Çevre", icon = "leaf.fill", minTier = SubscriptionTier.Free,
            body = "Atık, sızıntı, dökülme, çevresel maruziyet ve saha düzeni etkilerini analiz et.",
        )
        val legislation = AnalysisCanvas(
            id = "legislation", title = "Mevzuat", icon = "scroll.fill", minTier = SubscriptionTier.Pro,
            body = "İSG mevzuatı, yasal yükümlülük ve denetim uyumu açısından eksikleri değerlendir.",
        )
        val workingAtHeight = AnalysisCanvas(
            id = "working_at_height", title = "Yüksekte Çalışma", icon = "figure.climbing", minTier = SubscriptionTier.Free,
            body = "Düşme, korkuluk, iskele, emniyet kemeri, yaşam hattı ve yüksekte çalışma risklerine odaklan.",
        )
        val mobileEquipment = AnalysisCanvas(
            id = "mobile_equipment", title = "Hareketli Ekipman", icon = "truck.box.fill", minTier = SubscriptionTier.Free,
            body = "Forklift, transpalet, vinç, araç-yaya ayrımı ve hareketli ekipman risklerini analiz et.",
        )
        val generalPremium = AnalysisCanvas(
            id = "general_premium", title = "Genel Premium", icon = "star.square.fill", minTier = SubscriptionTier.Pro,
            body = "Tüm görünür riskleri daha ayrıntılı, önceliklendirilmiş ve denetim odaklı analiz et.",
        )
        val constructionMachinery = AnalysisCanvas(
            id = "construction_machinery", title = "İş Makineleri", icon = "wrench.and.screwdriver.fill", minTier = SubscriptionTier.Free,
            body = "Ekskavatör, yükleyici, vinç ve saha iş makineleri kaynaklı risklere odaklan.",
        )

        /** Same order as AnalysisCanvas.swift's `.all` — the CanvasSheet grid relies on this
         * exact order (2-row layout fills column-major). */
        val all: List<AnalysisCanvas> = listOf(
            general, ppe, machine,
            warningSigns, generalPremium, sector,
            fire, ergonomics, environmentMeasurement,
            explosion, environment, legislation,
            workingAtHeight, mobileEquipment, electrical,
            constructionMachinery,
        )
    }
}
