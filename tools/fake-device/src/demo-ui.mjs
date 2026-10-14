// Demo UI using every widget type; values are the initial state.
export const widgets = [
  { id: "main", ty: "page", lbl: "Boiler", icon: "home" },
  { id: "io", ty: "page", lbl: "I/O", icon: "tune" },
  { id: "setup", ty: "page", lbl: "Setup", icon: "settings" },

  { id: "hdr", ty: "header", lbl: "Fake boiler" },
  { id: "sensors", ty: "group", lbl: "Sensors" },
  { id: "temp", ty: "gauge", lbl: "Temperature", min: 0, max: 120, unit: "°C", style: "round", zones: [{ from: 90, to: 120, color: "#ff0000" }], grp: "sensors", ro: true },
  { id: "tchart", ty: "chart", lbl: "Temp history", series: [{ id: "temp", lbl: "Temp", color: "#ff8800" }, { id: "target", lbl: "Target", color: "#0088ff" }], win: 600, unit: "°C", legend: true, vals: true, grp: "sensors" },
  { id: "level", ty: "progress", lbl: "Tank", min: 0, max: 100, grp: "sensors" },
  { id: "bal", ty: "progress", lbl: "Balance", min: -100, max: 100, center: true, grp: "sensors" },
  { id: "disp", ty: "display", lbl: "Pressure", digits: 5, unit: "bar", grp: "sensors" },
  { id: "ok", ty: "led", lbl: "OK", color: "#00ff00", grp: "sensors" },
  { id: "rgb", ty: "led", lbl: "Status", rgb: true, grp: "sensors" },
  { id: "now", ty: "clock", lbl: "Device time", fmt: "HH:mm:ss", grp: "sensors" },

  { id: "control", ty: "group", lbl: "Control" },
  { id: "r1", ty: "row", grp: "control" },
  { id: "pump", ty: "switch", lbl: "Pump", on: "ON", off: "OFF", row: "r1", size: 1, grp: "control" },
  { id: "target", ty: "slider", lbl: "Target", min: 20, max: 90, step: 1, unit: "°C", row: "r1", size: 3, grp: "control" },
  { id: "mode", ty: "select", lbl: "Mode", opts: ["Off", "Auto", "Manual"], style: "seg", grp: "control" },
  { id: "n", ty: "number", lbl: "Cycles", min: 0, max: 10, step: 1, spin: true, grp: "control" },
  { id: "r2", ty: "row", grp: "control" },
  { id: "reset", ty: "button", lbl: "Reset error", hint: "Clears the error latch", icon: "restart_alt", row: "r2", grp: "control" },
  { id: "erase", ty: "button", lbl: "Erase", color: "#ff0000", hint: "Opens a confirm dialog", row: "r2", grp: "control" },
  { id: "rename", ty: "button", lbl: "Rename", hint: "Opens a prompt dialog", row: "r2", grp: "control" },
  { id: "horn", ty: "button", lbl: "Horn", hold: true, color: "#ff8800", grp: "control" },
  { id: "term", ty: "log", lbl: "Log", rows: 8, cap: 200 },

  { id: "inputs", ty: "group", lbl: "Inputs", page: "io" },
  { id: "joy", ty: "joystick", lbl: "Valve", center: true, sq: true, grp: "inputs", page: "io" },
  { id: "pad", ty: "dpad", lbl: "Move", grp: "inputs", page: "io" },
  { id: "col", ty: "color", lbl: "Light", grp: "inputs", page: "io" },
  { id: "start", ty: "datetime", lbl: "Start", mode: "time", grp: "inputs", page: "io" },
  { id: "days", ty: "flags", lbl: "Days", opts: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"], grp: "inputs", page: "io" },
  { id: "tbl", ty: "table", lbl: "Zones", cols: [{ lbl: "Zone", w: 2, align: "left" }, { lbl: "°C", w: 1, align: "right" }], page: "io" },
  { id: "img", ty: "image", lbl: "Diagram", src: "https://upload.wikimedia.org/wikipedia/commons/thumb/4/47/PNG_transparency_demonstration_1.png/240px-PNG_transparency_demonstration_1.png", page: "io" },
  { id: "cam", ty: "stream", lbl: "Camera", src: "http://192.168.1.60:81/stream", page: "io" },
  { id: "pos", ty: "map", lbl: "Location", zoom: 14, page: "io" },

  { id: "help", ty: "textblock", text: "Set the target and enable the pump.\nThe horn button is momentary.", page: "setup" },
  { id: "name", ty: "text", lbl: "Name", maxlen: 32, re: "^[A-Za-z ]*$", page: "setup" },
  { id: "pw", ty: "text", lbl: "Password", maxlen: 64, secret: true, page: "setup" },
  { id: "notes", ty: "textarea", lbl: "Notes", maxlen: 512, rows: 4, page: "setup" },
  { id: "sp", ty: "spacer", size: [1, 16], page: "setup" },
];

export const initialValues = {
  temp: 42.0, level: 70, bal: 10, disp: 1.85, ok: true, rgb: 0x00ff00, now: Math.floor(Date.now() / 1000),
  pump: false, target: 60, mode: 1, n: 3,
  joy: [0, 0], col: 0xff8800, start: 6 * 3600, days: 0b0011111,
  tbl: [["Kitchen", 21.5], ["Bath", 23.0], ["Hall", 19.8]],
  pos: [[52.52, 13.405, "Boiler"]],
  name: "Boiler", pw: "", notes: "",
};

// --huge-ui: the demo UI plus `n` generated widgets (~100 KB of JSON at 400; the schema caps `w` at 500 entries).
export function hugeUi(n = 400) {
  const w = widgets.map((x) => ({ ...x }));
  const values = { ...initialValues };
  const kinds = ["label", "gauge", "switch", "slider", "number", "select", "led", "progress", "text", "display"];
  const perGroup = 20, perPage = 200;
  for (let i = 0; i < n; i++) {
    const page = `p${Math.floor(i / perPage)}`, grp = `g${Math.floor(i / perGroup)}`;
    if (i % perPage === 0) w.push({ id: page, ty: "page", lbl: `Bank ${Math.floor(i / perPage) + 1}`, icon: "memory" });
    if (i % perGroup === 0) w.push({ id: grp, ty: "group", lbl: `Group ${Math.floor(i / perGroup) + 1}`, page, fold: true });
    const id = `w${i}`, ty = kinds[i % kinds.length];
    const base = { id, ty, lbl: `Widget ${i} ${ty}`, grp, page, hint: `Generated widget number ${i}. Long help text so that the ui message of the load test reaches about a hundred kilobytes.` };
    switch (ty) {
      case "label": w.push({ ...base, unit: "V", fmt: "%.2f" }); values[id] = (i % 100) / 7; break;
      case "gauge": w.push({ ...base, min: 0, max: 100, unit: "%", style: ["arc", "round", "linear"][i % 3], zones: [{ from: 80, to: 100, color: "#ff0000" }] }); values[id] = i % 100; break;
      case "switch": w.push({ ...base, on: "ON", off: "OFF" }); values[id] = i % 2 === 0; break;
      case "slider": w.push({ ...base, min: 0, max: 255, step: 1 }); values[id] = i % 255; break;
      case "number": w.push({ ...base, min: -100, max: 100, step: 0.5, spin: true }); values[id] = (i % 200) - 100; break;
      case "select": w.push({ ...base, opts: ["Off", "Low", "Medium", "High", "Max"], style: i % 2 ? "seg" : "list" }); values[id] = i % 5; break;
      case "led": w.push({ ...base, color: "#00ff00" }); values[id] = i % 3 === 0; break;
      case "progress": w.push({ ...base, min: 0, max: 100 }); values[id] = i % 100; break;
      case "text": w.push({ ...base, maxlen: 32 }); values[id] = `value ${i}`; break;
      case "display": w.push({ ...base, digits: 5, unit: "rpm" }); values[id] = i * 3; break;
    }
  }
  return { widgets: w, values };
}

// Value validation per widget type: returns true when v is acceptable.
export function validValue(w, v) {
  const num = (x) => typeof x === "number" && Number.isFinite(x);
  const inRange = (x) => num(x) && x >= (w.min ?? 0) && x <= (w.max ?? 100);
  switch (w.ty) {
    case "switch": return typeof v === "boolean";
    case "slider": case "number": return inRange(v);
    case "text": return typeof v === "string" && v.length <= (w.maxlen ?? 64) && (!w.re || new RegExp(w.re).test(v));
    case "textarea": return typeof v === "string" && v.length <= (w.maxlen ?? 256);
    case "select": return Number.isInteger(v) && v >= 0 && v < w.opts.length;
    case "flags": return Number.isInteger(v) && v >= 0 && v < 2 ** w.opts.length;
    case "color": return Number.isInteger(v) && v >= 0 && v <= 0xffffff;
    case "datetime": return Number.isInteger(v) && v >= 0;
    case "joystick": return Array.isArray(v) && v.length === 2 && v.every((x) => num(x) && x >= -100 && x <= 100);
    default: return false;
  }
}
