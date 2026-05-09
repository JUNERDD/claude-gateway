"use client";

import { useEffect } from "react";

/** 处理带 hash 的直达锚点（含 hashchange），与 smooth scroll 样式配合 */
export function LandingHashScroll() {
  useEffect(() => {
    const jump = () => {
      const id = window.location.hash.slice(1);
      if (!id) return;
      requestAnimationFrame(() => {
        document.getElementById(id)?.scrollIntoView({ block: "start" });
      });
    };
    jump();
    window.addEventListener("hashchange", jump);
    return () => window.removeEventListener("hashchange", jump);
  }, []);

  return null;
}
