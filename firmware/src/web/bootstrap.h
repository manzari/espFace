#pragma once
// Bootstrap page served at / (and for captive-portal probes): loads the renderer the device serves from /r/1/ (embed.h).
static const char ESPFACE_BOOTSTRAP_HTML[] =
"<!doctype html><html><head><meta charset=utf-8><meta name=viewport content=\"width=device-width,initial-scale=1\">"
"<title>espFace</title><style>body{font:16px system-ui,sans-serif;margin:0;background:#111;color:#eee}"
"#f{display:none;padding:24px;max-width:480px;margin:auto;line-height:1.5}"
"@media(prefers-color-scheme:light){body{background:#fafafa;color:#111}}</style></head><body>"
"<div id=app></div><div id=f><h2>Renderer failed to load</h2><p>The device could not deliver its web UI. Reload the page or use the espFace app.</p></div>"
"<script>(function(){var s=document.createElement('script');s.src='/r/1/app.js';"
"s.onerror=function(){document.getElementById('f').style.display='block'};document.head.appendChild(s)})()</script></body></html>";
