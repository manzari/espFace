import { useEffect, useState } from "preact/hooks";
import { Icon } from "./icons";
import { useSub, useTick } from "./hooks";
import { session, store } from "./state";
import type { Toast } from "./store";

function ToastItem({ t }: { t: Toast }) {
  useEffect(() => { const h = setTimeout(() => store.removeToast(t.id), t.lvl === "err" ? 7000 : 4000); return () => clearTimeout(h); }, [t.id]);
  return (
    <div class={`toast ${t.lvl}`} role="status">
      <Icon name={t.lvl === "err" ? "error" : t.lvl === "warn" ? "warning" : "info"} />
      <span>{t.msg}</span>
      <button class="iconbtn" onClick={() => store.removeToast(t.id)}><Icon name="close" size={16} /></button>
    </div>
  );
}

export function Toasts() {
  useSub("toast");
  return <div class="toasts">{store.toasts.map((t) => <ToastItem key={t.id} t={t} />)}</div>;
}

// Device dialogs: one at a time, oldest first; a timeout closes it as "cancel" (the device does the same).
export function Dialogs() {
  useSub("dlg");
  useTick(1000);
  const d = store.dialogs[0];
  const [v, setV] = useState("");
  useEffect(() => { setV(d?.def ?? ""); }, [d?.id]);
  if (!d) return null;
  const left = Math.max(0, Math.ceil((d.at + d.timeout * 1000 - Date.now()) / 1000));
  if (left === 0) { store.closeDialog(d.id); return null; }
  const answer = (ok: boolean) => session?.dlg(d.id, ok, d.kind === "prompt" ? v : undefined);
  return (
    <div class="modal-bg" data-dlg={d.id}>
      <form class="modal" onSubmit={(e) => { e.preventDefault(); answer(true); }}>
        <h3>{d.title ?? (d.kind === "prompt" ? "Input" : "Confirm")}</h3>
        <div>{d.msg}</div>
        {d.kind === "prompt" && <input class="field" value={v} autoFocus onInput={(e) => setV((e.target as HTMLInputElement).value)} />}
        <div class="hint">closes in {left} s</div>
        <div class="actions">
          <button type="button" class="btn" onClick={() => answer(false)}>Cancel</button>
          <button type="submit" class="btn primary">OK</button>
        </div>
      </form>
    </div>
  );
}

// Pairing: shown while the device wants a PIN or is locked out.
export function PinDialog() {
  useSub(["conn", "device"]);
  useTick(1000);
  const [pin, setPin] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => { setBusy(false); }, [store.version("conn")]);
  if (store.conn !== "pin" && store.conn !== "locked") return null;
  const locked = store.conn === "locked";
  const lockLeft = Math.max(0, Math.ceil((store.lockUntil - Date.now()) / 1000));
  const left = store.authLeft;
  return (
    <div class="modal-bg">
      <form class="modal" data-pin onSubmit={(e) => { e.preventDefault(); if (pin && !busy) { setBusy(true); void session?.submitPin(pin); } }}>
        <h3><Icon name="lock" /> {store.device?.name ?? "Device"} asks for a PIN</h3>
        {locked ? <div class="err">Too many wrong attempts. Locked for {lockLeft} s.</div> : (
          <>
            <input class="field" type="password" inputMode="numeric" autoComplete="off" autoFocus value={pin} placeholder="PIN" disabled={busy} onInput={(e) => setPin((e.target as HTMLInputElement).value)} />
            {left !== undefined && <div class="err">Wrong PIN, {left} attempt{left === 1 ? "" : "s"} left</div>}
            <div class="hint">The PIN is set in the device sketch. It never leaves this browser.</div>
            <div class="actions"><button type="submit" class="btn primary" disabled={!pin || busy}>{busy ? "Checking" : "Pair"}</button></div>
          </>
        )}
      </form>
    </div>
  );
}

// Local confirm for client-side actions (reboot, revoke); device dialogs use Dialogs above.
export function Confirm({ title, msg, onClose }: { title: string; msg: string; onClose: (ok: boolean) => void }) {
  return (
    <div class="modal-bg">
      <div class="modal">
        <h3>{title}</h3>
        <div>{msg}</div>
        <div class="actions">
          <button class="btn" onClick={() => onClose(false)}>Cancel</button>
          <button class="btn danger" onClick={() => onClose(true)}>OK</button>
        </div>
      </div>
    </div>
  );
}
