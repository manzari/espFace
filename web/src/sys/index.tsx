import { useEffect, useState } from "preact/hooks";
import { Icon } from "./../icons";
import { useSub } from "../hooks";
import { session, store } from "../state";
import { Confirm } from "../overlays";
import { hms } from "../widgets/Log";
import { loadTheme, saveTheme, type Theme } from "../theme";

const fmtUp = (ms?: number) => { if (ms === undefined) return "-"; const s = Math.floor(ms / 1000); const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60); return `${d ? d + "d " : ""}${h}h ${m}m ${s % 60}s`; };
const kb = (n?: number) => (n === undefined ? "-" : `${(n / 1024).toFixed(1)} KB`);

function Section({ title, icon, children }: { title: string; icon: string; children: preact.ComponentChildren }) {
  return <section class="card"><h3><Icon name={icon} /> {title}</h3>{children}</section>;
}

const NotAvailable = ({ what }: { what: string }) => <p class="na">{what} not available on this device.</p>;

function Info() {
  useSub(["sys:info", "device"]);
  useEffect(() => { session?.sys("info"); }, []);
  const d = store.device, i = store.sysInfo;
  if (!store.hasCap("info")) return <Section title="Device" icon="info"><NotAvailable what="Device info" /></Section>;
  return (
    <Section title="Device" icon="info">
      <dl class="kv">
        <dt>Name</dt><dd>{d?.name} <small style="color:var(--muted)">{d?.id}</small></dd>
        {d?.proj && <><dt>Project</dt><dd>{d.proj}</dd></>}
        <dt>Firmware</dt><dd>{i?.fw ?? d?.fw ?? "-"}</dd>
        {i?.repo && <><dt>Repository</dt><dd><a href={`https://github.com/${i.repo}`} target="_blank" rel="noreferrer">{i.repo}</a></dd></>}
        {i?.about && <><dt>About</dt><dd>{i.about}</dd></>}
        <dt>Chip</dt><dd>{i?.chip ?? "-"}</dd>
        <dt>Reboot reason</dt><dd>{i?.rr ?? "-"}</dd>
        <dt>Heap</dt><dd>{kb(i?.heap)} free, min {kb(i?.heapmin)}</dd>
        <dt>Uptime</dt><dd>{fmtUp(i?.up)}</dd>
        <dt>Time</dt><dd>{i?.time ? new Date(i.time * 1000).toLocaleString() : "not set"}</dd>
        <dt>Clients</dt><dd>{i?.clients ?? "-"}</dd>
        <dt>Protocol</dt><dd>v{d?.v} · caps {d?.caps?.join(", ") || "none"}</dd>
      </dl>
      <button class="btn" onClick={() => session?.sys("info")}>Refresh</button>
    </Section>
  );
}

function Wifi() {
  useSub(["sys:wifi.status", "sys:info"]);
  const has = store.hasCap("wifi");
  useEffect(() => { if (has) session?.sys("wifi.status"); }, [has]);
  const w = store.wifi, i = store.sysInfo;
  return (
    <Section title="WiFi" icon="wifi">
      {has ? (
        <dl class="kv">
          <dt>State</dt><dd>{w?.st ?? "-"}</dd>
          <dt>SSID</dt><dd>{w?.ssid ?? i?.ssid ?? "-"}</dd>
          <dt>IP</dt><dd>{w?.ip ?? i?.ip ?? "-"}</dd>
          <dt>RSSI</dt><dd>{w?.rssi ?? i?.rssi ?? "-"} dBm</dd>
          <dt>MAC</dt><dd>{i?.mac ?? "-"}</dd>
        </dl>
      ) : <NotAvailable what="WiFi status" />}
      <p class="na">WiFi provisioning (scan and join) arrives in phase 4.</p>
    </Section>
  );
}

function Security() {
  const [pin, setPin] = useState("");
  const [ask, setAsk] = useState(false);
  if (!store.hasCap("pin")) return <Section title="Security" icon="lock"><NotAvailable what="PIN management" /></Section>;
  const valid = pin === "" || (pin.length >= 4 && pin.length <= 32);
  return (
    <Section title="Security" icon="lock">
      <p>Current auth: {store.device?.auth === "pin" ? "PIN required" : "open"}. Changing the PIN or revoking drops every paired client, including this one.</p>
      <form class="inline" onSubmit={(e) => { e.preventDefault(); if (!valid) return; session?.forget(); session?.sys("pin.set", { pin }); setPin(""); }}>
        <input class={`field ${valid ? "" : "bad"}`} type="password" autoComplete="new-password" placeholder="New PIN (empty disables)" value={pin} onInput={(e) => setPin((e.target as HTMLInputElement).value)} />
        <button class="btn primary" style="width:auto" type="submit" disabled={!valid}>Set</button>
      </form>
      <button class="btn danger" onClick={() => setAsk(true)}>Revoke all pairings</button>
      {ask && <Confirm title="Revoke" msg="Delete all session tokens on the device?" onClose={(ok) => { setAsk(false); if (ok) { session?.forget(); session?.sys("revoke"); } }} />}
    </Section>
  );
}

function Reboot() {
  const [ask, setAsk] = useState(false);
  if (!store.hasCap("reboot")) return <Section title="Reboot" icon="power"><NotAvailable what="Reboot" /></Section>;
  return (
    <Section title="Reboot" icon="power">
      <button class="btn danger" onClick={() => setAsk(true)}>Reboot device</button>
      {ask && <Confirm title="Reboot" msg="Reboot the device now?" onClose={(ok) => { setAsk(false); if (ok) session?.sys("reboot"); }} />}
    </Section>
  );
}

function Ota() {
  const has = store.hasCap("ota") || store.hasCap("otaurl");
  return (
    <Section title="Firmware update" icon="upload">
      {has ? <p class="na">OTA upload and update by URL arrive in phase 4.</p> : <NotAvailable what="OTA" />}
    </Section>
  );
}

function Console() {
  useSub("console");
  return (
    <Section title="Console" icon="terminal">
      {store.console.length ? <div class="log" style="max-height:14rem">{store.console.map((l, i) => <div key={i} style={l.c ? `color:${l.c}` : ""}><span class="ts">{hms(l.ts)}</span>{l.msg}</div>)}</div> : <p class="na">No device log lines yet.</p>}
    </Section>
  );
}

function Appearance() {
  const [t, setT] = useState<Theme>(loadTheme());
  const upd = (p: Partial<Theme>) => { const n = { ...t, ...p }; setT(n); saveTheme(n); };
  return (
    <Section title="Appearance" icon="palette">
      <div class="themegrid">
        <span>Theme</span>
        <div class="seg">{(["auto", "light", "dark"] as const).map((m) => <button key={m} class={t.mode === m ? "on" : ""} onClick={() => upd({ mode: m })}>{m}</button>)}</div>
        <span>Accent</span>
        <input type="color" class="color" value={t.accent} onInput={(e) => upd({ accent: (e.target as HTMLInputElement).value })} />
        <span>Font size</span>
        <input type="range" class="slider" min="0.8" max="1.4" step="0.05" value={t.scale} onInput={(e) => upd({ scale: +(e.target as HTMLInputElement).value })} />
        <span>Wide layout</span>
        <label class={`switch ${t.wide ? "on" : ""}`}><input type="checkbox" checked={t.wide} style="position:absolute;opacity:0;width:0;height:0" onChange={(e) => upd({ wide: (e.target as HTMLInputElement).checked })} /><span class="track" /></label>
      </div>
    </Section>
  );
}

function Connection() {
  return (
    <Section title="Connection" icon="bolt">
      <dl class="kv"><dt>Device</dt><dd>{session?.host}</dd></dl>
      <button class="btn" onClick={() => { session?.forget(); session?.ws.reconnect(); }}>Forget pairing and reconnect</button>
    </Section>
  );
}

export function SysPages() {
  return (
    <div class="blocks">
      <Info /><Wifi /><Security /><Reboot /><Ota /><Console /><Appearance /><Connection />
    </div>
  );
}
