import type { Metadata } from "next";
import "./globals.css";

const siteUrl = new URL("https://claude-gateway.vercel.app");

export const metadata: Metadata = {
  metadataBase: siteUrl,
  title: "Claude Gateway — Local provider routing for Claude Desktop and Claude Code",
  description:
    "A native macOS gateway that routes Claude Desktop and Claude Code through local provider configuration, model aliases, secrets, logs, and sync.",
  applicationName: "Claude Gateway",
  keywords: [
    "Claude Desktop",
    "Claude Code",
    "Claude Gateway",
    "Anthropic-compatible providers",
    "Anthropic compatible",
    "macOS gateway",
    "local proxy",
    "model routing",
    "custom AI providers",
  ],
  authors: [{ name: "JUNERDD", url: "https://github.com/JUNERDD" }],
  creator: "JUNERDD",
  icons: {
    icon: "/app-icon.png",
    apple: "/app-icon.png",
  },
  alternates: {
    canonical: "/",
  },
  openGraph: {
    title: "Claude Gateway — Local provider routing for Claude Desktop and Claude Code",
    description:
      "Route Claude Desktop and Claude Code through local provider configuration, model aliases, secrets, logs, and sync.",
    url: "/",
    type: "website",
    siteName: "Claude Gateway",
    images: [
      {
        url: "/app-icon.png",
        width: 1024,
        height: 1024,
        alt: "Claude Gateway app icon",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Claude Gateway — Local provider routing for Claude Desktop and Claude Code",
    description:
      "Route Claude Desktop and Claude Code through local provider configuration, model aliases, secrets, logs, and sync.",
    images: ["/app-icon.png"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
