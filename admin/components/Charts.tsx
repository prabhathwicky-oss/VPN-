"use client";

import {
  Area, AreaChart, Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from "recharts";

const axis = { stroke: "#8c95b3", fontSize: 11, tickLine: false, axisLine: false } as const;
const tip = {
  contentStyle: { background: "#1c2440", border: "1px solid #2a3354", borderRadius: 10, color: "#e8ecf8" },
  labelStyle: { color: "#8c95b3" },
};

function fmtBytes(n: number) {
  const u = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
  return `${n.toFixed(n >= 100 || i === 0 ? 0 : 1)} ${u[i]}`;
}

export function TrafficChart({ data }: { data: { day: string; bytes: number }[] }) {
  if (!data.length) return <div className="empty">No traffic yet</div>;
  return (
    <ResponsiveContainer width="100%" height={240}>
      <BarChart data={data} margin={{ top: 6, right: 6, left: 0, bottom: 0 }}>
        <CartesianGrid stroke="#2a3354" vertical={false} />
        <XAxis dataKey="day" {...axis} tickFormatter={(d: string) => d.slice(5)} />
        <YAxis {...axis} width={64} tickFormatter={(v: number) => fmtBytes(v)} />
        <Tooltip {...tip} formatter={(v) => [fmtBytes(Number(v)), "Traffic"]} cursor={{ fill: "#ffffff08" }} />
        <Bar dataKey="bytes" fill="#2ee6a8" radius={[4, 4, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  );
}

export function SeriesChart({
  data, dataKey, label, color = "#8b7cff", format,
}: {
  data: Record<string, unknown>[]; dataKey: string; label: string; color?: string; format?: "bps";
}) {
  if (!data.length) return <div className="empty">No data yet</div>;
  const f = (v: number) => {
    if (format !== "bps") return String(v);
    const u = ["bps", "Kbps", "Mbps", "Gbps"];
    let i = 0;
    while (v >= 1000 && i < u.length - 1) { v /= 1000; i++; }
    return `${v.toFixed(i === 0 ? 0 : 1)} ${u[i]}`;
  };
  const id = `g-${dataKey}`;
  return (
    <ResponsiveContainer width="100%" height={220}>
      <AreaChart data={data} margin={{ top: 6, right: 6, left: 0, bottom: 0 }}>
        <defs>
          <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity={0.45} />
            <stop offset="100%" stopColor={color} stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid stroke="#2a3354" vertical={false} />
        <XAxis dataKey="t" {...axis} minTickGap={40} />
        <YAxis {...axis} width={64} tickFormatter={(v: number) => f(v)} allowDecimals={false} />
        <Tooltip {...tip} formatter={(v) => [f(Number(v)), label]} />
        <Area type="monotone" dataKey={dataKey} stroke={color} strokeWidth={2} fill={`url(#${id})`} />
      </AreaChart>
    </ResponsiveContainer>
  );
}
