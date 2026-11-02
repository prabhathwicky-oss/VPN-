#!/usr/bin/env python3
"""
YPN node agent.

Runs on every VPN server. It keeps the local WireGuard and Xray (VLESS/REALITY)
configuration in sync with the control plane, applies free-plan speed limits,
and reports usage counters + server load (which doubles as the heartbeat).

Standard library only. Python 3.8+.

  agent.py enroll --api URL --token TOKEN [--public-ip IP] [--sni HOST]
  agent.py run
"""
import argparse
import copy
import ipaddress
import json
import logging
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "1.0.0"
CONF_DIR = "/etc/ypn-agent"
CONF_PATH = os.path.join(CONF_DIR, "config.json")
REALITY_PATH = os.path.join(CONF_DIR, "reality.json")
XRAY_CONF = "/usr/local/etc/xray/config.json"
XRAY_BIN = shutil.which("xray") or "/usr/local/bin/xray"
XRAY_API = "127.0.0.1:10085"
XRAY_TAG = "vless-in"
WG_IFACE = "wg0"
WG_PUBKEY_PATH = "/etc/wireguard/publickey"
WG_NET = "10.66"

SYNC_INTERVAL = 20
REPORT_INTERVAL = 60

log = logging.getLogger("ypn-agent")


# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------
def sh(*args, check=True, input_text=None):
    r = subprocess.run(list(args), capture_output=True, text=True, input=input_text)
    if check and r.returncode != 0:
        raise RuntimeError("%s failed (%s): %s" % (" ".join(args), r.returncode, r.stderr.strip()))
    return r


def load_json(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return default


def write_json_atomic(path, data, mode=0o600):
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def host_to_ip(host):
    return "%s.%d.%d" % (WG_NET, (host >> 8) & 255, host & 255)


def api_call(conf, action, payload=None, auth=True, timeout=20):
    body = {"action": action}
    if payload is not None:
        body.update(payload)
    req = urllib.request.Request(
        conf["api_url"].rstrip("/") + "/node-api",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "User-Agent": "ypn-agent/" + VERSION},
        method="POST",
    )
    if auth:
        req.add_header("Authorization", "Bearer %s.%s" % (conf["node_id"], conf["secret"]))
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise RuntimeError("API %s -> HTTP %s: %s" % (action, e.code, detail))


def public_ip():
    for url in ("https://api.ipify.org", "https://ifconfig.me/ip", "https://ipv4.icanhazip.com"):
        try:
            with urllib.request.urlopen(url, timeout=8) as r:
                ip = r.read().decode().strip()
                ipaddress.ip_address(ip)
                return ip
        except Exception:
            continue
    raise RuntimeError("could not determine public IP; pass --public-ip")


# ----------------------------------------------------------------------------
# agent
# ----------------------------------------------------------------------------
class Agent:
    def __init__(self, conf):
        self.conf = conf
        self.lock = threading.Lock()
        self.shaped_hosts = None          # last applied free host set
        self.shaped_rate = None
        self.xray_pending = {}            # email -> bytes not yet reported
        self.last_net = None              # (time, rx, tx)
        self.default_iface = self._default_iface()
        self.last_sync_ok = 0.0

    # ---------------- sync ----------------
    def sync(self):
        with self.lock:
            desired = api_call(self.conf, "sync")
            self.apply_wireguard(desired.get("wireguard", []))
            self.apply_shaping(desired.get("wireguard", []), int(desired.get("free_speed_mbps") or 0))
            self.apply_xray(desired.get("xray", []))
            self.last_sync_ok = time.time()

    def wg_dump(self):
        r = sh("wg", "show", WG_IFACE, "dump", check=False)
        if r.returncode != 0:
            return {}
        peers = {}
        for line in r.stdout.strip().splitlines()[1:]:
            f = line.split("\t")
            if len(f) < 8:
                continue
            peers[f[0]] = {
                "allowed": f[3],
                "handshake": int(f[4] or 0),
                "rx": int(f[5] or 0),
                "tx": int(f[6] or 0),
            }
        return peers

    def apply_wireguard(self, desired):
        want = {}
        for p in desired:
            pk = p.get("public_key")
            if pk and p.get("host"):
                want[pk] = host_to_ip(int(p["host"])) + "/32"
        have = self.wg_dump()
        removed = added = 0
        for pk in have:
            if pk not in want:
                sh("wg", "set", WG_IFACE, "peer", pk, "remove", check=False)
                removed += 1
        for pk, allowed in want.items():
            if have.get(pk, {}).get("allowed") != allowed:
                sh("wg", "set", WG_IFACE, "peer", pk, "allowed-ips", allowed)
                added += 1
        if added or removed:
            log.info("wireguard: +%d -%d (total %d)", added, removed, len(want))

    def apply_shaping(self, desired, mbps):
        """Download speed cap for free users (egress on wg0) using HTB + u32."""
        hosts = sorted(int(p["host"]) for p in desired if p.get("free") and p.get("host"))
        if mbps <= 0:
            hosts = []
        if hosts == self.shaped_hosts and mbps == self.shaped_rate:
            return
        sh("tc", "qdisc", "del", "dev", WG_IFACE, "root", check=False)
        if hosts:
            sh("tc", "qdisc", "add", "dev", WG_IFACE, "root", "handle", "1:", "htb", "default", "1")
            sh("tc", "class", "add", "dev", WG_IFACE, "parent", "1:", "classid", "1:1", "htb", "rate", "10gbit")
            batch = []
            for i, h in enumerate(hosts):
                cid = "1:%x" % (16 + i)
                batch.append("class add dev %s parent 1: classid %s htb rate %dmbit ceil %dmbit" % (WG_IFACE, cid, mbps, mbps))
                batch.append("filter add dev %s protocol ip parent 1:0 prio 1 u32 match ip dst %s/32 flowid %s"
                             % (WG_IFACE, host_to_ip(h), cid))
            sh("tc", "-batch", "-", input_text="\n".join(batch) + "\n")
        self.shaped_hosts, self.shaped_rate = hosts, mbps
        log.info("shaping: %d free peers at %d Mbit/s", len(hosts), mbps)

    def apply_xray(self, desired):
        cfg = load_json(XRAY_CONF)
        if not cfg:
            return
        inbound = next((i for i in cfg.get("inbounds", []) if i.get("tag") == XRAY_TAG), None)
        if inbound is None:
            return
        current = {c["email"]: c for c in inbound["settings"].get("clients", [])}
        want = {c["email"]: {"id": c["id"], "email": c["email"], "flow": "xtls-rprx-vision", "level": 0}
                for c in desired if c.get("email") and c.get("id")}
        to_add = [c for e, c in want.items() if current.get(e, {}).get("id") != c["id"]]
        to_remove = [e for e in current if e not in want or current[e].get("id") != want[e]["id"]]
        if not to_add and not to_remove:
            return

        inbound["settings"]["clients"] = list(want.values())
        write_json_atomic(XRAY_CONF, cfg, 0o644)

        ok = True
        try:
            if to_remove:
                r = sh(XRAY_BIN, "api", "rmu", "-s", XRAY_API, "-tag=" + XRAY_TAG, *to_remove, check=False)
                ok = ok and r.returncode == 0
            if to_add:
                patch = copy.deepcopy(inbound)
                patch["settings"]["clients"] = to_add
                fd, tmp = tempfile.mkstemp(suffix=".json")
                with os.fdopen(fd, "w") as f:
                    json.dump({"inbounds": [patch]}, f)
                try:
                    r = sh(XRAY_BIN, "api", "adu", "-s", XRAY_API, tmp, check=False)
                    ok = ok and r.returncode == 0 and ("Added %d" % len(to_add)) in r.stdout
                finally:
                    os.unlink(tmp)
        except Exception as e:  # noqa
            log.warning("xray api error: %s", e)
            ok = False
        if not ok:
            log.info("xray live update failed, restarting xray")
            sh("systemctl", "restart", "xray", check=False)
        log.info("xray: +%d -%d (total %d)", len(to_add), len(to_remove), len(want))

    # ---------------- report ----------------
    def xray_stats(self):
        r = sh(XRAY_BIN, "api", "statsquery", "-s", XRAY_API, "-pattern", "user>>>", "-reset", check=False)
        if r.returncode != 0 or not r.stdout.strip():
            return {}
        try:
            data = json.loads(r.stdout)
        except json.JSONDecodeError:
            return {}
        out = {}
        for s in data.get("stat", []) or []:
            parts = s.get("name", "").split(">>>")
            if len(parts) >= 4 and parts[0] == "user":
                out[parts[1]] = out.get(parts[1], 0) + int(s.get("value", 0) or 0)
        return out

    def _default_iface(self):
        r = sh("ip", "-4", "route", "show", "default", check=False)
        f = r.stdout.split()
        return f[f.index("dev") + 1] if "dev" in f else "eth0"

    def load(self):
        cpu = os.getloadavg()[0] / max(os.cpu_count() or 1, 1)
        mem = 0.0
        try:
            info = {}
            with open("/proc/meminfo") as f:
                for line in f:
                    k, v = line.split(":", 1)
                    info[k] = int(v.split()[0])
            mem = 100.0 * (1 - info["MemAvailable"] / info["MemTotal"])
        except Exception:
            pass
        rx_bps = tx_bps = 0
        try:
            with open("/proc/net/dev") as f:
                for line in f:
                    if line.strip().startswith(self.default_iface + ":"):
                        v = line.split(":", 1)[1].split()
                        rx, tx = int(v[0]), int(v[8])
                        now = time.time()
                        if self.last_net:
                            dt = max(now - self.last_net[0], 1)
                            rx_bps = int((rx - self.last_net[1]) * 8 / dt)
                            tx_bps = int((tx - self.last_net[2]) * 8 / dt)
                        self.last_net = (now, rx, tx)
        except Exception:
            pass
        return {"cpu": round(cpu, 3), "mem": round(mem, 1), "rx_bps": max(rx_bps, 0), "tx_bps": max(tx_bps, 0)}

    def report(self):
        wg = [{"public_key": pk, "rx": p["rx"], "tx": p["tx"], "handshake": p["handshake"]}
              for pk, p in self.wg_dump().items()]
        for email, b in self.xray_stats().items():
            self.xray_pending[email] = self.xray_pending.get(email, 0) + b
        payload = {
            "wg": wg,
            "xray": [{"email": e, "bytes": b} for e, b in self.xray_pending.items() if b > 0],
            "load": self.load(),
            "agent_version": VERSION,
        }
        api_call(self.conf, "report", {"payload": payload})
        self.xray_pending.clear()

    # ---------------- main loop ----------------
    def run(self):
        threading.Thread(target=self.serve_poke, daemon=True).start()
        next_sync = next_report = 0.0
        while True:
            now = time.time()
            if now >= next_sync:
                try:
                    self.sync()
                except Exception as e:
                    log.error("sync failed: %s", e)
                next_sync = now + SYNC_INTERVAL
            if now >= next_report:
                try:
                    self.report()
                except Exception as e:
                    log.error("report failed: %s", e)
                next_report = now + REPORT_INTERVAL
            time.sleep(1)

    def serve_poke(self):
        agent = self
        state = {"last": 0.0}

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def _send(self, code, body):
                data = json.dumps(body).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_GET(self):
                if self.path == "/health":
                    self._send(200, {"ok": True, "version": VERSION, "last_sync": agent.last_sync_ok})
                else:
                    self._send(404, {"ok": False})

            def do_POST(self):
                if self.path != "/poke":
                    return self._send(404, {"ok": False})
                # The poke carries no data; it only triggers a pull from the API.
                if time.time() - state["last"] < 0.2:
                    time.sleep(0.2)
                state["last"] = time.time()
                try:
                    agent.sync()
                    self._send(200, {"ok": True})
                except Exception as e:
                    log.error("poke sync failed: %s", e)
                    self._send(500, {"ok": False})

        port = int(self.conf.get("agent_port", 8787))
        srv = ThreadingHTTPServer(("0.0.0.0", port), H)
        log.info("poke listener on :%d", port)
        srv.serve_forever()


# ----------------------------------------------------------------------------
# commands
# ----------------------------------------------------------------------------
def cmd_enroll(a):
    reality = load_json(REALITY_PATH, {})
    wg_pub = open(WG_PUBKEY_PATH).read().strip() if os.path.exists(WG_PUBKEY_PATH) else None
    ip = a.public_ip or public_ip()
    conf = {"api_url": a.api}
    res = api_call(conf, "enroll", {
        "token": a.token,
        "public_ip": ip,
        "wg_public_key": wg_pub,
        "wg_port": a.wg_port,
        "reality_public_key": reality.get("public_key"),
        "reality_short_id": reality.get("short_id"),
        "reality_sni": reality.get("sni"),
        "xray_port": a.xray_port,
        "agent_port": a.agent_port,
        "agent_version": VERSION,
    }, auth=False)
    conf.update({"node_id": res["node_id"], "secret": res["secret"], "agent_port": a.agent_port})
    write_json_atomic(CONF_PATH, conf)
    print("Enrolled as node %s (%s) with public IP %s" % (res.get("name"), res["node_id"], ip))


def cmd_run(_a):
    conf = load_json(CONF_PATH)
    if not conf or "secret" not in conf:
        sys.exit("not enrolled: run 'agent.py enroll' first")
    Agent(conf).run()


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("enroll")
    e.add_argument("--api", required=True, help="https://<project>.supabase.co/functions/v1")
    e.add_argument("--token", required=True)
    e.add_argument("--public-ip")
    e.add_argument("--wg-port", type=int, default=51820)
    e.add_argument("--xray-port", type=int, default=443)
    e.add_argument("--agent-port", type=int, default=8787)
    e.set_defaults(fn=cmd_enroll)
    r = sub.add_parser("run")
    r.set_defaults(fn=cmd_run)
    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
