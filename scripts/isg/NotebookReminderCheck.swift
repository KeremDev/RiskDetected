import Foundation

@main struct NotebookReminderCheck {
    static func main() throws {
        let reminder = UUID(), occurrence = UUID(), installation = UUID()
        let raw = try JSONSerialization.data(withJSONObject: [
            "schema_version": 1,
            "delivery_mode": "server_push",
            "has_more": false,
            "next_after": NSNull(),
            "reminders": [[
                "reminder_id": reminder.uuidString.lowercased(), "note_id": NSNull(), "title": "Kontrol",
                "recurrence": "daily", "local_time": "09:00:00", "starts_on": "2026-09-14",
                "timezone": "Europe/Istanbul", "series_version": 1, "state": "active",
                "updated_at": "2026-09-13T16:00:00Z", "delivery_strategy": "server_push",
                "delivery_installation_id": installation.uuidString.lowercased(),
                "next_occurrence": ["occurrence_id": occurrence.uuidString.lowercased(), "occurrence_no": 1,
                    "series_version": 1, "due_at": "2026-09-14T06:00:00Z",
                    "effective_due_at": "2026-09-14T06:00:00Z", "state": "scheduled", "snoozed_until": NSNull()]
            ]]
        ])
        let page = try JSONDecoder().decode(NotebookReminderPage.self, from: raw)
        try page.validate(after: nil)
        precondition(page.reminders.single?.delivery_installation_id == installation)
        let payload = NotebookReminderMutationPayload(mutation: UUID(), action: "create", reminder: nil,
            note: nil, occurrence: nil, expected: 0, title: "Kontrol", recurrence: .daily,
            localTime: "09:00:00", startsOn: "2026-09-14", timezone: "Europe/Istanbul",
            snoozedUntil: nil, installation: installation)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as! [String: Any]
        for key in ["p_reminder", "p_note", "p_occurrence", "p_snoozed_until"] {
            precondition(object[key] is NSNull)
        }
        precondition(object["p_installation"] as? String == installation.uuidString.uppercased())
        print("NotebookReminder: PASS (server-push owner, response bounds, explicit nulls)")
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
