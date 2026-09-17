export interface IsgWorkspaceContext {
  schema_version: 1;
  workspace_id: string;
  kind: "personal" | "osgb";
  name: string;
  status: "active" | "pending_purchase" | "admin_trial" | "admin_sponsored" | "suspended" | "archived";
  timezone: string;
  workspace_version: number;
  membership: {
    membership_id: string; user_id: string; role: "owner" | "admin" | "expert";
    status: "active" | "suspended" | "ended"; is_practicing_expert: boolean;
    permission_revision: number; membership_version: number;
  };
  can_read: boolean; can_operate: boolean; can_manage_members: boolean; can_manage_billing: boolean;
}

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const top = ["schema_version","workspace_id","kind","name","status","timezone","workspace_version","membership","can_read","can_operate","can_manage_members","can_manage_billing"];
const member = ["membership_id","user_id","role","status","is_practicing_expert","permission_revision","membership_version"];
const record = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v);
const exact = (v: Record<string, unknown>, keys: string[]) => Object.keys(v).length === keys.length && Object.keys(v).every(k => keys.includes(k));
const safe = (v: unknown): v is number => Number.isSafeInteger(v) && (v as number) >= 0;

export function parseIsgWorkspaceContext(input: unknown): {ok: true; value: IsgWorkspaceContext} | {ok: false; error: "VALIDATION_ERROR"} {
  const fail = {ok:false,error:"VALIDATION_ERROR"} as const;
  if (!record(input) || !exact(input,top) || input.schema_version !== 1 || typeof input.workspace_id !== "string" || !uuid.test(input.workspace_id) ||
      (input.kind !== "personal" && input.kind !== "osgb") || typeof input.name !== "string" || !input.name.trim() || new TextEncoder().encode(input.name).length > 200 ||
      typeof input.timezone !== "string" || !input.timezone || new TextEncoder().encode(input.timezone).length > 80 || !safe(input.workspace_version) || !record(input.membership)) return fail;
  const m=input.membership;
  if (!exact(m,member) || typeof m.membership_id !== "string" || !uuid.test(m.membership_id) || typeof m.user_id !== "string" || !uuid.test(m.user_id) ||
      !["owner","admin","expert"].includes(m.role as string) || !["active","suspended","ended"].includes(m.status as string) || typeof m.is_practicing_expert !== "boolean" ||
      !safe(m.permission_revision) || !safe(m.membership_version) || !["active","pending_purchase","admin_trial","admin_sponsored","suspended","archived"].includes(input.status as string) ||
      typeof input.can_read !== "boolean" || typeof input.can_operate !== "boolean" || typeof input.can_manage_members !== "boolean" || typeof input.can_manage_billing !== "boolean") return fail;
  const readable=m.status==="active" && ["active","pending_purchase","admin_trial","admin_sponsored"].includes(input.status as string);
  const operable=m.status==="active" && ["active","admin_trial","admin_sponsored"].includes(input.status as string);
  if (m.is_practicing_expert && (input.kind!=="osgb" || m.status!=="active") || input.kind==="personal" && (m.role!=="owner" || m.status!=="active" || m.is_practicing_expert) ||
      input.can_read!==readable || input.can_operate!==operable || input.can_manage_members!==(readable && ["owner","admin"].includes(m.role as string)) ||
      input.can_manage_billing!==(readable && m.role==="owner")) return fail;
  return {ok:true,value:structuredClone(input) as IsgWorkspaceContext};
}
