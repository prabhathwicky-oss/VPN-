import Link from "next/link";
import { ago, bytes, date } from "@/lib/format";
import { requireAdmin } from "@/lib/supabase";

export default async function UsersPage({ searchParams }: { searchParams: Promise<{ q?: string; page?: string }> }) {
  const { db } = await requireAdmin();
  const { q = "", page = "1" } = await searchParams;
  const p = Math.max(1, Number(page) || 1);
  const size = 50;
  const { data: users, error } = await db.rpc("admin_users", { p_search: q || null, p_limit: size, p_offset: (p - 1) * size });

  return (
    <>
      <div className="page-head">
        <div>
          <h1>Users</h1>
          <div className="sub">Anonymous accounts show as “anonymous” until the user saves an email.</div>
        </div>
        <form className="row" action="/users">
          <input name="q" defaultValue={q} placeholder="Search email or user ID" style={{ width: 280 }} />
          <button className="btn">Search</button>
        </form>
      </div>
      {error && <div className="callout bad">{error.message}</div>}
      <div className="card">
        <div className="table-wrap">
          <table>
            <thead>
              <tr><th>User</th><th>Plan</th><th>Devices</th><th>Today</th><th>30 days</th><th>Last seen</th><th>Joined</th></tr>
            </thead>
            <tbody>
              {(users ?? []).map((u: any) => (
                <tr key={u.id} className="link">
                  <td>
                    <Link href={`/users/${u.id}`}>
                      <b>{u.email ?? "anonymous"}</b>
                      <div className="muted mono">{u.id.slice(0, 8)}</div>
                    </Link>
                  </td>
                  <td>
                    {u.is_banned ? <span className="pill bad">banned</span>
                      : u.effective_plan === "pro" ? <span className="pill pro">pro</span>
                      : <span className="pill">free</span>}
                    {u.role === "admin" && <span className="pill warn plain" style={{ marginLeft: 6 }}>admin</span>}
                  </td>
                  <td>{u.devices}</td>
                  <td>{bytes(u.usage_today)}</td>
                  <td>{bytes(u.usage_30d)}</td>
                  <td className="muted">{ago(u.last_seen_at)}</td>
                  <td className="muted">{date(u.created_at).slice(0, 10)}</td>
                </tr>
              ))}
              {!users?.length && <tr><td colSpan={7} className="empty">No users found.</td></tr>}
            </tbody>
          </table>
        </div>
      </div>
      <div className="row" style={{ marginTop: 12, justifyContent: "flex-end" }}>
        {p > 1 && <Link className="btn sm" href={`/users?q=${encodeURIComponent(q)}&page=${p - 1}`}>← Prev</Link>}
        {(users?.length ?? 0) === size && <Link className="btn sm" href={`/users?q=${encodeURIComponent(q)}&page=${p + 1}`}>Next →</Link>}
      </div>
    </>
  );
}
