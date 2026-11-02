import Nav from "@/components/Nav";
import { signOut } from "@/app/actions";
import { requireAdmin } from "@/lib/supabase";

export const dynamic = "force-dynamic";

export default async function DashLayout({ children }: { children: React.ReactNode }) {
  const { db, email } = await requireAdmin();
  const { count } = await db.from("alerts").select("id", { count: "exact", head: true }).is("resolved_at", null);
  return (
    <div className="shell">
      <aside className="side">
        <div className="brand">
          <span className="brand-mark">◆</span> YPN Control
        </div>
        <Nav alerts={count ?? 0} />
        <div className="side-foot">
          <div style={{ marginBottom: 8, overflow: "hidden", textOverflow: "ellipsis" }}>{email}</div>
          <form action={signOut}><button className="btn sm">Sign out</button></form>
        </div>
      </aside>
      <main className="main">{children}</main>
    </div>
  );
}
