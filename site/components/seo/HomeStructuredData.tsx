import { faqItems, heroCopy } from "@/lib/landing-content";
import {
  SITE_DESCRIPTION,
  SITE_NAME,
  SITE_ORIGIN,
  SITE_TITLE,
} from "@/lib/seo-defaults";
import { downloadUrl, githubUrl } from "@/lib/site-urls";

/**
 * 首页 JSON-LD：WebSite + SoftwareApplication + FAQPage（与可见正文保持一致）。
 */
export function HomeStructuredData() {
  const homeUrl = `${SITE_ORIGIN}/`;

  const graph: Record<string, unknown>[] = [
    {
      "@type": "WebSite",
      "@id": `${homeUrl}#website`,
      name: SITE_NAME,
      url: homeUrl,
      description: SITE_DESCRIPTION,
    },
    {
      "@type": "SoftwareApplication",
      "@id": `${homeUrl}#software`,
      name: SITE_NAME,
      description: `${SITE_DESCRIPTION} ${heroCopy.flow}`,
      applicationCategory: "DeveloperApplication",
      operatingSystem: "macOS 14.4 or later",
      url: homeUrl,
      downloadUrl,
      offers: {
        "@type": "Offer",
        url: downloadUrl,
        price: "0",
        priceCurrency: "USD",
      },
      sameAs: [githubUrl],
    },
    {
      "@type": "FAQPage",
      "@id": `${homeUrl}#faq`,
      mainEntity: faqItems.map((item) => ({
        "@type": "Question",
        name: item.q,
        acceptedAnswer: {
          "@type": "Answer",
          text: item.a,
        },
      })),
    },
    {
      "@type": "WebPage",
      "@id": `${homeUrl}#webpage`,
      url: homeUrl,
      name: SITE_TITLE,
      description: SITE_DESCRIPTION,
      isPartOf: { "@id": `${homeUrl}#website` },
      about: { "@id": `${homeUrl}#software` },
    },
  ];

  const data = {
    "@context": "https://schema.org",
    "@graph": graph,
  };

  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{
        __html: JSON.stringify(data),
      }}
    />
  );
}
