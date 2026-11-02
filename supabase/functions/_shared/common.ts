import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2";

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function fail(code: string, message: string, status = 400): Response {
  return json({ error: { code, message } }, status);
}

let _admin: SupabaseClient | null = null;
export function admin(): SupabaseClient {
  if (_admin) return _admin;
  const url = Deno.env.get("SUPABASE_URL")!;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  _admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  return _admin;
}

/** Resolve the calling user from the Authorization header. */
export async function requireUser(req: Request): Promise<User> {
  const auth = req.headers.get("Authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");
  if (!token) throw new HttpError(401, "unauthorized", "Missing token");
  const { data, error } = await admin().auth.getUser(token);
  if (error || !data.user) throw new HttpError(401, "unauthorized", "Invalid session");
  return data.user;
}

export class HttpError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

export function handler(fn: (req: Request) => Promise<Response>) {
  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    try {
      return await fn(req);
    } catch (e) {
      if (e instanceof HttpError) return fail(e.code, e.message, e.status);
      console.error(e);
      return fail("internal", e instanceof Error ? e.message : "Internal error", 500);
    }
  };
}

export async function readJson<T = Record<string, unknown>>(req: Request): Promise<T> {
  if (req.method === "GET") return {} as T;
  try {
    return (await req.json()) as T;
  } catch {
    return {} as T;
  }
}

export async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function randomToken(bytes = 32): string {
  const a = new Uint8Array(bytes);
  crypto.getRandomValues(a);
  return [...a].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function getConfig(): Promise<Record<string, any>> {
  const { data, error } = await admin().from("app_config").select("key,value");
  if (error) throw error;
  const out: Record<string, any> = {};
  for (const row of data ?? []) out[row.key] = row.value;
  return out;
}

export interface Profile {
  id: string;
  plan: "free" | "pro";
  plan_expires_at: string | null;
  role: string;
  is_banned: boolean;
  xray_uuid: string;
}

export async function getProfile(userId: string): Promise<Profile> {
  const db = admin();
  let { data } = await db.from("profiles").select("*").eq("id", userId).maybeSingle();
  if (!data) {
    // trigger may not have fired for very old users — create on demand
    const ins = await db.from("profiles").insert({ id: userId }).select("*").single();
    data = ins.data;
  }
  return data as Profile;
}

export function effectivePlan(p: Profile): "free" | "pro" {
  if (p.plan === "pro" && (!p.plan_expires_at || new Date(p.plan_expires_at) > new Date())) return "pro";
  return "free";
}

/** Ask a node agent to re-sync now so a new peer is live before the client connects. */
export async function pokeNode(ip: string | null, port: number, timeoutMs = 4000): Promise<boolean> {
  if (!ip) return false;
  const host = ip.includes(":") ? `[${ip}]` : ip;
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const r = await fetch(`http://${host}:${port}/poke`, { method: "POST", signal: ctrl.signal });
    await r.body?.cancel();
    return r.ok;
  } catch {
    return false;
  } finally {
    clearTimeout(t);
  }
}

/** 10.66.0.0/16 host offset → dotted address. */
export function wgAddress(host: number): string {
  return `10.66.${(host >> 8) & 255}.${host & 255}`;
}
