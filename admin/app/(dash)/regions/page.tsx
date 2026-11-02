import { saveRegion } from "@/app/actions";
import { flag } from "@/lib/format";
import { requireAdmin } from "@/lib/supabase";

export default async function RegionsPage() {
  const { db } = await requireAdmin();
  const [{ data: regions }, { data: nodes }] = await Promise.all([
    db.from("regions").select("*").order("sort"),
    db.from("nodes").select("region_code,status"),
  ]);
  const counts = (code: string) => {
    const n = (nodes ?? []).filter((x) => x.region_code === code);
    return `${n.filter((x) => x.status === "active").length} active / ${n.filter((x) => x.status !== "retired").length}`;
  };

  return (
    <>
      <div className="page-head">
        <div>
          <h1>Regions</h1>
          <div className="sub">Locations shown in the app. Pro-only regions are locked for free users.</div>
        </div>
      </div>
      <div className="grid" style={{ gap: 10 }}>
        {(regions ?? []).map((r) => (
          <form key={r.code} action={saveRegion} className="card">
            <div className="row" style={{ alignItems: "flex-end" }}>
              <div style={{ fontSize: 28, width: 40 }}>{flag(r.country_code)}</div>
              <input type="hidden" name="code" value={r.code} />
              <label style={{ width: 90 }}>Code<input value={r.code} disabled /></label>
              <label style={{ flex: 1, minWidth: 160 }}>Name<input name="name" defaultValue={r.name} /></label>
              <label style={{ width: 90 }}>Country<input name="country_code" defaultValue={r.country_code} maxLength={2} /></label>
              <label style={{ width: 120 }}>DO region<input name="do_region" defaultValue={r.do_region ?? ""} placeholder="sgp1" /></label>
              <label style={{ width: 80 }}>Sort<input name="sort" type="number" defaultValue={r.sort} /></label>
              <label className="check"><input type="checkbox" name="pro_only" defaultChecked={r.pro_only} /> Pro only</label>
              <label className="check"><input type="checkbox" name="enabled" defaultChecked={r.enabled} /> Enabled</label>
              <span className="muted" style={{ minWidth: 110 }}>{counts(r.code)}</span>
              <button className="btn sm">Save</button>
            </div>
          </form>
        ))}
        <form action={saveRegion} className="card">
          <h2>Add region</h2>
          <div className="row" style={{ alignItems: "flex-end" }}>
            <label style={{ width: 90 }}>Code<input name="code" required placeholder="jp" /></label>
            <label style={{ flex: 1, minWidth: 160 }}>Name<input name="name" required placeholder="Japan" /></label>
            <label style={{ width: 90 }}>Country<input name="country_code" required maxLength={2} placeholder="JP" /></label>
            <label style={{ width: 120 }}>DO region<input name="do_region" placeholder="sgp1" /></label>
            <label style={{ width: 80 }}>Sort<input name="sort" type="number" defaultValue={10} /></label>
            <label className="check"><input type="checkbox" name="pro_only" defaultChecked /> Pro only</label>
            <label className="check"><input type="checkbox" name="enabled" defaultChecked /> Enabled</label>
            <button className="btn primary sm">Add</button>
          </div>
        </form>
      </div>
    </>
  );
}
