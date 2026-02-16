import { SiteHeader } from "@/components/site-header";
import { IconFolderCode } from "@tabler/icons-react";
import { ArrowUpRightIcon, Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import Link from "next/link";

export default async function DashboardPage() {
  return (
    <>
      <SiteHeader />
      <main className="px-[clamp(2svw,15.3svw-53px,11svw)] min-h-[calc(100svh-4rem)] flex flex-col items-center">
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon" className="rounded-full">
              <IconFolderCode />
            </EmptyMedia>
            <EmptyTitle>No Projects Yet</EmptyTitle>
            <EmptyDescription>
              You haven&apos;t created any projects yet. Get started by creating
              your first project.
            </EmptyDescription>
          </EmptyHeader>
          <EmptyContent>
            <div className="flex">
              <Button className="rounded-full">
                Create project <Plus />{" "}
              </Button>
            </div>
          </EmptyContent>
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
        </Empty>
      </main>
    </>
  );
}
