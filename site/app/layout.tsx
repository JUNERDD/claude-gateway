import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Claude DeepSeek Gateway",
  description:
    "A local macOS gateway that lets Claude Desktop and Claude Code send Anthropic-compatible requests to DeepSeek.",
  applicationName: "Claude DeepSeek Gateway",
  keywords: [
    "Claude Desktop",
    "Claude Code",
    "DeepSeek",
    "Anthropic compatible",
    "macOS gateway",
    "local proxy",
  ],
  authors: [{ name: "JUNERDD" }],
  creator: "JUNERDD",
  icons: {
    icon: "/app-icon.png",
    apple: "/app-icon.png",
  },
  openGraph: {
    title: "Claude DeepSeek Gateway",
    description:
      "Install a native macOS gateway for routing Claude Desktop and Claude Code requests to DeepSeek.",
    type: "website",
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
