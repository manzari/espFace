#pragma once
// Bootstrap page served by the device: loads the hosted renderer, falls back to a hint when offline.
#ifndef ESPFACE_RENDERER_HOST
#define ESPFACE_RENDERER_HOST "https://espface.manzari.dev"
#endif
static const char ESPFACE_BOOTSTRAP_HTML[] =
"<!doctype html><html><head><meta charset=utf-8><meta name=viewport content=\"width=device-width,initial-scale=1\">"
"<title>espFace</title><style>body{font:16px system-ui,sans-serif;margin:0;background:#111;color:#eee}"
"#f{display:none;padding:24px;max-width:480px;margin:auto;line-height:1.5}#f code{background:#333;padding:2px 6px;border-radius:4px}"
"@media(prefers-color-scheme:light){body{background:#fafafa;color:#111}#f code{background:#ddd}}</style></head><body>"
"<div id=app></div><div id=f><h2>No internet</h2><p>This device needs the espFace renderer, which could not be loaded.</p>"
"<p>Install the <b>espFace</b> app and connect to <code id=h></code>, or build the firmware with <code>ESPFACE_EMBED_WEB</code>.</p></div>"
"<script>(function(){var h=location.host,t=setTimeout(fail,5000),s=document.createElement('script');"
"s.src='" ESPFACE_RENDERER_HOST "/r/1/app.js';s.onload=function(){clearTimeout(t)};s.onerror=fail;"
"function fail(){clearTimeout(t);document.getElementById('h').textContent=h;document.getElementById('f').style.display='block'}"
"document.head.appendChild(s)})()</script></body></html>";
