#!/usr/bin/env node
import { spawnSync } from "node:child_process";

const SERVICES = {
  supabaseAccessToken: "riskdetected_supabase_access_token",
  supabaseDBPassword: "riskdetected_supabase_db_password",
  revenueCatRestAPIKey: "riskdetected_revenuecat_rest_api_key",
};

function readKeychain(service) {
  const result = spawnSync(
    "security",
    ["find-generic-password", "-a", process.env.USER ?? "", "-s", service, "-w"],
    { encoding: "utf8" },
  );
  if (result.status !== 0) return null;
  return result.stdout.trim() || null;
}

function status() {
  const rows = Object.entries(SERVICES).map(([name, service]) => ({
    name,
    service,
    present: Boolean(readKeychain(service)),
  }));

  for (const row of rows) {
    console.log(`${row.present ? "PASS" : "MISSING"} ${row.name} (${row.service})`);
  }

  return rows.every((row) => row.present) ? 0 : 1;
}

function supabase(args) {
  const token = readKeychain(SERVICES.supabaseAccessToken);
  const dbPassword = readKeychain(SERVICES.supabaseDBPassword);
  if (!token || !dbPassword) {
    console.error("Missing Supabase Keychain credentials. Run `node scripts/rd_ops_env.mjs status`.");
    return 1;
  }

  const result = spawnSync("supabase", args, {
    stdio: "inherit",
    env: {
      ...process.env,
      SUPABASE_ACCESS_TOKEN: token,
      SUPABASE_DB_PASSWORD: dbPassword,
    },
  });
  return result.status ?? 1;
}

function revenueCatDelete(appUserID) {
  const key = readKeychain(SERVICES.revenueCatRestAPIKey);
  if (!key) {
    console.error("Missing RevenueCat Keychain credential. Run `node scripts/rd_ops_env.mjs status`.");
    return 1;
  }
  if (!appUserID) {
    console.error("Usage: node scripts/rd_ops_env.mjs revenuecat-delete-user <app_user_id>");
    return 1;
  }
  if (/[\r\n]/.test(key)) {
    console.error("RevenueCat Keychain credential contains invalid line breaks.");
    return 1;
  }

  const curlConfigEscapedKey = key
    .replaceAll("\\", "\\\\")
    .replaceAll('"', '\\"');
  const curlConfig =
    `header = "Authorization: Bearer ${curlConfigEscapedKey}"\n`;

  const response = spawnSync(
    "curl",
    [
      "--config",
      "-",
      "--silent",
      "--show-error",
      "--fail-with-body",
      "--request",
      "DELETE",
      "--url",
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserID)}`,
      "--header",
      "Accept: application/json",
      "--header",
      "Content-Type: application/json",
    ],
    {
      encoding: "utf8",
      input: curlConfig,
    },
  );

  if (response.status === 0) {
    console.log(`deleted ${appUserID}`);
    return 0;
  }

  console.error(`failed ${appUserID}: ${response.stderr.trim() || response.stdout.trim()}`);
  return response.status ?? 1;
}

function usage() {
  console.log(`Usage:
  node scripts/rd_ops_env.mjs status
  node scripts/rd_ops_env.mjs supabase <supabase args...>
  node scripts/rd_ops_env.mjs revenuecat-delete-user <app_user_id>`);
}

const [command, ...args] = process.argv.slice(2);
let exitCode = 0;

switch (command) {
  case "status":
    exitCode = status();
    break;
  case "supabase":
    exitCode = supabase(args);
    break;
  case "revenuecat-delete-user":
    exitCode = revenueCatDelete(args[0]);
    break;
  default:
    usage();
    exitCode = 1;
}

process.exit(exitCode);
