import Link from "next/link";
import { notFound } from "next/navigation";
import { revokeDevice, saveNote, setPlan, toggleBan } from "@/app/actions";
import { TrafficChart } from "@/components/Charts";
import { ConfirmButton } from "@/components/Forms";
import { ago, bytes, date, isPro } from "@/lib/format";
import { requireAdmin } from "@/lib/supabase";

export default async function UserPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { db } = await requireAdmin();
  const { data: profile } = await db.from("profiles").select("*").eq("id", id).maybeSingle();
  if (!profile) notFound();

  const [{ data: auth }, { data: devices }, { data: peers }, { data: subs }, { data: usage }] = await Promise.all([
    db.auth.admin.getUserById(id),
    db.from("devices").select("*").eq("user_id", id).order("last_seen_at", { ascending: false }),
    db.from("peers").select("*, nodes(name)").eq("user_id", id).eq("status", "active"),
    db.from("subscriptions").select("*").eq("user_id", id).order("updated_at", { ascending: false }),
    db.from("usage_daily").select("day,bytes").eq("user_id", id).order("day").limit(60),
  ]);
  const pro = isPro(profile);

  return (
    <>
      <div className="page-head">
        <div>
          <div className="muted"><Link href="/users">← Users</Link></div>
          <h1>{auth?.user?.email ?? "Anonymous user"}</h1>
          <div className="sub mono">{id}</div>
        </div>
        <div className="row">
          {profile.is_banned ? <span className="pill bad">banned</span> : pro ? <span className="pill pro">pro</span> : <span className="pill">free</span>}
          <form action={toggleBan}>
            <input type="hidden" name="id" value={id} />
            <ConfirmButton className={profile.is_banned ? "btn" : "btn danger"}
              message={profile.is_banned ? "Unban this user?" : "Ban this user? Their sessions stop within seconds."}>
              {profile.is_banned ? "Unban" : "Ban"}
            </ConfirmButton>
          </form>
        </div>
      </div>

      <div className="grid two">
        <div className="card form">
          <h2>Plan</h2>
          <div className="muted">
            Current: <b style={{ color: "var(--text)" }}>{pro ? "Pro" : "Free"}</b>
            {profile.plan_expires_at ? ` · expires ${date(profile.plan_expires_at)}` : pro ? " · no expiry (manual)" : ""}
          </div>
          <form action={setPlan} className="row">
            <input type="hidden" name="id" value={id} />
            <input type="hidden" name="plan" value="pro" />
            <select name="days" defaultValue="30" style={{ width: 160 }}>
              <option value="7">7 days</option>
              <option value="30">30 days</option>
              <option value="365">1 year</option>
              <option value="0">No expiry</option>
            </select>
            <button className="btn violet">Grant Pro</button>
          </form>
          {profile.plan === "pro" && (
            <form action={setPlan}>
              <input type="hidden" name="id" value={id} />
              <input type="hidden" name="plan" value="free" />
              <button className="btn">Set to Free</button>
            </form>
          )}
          <form action={saveNote} className="form">
            <input type="hidden" name="id" value={id} />
            <label>Internal note<input name="note" defaultValue={profile.note ?? ""} placeholder="e.g. partner account" /></label>
            <div><button className="btn sm">Save note</button></div>
          </form>
        </div>

        <div className="card">
          <h2>Daily usage</h2>
          <TrafficChart data={(usage ?? []).map((u) => ({ day: u.day, bytes: Number(u.bytes) }))} />
        </div>
      </div>

      <div className="card" style={{ marginTop: 14 }}>
        <div className="spread">
          <h2>Devices</h2>
          <form action={revokeDevice}>
            <input type="hidden" name="user_id" value={id} />
            <ConfirmButton className="btn sm danger" message="Sign out all devices?">Sign out all</ConfirmButton>
          </form>
        </div>
        <div className="table-wrap">
          <table>
            <thead><tr><th>Device</th><th>App</th><th>Status</th><th>Session</th><th>Last seen</th><th></th></tr></thead>
            <tbody>
              {(devices ?? []).map((d) => {
                const peer = (peers ?? []).find((p) => p.device_id === d.id);
                return (
                  <tr key={d.id}>
                    <td><div>{d.model ?? d.platform}</div><div className="muted mono">{d.install_id.slice(0, 10)}</div></td>
                    <td>{d.app_version ?? "—"}</td>
                    <td>{d.revoked ? <span className="pill">signed out</span> : <span className="pill ok">active</span>}</td>
                    <td>
                      {peer
                        ? <>{peer.protocol === "vless" ? "Stealth" : "WireGuard"} · {peer.nodes?.name} · {bytes(peer.bytes_total)}<div className="muted">handshake {ago(peer.last_handshake_at)}</div></>
                        : <span className="muted">—</span>}
                    </td>
                    <td className="muted">{ago(d.last_seen_at)}</td>
                    <td>
                      {!d.revoked && (
                        <form action={revokeDevice}>
                          <input type="hidden" name="user_id" value={id} />
                          <input type="hidden" name="device_id" value={d.id} />
                          <button className="btn sm">Sign out</button>
                        </form>
                      )}
                    </td>
                  </tr>
                );
              })}
              {!devices?.length && <tr><td colSpan={6} className="empty">No devices.</td></tr>}
            </tbody>
          </table>
        </div>
      </div>

      <div className="card" style={{ marginTop: 14 }}>
        <h2>Subscriptions</h2>
        <div className="table-wrap">
          <table>
            <thead><tr><th>Product</th><th>State</th><th>Expires</th><th>Auto-renew</th><th>Order</th></tr></thead>
            <tbody>
              {(subs ?? []).map((s) => (
                <tr key={s.id}>
                  <td>{s.product_id}</td>
                  <td><span className={`pill ${s.state.includes("ACTIVE") ? "ok" : s.state.includes("GRACE") ? "warn" : ""}`}>{s.state.replace("SUBSCRIPTION_STATE_", "").toLowerCase()}</span></td>
                  <td>{date(s.expires_at)}</td>
                  <td>{s.auto_renewing == null ? "—" : s.auto_renewing ? "yes" : "no"}</td>
                  <td className="mono muted">{s.order_id ?? "—"}</td>
                </tr>
              ))}
              {!subs?.length && <tr><td colSpan={5} className="empty">No purchases.</td></tr>}
            </tbody>
          </table>
        </div>
      </div>
    </>
  );
}
