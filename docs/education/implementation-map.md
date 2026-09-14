# EDU implementation map — 14 September 2026

Authoritative scope: the user's implementation request in this task. The supplied source-spec.md is input, not authority over later decisions.

No planning, attendance confirmation, assessment, signed-copy upload or batch PDFs. A saved education is an expert-entered completed record. Certificate text is the expert's statement. No P07 assessment/completion record is invented.

| Existing surface | Integration |
|---|---|
| pilot_training_sessions/records/participants/revisions | One existing event; education JSON contains typed company/workplace/cycle/group scopes; stable company projection IDs |
| P07 training_catalogs/training_catalog_versions | Reused for checksum-pinned package. Live pilot does not have P06; nullable source_id is kept without importing P06. Source hash and provenance in package. Existing P07 FK remains unchanged where installed. |
| company_curriculum_versions | Reused; scope_key adds cycle/group-specific active defaults. Existing legacy scope preserved. |
| P11 documents/document_versions/templates | Reused without importing export_jobs, file_assets or imports. Server freezes personal snapshot; native apps render one PDF. |
| education_document_counters | Global scope/year counter fixes cross-company document-number collision for new education output; old numbers remain. |
| v2 APIs | Reads preserved. Advanced records cannot be edited by v2. No new catalogue silently backfilled into historical rows. |
| P07 complete_training | Unchanged and unused. Requires real attendance/assessment in its own domain. |
| Existing pending mutation Keychain | Owner-scoped v3 queue, immutable request and idempotency key. |
| NovaTrainingPDFDocument | Historical operational record export remains for old records; new personal certificate renderer is separate. |

Candidate: 20260914153220_isg_education_curriculum_certificates.sql. Two controls are born false: catalog_v1 and certificate_v1. The reconciled live migration is 20260914162507_isg_education_curriculum_certificates; both controls were enabled after isolated and live rollback checks for the single pilot account. Production P07/P11 families were absent at the initial read; existing training pilot tables were reused.

## Source differences intentionally applied

Source assessment_policy remains provenance only; it does not enable assessment. EDU-025/029/030/031 assessment gates, batch certificate tests and signed-copy cases are out of scope, not passing claims. Program times describe expert-recorded occurrence, not sensor-measured attendance. Training save and certificate field readiness are separate.

## Delivery state

Backend, iOS and Android implementation and automated validation are complete. The narrow migration is deployed to the existing pilot. Runtime evidence and the remaining physical sharing/printing acceptance are recorded in release-checklist.md.
