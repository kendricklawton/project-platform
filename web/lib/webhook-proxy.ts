import { getGcpAuthClient } from "@/lib/gcp-auth";

/**
 * webhook-proxy: Securely relays verified system events to the Arch-Infra engine.
 */
export async function forwardWebhookRequest(
  url: string,
  method: "POST" | "PATCH" | "DELETE",
  body?: unknown,
) {
  const requestBody = body ? JSON.stringify(body) : undefined;
  const secret = process.env.INTERNAL_API_SECRET;

  if (!secret) throw new Error("Internal API Secret missing");

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "X-Internal-Api-Key": secret,
  };

  const response = await fetch(url, { method, body: requestBody, headers });
  return { status: response.status, ok: response.ok };
}
