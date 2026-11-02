import { createServerClient } from "@supabase/ssr";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
export const SUPABASE_ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
export const FUNCTIONS_URL = `${SUPABASE_URL}/functions/v1`;
export const SITE_URL = (process.env.NEXT_PUBLIC_SITE_URL ?? "").replace(/\/$/, "");

/** Cookie-bound client acting as the signed-in admin (RLS applies). */
export async function sessionClient() {
  const store = await cookies();
  return createServerClient(SUPABASE_URL, SUPABASE_ANON, {
    cookies: {
      getAll: () => store.getAll(),
      setAll: (list) => {
        try {
          list.forEach(({ name, value, options }) => store.set(name, value, options));
        } catch {
          // called from a Server Component — the proxy refreshes cookies instead
        }
      },
    },
  });
}

let _service: SupabaseClient | null = null;
/** Service-role client. Only used after requireAdmin() has passed. */
export function serviceClient(): SupabaseClient {
  if (!_service) {
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!key) throw new Error("SUPABASE_SERVICE_ROLE_KEY is not set");
    _service = createClient(SUPABASE_URL, key, { auth: { persistSession: false, autoRefreshToken: false } });
  }
  return _service;
}

/** Ensures the visitor is a signed-in admin; returns a service-role client. */
export async function requireAdmin(): Promise<{ db: SupabaseClient; email: string }> {
  const supa = await sessionClient();
  const { data } = await supa.auth.getUser();
  if (!data.user) redirect("/login");
  const db = serviceClient();
  const { data: prof } = await db.from("profiles").select("role").eq("id", data.user.id).maybeSingle();
  if (prof?.role !== "admin") redirect("/login?error=not_admin");
  return { db, email: data.user.email ?? "" };
}
