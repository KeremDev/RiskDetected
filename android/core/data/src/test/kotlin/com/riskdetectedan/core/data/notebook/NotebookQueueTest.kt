package com.riskdetectedan.core.data.notebook

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class NotebookQueueTest {
    private class Memory : NotebookStorage {
        val values = mutableMapOf<UUID, String>(); var fail = false
        override fun read(owner: UUID) = values[owner]
        override fun write(owner: UUID, value: String) { check(!fail); values[owner] = value }
    }
    private val owner = NotebookIdentity(UUID.randomUUID(), UUID.randomUUID())
    private fun draft() = NotebookMutation(UUID.randomUUID().toString(), UUID.randomUUID().toString(), "sync", 0, "Başlık", "Taslak", null)
    private fun ack(intent: NotebookMutation, state: String = "created") = buildJsonObject {
        put("schema_version", 1); put("mutation_id", intent.mutation); put("note_id", intent.note)
        put("state", state); put("replayed", false); put("version", intent.expected + 1)
        intent.conflict?.let { put("conflict_id", it) }
    }
    @Test fun `organization payload persists and retries with unchanged fields`() = runBlocking {
        val intent = draft().copy(action = "organize", expected = 1, title = null, body = null,
            items = listOf(NotebookItem(UUID.randomUUID().toString(), "Task", true)), tags = listOf("Tag"))
        val store = Memory(); val sent = mutableListOf<JsonObject>()
        val queue = NotebookQueue(store, { owner }) { sent += it; throw NotebookFailure("network") }
        queue.stage(intent, owner); assertTrue(runCatching { queue.syncNext(owner) }.isFailure)
        val reopened = NotebookQueue(store, { owner }) { sent += it; ack(intent, "organized") }
        assertEquals(intent, reopened.pending(owner).single().intent)
        assertEquals("committed", reopened.syncNext(owner)); assertEquals(sent[0], sent[1])
        assertEquals(setOf("p_mutation", "p_note", "p_expected", "p_items", "p_tags"), sent[0].keys)
    }
    @Test fun `organization stale version keeps items until explicit replacement`() = runBlocking {
        val intent = draft().copy(action = "organize", expected = 1, title = null, body = null,
            items = listOf(NotebookItem(UUID.randomUUID().toString(), "Task", true)), tags = listOf("Tag"))
        val queue = NotebookQueue(Memory(), { owner }) { throw NotebookServerFailure("VERSION_CONFLICT") }
        queue.stage(intent, owner); assertEquals("blocked", queue.syncNext(owner))
        val replacement = intent.copy(mutation = UUID.randomUUID().toString(), expected = 3)
        queue.replaceOrganization(intent.mutation, replacement, owner)
        assertEquals(replacement, queue.pending(owner).single().intent)
    }
    @Test fun `resolution race retains conflict identifier for recovery`() = runBlocking {
        val intent = draft().copy(action = "resolve", expected = 2, conflict = UUID.randomUUID().toString())
        val queue = NotebookQueue(Memory(), { owner }) { throw NotebookServerFailure("VERSION_CONFLICT") }
        queue.stage(intent, owner); queue.syncNext(owner)
        assertEquals(intent.conflict, queue.pending(owner).single().conflictID)
    }
    @Test fun `persists before network and retries exact mutation after reopening`() = runBlocking {
        val store = Memory(); val intent = draft(); val sent = mutableListOf<JsonObject>()
        val queue = NotebookQueue(store, { owner }) { sent += it; assertNotNull(store.read(owner.owner)); throw NotebookFailure("network") }
        queue.stage(intent, owner); assertTrue(runCatching { queue.syncNext(owner) }.isFailure)
        val reopened = NotebookQueue(store, { owner }) { sent += it; ack(intent) }
        assertTrue(reopened.pending(owner).single().attempted)
        assertEquals("committed", reopened.syncNext(owner)); assertEquals(sent[0], sent[1]); assertTrue(reopened.pending(owner).isEmpty())
    }
    @Test fun `storage failure prevents network`() = runBlocking {
        val store = Memory(); val queue = NotebookQueue(store, { owner }) { error("NETWORK") }; queue.stage(draft(), owner); store.fail = true
        assertTrue(runCatching { queue.syncNext(owner) }.isFailure)
    }
    @Test fun `same mutation is immutable and duplicate stage is no-op`() = runBlocking {
        val queue = NotebookQueue(Memory(), { owner }) { error("NETWORK") }; val intent = draft()
        queue.stage(intent, owner); queue.stage(intent, owner)
        assertEquals(1, queue.pending(owner).size); assertTrue(runCatching { queue.stage(intent.copy(body = "Changed"), owner) }.isFailure)
    }
    @Test fun `account switch during send retains original account draft`() = runBlocking {
        val store = Memory(); var current = owner; val other = NotebookIdentity(UUID.randomUUID(), UUID.randomUUID()); val intent = draft()
        val queue = NotebookQueue(store, { current }) { current = other; ack(intent) }
        queue.stage(intent, owner); assertTrue(runCatching { queue.syncNext(owner) }.isFailure)
        assertTrue(queue.pending(other).isEmpty()); assertTrue(runCatching { queue.pending(owner) }.isFailure)
        current = owner; assertEquals(intent, queue.pending(owner).single().intent)
    }
    @Test fun `foreign owner envelope is rejected`() = runBlocking {
        val store = Memory(); val queue = NotebookQueue(store, { owner }) { error("NETWORK") }; queue.stage(draft(), owner)
        val other = NotebookIdentity(UUID.randomUUID(), UUID.randomUUID()); store.values[other.owner] = store.values[owner.owner]!!
        assertTrue(runCatching { NotebookQueue(store, { other }) { error("NETWORK") }.pending(other) }.isFailure)
    }
    @Test fun `conflict blocks subsequent same-note edits but permits atomic explicit resolution`() = runBlocking {
        val store = Memory(); val intent = draft(); val conflict = UUID.randomUUID().toString()
        var resolving = false
        val queue = NotebookQueue(store, { owner }) { args ->
            if (resolving) buildJsonObject { put("schema_version",1);put("mutation_id",args.getValue("p_mutation"));put("note_id",intent.note);put("state","resolved");put("version",3);put("replayed",false);put("conflict_id",conflict) }
            else buildJsonObject { put("schema_version",1);put("mutation_id",intent.mutation);put("note_id",intent.note);put("state","conflict");put("replayed",false);put("server_version",2);put("conflict_id",conflict);put("both_texts_preserved",true) }
        }
        queue.stage(intent, owner); queue.stage(intent.copy(mutation=UUID.randomUUID().toString(),body="Later"), owner)
        assertEquals("conflict",queue.syncNext(owner)); assertEquals("idle",queue.syncNext(owner)); assertEquals("Taslak",queue.pending(owner).first().intent.body)
        val replacement=intent.copy(mutation=UUID.randomUUID().toString(),action="resolve",expected=2,conflict=conflict,body="Merged")
        queue.resolveBlocked(intent.mutation,replacement,owner); resolving=true
        assertEquals("committed",queue.syncNext(owner)); assertEquals("Later",queue.pending(owner).single().intent.body)
    }
    @Test fun `tombstone and version rejection preserve recoverable text`() = runBlocking {
        for (code in listOf("NOTE_TOMBSTONED","VERSION_CONFLICT","ACCESS_DENIED","VALIDATION_ERROR","IDEMPOTENCY_CONFLICT")) {
            val queue=NotebookQueue(Memory(),{owner}) { throw NotebookServerFailure(code) }; val intent=draft()
            queue.stage(intent,owner);assertEquals("blocked",queue.syncNext(owner));assertEquals(code,queue.pending(owner).single().blocked);assertEquals(intent.body,queue.pending(owner).single().intent.body)
        }
    }
    @Test fun `malformed acknowledgement never removes draft`() = runBlocking {
        val store=Memory();val intent=draft();val queue=NotebookQueue(store,{owner}) { ack(intent).toMutableMap().let { it["note_id"]=JsonPrimitive(UUID.randomUUID().toString());JsonObject(it) } }
        queue.stage(intent,owner);assertTrue(runCatching { queue.syncNext(owner) }.isFailure);assertEquals(intent,queue.pending(owner).single().intent)
    }
    @Test fun `null RPC fields and Unicode limits match server contract`() {
        val intent=draft();assertEquals(JsonNull,intent.arguments()["p_conflict"])
        assertEquals(setOf("p_mutation","p_note","p_action","p_expected","p_title","p_body","p_conflict"),intent.arguments().keys)
        intent.copy(body="😀".repeat(20000)).validate();assertTrue(runCatching { intent.copy(body="x".repeat(20001)).validate() }.isFailure)
    }
    @Test fun `queue bound never evicts old drafts`() = runBlocking {
        val queue=NotebookQueue(Memory(),{owner}){error("NETWORK")};repeat(20){queue.stage(draft(),owner)}
        assertTrue(runCatching { queue.stage(draft(),owner) }.isFailure);assertEquals(20,queue.pending(owner).size)
    }
}
