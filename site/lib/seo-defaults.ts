/** 单一真相来源：metadata、结构化数据、sitemap / robots 共用，避免文案分叉 */

export const SITE_ORIGIN = "https://claude-gateway.vercel.app" as const;

export const SITE_NAME = "Claude Gateway";

export const SITE_TITLE =
  "Claude Gateway — Local wire between Claude clients and your models";

export const SITE_DESCRIPTION =
  "Native macOS control plane: Anthropic-compatible loopback, your upstreams, local keys and logs—no extra cloud dashboard.";

export const SITE_KEYWORDS = [
  "Claude Desktop",
  "Claude Code",
  "Claude Gateway",
  "Anthropic-compatible providers",
  "Anthropic compatible",
  "macOS gateway",
  "local proxy",
  "model routing",
  "custom AI providers",
] as const;
