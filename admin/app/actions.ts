"use server";

import { createHash, randomBytes } from "node:crypto";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { doCreateDroplet, doDestroyDroplet, doEnabled, installCommand } from "@/lib/providers";
import { requireAdmin, sessionClient } from "@/lib/supabase";

const sha256 = (s: string) => createHash("sha256").update(s).digest("hex");
const now = () => new Date().toISOString();

async function poke(ip: string | null, port: number) {
  if (!ip) return;
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 3000);
    await fetch(`http://${ip}:${port}/poke`, { method: "POST", signal: ctrl.signal, cache: "no-store" });
    clearTimeout(t);
  } catch {
    /* agents reconcile on their own within ~20s */
  }
}

async function userNodes(userId: string): Promise<{ ip: string | null; port: number }[]> {
  const { db } = await requireAdmin();
  const { data } = await db.from("peers").select("node_id, nodes(public_ip, agent_port)")
    .eq("user_id", userId).eq("status", "active");
  const seen = new Map<string, { ip: string | null; port: number }>();
  for (const p of (data ?? []) as any[]) {
    if (!seen.has(p.node_id)) seen.set(p.node_id, { ip: p.nodes?.public_ip ?? null, port: p.nodes?.agent_port ?? 8787 });
  }
  return [...seen.values()];
}

async function pokeAll(nodes: { ip: string | null; port: number }[]) {
  await Promise.all(nodes.map((n) => poke(n.ip, n.port)));
}

async function pokeUserNodes(userId: string) {
  await pokeAll(await userNodes(userId));
}

// ------------------------------------------------------------------ auth
export async function signOut() {
  const supa = await sessionClient();
  await supa.auth.signOut();
  redirect("/login");
}

// ------------------------------------------------------------------ users
export async function setPlan(formData: FormData) {
  const { db } = await requireAdmin();
  const id = String(formData.get("id"));
  const plan = String(formData.get("plan"));
  const days = Number(formData.get("days") || 0);
  const expires = plan === "pro" && days > 0 ? new Date(Date.now() + days * 86400_000).toISOString() : null;
  await db.from("profiles").update({ plan, plan_expires_at: plan === "pro" ? expires : null }).eq("id", id);
  await pokeUserNodes(id);
  revalidatePath(`/users/${id}`);
  revalidatePath("/users");
}

export async function toggleBan(formData: FormData) {
  const { db } = await requireAdmin();
  const id = String(formData.get("id"));
  const { data } = await db.from("profiles").select("is_banned").eq("id", id).single();
  await db.from("profiles").update({ is_banned: !data?.is_banned }).eq("id", id);
  await pokeUserNodes(id);
  revalidatePath(`/users/${id}`);
  revalidatePath("/users");
}

export async function revokeDevice(formData: FormData) {
  const { db } = await requireAdmin();
  const userId = String(formData.get("user_id"));
  const deviceId = formData.get("device_id") ? String(formData.get("device_id")) : null;
  let q = db.from("devices").update({ revoked: true }).eq("user_id", userId);
  if (deviceId) q = q.eq("id", deviceId);
  await q;
  const nodes = await userNodes(userId);
  let p = db.from("peers").update({ status: "revoked", revoked_at: now() }).eq("user_id", userId).eq("status", "active");
  if (deviceId) p = p.eq("device_id", deviceId);
  await p;
  await pokeAll(nodes);
  revalidatePath(`/users/${userId}`);
}

export async function saveNote(formData: FormData) {
  const { db } = await requireAdmin();
  const id = String(formData.get("id"));
  await db.from("profiles").update({ note: String(formData.get("note") ?? "") || null }).eq("id", id);
  revalidatePath(`/users/${id}`);
}

// ------------------------------------------------------------------ nodes
export type CreateNodeResult = { ok: boolean; message: string; command?: string; nodeId?: string };

async function createNodeRecord(fields: {
  name: string; region_code: string; kind: string; tier: string; capacity: number; reality_sni: string;
  provider: string; replaces_node_id?: string | null;
}) {
  const { db } = await requireAdmin();
  const token = randomBytes(24).toString("hex");
  const { data, error } = await db.from("nodes").insert({
    ...fields,
    status: "pending",
    enroll_token_hash: sha256(token),
    wg_enabled: fields.kind !== "stealth",
    vless_enabled: fields.kind !== "standard",
  }).select("*").single();
  if (error) throw new Error(error.message);
  return { node: data, token };
}

export async function createNode(_prev: CreateNodeResult | null, formData: FormData): Promise<CreateNodeResult> {
  try {
    const { db } = await requireAdmin();
    const region = String(formData.get("region_code"));
    const provider = String(formData.get("provider") || "manual");
    const name = String(formData.get("name") || "").trim() || `${region}-${Date.now().toString(36).slice(-4)}`;
    const sni = String(formData.get("reality_sni") || "www.microsoft.com").trim();
    const { node, token } = await createNodeRecord({
      name,
      region_code: region,
      kind: String(formData.get("kind") || "hybrid"),
      tier: String(formData.get("tier") || "all"),
      capacity: Number(formData.get("capacity") || 250),
      reality_sni: sni,
      provider,
    });
    if (provider === "digitalocean") {
      if (!doEnabled()) return { ok: false, message: "DO_API_TOKEN is not configured on the admin site." };
      const { data: reg } = await db.from("regions").select("do_region").eq("code", region).single();
      const dropletId = await doCreateDroplet({ name: `ypn-${name}`, region: reg?.do_region || "sgp1", token, sni });
      await db.from("nodes").update({ provider_instance_id: dropletId }).eq("id", node.id);
      revalidatePath("/nodes");
      return {
        ok: true, nodeId: node.id,
        message: `Droplet ${dropletId} is being created. The node will turn Active by itself in ~3–5 minutes.`,
      };
    }
    revalidatePath("/nodes");
    return {
      ok: true, nodeId: node.id, command: installCommand(token, sni),
      message: "Run this on a fresh Ubuntu 22.04/24.04 server as root. The token works once.",
    };
  } catch (e) {
    return { ok: false, message: e instanceof Error ? e.message : String(e) };
  }
}

export async function newEnrollToken(_prev: CreateNodeResult | null, formData: FormData): Promise<CreateNodeResult> {
  const { db } = await requireAdmin();
  const id = String(formData.get("id"));
  const token = randomBytes(24).toString("hex");
  const { data: node } = await db.from("nodes").update({
    status: "pending", enroll_token_hash: sha256(token), agent_secret_hash: null,
  }).eq("id", id).select("*").single();
  revalidatePath(`/nodes/${id}`);
  return {
    ok: true, nodeId: id, command: installCommand(token, node?.reality_sni ?? "www.microsoft.com"),
    message: "New one-time token created. Re-run the installer on the server (it keeps existing keys).",
  };
}

export async function setNodeStatus(formData: FormData) {
  const { db } = await requireAdmin();
  const id = String(formData.get("id"));
  const status = String(formData.get("status"));
  const patch: Record<string, unknown> = { status, updated_at: now() };
  if (status === "draining") patch.draining_since = now();
  await db.from("nodes").update(patch).eq("id", id);
  const { data: n } = await db.from("nodes").select("public_ip, agent_port").eq("id", id).single();
  await poke(n?.public_ip ?? null, n?.agent_port ?? 8787);
  revalidatePath("/nodes");
  revalidatePath(`/nodes/${id}`);
}

export async function updateNode(formData: FormData) {
  const { db } = await requireAdmin();
  const id = String(formData.get("id"));
  await db.from("nodes").update({
    name: String(formData.get("name")),
    capacity: Number(formData.get("capacity")),
    tier: String(formData.get("tier")),
    wg_enabled: formData.get("wg_enabled") === "on",
    vless_enabled: formData.get("vless_enabled") === "on",
    updated_at: now(),
  }).eq("id", id);
  revalidatePath(`/nodes/${id}`);
  revalidatePath("/nodes");
}

/** IP rotation: build a replacement node; the old one drains once the new one enrolls. */
export async function rotateNode(_prev: CreateNodeResult | null, formData: FormData): Promise<CreateNodeResult> {
  try {
    const { db } = await requireAdmin();
    const id = String(formData.get("id"));
    const { data: old } = await db.from("nodes").select("*").eq("id", id).single();
    if (!old) return { ok: false, message: "Node not found" };
    const base = String(old.name).replace(/-r\d+$/, "");
    const m = String(old.name).match(/-r(\d+)$/);
    const name = `${base}-r${m ? Number(m[1]) + 1 : 1}`;
    const { node, token } = await createNodeRecord({
      name, region_code: old.region_code, kind: old.kind, tier: old.tier, capacity: old.capacity,
      reality_sni: old.reality_sni, provider: old.provider, replaces_node_id: old.id,
    });
    if (old.provider === "digitalocean" && doEnabled()) {
      const { data: reg } = await db.from("regions").select("do_region").eq("code", old.region_code).single();
      const dropletId = await doCreateDroplet({ name: `ypn-${name}`, region: reg?.do_region || "sgp1", token, sni: old.reality_sni });
      await db.from("nodes").update({ provider_instance_id: dropletId }).eq("id", node.id);
      revalidatePath("/nodes");
      return { ok: true, nodeId: node.id, message: `Replacement ${name} is being created on DigitalOcean. ${old.name} will drain automatically once it is live.` };
    }
    revalidatePath("/nodes");
    return {
      ok: true, nodeId: node.id, command: installCommand(token, old.reality_sni),
      message: `Run this on a NEW server (new IP). ${old.name} will drain automatically once ${name} enrolls.`,
    };
  } catch (e) {
    return { ok: false, message: e instanceof Error ? e.message : String(e) };
  }
}

export async function destroyNode(formData: FormData) {
  const { db } = await requireAdmin();
  const id = String(formData.get("id"));
  const { data: n } = await db.from("nodes").select("*").eq("id", id).single();
  if (n?.provider === "digitalocean" && n.provider_instance_id && doEnabled()) {
    await doDestroyDroplet(n.provider_instance_id);
  }
  await db.from("nodes").update({ status: "retired", updated_at: now() }).eq("id", id);
  await db.from("peers").update({ status: "revoked", revoked_at: now() }).eq("node_id", id).eq("status", "active");
  revalidatePath("/nodes");
  redirect("/nodes");
}

// ------------------------------------------------------------------ regions
export async function saveRegion(formData: FormData) {
  const { db } = await requireAdmin();
  const code = String(formData.get("code")).trim().toLowerCase();
  await db.from("regions").upsert({
    code,
    name: String(formData.get("name")).trim(),
    country_code: String(formData.get("country_code")).trim().toUpperCase(),
    pro_only: formData.get("pro_only") === "on",
    enabled: formData.get("enabled") === "on",
    sort: Number(formData.get("sort") || 0),
    do_region: String(formData.get("do_region") || "").trim() || null,
  });
  revalidatePath("/regions");
}

// ------------------------------------------------------------------ config
export async function saveConfig(_prev: { ok: boolean; message: string } | null, formData: FormData) {
  const { db } = await requireAdmin();
  const key = String(formData.get("key"));
  try {
    const value = JSON.parse(String(formData.get("value")));
    await db.from("app_config").upsert({ key, value, updated_at: now() });
    revalidatePath("/config");
    return { ok: true, message: `Saved “${key}”.` };
  } catch (e) {
    return { ok: false, message: `Invalid JSON: ${e instanceof Error ? e.message : e}` };
  }
}

// ------------------------------------------------------------------ alerts
export async function resolveAlert(formData: FormData) {
  const { db } = await requireAdmin();
  const id = formData.get("id");
  let q = db.from("alerts").update({ resolved_at: now() }).is("resolved_at", null);
  if (id) q = q.eq("id", Number(id));
  await q;
  revalidatePath("/alerts");
  revalidatePath("/");
}
