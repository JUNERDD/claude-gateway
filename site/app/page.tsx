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
  PackageOpen,
  Server,
  ShieldCheck,
  Terminal,
} from "lucide-react";

const downloadUrl =
  "https://github.com/JUNERDD/claude-deepseek-gateway/releases/latest/download/ClaudeDeepSeekGateway-latest.dmg";
const githubUrl = "https://github.com/JUNERDD/claude-deepseek-gateway";
const defaultEndpoint = "127.0.0.1:4000";

const features = [
  {
    icon: KeyRound,
    title: "Your keys never leave",
    text: "API keys stay on your Mac. The gateway hands Claude a local bearer token instead of your upstream key.",
  },
  {
    icon: Code2,
    title: "Open source",
    text: "Every line is public. Inspect the code, audit the proxy, verify there's no telemetry.",
  },
  {
    icon: ShieldCheck,
    title: "No middleman",
    text: "Requests go directly from your machine to DeepSeek over HTTPS. No cloud relay, no third party.",
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
    text: "Add your DeepSeek API key locally.",
  },
  {
    icon: CheckCircle2,
    title: "Go",
    text: `Point Claude to ${defaultEndpoint}.`,
  },
];

const trustRows = [
  {
    icon: KeyRound,
    label: "API keys",
    detail: "Stored on your Mac, never transmitted",
  },
  {
    icon: Server,
    label: "Requests",
    detail: "Encrypted HTTPS to DeepSeek only",
  },
  {
    icon: HardDrive,
    label: "Logs",
    detail: "Local file you control, nothing phoned home",
  },
];

const faqs = [
  {
    question: "Do I need an Anthropic API key?",
    answer:
      "No. Claude clients authenticate with a local bearer key. Upstream requests use your DeepSeek API key.",
  },
  {
    question: "Does this replace Claude Desktop or Claude Code?",
    answer:
      "No. It runs alongside them, exposing a local Anthropic-compatible endpoint that forwards to DeepSeek.",
  },
  {
    question: "How does model name translation work?",
    answer:
      "Claude clients send model IDs like claude-sonnet-4-6. The gateway rewrites them to the DeepSeek model you configured before forwarding.",
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

  return (
    <MotionConfig reducedMotion="user">
    <main>
      {/* Header */}
      <header className="site-header">
        <Link
          className="brand-mark"
          href="#top"
          aria-label="Claude DeepSeek Gateway home"
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
          <span>Claude DeepSeek Gateway</span>
        </Link>
        <nav className="top-nav" aria-label="Primary navigation">
          <Link href="#features">Features</Link>
          <Link href="#setup">Setup</Link>
          <Link href={githubUrl} className="nav-cta">
            GitHub
          </Link>
        </nav>
      </header>

      {/* Hero */}
      <section id="top" className="hero-section">
        <div className="hero-copy">
          <p className="hero-kicker">Local first. Open source. Zero telemetry.</p>
          <h1>
            Claude <i>→</i> DeepSeek
          </h1>
          <div className="hero-endpoint" aria-label="Default endpoint">
            <span>{defaultEndpoint}</span>
          </div>
          <p className="hero-lede">
            A native macOS gateway that routes Claude Desktop and Claude Code
            requests to DeepSeek through a local Anthropic-compatible endpoint.
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

        <figure className="product-stage" aria-label="Gateway app preview">
          <div className="product-window">
            <div className="visual-toolbar" aria-hidden="true">
              <span />
              <span />
              <span />
              <strong>Claude DeepSeek Gateway</strong>
            </div>
            <Image
              src="/product-overview.png"
              width={1580}
              height={1041}
              alt="Claude DeepSeek Gateway macOS app overview showing gateway status, endpoint, provider, request metrics, and recent requests."
              priority
              className="product-shot"
            />
          </div>
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
          <h2 id="features-heading">Everything stays on your machine.</h2>
          <p>
            No cloud dashboard, no telemetry, no third party between you and
            DeepSeek.
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
          <h2 id="route-heading">One hop. Zero leaks.</h2>
          <p>
            Claude talks to localhost. The gateway rewrites model names
            and forwards to DeepSeek over HTTPS.
          </p>
        </motion.div>
        <motion.div
          className="route-diagram"
          aria-label="Claude clients route through local gateway to DeepSeek"
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
            <strong>Claude Desktop</strong>
            <span>or Claude Code</span>
          </motion.div>

          <div className="route-pipe" aria-hidden="true">
            <span className="route-pipe-line" />
            <ArrowRight className="route-pipe-arrow" size={14} />
          </div>

          <motion.div className="route-node route-node-active" variants={itemReveal}>
            <span className="route-node-icon">
              <Terminal aria-hidden="true" size={22} />
            </span>
            <strong>Gateway</strong>
            <span>Model rewrite + proxy</span>
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
            <strong>DeepSeek</strong>
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
          <h2 id="setup-heading">Four steps to running.</h2>
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
              claude
              {"\n"}
              <span className="cmd-comment"># That's it.</span>
            </div>
            <div className="setup-terminal-foot">
              <span>bash / zsh</span>
              <button
                type="button"
                onClick={() => {
                  navigator.clipboard.writeText(
                    `export ANTHROPIC_BASE_URL=http://${defaultEndpoint}`
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
          <h2 id="final-cta-heading">Use Claude. Pay DeepSeek.</h2>
          <p>Keep your workflow, cut your API costs.</p>
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
          Claude DeepSeek Gateway
        </span>
        <Link href={githubUrl}>GitHub</Link>
        <Link href={`${githubUrl}/blob/main/SECURITY.md`}>Security</Link>
        <Link href={`${githubUrl}/blob/main/LICENSE`}>License</Link>
      </footer>
    </main>
    </MotionConfig>
  );
}
