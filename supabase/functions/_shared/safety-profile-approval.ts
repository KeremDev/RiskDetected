export type SafetyProfileApprovalRecord = {
  sourceSHA256: string;
  languageApprovalSHA256: string;
  safetyApprovalSHA256: string;
  productApprovalSHA256: string;
  internalReviewID: string;
};

// This record is intentionally independent from generated profile output.
// It may only be populated after the exact source hash receives all three
// human approvals described by the safety-profile review contract.
export const SAFETY_PROFILE_APPROVAL_RECORD:
  | SafetyProfileApprovalRecord
  | null = {
    sourceSHA256:
      "3a68229b1860572ff70600287412d3dadf890597698acfc3edb23afc8b9c6932",
    languageApprovalSHA256:
      "bcc921a5e9c2872ed9f8ec59568319584d3c5c6b97f2e69b08984e1f51d788b5",
    safetyApprovalSHA256:
      "53c686b04331abebf2e4b466d1f4a70403f652a2808b63c35b01c0cdd0e220e8",
    productApprovalSHA256:
      "9d340c9e2b7c9969825ca7c8b13dba36d846ff978d29f79e867a90a0f8f0f3a3",
    internalReviewID: "RD-SPR-20260801-3A68229B",
  };

const SHA256_PATTERN = /^[0-9a-f]{64}$/;

export function approvedSafetyProfileSourceSHA256(): string | null {
  const record = SAFETY_PROFILE_APPROVAL_RECORD;
  if (
    record == null ||
    !SHA256_PATTERN.test(record.sourceSHA256) ||
    !SHA256_PATTERN.test(record.languageApprovalSHA256) ||
    !SHA256_PATTERN.test(record.safetyApprovalSHA256) ||
    !SHA256_PATTERN.test(record.productApprovalSHA256) ||
    record.internalReviewID.trim().length === 0
  ) {
    return null;
  }
  return record.sourceSHA256;
}
