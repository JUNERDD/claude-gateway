"use client";

import { Terminal } from "lucide-react";
import { githubUrl } from "@/lib/site-urls";

const links = [
  { label: "Security", href: `${githubUrl}/blob/main/SECURITY.md` },
  { label: "License", href: `${githubUrl}/blob/main/LICENSE` },
] as const;

export function LandingFooter() {
  return (
    <footer className="border-t border-white/[0.07] px-4 py-12 md:px-6">
      <div className="mx-auto flex max-w-7xl flex-col items-center justify-between gap-6 text-sm text-white/45 md:flex-row">
        <span className="flex items-center gap-2 font-medium text-white/80">
          <Terminal className="size-4 text-[#c8ff3d]" aria-hidden />
          Claude Gateway
        </span>
        <nav className="flex flex-wrap justify-center gap-x-8 gap-y-2">
          <a
            href={githubUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="transition hover:text-white"
          >
            GitHub
          </a>
          {links.map((l) => (
            <a
              key={l.label}
              href={l.href}
              target="_blank"
              rel="noopener noreferrer"
              className="transition hover:text-white"
            >
              {l.label}
            </a>
          ))}
        </nav>
      </div>
    </footer>
  );
}
