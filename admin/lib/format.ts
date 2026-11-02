export function bytes(n: number | string | null | undefined): string {
  let b = Number(n ?? 0);
  if (b < 1024) return `${b} B`;
  const u = ["KB", "MB", "GB", "TB", "PB"];
  let i = -1;
  do { b /= 1024; i++; } while (b >= 1024 && i < u.length - 1);
  return `${b.toFixed(b >= 100 ? 0 : 1)} ${u[i]}`;
}

export function bps(n: number | string | null | undefined): string {
  let b = Number(n ?? 0);
  const u = ["bps", "Kbps", "Mbps", "Gbps"];
  let i = 0;
  while (b >= 1000 && i < u.length - 1) { b /= 1000; i++; }
  return `${b.toFixed(b >= 100 || i === 0 ? 0 : 1)} ${u[i]}`;
}

export function ago(iso: string | null | undefined): string {
  if (!iso) return "never";
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 60) return `${Math.floor(s)}s ago`;
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
}

export function date(iso: string | null | undefined): string {
  if (!iso) return "—";
  return new Date(iso).toISOString().slice(0, 16).replace("T", " ");
}

export function flag(cc: string): string {
  if (!cc || cc.length !== 2) return "🌐";
  return String.fromCodePoint(...[...cc.toUpperCase()].map((c) => c.charCodeAt(0) + 127397));
}

export const statusClass: Record<string, string> = {
  active: "ok", pending: "warn", draining: "warn", offline: "bad", retired: "",
};

export function isPro(p: { plan: string; plan_expires_at: string | null }) {
  return p.plan === "pro" && (!p.plan_expires_at || new Date(p.plan_expires_at) > new Date());
}
