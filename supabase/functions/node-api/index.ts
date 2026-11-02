// API used by the agent running on every VPN server.
//   enroll : one-time token -> node secret (called by install.sh)
//   sync   : returns the peers/clients the node should currently serve
//   report : counters, handshakes and load; also acts as heartbeat
import {
  admin, handler, HttpError, json, randomToken, readJson, sha256Hex,
} from "../_shared/common.ts";

interface EnrollBody {
  action: "enroll";
  token: string;
  public_ip: string;
  wg_public_key?: string;
  wg_port?: number;
  reality_public_key?: string;
  reality_short_id?: string;
  reality_sni?: string;
  xray_port?: number;
  agent_port?: number;
  agent_version?: string;
}

async function authNode(req: Request) {
  const auth = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const [nodeId, secret] = auth.split(".");
  if (!nodeId || !secret || !/^[0-9a-f-]{36}$/.test(nodeId)) {
    throw new HttpError(401, "unauthorized", "Bad node credentials");
  }
  const { data: node } = await admin().from("nodes").select("*").eq("id", nodeId).maybeSingle();
  if (!node || !node.agent_secret_hash || node.agent_secret_hash !== await sha256Hex(secret)) {
    throw new HttpError(401, "unauthorized", "Bad node credentials");
  }
  return node;
}

Deno.serve(handler(async (req) => {
  const body = await readJson<Record<string, any>>(req);
  const db = admin();

  if (body.action === "enroll") {
    const b = body as EnrollBody;
    if (!b.token || !b.public_ip) throw new HttpError(400, "bad_request", "token and public_ip required");
    const hash = await sha256Hex(b.token);
    const { data: node } = await db.from("nodes").select("*")
      .eq("enroll_token_hash", hash).eq("status", "pending").maybeSingle();
    if (!node) throw new HttpError(401, "invalid_token", "Enrollment token is invalid or already used");

    const secret = randomToken(32);
    const { error } = await db.from("nodes").update({
      status: "active",
      enroll_token_hash: null,
      agent_secret_hash: await sha256Hex(secret),
      public_ip: b.public_ip,
      wg_public_key: b.wg_public_key ?? null,
      wg_port: b.wg_port ?? node.wg_port,
      reality_public_key: b.reality_public_key ?? null,
      reality_short_id: b.reality_short_id ?? null,
      reality_sni: b.reality_sni ?? node.reality_sni,
      xray_port: b.xray_port ?? node.xray_port,
      agent_port: b.agent_port ?? node.agent_port,
      agent_version: b.agent_version ?? null,
      last_heartbeat_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", node.id);
    if (error) throw error;

    // IP rotation: once the replacement is live, start draining the old node.
    if (node.replaces_node_id) {
      await db.from("nodes").update({
        status: "draining", draining_since: new Date().toISOString(), updated_at: new Date().toISOString(),
      }).eq("id", node.replaces_node_id).in("status", ["active", "offline"]);
      await db.from("alerts").insert({
        level: "info", kind: "node_rotated", node_id: node.replaces_node_id,
        message: `Node replaced by ${node.name} (${b.public_ip}); old node is draining`,
      });
    }
    await db.from("alerts").insert({
      level: "info", kind: "node_enrolled", node_id: node.id,
      message: `Node ${node.name} enrolled from ${b.public_ip}`,
    });
    return json({ node_id: node.id, secret, name: node.name });
  }

  const node = await authNode(req);

  if (body.action === "sync") {
    const { data, error } = await db.rpc("node_desired_state", { p_node: node.id });
    if (error) throw error;
    await db.from("nodes").update({ last_heartbeat_at: new Date().toISOString() }).eq("id", node.id);
    return json(data);
  }

  if (body.action === "report") {
    const { error } = await db.rpc("node_report", { p_node: node.id, payload: body.payload ?? {} });
    if (error) throw error;
    return json({ ok: true });
  }

  throw new HttpError(400, "bad_request", "Unknown action");
}));
