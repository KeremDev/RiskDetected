#!/usr/bin/env node
// Verifies the Apple Ads Platform API credentials and discovers the ad account
// the token can reach. Writes the resolved adAccountId back into
// .secrets/apple-ads-credentials.json so later scripts need no arguments.
//
// Usage: node scripts/aso/apple_ads_bootstrap.mjs

import { apiRequest, readCredentialsFile, writeCredentials } from "./_apple_ads_client.mjs";

async function main() {
  const credentials = readCredentialsFile();

  const me = await apiRequest("/me");
  console.log(`me: userId=${me?.data?.userId ?? "?"} orgId=${me?.data?.orgId ?? "?"}`);

  const acls = await apiRequest("/acls");
  const accounts = acls?.data ?? [];
  if (accounts.length === 0) {
    throw new Error("No ad accounts are visible to this token. Check the API user's role.");
  }

  for (const acl of accounts) {
    console.log(
      `acl: adAccountId=${acl.adAccountId ?? acl.orgId} name=${acl.orgName ?? "?"} ` +
        `role=${Array.isArray(acl.roleNames) ? acl.roleNames.join(",") : (acl.roleName ?? "?")}`,
    );
  }

  const resolved = accounts[0].adAccountId ?? accounts[0].orgId;
  if (accounts.length > 1) {
    console.log(`\nMultiple accounts visible; defaulting to ${resolved}. Edit the credentials file to override.`);
  }

  writeCredentials({ ...credentials, adAccountId: String(resolved) });
  console.log(`\nStored adAccountId=${resolved} in .secrets/apple-ads-credentials.json`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
