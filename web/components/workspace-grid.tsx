"use client";

import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { useStore } from "@/store/useStore";

export function WorkspaceGrid() {
  const { workspaces } = useStore();

  return (
    <div className="rounded-md border bg-white h-full flex flex-col shadow-sm overflow-hidden">
      <ScrollArea className="flex-1">
        <Table>
          <TableHeader className="sticky top-0 bg-white z-10 shadow-[0_1px_0_rgba(0,0,0,0.05)]">
            <TableRow className="bg-muted/40 hover:bg-muted/40">
              <TableHead>Name</TableHead>
              <TableHead>Type</TableHead>
              <TableHead>Role</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {workspaces.map((workspace) => (
              <TableRow
                key={workspace.id}
                className="cursor-pointer hover:bg-slate-50 transition-colors font-mono text-xs"
              >
                <TableCell className="text-muted-foreground break-all">
                  {workspace.name}
                </TableCell>
                <TableCell className="text-muted-foreground break-all">
                  {workspace.type}
                </TableCell>
                <TableCell className="text-muted-foreground">
                  {workspace.role}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </ScrollArea>
    </div>
  );
}
