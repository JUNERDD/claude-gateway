"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import { Link } from "@heroui/react";
import {
  MotionConfig,
  motion,
  type Variants,
  type ViewportOptions,
} from "motion/react";
import {
  ArrowDownToLine,
  ArrowRight,
  CheckCircle2,
  ChevronDown,
  Code2,
  Copy,
  GitFork,
  HardDrive,
  KeyRound,
  Menu,
  PackageOpen,
  Server,
  ShieldCheck,
  Terminal,
  X,
} from "lucide-react";

const downloadUrl =
  "https://github.com/JUNERDD/claude-gateway/releases/latest/download/ClaudeGateway-latest.dmg";
const githubUrl = "https://github.com/JUNERDD/claude-gateway";
const defaultEndpoint = "127.0.0.1:4000";

const features = [
  {
    icon: Server,
    title: "Bring any provider",
    text: "Register one or more Anthropic-compatible upstreams and keep provider-specific endpoints, headers, and auth modes local.",
  },
  {
    icon: GitFork,
    title: "Route models explicitly",
    text: "Expose Claude-visible model names while mapping each one to the provider and upstream model you choose.",
  },
  {
    icon: KeyRound,
    title: "Separate local secrets",
    text: "Claude clients use a local gateway key. Provider API keys stay in app-managed local secrets and never get copied into Claude config.",
  },
];

const setupSteps = [
  {
    icon: ArrowDownToLine,
    title: "Download",
    text: "Get the latest DMG for macOS.",
  },
  {
    icon: PackageOpen,
    title: "Install",
    text: "Drag to Applications and launch.",
  },
  {
    icon: ShieldCheck,
    title: "Configure",
    text: "Add providers, model routes, and the local gateway key.",
  },
  {
    icon: CheckCircle2,
    title: "Go",
    text: "Save, sync, and start the local LaunchAgent.",
  },
];

const trustRows = [
  {
    icon: KeyRound,
    label: "API keys",
    detail: "Stored in local app-managed secrets",
  },
  {
    icon: Server,
    label: "Providers",
    detail: "Any Anthropic-compatible upstream",
  },
  {
    icon: HardDrive,
    label: "Logs",
    detail: "Local files you control, no telemetry",
  },
];

const faqs = [
  {
    question: "Do I need an Anthropic API key?",
    answer:
      "No. Claude clients authenticate with a local bearer key. Upstream requests use your configured provider key.",
  },
  {
    question: "Which providers work?",
    answer:
      "Any provider that exposes an Anthropic-compatible messages API can be configured with its own base URL, auth mode, headers, and model routes.",
  },
  {
    question: "Does this replace Claude Desktop or Claude Code?",
    answer:
      "No. It runs alongside them, exposing a local Anthropic-compatible endpoint that forwards to your provider.",
  },
  {
    question: "How does model name translation work?",
    answer:
      "Claude clients send model IDs like claude-sonnet-4-6. The gateway rewrites each alias to the provider and upstream model configured in your route table.",
  },
  {
    question: "Where do I troubleshoot issues?",
    answer:
      "Start with the app's Logs view and the bundled doctor script. Full docs are on GitHub.",
  },
];

const sectionReveal: Variants = {
  hidden: { opacity: 0, y: 34 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.68, ease: "easeOut" },
  },
};

const itemReveal: Variants = {
  hidden: { opacity: 0, y: 18 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.48, ease: "easeOut" },
  },
};

const staggeredReveal: Variants = {
  hidden: {},
  visible: {
    transition: {
      staggerChildren: 0.08,
      delayChildren: 0.08,
    },
  },
};

const viewport: ViewportOptions = { once: true, amount: 0.24 };

export default function Home() {
  const [openFaq, setOpenFaq] = useState(-1);
  const [isNavOpen, setIsNavOpen] = useState(false);

  useEffect(() => {
    const scrollToHash = () => {
      const targetId = window.location.hash.slice(1);
      if (!targetId) return;
      window.requestAnimationFrame(() => {
        document.getElementById(targetId)?.scrollIntoView({ block: "start" });
      });
    };
    scrollToHash();
    window.addEventListener("hashchange", scrollToHash);
    return () => window.removeEventListener("hashchange", scrollToHash);
  }, []);

  useEffect(() => {
    if (!isNavOpen) return;

    const closeFromOutside = (event: PointerEvent) => {
      if (event.target instanceof Element && event.target.closest(".site-header")) {
        return;
      }
      setIsNavOpen(false);
    };
    const closeFromEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setIsNavOpen(false);
      }
    };
    const closeOnWideViewport = () => {
      if (window.innerWidth > 820) {
        setIsNavOpen(false);
      }
    };

    window.addEventListener("pointerdown", closeFromOutside);
    window.addEventListener("keydown", closeFromEscape);
    window.addEventListener("resize", closeOnWideViewport);
    return () => {
      window.removeEventListener("pointerdown", closeFromOutside);
      window.removeEventListener("keydown", closeFromEscape);
      window.removeEventListener("resize", closeOnWideViewport);
    };
  }, [isNavOpen]);

  return (
    <MotionConfig reducedMotion="user">
    <main>
      {/* Header */}
      <header className="site-header">
        <Link
          className="brand-mark"
          href="#top"
          aria-label="Claude Gateway home"
        >
          <span className="brand-mark-group">
            <Image
              src="/app-icon.png"
              width={32}
              height={32}
              alt=""
              priority
              className="brand-icon"
            />
            <span className="brand-dot" aria-hidden="true" />
          </span>
          <span>Claude Gateway</span>
        </Link>
        <button
          className="menu-toggle"
          type="button"
          aria-label={isNavOpen ? "Close navigation" : "Open navigation"}
          aria-expanded={isNavOpen}
          aria-controls="primary-nav"
          onClick={() => setIsNavOpen((open) => !open)}
        >
          {isNavOpen ? <X aria-hidden="true" size={20} /> : <Menu aria-hidden="true" size={20} />}
        </button>
        <nav
          id="primary-nav"
          className={`top-nav ${isNavOpen ? "is-open" : ""}`}
          aria-label="Primary navigation"
        >
          <Link href="#features" onClick={() => setIsNavOpen(false)}>Features</Link>
          <Link href="#setup" onClick={() => setIsNavOpen(false)}>Setup</Link>
          <Link href={githubUrl} className="nav-cta" onClick={() => setIsNavOpen(false)}>
            GitHub
          </Link>
        </nav>
      </header>

      {/* Hero */}
      <section id="top" className="hero-section">
        <div className="hero-copy">
          <p className="hero-kicker">Local macOS control plane for Claude clients</p>
          <h1>
            Claude Gateway
          </h1>
          <div className="hero-endpoint" aria-label="Default endpoint">
            <span>{"Claude clients -> localhost -> your providers"}</span>
          </div>
          <p className="hero-lede">
            Route Claude Desktop and Claude Code through a local gateway that
            owns provider configuration, model aliases, secrets, logs, and sync.
          </p>
          <div className="hero-actions">
            <Link className="primary-action" href={downloadUrl}>
              <ArrowDownToLine aria-hidden="true" size={18} />
              Download for macOS
            </Link>
            <Link className="secondary-action" href={githubUrl}>
              <GitFork aria-hidden="true" size={18} />
              View source
            </Link>
          </div>
        </div>

        <figure className="product-shot-wrap" aria-label="Gateway app preview">
          <Image
            src="/product-overview.png"
            width={1580}
            height={1041}
            alt="Claude Gateway macOS app overview showing local gateway status, provider routes, endpoint, request metrics, and recent requests."
            priority
          />
        </figure>
      </section>

      {/* Features */}
      <motion.section
        id="features"
        className="features-section"
        aria-labelledby="features-heading"
        variants={sectionReveal}
        initial="hidden"
        whileInView="visible"
        viewport={viewport}
      >
        <div className="section-heading">
          <p className="eyebrow">Why local</p>
          <h2 id="features-heading">Provider control without another cloud account.</h2>
          <p>
            Claude Gateway is the local boundary between Claude clients and the
            upstream providers you already use.
          </p>
        </div>

        <motion.div
          className="features-grid"
          variants={staggeredReveal}
          initial="hidden"
          whileInView="visible"
          viewport={viewport}
        >
          {features.map((item) => {
            const Icon = item.icon;
            return (
              <motion.article key={item.title} className="feature-card" variants={itemReveal}>
                <span className="feature-icon">
                  <Icon aria-hidden="true" size={22} />
                </span>
                <h3>{item.title}</h3>
                <p>{item.text}</p>
              </motion.article>
            );
          })}
        </motion.div>

        <motion.div
          className="trust-ledger"
          variants={staggeredReveal}
          initial="hidden"
          whileInView="visible"
          viewport={viewport}
          aria-label="Privacy guarantees"
        >
          {trustRows.map((row) => (
            <motion.div key={row.label} className="trust-row" variants={itemReveal}>
              <row.icon aria-hidden="true" size={20} />
              <div>
                <strong>{row.label}</strong>
                <span>{row.detail}</span>
              </div>
            </motion.div>
          ))}
        </motion.div>
      </motion.section>

      {/* How it routes */}
      <section
        id="api"
        className="route-section"
        aria-labelledby="route-heading"
      >
        <motion.div
          className="section-heading"
          variants={sectionReveal}
          initial="hidden"
          whileInView="visible"
          viewport={viewport}
        >
          <p className="eyebrow">How it routes</p>
          <h2 id="route-heading">Claude talks to localhost. Gateway handles the rest.</h2>
          <p>
            Each request is authenticated locally, matched against your model
            route table, and forwarded over HTTPS to the selected provider.
          </p>
        </motion.div>
        <motion.div
          className="route-diagram"
          aria-label="Claude clients route through local gateway to a configured upstream provider"
          variants={staggeredReveal}
          initial="hidden"
          whileInView="visible"
          viewport={viewport}
        >
          <div className="route-bg-particles" aria-hidden="true">
            <span className="route-bg-particle" />
            <span className="route-bg-particle" />
            <span className="route-bg-particle" />
            <span className="route-bg-particle" />
            <span className="route-bg-particle" />
          </div>

          <motion.div className="route-node" variants={itemReveal}>
            <span className="route-node-icon">
              <Code2 aria-hidden="true" size={22} />
            </span>
            <strong>Claude clients</strong>
            <span>Desktop + Code</span>
          </motion.div>

          <div className="route-pipe" aria-hidden="true">
            <span className="route-pipe-line" />
            <ArrowRight className="route-pipe-arrow" size={14} />
          </div>

          <motion.div className="route-node route-node-active" variants={itemReveal}>
            <span className="route-node-icon">
              <Terminal aria-hidden="true" size={22} />
            </span>
            <strong>Claude Gateway</strong>
            <span>Keys, routes, logs</span>
            <div className="route-endpoint-badge" aria-label="Local endpoint">
              <span className="route-endpoint-dot" />
              {defaultEndpoint}
            </div>
          </motion.div>

          <div className="route-pipe" aria-hidden="true">
            <span className="route-pipe-line" />
            <ArrowRight className="route-pipe-arrow" size={14} />
          </div>

          <motion.div className="route-node" variants={itemReveal}>
            <span className="route-node-icon">
              <Server aria-hidden="true" size={22} />
            </span>
            <strong>Providers</strong>
            <span>Anthropic-compatible API</span>
          </motion.div>
        </motion.div>
      </section>

      {/* Setup */}
      <section
        id="setup"
        className="setup-section"
        aria-labelledby="setup-heading"
      >
        <div className="section-heading" style={{ marginBottom: 52 }}>
          <p className="eyebrow">Get started</p>
          <h2 id="setup-heading">Four steps from install to synced Claude clients.</h2>
        </div>

        <div className="setup-inner">
          <motion.ol
            className="setup-steps"
            variants={staggeredReveal}
            initial="hidden"
            whileInView="visible"
            viewport={viewport}
          >
            {setupSteps.map((step, index) => (
              <motion.li key={step.title} className="setup-step" variants={itemReveal}>
                <div className="step-number-col">
                  <span className="step-number">
                    {String(index + 1).padStart(2, "0")}
                  </span>
                  <span className="step-number-sub">Step</span>
                </div>
                <div className="step-body">
                  <h3>{step.title}</h3>
                  <p>{step.text}</p>
                </div>
              </motion.li>
            ))}
          </motion.ol>

          <motion.div
            className="setup-terminal-block"
            initial={{ opacity: 0, y: 24 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={viewport}
            transition={{ duration: 0.6, ease: "easeOut", delay: 0.2 }}
          >
            <div className="setup-terminal-head" aria-hidden="true">
              <span className="setup-terminal-dot" />
              <span className="setup-terminal-dot" />
              <span className="setup-terminal-dot" />
              <span className="setup-terminal-title">Terminal</span>
            </div>
            <div className="setup-terminal-body">
              <span className="cmd-prompt">$ </span>
              <span className="cmd-export">export</span>
              {" "}ANTHROPIC_BASE_URL=
              <span className="cmd-value">http://{defaultEndpoint}</span>
              {"\n"}
              <span className="cmd-prompt">$ </span>
              <span className="cmd-export">export</span>
              {" "}ANTHROPIC_AUTH_TOKEN=
              <span className="cmd-value">local-gateway-key</span>
              {"\n"}
              <span className="cmd-prompt">$ </span>
              claude
              {"\n"}
              <span className="cmd-comment"># That&apos;s it.</span>
            </div>
            <div className="setup-terminal-foot">
              <span>bash / zsh</span>
              <button
                type="button"
                onClick={() => {
                  navigator.clipboard.writeText(
                    `export ANTHROPIC_BASE_URL=http://${defaultEndpoint}\nexport ANTHROPIC_AUTH_TOKEN=local-gateway-key`
                  );
                }}
              >
                <Copy aria-hidden="true" size={13} />
                Copy
              </button>
            </div>
          </motion.div>
        </div>
      </section>

      {/* CTA + FAQ */}
      <section
        className="closing-section"
        aria-labelledby="final-cta-heading"
      >
        <motion.div
          className="final-cta"
          variants={sectionReveal}
          initial="hidden"
          whileInView="visible"
          viewport={viewport}
        >
          <p className="eyebrow">Ready when you are</p>
          <h2 id="final-cta-heading">Use Claude with the providers you control.</h2>
          <p>Install the app, configure routes locally, and keep Claude synced.</p>
          <Link className="primary-action" href={downloadUrl}>
            Download latest DMG
            <ArrowDownToLine aria-hidden="true" size={18} />
          </Link>
          <span className="compatibility-note">macOS 14.4+ &middot; Apple Silicon &amp; Intel</span>
        </motion.div>
        <div
          id="faq"
          className="faq-column"
          aria-labelledby="faq-heading"
        >
          <motion.div
            variants={sectionReveal}
            initial="hidden"
            whileInView="visible"
            viewport={viewport}
          >
            <p id="faq-heading" className="eyebrow">FAQ</p>
            <div className="faq-accordion">
              {faqs.map((item, index) => (
                <details
                  key={item.question}
                  className="faq-item"
                  open={openFaq === index}
                  onToggle={(event) => {
                    if (event.currentTarget.open) {
                      setOpenFaq(index);
                      return;
                    }
                    setOpenFaq((current) => (current === index ? -1 : current));
                  }}
                >
                  <summary className="faq-trigger">
                    <span>{item.question}</span>
                    <ChevronDown aria-hidden="true" size={18} />
                  </summary>
                  <div className="faq-panel">
                    <p>{item.answer}</p>
                  </div>
                </details>
              ))}
            </div>
          </motion.div>
        </div>
      </section>

      {/* Footer */}
      <footer className="site-footer">
        <span className="footer-brand">
          <Terminal aria-hidden="true" size={20} />
          Claude Gateway
        </span>
        <Link href={githubUrl}>GitHub</Link>
        <Link href={`${githubUrl}/blob/main/SECURITY.md`}>Security</Link>
        <Link href={`${githubUrl}/blob/main/LICENSE`}>License</Link>
      </footer>
    </main>
    </MotionConfig>
  );
}
