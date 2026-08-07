package com.riskdetectedan.core.data.progress

import com.riskdetectedan.core.common.RdResult
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
 * Mirrors ProfessionalProgressSummary's computed properties. `weeklyTracking`'s "is this
 * actually the current week" check and its zero-state copy are NOT ported (needs the exact
 * iso8601/business-timezone week-start math iOS uses) — `weeklySummary` is exposed raw instead;
 * the UI reads it directly and shows nothing if null. Documented simplification, not a silent
 * drop: matches this port's pattern of porting the data contract before the last mile of
 * presentation logic.
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
