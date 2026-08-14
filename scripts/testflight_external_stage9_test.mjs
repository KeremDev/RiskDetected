import assert from "node:assert/strict";
import test from "node:test";
import {
  sanitizeStage9State,
  stage9SequenceReady,
} from "./testflight_external_stage9.mjs";

function manifest(completed = 8) {
  return {
    schema_version: 1,
    status: "hold",
    completed_stages: completed,
    required_stages: 9,
    next_stage: completed + 1,
    issues: [],
  };
}

const privateTester = {
  type: "betaTesters",
  id: "private-tester-id",
  attributes: {
    firstName: "Private",
    lastName: "Tester",
    email: "private@example.invalid",
    state: "INSTALLED",
  },
};

test("stage 9 is sequence-locked behind eight passed stages", () => {
  assert.equal(stage9SequenceReady(manifest(7)), false);
  assert.equal(stage9SequenceReady(manifest(8)), true);
});

test("sanitized status drops all tester personal fields", () => {
  const evidence = sanitizeStage9State({
    manifest: manifest(7),
    groupsPayload: {
      data: [{
        id: "private-group-id",
        attributes: {
          name: "Internal Testers",
          isInternalGroup: true,
        },
      }],
    },
    testersPayload: { data: [privateTester] },
    submissionsPayload: { data: [] },
    distributionPayload: {
      data: [{
        attributes: {
          externalBuildState: "READY_FOR_BETA_SUBMISSION",
        },
      }],
    },
    operation: "status",
  });
  assert.equal(evidence.status, "hold_prior_stages_incomplete");
  assert.equal(evidence.testers.total_count, 1);
  assert.deepEqual(evidence.testers.state_counts, { INSTALLED: 1 });
  assert.doesNotMatch(
    JSON.stringify(evidence),
    /private@example\.invalid|Private|private-tester-id|private-group-id/u,
  );
});

test("stage 9 readiness requires target group and beta submission", () => {
  const evidence = sanitizeStage9State({
    manifest: manifest(8),
    groupsPayload: {
      data: [{
        attributes: {
          name: "RiskDetected 1.3.0 External Review Candidate",
          isInternalGroup: false,
        },
      }],
    },
    testersPayload: { data: [privateTester] },
    submissionsPayload: {
      data: [{
        attributes: { betaReviewState: "WAITING_FOR_REVIEW" },
      }],
    },
    distributionPayload: {
      data: [{
        attributes: { externalBuildState: "WAITING_FOR_BETA_REVIEW" },
      }],
    },
    operation: "prepare",
  });
  assert.equal(evidence.status, "stage9_external_candidate_ready");
  assert.equal(evidence.safety.app_store_review_submitted, false);
  assert.equal(evidence.safety.app_store_release_performed, false);
});
