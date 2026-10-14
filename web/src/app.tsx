import { useEffect, useState } from "preact/hooks";
import { Icon } from "./icons";
import { useSub, useTick } from "./hooks";
import { Page } from "./layout";
import { Dialogs, PinDialog, Toasts } from "./overlays";
import { connect, session, store } from "./state";
import { rememberHost, resolveHost } from "./session";
import { SysPages } from "./sys";

function useMedia(q: string) {
  const [m, setM] = useState(() => matchMedia(q).matches);
  useEffect(() => { const mq = matchMedia(q); const fn = () => setM(mq.matches); mq.addEventListener("change", fn); return () => mq.removeEventListener("change", fn); }, [q]);
  return m;
}

function HostPrompt({ onPick }: { onPick: (h: string) => void }) {
  const [h, setH] = useState("localhost:8080");
  return (
    <div class="modal-bg">
      <form class="modal" onSubmit={(e) => { e.preventDefault(); if (h) onPick(h); }}>
        <h3>Connect to a device</h3>
        <div class="hint">Host and port of an espFace device, e.g. 192.168.4.1 or localhost:8080 for the fake device.</div>
        <input class="field" value={h} onInput={(e) => setH((e.target as HTMLInputElement).value)} />
        <div class="actions"><button class="btn primary" type="submit">Connect</button></div>
      </form>
    </div>
  );
}

// Shown above the last known UI while the socket is down; the widgets stay visible and are refreshed on reconnect.
function Banner() {
  useSub("conn");
  useTick(1000);
  if (store.conn === "offline") {
    const left = Math.max(0, Math.ceil(((session?.ws.retryAt ?? 0) - Date.now()) / 1000));
    const why = store.busy ? "Device is full (too many clients)" : "Connection lost";
    return (
      <div class="banner err" data-reconnect={left}>
        {why}, reconnecting{left > 0 ? ` in ${left} s` : ""} <button class="link" onClick={() => session?.ws.reconnect(0)}>retry now</button>
      </div>
    );
  }
  if (store.conn === "connecting") return <div class="banner">Connecting to {session?.host}</div>;
  return null;
}

export function App() {
  useSub(["layout", "page", "device", "conn"]);
  const [host, setHost] = useState<string | null>(resolveHost);
  const [view, setView] = useState<"ui" | "sys">("ui");
  const [menu, setMenu] = useState(false);
  const wideScreen = useMedia("(min-width: 700px)");
  useEffect(() => { if (host) connect(host); }, [host]);
  if (!host) return <HostPrompt onPick={(h) => { rememberHost(h); setHost(h); }} />;

  const pages = store.pages();
  const current = pages.find((p) => p.id === store.page) ?? pages[0];
  const tabs = pages.length > 1 && view === "ui";
  const bottom = tabs && !wideScreen;
  const goto = (id: string) => session?.page(id);
  const d = store.device;

  return (
    <div class={bottom ? "has-bottomnav" : ""}>
      <header class="top">
        {view === "sys" ? <button class="iconbtn" onClick={() => setView("ui")} aria-label="back"><Icon name="arrow_back" /></button> : <span class={`dot ${store.conn}`} title={store.conn} />}
        <span class="title">{view === "sys" ? "System" : (d?.name ?? "espFace")}{view === "ui" && d?.proj ? <small>{d.proj}</small> : null}</span>
        {tabs && wideScreen && (
          <nav class="tabs">{pages.map((p) => <button key={p.id} class={p.id === current?.id ? "on" : ""} onClick={() => goto(p.id)}>{p.icon && <Icon name={p.icon} size={18} />}{p.lbl}</button>)}</nav>
        )}
        <button class="iconbtn" aria-label="menu" onClick={() => setMenu(!menu)}><Icon name="more_vert" /></button>
        {menu && (
          <div class="menu" onClick={() => setMenu(false)}>
            <button onClick={() => setView("ui")}><Icon name="home" /> Device UI</button>
            <button onClick={() => setView("sys")}><Icon name="settings" /> System and settings</button>
          </div>
        )}
      </header>
      <Banner />
      <main class="main">
        {view === "sys" ? <SysPages /> : current ? <Page page={current} /> : <p class="na" style="text-align:center">{store.conn === "ready" ? "This device has no widgets." : "Waiting for the device"}</p>}
      </main>
      {bottom && (
        <nav class="bottomnav">{pages.map((p) => <button key={p.id} class={p.id === current?.id ? "on" : ""} onClick={() => goto(p.id)}><Icon name={p.icon ?? "unknown"} size={22} />{p.lbl}</button>)}</nav>
      )}
      <Toasts /><Dialogs /><PinDialog />
    </div>
  );
}
