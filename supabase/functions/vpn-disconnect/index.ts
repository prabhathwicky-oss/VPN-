// Releases the device's active sessions so server capacity is freed quickly.
import { admin, handler, json, pokeNode, readJson, requireUser } from "../_shared/common.ts";

Deno.serve(handler(async (req) => {
  const user = await requireUser(req);
  const { install_id } = await readJson<{ install_id?: string }>(req);
  const db = admin();
  if (!install_id) return json({ ok: true });

  const { data: device } = await db.from("devices").select("id")
    .eq("user_id", user.id).eq("install_id", install_id).maybeSingle();
  if (!device) return json({ ok: true });

  const { data: peers } = await db.from("peers")
    .update({ status: "revoked", revoked_at: new Date().toISOString() })
    .eq("device_id", device.id).eq("status", "active")
    .select("node_id");

  const nodeIds = [...new Set((peers ?? []).map((p) => p.node_id))];
  if (nodeIds.length) {
    const { data: nodes } = await db.from("nodes").select("public_ip,agent_port").in("id", nodeIds);
    // fire-and-forget; agents also reconcile on their own timer
    await Promise.all((nodes ?? []).map((n) => pokeNode(n.public_ip, n.agent_port, 2000)));
  }
  return json({ ok: true });
}));
