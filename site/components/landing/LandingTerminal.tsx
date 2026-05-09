"use client";

import { useCallback } from "react";
import { Copy } from "lucide-react";
import { defaultEndpoint } from "@/lib/site-urls";

const copyText = `export ANTHROPIC_BASE_URL=http://${defaultEndpoint}
export ANTHROPIC_AUTH_TOKEN=local-gateway-key`;

export function LandingTerminal() {
  const onCopy = useCallback(() => {
    void navigator.clipboard.writeText(copyText);
  }, []);

  return (
    <div className="min-w-0 overflow-hidden rounded-2xl border border-white/[0.1] bg-[#0c0c0e] shadow-[0_40px_100px_-40px_rgba(0,0,0,0.85)]">
      <div className="flex h-10 items-center gap-2 border-b border-white/[0.06] px-4">
        <span className="size-2.5 rounded-full bg-[#ff5f57]" />
        <span className="size-2.5 rounded-full bg-[#febc2e]" />
        <span className="size-2.5 rounded-full bg-[#28c840]" />
        <span className="ml-2 font-mono text-[10px] text-white/35">
          zsh — claude-gateway
        </span>
      </div>
      <pre className="min-w-0 overflow-x-hidden whitespace-pre-wrap break-words p-5 font-mono text-[13px] leading-relaxed text-white/88">
        <span className="text-white/35">$ </span>
        <span className="text-[#7dffb3]">export</span>{" "}
        <span className="text-white/80">ANTHROPIC_BASE_URL=</span>
        <span className="text-[#c8ff3d]">http://{defaultEndpoint}</span>
        {"\n"}
        <span className="text-white/35">$ </span>
        <span className="text-[#7dffb3]">export</span>{" "}
        <span className="text-white/80">ANTHROPIC_AUTH_TOKEN=</span>
        <span className="text-[#c8ff3d]">local-gateway-key</span>
        {"\n"}
        <span className="text-white/35">$ </span>
        <span className="text-white/90">claude</span>
        {"\n"}
        <span className="text-white/30"># point clients here, then ship.</span>
      </pre>
      <div className="flex items-center justify-between gap-3 border-t border-white/[0.06] px-4 py-3">
        <span className="font-mono text-[10px] text-white/35">bash · zsh</span>
        <button
          type="button"
          onClick={onCopy}
          className="inline-flex items-center gap-2 rounded-lg border border-white/10 bg-white/[0.04] px-3 py-1.5 font-mono text-[11px] text-white/80 transition hover:bg-white/[0.08]"
        >
          <Copy className="size-3.5" aria-hidden />
          Copy exports
        </button>
      </div>
    </div>
  );
}
