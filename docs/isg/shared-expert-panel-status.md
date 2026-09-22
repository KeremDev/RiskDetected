# Single expert panel — staging delivery

Date: 2026-09-20. Status: **IMPLEMENTED AND DEPLOYED TO STAGING**.
iPhone delivery: version 2.0.3, build 129, `com.riskdetected.app.osgbpilot`.

## Architectural contract

There is one expert UI: the original normal/personnel `NovaPilotRoot`.
Both normal and OSGB experts use its original company workspace, company card,
accordions, education hub/forms, nonconformity forms and module routes.
The alternate `NovaWorkspaceExpert*` leaf implementations were removed.
OSGB owner/admin management screens remain separate; they are not expert screens.

Future expert UI work belongs in these shared components. Differences belong in
`NovaExpertAccess` and the verified backend workspace/company authorization,
not role-specific copies of screens.

## Implemented and deployed

- Common domain services use `NovaExpertTransport`: identity/workspace tickets,
  before/after request validation, stale-result rejection and no personal retry
  after an organization request fails.
- The backend calls the existing normal domain routines through an explicit,
  typed RPC allowlist with live membership/assignment checks. Organization rows
  remain organization-owned; exposing an actor ID for old DTO compatibility does
  not transfer ownership.
- Normal company detail/card/child routes and education curricula, editable topic
  minutes, automatic validity and manual overrides are shared.
- Home uses the common aggregate dashboard, not an OSGB company selector.
- Analysis uses the original list/detail/forms and real workspace-scoped photo
  jobs, feedback, edits, filing, source links and report archive. Its full-screen
  result does not display the bottom tabs.
- Filed scored findings retain editable risk inputs in the normal detail store.
- Shared file upload, byte inspection/promotion and authorized downloads operate
  through the real storage pipeline. Inspection is not an antivirus guarantee.
- PDF reports now embed the app's licensed Turkish-capable font and include
  detailed findings, measures and references. Excel export remains available.
- Work-permit roots and visit-observation children receive the same validated
  workspace/actor stamps as other shared process records.
- Education catalog and certificate controls enabled on staging only.

Five local migrations were applied to staging with the migration tool:
`expert_shared_panel`, `expert_shared_analysis`,
`shared_expert_runtime_fixes`, `shared_expert_process_scope`,
`shared_expert_filed_scores`.
The tool assigns remote version timestamps; reconcile migration history before
any future CLI database push. Do not blindly push all local migrations.

Deployed functions: `isg-file-inspect`, `process-isg-workspace-jobs`.
Staging project: `qlymhrrlhklcudveknih`. Production was not modified.

## Verification evidence

- Signed simulator and physical iPhone build 129 succeeded.
- Build 129 installed and launched on the connected iPhone.
- 28 architecture/company/session/education regression tests passed.
- Both changed edge functions passed Deno type checking; worker tests passed.
- Transactional staging tests passed:
  - 8 core write/authorization cases, including personnel and education replay,
    manual detailed findings, risk records, unassigned/unknown scope rejection.
  - 18 module/process writes: emergency plan, drill, representative, equipment,
    PPE, checklist, contract, annual plan and child, board and decision, visit
    and observation, work permit, contractor and engagement, completed drill,
    personnel certificate; validity overrides included.
  - 5 analysis cases: source/photos, edit/feedback, filing, export queue, deletion.
  - Scored filing preserved risk method/inputs.
  - Revoked assignment and suspended membership denied direct access.
  - Shared file state-machine and authorization checks passed.
  - 19 common read RPC probes passed, including populated module fixtures.
- Real staging HTTP acceptance: password login; byte-exact JPEG upload,
  inspection and authorized download; actual AI analysis completion;
  PDF and XLSX generation and authorized downloads with format validation.
- Simulator UI with the OSGB expert: shared dashboard; company list/detail and
  workplace accordion; actual personnel save and updated company count;
  education four-step form and editable curriculum minutes; normal manual
  nonconformity form; analysis list/photo/result; successful selected-item
  filing into the company with a success confirmation.
- A screenshot verified no bottom tab bar on the analysis result.
- Existing security advisor warnings were unchanged after the main migration;
  the new private RLS tables intentionally have no direct client policies.

## Scope and test data

The physical-device check confirms installation/launch, not an exhaustive manual
tap-through of every screen on hardware. UI checks above ran in the simulator;
broader mutation and isolation checks ran against staging. This is not an
App Store/production release or a claim that pre-existing normal-panel product
limitations have been expanded.

QA created a test personnel record, uploaded files, an analysis, a filed finding
and report exports in the designated staging test company. Rollback acceptance
fixtures did not persist. Two pre-existing staging file entries were copied into
the canonical expert library through authorized download and reinspection;
originals were retained. No customer/production data was migrated.

Acceptance sources: `scripts/isg/shared_expert_*acceptance.sql`,
`scripts/isg/run_shared_expert_acceptance.mjs`.
Architecture guard: `scripts/isg/osgb_expert_navigation_guard.test.mjs`.
