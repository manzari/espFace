# Icons

Widgets, pages and the device itself can carry an icon. The protocol only transports a name; each client maps it to a glyph.

## Using icons

```cpp
face.setIcon("thermostat");                       // shown in the device list
ui.page("main", "Boiler").icon("home");           // page tab
ui.button("reset", "Reset").icon("restart_alt");  // widget
```

The shared set is a subset of Material Icons (filled). The web renderer draws the glyphs as inline SVG and the Flutter app maps the same names to its `Icons.*` constants. A test keeps both lists identical.

Unknown names render the `help_outline` glyph in both clients, so a typo is visible but harmless. A client that knows more icons than this table is free to show them, but only the names below are guaranteed everywhere.

## Shared set

<!--@include: ./icons-list.md-->
