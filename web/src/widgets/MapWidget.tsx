import { useEffect, useRef, useState } from "preact/hooks";
import type { Widget } from "../proto/types";
import { useValue } from "../hooks";
import { Frame } from "./common";

const CDN = "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/";
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type L = any;
let leaflet: Promise<L> | null = null;

// Leaflet is only fetched when a map widget mounts; the bundle itself stays free of it.
function loadLeaflet(): Promise<L> {
  if (leaflet) return leaflet;
  return (leaflet = new Promise((resolve, reject) => {
    const css = document.createElement("link");
    css.rel = "stylesheet"; css.href = CDN + "leaflet.min.css";
    document.head.appendChild(css);
    const s = document.createElement("script");
    s.src = CDN + "leaflet.min.js";
    s.onload = () => resolve((window as unknown as { L: L }).L);
    s.onerror = () => { leaflet = null; reject(new Error("leaflet")); };
    document.head.appendChild(s);
  }));
}

export function MapWidget({ w }: { w: Widget }) {
  const v = useValue(w.id);
  const host = useRef<HTMLDivElement>(null);
  const map = useRef<L>(null);
  const layer = useRef<L>(null);
  const [failed, setFailed] = useState(false);
  const latest = useRef<(L: L) => void>(() => {});
  const pts = Array.isArray(v) ? (v as unknown[]).filter((p) => Array.isArray(p) && typeof p[0] === "number" && typeof p[1] === "number") as [number, number, string?][] : [];

  useEffect(() => {
    let alive = true;
    loadLeaflet().then((L) => {
      if (!alive || !host.current || map.current) return;
      map.current = L.map(host.current, { zoomControl: false });
      L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", { attribution: "&copy; OpenStreetMap", maxZoom: 19 }).addTo(map.current);
      layer.current = L.layerGroup().addTo(map.current);
      map.current.setView([0, 0], 2);
      latest.current(L);   // points may have arrived while Leaflet was loading
    }).catch(() => setFailed(true));
    return () => { alive = false; map.current?.remove(); map.current = null; };
  }, []);

  const update = (L: L) => {
    if (!map.current || !layer.current) return;
    layer.current.clearLayers();
    for (const p of pts) { const m = L.marker([p[0], p[1]]).addTo(layer.current); if (p[2]) m.bindPopup(String(p[2])); }
    if (pts.length === 1) map.current.setView([pts[0][0], pts[0][1]], w.zoom ?? 12);
    else if (pts.length > 1) map.current.fitBounds(pts.map((p) => [p[0], p[1]]), { padding: [20, 20] });
  };
  latest.current = update;
  useEffect(() => { const L = (window as unknown as { L?: L }).L; if (L) update(L); }, [JSON.stringify(pts), w.zoom]);

  return <Frame w={w}>{failed ? <div class="na">map unavailable (no internet)</div> : <div class="map" ref={host} />}</Frame>;
}
