import Link from "next/link";
import { SeriesChart, TrafficChart } from "@/components/Charts";
import { ago, bps, bytes, flag, statusClass } from "@/lib/format";
import { requireAdmin } from "@/lib/supabase";

export default async function Overview() {
  const { db } = await requireAdmin();
  const [{ data: ov }, { data: traffic }, { data: online }, { data: nodes }, { data: alerts }, { data: regions }] =
    await Promise.all([
      db.from("admin_overview").select("*").single(),
      db.from("admin_traffic_daily").select("*"),
      db.from("admin_online_hourly").select("*"),
      db.from("nodes").select("*").neq("status", "retired").order("region_code"),
      db.from("alerts").select("*").is("resolved_at", null).order("created_at", { ascending: false }).limit(6),
      db.from("regions").select("code,country_code"),
    ]);
  const cc = Object.fromEntries((regions ?? []).map((r) => [r.code, r.country_code]));
  const o = ov ?? {};
  const totalCap = (nodes ?? []).filter((n) => n.status === "active").reduce((s, n) => s + n.capacity, 0);
  const totalPeers = (nodes ?? []).reduce((s, n) => s + (n.status === "active" ? n.active_peers : 0), 0);
  const throughput = (nodes ?? []).reduce((s, n) => s + Number(n.tx_bps ?? 0), 0);

  const kpis = [
    { label: "Online now", value: o.online_users ?? 0, hint: `${totalPeers}/${totalCap} peer slots` },
    { label: "Users", value: o.total_users ?? 0, hint: `${o.pro_users ?? 0} Pro` },
    { label: "Traffic today", value: bytes(o.bytes_today), hint: `${bps(throughput)} egress now` },
    { label: "Servers", value: o.active_nodes ?? 0, hint: `${o.offline_nodes ?? 0} offline` },
    { label: "Open alerts", value: o.open_alerts ?? 0, hint: "monitoring every minute" },
  ];

  return (
    <>
      <div className="page-head">
        <div>
          <h1>Overview</h1>
          <div className="sub">Live state of the YPN network</div>
        </div>
        <Link className="btn primary" href="/nodes">Manage servers</Link>
      </div>

      <div className="grid kpis">
        {kpis.map((k) => (
          <div key={k.label} className="card kpi">
            <div className="label">{k.label}</div>
            <div className="value">{k.value}</div>
            <div className="hint">{k.hint}</div>
          </div>
        ))}
      </div>

      <div className="grid two" style={{ marginTop: 14 }}>
        <div className="card">
          <h2>Traffic — last 30 days</h2>
          <TrafficChart data={(traffic ?? []).map((r) => ({ day: r.day, bytes: Number(r.bytes) }))} />
        </div>
        <div className="card">
          <h2>Connected peers — last 48h</h2>
          <SeriesChart
            data={(online ?? []).map((r) => ({
              t: new Date(r.hour).toISOString().slice(11, 16), peers: Number(r.peers),
            }))}
            dataKey="peers" label="Peers"
          />
        </div>
      </div>

      <div className="grid two" style={{ marginTop: 14 }}>
        <div className="card">
          <div className="spread"><h2>Servers</h2><Link href="/nodes" className="muted">All →</Link></div>
          <div className="table-wrap">
            <table>
              <thead><tr><th>Server</th><th>Status</th><th>Load</th><th>Heartbeat</th></tr></thead>
              <tbody>
                {(nodes ?? []).slice(0, 8).map((n) => (
                  <tr key={n.id}>
                    <td><Link href={`/nodes/${n.id}`}>{flag(cc[n.region_code])} {n.name}</Link></td>
                    <td><span className={`pill ${statusClass[n.status] ?? ""}`}>{n.status}</span></td>
                    <td>
                      <div className="bar"><span style={{ width: `${Math.min(100, (n.active_peers / Math.max(n.capacity, 1)) * 100)}%` }} /></div>
                    </td>
                    <td className="muted">{ago(n.last_heartbeat_at)}</td>
                  </tr>
                ))}
                {!nodes?.length && <tr><td colSpan={4} className="empty">No servers yet — add one under Servers.</td></tr>}
              </tbody>
            </table>
          </div>
        </div>
        <div className="card">
          <div className="spread"><h2>Open alerts</h2><Link href="/alerts" className="muted">All →</Link></div>
          {(alerts ?? []).map((a) => (
            <div key={a.id} className="spread" style={{ padding: "8px 0", borderBottom: "1px solid var(--line)" }}>
              <span>
                <span className={`pill ${a.level === "critical" ? "bad" : a.level === "warning" ? "warn" : ""}`}>{a.kind}</span>{" "}
                {a.message}
              </span>
              <span className="muted">{ago(a.created_at)}</span>
            </div>
          ))}
          {!alerts?.length && <div className="empty">All clear ✓</div>}
        </div>
      </div>
    </>
  );
}
