"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import { cx } from "@/lib/cx";
import { Menu, X } from "lucide-react";
import { githubUrl } from "@/lib/site-urls";

const nav = [
  { href: "#manifesto", label: "Principles" },
  { href: "#wire", label: "Path" },
  { href: "#setup", label: "Install" },
  { href: "#faq", label: "FAQ" },
] as const;

const menuEase = [0.22, 1, 0.36, 1] as const;

const mobileLinkList = {
  open: {
    transition: { staggerChildren: 0.045, delayChildren: 0.1 },
  },
} as const;

const mobileLinkItem = {
  closed: { opacity: 0, x: -10 },
  open: {
    opacity: 1,
    x: 0,
    transition: { duration: 0.24, ease: menuEase },
  },
} as const;

function NavLinksDesktop({ onNavigate }: { onNavigate: () => void }) {
  return (
    <>
      {nav.map((itemNav) => (
        <a
          key={itemNav.href}
          href={itemNav.href}
          className="rounded-xl px-3 py-2 text-sm text-white/65 transition hover:bg-white/[0.06] hover:text-white"
          onClick={onNavigate}
        >
          {itemNav.label}
        </a>
      ))}
      <a
        href={githubUrl}
        target="_blank"
        rel="noopener noreferrer"
        className="rounded-xl border border-[#c8ff3d]/35 bg-[#c8ff3d]/10 px-3 py-2 text-sm font-medium text-[#c8ff3d] hover:bg-[#c8ff3d]/18 md:ml-2"
        onClick={onNavigate}
      >
        Source
      </a>
    </>
  );
}

function NavLinksMobile({ onNavigate }: { onNavigate: () => void }) {
  return (
    <>
      {nav.map((itemNav) => (
        <motion.a
          key={itemNav.href}
          href={itemNav.href}
          className="rounded-xl px-3 py-3 text-[15px] font-medium text-white"
          variants={mobileLinkItem}
          onClick={onNavigate}
        >
          {itemNav.label}
        </motion.a>
      ))}
      <motion.a
        href={githubUrl}
        target="_blank"
        rel="noopener noreferrer"
        className="mt-1 rounded-xl border border-[#c8ff3d]/40 bg-[#c8ff3d]/12 px-3 py-3 text-center text-[15px] font-semibold text-[#c8ff3d] hover:bg-[#c8ff3d]/18"
        variants={mobileLinkItem}
        onClick={onNavigate}
      >
        Source
      </motion.a>
    </>
  );
}

export function LandingHeader() {
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!open) return;
    const onEsc = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    window.addEventListener("keydown", onEsc);
    return () => window.removeEventListener("keydown", onEsc);
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
    };
  }, [open]);

  useEffect(() => {
    const mq = window.matchMedia("(min-width: 768px)");
    const close = () => {
      if (mq.matches) setOpen(false);
    };
    mq.addEventListener("change", close);
    return () => mq.removeEventListener("change", close);
  }, []);

  return (
    <>
      <AnimatePresence>
        {open ? (
          <motion.div
            key="nav-backdrop"
            className="fixed inset-0 z-40 bg-black/75 backdrop-blur-sm md:hidden"
            aria-hidden
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.22, ease: menuEase }}
            onClick={() => setOpen(false)}
          />
        ) : null}
      </AnimatePresence>

      <header className="pointer-events-none fixed inset-x-0 top-0 z-50 flex justify-center px-4 pt-4 md:px-6">
        <div
          className={cx(
            "pointer-events-auto relative flex w-full max-w-7xl items-center justify-between gap-4 rounded-2xl border border-white/[0.08] bg-black/35 px-4 py-3 backdrop-blur-md",
            "supports-backdrop-filter:bg-black/25",
          )}
        >
          <a
            href="#top"
            className="flex min-w-0 items-center gap-3 text-white no-underline"
            aria-label="Claude Gateway home"
            onClick={() => setOpen(false)}
          >
            <Image
              src="/app-icon.png"
              width={36}
              height={36}
              alt=""
              className="size-9 shrink-0 rounded-xl ring-1 ring-white/10"
              priority
            />
            <span className="truncate font-medium tracking-tight text-white">
              Claude Gateway
            </span>
          </a>

          <button
            type="button"
            className="inline-flex size-10 shrink-0 items-center justify-center rounded-xl border border-white/15 text-white md:hidden"
            aria-label={open ? "Close menu" : "Open menu"}
            aria-expanded={open}
            aria-controls={open ? "primary-nav-mobile" : "primary-nav"}
            onClick={() => setOpen((v) => !v)}
          >
            {open ? <X size={20} /> : <Menu size={20} />}
          </button>

          <nav
            className="relative z-[1] hidden flex-row items-center gap-1 md:flex"
            aria-label="Primary"
            id="primary-nav"
          >
            <NavLinksDesktop onNavigate={() => {}} />
          </nav>

          <AnimatePresence>
            {open ? (
              <motion.nav
                key="primary-nav-mobile"
                id="primary-nav-mobile"
                className="absolute inset-x-0 top-[calc(100%+0.5rem)] z-[1] flex md:hidden flex-col rounded-2xl border border-white/[0.12] bg-[#0c0c0e] p-2 shadow-[0_28px_64px_-12px_rgba(0,0,0,0.92)]"
                aria-label="Primary"
                initial={{ opacity: 0, y: -14, scale: 0.98 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                exit={{ opacity: 0, y: -10, scale: 0.98 }}
                transition={{ duration: 0.28, ease: menuEase }}
              >
                <motion.div
                  className="flex flex-col"
                  variants={mobileLinkList}
                  initial="closed"
                  animate="open"
                >
                  <NavLinksMobile onNavigate={() => setOpen(false)} />
                </motion.div>
              </motion.nav>
            ) : null}
          </AnimatePresence>
        </div>
      </header>
    </>
  );
}
