// import Link from "next/link";
// import { Terminal } from "lucide-react";
// import { getSignInUrl, withAuth } from "@workos-inc/authkit-nextjs";
// import { Button } from "@/components/ui/button";
// import HeaderMobileMenu from "@/components/header-mobile-menu";

// export async function SiteHeader() {
//   const { user } = await withAuth();
//   const organizationId = process.env.WORKOS_ORG_ID;

//   // Generate the direct WorkOS Sign-in URL
//   const signInUrl = await getSignInUrl({
//     organizationId: organizationId,
//   });

//   const navLinks = [
//     { href: "/features", label: "Features" },
//     { href: "/cloud", label: "Cloud" },
//   ];

//   return (
//     <header className="flex items-center bg-background justify-between backdrop-blur-md sticky top-0 h-16 px-[clamp(2svw,15.3svw-53px,11svw)] w-full z-100">
//       <div className="flex flex-row items-center gap-6 bg-green-200">
//         <Link
//           href="/"
//           className="flex items-center gap-2 font-bold text-2xl tracking-tight hover:opacity-90 transition-opacity"
//         >
//           <div className="flex items-center justify-center rounded-full bg-primary p-2 text-primary-foreground shadow-sm">
//             <Terminal size={18} />
//           </div>
//         </Link>
//         <nav className="hidden md:flex items-center gap-6 ">
//           {navLinks.map((link) => (
//             <Link
//               key={link.href}
//               href={link.href}
//               className="font-bold text-2xl tracking-tight hover:opacity-90 transition-opacity"
//             >
//               {link.label}
//             </Link>
//           ))}
//         </nav>
//       </div>

//       <div className="hidden md:flex items-center gap-2">
//         {!user ? (
//           <>
//             <Link href={signInUrl}>
//               <Button size="sm" variant="outline" className="rounded-full px-5">
//                 Sign in
//               </Button>
//             </Link>
//           </>
//         ) : (
//           <div>User</div>
//         )}
//       </div>

//       {/* Mobile Menu (Client Component) */}
//       <div className="md:hidden">
//         <HeaderMobileMenu navLinks={navLinks} signInUrl={signInUrl} />
//       </div>
//     </header>
//   );
// }

import Link from "next/link";
import { Terminal } from "lucide-react";
import SiteHeaderMenu from "@/components/site-header-menu";
import { getSignInUrl, withAuth } from "@workos-inc/authkit-nextjs";
import { Button } from "@/components/ui/button";

export async function SiteHeader() {
  const { user } = await withAuth();
  const organizationId = process.env.WORKOS_ORG_ID;
  const signInUrl = await getSignInUrl({
    organizationId: organizationId,
  });

  const navLinks = [
    { href: "/features", label: "Features" },
    { href: "/cloud", label: "Cloud" },
  ];

  return (
    <header className="flex items-center bg-background justify-between backdrop-blur-md sticky top-0 h-16 px-[clamp(2svw,15.3svw-53px,11svw)] w-full">
      <div className="flex flex-row items-center gap-6">
        <Link
          href="/"
          className="flex items-center gap-2 font-bold text-2xl tracking-tight hover:opacity-90 transition-opacity"
        >
          <div className="flex items-center justify-center rounded-full bg-primary p-2 text-primary-foreground shadow-sm">
            <Terminal size={18} />
          </div>
        </Link>
        <nav className="flex items-center gap-6 ">
          {navLinks.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="font-bold text-2xl tracking-tight hover:opacity-90 transition-opacity"
            >
              {link.label}
            </Link>
          ))}
        </nav>
      </div>

      <div className="flex items-center gap-2">
        {!user ? (
          <>
            <Link href={signInUrl}>
              <Button size="sm" variant="outline" className="rounded-full px-5">
                Sign in
              </Button>
            </Link>
          </>
        ) : (
          <SiteHeaderMenu />
        )}
      </div>
    </header>
  );
}
