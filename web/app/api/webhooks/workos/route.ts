import { NextRequest, NextResponse } from "next/server";
import { workos, WorkosUser } from "@/lib/workos";
import { forwardWebhookRequest } from "@/lib/webhook-proxy";

export async function POST(request: NextRequest) {
  const webhookSecret = process.env.WORKOS_WEBHOOK_SECRET;
  const apiUrl = process.env.API_URL;

  if (!webhookSecret || !apiUrl) {
    return NextResponse.json({ error: "Config Error" }, { status: 500 });
  }

  // 1. Verify WorkOS Signature
  const payload = await request.json();
  const sigHeader = request.headers.get("workos-signature") || "";

  let event;
  try {
    event = await workos.webhooks.constructEvent({
      payload,
      sigHeader,
      secret: webhookSecret,
    });
  } catch (err) {
    return NextResponse.json({ error: "Invalid Signature" }, { status: 400 });
  }

  // 2. Map Event to Arch-Infra Actions
  const eventType = event.event;
  const userData = event.data as WorkosUser;

  // Prepare the standardized User object for your Go backend
  const archUser = {
    id: userData.id,
    email: userData.email,
    created_at: userData.createdAt,
  };

  let targetUrl = `${apiUrl}/user`;
  let method: "POST" | "PATCH" | "DELETE" = "POST";

  switch (eventType) {
    case "user.created":
      method = "POST";
      break;
    case "user.updated":
      method = "PATCH";
      targetUrl = `${apiUrl}/user/${userData.id}`;
      break;
    case "user.deleted":
      method = "DELETE";
      targetUrl = `${apiUrl}/user/${userData.id}`;
      break;
    default:
      return NextResponse.json({ skipped: true });
  }

  // 3. Relay to your Go Arch Engine
  try {
    const result = await forwardWebhookRequest(targetUrl, method, archUser);
    return NextResponse.json({ received: true, relayed: result.ok });
  } catch (error) {
    console.error("Relay failed:", error);
    return NextResponse.json({ error: "Downstream failure" }, { status: 502 });
  }
}
