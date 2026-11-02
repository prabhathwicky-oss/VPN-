import Link from "next/link";
import { resolveAlert } from "@/app/actions";
import { ago, date } from "@/lib/format";
import { requireAdmin } from "@/lib/supabase";

export default async function AlertsPage({ searchParams }: { searchParams: Promise<{ all?: string }> }) {
  const { db } = await requireAdmin();
  const { all } = await searchParams;
  let q = db.from("alerts").select("*, nodes(name)").order("created_at", { ascending: false }).limit(200);
  if (!all) q = q.is("resolved_at", null);
  const { data: alerts } = await q;

  return (
    <>
      <div className="page-head">
        <div>
          <h1>Alerts</h1>
          <div className="sub">Server offline, overload and CPU alerts are raised and cleared automatically every minute.</div>
        </div>
        <div className="row">
          <Link className="btn" href={all ? "/alerts" : "/alerts?all=1"}>{all ? "Open only" : "Show history"}</Link>
          {!all && !!alerts?.length && (
            <form action={resolveAlert}><button className="btn">Resolve all</button></form>
          )}
        </div>
      </div>
      <div className="card">
        <div className="table-wrap">
          <table>
            <thead><tr><th>Level</th><th>Alert</th><th>Server</th><th>Raised</th><th>Resolved</th><th></th></tr></thead>
            <tbody>
              {(alerts ?? []).map((a: any) => (
                <tr key={a.id}>
                  <td><span className={`pill ${a.level === "critical" ? "bad" : a.level === "warning" ? "warn" : ""}`}>{a.level}</span></td>
                  <td><b>{a.kind}</b><div className="muted">{a.message}</div></td>
                  <td>{a.node_id ? <Link href={`/nodes/${a.node_id}`}>{a.nodes?.name ?? "server"}</Link> : "—"}</td>
                  <td className="muted">{ago(a.created_at)}</td>
                  <td className="muted">{a.resolved_at ? date(a.resolved_at) : "—"}</td>
                  <td>
                    {!a.resolved_at && (
                      <form action={resolveAlert}>
                        <input type="hidden" name="id" value={a.id} />
                        <button className="btn sm">Resolve</button>
                      </form>
                    )}
                  </td>
                </tr>
              ))}
              {!alerts?.length && <tr><td colSpan={6} className="empty">No alerts 🎉</td></tr>}
            </tbody>
          </table>
        </div>
      </div>
    </>
  );
}
