import { getGcpAuthClient } from "@/lib/gcp-auth";
import { withAuth } from "@workos-inc/authkit-nextjs";

type ProxyMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

function headersToRecord(headers: Headers): Record<string, string> {
  const record: Record<string, string> = {};
  headers.forEach((value, key) => {
    record[key] = value;
  });
  return record;
}

export async function proxyRequest(
  req: Request,
  endpoint: string,
  method: ProxyMethod,
): Promise<Response> {
  const apiUrl = process.env.API_URL;
  if (!apiUrl) return Response.json({ error: "Config Error" }, { status: 500 });

  const { accessToken } = await withAuth();
  if (!accessToken) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  const targetUrl = `${apiUrl}${endpoint.startsWith("/") ? endpoint : `/${endpoint}`}`;
  let headers: Record<string, string> = {
    "Content-Type": "application/json",
    "X-Forwarded-Authorization": accessToken,
  };

  // INFRASTRUCTURE AUTH (GCP)
  // Matches 'internalFetch' logic: Copy ALL Google headers.
  if (process.env.NODE_ENV === "production") {
    try {
      const authClient = await getGcpAuthClient();
      const googleHeaders = await authClient.getRequestHeaders(targetUrl);

      headers = {
        ...headers,
        ...headersToRecord(googleHeaders as Headers),
      };
    } catch (error) {
      console.error("GCP Sign Error:", error);
      return Response.json({ error: "Internal Auth Error" }, { status: 500 });
    }
  }

  // EXECUTE & STREAM
  try {
    const res = await fetch(targetUrl, {
      method,
      headers,
      // CRITICAL FOR UPLOADS: Stream the request body directly
      body: method !== "GET" && method !== "DELETE" ? req.body : undefined,
      // @ts-expect-error - Required for streaming bodies in Node.js
      duplex: "half",
    });

    // 6. PREPARE RESPONSE HEADERS (STREAMING SAFETY)
    const responseHeaders = new Headers();
    for (const [k, v] of res.headers.entries()) {
      const lower = k.toLowerCase();
      if (
        lower !== "content-encoding" && // Prevents double-decoding errors
        lower !== "content-length" && // Prevents truncation if size changes
        lower !== "transfer-encoding" // Let Next.js handle the chunking
      ) {
        responseHeaders.set(k, v);
      }
    }

    // RETURN STREAM
    return new Response(res.body, {
      status: res.status,
      headers: responseHeaders,
    });
  } catch (error) {
    console.error(`Proxy Error [${method} ${endpoint}]:`, error);
    return Response.json({ error: "Bad Gateway" }, { status: 502 });
  }
}
