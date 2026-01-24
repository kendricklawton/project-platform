"use client";

import { useAuth } from "@workos-inc/authkit-nextjs/components";
import { useState, useEffect } from "react";
import Link from "next/link";
import { Divide as Hamburger } from "hamburger-react";
import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
  SheetTrigger,
  SheetTitle,
} from "@/components/ui/sheet";

type NavLink = {
  href: string;
  label: string;
};

export default function HeaderMobileMenu({
  navLinks,
  signInUrl,
}: {
  navLinks: NavLink[];
  signInUrl: string;
}) {
  const { user, signOut } = useAuth();
  const returnUrl = process.env.NEXT_PUBLIC_WEB_URL;
  const [isOpen, setIsOpen] = useState(false);

  const handleSignOut = async () => {
    await signOut({ returnTo: returnUrl });
  };

  useEffect(() => {
    const handleResize = () => {
      if (window.innerWidth >= 768) setIsOpen(false);
    };
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

  return (
    <Sheet open={isOpen} onOpenChange={setIsOpen} modal={false}>
      <SheetTrigger asChild>
        <div className="relative z-50 flex items-center justify-center outline-none">
          <Hamburger
            toggled={isOpen}
            toggle={setIsOpen}
            size={24}
            rounded
            label="Show menu"
            // color="grey"
          />
          <span className="sr-only">Toggle menu</span>
        </div>
      </SheetTrigger>

      <SheetContent
        side="bottom"
        onPointerDownOutside={(e) => e.preventDefault()}
        className="w-full top-16 h-[calc(100svh-64px)] [&>button]:hidden border-t-0 p-0 shadow-none"
      >
        <SheetTitle className="sr-only">Mobile Navigation</SheetTitle>
        <div className="flex flex-col gap-8 h-full pt-12 px-[clamp(2svw,15.3svw-53px,8svw)] text-foreground">
          <div className="flex flex-col gap-4">
            {navLinks.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                className="text-lg font-light tracking-tight hover:opacity-90 transition-opacity"
                onClick={() => setIsOpen(false)}
              >
                {link.label}
              </Link>
            ))}
          </div>

          <div className="flex flex-col gap-2">
            <Link href="/download" onClick={() => setIsOpen(false)}>
              <Button
                className="w-full rounded-full py-7 text-xl shadow-lg"
                size="lg"
              >
                Download
              </Button>
            </Link>
            {user ? (
              <Button
                onClick={handleSignOut}
                variant="outline"
                className="w-full rounded-full py-7 text-xl shadow-sm"
                size="lg"
              >
                Sign out
              </Button>
            ) : (
              <Link href={signInUrl}>
                <Button
                  variant="outline"
                  className="w-full rounded-full py-7 text-xl shadow-sm"
                  size="lg"
                >
                  Sign In
                </Button>
              </Link>
            )}
          </div>
        </div>
      </SheetContent>
    </Sheet>
  );
}
