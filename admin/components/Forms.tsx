"use client";

import { useActionState, useState } from "react";
import {
  createNode, newEnrollToken, rotateNode, saveConfig, type CreateNodeResult,
} from "@/app/actions";

function Result({ state }: { state: CreateNodeResult | null }) {
  const [copied, setCopied] = useState(false);
  if (!state) return null;
  return (
    <div className={`callout ${state.ok ? "ok" : "bad"}`} style={{ marginTop: 12 }}>
      <div>{state.message}</div>
      {state.command && (
        <>
          <pre className="cmd">{state.command}</pre>
          <button
            type="button"
            className="btn sm"
            style={{ marginTop: 8 }}
            onClick={() => {
              navigator.clipboard.writeText(state.command!);
              setCopied(true);
            }}
          >
            {copied ? "Copied ✓" : "Copy command"}
          </button>
        </>
      )}
    </div>
  );
}

export function CreateNodeForm({
  regions, doEnabled,
}: { regions: { code: string; name: string }[]; doEnabled: boolean }) {
  const [state, action, pending] = useActionState(createNode, null);
  return (
    <form action={action} className="form">
      <div className="form-grid">
        <label>Name<input name="name" placeholder="sg-1 (optional)" /></label>
        <label>
          Region
          <select name="region_code" defaultValue={regions[0]?.code}>
            {regions.map((r) => <option key={r.code} value={r.code}>{r.name}</option>)}
          </select>
        </label>
        <label>
          Type
          <select name="kind" defaultValue="hybrid">
            <option value="hybrid">Hybrid (WireGuard + Stealth)</option>
            <option value="standard">Standard (WireGuard)</option>
            <option value="stealth">Stealth (VLESS/REALITY)</option>
          </select>
        </label>
        <label>
          Tier
          <select name="tier" defaultValue="all">
            <option value="all">Free + Pro</option>
            <option value="pro">Pro only (priority)</option>
          </select>
        </label>
        <label>Capacity (peers)<input name="capacity" type="number" defaultValue={250} min={10} /></label>
        <label>REALITY SNI<input name="reality_sni" defaultValue="www.microsoft.com" /></label>
        <label>
          Deploy with
          <select name="provider" defaultValue={doEnabled ? "digitalocean" : "manual"}>
            <option value="manual">My own server (install command)</option>
            <option value="digitalocean" disabled={!doEnabled}>
              DigitalOcean (automatic){doEnabled ? "" : " — set DO_API_TOKEN"}
            </option>
          </select>
        </label>
      </div>
      <div><button className="btn primary" disabled={pending}>{pending ? "Creating…" : "Add server"}</button></div>
      <Result state={state} />
    </form>
  );
}

export function RotateForm({ id, label = "Rotate IP" }: { id: string; label?: string }) {
  const [state, action, pending] = useActionState(rotateNode, null);
  return (
    <form action={action}>
      <input type="hidden" name="id" value={id} />
      <button className="btn" disabled={pending}
        onClick={(e) => { if (!confirm("Create a replacement server with a new IP and drain this one?")) e.preventDefault(); }}>
        {pending ? "Working…" : label}
      </button>
      <Result state={state} />
    </form>
  );
}

export function EnrollTokenForm({ id }: { id: string }) {
  const [state, action, pending] = useActionState(newEnrollToken, null);
  return (
    <form action={action}>
      <input type="hidden" name="id" value={id} />
      <button className="btn" disabled={pending}
        onClick={(e) => { if (!confirm("Generate a new install token? The current agent secret stops working.")) e.preventDefault(); }}>
        {pending ? "Working…" : "New install token"}
      </button>
      <Result state={state} />
    </form>
  );
}

export function ConfigEditor({ k, value, help }: { k: string; value: unknown; help: string }) {
  const [state, action, pending] = useActionState(saveConfig, null);
  return (
    <form action={action} className="card form">
      <div className="spread">
        <h2 style={{ margin: 0 }} className="mono">{k}</h2>
        <button className="btn primary sm" disabled={pending}>{pending ? "Saving…" : "Save"}</button>
      </div>
      <div className="muted">{help}</div>
      <input type="hidden" name="key" value={k} />
      <textarea name="value" defaultValue={JSON.stringify(value, null, 2)} spellCheck={false} />
      {state && <div className={`callout ${state.ok ? "ok" : "bad"}`}>{state.message}</div>}
    </form>
  );
}

export function ConfirmButton({
  children, message, className = "btn",
}: { children: React.ReactNode; message: string; className?: string }) {
  return (
    <button className={className} onClick={(e) => { if (!confirm(message)) e.preventDefault(); }}>
      {children}
    </button>
  );
}
