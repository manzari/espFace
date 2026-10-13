#include "Widget.h"

namespace espface {

static const char* const kTypes[] = {
  "label", "button", "switch", "slider", "number", "text", "select", "gauge", "progress", "led", "chart", "header", "group", "page", "row", "spacer",
  "textarea", "flags", "color", "datetime", "joystick", "dpad", "display", "log", "table", "image", "stream", "clock", "map", "textblock"};

static const char* const kKeys[] = {
  "lbl", "grp", "page", "row", "size", "sq", "dis", "vis", "hint", "icon", "ro", "color", "hold", "on", "off", "min", "max", "step", "unit", "spin", "maxlen",
  "secret", "re", "opts", "style", "zones", "series", "win", "legend", "vals", "fold", "fmt", "center", "rows", "cap", "digits", "rgb", "mode", "src", "text",
  "exp", "cols", "zoom"};

const char* wtypeName(WType t) { return (uint8_t)t < (uint8_t)WType::Unknown ? kTypes[(uint8_t)t] : "unknown"; }

WType wtypeFromName(const char* n) {
  for (uint8_t i = 0; i < (uint8_t)WType::Unknown; i++) if (strcmp(kTypes[i], n) == 0) return (WType)i;
  return WType::Unknown;
}

const char* pkeyName(PKey k) { return (uint8_t)k < (uint8_t)PKey::_count ? kKeys[(uint8_t)k] : "?"; }

PKey pkeyFromName(const char* n) {
  for (uint8_t i = 0; i < (uint8_t)PKey::_count; i++) if (strcmp(kKeys[i], n) == 0) return (PKey)i;
  return PKey::_count;
}

VKind valueKind(WType t) {
  switch (t) {
    case WType::Label: case WType::Display: return VKind::NumOrStr;
    case WType::Switch: return VKind::Bool;
    case WType::Slider: case WType::Number: case WType::Gauge: case WType::Progress: return VKind::Num;
    case WType::Text: case WType::Textarea: return VKind::Str;
    case WType::Select: case WType::Flags: case WType::Color: case WType::Datetime: case WType::Clock: return VKind::Int;
    case WType::Led: return VKind::BoolOrInt;
    case WType::Joystick: return VKind::Pair;
    case WType::Table: case WType::Map: return VKind::Rows;
    default: return VKind::None;
  }
}

}  // namespace espface
