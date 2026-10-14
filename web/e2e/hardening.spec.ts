import { expect, test, type Browser, type Page } from "@playwright/test";

// Hardening scenarios against fake devices started with the knobs of tools/fake-device (see scripts/e2e.sh).
const dev = {
  plain: process.env.E2E_DEVICE ?? "localhost:8080",
  drop: process.env.E2E_DEVICE_DROP ?? "localhost:8081",
  slow: process.env.E2E_DEVICE_SLOW ?? "localhost:8082",
  huge: process.env.E2E_DEVICE_HUGE ?? "localhost:8083",
  busy: process.env.E2E_DEVICE_BUSY ?? "localhost:8084",
  flaky: process.env.E2E_DEVICE_FLAKY ?? "localhost:8085",
  lock: process.env.E2E_DEVICE_LOCK ?? "localhost:8086",
};

async function pair(page: Page, host: string, pin = "1234") {
  await page.goto(`/connect/?host=${host}`);
  const form = page.locator("form[data-pin]");
  await expect(form).toBeVisible({ timeout: 15000 });
  await form.locator("input").fill(pin);
  await form.locator("button[type=submit]").click();
  await expect(form).toBeHidden();
}

test("drop-every: reconnects with the token, keeps the last UI visible, shows a countdown banner", async ({ page }) => {
  await pair(page, dev.drop);
  const gauge = page.locator('.w[data-id="temp"]');
  await expect(gauge).toBeVisible();
  // the simulation keeps sending; every 8th message closes the socket
  const banner = page.locator(".banner.err");
  await expect(banner).toBeVisible({ timeout: 20000 });
  await expect(banner).toContainText("reconnecting");
  await expect(gauge).toBeVisible();
  await expect(page.locator("form[data-pin]")).toHaveCount(0);
  await expect(banner).toBeHidden({ timeout: 20000 });
  await expect(gauge).toBeVisible();
  await expect(page.locator("form[data-pin]")).toHaveCount(0);
  const attempts = await page.evaluate(() => (window as unknown as { espface: { session: { ws: { attempts: number } } } }).espface.session.ws.attempts);
  expect(attempts).toBeGreaterThanOrEqual(1);
});

test("lockout: five wrong PINs show a countdown that ticks down", async ({ page }) => {
  await page.goto(`/connect/?host=${dev.lock}`);
  const form = page.locator("form[data-pin]");
  await expect(form).toBeVisible({ timeout: 15000 });
  for (let i = 0; i < 5; i++) {
    await form.locator("input").fill("0000");
    await form.locator("button[type=submit]").click();
    if (i < 4) await expect(form.locator(".err")).toContainText(`${4 - i} attempt`);
  }
  await expect(form.locator(".err")).toContainText("Locked for");
  const read = async () => Number(/Locked for (\d+) s/.exec((await form.locator(".err").textContent()) ?? "")?.[1]);
  const a = await read();
  expect(a).toBeGreaterThan(50);
  await page.waitForTimeout(2100);
  const b = await read();
  expect(b).toBeLessThan(a);
  await expect(form.locator("input")).toHaveCount(0);
});

test("slow-ui: a fragmented ui renders completely", async ({ page }) => {
  await page.goto(`/connect/?host=${dev.slow}`);
  await expect(page.locator('.w[data-id="temp"]')).toBeVisible({ timeout: 30000 });
  await expect(page.locator('.w[data-id="term"]')).toBeVisible();
  await expect(page.locator(".bottomnav button")).toHaveCount(3);
  const n = await page.evaluate(() => (window as unknown as { espface: { store: { widgets: Map<string, unknown> } } }).espface.store.widgets.size);
  expect(n).toBeGreaterThanOrEqual(40);
});

test("huge-ui: hundreds of widgets stay interactive; render times are reported", async ({ page }) => {
  const t0 = Date.now();
  await page.goto(`/connect/?host=${dev.huge}`);
  await expect(page.locator('.w[data-id="temp"]')).toBeVisible({ timeout: 30000 });
  const firstPaint = Date.now() - t0;
  const size = await page.evaluate(() => (window as unknown as { espface: { store: { widgets: Map<string, unknown> } } }).espface.store.widgets.size);
  expect(size).toBeGreaterThan(400);
  // switch to the generated page with 200 widgets and measure until the last one is in the DOM
  const t1 = Date.now();
  await page.locator(".bottomnav button", { hasText: "Bank 1" }).click();
  await expect(page.locator('.w[data-id="w199"]')).toBeAttached({ timeout: 30000 });
  const pageSwitch = Date.now() - t1;
  const cells = await page.locator(".w").count();
  // a slider on the generated page still answers to input
  const sw = page.locator('.w[data-id="w2"] label.switch');
  await sw.scrollIntoViewIfNeeded();
  const was = await sw.evaluate((el) => el.classList.contains("on"));
  const t2 = Date.now();
  await sw.click();
  await expect(sw).toHaveClass(was ? /^(?!.*\bon\b)/ : /\bon\b/, { timeout: 5000 });
  const toggle = Date.now() - t2;
  console.log(`huge-ui: ${size} widgets, first widget after ${firstPaint} ms, page with ${cells} widgets rendered in ${pageSwitch} ms, switch echo ${toggle} ms`);
  expect(pageSwitch).toBeLessThan(5000);
  expect(toggle).toBeLessThan(2000);
});

test("1000 reconnects do not leak listeners or heap", async ({ page }) => {
  test.setTimeout(300000);
  await pair(page, dev.plain);
  await expect(page.locator('.w[data-id="temp"]')).toBeVisible();
  type Dbg = { espface: { store: { listenerCount(): number; conn: string }; session: { ws: { reconnect(d: number): void; attempts: number } } }; gc?: () => void; performance: { memory?: { usedJSHeapSize: number } } };
  const cycle = async (n: number) => {
    for (let i = 0; i < n; i++) {
      const before = await page.evaluate(() => { const s = (window as unknown as Dbg).espface.session; const a = s.ws.attempts; s.ws.reconnect(0); return a; });
      await page.waitForFunction((a) => { const e = (window as unknown as Dbg).espface; return e.session.ws.attempts > a && e.store.conn === "ready"; }, before, { timeout: 10000 });
    }
  };
  const measure = async () => {
    await page.waitForTimeout(300);
    return page.evaluate(() => { const w = window as unknown as Dbg; w.gc?.(); w.gc?.(); return { heap: w.performance.memory?.usedJSHeapSize ?? 0, listeners: w.espface.store.listenerCount() }; });
  };
  await cycle(50);
  const before = await measure();
  await cycle(950);
  const after = await measure();
  const attempts = await page.evaluate(() => (window as unknown as Dbg).espface.session.ws.attempts);
  console.log(`reconnect leak: ${attempts} reconnects, listeners ${before.listeners} -> ${after.listeners}, heap ${(before.heap / 1048576).toFixed(1)} -> ${(after.heap / 1048576).toFixed(1)} MB`);
  expect(attempts).toBeGreaterThanOrEqual(1000);
  expect(after.listeners).toBeLessThanOrEqual(before.listeners + 2);
  if (before.heap) expect(after.heap).toBeLessThan(before.heap + 8 * 1048576);
  await expect(page.locator('.w[data-id="temp"]')).toBeVisible();
  await expect(page.locator("form[data-pin]")).toHaveCount(0);
});

async function secondTab(browser: Browser, host: string, pin?: string) {
  const ctx = await browser.newContext({ viewport: { width: 420, height: 800 } });
  const page = await ctx.newPage();
  if (pin) await pair(page, host, pin); else await page.goto(`/connect/?host=${host}`);
  return { ctx, page };
}

test("multi-client: two tabs see the same state and the same dialogs", async ({ page, browser }) => {
  await pair(page, dev.plain);
  const b = await secondTab(browser, dev.plain, "1234");
  const pumpA = page.locator('.w[data-id="pump"] label.switch');
  const pumpB = b.page.locator('.w[data-id="pump"] label.switch');
  await expect(pumpA).toBeVisible();
  await expect(pumpB).toBeVisible();
  const was = await pumpA.evaluate((el) => el.classList.contains("on"));
  await pumpA.click();
  const want = was ? /^(?!.*\bon\b)/ : /\bon\b/;
  await expect(pumpA).toHaveClass(want);
  await expect(pumpB).toHaveClass(want, { timeout: 5000 });
  await expect(b.page.locator('.w[data-id="term"] .log')).toContainText(was ? "pump off" : "pump on");
  // a device dialog opened from A shows in B; A answers, B's copy closes
  await page.locator('.w[data-id="erase"] button').click();
  await expect(page.locator(".modal-bg[data-dlg]")).toBeVisible();
  await expect(b.page.locator(".modal-bg[data-dlg]")).toBeVisible({ timeout: 5000 });
  await page.locator(".modal-bg[data-dlg] button[type=button]").click();
  await expect(page.locator(".modal-bg[data-dlg]")).toBeHidden();
  await expect(b.page.locator(".modal-bg[data-dlg]")).toBeHidden({ timeout: 5000 });
  await expect(b.page.locator(".toast")).toContainText("Erase cancelled");
  await b.ctx.close();
});

test("max-clients: the second tab waits with a busy banner until the first leaves", async ({ page, browser }) => {
  await page.goto(`/connect/?host=${dev.busy}`);
  await expect(page.locator('.w[data-id="temp"]')).toBeVisible({ timeout: 15000 });
  const b = await secondTab(browser, dev.busy);
  await expect(b.page.locator(".banner.err")).toContainText("Device is full", { timeout: 15000 });
  await expect(b.page.locator('.w[data-id="temp"]')).toHaveCount(0);
  await page.close();
  await expect(b.page.locator('.w[data-id="temp"]')).toBeVisible({ timeout: 40000 });
  await expect(b.page.locator(".banner")).toBeHidden();
  await b.ctx.close();
});

test("flaky-auth: one PIN entry is enough even when the device flakes on the first auth", async ({ page }) => {
  await pair(page, dev.flaky);
  await expect(page.locator('.w[data-id="temp"]')).toBeVisible({ timeout: 15000 });
  await expect(page.locator("form[data-pin]")).toHaveCount(0);
});
