import { getGcpAuthClient } from "@/lib/gcp-auth";

export type FetchOptions = {
  token?: string;
};

function headersToRecord(headers: Headers): Record<string, string> {
  const record: Record<string, string> = {};
  headers.forEach((value, key) => {
    record[key] = value;
  });
  return record;
}

export async function internalFetch<T>(
  endpoint: string,
  options: FetchOptions = {},
): Promise<T | null> {
  const apiUrl = process.env.API_URL;
  if (!apiUrl) return null;

  const url = `${apiUrl}${endpoint.startsWith("/") ? endpoint : `/${endpoint}`}`;

  let headers: Record<string, string> = {
    "Content-Type": "application/json",
  };

  if (options.token) {
    headers["X-Forwarded-Authorization"] = options.token;
  }

  if (process.env.NODE_ENV === "production") {
    try {
      const authClient = await getGcpAuthClient();
      const googleHeaders = await authClient.getRequestHeaders(url);

      headers = {
        ...headers,
        ...headersToRecord(googleHeaders as Headers),
      };
    } catch (error) {
      console.error("GCP Auth Failed", error);
      return null;
    }
  }

  try {
    const response = await fetch(url, { headers });

    if (!response.ok) {
      throw new Error(`HTTP Error ${response.status}`);
    }

    return (await response.json()) as T;
  } catch (error) {
    console.error("Fetch Error:", error);
    return null;
  }
}
