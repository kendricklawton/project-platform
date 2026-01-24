"use client";

import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Terminal } from "lucide-react";

type SiteHeroProps = {
  badge?: string;
  title: string;
  subtitle: string;
  ctaText?: string;
  ctaHref?: string;
  secondaryText?: string;
  secondaryHref?: string;
  terminalCommand?: string;
};

export function SiteHero({
  badge,
  title,
  subtitle,
  ctaText = "Start Deploying",
  ctaHref = "/dashboard",
  secondaryText,
  secondaryHref,
  terminalCommand = "task deploy",
}: SiteHeroProps) {
  return (
    <div className="relative flex flex-col items-center justify-center py-24 px-6 overflow-hidden">
      <div className="absolute top-0 -z-10 h-full w-full bg-[radial-gradient(ellipse_at_top,var(--color-primary)/0.05,transparent_70%)]" />

      <div className="max-w-4xl w-full text-center space-y-10">
        {/* The Git Version Badge */}
        {badge && (
          <div className="inline-flex items-center rounded-full border border-border bg-muted/50 px-3 py-1 text-sm font-medium text-muted-foreground transition-colors hover:bg-muted">
            <span className="flex h-2 w-2 rounded-full bg-indigo-500 mr-2 animate-pulse shadow-[0_0_8px_2px_rgba(99,102,241,0.4)]"></span>
            {badge}
          </div>
        )}

        <h1 className="text-6xl md:text-8xl font-extrabold tracking-tighter text-foreground font-sans">
          {title}
          <span className="block text-muted-foreground mt-2">{subtitle}</span>
        </h1>

        <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
          <Link href={ctaHref}>
            <Button className="bg-primary text-primary-foreground h-14 px-10 rounded-full text-lg font-bold shadow-xl">
              {ctaText}
            </Button>
          </Link>

          {secondaryText && secondaryHref && (
            <Link href={secondaryHref}>
              <Button
                variant="ghost"
                className="text-muted-foreground hover:text-foreground h-14 px-10 text-lg font-medium"
              >
                {secondaryText}
              </Button>
            </Link>
          )}
        </div>

        <div className="mt-20 w-full max-w-lg mx-auto">
          <div className="flex items-center justify-between bg-muted/30 border border-border rounded-2xl p-4 backdrop-blur-sm">
            <div className="flex items-center gap-3 font-mono">
              <Terminal className="w-4 h-4 text-primary opacity-70" />
              <span className="text-muted-foreground">$</span>
              <code className="text-foreground text-sm font-medium">
                {terminalCommand}
              </code>
            </div>
            <div className="flex gap-1.5">
              <div className="w-2 h-2 rounded-full bg-border" />
              <div className="w-2 h-2 rounded-full bg-border" />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
