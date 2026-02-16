import { handleAuth } from "@workos-inc/authkit-nextjs";
import { workos } from "@/lib/workos";

export const GET = handleAuth({
  returnPathname: process.env.RETURN_PATHNAME,
  onSuccess: async ({ user }) => {
    try {
      if (!user.metadata?.subscription_tier) {
        await workos.userManagement.updateUser({
          userId: user.id,
          metadata: {
            subscription_tier: "hobby",
          },
        });
      }

      if (process.env.WORKOS_ORG_ID) {
        await workos.userManagement.createOrganizationMembership({
          userId: user.id,
          organizationId: process.env.WORKOS_ORG_ID,
        });
      }
    } catch (error) {
      console.error("Error setting up new user in WorkOS:", error);
    }
  },
});
