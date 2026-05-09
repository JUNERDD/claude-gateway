"use client";

import { motion } from "motion/react";
import { cx } from "@/lib/cx";
import { defaultEndpoint } from "@/lib/site-urls";
import { wireCopy } from "@/lib/landing-content";
import { rise, riseSm, stagger, viewportSoft } from "./motion-presets";

function WireAtmosphere() {
  return (
    <>
      <div
        className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_75%_55%_at_15%_30%,rgba(200,255,61,0.07),transparent_58%),radial-gradient(ellipse_60%_48%_at_92%_65%,rgba(96,165,250,0.055),transparent_52%)]"
        aria-hidden
      />
      <div
        className="pointer-events-none absolute inset-0 bg-gradient-to-b from-[#050506] via-transparent to-[#050506]/85"
        aria-hidden
      />
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.055]"
        style={{
          backgroundImage: `url("data:image/svg+xml,%3Csvg viewBox='0 0 512 512' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.75' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E")`,
        }}
        aria-hidden
      />
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.2]"
        style={{
          backgroundImage: `
            linear-gradient(to right, rgba(255,255,255,0.04) 1px, transparent 1px),
            linear-gradient(to bottom, rgba(255,255,255,0.04) 1px, transparent 1px)
          `,
          backgroundSize: "64px 64px",
          maskImage:
            "radial-gradient(ellipse 85% 70% at 70% 45%, black 10%, transparent 70%)",
          WebkitMaskImage:
            "radial-gradient(ellipse 85% 70% at 70% 45%, black 10%, transparent 70%)",
        }}
        aria-hidden
      />
    </>
  );
}

export function LandingWire() {
  return (
    <section
      id="wire"
      className="relative overflow-x-clip border-t border-white/[0.07] bg-[#050506] px-4 py-24 md:px-6 md:py-32"
      aria-labelledby="wire-title"
    >
      <WireAtmosphere />

      <div className="relative mx-auto max-w-7xl">
        <div className="grid items-start gap-14 lg:grid-cols-12 lg:gap-12 xl:gap-16">
          <motion.header
            className="min-w-0 lg:col-span-5 xl:col-span-4"
            variants={stagger}
            initial="hidden"
            whileInView="visible"
            viewport={viewportSoft}
          >
            <motion.p
              variants={riseSm}
              className="font-mono text-[10px] font-bold uppercase tracking-[0.2em] text-[#c8ff3d]/80"
            >
              Traffic shape
            </motion.p>
            <motion.h2
              id="wire-title"
              variants={rise}
              className="mt-4 font-serif text-3xl font-semibold tracking-[-0.025em] text-white md:text-4xl lg:text-[2.35rem] lg:leading-tight"
            >
              {wireCopy.title}
            </motion.h2>
            <motion.p
              variants={rise}
              className="mt-5 max-w-md text-sm leading-relaxed text-white/58 md:text-base"
            >
              {wireCopy.lede}
            </motion.p>
          </motion.header>

          <motion.div
            className="min-w-0 w-full lg:col-span-7 xl:col-span-8"
            initial={{ opacity: 0, y: 32 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={viewportSoft}
            transition={{ duration: 0.7, ease: [0.22, 1, 0.36, 1] }}
          >
            <div className="relative w-full overflow-hidden rounded-2xl border border-white/[0.09] bg-gradient-to-br from-white/[0.045] via-transparent to-[#c8ff3d]/[0.04] px-6 py-7 shadow-[0_40px_80px_-48px_rgba(0,0,0,0.92)] md:px-8 md:py-8">
              <div
                className="pointer-events-none absolute -left-16 top-1/2 size-72 -translate-y-1/2 rounded-full bg-[#c8ff3d]/[0.06] blur-3xl"
                aria-hidden
              />

              <div
                className="relative grid gap-8 md:grid-cols-3 md:gap-0 md:divide-x md:divide-white/[0.08]"
                role="list"
                aria-label="Request path"
              >
                {wireCopy.nodes.map((node, i) => (
                  <motion.div
                    key={node.label}
                    role="listitem"
                    className={cx(
                      "relative min-w-0 md:px-5 lg:px-6",
                      i > 0 && "border-t border-white/[0.08] pt-8 md:border-t-0 md:pt-0",
                    )}
                    initial={{ opacity: 0, y: 20 }}
                    whileInView={{ opacity: 1, y: 0 }}
                    viewport={{ once: true, amount: 0.35 }}
                    transition={{
                      duration: 0.55,
                      delay: 0.08 * i,
                      ease: [0.22, 1, 0.36, 1],
                    }}
                    whileHover={{ y: -2 }}
                    whileTap={{ scale: 0.995 }}
                  >
                    <div
                      className={cx(
                        "flex flex-col",
                        node.highlight ? "md:pt-0.5" : "text-left",
                      )}
                    >
                      <p className="text-lg font-semibold tracking-tight text-white md:text-xl">
                        {node.label}
                      </p>
                      <p className="mt-1.5 text-[15px] leading-snug text-white/50 md:mt-2 md:text-base md:text-white/46">
                        {node.sub}
                      </p>
                      {node.highlight ? (
                        <p className="mt-4 font-mono text-sm font-medium tracking-wide text-[#c8ff3d] md:mt-5 md:text-base">
                          {defaultEndpoint}
                        </p>
                      ) : null}
                    </div>
                  </motion.div>
                ))}
              </div>

              <motion.div
                className="relative mt-8 border-t border-white/[0.07] pt-6 md:mt-9 md:pt-7"
                initial={{ opacity: 0 }}
                whileInView={{ opacity: 1 }}
                viewport={{ once: true, amount: 0.5 }}
                transition={{ delay: 0.2, duration: 0.5 }}
              >
                <div className="relative px-2 md:px-8" aria-hidden>
                  <div className="pointer-events-none absolute left-2 right-2 top-[0.5rem] h-px md:left-8 md:right-8 bg-gradient-to-r from-white/12 via-white/22 to-white/12" />
                  <motion.div
                    className="pointer-events-none absolute left-2 right-2 top-[0.5rem] h-px md:left-8 md:right-8 origin-center bg-gradient-to-r from-transparent via-[#c8ff3d]/45 to-transparent"
                    initial={{ scaleX: 0, opacity: 0 }}
                    whileInView={{ scaleX: 1, opacity: 1 }}
                    viewport={{ once: true, amount: 0.6 }}
                    transition={{
                      duration: 0.85,
                      ease: [0.22, 1, 0.36, 1],
                      delay: 0.15,
                    }}
                  />
                  <div className="relative flex justify-between gap-2">
                    {wireCopy.nodes.map((node) => (
                      <div
                        key={`dot-${node.label}`}
                        className="flex min-w-0 flex-1 flex-col items-center"
                      >
                        <div
                          className={cx(
                            "relative z-10 size-2.5 shrink-0 rounded-full md:size-3",
                            node.highlight
                              ? "bg-[#c8ff3d] shadow-[0_0_14px_rgba(200,255,61,0.45)]"
                              : "bg-white/40",
                          )}
                        />
                      </div>
                    ))}
                  </div>
                </div>

                <p className="mt-6 text-center font-mono text-[11px] tracking-[0.16em] text-white/40 uppercase md:mt-7">
                  {wireCopy.railCaption}
                </p>
              </motion.div>
            </div>
          </motion.div>
        </div>
      </div>
    </section>
  );
}
