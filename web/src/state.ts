import { Session } from "./session";
import { Store } from "./store";

export const store = new Store();
export let session: Session | null = null;

export function connect(host: string): Session {
  session?.stop();
  session = new Session(store, host);
  session.start();
  return session;
}

// Debug hook for e2e tests and the browser console.
(globalThis as unknown as { espface: unknown }).espface = { store, get session() { return session; } };
