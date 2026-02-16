import Link from "next/link";
// import { ArrowUpRightIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
export function SiteFooter() {
  return (
    <footer className="py-8 text-center text-sm text-muted-foreground w-full">
      <p>
        <span>
          Built by{" "}
          <Button
            variant="link"
            asChild
            className="text-muted-foreground p-0 underline"
            size="sm"
          >
            <Link href="/">K-Henry</Link>
          </Button>
          . The source code is available on{" "}
          <Button
            variant="link"
            asChild
            className="text-muted-foreground p-0 underline"
            size="sm"
          >
            <Link href="/">GitHub</Link>
          </Button>
          .
        </span>
      </p>
      {/*<div className="flex justify-center gap-4 text-xs opacity-70">
        <Button
          variant="link"
          asChild
          className="text-muted-foreground"
          size="sm"
        >
          <Link href="/">
            Learn More <ArrowUpRightIcon />
          </Link>
        </Button>
        <Button
          variant="link"
          asChild
          className="text-muted-foreground"
          size="sm"
        >
          <Link href="/">
            Learn More <ArrowUpRightIcon />
          </Link>
        </Button>
        <Button
          variant="link"
          asChild
          className="text-muted-foreground"
          size="sm"
        >
          <Link href="/">
            Twitter <ArrowUpRightIcon />
          </Link>
        </Button>
      </div>*/}
    </footer>
  );
}
