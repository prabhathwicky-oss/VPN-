# Setup guide

Everything below happens in web dashboards — no coding and no terminal needed, except pasting one
command into a new server (or none, if you use DigitalOcean automatic deploys).

## 1. Put the code on GitHub
1. Create a **private** repository (e.g. `ypn-vpn`) on github.com.
2. Upload the contents of this folder (keep the folder structure, including `.github/`).

## 2. Supabase (database + API)
1. Create a project at supabase.com. Choose the **Singapore** region (closest to your users and first servers).
   Save the **database password**.
2. **Authentication › Sign In / Providers**: turn on **Allow anonymous sign-ins** and keep **Email** enabled.
3. **Authentication › Email Templates** → *Magic Link* and *Change Email Address*: make sure the body includes
   `{{ .Token }}` (the app signs in with a 6-digit code, not a link). Example: `Your YPN code is {{ .Token }}`.
4. Note from **Project Settings**: the *Project ref*, *Project URL*, *anon/publishable key* and *service_role/secret key*.
5. Create a personal **access token**: supabase.com/dashboard/account/tokens.

## 3. GitHub secrets
Repository › Settings › Secrets and variables › Actions.

**Secrets**

| Name | Value |
|---|---|
| `SUPABASE_ACCESS_TOKEN` | personal access token (step 2.5) |
| `SUPABASE_DB_PASSWORD` | database password |
| `SUPABASE_PROJECT_REF` | project ref |
| `SUPABASE_URL` | `https://<ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | anon / publishable key |
| `ADMOB_APP_ID`, `ADMOB_BANNER_ID`, `ADMOB_INTERSTITIAL_ID` | from AdMob (leave empty → Google test ads) |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | upload key (see §7; optional for testing) |
| `GOOGLE_SERVICE_ACCOUNT_JSON` | Play Console API service account key (see §6) |
| `RTDN_TOKEN` | any long random string |

**Variables** (optional): `ANDROID_PACKAGE` (default `com.ypnvpn.app` — choose it once, it can never change after
publishing), `APP_NAME`, `PRIVACY_URL`, `TERMS_URL`, `SUPPORT_EMAIL`.

Then: **Actions › Backend (Supabase) › Run workflow**. This creates all tables and deploys the API.

## 4. Admin dashboard (Vercel)
1. vercel.com › Add New › Project › import the repository. **Root Directory: `admin`**.
2. Environment variables (from `admin/.env.example`):
   `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`,
   `NEXT_PUBLIC_SITE_URL` (the Vercel URL, e.g. `https://ypn-admin.vercel.app`), optionally `DO_API_TOKEN`.
3. Deploy. Check that `https://<your-admin>/install.sh` downloads a script.
4. Make yourself admin: Supabase › Authentication › Users › **Add user** (email + password), then
   SQL Editor → run `supabase/make_admin.sql` with your email. Sign in to the dashboard.

## 5. First VPN server
**Option A — automatic (recommended):** create a DigitalOcean API token (Read+Write), add it to Vercel as
`DO_API_TOKEN`, redeploy, then Admin › Servers › Add server › *Deploy with: DigitalOcean*. Done — it turns
**Active** in ~5 minutes. *Rotate IP* will then build replacement servers automatically too.

**Option B — any VPS** (Vultr, Hetzner, Contabo…): create Ubuntu 24.04, 1 vCPU / 1 GB, in Singapore.
Admin › Servers › Add server › *My own server* → copy the command → paste it into the server's web console.

Firewall ports: **443/tcp** (Stealth), **51820/udp** (WireGuard), **8787/tcp** (control poke).

## 6. Google Play
1. Play Console account **registered as an organization** (VPN apps must be published by organizations).
2. Create the app with package name = `ANDROID_PACKAGE`.
3. Monetize › Subscriptions: create `ypn_pro_monthly` and `ypn_pro_yearly` (or change IDs in Admin › Protocols & Plans › products).
4. Setup › API access: create a service account, grant it *View financial data* + *Manage orders and subscriptions*,
   download its JSON key → GitHub secret `GOOGLE_SERVICE_ACCOUNT_JSON` → re-run the backend workflow.
5. Monetization setup › Real-time developer notifications: create a Pub/Sub topic with a **push** subscription to
   `https://<ref>.supabase.co/functions/v1/play-rtdn?token=<RTDN_TOKEN>`.
6. App content › **VPN declaration**: declare VpnService is the core functionality.

## 7. Build the app
**Actions › Android app › Run workflow.** Download the APK from the run's *Artifacts* or the *Releases* page
and install it on a phone. Upload the `.aab` to Play Console.

For Play uploads you need an upload key. Generate one once (Android Studio › Build › Generate Signed Bundle,
or any keytool), base64 it (`base64 -w0 upload.jks`) and store it plus its passwords as the four `ANDROID_*`
secrets. Keep the .jks file safe.

## Day-to-day
- **A server got blocked** → Admin › Server › *Rotate IP*. Users move to the new IP automatically.
- **Grant Pro manually** → Admin › Users › user › *Grant Pro*.
- **Announce maintenance** → Admin › Protocols & Plans › `app` → set `"announcement"` or `"maintenance": true`.
- **Change free limits / ads frequency** → Admin › Protocols & Plans.
