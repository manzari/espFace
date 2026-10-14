/// <reference types="vitest/config" />
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

// One classic-script bundle at dist/r/1/app.js + app.css; connect/index.html is the dev / hosted connect page,
// public/index.html the landing page of the hosted site.
export default defineConfig({
  appType: "mpa",
  build: {
    target: "es2020",
    modulePreload: false,
    cssCodeSplit: false,
    assetsInlineLimit: 0,
    rollupOptions: {
      input: "connect/index.html",
      output: {
        format: "iife",
        inlineDynamicImports: true,
        entryFileNames: "r/1/app.js",
        assetFileNames: "r/1/app.[ext]",
      },
    },
  },
  test: {
    environment: "node",
    include: ["test/**/*.test.ts"],
    testTimeout: 30000,
    // the in-process fake device (tools/fake-device) imports `ws`; resolve it from web/node_modules
    alias: { ws: fileURLToPath(new URL("./node_modules/ws/wrapper.mjs", import.meta.url)) },
  },
});
