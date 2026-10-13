import { expect, test } from "@playwright/test";

// Smoke test against the fake device (PIN 1234). E2E_DEVICE is host:port of the fake device as seen from the browser.
const device = process.env.E2E_DEVICE ?? "localhost:8080";

test("pair, read, control, answer a dialog, switch page", async ({ page }) => {
  await page.goto(`/?host=${device}`);

  // pairing with a wrong PIN first, then the right one
  const pin = page.locator("form[data-pin]");
  await expect(pin).toBeVisible();
  await pin.locator("input").fill("0000");
  await pin.locator("button[type=submit]").click();
  await expect(pin.locator(".err")).toContainText("4 attempts left");
  await pin.locator("input").fill("1234");
  await pin.locator("button[type=submit]").click();
  await expect(pin).toBeHidden();

  // the gauge shows the simulated temperature
  const gauge = page.locator('.w[data-id="temp"]');
  await expect(gauge).toBeVisible();
  await expect(gauge.locator("text.num")).not.toHaveText("");
  await expect(gauge.locator("text.unit")).toHaveText("°C");

  // toggle the pump switch; the device echoes the value and logs it
  const pump = page.locator('.w[data-id="pump"] label.switch');
  await expect(pump).not.toHaveClass(/\bon\b/);
  await pump.click();
  await expect(pump).toHaveClass(/\bon\b/);
  await expect(page.locator('.w[data-id="term"] .log')).toContainText("pump on");

  // confirm dialog from the Erase button
  await page.locator('.w[data-id="erase"] button').click();
  const dlg = page.locator(".modal-bg[data-dlg]");
  await expect(dlg).toBeVisible();
  await expect(dlg).toContainText("Erase all stored data?");
  await dlg.locator("button[type=submit]").click();
  await expect(dlg).toBeHidden();
  await expect(page.locator(".toast")).toContainText("Erased");

  // switch to the I/O page (bottom nav on the phone viewport); joystick and dpad live there
  await page.locator(".bottomnav button", { hasText: "I/O" }).click();
  await expect(page.locator('.w[data-id="joy"] .joy')).toBeVisible();
  await expect(page.locator('.w[data-id="pad"] .dpad')).toBeVisible();
  await expect(page.locator('.w[data-id="tbl"] table')).toContainText("Kitchen");
  await expect(page.locator('.w[data-id="temp"]')).toHaveCount(0);

  // token is remembered: a reload pairs without a PIN
  await page.reload();
  await expect(page.locator('.w[data-id="temp"]')).toBeVisible();
  await expect(pin).toHaveCount(0);
});

test("system page shows device info and caps", async ({ page }) => {
  await page.goto(`/?host=${device}`);
  const pin = page.locator("form[data-pin]");
  await pin.locator("input").fill("1234");
  await pin.locator("button[type=submit]").click();
  await expect(page.locator('.w[data-id="temp"]')).toBeVisible();
  await page.locator('button[aria-label="menu"]').click();
  await page.locator(".menu button", { hasText: "System" }).click();
  const info = page.locator("section.card", { hasText: "Reboot reason" });
  await expect(info).toContainText("FAKE");
  await expect(info).toContainText("manzari/espFace");
  await expect(info).toContainText("power");
  await expect(page.locator("section.card", { hasText: "SSID" })).toContainText("192.168.1.50");
});
