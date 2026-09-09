import Foundation

let suite = "rd.meta.tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let ledger = MetaEventLedger(defaults: defaults)
precondition(ledger.claim("report_created", sourceID: "report-1"))
precondition(!ledger.claim("report_created", sourceID: "report-1"))
precondition(MetaEventLedger(defaults: defaults).claim("report_created", sourceID: "report-2"))
precondition(!MetaEventLedger(defaults: defaults).claim("report_created", sourceID: "report-1"))
precondition(ledger.claim("trial_started", sourceID: "transaction-1"))
precondition(ledger.claim("subscription_started", sourceID: "transaction-1"))
precondition(ledger.claim("first_risk_analysis", sourceID: "account-1"))
precondition(ledger.claim("first_risk_analysis", sourceID: "account-2"))
precondition(!ledger.claim("first_risk_analysis", sourceID: "account-1"))
precondition(!defaults.dictionaryRepresentation().keys.contains { $0.contains("account-1") || $0.contains("report-1") })
let now = Date()
precondition(MetaEventLedger.isNewRegistration(createdAt: now.addingTimeInterval(-10), lastSignInAt: now, now: now))
precondition(!MetaEventLedger.isNewRegistration(createdAt: now.addingTimeInterval(-86400), lastSignInAt: now, now: now))
precondition(!MetaEventLedger.isNewRegistration(createdAt: now.addingTimeInterval(-86400), lastSignInAt: now.addingTimeInterval(-86400), now: now))
precondition(!MetaEventLedger.isNewRegistration(createdAt: now, lastSignInAt: nil, now: now))
precondition(!MetaEventLedger.isNewRegistration(createdAt: now.addingTimeInterval(10), lastSignInAt: now, now: now))
print("Meta ledger: 15 checks passed (persistent deduplication, account isolation, identifiers, registration)")
