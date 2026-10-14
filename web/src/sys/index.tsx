import { useEffect, useRef, useState } from "preact/hooks";
import { Icon } from "./../icons";
import { useSub } from "../hooks";
import { session, store } from "../state";
import { Confirm } from "../overlays";
import { hms } from "../widgets/Log";
import { loadTheme, saveTheme, type Theme } from "../theme";
import { md5hex } from "../proto/md5";
import { RENDERER_PROTOCOL, RENDERER_VERSION } from "../version";
import { compareVersions, pickRelease, pushImage, releaseUrl, type ReleaseInfo } from "./ota";

const fmtUp = (ms?: number) => { if (ms === undefined) return "-"; const s = Math.floor(ms / 1000); const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60); return `${d ? d + "d " : ""}${h}h ${m}m ${s % 60}s`; };
const kb = (n?: number) => (n === undefined ? "-" : `${(n / 1024).toFixed(1)} KB`);
const bars = (rssi: number) => "▂▄▆█".slice(0, rssi >= -55 ? 4 : rssi >= -65 ? 3 : rssi >= -75 ? 2 : 1);
const RR: Record<string, string> = { ota: "firmware update", button: "reset button", panic: "crash (panic)", power: "power on", wdt: "watchdog", sw: "software reset", brownout: "brownout", other: "other" };

function Section({ title, icon, children }: { title: string; icon: string; children: preact.ComponentChildren }) {
  return <section class="card"><h3><Icon name={icon} /> {title}</h3>{children}</section>;
}

const NotAvailable = ({ what }: { what: string }) => <p class="na">{what} not available on this device.</p>;

// User-triggered GitHub release check; off until the button is pressed so the page stays offline by default.
function ReleaseCheck({ repo, fw }: { repo: string; fw?: string }) {
  const [state, setState] = useState<{ busy?: boolean; rel?: ReleaseInfo; err?: string } | null>(null);
  const check = async () => {
    setState({ busy: true });
    try {
      const r = await fetch(releaseUrl(repo), { headers: { Accept: "application/vnd.github+json" } });
      if (!r.ok) throw new Error(`GitHub answered ${r.status}`);
      const rel = pickRelease(await r.json());
      if (!rel) throw new Error("no release found");
      setState({ rel });
    } catch (e) { setState({ err: (e as Error).message }); }
  };
  const rel = state?.rel;
  const newer = rel && fw ? compareVersions(rel.version, fw) > 0 : false;
  return (
    <div class="release">
      <button class="btn" disabled={state?.busy} onClick={check}>{state?.busy ? "Checking" : "Check for updates on GitHub"}</button>
      {state?.err && <p class="err">{state.err}</p>}
      {rel && (
        <p>
          Latest release: <b>{rel.version}</b>{fw ? (newer ? " (newer than " + fw + ")" : " (up to date)") : ""}
          {rel.page && <> · <a href={rel.page} target="_blank" rel="noreferrer">release notes</a></>}
          {newer && rel.url && store.hasCap("otaurl") && <> · <button class="btn primary" style="width:auto;margin-left:6px" onClick={() => { if (confirm(`Install ${rel.asset} on the device?`)) session?.sys("ota.url", { url: rel.url }); }}>Install {rel.asset}</button></>}
          {newer && !rel.url && " · no .bin asset in this release"}
        </p>
      )}
    </div>
  );
}

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
        <dt>Last reboot</dt><dd data-rr={i?.rr}>{i?.rr ? `${RR[i.rr] ?? i.rr} (${i.rr})` : "-"}</dd>
        <dt>Heap</dt><dd>{kb(i?.heap)} free, min {kb(i?.heapmin)}</dd>
        <dt>Uptime</dt><dd>{fmtUp(i?.up)}</dd>
        <dt>Time</dt><dd>{i?.time ? new Date(i.time * 1000).toLocaleString() : "not set"}</dd>
        <dt>Network</dt><dd>{i?.ssid ? `${i.ssid}${i.rssi !== undefined ? ` ${i.rssi} dBm` : ""}` : "-"}{i?.ip ? ` · ${i.ip}` : ""}</dd>
        <dt>MAC</dt><dd>{i?.mac ?? "-"}</dd>
        <dt>Clients</dt><dd>{i?.clients ?? "-"}</dd>
        <dt>Protocol</dt><dd>v{d?.v} · caps {d?.caps?.join(", ") || "none"}</dd>
      </dl>
      <button class="btn" onClick={() => session?.sys("info")}>Refresh</button>
      {i?.repo && <ReleaseCheck repo={i.repo} fw={i.fw ?? d?.fw} />}
    </Section>
  );
}

function Wifi() {
  useSub(["sys:wifi.status", "sys:wifi.scan", "sys:info", "device", "conn"]);
  const has = store.hasCap("wifi");
  const [ssid, setSsid] = useState("");
  const [pass, setPass] = useState("");
  const [show, setShow] = useState(false);
  const [scanning, setScanning] = useState(false);
  useEffect(() => { if (has && store.conn === "ready") session?.sys("wifi.status"); }, [has, store.conn]);
  useEffect(() => { setScanning(false); }, [store.wifiScan]);
  const w = store.wifi, i = store.sysInfo;
  if (!has) return <Section title="WiFi" icon="wifi"><NotAvailable what="WiFi" /></Section>;
  const st = w?.st;
  const stText = st === "connected" ? "connected" : st === "connecting" ? "connecting…" : st === "ap" ? "access point (not connected to a network)" : st === "failed" ? "connection failed" : "-";
  const scan = () => { if (session?.sys("wifi.scan")) { setScanning(true); store.wifiScan = null; } };
  const join = (e: Event) => { e.preventDefault(); if (!ssid) return; session?.sys("wifi.set", { ssid, pass }); setPass(""); };
  return (
    <Section title="WiFi" icon="wifi">
      <dl class="kv">
        <dt>State</dt><dd data-wifi={st}>{stText}</dd>
        <dt>Network</dt><dd>{w?.ssid ?? i?.ssid ?? "-"}{w?.rssi !== undefined ? ` ${w.rssi} dBm ${bars(w.rssi)}` : ""}</dd>
        <dt>IP</dt><dd>{w?.ip ?? i?.ip ?? "-"}</dd>
      </dl>
      <p>Join a network: scan, pick one and enter its password. The device stores the credentials and reconnects on boot; if it fails it reopens its access point.</p>
      <button class="btn" onClick={scan} disabled={scanning}>{scanning ? "Scanning…" : "Scan networks"}</button>
      {store.wifiScan && (store.wifiScan.length ? (
        <div class="list" data-scan>
          {store.wifiScan.map((ap) => (
            <button key={ap.ssid} type="button" class={ap.ssid === ssid ? "on" : ""} onClick={() => setSsid(ap.ssid)}>
              <Icon name="wifi" size={18} /> {ap.ssid} {ap.enc && <Icon name="lock" size={14} />}
              <span class="rssi">{bars(ap.rssi)} {ap.rssi} dBm</span>
            </button>
          ))}
        </div>
      ) : <p class="na">No networks found.</p>)}
      <form class="blocks" data-wifi-form onSubmit={join} style="gap:8px">
        <input class="field" placeholder="SSID" value={ssid} maxLength={32} onInput={(e) => setSsid((e.target as HTMLInputElement).value)} />
        <div class="inline">
          <input class="field" type={show ? "text" : "password"} placeholder="Password (empty for open networks)" autoComplete="off" maxLength={64} value={pass} onInput={(e) => setPass((e.target as HTMLInputElement).value)} />
          <button type="button" class="iconbtn" aria-label="show password" onClick={() => setShow(!show)}><Icon name={show ? "visibility_off" : "visibility"} /></button>
        </div>
        <button class="btn primary" type="submit" disabled={!ssid || st === "connecting"}>Connect</button>
      </form>
      {st === "ap" && <p class="na">You are connected to the device's own access point; after it joins a network this page will lose the connection. Reconnect via the new IP or the app.</p>}
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
      {ask && <Confirm title="Reboot" msg="Reboot the device now? Clients reconnect automatically." onClose={(ok) => { setAsk(false); if (ok) session?.sys("reboot"); }} />}
    </Section>
  );
}

type OtaPhase = "idle" | "hashing" | "begin" | "sending" | "verifying";

// Push: file -> md5 -> ota.begin -> binary frames with backpressure -> device ota.progress/ota.done. URL: ota.url.
function Ota() {
  useSub(["sys:ota", "device", "conn"]);
  const push = store.hasCap("ota"), byUrl = store.hasCap("otaurl");
  const [file, setFile] = useState<{ name: string; data: Uint8Array; md5: string } | null>(null);
  const [phase, setPhase] = useState<OtaPhase>("idle");
  const [sent, setSent] = useState(0);
  const [url, setUrl] = useState("");
  const abort = useRef(false);
  const o = store.ota;
  useEffect(() => { if (o?.done) setPhase("idle"); }, [o]);
  const busy = phase !== "idle" || (!!o && !o.done);

  const pick = async (e: Event) => {
    const f = (e.target as HTMLInputElement).files?.[0];
    if (!f) return;
    setPhase("hashing");
    const data = new Uint8Array(await f.arrayBuffer());
    setFile({ name: f.name, data, md5: md5hex(data) });
    setPhase("idle");
  };

  const waitBegin = () => new Promise<boolean>((resolve) => {
    const off = store.subscribe("sys:ota", () => { const s = store.lastSys, err = store.ota?.done && store.ota.ok === false; if (err || (s?.cmd === "ota.begin" && typeof s.ok === "boolean")) { off(); resolve(!err && s?.ok === true); } });
    setTimeout(() => { off(); resolve(false); }, 10000);
  });

  const upload = async () => {
    if (!file || !session) return;
    abort.current = false; setSent(0);
    store.ota = { pct: 0 }; store.emit("sys:ota");
    setPhase("begin");
    session.sys("ota.begin", { size: file.data.length, md5: file.md5, kind: "fw" });
    if (!(await waitBegin())) { setPhase("idle"); if (!store.ota?.done) { store.ota = { pct: 0, done: true, ok: false, msg: "device did not accept the update" }; store.emit("sys:ota"); } return; }
    setPhase("sending");
    try {
      await pushImage({ sendBinary: (b) => session!.sendBinary(b), bufferedAmount: () => session!.bufferedAmount() }, file.data, { onProgress: (n) => setSent(n), aborted: () => abort.current || store.conn !== "ready" });
      setPhase("verifying");
    } catch (e) {
      setPhase("idle");
      if (abort.current) session.sys("ota.abort");
      store.ota = { pct: 0, done: true, ok: false, msg: (e as Error).message }; store.emit("sys:ota");
    }
  };

  const cancel = () => { abort.current = true; if (phase === "idle" && o && !o.done) { session?.sys("ota.abort"); store.ota = null; store.emit("sys:ota"); } };
  const pct = file && phase === "sending" ? Math.max(o?.pct ?? 0, Math.floor((sent * 100) / file.data.length)) : o?.pct ?? 0;
  const status = o?.done ? (o.ok ? "Update installed, the device is rebooting." : `Update failed: ${o.msg ?? "unknown error"}`) : phase === "hashing" ? "Reading file…" : phase === "begin" ? "Waiting for the device…" : phase === "sending" ? `Uploading ${pct}%` : phase === "verifying" ? "Verifying…" : o && !o.done ? `Device progress ${o.pct}%` : "";

  if (!push && !byUrl) return <Section title="Firmware update" icon="upload"><NotAvailable what="OTA" /></Section>;
  return (
    <Section title="Firmware update" icon="upload">
      {push ? (
        <>
          <p>Upload a firmware image (`.bin` built for this board). The device verifies the MD5 and reboots into the new firmware.</p>
          <input class="field" type="file" accept=".bin,application/octet-stream" data-ota-file disabled={busy} onChange={pick} />
          {file && <p>{file.name}: {kb(file.data.length)}, md5 <code>{file.md5}</code></p>}
          <div class="inline">
            <button class="btn primary" data-ota-upload disabled={!file || busy} onClick={upload}>Upload and install</button>
            {busy && <button class="btn danger" style="width:auto" onClick={cancel}>Cancel</button>}
          </div>
        </>
      ) : <p class="na">Push upload is not available on this transport.</p>}
      {byUrl && (
        <form class="inline" onSubmit={(e) => { e.preventDefault(); if (!url || busy) return; store.ota = { pct: 0 }; store.emit("sys:ota"); session?.sys("ota.url", { url }); }}>
          <input class="field" type="url" placeholder="https://example.com/firmware.bin" value={url} disabled={busy} onInput={(e) => setUrl((e.target as HTMLInputElement).value)} />
          <button class="btn" style="width:auto" type="submit" disabled={!/^https?:\/\//.test(url) || busy}>Install from URL</button>
        </form>
      )}
      {(busy || o) && (
        <div data-ota-status data-ok={o?.done ? String(!!o.ok) : undefined}>
          <div class="bar"><div class="fill" style={`width:${pct}%`} /></div>
          <p class={o?.done && !o.ok ? "err" : ""}>{status}</p>
        </div>
      )}
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
      <footer class="ver" data-renderer-version={RENDERER_VERSION}>espFace web renderer {RENDERER_VERSION} · protocol v{RENDERER_PROTOCOL}</footer>
    </div>
  );
}
