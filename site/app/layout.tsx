import type { Metadata } from "next";
import "./globals.css";

const siteUrl = new URL("https://claude-deepseek-gateway.vercel.app");

export const metadata: Metadata = {
  metadataBase: siteUrl,
  title: "Claude DeepSeek Gateway — Local macOS proxy for DeepSeek",
  description:
    "A native macOS gateway that routes Claude Desktop and Claude Code requests to DeepSeek through a local Anthropic-compatible endpoint. Open source, local first, zero telemetry.",
  applicationName: "Claude DeepSeek Gateway",
  keywords: [
    "Claude Desktop",
    "Claude Code",
    "DeepSeek",
    "Anthropic compatible",
    "macOS gateway",
    "local proxy",
    "API cost savings",
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
    title: "Claude DeepSeek Gateway — Local macOS proxy for DeepSeek",
    description:
      "Route Claude Desktop and Claude Code to DeepSeek through a local Anthropic-compatible endpoint. Open source, local first, zero telemetry.",
    url: "/",
    type: "website",
    siteName: "Claude DeepSeek Gateway",
    images: [
      {
        url: "/app-icon.png",
        width: 1024,
        height: 1024,
        alt: "Claude DeepSeek Gateway app icon",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Claude DeepSeek Gateway — Local macOS proxy for DeepSeek",
    description:
      "Route Claude Desktop and Claude Code to DeepSeek through a local Anthropic-compatible endpoint. Open source, local first, zero telemetry.",
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
