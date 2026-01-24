import { authkitMiddleware } from "@workos-inc/authkit-nextjs";

export default authkitMiddleware({
  redirectUri: process.env.WORKOS_REDIRECT_URI,
  middlewareAuth: {
    enabled: true,
    // SECURITY NOTE:
    // We are explicitly bypassing the authentication gate for specific public-facing routes.
    //
    // architectural_decision:
    // Webhooks are machine-to-machine communication, not user sessions. They do not carry
    // browser cookies or session tokens. If the middleware intercepts a webhook POST
    // and demands a session (307 Redirect), the webhook provider (WorkOS) will fail
    // the delivery.
    //
    // critical_implementation_detail:
    // By adding "/api/webhooks/workos" here, we allow the request to pass through the
    // middleware layer and reach the Route Handler.
    //
    // ⚠️ DEFENSE IN DEPTH WARNING:
    // Exposing this endpoint publicly removes the *session* requirement, but it MUST
    // NOT be left unsecured. You are now responsible for verifying the `WorkOS-Signature`
    // header via HMAC-SHA256 inside the route handler itself.
    unauthenticatedPaths: [
      "/",
      "/features",
      "/pricing",
      "/privacy",
      "/terms",
      "/api/webhooks/workos",
    ],
  },
});

export const config = {
  matcher: [
    /*
     * Match all request paths except for static assets.
     * * performance_optimization:
     * We generally want to exclude static files (_next/static, images, etc.) from
     * middleware invocation to reduce Edge Function usage and latency.
     * * trade_off:
     * We are currently including API routes in this matcher (by NOT excluding /api).
     * This allows AuthKit to inject session details into requests if needed, but
     * necessitates the `unauthenticatedPaths` whitelist above for public APIs.
     * An alternative approach for high-throughput APIs is to exclude `/api`
     * entirely in this regex to skip middleware overhead completely.
     */
    "/((?!_next/static|_next/image|favicon.ico|images).*)",
  ],
};
