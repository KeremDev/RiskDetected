package com.riskdetectedan.core.data.nova

import android.content.Context
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.isg.NovaExpertFailure
import com.riskdetectedan.core.data.isg.NovaExpertTransport
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.*
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/** The "Senin İçin" answer (iOS `NovaForYouFeed`). The server ranks the cards; the client words and draws them. */
@Serializable
data class NovaForYouFeed(
    @SerialName("schema_version") val schemaVersion: Int,
    val role: String,
    val segment: String,
    val cards: List<NovaForYouCard>,
    val more: List<NovaForYouCard> = emptyList(),
    /** True when "Tümü" was cut at its limit; the rest live in the module lists. */
    @SerialName("has_more") val hasMore: Boolean = false,
) {
    /** The same answer without cards hidden on this device and not yet confirmed by the server. */
    fun removing(ids: Set<String>): NovaForYouFeed =
        if (ids.isEmpty()) this else copy(cards = cards.filterNot { it.id in ids }, more = more.filterNot { it.id in ids })
}

@Serializable
data class NovaForYouCard(
    val id: String,
    val key: String,
    val kind: String,
    val tone: String,
    val dismissible: Boolean,
    val params: Params = Params(),
    val target: Target,
) {
    @Serializable
    data class Params(
        val count: Int? = null, val total: Int? = null, val delta: Int? = null, val sessions: Int? = null,
        val title: String? = null, @SerialName("company_name") val companyName: String? = null, val kind: String? = null,
        @SerialName("due_on") val dueOn: String? = null, @SerialName("updated_at") val updatedAt: String? = null,
    )

    @Serializable
    data class Target(
        val route: String, val id: String? = null, @SerialName("company_id") val companyId: String? = null,
        val kind: String? = null, val status: String? = null, val ref: String? = null,
        /** Inclusive Istanbul days of the records the card counted. */
        val from: String? = null, val to: String? = null,
        /** Only the member's own records (organization sessions). */
        val mine: Boolean? = null,
    )
}

/**
 * Where the ranked cards go on the home page (iOS `NovaForYouLayout`). The large area rotates through the
 * feature suggestions. Below it, two boxes: what needs attention (the most urgent, always) and one unfinished
 * item (the visit's turn, see [NovaForYouRotation]); progress runs as a strip under them. When a box is empty,
 * progress takes it and the strip goes; a first-step card fills a box still empty. No two places show the same
 * kind. With no suggestion left, the first steps rotate on top.
 */
data class NovaForYouLayout<T>(
    val featured: List<T> = emptyList(),
    /** One or two boxes side by side. */
    val boxes: List<T> = emptyList(),
    /** Progress, when both boxes are taken. */
    val strip: T? = null,
) {
    val size: Int get() = featured.size + boxes.size + (if (strip == null) 0 else 1)

    companion object {
        fun <T> of(items: List<T>, kind: (T) -> String, id: (T) -> String = { "" }, continueId: String? = null): NovaForYouLayout<T> {
            fun all(value: String) = items.filter { kind(it) == value }
            val discover = all("discover").take(5)
            val starts = all("motivation")
            val unfinished = all("continue")
            val work = unfinished.firstOrNull { id(it) == continueId } ?: unfinished.firstOrNull()
            val pair = listOfNotNull(all("critical").firstOrNull(), work)
            val progress = all("performance").firstOrNull()
            val progressBoxed = progress != null && pair.size < 2
            val boxes = pair.toMutableList()
            val start = starts.firstOrNull()
            if (boxes.size + (if (progressBoxed) 1 else 0) < 2 && discover.isNotEmpty() && start != null) boxes += start
            if (progressBoxed && progress != null) boxes += progress
            return NovaForYouLayout(discover.ifEmpty { starts.take(5) }, boxes, if (progressBoxed) null else progress)
        }
    }
}

/**
 * Which unfinished item the home page shows (iOS `NovaForYouContinueRotation`). Each visit shows the one after
 * the item shown last, kept on this device per user and workspace; within a visit it stays, unless it goes away.
 */
class NovaForYouRotation(private val read: () -> String?, private val write: (String) -> Unit) {
    var current: String? = null
        private set
    private var picked = false

    fun newVisit() { picked = false }

    /** The item for this visit among the unfinished ones, in server order. */
    fun pick(ids: List<String>): String? {
        current?.takeIf { picked && it in ids }?.let { return it }
        current = next(if (picked) current else read(), ids)
        current?.let { picked = true; write(it) }
        return current
    }

    companion object {
        /** The item after the one shown last; the first when that one is gone. */
        fun next(after: String?, ids: List<String>): String? {
            val index = after?.let(ids::indexOf) ?: -1
            return if (index < 0) ids.firstOrNull() else ids[(index + 1) % ids.size]
        }
    }
}

/**
 * What a "Senin İçin" card asks the list it opens to show: exactly the records the card counted
 * (iOS `NovaListPreset`). The list shows the card's own words as a removable filter.
 */
data class NovaListPreset(
    /** The card's title, shown on the filter chip. */
    val title: String,
    val status: String?,
    /** Inclusive Istanbul days ("yyyy-MM-dd"). */
    val from: String?,
    val to: String?,
    /** Only records this member made (organization sessions). */
    val mine: String?,
) {
    fun includes(day: String): Boolean = (from == null || day >= from) && (to == null || day <= to)

    /** Whether the moment falls on one of the preset's days in Istanbul. */
    fun includes(moment: Instant?): Boolean {
        if (from == null && to == null) return true
        return moment != null && includes(istanbulDay(moment))
    }

    /** Whether a list ordered newest first can stop reading here: everything after it is older than the first day. */
    fun isBefore(moment: Instant?): Boolean = from != null && moment != null && istanbulDay(moment) < from

    fun isMine(creator: String?): Boolean = mine == null || creator.equals(mine, ignoreCase = true)

    companion object {
        fun of(title: String, target: NovaForYouCard.Target, actor: String) =
            NovaListPreset(title, target.status, target.from, target.to, if (target.mine == true) actor else null)

        fun istanbulDay(moment: Instant): String = moment.atZone(ZoneId.of("Europe/Istanbul")).toLocalDate().toString()

        /** A server timestamp, with or without fractional seconds. */
        fun moment(value: String?): Instant? = value?.let { runCatching { OffsetDateTime.parse(it).toInstant() }.getOrNull() }
    }
}

/**
 * One card event or feature use with its own id and the moment it happened (iOS `NovaForYouEvent`).
 * The server applies a repeated or late delivery without harm, so the queue can always resend.
 */
@Serializable
data class NovaForYouEvent(
    val id: String,
    val occurredAt: Long,
    val action: String,
    val cards: List<String> = emptyList(),
    val feature: String? = null,
) {
    companion object {
        fun card(action: String, cards: List<String>) =
            NovaForYouEvent(UUID.randomUUID().toString(), System.currentTimeMillis(), action, cards)
        fun use(feature: String) =
            NovaForYouEvent(UUID.randomUUID().toString(), System.currentTimeMillis(), "feature", feature = feature)
    }
}

/**
 * "Senin İçin" reads and events (iOS `NovaForYouService` + `NovaForYouOutbox` + `NovaLocalDraftDigest`).
 * Calls go through [NovaExpertTransport], so an organization session reaches the same endpoints through
 * `isg_expert_rpc_v1`. Events are written to a per user + workspace queue first, sent next and removed
 * on the server's answer; at most 50, and none older than 30 days.
 */
@Singleton
class NovaForYouService @Inject constructor(
    @ApplicationContext context: Context,
    private val transport: NovaExpertTransport,
    private val training: NovaTrainingService,
    private val companyCreate: NovaCompanyCreateService,
) {
    companion object {
        /** The card set this build can word; a card added later never reaches it. 2: the progress cards for the whole record. */
        const val CONTRACT = 2
        private var current: NovaForYouService? = null

        /**
         * Records the use of a feature that leaves no record of its own (the on-device wizards, the sample
         * form libraries, statistics, Evrak Takibi). Screens call it without holding the service.
         */
        fun recordUse(feature: String) { current?.use(feature) }
    }

    init { current = this }

    private val outbox = context.getSharedPreferences("nova.foryou.outbox.v1", Context.MODE_PRIVATE)
    private val turns = context.getSharedPreferences("nova.foryou.continue.v1", Context.MODE_PRIVATE)
    private val json = Json(novaJson) { encodeDefaults = true }
    private val lock = Mutex()
    private val flushing = mutableSetOf<String>()
    private val recorded = mutableSetOf<String>()
    private val answers = java.util.concurrent.ConcurrentHashMap<String, NovaForYouFeed>()
    private val background = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun namespace(identity: IsgWorkspaceIdentity): String =
        transport.capture()?.access?.storageNamespace ?: "${identity.userId.lowercase()}:personal"

    /** The last answer for this user and workspace, drawn while the fresh one loads. */
    fun cached(identity: IsgWorkspaceIdentity): NovaForYouFeed? = answers[namespace(identity)]

    /** The unfinished item's turn for one visit to the home page, per user and workspace. */
    fun rotation(identity: IsgWorkspaceIdentity): NovaForYouRotation {
        val namespace = namespace(identity)
        return NovaForYouRotation({ turns.getString(namespace, null) }, { turns.edit().putString(namespace, it).apply() })
    }

    /** Sends what is queued first, so the answer already reflects the latest decisions (iOS `NovaForYouModel.load`). */
    suspend fun load(identity: IsgWorkspaceIdentity, routes: List<String>, personal: Boolean): NovaForYouFeed {
        runCatching { flush(identity) }.onFailure { if (it is CancellationException) throw it }
        if (transport.identityNow() != identity) throw NovaExpertFailure("ACCESS_DENIED")
        val local = localDrafts(identity, personal)
        val data = transport.execute("isg_home_feed_v1", buildJsonObject {
            put("p_local", JsonArray(local))
            put("p_client", buildJsonObject {
                put("contract", CONTRACT)
                put("routes", JsonArray(routes.map(::JsonPrimitive)))
            })
        }, maxBytes = 1_048_576)
        if (transport.identityNow() != identity) throw NovaExpertFailure("ACCESS_DENIED")
        val feed = data.decodeAs(NovaForYouFeed.serializer())
        if (feed.schemaVersion != 1) throw NovaExpertFailure("UNAVAILABLE")
        answers[namespace(identity)] = feed
        return feed
    }

    /** Unfinished work that exists only on this device, in this session's scope. Nothing of the draft leaves it. */
    private fun localDrafts(identity: IsgWorkspaceIdentity, personal: Boolean): List<JsonObject> {
        val drafts = mutableListOf<JsonObject>()
        runCatching { training.newDraftStamp(identity) }.getOrNull()?.let { stamp ->
            drafts += buildJsonObject {
                put("kind", "training_draft"); put("ref", stamp.ref.lowercase())
                stamp.companyId?.let { put("company_id", it) }
                put("updated_at", Instant.ofEpochMilli(stamp.updatedAt).toString())
            }
        }
        // A company create interrupted while it was being sent. The intent has its own mutation id; it keeps
        // no edit time, and it is the most urgent kind of unfinished work, so it is described as current.
        if (personal) runCatching { companyCreate.pending(identity) }.getOrNull()?.let { intent ->
            drafts += buildJsonObject {
                put("kind", "company_create"); put("ref", intent.mutationID.lowercase())
                put("updated_at", Instant.now().toString())
            }
        }
        return drafts
    }

    fun pending(namespace: String): List<NovaForYouEvent> =
        outbox.getString(namespace, null)?.let { raw ->
            runCatching { json.decodeFromString(ListSerializer(NovaForYouEvent.serializer()), raw) }.getOrNull()
        }.orEmpty()

    private fun write(namespace: String, events: List<NovaForYouEvent>) {
        val cutoff = System.currentTimeMillis() - 30L * 86_400_000L
        val kept = events.filter { it.occurredAt >= cutoff }.takeLast(50)
        if (kept.isEmpty()) outbox.edit().remove(namespace).apply()
        else outbox.edit().putString(namespace, json.encodeToString(ListSerializer(NovaForYouEvent.serializer()), kept)).apply()
    }

    suspend fun add(namespace: String, event: NovaForYouEvent) = lock.withLock { write(namespace, pending(namespace) + event) }

    /**
     * Sends in the order the events happened. A refused event (malformed for this server) is dropped; a
     * network or session failure stops the pass and the rest waits for the next one.
     */
    suspend fun flush(identity: IsgWorkspaceIdentity) {
        val namespace = namespace(identity)
        if (!lock.withLock { flushing.add(namespace) }) return
        try {
            for (event in pending(namespace).sortedBy { it.occurredAt }) {
                try {
                    send(identity, event)
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (failure: NovaExpertFailure) {
                    if (failure.code != "VALIDATION_ERROR") return
                } catch (_: Exception) {
                    return
                }
                lock.withLock { write(namespace, pending(namespace).filterNot { it.id == event.id }) }
            }
        } finally {
            lock.withLock { flushing.remove(namespace) }
        }
    }

    private suspend fun send(identity: IsgWorkspaceIdentity, event: NovaForYouEvent) {
        if (transport.identityNow() != identity) throw NovaExpertFailure("ACCESS_DENIED")
        val moment = Instant.ofEpochMilli(event.occurredAt).toString()
        val feature = event.feature
        if (feature != null) {
            transport.execute("isg_feature_usage_v1", buildJsonObject { put("p_feature", feature); put("p_occurred_at", moment) })
        } else {
            transport.execute("isg_home_card_action_v1", buildJsonObject {
                put("p_action", event.action); put("p_cards", JsonArray(event.cards.map(::JsonPrimitive)))
                put("p_event", event.id); put("p_occurred_at", moment)
            })
        }
    }

    /** Queues [event] for this session's scope and sends what is waiting. */
    fun record(identity: IsgWorkspaceIdentity, event: NovaForYouEvent) {
        val namespace = namespace(identity)
        background.launch {
            add(namespace, event)
            runCatching { flush(identity) }
        }
    }

    private fun use(feature: String) {
        val identity = transport.identityNow() ?: return
        // The server only needs to know the feature was used; once per app session and scope is enough.
        if (!synchronized(recorded) { recorded.add("${namespace(identity)}|$feature") }) return
        record(identity, NovaForYouEvent.use(feature))
    }
}
