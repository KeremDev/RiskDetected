#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import path from "node:path";

const PROJECT_REF = "ppcrzemgiztzcgddbins";
const SUPABASE_URL = `https://${PROJECT_REF}.supabase.co`;
const PUBLISHABLE_KEY = process.env.RISKDETECTED_CANARY_PUBLISHABLE_KEY ??
  "sb_publishable_cUQq5Lv-zDF1hXqwnmAj1A_LTdk9FJt";

function arg(name, fallback = null) {
  const prefix = `--${name}=`;
  return process.argv.find((value) => value.startsWith(prefix))?.slice(prefix.length) ?? fallback;
}

function requireArg(name) {
  const value = arg(name);
  if (!value) throw new Error(`Missing --${name}=...`);
  return value;
}

function canaryPassword() {
  const value = process.env.RISKDETECTED_CANARY_PASSWORD ?? arg("password");
  if (!value) {
    throw new Error("Set RISKDETECTED_CANARY_PASSWORD or pass --password=...");
  }
  return value;
}

function assertProductionConfirmation() {
  if (arg("confirm-production") !== PROJECT_REF) {
    throw new Error(`Refusing production mutation without --confirm-production=${PROJECT_REF}`);
  }
}

async function request(endpoint, { token, method = "GET", json, bytes, headers = {} } = {}) {
  const response = await fetch(`${SUPABASE_URL}${endpoint}`, {
    method,
    headers: {
      apikey: PUBLISHABLE_KEY,
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(json !== undefined ? { "Content-Type": "application/json" } : {}),
      ...headers,
    },
    body: json !== undefined ? JSON.stringify(json) : bytes,
  });
  const text = await response.text();
  let body = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = text;
  }
  if (!response.ok) {
    const error = new Error(`${method} ${endpoint} failed (${response.status}): ${text.slice(0, 800)}`);
    error.status = response.status;
    error.body = body;
    throw error;
  }
  return { status: response.status, body };
}

async function passwordSession(email, password) {
  const result = await request("/auth/v1/token?grant_type=password", {
    method: "POST",
    json: { email, password },
  });
  const token = result.body?.access_token;
  const userID = result.body?.user?.id;
  if (!token || !userID) throw new Error("Password session did not return a token and user id.");
  return { token, userID };
}

async function signup() {
  assertProductionConfirmation();
  const email = requireArg("email");
  const password = canaryPassword();
  const result = await request("/auth/v1/signup", {
    method: "POST",
    json: {
      email,
      password,
      data: {
        full_name: "RiskDetected Production Canary",
        app_language: "tr",
        preferred_content_locale: "tr-TR",
        work_jurisdiction_country: "TR",
        safety_profile_id: "tr-tr-current-v1",
        safety_profile_version: 1,
        preferred_method: "fine_kinney",
        qa_canary: true,
      },
    },
  });
  const userID = result.body?.user?.id ?? result.body?.id;
  if (!userID) throw new Error("Signup did not return a user id.");
  console.log(JSON.stringify({ phase: "signup", status: result.status, user_id: userID, email }));
}

function encodedObjectPath(value) {
  return value.split("/").map(encodeURIComponent).join("/");
}

async function createAndRunAnalysis() {
  assertProductionConfirmation();
  const email = requireArg("email");
  const password = canaryPassword();
  const imagePath = path.resolve(requireArg("image"));
  const label = arg("label", "production-ios-analysis-canary");
  const expectedRoute = arg("expect-route");
  const expectedPool = arg("expect-pool");
  const { token, userID } = await passwordSession(email, password);
  const analysisID = crypto.randomUUID();
  const photoID = crypto.randomUUID();
  const storagePath = `${userID}/${analysisID}/p1.jpg`;
  const image = await readFile(imagePath);

  const analysisInsert = await request("/rest/v1/analyses", {
    token,
    method: "POST",
    headers: { Prefer: "return=representation" },
    json: {
      id: analysisID,
      user_id: userID,
      kind: "photo",
      canvas: "general",
      title: `QA ${label}`,
      status: "pending",
      analysis_sector: "general",
      analysis_sector_source: "user_selected",
      analysis_sector_prompt_version: "active-sector-v1",
      primary_method: "fine_kinney",
    },
  });
  if (!Array.isArray(analysisInsert.body) || analysisInsert.body[0]?.id !== analysisID) {
    throw new Error("Analysis insert did not return the expected id.");
  }

  await request(`/storage/v1/object/photos/${encodedObjectPath(storagePath)}`, {
    token,
    method: "POST",
    bytes: image,
    headers: { "Content-Type": "image/jpeg", "x-upsert": "true" },
  });

  await request("/rest/v1/photos", {
    token,
    method: "POST",
    headers: { Prefer: "return=minimal" },
    json: {
      analysis_id: analysisID,
      user_id: userID,
      storage_path: storagePath,
      width: Number(arg("width", "1024")),
      height: Number(arg("height", "682")),
      size_bytes: image.byteLength,
      byte_size: image.byteLength,
      mime_type: "image/jpeg",
      sequence_index: 1,
      client_photo_id: photoID,
      is_primary: true,
      upload_payload_version: "photo-batch-storage-v1",
      compression_metadata: {
        jpeg_quality: 0.78,
        quality_policy: "production-canary-v1",
        max_dimension: 1024,
        encoded_byte_count: Math.ceil(image.byteLength / 3) * 4,
        storage_strategy: "client-storage-paths-v1",
      },
    },
  });

  const invoke = await request("/functions/v1/analyze", {
    token,
    method: "POST",
    json: {
      analysis_id: analysisID,
      canvas: "general",
      canvases: ["general"],
      analysis_mode: "standard",
      text_input: null,
      request_id: crypto.randomUUID(),
      support_id: `QA-IOS-${crypto.randomUUID()}`,
      company_id: null,
      analysis_sector: "general",
      analysis_sector_source: "user_selected",
      analysis_sector_prompt_version: "active-sector-v1",
      app_language: "tr",
      output_language: "tr",
      output_locale: "tr-TR",
      work_jurisdiction_country: "TR",
      work_jurisdiction_region: null,
      safety_profile_id: "tr-tr-current-v1",
      safety_profile_version: 1,
      method: "fine_kinney",
      photo_paths: [storagePath],
      photo_base64_parts: [],
      client_app_version: "1.3.1",
      client_app_build: "81",
      client_platform: "ios",
      api_contract_version: 2,
      client_capabilities: {
        multi_photo_analysis: true,
        multi_photo_coverage_v2: true,
        editable_findings: true,
        report_snapshot_v2: true,
        global_localization_wave1: false,
      },
    },
  });
  console.log(JSON.stringify({ phase: "queued", analysis_id: analysisID, invoke_status: invoke.status }));

  const deadline = Date.now() + Number(arg("timeout-ms", "360000"));
  let analysis = null;
  let usage = null;
  while (Date.now() < deadline) {
    const analysisResult = await request(
      `/rest/v1/analyses?id=eq.${analysisID}&select=status,status_message,failure_code,finding_count,raw_ai_response`,
      { token },
    );
    analysis = Array.isArray(analysisResult.body) ? analysisResult.body[0] : null;
    const usageResult = await request(
      `/rest/v1/ai_usage_logs?analysis_id=eq.${analysisID}&select=user_plan,quality_tier,ai_execution_route,provider,model,api_key_alias,fallback_source,http_status,error,error_code&order=created_at.asc`,
      { token },
    );
    const rows = Array.isArray(usageResult.body) ? usageResult.body : [];
    usage = rows.at(-1) ?? null;
    if (analysis?.status === "completed" && usage) break;
    if (analysis?.status === "failed") break;
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }

  const inputAudit = analysis?.raw_ai_response?._input_audit ?? null;
  const actualRoute = usage?.ai_execution_route ?? inputAudit?.ai_execution_route ?? null;
  const apiKeyAlias = usage?.api_key_alias ?? null;
  const inferredPool = typeof apiKeyAlias === "string" && apiKeyAlias.includes("_paid_")
    ? "paid"
    : typeof apiKeyAlias === "string" && apiKeyAlias.startsWith("gemini_")
    ? "free"
    : null;
  const actualPool = inputAudit?.gemini_pool ?? inputAudit?.expected_gemini_pool ?? inferredPool;
  const result = {
    phase: "analysis",
    label,
    user_id: userID,
    analysis_id: analysisID,
    storage_path: storagePath,
    status: analysis?.status ?? null,
    failure_code: analysis?.failure_code ?? null,
    finding_count: analysis?.finding_count ?? null,
    route: actualRoute,
    pool: actualPool,
    quality_tier: usage?.quality_tier ?? inputAudit?.quality_tier ?? null,
    provider: usage?.provider ?? null,
    model: usage?.model ?? null,
    api_key_alias: apiKeyAlias,
    http_status: usage?.http_status ?? null,
    error_code: usage?.error_code ?? null,
  };
  console.log(JSON.stringify(result));
  if (result.status !== "completed") throw new Error(`Analysis did not complete: ${JSON.stringify(result)}`);
  if (expectedRoute && result.route !== expectedRoute) {
    throw new Error(`Expected route ${expectedRoute}, got ${result.route ?? "null"}.`);
  }
  if (expectedPool && result.pool !== expectedPool) {
    throw new Error(`Expected pool ${expectedPool}, got ${result.pool ?? "null"}.`);
  }
}

async function cleanupStorage() {
  assertProductionConfirmation();
  const email = requireArg("email");
  const password = canaryPassword();
  const { token, userID } = await passwordSession(email, password);
  const photos = await request(
    `/rest/v1/photos?user_id=eq.${userID}&select=storage_path`,
    { token },
  );
  const paths = Array.isArray(photos.body)
    ? photos.body.map((row) => row.storage_path).filter(Boolean)
    : [];
  const extraPath = arg("extra-path");
  const cleanupPaths = [...new Set([...paths, ...(extraPath ? [extraPath] : [])])];
  for (const storagePath of cleanupPaths) {
    await request(`/storage/v1/object/photos/${encodedObjectPath(storagePath)}`, {
      token,
      method: "DELETE",
    });
  }
  console.log(JSON.stringify({ phase: "cleanup-storage", user_id: userID, removed_objects: cleanupPaths.length }));
}

const command = process.argv[2];
if (command === "signup") await signup();
else if (command === "analyze") await createAndRunAnalysis();
else if (command === "cleanup-storage") await cleanupStorage();
else throw new Error("Usage: production_ios_analysis_canary.mjs <signup|analyze|cleanup-storage> ...");
