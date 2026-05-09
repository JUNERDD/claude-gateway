import type { MetadataRoute } from "next";
import { SITE_ORIGIN } from "@/lib/seo-defaults";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: "/",
    },
    sitemap: `${SITE_ORIGIN}/sitemap.xml`,
  };
}
