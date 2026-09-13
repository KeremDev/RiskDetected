package com.riskdetectedan.core.data.notebook

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable data class NotebookItem(val item_id: String, val text: String, val done: Boolean)
@Serializable data class NotebookOrganization(val schema_version: Int, val note_id: String, val version: Long,
    val tombstone: Boolean, val items: List<NotebookItem>, val tags: List<String>) {
    fun validate(id: String) {
        require(schema_version == 1 && note_id == id && version in 1..9007199254740991L && (!tombstone || (items.isEmpty() && tags.isEmpty())))
        validateNotebookOrganization(items, tags)
    }
}
fun validateNotebookOrganization(items: List<NotebookItem>, tags: List<String>) {
    require(items.size <= 500 && tags.size <= 30 && items.map { it.item_id }.toSet().size == items.size)
    require(items.all { UUID.fromString(it.item_id).toString() == it.item_id && it.text.isNotBlank() && it.text.codePointCount(0, it.text.length) <= 1000 })
    require(tags.all { it.isNotBlank() && it.codePointCount(0, it.length) <= 60 })
    require(tags.map { it.trim().lowercase(java.util.Locale.ROOT) }.toSet().size == tags.size)
}
