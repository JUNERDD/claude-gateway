"use client";

import { motion } from "motion/react";
import { launchSteps } from "@/lib/landing-content";
import { rise, stagger, viewportSoft } from "./motion-presets";
import { LandingTerminal } from "./LandingTerminal";

export function LandingLaunch() {
  return (
    <section
      id="setup"
      className="border-t border-white/[0.07] bg-[#050506] px-4 py-24 md:px-6 md:py-32"
      aria-labelledby="launch-title"
    >
      <div className="mx-auto grid max-w-7xl gap-16 lg:grid-cols-[1fr_minmax(300px,400px)] lg:gap-20">
        <motion.div
          initial="hidden"
          whileInView="visible"
          viewport={viewportSoft}
          variants={stagger}
        >
          <motion.p
            variants={rise}
            className="font-mono text-[10px] font-bold uppercase tracking-[0.2em] text-[#c8ff3d]/75"
          >
            Install
          </motion.p>
          <motion.h2
            id="launch-title"
            variants={rise}
            className="mt-4 font-serif text-3xl font-semibold tracking-[-0.02em] text-white md:text-4xl"
          >
            Four beats. Running service.
          </motion.h2>
          <motion.ol variants={stagger} className="mt-12 space-y-0">
            {launchSteps.map((step, i) => (
              <motion.li
                key={step.title}
                variants={rise}
                className="border-t border-white/[0.08] py-10 first:border-t-0 first:pt-0 last:pb-0"
              >
                <div className="flex gap-8">
                  <span className="font-mono text-3xl font-bold tabular-nums text-white/20 md:text-4xl">
                    {String(i + 1).padStart(2, "0")}
                  </span>
                  <div>
                    <h3 className="text-lg font-semibold text-white">
                      {step.title}
                    </h3>
                    <p className="mt-2 max-w-md text-sm leading-relaxed text-white/55">
                      {step.body}
                    </p>
                  </div>
                </div>
              </motion.li>
            ))}
          </motion.ol>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 24 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={viewportSoft}
          transition={{ duration: 0.55, ease: [0.22, 1, 0.36, 1] }}
          className="min-w-0 lg:pt-14"
        >
          <LandingTerminal />
        </motion.div>
      </div>
    </section>
  );
}
