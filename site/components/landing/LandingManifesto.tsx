"use client";

import { motion } from "motion/react";
import { manifestoCopy } from "@/lib/landing-content";
import { rise, riseSm, stagger, viewportSoft } from "./motion-presets";

export function LandingManifesto() {
  return (
    <section
      id="manifesto"
      className="border-t border-white/[0.07] bg-[#050506] px-4 py-24 md:px-6 md:py-32"
      aria-labelledby="manifesto-title"
    >
      <motion.div
        className="mx-auto max-w-7xl"
        variants={stagger}
        initial="hidden"
        whileInView="visible"
        viewport={viewportSoft}
      >
        <motion.h2
          id="manifesto-title"
          variants={rise}
          className="max-w-2xl font-serif text-3xl font-semibold tracking-[-0.02em] text-white md:text-5xl"
        >
          {manifestoCopy.title}
        </motion.h2>
        <motion.p
          variants={rise}
          className="mt-6 max-w-2xl text-lg leading-relaxed text-white/65"
        >
          {manifestoCopy.lede}
        </motion.p>

        <motion.ul
          variants={stagger}
          className="mt-16 grid gap-0 md:grid-cols-3 md:divide-x md:divide-white/[0.08]"
        >
          {manifestoCopy.principles.map((item, i) => (
            <motion.li
              key={item.title}
              variants={riseSm}
              className="border-t border-white/[0.08] px-0 py-10 first:border-t-0 md:border-t-0 md:px-8 md:first:pl-0 md:last:pr-0"
            >
              <span className="font-mono text-[10px] font-bold uppercase tracking-[0.2em] text-[#c8ff3d]/80">
                {String(i + 1).padStart(2, "0")}
              </span>
              <h3 className="mt-4 text-lg font-semibold tracking-tight text-white">
                {item.title}
              </h3>
              <p className="mt-3 text-sm leading-relaxed text-white/55">
                {item.body}
              </p>
            </motion.li>
          ))}
        </motion.ul>
      </motion.div>
    </section>
  );
}
