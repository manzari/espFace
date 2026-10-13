/// <reference types="vitest/config" />
import { defineConfig } from "vite";

// One classic-script bundle at dist/r/1/app.js + app.css; index.html is the dev / hosted landing page.
export default defineConfig({
  build: {
    target: "es2020",
    modulePreload: false,
    cssCodeSplit: false,
    assetsInlineLimit: 0,
    rollupOptions: {
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
  },
});
