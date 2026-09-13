import Foundation

enum NotebookReminderRecurrence: String, CaseIterable, Codable, Identifiable {
    case once, daily, weekly, monthly

    var id: String { rawValue }
    var label: String {
        switch self {
        case .once: return "Bir kez"
        case .daily: return "Her gün"
        case .weekly: return "Her hafta"
        case .monthly: return "Her ay"
        }
    }
}

struct NotebookReminderOccurrence: Codable, Equatable, Identifiable {
    let occurrence_id: UUID
    let occurrence_no: Int
    let series_version: Int64
    let due_at: String
    let effective_due_at: String
    let state: String
    let snoozed_until: String?

    var id: UUID { occurrence_id }

    func validate() throws {
        guard occurrence_no > 0,
              (1...9_007_199_254_740_991).contains(series_version),
              ["scheduled", "snoozed"].contains(state),
              NotebookReminderDate.parse(due_at) != nil,
              NotebookReminderDate.parse(effective_due_at) != nil,
              snoozed_until == nil || NotebookReminderDate.parse(snoozed_until!) != nil else {
            throw NotebookFailure.invalid
        }
    }
}

struct NotebookReminder: Codable, Equatable, Identifiable {
    let reminder_id: UUID
    let note_id: UUID?
    let title: String
    let recurrence: NotebookReminderRecurrence
    let local_time: String
    let starts_on: String
    let timezone: String
    let series_version: Int64
    let state: String
    let updated_at: String
    let delivery_strategy: String?
    let delivery_installation_id: UUID?
    let next_occurrence: NotebookReminderOccurrence?

    var id: UUID { reminder_id }

    func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.unicodeScalars.count <= 200,
              (1...9_007_199_254_740_991).contains(series_version),
              ["active", "cancelled"].contains(state),
              delivery_strategy == nil || delivery_strategy == "server_push",
              !local_time.isEmpty, !starts_on.isEmpty, !timezone.isEmpty,
              NotebookReminderDate.parse(updated_at) != nil else {
            throw NotebookFailure.invalid
        }
        try next_occurrence?.validate()
    }
}

struct NotebookReminderPage: Decodable {
    let schema_version: Int
    let reminders: [NotebookReminder]
    let has_more: Bool
    let next_after: UUID?
    let delivery_mode: String

    func validate(after: UUID?) throws {
        guard schema_version == 1, delivery_mode == "server_push", reminders.count <= 20,
              has_more ? reminders.count == 20 && next_after == reminders.last?.reminder_id : next_after == nil else {
            throw NotebookFailure.invalid
        }
        var previous = after?.uuidString.lowercased() ?? ""
        for reminder in reminders {
            try reminder.validate()
            let current = reminder.reminder_id.uuidString.lowercased()
            guard current > previous else { throw NotebookFailure.invalid }
            previous = current
        }
    }
}

struct NotebookReminderMutationPayload: Encodable {
    let mutation: UUID
    let action: String
    let reminder: UUID?
    let note: UUID?
    let occurrence: UUID?
    let expected: Int64
    let title: String?
    let recurrence: NotebookReminderRecurrence?
    let localTime: String?
    let startsOn: String?
    let timezone: String?
    let snoozedUntil: String?
    let installation: UUID?

    enum CodingKeys: String, CodingKey {
        case mutation = "p_mutation", action = "p_action", reminder = "p_reminder", note = "p_note"
        case occurrence = "p_occurrence", expected = "p_expected", title = "p_title"
        case recurrence = "p_recurrence", localTime = "p_local_time", startsOn = "p_starts_on"
        case timezone = "p_timezone", snoozedUntil = "p_snoozed_until", installation = "p_installation"
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(mutation, forKey: .mutation)
        try values.encode(action, forKey: .action)
        try values.encode(expected, forKey: .expected)
        try values.encodeOptional(reminder, forKey: .reminder)
        try values.encodeOptional(note, forKey: .note)
        try values.encodeOptional(occurrence, forKey: .occurrence)
        try values.encodeOptional(title, forKey: .title)
        try values.encodeOptional(recurrence, forKey: .recurrence)
        try values.encodeOptional(localTime, forKey: .localTime)
        try values.encodeOptional(startsOn, forKey: .startsOn)
        try values.encodeOptional(timezone, forKey: .timezone)
        try values.encodeOptional(snoozedUntil, forKey: .snoozedUntil)
        try values.encodeOptional(installation, forKey: .installation)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeOptional<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) }
    }
}

enum NotebookReminderDate {
    static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let isoWithoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        iso.date(from: value) ?? isoWithoutFraction.date(from: value)
    }

    static func string(_ date: Date) -> String { iso.string(from: date) }
}
