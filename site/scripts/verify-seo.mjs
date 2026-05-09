#!/usr/bin/env node
/**
 * CI SEO 冒烟：对已构建站点发起 HTTP 断言（需在 next start 之后运行）。
 * SITE_ORIGIN / 标题 / 描述从 lib/seo-defaults.ts 解析，避免与源码分叉。
 */

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

function loadSeoDefaultsTs() {
  return readFileSync(join(__dirname, "../lib/seo-defaults.ts"), "utf8");
}

/** @param {string} src @param {string} name */
function exportConstStringSameLine(src, name) {
  const re = new RegExp(
    `export const ${name}\\s*=\\s*"([^"]*)"\\s*(?:as const)?;`,
  );
  const m = src.match(re);
  return m ? m[1] : null;
}

/** 支持 `export const X =\n  "..."` */
/** @param {string} src @param {string} name */
function exportConstStringNextLine(src, name) {
  const re = new RegExp(
    `export const ${name}\\s*=\\s*\\r?\\n\\s*"([^"]+)"\\s*;`,
    "m",
  );
  const m = src.match(re);
  return m ? m[1] : null;
}

function parseRepoSeo() {
  const src = loadSeoDefaultsTs();
  const origin =
    exportConstStringSameLine(src, "SITE_ORIGIN") ??
    (() => {
      throw new Error("verify-seo: cannot parse SITE_ORIGIN from seo-defaults.ts");
    })();
  const siteName =
    exportConstStringSameLine(src, "SITE_NAME") ??
    (() => {
      throw new Error("verify-seo: cannot parse SITE_NAME from seo-defaults.ts");
    })();
  const title =
    exportConstStringNextLine(src, "SITE_TITLE") ??
    exportConstStringSameLine(src, "SITE_TITLE");
  const description =
    exportConstStringNextLine(src, "SITE_DESCRIPTION") ??
    exportConstStringSameLine(src, "SITE_DESCRIPTION");
  if (!title || !description) {
    throw new Error(
      "verify-seo: cannot parse SITE_TITLE / SITE_DESCRIPTION from seo-defaults.ts",
    );
  }
  return { origin, siteName, title, description };
}

/** @param {string[]} argv */
function parseBase(argv) {
  const i = argv.indexOf("--base");
  if (i >= 0 && argv[i + 1]) return argv[i + 1];
  const env = process.env.SEO_VERIFY_BASE;
  if (env) return env;
  return "http://127.0.0.1:3000";
}

/** @param {string} msg */
function fail(msg) {
  console.error(`verify-seo: ${msg}`);
  process.exit(1);
}

/** @param {string} base @param {string} path */
async function fetchText(base, path) {
  const url = new URL(path, base.endsWith("/") ? base : `${base}/`).toString();
  const res = await fetch(url, {
    redirect: "manual",
    headers: { Accept: "text/html,application/xhtml+xml,text/plain,application/xml;q=0.9,*/*;q=0.8" },
  });
  if (!res.ok) fail(`GET ${path} → ${res.status} (expected 2xx)`);
  return await res.text();
}

/** @param {string} html */
function metaDescription(html) {
  const m = html.match(
    /<meta[^>]+name=["']description["'][^>]*content=["']([^"']*)["'][^>]*>/i,
  );
  if (m) return m[1];
  const m2 = html.match(
    /<meta[^>]+content=["']([^"']*)["'][^>]*name=["']description["'][^>]*>/i,
  );
  return m2 ? m2[1] : null;
}

/** @param {string} html */
function canonicalHref(html) {
  const m = html.match(/<link[^>]+rel=["']canonical["'][^>]*href=["']([^"']+)["']/i);
  return m ? m[1] : null;
}

/** @param {string} html */
function ldJsonBlocks(html) {
  const blocks = [];
  const re = /<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
  let x;
  while ((x = re.exec(html)) !== null) {
    blocks.push(x[1].trim());
  }
  return blocks;
}

/** @param {unknown} g */
function graphTypes(g) {
  if (!g || typeof g !== "object") return [];
  const graph = /** @type {{ "@graph"?: unknown[] }} */ (g)["@graph"];
  if (!Array.isArray(graph)) return [];
  return graph
    .map((node) =>
      node && typeof node === "object" && "@type" in node
        ? /** @type {{ "@type": string | string[] }} */ (node)["@type"]
        : null,
    )
    .flatMap((t) => (Array.isArray(t) ? t : t ? [t] : []));
}

async function main() {
  const { origin, title, description } = parseRepoSeo();
  const base = parseBase(process.argv.slice(2));

  console.log(`verify-seo: base=${base} expectOrigin=${origin}`);

  const html = await fetchText(base, "/");

  if (!html.includes("<title>")) fail("home: missing <title>");
  if (!html.includes(title)) fail(`home: <title> body must include SITE_TITLE`);

  const md = metaDescription(html);
  if (!md) fail("home: missing meta description");
  const decoded = md
    .replace(/&quot;/g, '"')
    .replace(/&#x27;/g, "'")
    .replace(/&amp;/g, "&");
  if (decoded !== description && !decoded.includes(description.slice(0, 48))) {
    fail("home: meta description does not match SITE_DESCRIPTION (prefix check)");
  }

  const canon = canonicalHref(html);
  if (!canon) fail("home: missing canonical link");
  const originNoSlash = origin.replace(/\/$/, "");
  const canonNoSlash = canon.replace(/\/$/, "");
  if (canonNoSlash !== originNoSlash) {
    fail(
      `home: canonical href mismatch: got ${canon}, expected origin ${originNoSlash}`,
    );
  }

  if (!html.includes(`property="og:title"`)) fail("home: missing og:title meta");
  if (!html.includes(`property="og:url"`)) fail("home: missing og:url meta");

  const h1count = (html.match(/<h1\b/gi) ?? []).length;
  if (h1count !== 1) fail(`home: expected exactly one <h1>, got ${h1count}`);

  const ldBlocks = ldJsonBlocks(html);
  if (ldBlocks.length === 0) fail("home: no application/ld+json blocks");

  let mergedTypes = [];
  for (const raw of ldBlocks) {
    let data;
    try {
      data = JSON.parse(raw);
    } catch {
      fail("home: invalid JSON-LD (parse error)");
    }
    mergedTypes.push(...graphTypes(data));
    if (data && typeof data === "object" && "@type" in data && !("@graph" in data)) {
      const t = /** @type {{ "@type": unknown }} */ (data)["@type"];
      if (typeof t === "string") mergedTypes.push(t);
      else if (Array.isArray(t)) mergedTypes.push(...t.filter((x) => typeof x === "string"));
    }
  }

  const need = ["WebSite", "SoftwareApplication", "FAQPage", "WebPage"];
  for (const t of need) {
    if (!mergedTypes.includes(t)) fail(`home: JSON-LD missing @type ${t}`);
  }

  const robots = await fetchText(base, "/robots.txt");
  if (!/User-agent:\s*\*/i.test(robots)) fail("robots.txt: missing User-agent: *");
  if (!/Allow:\s*\//i.test(robots)) fail("robots.txt: missing Allow: /");
  if (!robots.includes(`${origin}/sitemap.xml`)) {
    fail(`robots.txt: must reference sitemap ${origin}/sitemap.xml`);
  }

  const sm = await fetchText(base, "/sitemap.xml");
  if (!sm.includes("<urlset")) fail("sitemap.xml: not a urlset document");
  if (!sm.includes(origin)) fail(`sitemap.xml: must include SITE_ORIGIN ${origin}`);

  console.log("verify-seo: OK");
}

try {
  await main();
} catch (e) {
  console.error(e);
  process.exit(1);
}
