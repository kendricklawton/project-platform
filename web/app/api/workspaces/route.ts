import { NextRequest, NextResponse } from "next/server";
import { proxyRequest } from "@/lib/api-proxy";

export async function DELETE(request: NextRequest) {
  if (process.env.NODE_ENV !== "development") {
    return NextResponse.json(
      { error: "Bulk delete is not allowed in production" },
      { status: 403 },
    );
  }
  return proxyRequest(request, "/workspaces", "DELETE");
}

export async function POST(request: NextRequest) {
  return proxyRequest(request, "/workspaces", "POST");
}
