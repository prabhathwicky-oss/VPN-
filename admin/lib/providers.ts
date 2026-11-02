// Cloud provider automation for 1-click node deploys and IP rotation.
import { FUNCTIONS_URL, SITE_URL } from "./supabase";

export function installCommand(token: string, sni: string): string {
  return `curl -fsSL ${SITE_URL}/install.sh | sudo bash -s -- --api ${FUNCTIONS_URL} --token ${token} --agent-url ${SITE_URL}/agent.py --sni ${sni}`;
}

function cloudInit(token: string, sni: string): string {
  return `#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
curl -fsSL ${SITE_URL}/install.sh -o /root/ypn-install.sh
bash /root/ypn-install.sh --api ${FUNCTIONS_URL} --token ${token} --agent-url ${SITE_URL}/agent.py --sni ${sni} > /var/log/ypn-install.log 2>&1
`;
}

export const doEnabled = () => Boolean(process.env.DO_API_TOKEN);

async function doFetch(path: string, init: RequestInit = {}) {
  const r = await fetch(`https://api.digitalocean.com/v2${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${process.env.DO_API_TOKEN}`,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
    cache: "no-store",
  });
  if (!r.ok && r.status !== 404) throw new Error(`DigitalOcean ${r.status}: ${await r.text()}`);
  return r.status === 204 || r.status === 404 ? null : r.json();
}

export async function doCreateDroplet(opts: { name: string; region: string; token: string; sni: string }) {
  const sshKeys = (process.env.DO_SSH_KEYS ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  const res = await doFetch("/droplets", {
    method: "POST",
    body: JSON.stringify({
      name: opts.name,
      region: opts.region,
      size: process.env.DO_DROPLET_SIZE || "s-1vcpu-1gb",
      image: "ubuntu-24-04-x64",
      ipv6: false,
      monitoring: true,
      tags: ["ypn-vpn"],
      ssh_keys: sshKeys.length ? sshKeys : undefined,
      user_data: cloudInit(opts.token, opts.sni),
    }),
  });
  return String(res?.droplet?.id ?? "");
}

export async function doDestroyDroplet(id: string) {
  if (!id) return;
  await doFetch(`/droplets/${id}`, { method: "DELETE" });
}
