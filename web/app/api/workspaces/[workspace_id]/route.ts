import { NextRequest } from "next/server";
import { proxyRequest } from "@/lib/api-proxy";

type RouteParams = {
  params: Promise<{ id: string }>;
};

export async function DELETE(req: NextRequest, { params }: RouteParams) {
  const { id } = await params;
  return proxyRequest(req, `/workspaces/${id}`, "DELETE");
}

export async function PATCH(req: NextRequest, { params }: RouteParams) {
  const { id } = await params;
  return proxyRequest(req, `/workspaces/${id}`, "PATCH");
}
