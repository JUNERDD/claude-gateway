"use client";

import { motion } from "motion/react";
import { ArrowDownToLine } from "lucide-react";
import { downloadUrl, githubUrl } from "@/lib/site-urls";
import { closerCopy, faqItems } from "@/lib/landing-content";
import { rise, stagger, viewportSoft } from "./motion-presets";

export function LandingCloser() {
  return (
    <section
      className="border-t border-white/[0.07] bg-[#080809] px-4 py-24 md:px-6 md:py-32"
      aria-labelledby="closer-title"
    >
      <div className="mx-auto max-w-7xl">
        <motion.div
          className="grid gap-16 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)] lg:gap-20"
          initial="hidden"
          whileInView="visible"
          viewport={viewportSoft}
          variants={stagger}
        >
          <div>
            <motion.h2
              id="closer-title"
              variants={rise}
              className="font-serif text-3xl font-semibold tracking-[-0.02em] text-white md:text-4xl"
            >
              {closerCopy.title}
            </motion.h2>
            <motion.p variants={rise} className="mt-5 max-w-md text-white/60">
              {closerCopy.lede}
            </motion.p>
            <motion.div variants={rise} className="mt-10">
              <a
                href={downloadUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex h-12 items-center justify-center gap-2 rounded-full bg-[#c8ff3d] px-8 text-sm font-semibold text-black transition hover:brightness-105"
              >
                <ArrowDownToLine className="size-4" aria-hidden />
                Download latest
              </a>
              <p className="mt-4 font-mono text-xs text-white/40">
                {closerCopy.compat}
              </p>
              <a
                href={githubUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="mt-6 inline-block text-sm text-white/50 underline decoration-white/25 underline-offset-4 transition hover:text-white"
              >
                Browse source →
              </a>
            </motion.div>
          </div>

          <motion.section
            id="faq"
            variants={rise}
            aria-labelledby="faq-heading"
          >
            <h2
              id="faq-heading"
              className="font-mono text-[10px] font-bold uppercase tracking-[0.2em] text-[#c8ff3d]/75"
            >
              Questions
            </h2>
            <div className="mt-6 divide-y divide-white/[0.08] border-t border-white/[0.08]">
              {faqItems.map((item) => (
                <details
                  key={item.q}
                  className="group border-b border-white/[0.08]"
                >
                  <summary className="cursor-pointer list-none py-5 pr-4 text-left text-sm font-medium text-white marker:content-none [&::-webkit-details-marker]:hidden">
                    <span className="flex items-start justify-between gap-4">
                      {item.q}
                      <span className="mt-0.5 shrink-0 text-[#c8ff3d] transition group-open:rotate-45">
                        +
                      </span>
                    </span>
                  </summary>
                  <p className="pb-5 text-sm leading-relaxed text-white/55">
                    {item.a}
                  </p>
                </details>
              ))}
            </div>
          </motion.section>
        </motion.div>
      </div>
    </section>
  );
}
