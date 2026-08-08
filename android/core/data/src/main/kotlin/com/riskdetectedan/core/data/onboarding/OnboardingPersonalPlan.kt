package com.riskdetectedan.core.data.onboarding

/**
 * Mirrors App/Models/OnboardingPersonalPlan.swift — the segment-resolution + copy model behind
 * PlanSummary/TrialInvite's "personal plan" recap. `icon` fields carry the same SF-Symbol-style
 * string keys iOS uses (not an `ImageVector` — this module has no Compose dependency, matches the
 * existing `sectorIcon()`/`hazardIcon()` pattern where the *feature* module owns the
 * string-to-Material-icon mapping, not `core:data`).
 */
enum class OnboardingPersonalPlanSegment(val key: String) {
    Construction("construction"),
    IndustrialHighRisk("industrial_high_risk"),
    OsgbHighVolume("osgb_high_volume"),
    OfficeService("office_service"),
    HealthTeam("health_team"),
}

data class OnboardingPersonalPlanStep(
    val icon: String,
    val title: String,
    val subtitle: String,
)

data class OnboardingPersonalPlanContext(
    val segment: OnboardingPersonalPlanSegment,
    val eyebrow: String,
    val headline: String,
    val subtitle: String,
    val chips: List<String>,
    val heroIcon: String,
    val steps: List<OnboardingPersonalPlanStep>,
) {
    companion object {
        /** Mirrors `OnboardingPersonalPlanContext.make(from:)` + `resolveSegment(from:)` exactly
         * (same 5-way branch order, same field values). [certificateLabel]/[hazardsLabel]/
         * [primarySectorLabel] mirror `OnboardingV2State`'s same-named computed properties —
         * pass the real onboarding answers, not fallback placeholders, at the call site. */
        fun make(
            certificate: OnboardingCertificate?,
            hazards: Set<OnboardingHazardClass>,
            sectors: List<OnboardingSector>,
            frequency: OnboardingFrequency?,
            certificateLabel: String,
            hazardsLabel: String,
            primarySectorLabel: String,
        ): OnboardingPersonalPlanContext {
            val segment = resolveSegment(certificate, hazards, sectors, frequency)
            val chips = listOf(certificateLabel, hazardsLabel, primarySectorLabel)
            val frequencyTitle = frequency?.title ?: "Rutin denetim"

            return when (segment) {
                OnboardingPersonalPlanSegment.OsgbHighVolume -> OnboardingPersonalPlanContext(
                    segment = segment,
                    eyebrow = "Sana Özel",
                    headline = "Yoğun denetim temponla yarışacak planın hazır",
                    subtitle = "İSG için eğitilmiş sistem, $frequencyTitle temposunda.",
                    chips = chips,
                    heroIcon = "bolt.fill",
                    steps = listOf(
                        OnboardingPersonalPlanStep("camera.viewfinder", "Fotoğraf", "İSG için eğitilmiş yapay zekamız anında çözümlesin."),
                        OnboardingPersonalPlanStep("exclamationmark.triangle.fill", "Riskler", "En kritik bulgu liste başında."),
                        OnboardingPersonalPlanStep("building.2.fill", "Rapor", "Rapor firma arşivine kaydedilsin."),
                        OnboardingPersonalPlanStep("paperplane.fill", "Paylaş", "Risk Analizini PDF/Excel tek tıkla ilet."),
                    ),
                )
                OnboardingPersonalPlanSegment.HealthTeam -> OnboardingPersonalPlanContext(
                    segment = segment,
                    eyebrow = "Sana özel ekip akışı",
                    headline = "İSG ekibin için kayıt ve paylaşım düzeni hazır",
                    subtitle = "$certificateLabel rolüne göre; anlaşılır bulgu dili ve düzenli dokümantasyon odaklı bir akış kurduk. Ekip içi iletişim ve arşivleme aynı yerde.",
                    chips = chips,
                    heroIcon = "cross.case.fill",
                    steps = listOf(
                        OnboardingPersonalPlanStep("camera.viewfinder", "Fotoğraf", "Gözlemini hızla analize aktar."),
                        OnboardingPersonalPlanStep("person.2.fill", "Ekip dilinde özetle", "Bulgular anlaşılır ve uygulanabilir kalsın."),
                        OnboardingPersonalPlanStep("doc.richtext.fill", "Rapor çıktısı oluştur", "Kayıt ve takip için düzenli doküman üret."),
                        OnboardingPersonalPlanStep("square.and.arrow.up.fill", "Paylaş ve arşivle", "Raporlar ekibinin hep elinin altında olsun."),
                    ),
                )
                OnboardingPersonalPlanSegment.Construction -> OnboardingPersonalPlanContext(
                    segment = segment,
                    eyebrow = "Sana Özel",
                    headline = "Şantiye tehlikeleri dakikalar içinde raporla.",
                    subtitle = "$primarySectorLabel için eğitilmiş sistem, anında rapor.",
                    chips = chips,
                    heroIcon = "hammer.fill",
                    steps = listOf(
                        OnboardingPersonalPlanStep("camera.viewfinder", "Fotoğraf", "İSG için eğitilmiş yapay zekamız anında çözümlesin."),
                        OnboardingPersonalPlanStep("shield.lefthalf.filled", "Riskler", "En kritik bulgu liste başında."),
                        OnboardingPersonalPlanStep("doc.text.magnifyingglass", "Risk Analizi", "Fine-Kinney/5x5 Rapor hazır."),
                        OnboardingPersonalPlanStep("paperplane.fill", "Paylaş", "Risk Analizini PDF/Excel tek tıkla ilet."),
                    ),
                )
                OnboardingPersonalPlanSegment.IndustrialHighRisk -> OnboardingPersonalPlanContext(
                    segment = segment,
                    eyebrow = "Sana özel",
                    headline = "Risk analiz planın hazır",
                    subtitle = "$primarySectorLabel için eğitilmiş sistem, denetime hazır rapor.",
                    chips = chips,
                    heroIcon = "exclamationmark.shield.fill",
                    steps = listOf(
                        OnboardingPersonalPlanStep("camera.viewfinder", "Fotoğraf", "Fotoğraf ya da metni paylaş, analiz başlasın."),
                        OnboardingPersonalPlanStep("gauge", "Riskler", "En kritik bulgu liste başında."),
                        OnboardingPersonalPlanStep("doc.text.magnifyingglass", "Detaylı rapor üretilir", "Fine-Kinney ve 5x5 çıktıları otomatik hazırlanır."),
                        OnboardingPersonalPlanStep("building.2.fill", "Paylaş", "Risk Analizini PDF/Excel tek tıkla ilet."),
                    ),
                )
                OnboardingPersonalPlanSegment.OfficeService -> OnboardingPersonalPlanContext(
                    segment = segment,
                    eyebrow = "Sana özel denetim akışı",
                    headline = "Pratik kontrol ve raporlama akışın hazır",
                    subtitle = "$primarySectorLabel için eğitilmiş Sistem, sade rapor.",
                    chips = chips,
                    heroIcon = "building.2.fill",
                    steps = listOf(
                        OnboardingPersonalPlanStep("checklist", "Fotoğraf", "Fotoğraf ya da metni paylaş, analiz başlasın."),
                        OnboardingPersonalPlanStep("exclamationmark.triangle.fill", "Riskler", "En kritik bulgu liste başında."),
                        OnboardingPersonalPlanStep("doc.on.doc.fill", "Rapor", "PDF/Excel çıktısı arşive hazır gelir."),
                        OnboardingPersonalPlanStep("clock.fill", "Takip ritmini koru", "$frequencyTitle akışına uygun ilerle."),
                    ),
                )
            }
        }

        private fun resolveSegment(
            certificate: OnboardingCertificate?,
            hazards: Set<OnboardingHazardClass>,
            sectors: List<OnboardingSector>,
            frequency: OnboardingFrequency?,
        ): OnboardingPersonalPlanSegment {
            if (frequency == OnboardingFrequency.SixToFifteen || frequency == OnboardingFrequency.FifteenPlus) {
                return OnboardingPersonalPlanSegment.OsgbHighVolume
            }
            if (certificate == OnboardingCertificate.Doctor || certificate == OnboardingCertificate.OtherHealth) {
                return OnboardingPersonalPlanSegment.HealthTeam
            }
            if (sectors.contains(OnboardingSector.Construction)) {
                return OnboardingPersonalPlanSegment.Construction
            }
            if (sectors.contains(OnboardingSector.Mining) ||
                sectors.contains(OnboardingSector.Energy) ||
                sectors.contains(OnboardingSector.Manufacturing) ||
                hazards.contains(OnboardingHazardClass.Critical)
            ) {
                return OnboardingPersonalPlanSegment.IndustrialHighRisk
            }
            return OnboardingPersonalPlanSegment.OfficeService
        }
    }
}
