// Called by the app on launch / resume. Registers the device and returns
// everything the app needs: plan, limits, ads config, protocols, regions.
import {
  admin, effectivePlan, getConfig, getProfile, handler, HttpError, json, readJson, requireUser,
} from "../_shared/common.ts";

interface Body { install_id?: string; model?: string; app_version?: string }

Deno.serve(handler(async (req) => {
  const user = await requireUser(req);
  const body = await readJson<Body>(req);
  if (!body.install_id) throw new HttpError(400, "bad_request", "install_id required");
  const db = admin();

  const [profile, cfg] = await Promise.all([getProfile(user.id), getConfig()]);
  if (profile.is_banned) throw new HttpError(403, "banned", "This account has been suspended.");
  const plan = effectivePlan(profile);

  // Register device and enforce plan device limit (oldest device is signed out).
  const maxDevices = Number((plan === "pro" ? cfg.pro_plan?.max_devices : cfg.free_plan?.max_devices) ?? 1);
  const { data: device, error: devErr } = await db.from("devices").upsert({
    user_id: user.id,
    install_id: body.install_id,
    model: body.model ?? null,
    app_version: body.app_version ?? null,
    revoked: false,
    last_seen_at: new Date().toISOString(),
  }, { onConflict: "user_id,install_id" }).select("*").single();
  if (devErr) throw devErr;

  const { data: devices } = await db.from("devices").select("id,last_seen_at")
    .eq("user_id", user.id).eq("revoked", false).order("last_seen_at", { ascending: false });
  const extra = (devices ?? []).filter((d) => d.id !== device.id).slice(Math.max(0, maxDevices - 1));
  if (extra.length) {
    const ids = extra.map((d) => d.id);
    await db.from("devices").update({ revoked: true }).in("id", ids);
    await db.from("peers").update({ status: "revoked", revoked_at: new Date().toISOString() })
      .in("device_id", ids).eq("status", "active");
  }
  await db.from("profiles").update({ last_seen_at: new Date().toISOString() }).eq("id", user.id);

  // Regions with live availability
  const [{ data: regions }, { data: nodes }, { data: usage }] = await Promise.all([
    db.from("regions").select("*").eq("enabled", true).order("sort"),
    db.from("nodes").select("region_code,kind,tier,active_peers,capacity,last_heartbeat_at,wg_enabled,vless_enabled")
      .eq("status", "active"),
    db.rpc("usage_today", { uid: user.id }),
  ]);
  const fresh = Date.now() - 3 * 60_000;
  const regionList = (regions ?? []).map((r) => {
    const rn = (nodes ?? []).filter((n) => n.region_code === r.code &&
      n.last_heartbeat_at && new Date(n.last_heartbeat_at).getTime() > fresh &&
      (plan === "pro" || n.tier === "all"));
    const cap = rn.reduce((s, n) => s + n.capacity, 0);
    const used = rn.reduce((s, n) => s + n.active_peers, 0);
    return {
      code: r.code,
      name: r.name,
      country_code: r.country_code,
      pro_only: r.pro_only,
      locked: r.pro_only && plan !== "pro",
      available: rn.length > 0,
      load: cap > 0 ? Math.round((used / cap) * 100) : 100,
      stealth: rn.some((n) => n.vless_enabled && n.kind !== "standard"),
    };
  });

  const protocols = cfg.protocols ?? {};
  const freeProtocols: string[] = protocols.free_protocols ?? ["wireguard", "vless"];
  const allowed = ["wireguard", "vless"].filter((p) =>
    protocols[p]?.enabled !== false && (plan === "pro" || freeProtocols.includes(p)));

  return json({
    user: { id: user.id, is_anonymous: user.is_anonymous ?? !user.email, email: user.email ?? null },
    plan: {
      name: plan,
      expires_at: profile.plan_expires_at,
      daily_limit_bytes: plan === "pro" ? null : Number(cfg.free_plan?.daily_mb ?? 500) * 1024 * 1024,
      used_today_bytes: Number(usage ?? 0),
      speed_limit_mbps: plan === "pro" ? null : Number(cfg.free_plan?.speed_mbps ?? 0) || null,
      max_devices: maxDevices,
    },
    ads: plan === "pro" ? { enabled: false } : (cfg.ads ?? { enabled: false }),
    protocols: {
      allowed,
      fallback_order: (protocols.fallback_order ?? ["wireguard", "vless"]).filter((p: string) => allowed.includes(p)),
    },
    app: cfg.app ?? {},
    products: cfg.products ?? {},
    regions: regionList,
    device_id: device.id,
  });
}));
