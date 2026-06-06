# Company Pro Device Live QA - 2026-05-30

## Scope

- Real device TestFlight QA with active Pro user.
- Flow: Profile > Firmalarım > add company > edit company > archive company.
- Backend verification: Supabase live `companies` table for `kayalar.kerem@gmail.com`.

## Result

- PASS: Pro user created a new company from the real device.
- PASS: The same company row was edited successfully.
- PASS: The same company row was archived successfully.
- PASS: Archived company no longer appears in the active company query.

## Evidence

- User: `kayalar.kerem@gmail.com`
- Company id: `b1ae19ca-bb05-47bb-804c-a3643ec9240f`
- Final name: `QA Pro Firma 20260530 Düzenlendi`
- Hazard class: `medium`
- Address: `Pro Sok.`
- Department: `Kerem`
- Contact person: `İsg`
- Default responsible: `Bölüm Yöneticisi`
- Default due days: `20`
- Created at: `2026-05-30T00:36:54.912497Z`
- Updated at: `2026-05-30T00:38:01.466964Z`
- Final archived state: `is_archived=true`

## Active List Check

- Query: active company count for `QA Pro Firma 20260530%`.
- Result: `0`

## Notes

- Existing active company `Deneme Firma` stayed active.
- This closes the remaining Pro real-device company management QA item.
