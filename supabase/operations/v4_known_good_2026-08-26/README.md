# v4 known-good checkpoint — 2026-08-26

Single-photo analyses were verified clean at this point. Use it to get back here
if a later change makes the engine worse.

## What the checkpoint is

Three things have to match, and none of them is enough on its own:

| part | pinned at |
|---|---|
| code | git tag `v4-known-good-2026-08-26` (`61e0796`) |
| deployed function | whatever that tag deploys |
| engine config row | `private.analysis_v4_configs`, copied to an inert row |

`begin_analysis_engine_run_v4` hands the deployed function a snapshot of the
config row, and the function throws `v4_runtime_snapshot_mismatch` when the
prompt or router version in that snapshot is not the one compiled into it. So
rolling back the code without the config — or the config without the code — takes
the engine down instead of back. Order matters.

The stored copy sits in the same table with `is_active = false` and
`integrity_status = 'retired'`. `resolve_analysis_engine_route_v5` selects
`where is_active and integrity_status = 'valid'`, so the copy is invisible to the
running engine and cannot be picked by accident.

## Versions at the checkpoint

```
prompt   v4-vision-core-v5
sha256   116ac911e576c83c61810ecfc956a8f7d0a4b1bb51b16fe8a7c4ec3d1caefb2e
router   claim-routing-v11
schema   safety-claim-v4.0
tests    78 passed / 0 failed
```

Premium thinking budget 3072 single and multi; report budget 8 scored + 8
unscored.

## Rolling back

1. Check out the tag and deploy, so the running function matches the config you
   are about to restore.

   ```
   git checkout v4-known-good-2026-08-26
   supabase functions deploy analyze-v4 --project-ref ppcrzemgiztzcgddbins
   ```

2. Restore the config row.

   ```
   psql "$DATABASE_URL" -f supabase/operations/v4_known_good_2026-08-26/restore_config.sql
   ```

   It is safe to re-run and it verifies its own result.

3. Confirm the two agree before running an analysis.

   ```sql
   select prompt_version, prompt_sha256, router_version, integrity_status
   from private.analysis_v4_configs where is_active;
   ```

   The row must read `v4-vision-core-v5` / `claim-routing-v11` / `valid`, and
   `V4_PROMPT_VERSION` and `V4_ROUTER_VERSION` in
   `supabase/functions/analyze-v4/contracts.ts` must read the same. If they
   differ, the deploy in step 1 did not land — fix that before analysing, or
   every run fails at the snapshot gate.

4. Run one single-photo analysis and check the trace:

   ```sql
   select r.prompt_version, r.policy_version, t.trace->'candidate_counts'
   from private.analysis_engine_runs r
   join private.analysis_quality_trace_v4 t on t.engine_run_id = r.id
   order by r.started_at desc limit 1;
   ```

## Rolling forward again

There is nothing to undo. Land the new work as normal migrations and a deploy;
the checkpoint row is inert and stays where it is for the next time.

## What was still open at the checkpoint

Not defects in this code — recorded so the next session does not rediscover them:

- The same photograph scores `fatal` in one run and `serious` in the next. The
  router classifies what it is given and cannot recover a candidate the model
  never produced. A second verification pass (~+35% cost) is the open decision.
- `findings.confidence` is the model's own self-report averaged, and two
  engine-generated item types are hardcoded to 1.0, so the "AI güveni" figure in
  the app is not calibrated. Four provably false guardrail claims were once
  published at 100%.
- Module coverage sometimes closes `energy` as not assessable on a pressurised
  hose, where the pressure is the hazardous energy. Those items are not
  published, so no reader sees it.
