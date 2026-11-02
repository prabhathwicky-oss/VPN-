import Link from "next/link";
import { CreateNodeForm } from "@/components/Forms";
import { ago, bps, flag, statusClass } from "@/lib/format";
import { doEnabled } from "@/lib/providers";
import { requireAdmin } from "@/lib/supabase";

export default async function NodesPage({ searchParams }: { searchParams: Promise<{ show?: string }> }) {
  const { db } = await requireAdmin();
  const { show } = await searchParams;
  let q = db.from("nodes").select("*").order("region_code").order("name");
  if (show !== "all") q = q.neq("status", "retired");
  const [{ data: nodes }, { data: regions }] = await Promise.all([q, db.from("regions").select("*").order("sort")]);
  const cc = Object.fromEntries((regions ?? []).map((r) => [r.code, r.country_code]));

  return (
    <>
      <div className="page-head">
        <div>
          <h1>Servers</h1>
          <div className="sub">WireGuard + VLESS/REALITY nodes. New servers enroll themselves and appear here.</div>
        </div>
        <Link className="btn" href={show === "all" ? "/nodes" : "/nodes?show=all"}>
          {show === "all" ? "Hide retired" : "Show retired"}
        </Link>
      </div>

      <div className="card">
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Server</th><th>Status</th><th>Type</th><th>Tier</th><th>IP</th>
                <th>Peers</th><th>CPU</th><th>Egress</th><th>Heartbeat</th>
              </tr>
            </thead>
            <tbody>
              {(nodes ?? []).map((n) => (
                <tr key={n.id} className="link">
                  <td><Link href={`/nodes/${n.id}`}><b>{flag(cc[n.region_code])} {n.name}</b></Link></td>
                  <td><span className={`pill ${statusClass[n.status] ?? ""}`}>{n.status}</span></td>
                  <td className="muted">
                    {n.kind}
                    {n.wg_enabled ? " · WG" : ""}{n.vless_enabled ? " · VLESS" : ""}
                  </td>
                  <td>{n.tier === "pro" ? <span className="pill pro plain">PRO</span> : <span className="muted">all</span>}</td>
                  <td className="mono">{n.public_ip ?? "—"}</td>
                  <td>
                    <div className="row" style={{ flexWrap: "nowrap" }}>
                      <div className="bar"><span style={{ width: `${Math.min(100, (n.active_peers / Math.max(n.capacity, 1)) * 100)}%` }} /></div>
                      <span className="muted">{n.active_peers}/{n.capacity}</span>
                    </div>
                  </td>
                  <td>{n.cpu_load == null ? "—" : `${Math.round(n.cpu_load * 100)}%`}</td>
                  <td>{bps(n.tx_bps)}</td>
                  <td className="muted">{ago(n.last_heartbeat_at)}</td>
                </tr>
              ))}
              {!nodes?.length && <tr><td colSpan={9} className="empty">No servers yet. Add your first one below.</td></tr>}
            </tbody>
          </table>
        </div>
      </div>

      <div className="card" style={{ marginTop: 14 }}>
        <h2>Add a server</h2>
        <p className="muted" style={{ marginTop: -4 }}>
          Use a fresh Ubuntu 22.04/24.04 VPS (1 vCPU / 1 GB handles ~150–250 users). Open ports 443/tcp, 51820/udp and 8787/tcp.
        </p>
        <CreateNodeForm regions={(regions ?? []).map((r) => ({ code: r.code, name: r.name }))} doEnabled={doEnabled()} />
      </div>
    </>
  );
}
