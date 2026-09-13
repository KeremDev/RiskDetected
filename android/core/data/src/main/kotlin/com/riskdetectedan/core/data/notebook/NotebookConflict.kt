package com.riskdetectedan.core.data.notebook

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable data class NotebookConflict(val conflict_id: String, val base_version: Long, val server_version: Long,
    val incoming_title: String?, val incoming_body: String?, val server_title: String?, val server_body: String?)
@Serializable data class NotebookConflictDetail(val note_id: String, val title: String?, val body: String?, val version: Long,
    val tombstone: Boolean, val updated_at: String, val conflicts: List<NotebookConflict>) {
    fun record() = NotebookRecord(note_id, title, body, version, tombstone, updated_at)
}
@Serializable data class NotebookConflictPage(val schema_version: Int, val note: NotebookConflictDetail,
    val has_more_conflicts: Boolean, val next_conflict_after: String?) {
    fun validate(noteID: String, after: String?) {
        note.record().validate()
        require(schema_version == 1 && note.note_id == noteID && note.conflicts.size <= 20 && (!note.tombstone || note.conflicts.isEmpty()))
        require(if (has_more_conflicts) note.conflicts.size == 20 && next_conflict_after == note.conflicts.last().conflict_id else next_conflict_after == null)
        var previous = after ?: ""
        for (conflict in note.conflicts) {
            require(UUID.fromString(conflict.conflict_id).toString() == conflict.conflict_id && conflict.conflict_id > previous)
            require(conflict.base_version in 0..9007199254740991L && conflict.server_version in 1..note.version)
            require(listOf(conflict.incoming_title, conflict.server_title).all { (it?.codePointCount(0, it.length) ?: 0) <= 200 })
            require(listOf(conflict.incoming_body, conflict.server_body).all { (it?.codePointCount(0, it.length) ?: 0) <= 20000 })
            previous = conflict.conflict_id
        }
    }
}
