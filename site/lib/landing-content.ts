/** 重新收窄信息架构：单承诺 → 三条原则 → 一条路径 → 安装 → 收尾 FAQ */

export const heroCopy = {
  brand: "Claude Gateway",
  kicker: "macOS · local control plane",
  title: "Own the wire between Claude and your models.",
  lede:
    "Native app on the boundary: clients to loopback; you keep routes, provider secrets, and logs on disk.",
  flow: "Claude Desktop / Code → loopback → your Anthropic-compatible upstream",
};

export const manifestoCopy = {
  title: "Local first. Precise by design.",
  lede:
    "Gateway is a single choke point: it preserves the Anthropic client experience while you swap upstreams and model aliases without touching every machine twice.",
  principles: [
    {
      title: "Any upstream that speaks the shape",
      body:
        "Point at Anthropic-compatible message APIs. Keep per-provider URLs, headers, and auth modes in one importable config.",
    },
    {
      title: "Model names you control",
      body:
        "Expose stable client-visible IDs; translate each alias to the provider and upstream model in your route table.",
    },
    {
      title: "Secrets stay out of Claude config",
      body:
        "Clients authenticate with a local bearer key. Provider keys never get copied into Claude Desktop or Claude Code config files.",
    },
  ],
};

export const wireCopy = {
  title: "One hop. No mystery.",
  lede:
    "Every request is authorized locally, matched to a route, then forwarded over HTTPS to the upstream you picked.",
  railCaption: "Single hop · local auth · TLS upstream",
  nodes: [
    { label: "Claude clients", sub: "Desktop · Code" },
    { label: "Gateway", sub: "Keys · routes · logs", highlight: true as const },
    { label: "Upstream", sub: "Your API" },
  ],
};

export const launchSteps = [
  {
    title: "Download",
    body: "Grab the latest macOS DMG from Releases.",
  },
  {
    title: "Install",
    body: "Drag into Applications and open once to seed prefs.",
  },
  {
    title: "Wire providers",
    body: "Paste credentials and confirm model aliases in the app.",
  },
  {
    title: "Sync & run",
    body: "Save, let the LaunchAgent come up, point clients at loopback.",
  },
];

export const closerCopy = {
  title: "Ship traffic you can explain.",
  lede:
    "Install, route once, and keep Claude on the tools you already pay for and audit.",
  compat: "macOS 14.4+ · Apple Silicon & Intel",
};

export const faqItems = [
  {
    q: "Do I need an Anthropic API key in Claude?",
    a: "No. Clients use a local gateway token. Only the upstream call carries your provider credential.",
  },
  {
    q: "Which providers qualify?",
    a: "Anything that correctly implements an Anthropic-compatible messages endpoint—you set base URL, headers, and auth mode per provider.",
  },
  {
    q: "Is this a replacement for Claude Desktop?",
    a: "It sits beside Desktop and Code: they stay as-is while their traffic exits through your gateway instead of directly to a vendor URL.",
  },
  {
    q: "How do model aliases work?",
    a: "Clients send familiar model IDs; the gateway rewrites each to the provider + model string you configured for that alias.",
  },
  {
    q: "Where do I start debugging?",
    a: "Use the in-app log stream and the bundled doctor script; deeper notes live in the repo docs.",
  },
];
