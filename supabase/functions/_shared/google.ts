// Google Play Developer API helpers (service-account auth via WebCrypto).
import { admin } from "./common.ts";

const SCOPE = "https://www.googleapis.com/auth/androidpublisher";
let cached: { token: string; exp: number } | null = null;

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function accessToken(): Promise<string> {
  if (cached && cached.exp > Date.now() + 60_000) return cached.token;
  const raw = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON");
  if (!raw) throw new Error("GOOGLE_SERVICE_ACCOUNT_JSON is not configured");
  const sa = JSON.parse(raw);
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email, scope: SCOPE, aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
  }));
  const pem = String(sa.private_key).replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claim}`)));
  const jwt = `${header}.${claim}.${b64url(sig)}`;
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  if (!r.ok) throw new Error(`Google auth failed: ${r.status} ${await r.text()}`);
  const j = await r.json();
  cached = { token: j.access_token, exp: Date.now() + j.expires_in * 1000 };
  return cached.token;
}

function pkg(): string {
  const p = Deno.env.get("PLAY_PACKAGE_NAME");
  if (!p) throw new Error("PLAY_PACKAGE_NAME is not configured");
  return p;
}

export async function getSubscriptionV2(purchaseToken: string): Promise<any> {
  const t = await accessToken();
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${pkg()}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
  const r = await fetch(url, { headers: { Authorization: `Bearer ${t}` } });
  if (!r.ok) throw new Error(`Play API ${r.status}: ${await r.text()}`);
  return await r.json();
}

export async function acknowledge(productId: string, purchaseToken: string): Promise<void> {
  const t = await accessToken();
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${pkg()}/purchases/subscriptions/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`;
  const r = await fetch(url, {
    method: "POST", headers: { Authorization: `Bearer ${t}`, "Content-Type": "application/json" }, body: "{}",
  });
  if (!r.ok && r.status !== 409) console.error("acknowledge failed", r.status, await r.text());
}

const ENTITLED = new Set([
  "SUBSCRIPTION_STATE_ACTIVE",
  "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
  "SUBSCRIPTION_STATE_CANCELED", // cancelled but still paid until expiry
]);

/**
 * Fetch a purchase from Google, store it, attach it to `userId` (if given) and
 * recompute the owner's plan. Returns the stored subscription row.
 */
export async function syncPurchase(purchaseToken: string, userId?: string) {
  const db = admin();
  const sub = await getSubscriptionV2(purchaseToken);
  const line = (sub.lineItems ?? [])[0] ?? {};
  const productId: string = line.productId ?? "unknown";
  const expiresAt: string | null = line.expiryTime ?? null;
  const state: string = sub.subscriptionState ?? "UNKNOWN";

  const { data: existing } = await db.from("subscriptions").select("*").eq("purchase_token", purchaseToken).maybeSingle();
  const owner = userId ?? existing?.user_id;
  if (!owner) return null;

  // A token restored from another (e.g. old anonymous) account is transferred.
  const previousOwner = existing && existing.user_id !== owner ? existing.user_id : null;

  // Upgrades/downgrades: the old token is superseded.
  if (sub.linkedPurchaseToken) {
    await db.from("subscriptions").update({ state: "SUPERSEDED", updated_at: new Date().toISOString() })
      .eq("purchase_token", sub.linkedPurchaseToken);
  }

  const { data: row, error } = await db.from("subscriptions").upsert({
    user_id: owner,
    platform: "google_play",
    product_id: productId,
    purchase_token: purchaseToken,
    order_id: sub.latestOrderId ?? null,
    state,
    auto_renewing: line.autoRenewingPlan?.autoRenewEnabled ?? null,
    expires_at: expiresAt,
    raw: sub,
    updated_at: new Date().toISOString(),
  }, { onConflict: "purchase_token" }).select("*").single();
  if (error) throw error;

  if (sub.acknowledgementState === "ACKNOWLEDGEMENT_STATE_PENDING" && ENTITLED.has(state)) {
    await acknowledge(productId, purchaseToken);
  }

  await recomputePlan(owner);
  if (previousOwner) await recomputePlan(previousOwner);
  return row;
}

export async function recomputePlan(userId: string) {
  const db = admin();
  const { data: subs } = await db.from("subscriptions").select("state,expires_at").eq("user_id", userId);
  const now = Date.now();
  let best: number | null = null;
  for (const s of subs ?? []) {
    if (!ENTITLED.has(s.state) || !s.expires_at) continue;
    const t = new Date(s.expires_at).getTime();
    if (t > now && (best === null || t > best)) best = t;
  }
  const { data: prof } = await db.from("profiles").select("plan,plan_expires_at,note").eq("id", userId).single();
  // Manual (admin-granted) Pro with no expiry is left alone.
  const manualPro = prof?.plan === "pro" && !prof?.plan_expires_at;
  if (manualPro) return;
  await db.from("profiles").update(best
    ? { plan: "pro", plan_expires_at: new Date(best).toISOString() }
    : { plan: "free", plan_expires_at: null }).eq("id", userId);
}
