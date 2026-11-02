import Link from "next/link";
import { notFound } from "next/navigation";
import { destroyNode, setNodeStatus, updateNode } from "@/app/actions";
import { SeriesChart } from "@/components/Charts";
import { ConfirmButton, EnrollTokenForm, RotateForm } from "@/components/Forms";
import { ago, bps, date, flag, statusClass } from "@/lib/format";
import { requireAdmin } from "@/lib/supabase";

export default async function NodePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { db } = await requireAdmin();
  const { data: n } = await db.from("nodes").select("*, regions(name,country_code)").eq("id", id).maybeSingle();
  if (!n) notFound();

  const since = new Date(Date.now() - 24 * 3600_000).toISOString();
  const [{ data: metrics }, { count: activePeers }, { data: replacedBy }] = await Promise.all([
    db.from("node_metrics").select("at,active_peers,tx_bps,cpu_load").eq("node_id", id).gte("at", since).order("at"),
    db.from("peers").select("id", { count: "exact", head: true }).eq("node_id", id).eq("status", "active"),
    db.from("nodes").select("id,name,status").eq("replaces_node_id", id),
  ]);
  const series = (metrics ?? []).map((m) => ({
    t: new Date(m.at).toISOString().slice(11, 16),
    peers: m.active_peers ?? 0,
    tx: Number(m.tx_bps ?? 0),
  }));

  const statusBtn = (status: string, label: string, cls = "btn") => (
    <form action={setNodeStatus}>
      <input type="hidden" name="id" value={n.id} />
      <input type="hidden" name="status" value={status} />
      <button className={cls}>{label}</button>
    </form>
  );

  return (
    <>
      <div className="page-head">
        <div>
          <div className="muted"><Link href="/nodes">← Servers</Link></div>
          <h1>{flag(n.regions?.country_code)} {n.name} <span className={`pill ${statusClass[n.status] ?? ""}`}>{n.status}</span></h1>
          <div className="sub mono">{n.public_ip ?? "not enrolled yet"} · {n.regions?.name} · agent {n.agent_version ?? "—"}</div>
        </div>
        <div className="row">
          {n.status === "active" && statusBtn("draining", "Drain")}
          {(n.status === "draining" || n.status === "offline") && statusBtn("active", "Activate", "btn primary")}
          {n.status !== "retired" && n.status !== "pending" && <RotateForm id={n.id} />}
        </div>
      </div>

      {n.status === "pending" && (
        <div className="callout" style={{ marginBottom: 14 }}>
          Waiting for this server to enroll. If you lost the install command, generate a new token below.
        </div>
      )}
      {replacedBy?.length ? (
        <div className="callout" style={{ marginBottom: 14 }}>
          Replacement: {replacedBy.map((r) => <Link key={r.id} href={`/nodes/${r.id}`}><b>{r.name}</b> ({r.status}) </Link>)}
        </div>
      ) : null}

      <div className="grid kpis">
        <div className="card kpi"><div className="label">Active peers</div><div className="value">{n.active_peers}</div><div className="hint">{activePeers ?? 0} allocated · cap {n.capacity}</div></div>
        <div className="card kpi"><div className="label">CPU</div><div className="value">{n.cpu_load == null ? "—" : `${Math.round(n.cpu_load * 100)}%`}</div><div className="hint">RAM {n.mem_used_pct == null ? "—" : `${Math.round(n.mem_used_pct)}%`}</div></div>
        <div className="card kpi"><div className="label">Egress</div><div className="value">{bps(n.tx_bps)}</div><div className="hint">ingress {bps(n.rx_bps)}</div></div>
        <div className="card kpi"><div className="label">Heartbeat</div><div className="value" style={{ fontSize: 22 }}>{ago(n.last_heartbeat_at)}</div><div className="hint">created {date(n.created_at)}</div></div>
      </div>

      <div className="grid two" style={{ marginTop: 14 }}>
        <div className="card"><h2>Peers — 24h</h2><SeriesChart data={series} dataKey="peers" label="Peers" /></div>
        <div className="card"><h2>Egress — 24h</h2><SeriesChart data={series} dataKey="tx" label="Egress" color="#2ee6a8" format="bps" /></div>
      </div>

      <div className="grid two" style={{ marginTop: 14 }}>
        <form action={updateNode} className="card form">
          <h2>Settings</h2>
          <input type="hidden" name="id" value={n.id} />
          <div className="form-grid">
            <label>Name<input name="name" defaultValue={n.name} /></label>
            <label>Capacity<input name="capacity" type="number" defaultValue={n.capacity} /></label>
            <label>
              Tier
              <select name="tier" defaultValue={n.tier}>
                <option value="all">Free + Pro</option>
                <option value="pro">Pro only</option>
              </select>
            </label>
          </div>
          <label className="check"><input type="checkbox" name="wg_enabled" defaultChecked={n.wg_enabled} /> WireGuard enabled</label>
          <label className="check"><input type="checkbox" name="vless_enabled" defaultChecked={n.vless_enabled} /> VLESS / REALITY (stealth) enabled</label>
          <div><button className="btn primary">Save</button></div>
        </form>

        <div className="card form">
          <h2>Protocol details</h2>
          <table>
            <tbody>
              <tr><td className="muted">WireGuard</td><td className="mono">:{n.wg_port}/udp · {n.wg_public_key ? `${n.wg_public_key.slice(0, 16)}…` : "—"}</td></tr>
              <tr><td className="muted">REALITY</td><td className="mono">:{n.xray_port}/tcp · SNI {n.reality_sni}</td></tr>
              <tr><td className="muted">Public key</td><td className="mono">{n.reality_public_key ? `${n.reality_public_key.slice(0, 16)}…` : "—"}</td></tr>
              <tr><td className="muted">Provider</td><td>{n.provider}{n.provider_instance_id ? ` · ${n.provider_instance_id}` : ""}</td></tr>
            </tbody>
          </table>
          <div className="row" style={{ alignItems: "flex-start" }}>
            <EnrollTokenForm id={n.id} />
            {n.status !== "retired" && (
              <form action={destroyNode}>
                <input type="hidden" name="id" value={n.id} />
                <ConfirmButton className="btn danger"
                  message={n.provider === "digitalocean" ? "Retire this server AND destroy the droplet?" : "Retire this server? Connected users will be moved."}>
                  Retire{n.provider === "digitalocean" ? " & destroy" : ""}
                </ConfirmButton>
              </form>
            )}
          </div>
        </div>
      </div>
    </>
  );
}
