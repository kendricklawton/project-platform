import { internalFetch } from "./base";
import { withAuth } from "@workos-inc/authkit-nextjs";

/**
 * IDENTITY LAYER (WorkOS Implementation)
 *
 * This wrapper is the only place in our codebase that is coupled to WorkOS.
 * It is responsible for:
 * 1. Interacting with the WorkOS SDK
 * 2. Extracting the user context
 * 3. Delegating the network request to the base `internalFetch`
 *
 * FUTURE PROOFING:
 * If we need to support a new provider (e.g. `fetchWithAuth0User`),
 * or a system user (e.g. `fetchAsAdmin`), we just create a sibling function
 * to this one. The core networking logic remains untouched.
 */
export async function fetchWithWorkosUser<T>(endpoint: string) {
  const { accessToken } = await withAuth();

  if (!accessToken) {
    console.warn("User not authenticated");
    return null;
  }

  return internalFetch<T>(endpoint, { token: accessToken });
}
