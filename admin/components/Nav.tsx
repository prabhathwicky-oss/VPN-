"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const items = [
  { href: "/", label: "Overview", icon: "◉" },
  { href: "/nodes", label: "Servers", icon: "▣" },
  { href: "/users", label: "Users", icon: "◎" },
  { href: "/regions", label: "Regions", icon: "◍" },
  { href: "/config", label: "Protocols & Plans", icon: "⚙" },
  { href: "/alerts", label: "Alerts", icon: "⚑" },
];

export default function Nav({ alerts }: { alerts: number }) {
  const path = usePathname();
  return (
    <nav className="nav">
      {items.map((i) => {
        const active = i.href === "/" ? path === "/" : path.startsWith(i.href);
        return (
          <Link key={i.href} href={i.href} className={active ? "active" : ""}>
            <span style={{ width: 18, textAlign: "center" }}>{i.icon}</span>
            {i.label}
            {i.href === "/alerts" && alerts > 0 && (
              <span className="pill bad plain" style={{ marginLeft: "auto" }}>{alerts}</span>
            )}
          </Link>
        );
      })}
    </nav>
  );
}
