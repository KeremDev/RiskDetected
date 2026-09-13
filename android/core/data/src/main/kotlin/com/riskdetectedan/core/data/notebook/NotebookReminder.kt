package com.riskdetectedan.core.data.notebook

import kotlinx.serialization.Serializable
import java.time.OffsetDateTime
import java.util.UUID

@Serializable
data class NotebookReminderOccurrence(
    val occurrence_id: String,
    val occurrence_no: Int,
    val series_version: Long,
    val due_at: String,
    val effective_due_at: String,
    val state: String,
    val snoozed_until: String? = null,
) {
    fun validate() {
        UUID.fromString(occurrence_id)
        require(occurrence_no > 0 && series_version in 1..9_007_199_254_740_991)
        require(state in setOf("scheduled", "snoozed"))
        OffsetDateTime.parse(due_at)
        OffsetDateTime.parse(effective_due_at)
        snoozed_until?.let(OffsetDateTime::parse)
    }
}

@Serializable
data class NotebookReminder(
    val reminder_id: String,
    val note_id: String? = null,
    val title: String,
    val recurrence: String,
    val local_time: String,
    val starts_on: String,
    val timezone: String,
    val series_version: Long,
    val state: String,
    val updated_at: String,
    val delivery_strategy: String? = null,
    val delivery_installation_id: String? = null,
    val next_occurrence: NotebookReminderOccurrence? = null,
) {
    fun validate() {
        UUID.fromString(reminder_id)
        note_id?.let(UUID::fromString)
        delivery_installation_id?.let(UUID::fromString)
        require(title.isNotBlank() && title.codePointCount(0, title.length) <= 200)
        require(recurrence in setOf("once", "daily", "weekly", "monthly"))
        require(local_time.isNotBlank() && starts_on.isNotBlank() && timezone.isNotBlank())
        require(series_version in 1..9_007_199_254_740_991 && state in setOf("active", "cancelled"))
        require(delivery_strategy == null || delivery_strategy == "server_push")
        OffsetDateTime.parse(updated_at)
        next_occurrence?.validate()
    }
}

@Serializable
internal data class NotebookReminderPage(
    val schema_version: Int,
    val reminders: List<NotebookReminder>,
    val has_more: Boolean,
    val next_after: String? = null,
    val delivery_mode: String,
) {
    fun validate(after: String?) {
        require(schema_version == 1 && delivery_mode == "server_push" && reminders.size <= 20)
        require(if (has_more) reminders.size == 20 && next_after == reminders.last().reminder_id else next_after == null)
        var previous = after.orEmpty()
        reminders.forEach {
            it.validate()
            require(it.reminder_id > previous)
            previous = it.reminder_id
        }
    }
}
