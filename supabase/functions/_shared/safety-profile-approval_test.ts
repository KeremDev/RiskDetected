import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  approvedSafetyProfileSourceSHA256,
  SAFETY_PROFILE_APPROVAL_RECORD,
} from "./safety-profile-approval.ts";
import { safetyProfileSourceSHA256 } from "./safety-profile-manifest.ts";
import { safetyProfiles as approvedSafetyProfiles } from "./approved-safety-profiles.generated.ts";
import {
  safetyProfiles as draftSafetyProfiles,
  safetyProfileSourceSHA256 as draftSafetyProfileSourceSHA256,
} from "./generated/safety-profiles.generated.ts";

Deno.test("exact-hash safety profile approval covers language, safety and product", () => {
  assertEquals(
    SAFETY_PROFILE_APPROVAL_RECORD?.sourceSHA256,
    safetyProfileSourceSHA256,
  );
  assertEquals(
    approvedSafetyProfileSourceSHA256(),
    safetyProfileSourceSHA256,
  );
  assertEquals(
    SAFETY_PROFILE_APPROVAL_RECORD?.internalReviewID,
    "RD-SPR-20260801-3A68229B",
  );
  assertEquals(
    SAFETY_PROFILE_APPROVAL_RECORD?.languageApprovalSHA256,
    "bcc921a5e9c2872ed9f8ec59568319584d3c5c6b97f2e69b08984e1f51d788b5",
  );
  assertEquals(
    SAFETY_PROFILE_APPROVAL_RECORD?.safetyApprovalSHA256,
    "53c686b04331abebf2e4b466d1f4a70403f652a2808b63c35b01c0cdd0e220e8",
  );
  assertEquals(
    SAFETY_PROFILE_APPROVAL_RECORD?.productApprovalSHA256,
    "9d340c9e2b7c9969825ca7c8b13dba36d846ff978d29f79e867a90a0f8f0f3a3",
  );
});

Deno.test("runtime stays on the sealed approved profile artifact", () => {
  assertEquals(
    safetyProfileSourceSHA256,
    "3a68229b1860572ff70600287412d3dadf890597698acfc3edb23afc8b9c6932",
  );
  assertEquals(
    draftSafetyProfileSourceSHA256,
    "ae72ae29ac4ed47d6ffbd7aa37dba426e44647066fe70d93d1021e8eefa54ad3",
  );
  assertEquals(approvedSafetyProfiles, draftSafetyProfiles);
});
