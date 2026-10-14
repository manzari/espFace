import { expect, test } from "@playwright/test";
import { createHash } from "node:crypto";

// Smoke test against the fake device (PIN 1234). E2E_DEVICE is host:port of the fake device as seen from the browser.
const device = process.env.E2E_DEVICE ?? "localhost:8080";

test("pair, read, control, answer a dialog, switch page", async ({ page }) => {
  await page.goto(`/connect/?host=${device}`);

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
  await page.goto(`/connect/?host=${device}`);
  const pin = page.locator("form[data-pin]");
  await pin.locator("input").fill("1234");
  await pin.locator("button[type=submit]").click();
  await expect(page.locator('.w[data-id="temp"]')).toBeVisible();
  await page.locator('button[aria-label="menu"]').click();
  await page.locator(".menu button", { hasText: "System" }).click();
  const info = page.locator("section.card", { hasText: "Last reboot" });
  await expect(info).toContainText("FAKE");
  await expect(info).toContainText("manzari/espFace");
  await expect(info.locator("[data-rr]")).toHaveAttribute("data-rr", "power");
  await expect(info).toContainText("aa:bb:cc:dd:ee:ff");
  await expect(info).toContainText("Home -58 dBm");
  const wifi = page.locator("section.card", { hasText: "Scan networks" });
  await expect(wifi).toContainText("192.168.1.50");
  await expect(wifi.locator("[data-wifi]")).toHaveAttribute("data-wifi", "connected");
});

async function pairAndOpenSystem(page: import("@playwright/test").Page) {
  await page.goto(`/connect/?host=${device}`);
  const pin = page.locator("form[data-pin]");
  await pin.locator("input").fill("1234");
  await pin.locator("button[type=submit]").click();
  await expect(page.locator('.w[data-id="temp"]')).toBeVisible();
  await page.locator('button[aria-label="menu"]').click();
  await page.locator(".menu button", { hasText: "System" }).click();
}

test("wifi scan lists networks and wifi.set pushes status", async ({ page }) => {
  await pairAndOpenSystem(page);
  const wifi = page.locator("section.card", { hasText: "Scan networks" });
  await wifi.locator("button", { hasText: "Scan networks" }).click();
  const list = wifi.locator("[data-scan] button");
  await expect(list).toHaveCount(3);
  await expect(list.first()).toContainText("Home");
  await expect(list.first()).toContainText("-55 dBm");
  await expect(list.nth(1).locator("svg")).toHaveCount(1);   // Cafe is open: no lock icon
  await list.nth(1).click();
  await expect(wifi.locator("form input").first()).toHaveValue("Cafe");
  await wifi.locator("form button[type=submit]").click();
  await expect(wifi.locator("[data-wifi]")).toHaveAttribute("data-wifi", "connecting");
  await expect(wifi.locator("[data-wifi]")).toHaveAttribute("data-wifi", "connected", { timeout: 5000 });
  await expect(wifi).toContainText("Cafe");
});

test("OTA push: file -> md5 -> binary frames -> device verifies and reboots", async ({ page }) => {
  await pairAndOpenSystem(page);
  const ota = page.locator("section.card", { hasText: "Firmware update" });
  const image = Buffer.alloc(4096 * 5 + 123);
  for (let i = 0; i < image.length; i++) image[i] = (i * 13 + 5) & 255;
  await ota.locator("[data-ota-file]").setInputFiles({ name: "firmware.bin", mimeType: "application/octet-stream", buffer: image });
  await expect(ota).toContainText(createHash("md5").update(image).digest("hex"));
  await ota.locator("[data-ota-upload]").click();
  const status = ota.locator("[data-ota-status]");
  await expect(status).toHaveAttribute("data-ok", "true", { timeout: 15000 });
  await expect(status).toContainText("rebooting");
  // the fake device drops every client 1 s after a successful update; the page reconnects by itself
  await page.waitForTimeout(1500);
  await page.locator('button[aria-label="back"]').click();
  await expect(page.locator('.w[data-id="temp"]')).toBeVisible({ timeout: 15000 });
  await expect(page.locator(".banner")).toBeHidden({ timeout: 15000 });
});

test("OTA by URL shows device progress", async ({ page }) => {
  await pairAndOpenSystem(page);
  const ota = page.locator("section.card", { hasText: "Firmware update" });
  await ota.locator("input[type=url]").fill("https://example.com/fw.bin");
  await ota.locator("button", { hasText: "Install from URL" }).click();
  await expect(ota.locator("[data-ota-status]")).toContainText("Device progress", { timeout: 5000 });
  await expect(ota.locator("[data-ota-status]")).toHaveAttribute("data-ok", "true", { timeout: 15000 });
});
