import type { Variants, ViewportOptions } from "motion/react";

export const viewportSoft: ViewportOptions = { once: true, amount: 0.22 };

export const rise: Variants = {
  hidden: { opacity: 0, y: 28 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.65, ease: [0.22, 1, 0.36, 1] },
  },
};

export const riseSm: Variants = {
  hidden: { opacity: 0, y: 16 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.45, ease: [0.22, 1, 0.36, 1] },
  },
};

export const stagger: Variants = {
  hidden: {},
  visible: {
    transition: { staggerChildren: 0.09, delayChildren: 0.08 },
  },
};

/** 终端 / 代码块：分行入场，短促避免阅读被拖慢 */
export const terminalStagger: Variants = {
  hidden: {},
  visible: {
    transition: { staggerChildren: 0.055, delayChildren: 0.06 },
  },
};

export const terminalLine: Variants = {
  hidden: { opacity: 0, x: -10 },
  visible: {
    opacity: 1,
    x: 0,
    transition: { duration: 0.32, ease: [0.22, 1, 0.36, 1] },
  },
};

/** Primary CTA：仅 transform，低成本 hover / tap */
export const ctaTransition = {
  type: "spring" as const,
  stiffness: 520,
  damping: 28,
};
