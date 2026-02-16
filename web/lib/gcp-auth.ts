import { JWT, IdTokenClient, AuthClient } from "google-auth-library";

let cachedClient: AuthClient | null = null;

function getGcpCredentials() {
  const encodedKey = process.env.GCP_BASE_64_JSON;
  if (!encodedKey) {
    throw new Error("GCP_BASE_64_JSON env var is not set.");
  }
  const decodedKey = Buffer.from(encodedKey, "base64").toString("utf-8");
  return JSON.parse(decodedKey);
}

export async function getGcpAuthClient(): Promise<AuthClient> {
  if (cachedClient) {
    return cachedClient;
  }

  const targetAudience = process.env.API_URL;
  if (!targetAudience) {
    throw new Error("API_URL not set.");
  }

  const credentials = getGcpCredentials();

  const jwt = new JWT({
    email: credentials.client_email,
    key: credentials.private_key,
    keyId: credentials.private_key_id,
  });

  cachedClient = new IdTokenClient({
    targetAudience: targetAudience,
    idTokenProvider: jwt,
  });

  return cachedClient;
}
