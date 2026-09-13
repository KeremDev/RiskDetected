package com.riskdetectedan.core.data.notebook

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import java.util.UUID

class NotebookFailure(val code: String) : Exception(code)
class NotebookServerFailure(val code: String) : Exception(code)
data class NotebookIdentity(val owner: UUID, val session: UUID)
@Serializable
data class NotebookMutation(val mutation: String, val note: String, val action: String, val expected: Long,
    val title: String?, val body: String?, val conflict: String?, val items: List<NotebookItem>? = null, val tags: List<String>? = null) {
    fun validate() {
        require(UUID.fromString(mutation).toString() == mutation && UUID.fromString(note).toString() == note)
        require(conflict == null || UUID.fromString(conflict).toString() == conflict)
        if (action == "organize") {
            require(expected in 1..9007199254740990L && title == null && body == null && conflict == null && items != null && tags != null)
            validateNotebookOrganization(items, tags); return
        }
        require(items == null && tags == null)
        require(action in setOf("sync", "delete", "resolve") && expected in 0..9007199254740990L)
        require((title?.codePointCount(0, title.length) ?: 0) <= 200 && (body?.codePointCount(0, body.length) ?: 0) <= 20000)
        require((action == "resolve") == (conflict != null))
        require(if (action == "delete") title == null && body == null else title != null || body != null)
    }
    fun arguments(): JsonObject {
        validate()
        if (action == "organize") return buildJsonObject {
            put("p_mutation", mutation); put("p_note", note); put("p_expected", expected)
            put("p_items", Json.encodeToJsonElement(items!!)); put("p_tags", Json.encodeToJsonElement(tags!!))
        }
        return buildJsonObject {
            put("p_mutation", mutation); put("p_note", note); put("p_action", action); put("p_expected", expected)
            put("p_title", title?.let(::JsonPrimitive) ?: JsonNull); put("p_body", body?.let(::JsonPrimitive) ?: JsonNull)
            put("p_conflict", conflict?.let(::JsonPrimitive) ?: JsonNull)
        }
    }
}
@Serializable
data class NotebookPending(val intent: NotebookMutation, val attempted: Boolean = false, val blocked: String? = null, val conflictID: String? = null)
interface NotebookStorage { fun read(owner: UUID): String?; fun write(owner: UUID, value: String) }

/** Explicitly driven durable outbox. No automatic launch, company dependency, or paid gate. */
class NotebookQueue(private val storage: NotebookStorage, private val current: () -> NotebookIdentity?,
    private val send: suspend (JsonObject) -> JsonObject) {
    @Serializable private data class Ledger(val schema: Int = 1, val owner: String, val entries: List<NotebookPending>)
    companion object { private val lock = Mutex() }
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = false }
    private suspend fun check(identity: NotebookIdentity) {
        currentCoroutineContext().ensureActive()
        if (current() != identity) throw NotebookFailure("IDENTITY_CHANGED")
    }
    private fun load(owner: UUID): Ledger {
        val value = storage.read(owner) ?: return Ledger(owner = owner.toString(), entries = emptyList())
        require(value.toByteArray(Charsets.UTF_8).size <= 2_000_000)
        val ledger = json.decodeFromString<Ledger>(value)
        require(ledger.schema == 1 && ledger.owner == owner.toString() && ledger.entries.size <= 20)
        require(ledger.entries.map { it.intent.mutation }.toSet().size == ledger.entries.size)
        ledger.entries.forEach { it.intent.validate() }; return ledger
    }
    private fun persist(ledger: Ledger) {
        val value = json.encodeToString(ledger)
        if (value.toByteArray(Charsets.UTF_8).size > 2_000_000) throw NotebookFailure("QUEUE_FULL")
        storage.write(UUID.fromString(ledger.owner), value)
    }
    suspend fun pending(identity: NotebookIdentity): List<NotebookPending> = lock.withLock { check(identity); load(identity.owner).entries }
    suspend fun stage(intent: NotebookMutation, identity: NotebookIdentity) = lock.withLock {
        check(identity); intent.validate(); val ledger = load(identity.owner)
        ledger.entries.find { it.intent.mutation == intent.mutation }?.let { require(it.intent == intent); return@withLock }
        if (ledger.entries.size >= 20) throw NotebookFailure("QUEUE_FULL")
        persist(ledger.copy(entries = ledger.entries + NotebookPending(intent)))
    }
    /** Explicit user recovery action, never automatically invoked on errors. */
    suspend fun discard(mutation: String, identity: NotebookIdentity) = lock.withLock {
        check(identity); val ledger = load(identity.owner)
        persist(ledger.copy(entries = ledger.entries.filterNot { it.intent.mutation == mutation }))
    }
    suspend fun resolveBlocked(mutation: String, replacement: NotebookMutation, identity: NotebookIdentity) = lock.withLock {
        check(identity); replacement.validate(); val ledger = load(identity.owner)
        val index = ledger.entries.indexOfFirst { it.intent.mutation == mutation }; require(index >= 0)
        val prior = ledger.entries[index]
        require(prior.blocked == "VERSION_CONFLICT" && prior.conflictID != null && replacement.action == "resolve" &&
            replacement.note == prior.intent.note && replacement.conflict == prior.conflictID && ledger.entries.none { it.intent.mutation == replacement.mutation })
        val entries = ledger.entries.toMutableList(); entries[index] = NotebookPending(replacement)
        persist(ledger.copy(entries = entries))
    }
    suspend fun syncNext(identity: NotebookIdentity): String = lock.withLock {
        check(identity); val ledger = load(identity.owner); val blockedNotes = mutableSetOf<String>()
        val index = ledger.entries.indexOfFirst {
            if (it.blocked != null) { blockedNotes += it.intent.note; false } else it.intent.note !in blockedNotes
        }
        if (index < 0) return@withLock "idle"
        val entries = ledger.entries.toMutableList(); entries[index] = entries[index].copy(attempted = true)
        persist(ledger.copy(entries = entries)); check(identity)
        val intent = entries[index].intent
        val ack = try { send(intent.arguments()) } catch (error: Exception) {
            check(identity)
            val code = (error as? NotebookServerFailure)?.code
            if (code in setOf("VERSION_CONFLICT", "NOTE_TOMBSTONED", "IDEMPOTENCY_CONFLICT", "ACCESS_DENIED", "VALIDATION_ERROR", "CONFLICT_ALREADY_RESOLVED")) {
                entries[index] = entries[index].copy(blocked = code,
                    conflictID = if (code == "VERSION_CONFLICT" && intent.action == "resolve") intent.conflict else entries[index].conflictID)
                persist(ledger.copy(entries = entries)); return@withLock "blocked"
            }
            throw NotebookFailure("UNAVAILABLE")
        }
        check(identity)
        require(ack.toString().toByteArray(Charsets.UTF_8).size <= 16384)
        require(ack["schema_version"]?.jsonPrimitive?.int == 1 && ack["mutation_id"]?.jsonPrimitive?.content == intent.mutation && ack["note_id"]?.jsonPrimitive?.content == intent.note)
        require(ack["replayed"]?.jsonPrimitive?.booleanOrNull != null)
        val state = ack["state"]?.jsonPrimitive?.content
        if (state == "conflict") {
            val conflict = ack["conflict_id"]!!.jsonPrimitive.content
            val version = ack["server_version"]!!.jsonPrimitive.long
            require(intent.action == "sync" && UUID.fromString(conflict).toString() == conflict && version in 1..9007199254740991L && ack["both_texts_preserved"]?.jsonPrimitive?.boolean == true)
            entries[index] = entries[index].copy(blocked = "VERSION_CONFLICT", conflictID = conflict)
            persist(ledger.copy(entries = entries)); return@withLock "conflict"
        }
        val allowed = when (intent.action) { "organize" -> setOf("organized"); "delete" -> setOf("deleted"); "resolve" -> setOf("resolved"); else -> setOf("created", "updated", "unchanged") }
        val version = ack["version"]!!.jsonPrimitive.long
        require(intent.action != "resolve" || ack["conflict_id"]?.jsonPrimitive?.content == intent.conflict)
        require(state in allowed && version in 1..9007199254740991L && (state == "deleted" || version == intent.expected + if (state == "unchanged") 0 else 1))
        entries.removeAt(index); persist(ledger.copy(entries = entries)); "committed"
    }
    suspend fun replaceOrganization(mutation: String, replacement: NotebookMutation, identity: NotebookIdentity) = lock.withLock {
        check(identity); replacement.validate(); val ledger = load(identity.owner)
        val index = ledger.entries.indexOfFirst { it.intent.mutation == mutation }; require(index >= 0)
        val prior = ledger.entries[index]
        require(prior.blocked == "VERSION_CONFLICT" && prior.intent.action == "organize" && replacement.action == "organize" &&
            replacement.note == prior.intent.note && ledger.entries.none { it.intent.mutation == replacement.mutation })
        val entries = ledger.entries.toMutableList(); entries[index] = NotebookPending(replacement); persist(ledger.copy(entries = entries))
    }
}
