# YPN VPN

A complete Android VPN platform, built from the *VPN Application Development Proposal*:

| Part | Folder | Tech |
|---|---|---|
| Android app | `app/` | Flutter · WireGuard · Xray (VLESS + REALITY) · AdMob · Google Play Billing |
| Control API + database | `supabase/` | Supabase Postgres, Row-Level Security, pg_cron, Edge Functions (Deno) |
| Admin dashboard | `admin/` | Next.js 16 on Vercel |
| VPN server node | `server/` | Ubuntu installer + Python agent (WireGuard + Xray) |
| CI/CD | `.github/workflows/` | APK/AAB build, backend deploy, checks |

## How it fits together

```
 Android app ──HTTPS──▶ Supabase Edge Functions ──▶ Postgres (users, plans, nodes, peers, usage)
     │                         │  ▲
     │ tunnel                  │  │ sync / report (every 20–60 s, own secret)
     ▼                         ▼  │
 VPN node: WireGuard :51820/udp  +  VLESS-REALITY :443/tcp  +  agent :8787 (poke)
     ▲
 Admin dashboard (Vercel) — users, servers, 1-click deploy, IP rotation, protocols, alerts
```

**Connection flow:** the app asks `vpn-connect` for a session → the API picks the least-loaded
healthy node allowed for the user's plan → allocates a WireGuard address (or a VLESS client) →
"pokes" the node agent, which pulls the change instantly → the app starts the tunnel and verifies
real traffic flows. If it doesn't, the app tries another node, then falls back from WireGuard to
Stealth (VLESS + REALITY, which looks like ordinary HTTPS to `www.microsoft.com`). If the API itself is
blocked, the app reuses the last working configuration.

## Proposal coverage

| Proposal item | Where |
|---|---|
| One-tap connect, auto & manual region | `app/lib/screens/home_screen.dart`, `servers_screen.dart` |
| Auto-reconnect, failover, protocol fallback | `app/lib/state/app_state.dart` |
| WireGuard standard nodes, Xray/VLESS stealth nodes | `server/install.sh`, `app/lib/services/vpn_engine.dart` |
| DNS protection, IPv6 leak block, encrypted tunnels | WireGuard `AllowedIPs ::/0`, pushed DNS, REALITY |
| Free/Pro plans, AdMob banner + interstitial | `supabase/functions/app-bootstrap`, `app/lib/services/ads_service.dart` |
| Play Billing with server validation, RTDN renewals | `supabase/functions/billing-verify`, `play-rtdn`, `_shared/google.ts` |
| Free daily data cap, free speed cap, Pro priority nodes | `node_desired_state`, agent `tc` shaping, `pick_node` |
| User / device / session management | Admin › Users |
| Add/remove nodes, health, regions | Admin › Servers, Regions |
| Enable/disable protocols, fallback order | Admin › Protocols & Plans |
| IP rotation via node replacement, rapid deploy | Admin › Server › *Rotate IP* (DigitalOcean automatic or install command) |
| Monitoring, analytics, alerts | `monitor_tick()` (pg_cron), Admin › Overview / Alerts |
| Kill switch | Android Always-on VPN (guided in Settings) |

## Getting started

Follow **[docs/SETUP.md](docs/SETUP.md)** — about 45 minutes, mostly creating accounts.
Before publishing, read **[docs/LAUNCH_CHECKLIST.md](docs/LAUNCH_CHECKLIST.md)**.
