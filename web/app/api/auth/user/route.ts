import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { withAuth } from "@workos-inc/authkit-nextjs";
import { workos } from "@/lib/workos";

const CURRENT_ORG_ID = process.env.WORKOS_ORG_ID;
const RETURN_TO_URL = process.env.NEXT_PUBLIC_WEB_URL;

export async function DELETE() {
  if (!RETURN_TO_URL) {
    console.error("Config Error: NEXT_PUBLIC_WEB_URL is missing.");
    return NextResponse.json(
      { error: "Server configuration error." },
      { status: 500 },
    );
  }

  try {
    const { user, sessionId } = await withAuth();
    if (!user || !sessionId) {
      return NextResponse.json(
        { error: "Authentication required." },
        { status: 401 },
      );
    }

    const userId = user.id;
    console.log(`Processing deletion for user: ${userId}`);

    const { data: memberships } =
      await workos.userManagement.listOrganizationMemberships({
        userId: userId,
      });

    if (CURRENT_ORG_ID) {
      const targetMembership = memberships.find(
        (m) => m.organizationId === CURRENT_ORG_ID,
      );

      if (!targetMembership) {
        console.warn(`User ${userId} is not a member of ${CURRENT_ORG_ID}`);
        return NextResponse.json(
          { error: "User is not a member of the current organization." },
          { status: 403 },
        );
      }

      if (memberships.length > 1) {
        await workos.userManagement.deleteOrganizationMembership(
          targetMembership.id,
        );
        console.log(
          `Removed membership ${targetMembership.id} for user ${userId}`,
        );
      } else {
        await workos.userManagement.deleteUser(userId);
        console.log(`User only had one org. Deleted user account: ${userId}`);
      }
    } else {
      await workos.userManagement.deleteUser(userId);
      console.log(`No Org context. Deleted user account: ${userId}`);
    }

    const cookieStore = await cookies();
    cookieStore.delete("wos-session");

    return NextResponse.json(
      {
        message: "Successfully Deleted",
        logoutUrl: RETURN_TO_URL,
      },
      { status: 200 },
    );
  } catch (error) {
    console.error("Account Deletion Error:", error);
    const errorMessage =
      error instanceof Error ? error.message : "Unknown error";

    return NextResponse.json(
      { error: `Failed to delete account: ${errorMessage}` },
      { status: 500 },
    );
  }
}
