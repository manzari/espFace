declare const __RENDERER_VERSION__: string;
// Injected from package.json by vite.config.ts; the hosted path /r/1/ follows the protocol major.
export const RENDERER_VERSION: string = typeof __RENDERER_VERSION__ === "string" ? __RENDERER_VERSION__ : "dev";
export const RENDERER_PROTOCOL = 1;
