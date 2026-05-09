import dynamic from "next/dynamic";
import { HomeStructuredData } from "@/components/seo/HomeStructuredData";
import { LandingHashScroll } from "@/components/landing/LandingHashScroll";
import { LandingHeader } from "@/components/landing/LandingHeader";
import { LandingHero } from "@/components/landing/LandingHero";
import { LandingMotionRoot } from "@/components/landing/LandingMotionRoot";

const LandingManifesto = dynamic(() =>
  import("@/components/landing/LandingManifesto").then((m) => ({
    default: m.LandingManifesto,
  })),
);

const LandingWire = dynamic(() =>
  import("@/components/landing/LandingWire").then((m) => ({
    default: m.LandingWire,
  })),
);

const LandingLaunch = dynamic(() =>
  import("@/components/landing/LandingLaunch").then((m) => ({
    default: m.LandingLaunch,
  })),
);

const LandingCloser = dynamic(() =>
  import("@/components/landing/LandingCloser").then((m) => ({
    default: m.LandingCloser,
  })),
);

const LandingFooter = dynamic(() =>
  import("@/components/landing/LandingFooter").then((m) => ({
    default: m.LandingFooter,
  })),
);

export default function Home() {
  return (
    <>
      <HomeStructuredData />
      <LandingMotionRoot>
        <LandingHashScroll />
        <LandingHeader />
        <main>
          <LandingHero />
          <LandingManifesto />
          <LandingWire />
          <LandingLaunch />
          <LandingCloser />
          <LandingFooter />
        </main>
      </LandingMotionRoot>
    </>
  );
}
