# Launch checklist

## Legal & policy (do these first)
- [ ] **Local law.** Several countries restrict or license VPN services (Myanmar's 2025 Cybersecurity Law,
      China, Russia, Iran and others). Get written advice from a lawyer in each target market on whether you
      need a licence, and on where the company and servers should be.
- [ ] **Company.** Apple and Google both expect VPN apps to come from an organization account. Register the
      publishing company and get a D-U-N-S number.
- [ ] **Privacy policy & terms** hosted at `PRIVACY_URL` / `TERMS_URL` (template: `docs/PRIVACY_POLICY_TEMPLATE.md`).
- [ ] **Play Console:** VPN declaration, Data safety form (matches the privacy policy), ads declaration, content rating.
- [ ] **Abuse handling:** an abuse@ mailbox and a process for DMCA/abuse notices from your hosting provider.
      The servers already block SMTP (port 25), BitTorrent (stealth) and private networks.

## Product
- [ ] Real AdMob IDs set (until then the app shows Google test ads).
- [ ] Subscriptions created in Play and tested with a licence tester account (purchase, restore, cancel, expiry).
- [ ] At least 2 servers in Singapore so users fail over when one is down or blocked.
- [ ] Tested on the target networks — try Auto, Fast and Stealth modes on mobile data and Wi-Fi.
- [ ] Kill switch tested via Android Always-on VPN.

## Operations
- [ ] Admin account uses a strong unique password.
- [ ] Supabase: enable Point-in-Time Recovery or daily backups.
- [ ] Watch Admin › Alerts for the first week; check server CPU and egress.
- [ ] Bandwidth budget: a 1 GB DigitalOcean droplet includes ~1 TB/month. Free users at 500 MB/day
      ≈ 15 GB/month each at the cap — budget servers for your expected free-user count.

## Known limits of v1
- iOS is not included (needs a Mac build pipeline and an Apple organization account).
- Free-plan speed limiting applies to WireGuard downloads; Stealth sessions are limited by the daily data cap only.
- If Supabase itself is blocked in a country, new users cannot sign up there; returning users reconnect with their
  cached server config. A custom API domain behind a CDN is the usual next step.
