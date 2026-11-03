#!/usr/bin/env bash
# =============================================================================
# YPN VPN node installer — Ubuntu 22.04 / 24.04 (Debian 12 also works)
#
# Installs WireGuard (standard node) + Xray VLESS/REALITY (stealth node),
# hardens forwarding, installs the YPN agent and enrolls the server with the
# control plane using a one-time token from the admin dashboard.
#
#   curl -fsSL https://ADMIN_SITE/install.sh | sudo bash -s -- \
#        --api https://PROJECT.supabase.co/functions/v1 --token ENROLL_TOKEN
#
# Options: --sni www.microsoft.com  --wg-port 51820  --xray-port 443
#          --agent-url https://ADMIN_SITE/agent.py   --public-ip x.x.x.x
# =============================================================================
set -euo pipefail

API=""; TOKEN=""; SNI="www.microsoft.com"; WG_PORT=51820; XRAY_PORT=443; AGENT_PORT=8787
AGENT_URL=""; PUBLIC_IP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api) API="$2"; shift 2;;
    --token) TOKEN="$2"; shift 2;;
    --sni) SNI="$2"; shift 2;;
    --wg-port) WG_PORT="$2"; shift 2;;
    --xray-port) XRAY_PORT="$2"; shift 2;;
    --agent-url) AGENT_URL="$2"; shift 2;;
    --public-ip) PUBLIC_IP="$2"; shift 2;;
    *) echo "Unknown option $1"; exit 1;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)."; exit 1; }
[[ -n "$API" && -n "$TOKEN" ]] || { echo "--api and --token are required"; exit 1; }
[[ -n "$AGENT_URL" ]] || AGENT_URL="${INSTALL_BASE_URL:-https://raw.githubusercontent.com/prabhathwicky-oss/VPN-/main/server}/agent.py"

log() { echo -e "\033[1;36m==>\033[0m $*"; }

# --------------------------------------------------------------------------- packages
log "Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -qq
apt-get install -y -qq wireguard-tools iptables iproute2 curl python3 openssl ca-certificates unzip jq >/dev/null

# --------------------------------------------------------------------------- kernel
log "Tuning kernel (forwarding, BBR)"
cat > /etc/sysctl.d/99-ypn.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
EOF
sysctl --system >/dev/null

DEF_IF=$(ip -4 route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
[[ -n "$DEF_IF" ]] || { echo "Could not detect default interface"; exit 1; }

# --------------------------------------------------------------------------- host firewall
# Oracle Cloud (and some other) Ubuntu images ship iptables rules that REJECT
# everything except SSH. Open our ports above that rule and persist them.
log "Opening ports $WG_PORT/udp, $XRAY_PORT/tcp, $AGENT_PORT/tcp in the host firewall"
open_port() {
  iptables -C INPUT -p "$1" --dport "$2" -j ACCEPT 2>/dev/null || iptables -I INPUT -p "$1" --dport "$2" -j ACCEPT
}
open_port udp "$WG_PORT"
open_port tcp "$XRAY_PORT"
open_port tcp "$AGENT_PORT"
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save >/dev/null 2>&1 || true
elif [[ -d /etc/iptables ]]; then
  iptables-save > /etc/iptables/rules.v4
fi

# --------------------------------------------------------------------------- WireGuard
log "Configuring WireGuard on :$WG_PORT"
mkdir -p /etc/wireguard && chmod 700 /etc/wireguard
if [[ ! -f /etc/wireguard/privatekey ]]; then
  (umask 077; wg genkey > /etc/wireguard/privatekey)
fi
wg pubkey < /etc/wireguard/privatekey > /etc/wireguard/publickey

# Rules are inserted (-I) so they sit above any provider default REJECT rule
# (Oracle Cloud images end the FORWARD chain with REJECT). Inserted in reverse:
# the last one inserted ends up first.
FW_UP="iptables -t nat -A POSTROUTING -s 10.66.0.0/16 -o $DEF_IF -j MASQUERADE"
FW_UP+="; iptables -I FORWARD -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
FW_UP+="; iptables -I FORWARD -i wg0 -j ACCEPT"
FW_UP+="; iptables -I FORWARD -i wg0 -p tcp --dport 25 -j DROP"
FW_UP+="; iptables -I FORWARD -i wg0 -d 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16,100.64.0.0/10 -j DROP"
FW_UP+="; iptables -I FORWARD -i wg0 -o wg0 -j DROP"
FW_UP+="; iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu"
FW_DOWN="${FW_UP//-A /-D }"; FW_DOWN="${FW_DOWN//-I /-D }"

cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.66.0.1/16
ListenPort = $WG_PORT
PrivateKey = $(cat /etc/wireguard/privatekey)
SaveConfig = false
PostUp = $FW_UP
PostDown = $FW_DOWN
EOF
chmod 600 /etc/wireguard/wg0.conf
systemctl enable wg-quick@wg0 >/dev/null 2>&1
systemctl restart wg-quick@wg0

# --------------------------------------------------------------------------- Xray
log "Installing Xray (VLESS + REALITY) on :$XRAY_PORT"
bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null
XRAY=/usr/local/bin/xray
mkdir -p /etc/ypn-agent && chmod 700 /etc/ypn-agent

if [[ ! -f /etc/ypn-agent/reality.json ]]; then
  KEYS=$($XRAY x25519)
  PRIV=$(echo "$KEYS" | awk -F': *' '/^Private/ {print $2; exit}')
  PUB=$(echo "$KEYS"  | awk -F': *' '/PublicKey|Public key|^Password/ {print $2; exit}')
  SID=$(openssl rand -hex 8)
  [[ -n "$PRIV" && -n "$PUB" ]] || { echo "Failed to generate REALITY keys"; echo "$KEYS"; exit 1; }
  jq -n --arg priv "$PRIV" --arg pub "$PUB" --arg sid "$SID" --arg sni "$SNI" \
     '{private_key:$priv, public_key:$pub, short_id:$sid, sni:$sni}' > /etc/ypn-agent/reality.json
  chmod 600 /etc/ypn-agent/reality.json
fi
PRIV=$(jq -r .private_key /etc/ypn-agent/reality.json)
SID=$(jq -r .short_id /etc/ypn-agent/reality.json)
SNI=$(jq -r .sni /etc/ypn-agent/reality.json)

# Keep existing clients if re-running the installer
EXISTING_CLIENTS='[]'
if [[ -f /usr/local/etc/xray/config.json ]]; then
  EXISTING_CLIENTS=$(jq -c '[.inbounds[]? | select(.tag=="vless-in") | .settings.clients[]?]' /usr/local/etc/xray/config.json 2>/dev/null || echo '[]')
fi

jq -n --arg priv "$PRIV" --arg sid "$SID" --arg sni "$SNI" --argjson port "$XRAY_PORT" \
      --argjson clients "$EXISTING_CLIENTS" '
{
  log: { loglevel: "warning", access: "none" },
  api: { tag: "api", listen: "127.0.0.1:10085", services: ["HandlerService", "StatsService"] },
  stats: {},
  policy: {
    levels: { "0": { statsUserUplink: true, statsUserDownlink: true, handshake: 4, connIdle: 300 } }
  },
  inbounds: [{
    tag: "vless-in", listen: "0.0.0.0", port: $port, protocol: "vless",
    settings: { clients: $clients, decryption: "none" },
    streamSettings: {
      network: "tcp", security: "reality",
      realitySettings: {
        show: false, target: ($sni + ":443"), xver: 0,
        serverNames: [$sni], privateKey: $priv, shortIds: [$sid]
      }
    },
    sniffing: { enabled: true, destOverride: ["http", "tls", "quic"] }
  }],
  outbounds: [
    { tag: "direct", protocol: "freedom" },
    { tag: "block", protocol: "blackhole" }
  ],
  routing: {
    domainStrategy: "AsIs",
    rules: [
      { type: "field", ip: ["geoip:private"], outboundTag: "block" },
      { type: "field", protocol: ["bittorrent"], outboundTag: "block" },
      { type: "field", port: "25", outboundTag: "block" }
    ]
  }
}' > /usr/local/etc/xray/config.json
chmod 644 /usr/local/etc/xray/config.json
$XRAY run -test -c /usr/local/etc/xray/config.json >/dev/null
systemctl enable xray >/dev/null 2>&1
systemctl restart xray

# --------------------------------------------------------------------------- agent
log "Installing YPN agent"
mkdir -p /opt/ypn-agent
if [[ -f "$(dirname "$0")/agent.py" ]]; then
  cp "$(dirname "$0")/agent.py" /opt/ypn-agent/agent.py
else
  [[ "$AGENT_URL" == http* ]] || { echo "Set --agent-url https://ADMIN_SITE/agent.py"; exit 1; }
  curl -fsSL "$AGENT_URL" -o /opt/ypn-agent/agent.py
fi
chmod 755 /opt/ypn-agent/agent.py

if [[ ! -f /etc/ypn-agent/config.json ]]; then
  log "Enrolling with control plane"
  ENROLL_ARGS=(--api "$API" --token "$TOKEN" --wg-port "$WG_PORT" --xray-port "$XRAY_PORT" --agent-port "$AGENT_PORT")
  [[ -n "$PUBLIC_IP" ]] && ENROLL_ARGS+=(--public-ip "$PUBLIC_IP")
  python3 /opt/ypn-agent/agent.py enroll "${ENROLL_ARGS[@]}"
fi

cat > /etc/systemd/system/ypn-agent.service <<EOF
[Unit]
Description=YPN VPN node agent
After=network-online.target wg-quick@wg0.service xray.service
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 /opt/ypn-agent/agent.py run
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable ypn-agent >/dev/null 2>&1
systemctl restart ypn-agent

# --------------------------------------------------------------------------- firewall (optional)
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow 22/tcp >/dev/null; ufw allow "$WG_PORT"/udp >/dev/null
  ufw allow "$XRAY_PORT"/tcp >/dev/null; ufw allow "$AGENT_PORT"/tcp >/dev/null
  ufw route allow in on wg0 out "$DEF_IF" >/dev/null
fi

log "Done. WireGuard :$WG_PORT/udp  •  VLESS-REALITY :$XRAY_PORT/tcp (SNI $SNI)  •  agent :$AGENT_PORT"
systemctl --no-pager --lines=0 status ypn-agent | head -3 || true
