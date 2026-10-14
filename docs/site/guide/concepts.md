# Concepts

## The device describes, the clients render

The sketch builds a list of widgets. When a client connects and authenticates, the device sends one `ui` message with the whole description and a revision number `rev`, followed by an `upd` message with every current value. Clients draw what they are told and ignore unknown widget types, props and messages, so a newer firmware never breaks an older app.

`rev` increases on every rebuild. A client that has the same `rev` cached may skip parsing the `ui` but still applies the following `upd`.

## Layout: pages, groups, rows, widgets

```cpp
Ui& ui = face.ui();
ui.page("main", "Boiler").icon("home");
ui.group("control", "Control");
ui.row("r1").group("control");
ui.sw("pump", "Pump").row("r1").size(1).group("control");
ui.slider("target", "Target", 20, 90, 1, "°C").row("r1").size(3).group("control");
ui.spacer("sp", 1, 16);
```

- Layout is pages, then group cards, then rows, then widgets, always in declaration order.
- Widgets declared after `page()` belong to that page. `.page(id)` overrides this explicitly.
- `group(id, lbl)` creates a card; widgets join it with `.group(id)`. Groups can start folded with `.fold()`.
- `row(id)` places widgets side by side; `.row(id).size(w)` sets the relative width (default 1). `.size(w, h)` also fixes the height in pixels.
- A `group`, `page` or `row` must be declared before the widgets that reference it.
- Page, fold and scroll state live in the client, not on the device.

## Values and props

A widget has a value (what the user sets or the sketch shows) and props (its look and limits).

- **Values** travel in `upd` (device to client) and `set` (client to device). The sketch writes them with `face.set(id, v)` and reads user input through `onChange` or `bind`. `upd` messages are batched, at most one per 100 ms per client.
- **Props** such as label, color, range or options are static. Change them at runtime without a rebuild:

```cpp
face.ui().prop("temp").color("#ff0000").label("Temperature (HOT)");
face.ui().show("reset", true);
```

- Structural changes (adding or removing widgets) need `face.ui().rebuild()`, which bumps `rev` and resends the UI to all clients.

## Persisted inputs

`.persist()` stores an input in NVS under the widget id and restores it before `setup()` returns. `onChange` fires once with the restored value. Because the id doubles as the NVS key, ids are limited to 15 characters (`A-Za-z0-9_`). Each UI has its own NVS namespace, `efv_<ui name>` (`efv_main` for `face.ui()`; names over 11 characters are hashed), so a widget id like `pin` or `ssid` never touches the library's settings in the `espface` namespace, and two UIs can persist the same id independently. Renaming a UI starts it with empty values.

```cpp
ui.slider("target", "Target", 20, 90, 1, "°C").persist().onChange([](float v) { target = v; });
```

## Bind helpers

`.bind(var)` keeps a `bool`, `int`, `float` or string variable in sync with the widget in both directions.

```cpp
bool pump = false;
ui.sw("pump", "Pump").bind(pump);
```

## Dialogs

```cpp
face.ui().confirm("d1", "Erase all stored data?", [](bool ok, const Str&) {
  if (ok) face.toast("warn", "Erased");
}, "Erase");
face.ui().prompt("d2", "New name", [](bool ok, const Str& v) { if (ok) face.set("state", v.c_str()); }, "idle");
```

The device sends the dialog to every connected client. The first answer wins and the device closes the dialog on all others. Without an answer it closes after the timeout (default 60 s) and counts as `ok:false`.

## Multiple UIs

A second, independent UI can be bound to one transport, for example an open setup UI on BLE while the main UI stays on WiFi:

```cpp
face.setPin("1234");
Ui& setup = face.addUi("setup");
setup.pin("");              // no PIN on this UI
face.ble().use(setup);      // needs -DESPFACE_BLE
setup.header("WiFi setup");
```

By default all transports serve `face.ui()`. `ui.pin("")` disables the PIN for that UI, `ui.pin("9999")` sets its own. The `Provisioning` example shows the full pattern.

## Transports and security

WiFi WebSocket is on by default; BLE, serial and Bluetooth Classic are added with one call each and share the same session logic. See [Transports](/guide/transports). The protocol has no encryption and relies on a trusted network; the PIN is checked by challenge-response. See [Security model](/guide/security).

## Active page filtering

A client tells the device which page it shows (`page` message). The device may omit `upd` values for widgets on other pages for that client and sends a full `upd` of the page's widgets on each page change. Chart points, log lines, toasts, dialogs and prop changes are always sent.

## Time

- Timestamps in chart points and log lines are milliseconds. A value below 2^40 is device uptime and the client converts it to wall time using the `up` field of the device hello. A value of 2^40 or above is unix milliseconds.
- After a successful hello the client sends a `time` message with its clock and timezone offset. The device uses it when it has no better source.
- With `face.enableNtp(true, ...)` the device syncs itself. `face.time()` returns unix seconds from NTP, else the last client clock, else 0. `face.setTime(unix)` feeds an external RTC.
- `clock` widgets get the device time pushed every minute.
