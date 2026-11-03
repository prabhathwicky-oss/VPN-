// Allocates a VPN session for the calling device and returns a ready-to-use
// client configuration. Handles node selection, plan gating, quota checks,
// protocol selection and failover (exclude_nodes).
import {
  admin, effectivePlan, getConfig, getProfile, handler, HttpError, json, pokeNode, readJson,
  requireUser, wgAddress,
} from "../_shared/common.ts";

interface Body {
  install_id?: string;
  region?: string;            // 'auto' or region code
  protocol?: string;          // 'auto' | 'wireguard' | 'vless'
  wg_public_key?: string;     // required for wireguard
  exclude_nodes?: string[];   // node ids that failed for this client
}

const B64_KEY = /^[A-Za-z0-9+/]{42,43}=$/;

Deno.serve(handler(async (req) => {
  const user = await requireUser(req);
  const body = await readJson<Body>(req);
  const db = admin();

  if (!body.install_id) throw new HttpError(400, "bad_request", "install_id required");
  const [profile, cfg] = await Promise.all([getProfile(user.id), getConfig()]);
  if (profile.is_banned) throw new HttpError(403, "banned", "This account has been suspended.");
  if (cfg.app?.maintenance) throw new HttpError(503, "maintenance", "Service is under maintenance. Please try again soon.");
  const plan = effectivePlan(profile);

  const { data: device } = await db.from("devices").select("*")
    .eq("user_id", user.id).eq("install_id", body.install_id).maybeSingle();
  if (!device) throw new HttpError(409, "device_unknown", "Please restart the app.");
  if (device.revoked) throw new HttpError(403, "device_revoked", "This device was signed out because your plan's device limit was reached.");

  if (plan === "free") {
    const { data: over } = await db.rpc("over_free_quota", { uid: user.id });
    if (over) throw new HttpError(402, "quota_exceeded", "You've used today's free data. Upgrade to Pro for unlimited data.");
  }

  // Region gating
  const region = body.region && body.region !== "auto" ? body.region : "auto";
  if (region !== "auto") {
    const { data: r } = await db.from("regions").select("*").eq("code", region).maybeSingle();
    if (!r || !r.enabled) throw new HttpError(404, "region_unavailable", "That location is unavailable.");
    if (r.pro_only && plan !== "pro") throw new HttpError(402, "pro_required", "This location is available on Pro.");
  }

  // Protocol candidates
  const protocols = cfg.protocols ?? {};
  const freeProtocols: string[] = protocols.free_protocols ?? ["wireguard", "vless"];
  const allowed = ["wireguard", "vless"].filter((p) =>
    protocols[p]?.enabled !== false && (plan === "pro" || freeProtocols.includes(p)));
  let candidates: string[];
  if (body.protocol && body.protocol !== "auto") {
    if (!allowed.includes(body.protocol)) throw new HttpError(402, "protocol_unavailable", "That protocol isn't available on your plan.");
    candidates = [body.protocol];
  } else {
    candidates = (protocols.fallback_order ?? ["wireguard", "vless"]).filter((p: string) => allowed.includes(p));
  }
  if (!candidates.length) throw new HttpError(503, "no_protocol", "No protocol is currently enabled.");

  const exclude = (body.exclude_nodes ?? []).filter((x) => /^[0-9a-f-]{36}$/.test(x));

  for (const protocol of candidates) {
    if (protocol === "wireguard" && !(body.wg_public_key && B64_KEY.test(body.wg_public_key))) continue;

    const { data: node } = await db.rpc("pick_node", {
      p_user: user.id, p_region: region, p_protocol: protocol, p_exclude: exclude,
    });
    if (!node || !node.id) continue;

    const app = cfg.app ?? {};
    const dns: string[] = app.dns ?? ["1.1.1.1", "1.0.0.1"];
    const nodeInfo = { id: node.id, name: node.name, region: node.region_code };

    if (protocol === "wireguard") {
      const { data: peer, error } = await db.rpc("create_wg_peer", {
        p_user: user.id, p_device: device.id, p_node: node.id, p_pubkey: body.wg_public_key,
      });
      if (error) { console.error(error); exclude.push(node.id); continue; }
      await pokeNode(node.public_ip, node.agent_port);
      return json({
        protocol,
        node: nodeInfo,
        peer_id: peer.id,
        wireguard: {
          address: `${wgAddress(peer.wg_host)}/32`,
          dns,
          mtu: Number(app.mtu ?? 1280),
          server_public_key: node.wg_public_key,
          endpoint: `${node.public_ip}:${node.wg_port}`,
          allowed_ips: "0.0.0.0/0, ::/0",
          keepalive: 25,
        },
      });
    }

    if (protocol === "vless") {
      const { data: peer, error } = await db.rpc("create_vless_peer", {
        p_user: user.id, p_device: device.id, p_node: node.id,
      });
      if (error) { console.error(error); exclude.push(node.id); continue; }
      await pokeNode(node.public_ip, node.agent_port);
      const params = new URLSearchParams({
        encryption: "none",
        flow: "xtls-rprx-vision",
        security: "reality",
        sni: node.reality_sni,
        fp: "chrome",
        pbk: node.reality_public_key,
        sid: node.reality_short_id ?? "",
        type: "tcp",
        headerType: "none",
      });
      const link = `vless://${profile.xray_uuid}@${node.public_ip}:${node.xray_port}?${params}#YPN-${node.region_code.toUpperCase()}`;
      return json({ protocol, node: nodeInfo, peer_id: peer.id, vless: { link, dns } });
    }
  }

  const { count } = await db.from("nodes").select("id", { count: "exact", head: true }).eq("status", "active");
  throw new HttpError(503, "no_capacity", count
    ? "All servers are busy right now. Please try another location."
    : "No servers are online right now. Please try again in a few minutes.");
}));
