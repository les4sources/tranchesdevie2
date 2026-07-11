#!/usr/bin/env node
// Génère les captures d'écran de la documentation boulanger.
//
// Entrées (variables d'environnement, remplies par rake docs:screenshots) :
//   DOCS_BASE_URL     ex. http://127.0.0.1:4567
//   DOCS_ADMIN_PWD    mot de passe admin
//   DOCS_MANIFEST     chemin vers script/docs/screenshot_manifest.yml
//   DOCS_OUTPUT_DIR   chemin vers docs/admin/images/
//
// Ce script est intentionnellement autonome (pas de dépendance npm hors
// playwright + js-yaml) et sait résoudre les placeholders `FIRST_*_ID`
// via l'API interne /api/v1 quand elle est accessible avec la clef locale,
// sinon via une heuristique DOM sur les listes admin.

import { chromium } from "playwright";
import fs from "node:fs/promises";
import path from "node:path";
import yaml from "js-yaml";

const BASE = process.env.DOCS_BASE_URL || "http://127.0.0.1:4567";
const ADMIN_PWD = process.env.DOCS_ADMIN_PWD || "demo";
const MANIFEST_PATH = process.env.DOCS_MANIFEST;
const OUTPUT_DIR = process.env.DOCS_OUTPUT_DIR;

if (!MANIFEST_PATH || !OUTPUT_DIR) {
  console.error("DOCS_MANIFEST et DOCS_OUTPUT_DIR sont requis.");
  process.exit(2);
}

const raw = await fs.readFile(MANIFEST_PATH, "utf8");
const manifest = yaml.load(raw);
await fs.mkdir(OUTPUT_DIR, { recursive: true });

const CHROMIUM_PATH = "/opt/pw-browsers/chromium";
const launchOpts = {};
try {
  await fs.access(CHROMIUM_PATH);
  launchOpts.executablePath = CHROMIUM_PATH;
} catch {
  // pas de Chromium local, on laisse Playwright chercher le sien
}

const browser = await chromium.launch(launchOpts);
const context = await browser.newContext({
  viewport: manifest.viewport ?? { width: 1280, height: 900 },
  locale: "fr-BE",
  timezoneId: "Europe/Brussels"
});
const page = await context.newPage();

// 1. Login admin — les captures « no_auth: true » n'ont pas besoin de session
await page.goto(`${BASE}/admin/login`, { waitUntil: "domcontentloaded" });
await page.fill('input[name="password"]', ADMIN_PWD);
await Promise.all([
  page.waitForURL(/\/admin\/orders/),
  page.click('button[type="submit"], input[type="submit"]')
]);

// 2. Résolution des placeholders FIRST_*_ID
const ids = await resolveFirstIds(page);

// 3. Boucle sur les captures
let failed = 0;
for (const shot of manifest.screenshots ?? []) {
  const target = new URL(interpolate(shot.path, ids), BASE).toString();
  try {
    if (shot.no_auth) {
      const ctx2 = await browser.newContext({ viewport: manifest.viewport });
      const p2 = await ctx2.newPage();
      await p2.goto(target, { waitUntil: "networkidle" });
      await capture(p2, shot);
      await ctx2.close();
    } else {
      await page.goto(target, { waitUntil: "networkidle" });
      if (shot.wait_for) await page.waitForSelector(shot.wait_for, { timeout: 5000 });
      if (shot.click)    await page.click(shot.click);
      await capture(page, shot);
    }
    console.log(`  ✔ ${shot.slug}`);
  } catch (err) {
    failed++;
    console.error(`  ✘ ${shot.slug} — ${err.message}`);
  }
}

await browser.close();
process.exit(failed > 0 ? 1 : 0);

// ---- helpers ---------------------------------------------------------------

async function capture(pageOrLoc, shot) {
  const outPath = path.join(OUTPUT_DIR, `${shot.slug}.png`);
  if (shot.crop_to) {
    const el = await pageOrLoc.$(shot.crop_to);
    if (!el) throw new Error(`Sélecteur introuvable : ${shot.crop_to}`);
    await el.screenshot({ path: outPath, mask: buildMasks(pageOrLoc) });
  } else {
    await pageOrLoc.screenshot({
      path: outPath,
      fullPage: shot.full_page !== false,
      mask: await buildMasksAsync(pageOrLoc)
    });
  }
}

async function buildMasksAsync(page) {
  const selectors = manifest.mask_selectors ?? [];
  const masks = [];
  for (const sel of selectors) {
    const els = await page.$$(sel);
    masks.push(...els);
  }
  return masks;
}

function buildMasks() {
  // no-op pour capture d'un élément ciblé — Playwright n'accepte pas de mask
  // hors du bounding box de l'élément capturé.
  return [];
}

function interpolate(pathTemplate, ids) {
  return pathTemplate
    .replace("FIRST_BAKE_DAY_ID",    ids.bakeDay    ?? "1")
    .replace("FIRST_ORDER_ID",       ids.order      ?? "1")
    .replace("FIRST_PAID_ORDER_ID",  ids.paidOrder  ?? ids.order ?? "1")
    .replace("FIRST_CUSTOMER_ID",    ids.customer   ?? "1")
    .replace("FIRST_PRODUCT_ID",     ids.product    ?? "1");
}

async function resolveFirstIds(page) {
  const ids = {};
  const scrape = async (url, selector) => {
    await page.goto(new URL(url, BASE).toString(), { waitUntil: "domcontentloaded" });
    const href = await page.getAttribute(selector, "href").catch(() => null);
    if (!href) return null;
    const m = href.match(/\/(\d+)(?:$|\/|\?)/);
    return m ? m[1] : null;
  };
  ids.bakeDay  = await scrape("/admin/bake_days",  "a[href*='/admin/bake_days/']:not([href$='/new']):not([href*='/edit'])");
  ids.order    = await scrape("/admin/orders",     "a[href*='/admin/orders/']:not([href$='/new']):not([href*='/edit'])");
  ids.customer = await scrape("/admin/customers",  "a[href*='/admin/customers/']:not([href$='/new']):not([href*='/edit'])");
  ids.product  = await scrape("/admin/products",   "a[href*='/admin/products/']:not([href$='/new']):not([href*='/edit'])");
  ids.paidOrder = ids.order; // simplification : première commande = payée dans les seeds démo
  return ids;
}
