# espFace firmware library

Arduino library for ESP32 (core 3.x). The sketch describes widgets; the espFace apps and web renderer draw them.

```cpp
#include <espFace.h>
EspFace face;
void setup() {
  face.begin("Boiler");
  face.setPin("1234");
  face.wifi().autoConnect();
  face.ui().gauge("temp", "Temperature", 0, 120, "°C");
  face.ui().sw("pump", "Pump").onChange([](bool on) { digitalWrite(PUMP, on); });
}
void loop() { face.loop(); face.set("temp", readTemp()); }
```

## Builder (`face.ui()`)

Every method returns a `WidgetRef` for chaining. Widgets declared after `page()` belong to that page.

| Method | Widget | Value |
|---|---|---|
| `page(id, lbl)` | page (tab) | – |
| `header(lbl)` | header | – |
| `group(id, lbl)` | group card; widgets join it via `.group(id)` | – |
| `row(id)` | row; widgets join it via `.row(id).size(w)` | – |
| `spacer(id, w=1, h=8)` | spacer | – |
| `label(id, lbl, unit=0)` | label (output) | number or string |
| `button(id, lbl)` | button; `.hold()` for press/release | `onClick` / `onEvent(int)` |
| `sw(id, lbl)` | switch; `.labels(on, off)` | bool |
| `slider(id, lbl, min, max, step=1, unit=0)` | slider | float |
| `number(id, lbl, min, max, step=1, unit=0)` | number input; `.spin()` | float |
| `text(id, lbl, maxlen=64)` | text input; `.secret()`, `.regex(re)` | string |
| `textarea(id, lbl, maxlen=256, rows=4)` | multi-line text | string |
| `select(id, lbl, {opts})` | dropdown; `.style("seg")` | int index |
| `flags(id, lbl, {opts})` | checkbox set (max 32) | int bitmask |
| `color(id, lbl)` | colour picker | int 0xRRGGBB |
| `datetime(id, lbl, mode="datetime")` | date/time picker; `.mode("date"\|"time"\|"datetime")` | int unix seconds |
| `joystick(id, lbl)` | joystick; `.center()`, `.exp()` | pair, `onMove(x, y)` each -100..100 |
| `dpad(id, lbl)` | direction pad | `onEvent(int)`: `'u' 'd' 'l' 'r' 'c'` on press, 0 on release |
| `gauge(id, lbl, min, max, unit=0)` | gauge (output); `.style("arc"\|"round"\|"linear")`, `.zone(from, to, color)` | float |
| `progress(id, lbl, min=0, max=100)` | bar (output); `.center()` for bipolar | float |
| `display(id, lbl, digits=4, unit=0)` | 7-segment readout (output) | number or string |
| `led(id, lbl, color=0)` | LED (output); `.rgb()` makes the value a colour | bool, or int 0xRRGGBB with `.rgb()` |
| `chart(id, lbl, win=300, unit=0)` | chart; `.series(id, lbl, color)`, `.style()`, `.legend()`, `.values()` | `face.push(chart, series, v)` |
| `log(id, lbl, cap=200, rows=8)` | log view | `face.log(id, msg, color)` |
| `table(id, lbl)` | table (output); `.column(lbl, w=1, align="left")`, at least one | `setRows(id, json)` |
| `image(id, lbl, src)` | image; `prop(id).src(url)` to change | – |
| `stream(id, lbl, src)` | MJPEG stream | – |
| `clock(id, lbl, fmt=0)` | clock (output); the library pushes the device time every minute | int unix seconds |
| `map(id, lbl, zoom=12)` | map (output) | `setPoints(id, json)` |
| `textblock(id, text)` | static paragraph | – |
| `add(WType, id, lbl=0)` | any type, no defaults | per type |

Common chain modifiers: `.group(id)`, `.page(id)`, `.row(id)`, `.size(w, h=0)`, `.square()`, `.disabled()`, `.readOnly()`, `.hint(text)`, `.icon(name)`, `.color(hex)`, `.unit(u)`, `.range(min, max)`, `.step(s)`, `.value(v)`, `.persist()` (NVS, restored before `setup()` returns), `.bind(var)` (two-way with a `bool`/`int`/`float`/`String`), `.onChange(lambda)` (argument type picks the conversion: `bool`, `int`, `uint32_t`, `float`, `const String&`, `const Value&`).

## Runtime

| Call | Effect |
|---|---|
| `face.set(id, v)` | update a value (`bool`, `int`, `uint32_t`, `float`, `const char*`); joystick: `set(id, x, y)` |
| `face.setRows(id, "[[\"Kitchen\",21.5],[\"Bath\",23]]")` | table rows as a raw JSON array of rows |
| `face.setPoints(id, "[[52.52,13.4,\"Home\"]]")` | map points `[lat, lon, lbl]` |
| `face.push(chart, series, v)` | chart point |
| `face.log(msg)` / `face.log(id, msg, color)` | log line, optionally to one log widget |
| `face.toast(lvl, msg)` | `info`, `warn`, `err` toast on all clients |
| `face.ui().prop(id).label(..).color(..).src(..).min(..).disabled(..).visible(..).options({..})` | runtime prop change without rebuild |
| `face.ui().show(id, bool)` | hide/show |
| `face.ui().confirm(id, msg, cb)` / `prompt(id, msg, cb, def)` | dialogs on all clients, first answer wins |
| `face.ui().rebuild()` | resend the UI after structural changes |
| `face.time()` / `face.setTime(unix)` | unix time from NTP, the client clock or an RTC |

Development (all in Docker, from the repository root):

```
docker build -f docker/platformio.Dockerfile -t espface-pio .
docker volume create espface-pio
docker run --rm -v "$PWD":/w -v espface-pio:/pio -w /w/firmware espface-pio test -e native        # unit tests
docker run --rm -v "$PWD":/w -v espface-pio:/pio -w /w/firmware --entrypoint sh espface-pio tools/ci-build.sh   # ESP32 builds + footprint.md
```

Compile-time options: `ESPFACE_MAX_CLIENTS` (4), `ESPFACE_LOG_HISTORY` (0), `ESPFACE_RENDERER_HOST`, `ESPFACE_FRAME_SIZE` (1024).
