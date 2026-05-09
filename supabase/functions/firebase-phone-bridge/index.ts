/**
 * firebase-phone-bridge
 *
 * Verifies a Firebase Phone Auth ID token, creates/links a Supabase Auth user,
 * then returns short-lived Supabase password credentials for the iOS app to
 * exchange with normal Supabase email/password sign-in.
 *
 * Deploy with JWT verification disabled because callers do not have a
 * Supabase session yet:
 *   supabase functions deploy firebase-phone-bridge --no-verify-jwt
 *
 * Required secrets:
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *   FIREBASE_PROJECT_ID
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type FirebaseClaims = {
  aud: string;
  exp: number;
  iat: number;
  iss: string;
  sub: string;
  phone_number?: string;
  firebase?: {
    sign_in_provider?: string;
  };
};

type JWKS = {
  keys: FirebaseJWK[];
};

type FirebaseJWK = JsonWebKey & {
  kid?: string;
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function base64URLToBytes(input: string): Uint8Array {
  const normalized = input.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(
    normalized.length + (4 - normalized.length % 4) % 4,
    "=",
  );
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function decodeJSONPart<T>(part: string): T {
  const text = new TextDecoder().decode(base64URLToBytes(part));
  return JSON.parse(text) as T;
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

async function verifyFirebaseIDToken(
  idToken: string,
  projectID: string,
): Promise<FirebaseClaims> {
  const parts = idToken.split(".");
  if (parts.length !== 3) {
    throw new Error("invalid_token_format");
  }

  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const header = decodeJSONPart<{ alg?: string; kid?: string }>(encodedHeader);
  const payload = decodeJSONPart<FirebaseClaims>(encodedPayload);

  if (header.alg !== "RS256" || !header.kid) {
    throw new Error("invalid_token_header");
  }

  const jwksResponse = await fetch(
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
  );
  if (!jwksResponse.ok) {
    throw new Error("firebase_jwks_unavailable");
  }

  const jwks = await jwksResponse.json() as JWKS;
  const jwk = jwks.keys.find((key) => key.kid === header.kid);
  if (!jwk) {
    throw new Error("firebase_jwk_not_found");
  }

  const key = await crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );

  const signedData = new TextEncoder().encode(
    `${encodedHeader}.${encodedPayload}`,
  );
  const signature = base64URLToBytes(encodedSignature);
  const validSignature = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    toArrayBuffer(signature),
    toArrayBuffer(signedData),
  );
  if (!validSignature) {
    throw new Error("invalid_token_signature");
  }

  const now = Math.floor(Date.now() / 1000);
  const expectedIssuer = `https://securetoken.google.com/${projectID}`;

  if (payload.aud !== projectID) throw new Error("invalid_token_audience");
  if (payload.iss !== expectedIssuer) throw new Error("invalid_token_issuer");
  if (!payload.sub || payload.sub.length > 128) {
    throw new Error("invalid_token_subject");
  }
  if (payload.exp <= now) throw new Error("expired_token");
  if (payload.iat > now + 60) throw new Error("invalid_token_iat");
  if (!payload.phone_number) throw new Error("missing_phone_number");
  if (payload.firebase?.sign_in_provider !== "phone") {
    throw new Error("not_phone_provider");
  }

  return payload;
}

function makeBridgeEmail(firebaseUID: string): string {
  const safeUID = firebaseUID.toLowerCase().replace(/[^a-z0-9._-]/g, "-");
  return `phone-${safeUID}@firebase.riskdetected.local`;
}

function makePassword(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes).map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function findUserByPhone(supabase: any, phone: string) {
  for (let page = 1; page <= 20; page += 1) {
    const { data, error } = await supabase.auth.admin.listUsers({
      page,
      perPage: 1000,
    });
    if (error) throw error;
    const user = data.users.find((candidate: { phone?: string }) =>
      candidate.phone === phone
    );
    if (user) return user;
    if (data.users.length < 1000) return null;
  }
  return null;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const firebaseProjectID = Deno.env.get("FIREBASE_PROJECT_ID");

  if (!supabaseUrl || !serviceRoleKey || !firebaseProjectID) {
    return json(500, { error: "Firebase phone bridge is not configured" });
  }

  let idToken = "";
  try {
    const body = await req.json();
    idToken = String(body.id_token ?? "");
  } catch {
    return json(400, { error: "Invalid JSON body" });
  }

  if (!idToken) {
    return json(400, { error: "id_token is required" });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const claims = await verifyFirebaseIDToken(idToken, firebaseProjectID);
    const firebaseUID = claims.sub;
    const phone = claims.phone_number!;
    const email = makeBridgeEmail(firebaseUID);
    const password = makePassword();
    const now = new Date().toISOString();

    const { data: existingLink, error: linkError } = await supabase
      .from("firebase_phone_auth_links")
      .select("supabase_user_id")
      .eq("firebase_project_id", firebaseProjectID)
      .eq("firebase_uid", firebaseUID)
      .maybeSingle();

    if (linkError) throw linkError;

    let userID = existingLink?.supabase_user_id as string | undefined;
    let createdUser = false;

    if (!userID) {
      const existingPhoneUser = await findUserByPhone(supabase, phone);
      if (existingPhoneUser) {
        userID = existingPhoneUser.id;
      } else {
        const { data: created, error: createError } = await supabase.auth.admin
          .createUser({
            email,
            password,
            email_confirm: true,
            phone,
            phone_confirm: true,
            user_metadata: {
              auth_provider: "firebase_phone",
              firebase_uid: firebaseUID,
            },
          });
        if (createError) throw createError;
        if (!created.user) throw new Error("supabase_user_not_created");
        userID = created.user.id;
        createdUser = true;
      }

      const { error: upsertLinkError } = await supabase
        .from("firebase_phone_auth_links")
        .upsert({
          firebase_project_id: firebaseProjectID,
          firebase_uid: firebaseUID,
          supabase_user_id: userID,
          phone,
          last_sign_in_at: now,
          updated_at: now,
        }, { onConflict: "firebase_project_id,firebase_uid" });
      if (upsertLinkError) throw upsertLinkError;
    }

    if (!userID) throw new Error("supabase_user_not_resolved");

    const { error: updateUserError } = await supabase.auth.admin.updateUserById(
      userID,
      {
        email,
        password,
        email_confirm: true,
        phone,
        phone_confirm: true,
        user_metadata: {
          auth_provider: "firebase_phone",
          firebase_uid: firebaseUID,
        },
      },
    );
    if (updateUserError) throw updateUserError;

    await supabase
      .from("profiles")
      .upsert({
        id: userID,
        email,
        phone,
        full_name: "Telefon Kullanıcısı",
        initials: "TK",
        tier: "free",
      }, { onConflict: "id", ignoreDuplicates: true });

    await supabase
      .from("firebase_phone_auth_links")
      .update({ last_sign_in_at: now, updated_at: now, phone })
      .eq("firebase_project_id", firebaseProjectID)
      .eq("firebase_uid", firebaseUID);

    return json(200, {
      email,
      password,
      user_id: userID,
      phone,
      created_user: createdUser,
    });
  } catch (error) {
    console.error("Firebase phone bridge error", error);
    return json(401, {
      error: "Firebase phone verification failed",
      code: error instanceof Error ? error.message : "unknown_error",
    });
  }
});
