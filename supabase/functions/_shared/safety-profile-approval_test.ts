import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  approvedSafetyProfileSourceSHA256,
  SAFETY_PROFILE_APPROVAL_RECORD,
} from "./safety-profile-approval.ts";
import { safetyProfileSourceSHA256 } from "./safety-profile-manifest.ts";

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
