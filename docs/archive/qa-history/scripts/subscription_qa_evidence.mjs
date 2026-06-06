#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

const SERVICES = {
  supabaseAccessToken: "riskdetected_supabase_access_token",
  supabaseDBPassword: "riskdetected_supabase_db_password",
  revenueCatRestAPIKey: "riskdetected_revenuecat_rest_api_key",
};

function usage() {
  console.log(`Usage:
  node scripts/subscription_qa_evidence.mjs --email <email> --environment <env> --scenario <id> [--output <file>]
  node scripts/subscription_qa_evidence.mjs --user-id <uuid> --environment <env> --scenario <id> [--db-url <postgres-url>]

Examples:
  node scripts/subscription_qa_evidence.mjs --email test@example.com --environment apple_sandbox --scenario A1
  SUPABASE_DB_URL="postgresql://..." REVENUECAT_REST_API_KEY="..." node scripts/subscription_qa_evidence.mjs --email qa@example.com --environment revenuecat_test_store --scenario B1`);
}

function parseArgs() {
  const args = process.argv.slice(2);
  const parsed = {
    limit: 25,
    revenueCatKeyService: SERVICES.revenueCatRestAPIKey,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--help" || arg === "-h") {
      parsed.help = true;
      continue;
    }
    if (!arg.startsWith("--")) {
      throw new Error(`Unexpected argument: ${arg}`);
    }

    const key = arg.slice(2).replaceAll("-", "_");
    const value = args[index + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for ${arg}`);
    }
    index += 1;

    switch (key) {
      case "email":
        parsed.email = value.trim().toLowerCase();
        break;
      case "user_id":
        parsed.userID = value.trim();
        break;
      case "environment":
        parsed.environment = value.trim();
        break;
      case "scenario":
        parsed.scenario = value.trim();
        break;
      case "output":
        parsed.output = value.trim();
        break;
      case "db_url":
        parsed.dbURL = value.trim();
        break;
      case "limit":
        parsed.limit = Number.parseInt(value, 10);
        break;
      case "revenuecat_key_service":
        parsed.revenueCatKeyService = value.trim();
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  parsed.dbURL ??= process.env.SUPABASE_DB_URL;
  parsed.revenueCatRestAPIKey ??= process.env.REVENUECAT_REST_API_KEY;
  return parsed;
}

function readKeychain(service) {
  const result = spawnSync(
    "security",
    ["find-generic-password", "-a", process.env.USER ?? "", "-s", service, "-w"],
    { encoding: "utf8" },
  );
  if (result.status !== 0) return null;
  return result.stdout.trim() || null;
}

function sqlString(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function sqlUUID(value) {
  return `${sqlString(value)}::uuid`;
}

function normalizeRows(payload) {
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload?.rows)) return payload.rows;
  if (Array.isArray(payload?.data)) return payload.data;
  if (Array.isArray(payload?.result)) return payload.result;
  return [];
}

function parseSupabaseJSON(stdout) {
  const text = stdout.trim();
  if (!text) return [];
  try {
    return normalizeRows(JSON.parse(text));
  } catch (error) {
    throw new Error(`Could not parse Supabase JSON output: ${error.message}\n${text.slice(0, 500)}`);
  }
}

function supabaseQuery(sql, options) {
  const args = ["db", "query", "--output", "json"];
  if (options.dbURL) {
    args.push("--db-url", options.dbURL);
  } else {
    args.push("--linked");
  }
  args.push(sql);

  const env = { ...process.env };
  if (!options.dbURL) {
    const accessToken = readKeychain(SERVICES.supabaseAccessToken);
    const dbPassword = readKeychain(SERVICES.supabaseDBPassword);
    if (accessToken) env.SUPABASE_ACCESS_TOKEN = accessToken;
    if (dbPassword) env.SUPABASE_DB_PASSWORD = dbPassword;
  }

  const result = spawnSync("supabase", args, {
    encoding: "utf8",
    env,
    maxBuffer: 1024 * 1024 * 12,
  });

  if (result.status !== 0) {
    throw new Error(result.stderr.trim() || result.stdout.trim() || "Supabase query failed");
  }

  return parseSupabaseJSON(result.stdout);
}

function userWhereClause({ email, userID }) {
  const clauses = [];
  if (email) clauses.push(`lower(u.email) = lower(${sqlString(email)})`);
  if (userID) clauses.push(`u.id = ${sqlUUID(userID)}`);
  return clauses.join(" or ");
}

function findUsers(options) {
  const sql = `
select
  u.id::text as user_id,
  u.email,
  u.created_at::text as auth_created_at,
  p.tier as profile_tier,
  p.created_at::text as profile_created_at,
  p.updated_at::text as profile_updated_at,
  us.tier as subscription_tier,
  us.status as subscription_status,
  us.source as subscription_source,
  us.revenuecat_app_user_id,
  us.entitlement_id,
  us.entitlement_ids,
  us.product_id,
  us.environment,
  us.current_period_ends_at::text as current_period_ends_at,
  us.last_event_id,
  us.updated_at::text as subscription_updated_at
from auth.users u
left join public.profiles p on p.id = u.id
left join public.user_subscriptions us on us.user_id = u.id
where ${userWhereClause(options)}
order by u.created_at desc
limit 10;
`;
  return supabaseQuery(sql, options);
}

function boundedLimit(options) {
  return Number.isFinite(options.limit) ? Math.max(1, Math.min(options.limit, 100)) : 25;
}

function findSubscriptionEvents(userID, options) {
  if (!userID) return [];
  const sql = `
select
  event_id,
  event_type,
  app_user_id,
  user_id::text as user_id,
  product_id,
  entitlement_ids,
  environment,
  received_at::text as received_at,
  processed_at::text as processed_at,
  raw_event->>'transaction_id' as transaction_id,
  raw_event->>'original_transaction_id' as original_transaction_id,
  raw_event->>'purchased_at_ms' as purchased_at_ms,
  raw_event->>'expiration_at_ms' as expiration_at_ms,
  raw_event->'transferred_from' as transferred_from,
  raw_event->'transferred_to' as transferred_to
from public.subscription_events
where user_id = ${sqlUUID(userID)} or app_user_id = ${sqlString(userID)}
order by received_at desc
limit ${boundedLimit(options)};
`;
  return supabaseQuery(sql, options);
}

function findPaywallEvents(userID, options) {
  if (!userID) return [];
  const sql = `
select
  id::text as id,
  created_at::text as created_at,
  event_name,
  source,
  variant_id,
  selected_tier,
  billing,
  product_identifier,
  metadata
from public.paywall_events
where user_id = ${sqlUUID(userID)}
order by created_at desc
limit ${boundedLimit(options)};
`;
  return supabaseQuery(sql, options);
}

async function fetchRevenueCatSubscriber(appUserID, options) {
  if (!appUserID) return { skipped: "No Supabase user id found." };
  const apiKey = options.revenueCatRestAPIKey || readKeychain(options.revenueCatKeyService);
  if (!apiKey) return { skipped: "RevenueCat REST API key not found." };

  const response = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserID)}`, {
    headers: {
      Authorization: `Bearer ${apiKey}`,
      Accept: "application/json",
    },
  });

  const body = await response.text();
  let json = null;
  try {
    json = body ? JSON.parse(body) : null;
  } catch {
    json = { raw: body.slice(0, 1000) };
  }

  return {
    http_status: response.status,
    ok: response.ok,
    snapshot: summarizeRevenueCat(json),
  };
}

function summarizeRevenueCat(payload) {
  const subscriber = payload?.subscriber;
  if (!subscriber) return payload;

  const now = Date.now();
  const entitlements = subscriber.entitlements ?? {};
  const activeEntitlements = Object.fromEntries(
    Object.entries(entitlements).filter(([, entitlement]) => {
      if (entitlement?.expires_date === null) return true;
      const expiresAt = Date.parse(entitlement?.expires_date ?? "");
      return Number.isFinite(expiresAt) && expiresAt > now;
    }),
  );

  return {
    original_app_user_id: subscriber.original_app_user_id,
    first_seen: subscriber.first_seen,
    management_url: subscriber.management_url,
    active_entitlements: activeEntitlements,
    entitlements,
    subscriptions: subscriber.subscriptions ?? {},
  };
}

function fencedJSON(value) {
  return `\`\`\`json\n${JSON.stringify(value, null, 2)}\n\`\`\``;
}

function renderReport({ options, users, selectedUser, subscriptionEvents, paywallEvents, revenueCat }) {
  const generatedAt = new Date().toISOString();
  return `# Subscription QA Evidence

- generated_at: ${generatedAt}
- scenario: ${options.scenario}
- environment: ${options.environment}
- email: ${options.email ?? ""}
- user_id: ${options.userID ?? selectedUser?.user_id ?? ""}
- revenuecat_customer_id: ${selectedUser?.user_id ?? ""}

## Manual Evidence To Attach

- app_screenshot:
- purchase_sheet_sandbox_email:
- user_facing_message:
- support_code:
- expected_result:
- actual_result:
- status: pass/fail/blocked
- classification:

## Supabase User State

${fencedJSON(users)}

## RevenueCat Subscriber Snapshot

${fencedJSON(revenueCat)}

## Recent Subscription Events

${fencedJSON(subscriptionEvents)}

## Recent Paywall Events

${fencedJSON(paywallEvents)}
`;
}

async function main() {
  const options = parseArgs();
  if (options.help) {
    usage();
    return;
  }
  if (!options.email && !options.userID) {
    throw new Error("Provide --email or --user-id.");
  }
  if (!options.environment) {
    throw new Error("Provide --environment.");
  }
  if (!options.scenario) {
    throw new Error("Provide --scenario.");
  }

  const users = findUsers(options);
  const selectedUser = users[0] ?? null;
  const selectedUserID = selectedUser?.user_id ?? options.userID ?? null;
  const subscriptionEvents = findSubscriptionEvents(selectedUserID, options);
  const paywallEvents = findPaywallEvents(selectedUserID, options);
  const revenueCat = await fetchRevenueCatSubscriber(selectedUserID, options);
  const report = renderReport({ options, users, selectedUser, subscriptionEvents, paywallEvents, revenueCat });

  if (options.output) {
    mkdirSync(dirname(options.output), { recursive: true });
    writeFileSync(options.output, report, "utf8");
    console.log(`wrote ${options.output}`);
  } else {
    process.stdout.write(report);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
