"use client";

import React from "react";
import { AuthKitProvider } from "@workos-inc/authkit-nextjs/components";

type ProviderWrapperProps = {
  children: React.ReactNode;
};

export default function ProviderWrapper({ children }: ProviderWrapperProps) {
  return <AuthKitProvider>{children}</AuthKitProvider>;
}
