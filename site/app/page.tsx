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
  Clipboard,
  Code2,
  Database,
  ExternalLink,
  GitFork,
  HardDrive,
  KeyRound,
  Laptop,
  PackageOpen,
  Route,
  Server,
  Settings2,
  ShieldCheck,
  ShieldOff,
  Terminal,
} from "lucide-react";

const downloadUrl =
  "https://github.com/JUNERDD/claude-deepseek-gateway/releases/latest/download/ClaudeDeepSeekGateway-latest.dmg";
const githubUrl = "https://github.com/JUNERDD/claude-deepseek-gateway";
const readmeUrl =
  "https://github.com/JUNERDD/claude-deepseek-gateway#readme";
const defaultEndpoint = "127.0.0.1:4000";

const principles = [
  {
    icon: Laptop,
    title: "Runs on your Mac",
    text: "The gateway listens locally and stays visible in a native control surface.",
  },
  {
    icon: KeyRound,
    title: "Keys stay local",
    text: "Claude clients receive a separate local bearer key, not your upstream key.",
  },
  {
    icon: ShieldOff,
    title: "No tracking",
    text: "No custom analytics scripts, cookies, or telemetry are added to this site.",
  },
];

const localProofs = [
  {
    icon: KeyRound,
    title: "You keep your keys",
    text: "Stored locally. Never sent to us.",
  },
  {
    icon: ShieldOff,
    title: "No tracking",
    text: "No analytics. No telemetry.",
  },
  {
    icon: Code2,
    title: "Open source",
    text: "Inspect the code. Verify everything.",
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

const routeNodes = [
  {
    icon: Code2,
    title: "Claude Desktop",
    detail: "or Claude Code",
  },
  {
    icon: Terminal,
    title: "Claude DeepSeek",
    detail: "Gateway",
    active: true,
  },
  {
    icon: Route,
    title: "DeepSeek",
    detail: "Anthropic-compatible",
  },
];

const trustRows = [
  {
    icon: Server,
    label: "Requests",
    detail: "From Claude to DeepSeek",
    status: "Allowed",
  },
  {
    icon: KeyRound,
    label: "API keys",
    detail: "Stored on your Mac",
    status: "Local only",
  },
  {
    icon: ShieldOff,
    label: "Telemetry",
    detail: "No analytics. No pings.",
    status: "Blocked",
  },
  {
    icon: Database,
    label: "Logs",
    detail: "Local log file you control",
    status: "Local only",
  },
  {
    icon: Code2,
    label: "Source code",
    detail: "Open source",
    status: "Public",
  },
];

const faqs = [
  {
    question: "Do I need an Anthropic API key?",
    answer:
      "No. Claude clients receive a local bearer key for the gateway. Upstream text requests use your DeepSeek API key.",
  },
  {
    question: "Does this replace Claude Desktop or Claude Code?",
    answer:
      "No. It sits between those clients and DeepSeek, exposing a local Anthropic-compatible endpoint on your Mac.",
  },
  {
    question: "Why expose claude-* model names?",
    answer:
      "Claude clients expect Claude-style model identifiers. The gateway rewrites the model field before forwarding the request.",
  },
  {
    question: "Where do I troubleshoot setup issues?",
    answer:
      "Use the app's Issues and Logs views first, then run the bundled doctor script or open the full README.",
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
  const [openFaq, setOpenFaq] = useState(0);

  useEffect(() => {
    const scrollToHash = () => {
      const targetId = window.location.hash.slice(1);
      if (!targetId) {
        return;
      }

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
      <header className="site-header">
        <Link
          className="brand-mark"
          href="#top"
          aria-label="Claude DeepSeek Gateway home"
        >
          <Image
            src="/app-icon.png"
            width={36}
            height={36}
            alt=""
            priority
            className="brand-icon"
          />
          <span>Claude DeepSeek Gateway</span>
        </Link>
        <nav className="top-nav" aria-label="Primary navigation">
          <Link href={readmeUrl}>Docs</Link>
          <Link href="#setup">Installation</Link>
          <Link href="#api">API</Link>
          <Link href={githubUrl}>
            GitHub <ExternalLink aria-hidden="true" size={13} />
          </Link>
        </nav>
        <div className="privacy-pill" aria-label="No tracking">
          <span aria-hidden="true" />
          No tracking
        </div>
      </header>

      <section id="top" className="hero-section">
        <div className="hero-copy">
          <p className="hero-kicker">Local Claude-to-DeepSeek gateway</p>
          <h1>
            <span>Claude</span>
            <span>DeepSeek</span>
            <span>Gateway</span>
          </h1>
          <div className="hero-endpoint" aria-label="Default endpoint">
            <span>127.0.0.1</span>
          </div>
          <p className="hero-lede">Open source. Local first. No tracking.</p>
          <div className="hero-actions" aria-label="Download actions">
            <Link className="primary-action" href={downloadUrl}>
              <ArrowDownToLine aria-hidden="true" size={18} />
              Download for macOS
            </Link>
            <Link className="secondary-action" href={githubUrl}>
              <GitFork aria-hidden="true" size={18} />
              View source
            </Link>
          </div>
          <ul className="hero-assurances" aria-label="Product assurances">
            {principles.map((item) => {
              const Icon = item.icon;
              return (
                <li key={item.title}>
                  <Icon aria-hidden="true" size={16} />
                  {item.title}
                </li>
              );
            })}
          </ul>
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
              alt="Claude DeepSeek Gateway macOS app overview with gateway status, endpoint, provider, request metrics, and recent requests."
              priority
              className="product-shot"
            />
          </div>
        </figure>
      </section>

      <motion.section
        className="local-section"
        aria-labelledby="local-heading"
        variants={sectionReveal}
        initial="hidden"
        whileInView="visible"
        viewport={viewport}
      >
        <div className="local-copy">
          <p className="eyebrow">Local by design</p>
          <h2 id="local-heading">Your models. Your keys. Your machine.</h2>
          <p>
            Claude DeepSeek Gateway runs entirely on your Mac. Your requests
            never leave your machine except to DeepSeek.
          </p>
          <motion.div
            className="local-proof-list"
            variants={staggeredReveal}
            initial="hidden"
            whileInView="visible"
            viewport={viewport}
          >
            {localProofs.map((item) => {
              const Icon = item.icon;
              return (
                <motion.article key={item.title} className="local-proof" variants={itemReveal}>
                  <span className="local-proof-icon">
                    <Icon aria-hidden="true" size={20} />
                  </span>
                  <div>
                    <h3>{item.title}</h3>
                    <p>{item.text}</p>
                  </div>
                </motion.article>
              );
            })}
          </motion.div>
        </div>

        <motion.div
          className="status-stage"
          aria-label="Local gateway status"
          initial={{ opacity: 0, scale: 0.94 }}
          whileInView={{ opacity: 1, scale: 1 }}
          viewport={viewport}
          transition={{ duration: 0.7, ease: "easeOut" }}
        >
          <div className="signal-rings" aria-hidden="true">
            <span />
            <span />
            <span />
          </div>
          <div className="status-card">
            <div className="status-dots" aria-hidden="true">
              <span />
              <span />
              <span />
            </div>
            <p className="status-running">
              <span aria-hidden="true" />
              Gateway is running
            </p>
            <dl>
              <div>
                <dt>Endpoint</dt>
                <dd>
                  {defaultEndpoint}
                  <Clipboard aria-hidden="true" size={15} />
                </dd>
              </div>
              <div>
                <dt>Provider</dt>
                <dd>
                  DeepSeek <strong>Active</strong>
                </dd>
              </div>
              <div>
                <dt>Requests today</dt>
                <dd>128</dd>
              </div>
            </dl>
            <div className="status-actions">
              <span>Open Logs</span>
              <Settings2 aria-hidden="true" size={16} />
            </div>
          </div>
        </motion.div>
      </motion.section>

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
          <h2 id="route-heading">Claude talks to localhost.</h2>
          <p>
            Claude Desktop and Claude Code send requests to 127.0.0.1. The
            gateway forwards them to DeepSeek and streams the response back.
          </p>
        </motion.div>
        <motion.div
          className="route-map"
          aria-label="Claude clients route through local gateway to DeepSeek"
          variants={staggeredReveal}
          initial="hidden"
          whileInView="visible"
          viewport={viewport}
        >
          {routeNodes.map((node, index) => {
            const Icon = node.icon;
            return (
              <motion.div
                key={node.title}
                className={node.active ? "route-map-node route-map-node-active" : "route-map-node"}
                variants={itemReveal}
              >
                <Icon aria-hidden="true" size={30} />
                <strong>{node.title}</strong>
                <span>{node.detail}</span>
                {node.active ? <em>127.0.0.1</em> : null}
                {index < routeNodes.length - 1 ? (
                  <ArrowRight className="route-map-arrow" aria-hidden="true" size={28} />
                ) : null}
              </motion.div>
            );
          })}
          <div className="response-stream" aria-hidden="true">Response stream</div>
        </motion.div>
      </section>

      <section
        id="setup"
        className="setup-section"
        aria-labelledby="setup-heading"
      >
        <motion.div
          className="section-heading"
          variants={sectionReveal}
          initial="hidden"
          whileInView="visible"
          viewport={viewport}
        >
          <p className="eyebrow">Get started</p>
          <h2 id="setup-heading">Four steps. No proxy choreography.</h2>
          <Link className="text-link setup-guide-link" href={readmeUrl}>
            View installation guide <ArrowRight aria-hidden="true" size={16} />
          </Link>
        </motion.div>
        <motion.ol
          className="setup-timeline"
          variants={staggeredReveal}
          initial="hidden"
          whileInView="visible"
          viewport={viewport}
        >
          {setupSteps.map((step, index) => (
            <motion.li key={step.title} variants={itemReveal}>
              <span className="step-index">{String(index + 1).padStart(2, "0")}</span>
              <div className="step-icon">
                <step.icon aria-hidden="true" size={22} />
              </div>
              <div>
                <h3>{step.title}</h3>
                <p>{step.text}</p>
              </div>
            </motion.li>
          ))}
        </motion.ol>
        <motion.div
          className="terminal-strip"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={viewport}
          transition={{ duration: 0.54, ease: "easeOut", delay: 0.18 }}
        >
          <code>
            <span>export</span> ANTHROPIC_BASE_URL=<strong>http://{defaultEndpoint}</strong>
          </code>
          <Clipboard aria-hidden="true" size={18} />
        </motion.div>
      </section>

      <section
        id="privacy"
        className="trust-section"
        aria-labelledby="trust-heading"
      >
        <motion.div
          className="trust-statement"
          variants={sectionReveal}
          initial="hidden"
          whileInView="visible"
          viewport={viewport}
        >
          <p className="eyebrow">Trust ledger</p>
          <h2 id="trust-heading">Trust boundary</h2>
          <p>
            Your data stays on your machine. Only model requests go to DeepSeek
            over HTTPS.
          </p>
          <Link className="text-link" href={readmeUrl}>
            Read the threat model <ArrowRight aria-hidden="true" size={16} />
          </Link>
          <div className="architecture-note">
            <LockBadge />
            <div>
              <strong>Client-only architecture</strong>
              <span>No cloud component. No middleman.</span>
            </div>
          </div>
        </motion.div>
        <motion.div
          className="trust-ledger"
          variants={staggeredReveal}
          initial="hidden"
          whileInView="visible"
          viewport={viewport}
        >
          {trustRows.map((row) => (
            <motion.div key={row.label} className="trust-row" variants={itemReveal}>
              <row.icon aria-hidden="true" size={23} />
              <strong>{row.label}</strong>
              <span>{row.detail}</span>
              <em>{row.status}</em>
            </motion.div>
          ))}
        </motion.div>
      </section>

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
          <h2 id="final-cta-heading">Keep control. Ship faster.</h2>
          <p>Route Claude to DeepSeek in minutes.</p>
          <Link className="primary-action" href={downloadUrl}>
            Download latest DMG
            <ArrowDownToLine aria-hidden="true" size={18} />
          </Link>
          <span className="compatibility-note">macOS 14.4+ · Apple Silicon & Intel</span>
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

      <footer className="site-footer">
        <span className="footer-brand">
          <Terminal aria-hidden="true" size={22} />
          Claude DeepSeek Gateway
        </span>
        <Link href={githubUrl}>GitHub</Link>
        <Link href={readmeUrl}>Docs</Link>
        <Link href={readmeUrl}>Security</Link>
      </footer>
    </main>
    </MotionConfig>
  );
}

function LockBadge() {
  return (
    <span className="lock-badge" aria-hidden="true">
      <HardDrive size={21} />
    </span>
  );
}
