package com.riskdetectedan.core.data.progress

import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.common.RdClientMetadata
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mirrors ProfessionalProgressModels.swift's title ladder exactly (label/threshold values,
 * Turkish copy only — RDLocalization's English catalog isn't ported, matches this port's
 * Turkish-first scope everywhere else). Per-title accent colors (RDColor hex values) are NOT
 * ported — functional-skeleton-first, same simplification already applied to every other
 * screen this session ("fonksiyonel iskelete devam et"); the visual-design pass adds these.
 */
enum class ProfessionalProgressTitle(val key: String, val label: String, val threshold: Int) {
    Candidate("candidate", "Aday Uzman", 0),
    FieldObserver("field_observer", "Saha Gözlemcisi", 1_000),
    RiskHunter("risk_hunter", "Risk Avcısı", 5_000),
    HazardAnalyst("hazard_analyst", "Tehlike Analisti", 15_000),
    SeniorRiskSpecialist("senior_risk_specialist", "Kıdemli Risk Uzmanı", 40_000),
    SafetyStrategist("safety_strategist", "Güvenlik Stratejisti", 90_000),
    MasterHSESpecialist("master_hse_specialist", "Usta İSG Uzmanı", 180_000),
    ;

    companion object {
        fun current(mdp: Int): ProfessionalProgressTitle =
            entries.lastOrNull { mdp >= it.threshold } ?: Candidate

        fun next(after: ProfessionalProgressTitle): ProfessionalProgressTitle? {
            val index = entries.indexOf(after)
            return entries.getOrNull(index + 1)
        }
    }
}

/** Mirrors ProfessionalProgressCompetency — icon/accent mapping not ported (see title ladder's
 * doc comment, same reason). */
enum class ProfessionalProgressCompetency(val key: String, val label: String) {
    Fire("fire", "Yangın"),
    Chemical("chemical", "Kimyasal"),
    Electrical("electrical", "Elektrik"),
    Mechanical("mechanical", "Mekanik"),
    Ergonomics("ergonomics", "Ergonomi"),
    Psychosocial("psychosocial", "Psikososyal"),
    WorkingAtHeight("working_at_height", "Yüksekte Çalışma"),
    Ppe("ppe", "KKD"),
    Mining("mining", "Maden"),
    Construction("construction", "İnşaat"),
    Factory("factory", "Fabrika"),
    ;

    companion object {
        fun fromKey(key: String?): ProfessionalProgressCompetency? =
            entries.firstOrNull { it.key == key }
    }
}

@Serializable
data class ProfessionalProgressProfileRow(
    @SerialName("user_id") val userId: String,
    @SerialName("total_mdp") val totalMdp: Int = 0,
    @SerialName("current_title_key") val currentTitleKey: String = ProfessionalProgressTitle.Candidate.key,
    @SerialName("total_analyses") val totalAnalyses: Int = 0,
    @SerialName("total_reports") val totalReports: Int = 0,
    @SerialName("total_findings") val totalFindings: Int = 0,
    @SerialName("critical_findings") val criticalFindings: Int = 0,
    @SerialName("high_findings") val highFindings: Int = 0,
    @SerialName("medium_findings") val mediumFindings: Int = 0,
    @SerialName("low_findings") val lowFindings: Int = 0,
    @SerialName("unknown_findings") val unknownFindings: Int = 0,
    @SerialName("active_days") val activeDays: Int = 0,
    @SerialName("last_event_at") val lastEventAt: String? = null,
    @SerialName("last_title_change_at") val lastTitleChangeAt: String? = null,
)

@Serializable
data class ProfessionalProgressCompetencyStat(
    @SerialName("user_id") val userId: String,
    @SerialName("competency_key") val competencyKey: String,
    @SerialName("analysis_count") val analysisCount: Int = 0,
    @SerialName("report_count") val reportCount: Int = 0,
    @SerialName("finding_count") val findingCount: Int = 0,
    @SerialName("critical_count") val criticalCount: Int = 0,
    @SerialName("high_count") val highCount: Int = 0,
    @SerialName("medium_count") val mediumCount: Int = 0,
    @SerialName("low_count") val lowCount: Int = 0,
    @SerialName("unknown_count") val unknownCount: Int = 0,
    @SerialName("onboarding_seed") val onboardingSeed: Boolean = false,
    @SerialName("last_detected_at") val lastDetectedAt: String? = null,
) {
    val competency: ProfessionalProgressCompetency? get() = ProfessionalProgressCompetency.fromKey(competencyKey)
    val signalCount: Int get() = findingCount + reportCount

    /** Mirrors the Swift `score` computation exactly: log-scaled signal count against a base-26
     * curve, clamped 0..100, with a flat 8 for an onboarding-seeded competency with no real
     * signal yet. */
    val score: Int
        get() {
            if (signalCount <= 0) return if (onboardingSeed) 8 else 0
            val normalized = 100 * kotlin.math.ln(1.0 + signalCount) / kotlin.math.ln(26.0)
            return normalized.let { kotlin.math.min(100, kotlin.math.max(0, Math.round(it).toInt())) }
        }
}

@Serializable
data class ProfessionalProgressBadge(
    val id: String,
    @SerialName("badge_key") val badgeKey: String,
    @SerialName("badge_type") val badgeType: String,
    val title: String,
    val subtitle: String,
    @SerialName("icon_name") val iconName: String,
    @SerialName("unlocked_at") val unlockedAt: String? = null,
    @SerialName("seen_at") val seenAt: String? = null,
) {
    val isSeen: Boolean get() = seenAt != null

    /** Badge rows predate the global-localization contract and therefore contain Turkish copy.
     * Resolve the stable server key on-device so an English Android session never renders that
     * legacy Turkish payload. Unknown future badges deliberately fall back to the server value. */
    val localizedTitle: String
        get() = if (RdClientMetadata.APP_LANGUAGE == "en") englishCopy()?.first ?: title else title

    val localizedSubtitle: String
        get() = if (RdClientMetadata.APP_LANGUAGE == "en") englishCopy()?.second ?: subtitle else subtitle

    private fun englishCopy(): Pair<String, String>? = when (badgeKey) {
        "reports:1" -> "First Step" to
            "You created your first report. Your professional tracking journey has begun."
        "reports:10" -> "Steady Start" to
            "You reached 10 reports. Your reporting discipline is getting stronger."
        "reports:25" -> "Consistent Professional" to
            "You built a regular tracking habit with 25 reports."
        "reports:50" -> "Experienced Observer" to
            "Fifty reports represent a strong body of field observation."
        "reports:100" -> "Hundred Report Club" to
            "Your 100th report is a significant professional milestone."
        "reports:250" -> "Field Veteran" to
            "You reached 250 reports. Your professional track record is growing deeper."
        "reports:500" -> "Senior Field Leader" to
            "Five hundred reports demonstrate sustained field discipline."
        "reports:1000" -> "Thousand Report Master" to
            "You reached 1,000 reports. This is a major professional archive."
        "competency:3" -> "Versatile Perspective" to
            "You documented risks across 3 competency areas."
        "competency:5" -> "Broad-Spectrum Specialist" to
            "You built experience across 5 different competency areas."
        "competency:8" -> "Comprehensive Analyst" to
            "You made 8 different competency areas visible."
        "competency:11" -> "Full-Spectrum Analyst" to
            "You built a track record across all 11 competency areas."
        "risk:first_high" -> "Decisive Action" to
            "You completed your first high- or critical-risk analysis and made a difficult issue visible."
        "report_kind:first_risk_analysis" -> "Risk Assessment Report" to
            "You archived your first detailed risk assessment report."
        "active_days:30" -> "One-Month Journey" to
            "You created analyses or reports on 30 different active days."
        "active_days:90" -> "Three Months of Consistency" to
            "You established a professional tracking record across 90 active days."
        "active_days:365" -> "A Year of Experience" to
            "You built an active RiskDetected track record spanning a full year."
        else -> if (badgeKey.startsWith("onboarding_area:first_report:")) {
            "First Report in Your Selected Field" to
                "You created your first report in a competency area selected during onboarding."
        } else {
            null
        }
    }
}

@Serializable
data class ProfessionalProgressMessage(
    val id: String,
    @SerialName("message_type") val messageType: String,
    val title: String,
    val body: String,
    @SerialName("competency_key") val competencyKey: String? = null,
    @SerialName("risk_level") val riskLevel: String? = null,
    @SerialName("seen_at") val seenAt: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
)

@Serializable
data class ProfessionalProgressWeeklySummary(
    val id: String,
    @SerialName("week_start") val weekStart: String,
    @SerialName("reports_count") val reportsCount: Int = 0,
    @SerialName("analyses_count") val analysesCount: Int = 0,
    @SerialName("findings_count") val findingsCount: Int = 0,
    @SerialName("top_competency_key") val topCompetencyKey: String? = null,
    @SerialName("message_title") val messageTitle: String? = null,
    @SerialName("message_body") val messageBody: String? = null,
)

/**
 * Mirrors ProfessionalProgressSummary's computed properties, including [weeklyTracking] (real
 * iso8601/Europe-Istanbul week-start math, ported once Home's real layout needed the exact
 * zero-state copy it drives — see that property's own doc comment).
 */
data class ProfessionalProgressSummary(
    val profile: ProfessionalProgressProfileRow,
    val competencies: List<ProfessionalProgressCompetencyStat>,
    val badges: List<ProfessionalProgressBadge>,
    val messages: List<ProfessionalProgressMessage>,
    val weeklySummary: ProfessionalProgressWeeklySummary?,
) {
    val currentTitle: ProfessionalProgressTitle get() = ProfessionalProgressTitle.current(profile.totalMdp)
    val nextTitle: ProfessionalProgressTitle? get() = ProfessionalProgressTitle.next(currentTitle)

    val nextTitleRemaining: Int
        get() = nextTitle?.let { (it.threshold - profile.totalMdp).coerceAtLeast(0) } ?: 0

    val titleProgress: Double
        get() {
            val next = nextTitle ?: return 1.0
            val current = currentTitle.threshold
            val span = (next.threshold - current).coerceAtLeast(1)
            return ((profile.totalMdp - current).toDouble() / span).coerceIn(0.0, 1.0)
        }

    val topCompetencies: List<ProfessionalProgressCompetencyStat>
        get() = competencies
            .filter { it.signalCount > 0 || it.onboardingSeed }
            .sortedWith(
                compareByDescending<ProfessionalProgressCompetencyStat> { it.signalCount }
                    .thenByDescending { it.score },
            )

    val pendingCelebration: ProfessionalProgressBadge?
        get() = badges.firstOrNull { !it.isSeen }

    /** Real port of `ProfessionalProgressSummary.weeklyTracking` (was explicitly NOT ported in
     * Faz #24, documented then as "needs the exact iso8601/business-timezone week-start math").
     * `weeklySummary.normalizedWeekStart` (first 10 chars) vs. the current ISO-8601 week's Monday
     * in Europe/Istanbul — a stale (last week's) `weeklySummary` row falls back to the same
     * zero-state as no row at all, matching the Swift `guard` exactly. */
    val weeklyTracking: ProfessionalProgressWeeklyTracking
        get() {
            val current = weeklySummary?.takeIf { it.weekStart.take(10) == currentWeekStartIso() }
            if (current == null) {
                return ProfessionalProgressWeeklyTracking(
                    title = localized("Haftalık Takip", "Weekly Tracking"),
                    body = weeklyTrackingBody(reports = 0, analyses = 0),
                    reportsCount = 0,
                    analysesCount = 0,
                    findingsCount = 0,
                    topCompetency = null,
                )
            }
            val topCompetency = ProfessionalProgressCompetency.fromKey(current.topCompetencyKey)
            return ProfessionalProgressWeeklyTracking(
                title = if (RdClientMetadata.APP_LANGUAGE == "en") {
                    "Weekly Tracking"
                } else {
                    current.messageTitle ?: "Haftalık Takip"
                },
                body = if (RdClientMetadata.APP_LANGUAGE == "en") {
                    weeklyTrackingBody(reports = current.reportsCount, analyses = current.analysesCount)
                } else {
                    current.messageBody
                        ?: weeklyTrackingBody(reports = current.reportsCount, analyses = current.analysesCount)
                },
                reportsCount = current.reportsCount,
                analysesCount = current.analysesCount,
                findingsCount = current.findingsCount,
                topCompetency = topCompetency,
            )
        }

    private fun weeklyTrackingBody(reports: Int, analyses: Int): String = when {
        reports == 0 && analyses == 0 -> localized("Bu hafta ilk analizini başlat. 😔", "Start your first analysis this week. 😔")
        reports == 0 -> localized("$analyses analiz tamamladın. Şimdi rapora dönüştür.", "You completed $analyses analyses. Now turn them into a report.")
        reports == 1 -> localized("İlk rapor tamam. Devam et.", "First report complete. Keep going.")
        else -> localized("Bu hafta $reports rapor tamamladın. 💪", "You completed $reports reports this week. 💪")
    }

    private fun localized(tr: String, en: String): String =
        if (RdClientMetadata.APP_LANGUAGE == "en") en else tr

    private companion object {
        /** Matches `Calendar(identifier: .iso8601)`'s week-of-year start (Monday), same
         * "Europe/Istanbul" business timezone as everywhere else in this feature. */
        fun currentWeekStartIso(): String {
            val zone = java.time.ZoneId.of("Europe/Istanbul")
            val monday = java.time.LocalDate.now(zone)
                .with(java.time.temporal.TemporalAdjusters.previousOrSame(java.time.DayOfWeek.MONDAY))
            return java.time.format.DateTimeFormatter.ISO_LOCAL_DATE.format(monday)
        }
    }
}

/** Real port of `ProfessionalProgressWeeklyTracking` — the resolved (possibly zero-state) weekly
 * message [ProfessionalProgressSummary.weeklyTracking] computes, distinct from the raw
 * [ProfessionalProgressWeeklySummary] row. */
data class ProfessionalProgressWeeklyTracking(
    val title: String,
    val body: String,
    val reportsCount: Int,
    val analysesCount: Int,
    val findingsCount: Int,
    val topCompetency: ProfessionalProgressCompetency?,
) {
    val hasActivity: Boolean get() = reportsCount > 0 || analysesCount > 0
}

@Singleton
class ProfessionalProgressRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    suspend fun fetchSummary(userId: String): RdResult<ProfessionalProgressSummary> = try {
        coroutineScope {
            val profileDeferred = async {
                client.postgrest.from("professional_progress_profiles")
                    .select {
                        filter { eq("user_id", userId) }
                        limit(1)
                    }
                    .decodeList<ProfessionalProgressProfileRow>()
            }
            val competenciesDeferred = async {
                client.postgrest.from("professional_progress_competency_stats")
                    .select {
                        filter { eq("user_id", userId) }
                    }
                    .decodeList<ProfessionalProgressCompetencyStat>()
            }
            val badgesDeferred = async {
                client.postgrest.from("professional_progress_badges")
                    .select {
                        filter { eq("user_id", userId) }
                        order("unlocked_at", Order.DESCENDING)
                        limit(24)
                    }
                    .decodeList<ProfessionalProgressBadge>()
            }
            val messagesDeferred = async {
                client.postgrest.from("professional_progress_messages")
                    .select {
                        filter { eq("user_id", userId) }
                        order("created_at", Order.DESCENDING)
                        limit(5)
                    }
                    .decodeList<ProfessionalProgressMessage>()
            }
            val weeklyDeferred = async {
                client.postgrest.from("professional_progress_weekly_summaries")
                    .select {
                        filter { eq("user_id", userId) }
                        order("week_start", Order.DESCENDING)
                        limit(1)
                    }
                    .decodeList<ProfessionalProgressWeeklySummary>()
            }

            val profileRows = profileDeferred.await()
            val profile = profileRows.firstOrNull() ?: ProfessionalProgressProfileRow(userId = userId)

            RdResult.Success(
                ProfessionalProgressSummary(
                    profile = profile,
                    competencies = competenciesDeferred.await(),
                    badges = badgesDeferred.await(),
                    messages = messagesDeferred.await(),
                    weeklySummary = weeklyDeferred.await().firstOrNull(),
                ),
            )
        }
    } catch (t: Throwable) {
        RdResult.Failure("professional_progress_fetch_failed", t.message ?: "fetch_failed", t)
    }

    suspend fun markBadgeSeen(badgeId: String): RdResult<Unit> = try {
        client.postgrest.from("professional_progress_badges")
            .update(mapOf("seen_at" to Instant.now().toString())) {
                filter { eq("id", badgeId) }
            }
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure("professional_progress_badge_seen_failed", t.message ?: "failed", t)
    }

    suspend fun markMessageSeen(messageId: String): RdResult<Unit> = try {
        client.postgrest.from("professional_progress_messages")
            .update(mapOf("seen_at" to Instant.now().toString())) {
                filter { eq("id", messageId) }
            }
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure("professional_progress_message_seen_failed", t.message ?: "failed", t)
    }
}
