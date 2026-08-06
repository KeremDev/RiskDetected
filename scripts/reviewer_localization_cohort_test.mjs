import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  materializeOperation,
  reviewDemoAccountName,
  reviewerActivationSequenceAllowed,
  reviewerStatusSQL,
  sanitizeReviewerStatus,
} from "./reviewer_localization_cohort.mjs";

const syntheticEmail = "synthetic-review@example.invalid";

test("review details parser requires a configured demo account", () => {
  assert.equal(reviewDemoAccountName(JSON.stringify({
    data: {
      attributes: {
        demoAccountRequired: true,
        demoAccountName: syntheticEmail,
      },
    },
  })), syntheticEmail);
  assert.throws(
    () => reviewDemoAccountName(JSON.stringify({
      data: {
        attributes: {
          demoAccountRequired: false,
          demoAccountName: syntheticEmail,
        },
      },
    })),
    /valid required demo account/u,
  );
});

test("status SQL uses only the synthetic fixture during unit tests", () => {
  const sql = reviewerStatusSQL(syntheticEmail);
  assert.match(sql, /matching_auth_user_count/u);
  assert.match(sql, /synthetic-review@example\.invalid/u);
  assert.doesNotMatch(sql, /select\s+email|select\s+id/u);
});

test("psql operation is materialized without meta commands or placeholders", () => {
  const source = readFileSync(
    "supabase/operations/enable_global_localization_reviewer_cohort.sql",
    "utf8",
  );
  const rendered = materializeOperation(source, syntheticEmail);
  assert.doesNotMatch(rendered, /\\set|\\if|\\echo|:'reviewer_email'/u);
  assert.match(rendered, /synthetic-review@example\.invalid/u);
  assert.match(rendered, /begin;/u);
  assert.match(rendered, /commit;/u);
});

test("aggregate status distinguishes off and reviewer-only active states", () => {
  const base = {
    matching_auth_user_count: 1,
    flag_count: 13,
    enabled_ios_build_entry_count: 0,
    kill_switch_true_count: 0,
  };
  const off = sanitizeReviewerStatus({
    ...base,
    off_count: 13,
    allowlist_count: 0,
    enabled_user_hash_entry_count: 0,
  }, "status");
  assert.equal(off.state, "ready_for_authorized_activation");
  const active = sanitizeReviewerStatus({
    ...base,
    off_count: 0,
    allowlist_count: 13,
    enabled_user_hash_entry_count: 13,
  }, "activate");
  assert.equal(active.state, "reviewer_only_allowlist_active");
  assert.equal(JSON.stringify(active).includes(syntheticEmail), false);
});

test("activation is sequence-locked until stage 1 passes", () => {
  const base = {
    schema_version: 1,
    status: "hold",
    required_stages: 9,
    issues: [],
  };
  assert.equal(reviewerActivationSequenceAllowed({
    ...base,
    completed_stages: 0,
    next_stage: 1,
  }), false);
  assert.equal(reviewerActivationSequenceAllowed({
    ...base,
    completed_stages: 1,
    next_stage: 2,
  }), true);
  assert.equal(reviewerActivationSequenceAllowed({
    ...base,
    status: "passed",
    completed_stages: 9,
    next_stage: null,
  }), true);
});
