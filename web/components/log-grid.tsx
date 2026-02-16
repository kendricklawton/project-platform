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
import { cn } from "@/lib/utils";

export function LogGrid() {
  const { logs } = useStore();

  return (
    <div className="rounded-md border bg-white h-full flex flex-col shadow-sm overflow-hidden">
      <ScrollArea className="flex-1">
        {/* Only one Table component is needed now */}
        <Table>
          <TableHeader className="sticky top-0 bg-white z-10 shadow-[0_1px_0_rgba(0,0,0,0.05)]">
            <TableRow className="bg-muted/40 hover:bg-muted/40">
              <TableHead className="w-25">Status</TableHead>
              <TableHead className="w-25">Method</TableHead>
              <TableHead>Path</TableHead>
              <TableHead className="w-37.5">Source</TableHead>
              <TableHead className="text-right w-30">Time</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {logs.map((log) => (
              <TableRow
                key={log.id}
                className="cursor-pointer hover:bg-slate-50 transition-colors font-mono text-xs"
              >
                <TableCell>
                  <Badge
                    variant="outline"
                    className={cn(
                      "font-mono font-normal",
                      log.status >= 200 && log.status < 300
                        ? "border-green-200 text-green-700 bg-green-50"
                        : "border-red-200 text-red-700 bg-red-50",
                    )}
                  >
                    {log.status}
                  </Badge>
                </TableCell>
                <TableCell className="font-bold">{log.method}</TableCell>
                <TableCell className="text-muted-foreground break-all">
                  {log.path}
                </TableCell>
                <TableCell className="text-muted-foreground">
                  {log.source}
                </TableCell>
                <TableCell className="text-right text-muted-foreground">
                  {log.timestamp}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </ScrollArea>
    </div>
  );
}
