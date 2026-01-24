import Link from "next/link";
import { Terminal } from "lucide-react";
import { useAuth } from "@workos-inc/authkit-nextjs/components";
import { Button } from "@/components/ui/button";
import HeaderMobileMenu from "@/components/header-mobile-menu";

export function WorkspaceHeader() {
  const { user, signOut } = useAuth();
  const organizationId = process.env.WORKOS_ORG_ID;

  const navLinks = [
    { href: "/workspaces", label: "Workspaces" },
    { href: "/pricing", label: "Pricing" },
  ];

  return (
    <header className="flex items-center bg-background justify-between backdrop-blur-md sticky top-0 h-16 px-[clamp(2svw,15.3svw-53px,11svw)] w-full z-100">
      <div className="flex items-center gap-6">
        <Link
          href="/"
          className="flex items-center gap-2 font-bold text-2xl tracking-tight hover:opacity-90 transition-opacity"
        >
          <div className="flex items-center justify-center rounded-full bg-primary p-2 text-primary-foreground shadow-sm">
            <Terminal size={18} />
          </div>
          <span>Untitled</span>
        </Link>
        <nav className="hidden md:flex items-center gap-6">
          {navLinks.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="text-lg font-light tracking-tight hover:opacity-90 transition-opacity"
            >
              {link.label}
            </Link>
          ))}
        </nav>
      </div>

      <div className="hidden md:flex items-center gap-2">
        {/* User Dropdown Menu (Client Component) */}
        <div>User</div>
      </div>

      {/* Mobile Menu (Client Component) */}
      <div className="md:hidden">
        <SiteHeaderMenu navLinks={navLinks} signInUrl={signInUrl} />
      </div>
    </header>
  );
}
