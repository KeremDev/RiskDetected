# Live RLS Isolation QA - 2026-05-29

Generated: 2026-05-29T22:30:26.164Z
Project: ppcrzemgiztzcgddbins
Run ID: 1780093812899-1620a47a

## Summary

- PASS: 12
- WARN: 0
- FAIL: 0

## Checks

| Status | Check | Detail |
| --- | --- | --- |
| PASS | Create temp users | dd45fa61..., e1d097e0... |
| PASS | User A inserts own analysis | 0f5b56e1-0116-487d-83cb-d6288c186b6c |
| PASS | User A inserts own photo | ab58d1f3-00c6-4261-b23c-26389bd04b9e |
| PASS | User A inserts own report | 7c11b6a3-f204-48a4-9e20-dac6c0f7c29e |
| PASS | User A selects own analysis | expected 1, got 1 |
| PASS | User B cannot select user A analysis | expected 0, got 0 |
| PASS | User A selects own photo | expected 1, got 1 |
| PASS | User B cannot select user A photo | expected 0, got 0 |
| PASS | User A selects own report | expected 1, got 1 |
| PASS | User B cannot select user A report | expected 0, got 0 |
| PASS | User B cannot insert analysis for user A | 403: {"code":"42501","details":null,"hint":null,"message":"new row violates row-level security policy for table \"analyses\""} |
| PASS | Cleanup temp auth users | qa-rls-a-1780093812899-1620a47a, qa-rls-b-1780093812899-1620a47a |

## Scope

- Creates two temporary Supabase auth users.
- Inserts temporary `analyses`, `photos`, and `reports` rows for user A through authenticated REST.
- Verifies user A can select own rows and user B sees zero rows for those IDs.
- Verifies user B cannot insert an `analyses` row using user A's `user_id`.
- Deletes temporary auth users at the end; cascades clean user-owned rows.

