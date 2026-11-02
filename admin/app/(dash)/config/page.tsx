import { ConfigEditor } from "@/components/Forms";
import { requireAdmin } from "@/lib/supabase";

const HELP: Record<string, string> = {
  protocols:
    "Enable/disable WireGuard and VLESS globally, the order the app tries them in Auto mode (fallback_order), and which protocols free users may use (free_protocols).",
  free_plan: "Free plan limits: daily_mb (daily data cap), speed_mbps (download cap per user on WireGuard), max_devices.",
  pro_plan: "Pro plan limits: max_devices.",
  ads: "AdMob for free users: enabled, banner, interstitial, interstitial_every (show after every N connections).",
  app: "dns servers pushed to clients, tunnel mtu, min_version, announcement (text shown on the home screen or null), maintenance (true blocks new connections).",
  products: "Google Play subscription product IDs. Create the same IDs in Play Console › Monetize › Subscriptions.",
};

export default async function ConfigPage() {
  const { db } = await requireAdmin();
  const { data } = await db.from("app_config").select("*").order("key");
  const order = Object.keys(HELP);
  const idx = (k: string) => (order.indexOf(k) < 0 ? 99 : order.indexOf(k));
  const rows = [...(data ?? [])].sort((a, b) => idx(a.key) - idx(b.key));

  return (
    <>
      <div className="page-head">
        <div>
          <h1>Protocols & Plans</h1>
          <div className="sub">Changes reach apps on their next refresh (≤ 2 minutes) and servers on their next sync (≤ 20 seconds).</div>
        </div>
      </div>
      <div className="grid two">
        {rows.map((r) => <ConfigEditor key={r.key} k={r.key} value={r.value} help={HELP[r.key] ?? ""} />)}
      </div>
    </>
  );
}
