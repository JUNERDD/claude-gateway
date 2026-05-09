"use client";

import Image from "next/image";
import { motion, useScroll, useTransform } from "motion/react";
import type { RefObject } from "react";
import { useRef } from "react";
import { ArrowDownToLine, GitBranch } from "lucide-react";
import { downloadUrl, githubUrl } from "@/lib/site-urls";
import { heroCopy } from "@/lib/landing-content";
import { ctaTransition, rise, stagger } from "./motion-presets";

/** Full-bleed plane：影像左偏、右缘压暗，让 UI 截图退成氛围而非主角 */
function HeroBackdrop({
  sectionRef,
}: {
  sectionRef: RefObject<HTMLElement | null>;
}) {
  const { scrollYProgress } = useScroll({
    target: sectionRef,
    offset: ["start start", "end start"],
  });
  const parallaxY = useTransform(scrollYProgress, [0, 1], ["0%", "11%"]);
  const parallaxScale = useTransform(scrollYProgress, [0, 1], [1, 1.045]);

  return (
    <div className="absolute inset-0 overflow-hidden bg-[#050506]">
      <motion.div
        className="absolute inset-y-0 left-1/2 h-full w-[135vw] max-w-none -translate-x-1/2 will-change-transform"
        style={{ y: parallaxY, scale: parallaxScale }}
        aria-hidden
      >
        <motion.div
          className="relative h-full w-full origin-[32%_0%] will-change-transform"
          initial={{ scale: 1.07 }}
          animate={{ scale: 1 }}
          transition={{ duration: 1.25, ease: [0.22, 1, 0.36, 1] }}
        >
          <Image
            src="/product-overview.png"
            alt=""
            fill
            priority
            sizes="100vw"
            className="object-cover object-[24%_18%] sm:object-[26%_19%] md:object-[28%_20%] lg:object-[30%_20%] xl:object-[30%_18%]"
          />
        </motion.div>
      </motion.div>

      {/* 右侧沉重感：缘外压暗 + 去饱和，把视觉重心还给左列文案 */}
      <div
        className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_90%_70%_at_88%_45%,rgba(5,5,6,0)_0%,rgba(5,5,6,0.35)_45%,rgba(5,5,6,0.92)_100%)]"
        aria-hidden
      />
      <div
        className="pointer-events-none absolute inset-0 bg-gradient-to-l from-[#050506] via-[#050506]/75 from-[0%] via-[38%] to-transparent to-[72%]"
        aria-hidden
      />
      <div
        className="pointer-events-none absolute inset-0 bg-gradient-to-r from-[#050506]/95 via-[#050506]/55 from-[0%] via-[48%] to-transparent to-[76%]"
        aria-hidden
      />

      <div
        className="pointer-events-none absolute inset-0 bg-gradient-to-t from-[#050506]/82 via-transparent to-[#050506]/[0.02] to-[28%]"
        aria-hidden
      />
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.05]"
        style={{
          backgroundImage: `url("data:image/svg+xml,%3Csvg viewBox='0 0 512 512' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.8' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E")`,
        }}
        aria-hidden
      />
    </div>
  );
}

export function LandingHero() {
  const sectionRef = useRef<HTMLElement | null>(null);

  return (
    <section
      ref={sectionRef}
      id="top"
      className="relative isolate min-h-svh w-full overflow-x-clip"
      aria-labelledby="landing-hero-title"
    >
      <HeroBackdrop sectionRef={sectionRef} />

      <div className="relative z-[2] mx-auto grid min-h-svh w-full max-w-7xl grid-cols-1 items-center gap-10 px-4 pb-20 pt-[5.75rem] md:gap-12 md:px-6 md:pb-24 md:pt-24 lg:grid-cols-12 lg:gap-6 lg:pb-28">
        {/* 左列占满叙事权重；右列留白，让背景影像只做气氛 */}
        <div className="relative lg:col-span-7 lg:max-w-none xl:col-span-6">
          <motion.div
            variants={stagger}
            initial="hidden"
            animate="visible"
            className="relative max-w-xl md:max-w-2xl"
          >
            <motion.p
              variants={rise}
              className="relative font-serif text-lg font-medium tracking-[-0.02em] text-white md:text-xl"
            >
              {heroCopy.brand}
            </motion.p>
            <motion.p
              variants={rise}
              className="relative mt-2 font-mono text-[11px] font-semibold uppercase tracking-[0.22em] text-[#c8ff3d]/90"
            >
              {heroCopy.kicker}
            </motion.p>
            <motion.h1
              id="landing-hero-title"
              variants={rise}
              className="relative mt-5 font-serif text-[2.125rem] font-semibold leading-[1.05] tracking-[-0.035em] text-white sm:text-4xl md:text-5xl md:leading-[1.02] lg:text-[3.25rem] lg:leading-[0.98] xl:text-6xl"
            >
              {heroCopy.title}
            </motion.h1>
            <motion.p
              variants={rise}
              className="relative mt-6 max-w-xl text-base leading-relaxed text-white/72 md:text-lg"
            >
              {heroCopy.lede}
            </motion.p>
            <motion.p
              variants={rise}
              className="relative mt-6 max-w-xl border-l-2 border-[#c8ff3d]/80 pl-4 font-mono text-sm leading-snug text-[#c8ff3d]/88"
            >
              {heroCopy.flow}
            </motion.p>
            <motion.div
              variants={rise}
              className="relative mt-10 flex flex-col gap-3 sm:flex-row sm:flex-wrap"
            >
              <motion.a
                href={downloadUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex h-12 items-center justify-center gap-2 rounded-full bg-[#c8ff3d] px-7 text-sm font-semibold text-black transition hover:brightness-105"
                whileHover={{ y: -2 }}
                whileTap={{ scale: 0.98 }}
                transition={ctaTransition}
              >
                <ArrowDownToLine className="size-4" aria-hidden />
                Download DMG
              </motion.a>
              <motion.a
                href={githubUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex h-12 items-center justify-center gap-2 rounded-full border border-white/20 px-7 text-sm font-medium text-white/90 transition hover:border-white/40 hover:bg-white/[0.04]"
                whileHover={{ y: -2 }}
                whileTap={{ scale: 0.98 }}
                transition={ctaTransition}
              >
                <GitBranch className="size-4 text-white/70" aria-hidden />
                View repository
              </motion.a>
            </motion.div>
          </motion.div>
        </div>

        <div
          className="hidden min-h-[1px] lg:col-span-5 xl:col-span-6"
          aria-hidden
        />
      </div>

      <span className="sr-only">
        Product screenshot: Claude Gateway macOS application showing status,
        routes, and request metrics.
      </span>
    </section>
  );
}
