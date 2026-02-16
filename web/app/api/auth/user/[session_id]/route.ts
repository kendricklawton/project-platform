import { workos } from "@/lib/workos";
import { NextResponse, NextRequest } from "next/server";

type RouteParams = {
  params: Promise<{ session_id: string }>;
};

export async function DELETE(request: NextRequest, { params }: RouteParams) {
  const { session_id } = await params;

  try {
    await workos.userManagement.revokeSession({
      sessionId: session_id,
    });

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("Revoke Session Error:", error);

    if (error instanceof Error) {
      return NextResponse.json(
        { error: `API Error: ${error.message}` },
        { status: 500 },
      );
    }

    return NextResponse.json(
      { error: "An unexpected error occurred during account operation." },
      { status: 500 },
    );
  }
}
