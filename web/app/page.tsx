import { SiteHeader } from "@/components/site-header";
import { SiteHero } from "@/components/site-hero";
import { SiteFooter } from "@/components/site-footer";
import { getSignInUrl, withAuth } from "@workos-inc/authkit-nextjs";

export default async function LandingPage() {
  const { user } = await withAuth();
  const organizationId = process.env.WORKOS_ORG_ID;
  const signInUrl = await getSignInUrl({
    organizationId: organizationId,
  });

  const gitVersion = process.env.NEXT_PUBLIC_GIT_VERSION || "v1.0.0-beta";
  return (
    <div className="flex flex-col min-h-screen bg-background text-foreground transition-colors duration-300">
      <SiteHeader />
      <main className="flex-1 flex flex-col items-center">
        {/* HERO SECTION */}
        <SiteHero
          badge={gitVersion}
          title="Go Cloud."
          subtitle="Private AI."
          ctaText={user ? "Open Console" : "Start Building"}
          ctaHref={user ? "/dashboard" : signInUrl}
          secondaryText="Download CLI"
          secondaryHref="/download"
          terminalCommand="mini deploy"
        />

        {/* ARCHITECTURE PROOF SECTION */}
        <section className="w-full max-w-6xl mx-auto py-32 px-6">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-16 border-t border-border pt-24">
            <div className="space-y-4">
              <h3 className="text-foreground font-bold text-xl tracking-tight">
                Isolated by gVisor
              </h3>
              <p className="text-muted-foreground leading-relaxed text-base">
                Kernel-level protection for every container. Your services are
                sandboxed from day one using Google&apos;s runsc runtime.
              </p>
            </div>

            <div className="space-y-4">
              <h3 className="text-foreground font-bold text-xl tracking-tight">
                Private Ollama
              </h3>
              <p className="text-muted-foreground leading-relaxed text-base">
                In-cluster LLM access. Zero-latency inference over private
                Tailscale tunnels. Keep your data off the public web.
              </p>
            </div>

            <div className="space-y-4">
              <h3 className="text-foreground font-bold text-xl tracking-tight">
                Daemonless Builds
              </h3>
              <p className="text-muted-foreground leading-relaxed text-base">
                Powered by ko. No Dockerfiles. No local registry. Pure Go to OCI
                images in seconds, deployed to Knative instantly.
              </p>
            </div>
          </div>
        </section>
      </main>

      <SiteFooter />
    </div>
  );
}
