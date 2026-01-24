import { NextResponse } from "next/server";
import { getSignInUrl } from "@workos-inc/authkit-nextjs";

export async function GET() {
  try {
    const signInUrl = await getSignInUrl();
    return NextResponse.redirect(signInUrl);
  } catch (error) {
    console.error("Redirect to Sign-In Error:", error);

    return NextResponse.json(
      { error: "Could not generate sign-in URL" },
      { status: 500 },
    );
  }
}
