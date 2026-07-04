import type { Metadata } from "next";
import { GeistSans } from "geist/font/sans";
import { Analytics } from "@vercel/analytics/next";
import { Attribution } from "@/components/Attribution";
import { ScrollDepth } from "@/components/ScrollDepth";
import { Pixels } from "@/components/Pixels";
import { copy } from "@/lib/copy";
import "@/styles/globals.css";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://adoptaboop.com";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: copy.meta.title,
  description: copy.meta.description,
  applicationName: "Boop",
  keywords: ["desk companion for AI agents", "AI coding agents", "Claude Code", "Cursor", "Codex"],
  alternates: { canonical: "/" },
  robots: { index: true, follow: true },
  openGraph: {
    type: "website",
    url: "/",
    title: copy.meta.title,
    description: copy.meta.description,
    siteName: "Boop",
    images: [{ url: "/og.jpg", width: 1200, height: 630, alt: copy.meta.title }],
  },
  twitter: {
    card: "summary_large_image",
    title: copy.meta.title,
    description: copy.meta.description,
    images: ["/og.jpg"],
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={GeistSans.variable}>
      <body>
        <Attribution />
        {children}
        <ScrollDepth />
        <Pixels />
        <Analytics />
      </body>
    </html>
  );
}
