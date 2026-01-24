import { WorkosUser } from "@/lib/workos";

interface UserWithCustomAttributes extends WorkosUser {
  reloadUserInfo?: {
    customAttributes: string;
  };
}

type SubscriptionType = "Hobby" | "Pro" | "Pro Plus" | "Ultra";

// --- Constants ---

export const hobbyWorkspaceLimit =
  process.env.NEXT_PUBLIC_HOBBY_WORKSPACE_LIMIT;
export const hobbyResourceLimit = process.env.NEXT_PUBLIC_HOBBY_TRADES_LIMIT;
export const hobbyFunctionLimit = process.env.NEXT_PUBLIC_HOBBY_FUNCTION_LIMIT;
export const hobbyTokenAllotment =
  process.env.NEXT_PUBLIC_HOBBY_TOKEN_ALLOTMENT;

export const proWorkspaceLimit = process.env.NEXT_PUBLIC_PRO_WORKSPACE_LIMIT;
export const proResourceLimit = process.env.NEXT_PUBLIC_PRO_RESOURCE_LIMIT;
export const proFunctionLimit = process.env.NEXT_PUBLIC_PRO_FUNCTION_LIMIT;
export const proTokenAllotment = process.env.NEXT_PUBLIC_PRO_TOKEN_ALLOTMENT;

export const proPlusWorkspaceLimit =
  process.env.NEXT_PUBLIC_PRO_PLUS_WORKSPACE_LIMIT;
export const proPlusResourceLimit =
  process.env.NEXT_PUBLIC_PRO_PLUS_RESOURCE_LIMIT;
export const proPlusFunctionLimit =
  process.env.NEXT_PUBLIC_PRO_PLUS_FUNCTION_LIMIT;
export const proPlusTokenAllotment =
  process.env.NEXT_PUBLIC_PRO_PLUS_TOKEN_ALLOTMENT;

export const ultraWorkspaceLimit =
  process.env.NEXT_PUBLIC_ULTRA_WORKSPACE_LIMIT;
export const ultraResourceLimit = process.env.NEXT_PUBLIC_ULTRA_RESOURCE_LIMIT;
export const ultraFunctionLimit = process.env.NEXT_PUBLIC_ULTRA_FUNCTION_LIMIT;
export const ultraTokenAllotment =
  process.env.NEXT_PUBLIC_ULTRA_TOKEN_ALLOTMENT;

// --- Helpers ---

export const getUserSubscriptionType = (
  user: WorkosUser | null,
): SubscriptionType => {
  if (!user) {
    return "Hobby";
  }

  const userInfo = user as UserWithCustomAttributes;

  try {
    const customAttributes = JSON.parse(
      userInfo.reloadUserInfo?.customAttributes || "{}",
    );

    switch (customAttributes.subscription) {
      case "hobby":
        console.log("Hobby");
        return "Hobby";
      case "pro":
        console.log("Pro");
        return "Pro";
      case "pro_plus":
        console.log("Pro Plus");
        return "Pro Plus";
      case "ultra":
        console.log("Ultra");
        return "Ultra";
      default:
        console.log("Default");
        return "Hobby";
    }
  } catch (error) {
    console.error("Error parsing customAttributes:", error);
    return "Hobby";
  }
};

export const isSubscriptionLimitReached = (
  currentEntity: "functions" | "workspace" | "resource" | "tokens",
  currentEntityAmount: number,
  user?: WorkosUser | null,
): boolean => {
  if (!user) {
    return true;
  }

  const subscriptionType = getUserSubscriptionType(user);
  let limit: string | undefined = "0";

  // Logic: Select the correct limit based on Subscription AND Entity
  switch (subscriptionType) {
    case "Ultra":
      if (currentEntity === "workspace") limit = ultraWorkspaceLimit;
      if (currentEntity === "resource") limit = ultraResourceLimit;
      if (currentEntity === "functions") limit = ultraFunctionLimit;
      if (currentEntity === "tokens") limit = ultraTokenAllotment;
      break;
    case "Pro Plus":
      if (currentEntity === "workspace") limit = proWorkspaceLimit;
      if (currentEntity === "resource") limit = proResourceLimit;
      if (currentEntity === "functions") limit = proFunctionLimit;
      if (currentEntity === "tokens") limit = proTokenAllotment;
      break;
    case "Pro":
      if (currentEntity === "workspace") limit = proWorkspaceLimit;
      if (currentEntity === "resource") limit = proResourceLimit;
      if (currentEntity === "functions") limit = proFunctionLimit;
      if (currentEntity === "tokens") limit = proTokenAllotment;
      break;
    case "Hobby":
    default:
      if (currentEntity === "workspace") limit = hobbyWorkspaceLimit;
      if (currentEntity === "resource") limit = hobbyResourceLimit;
      if (currentEntity === "functions") limit = hobbyFunctionLimit;
      if (currentEntity === "tokens") limit = hobbyTokenAllotment;
      break;
  }

  const numericLimit = Number(limit || 0);
  return currentEntityAmount >= numericLimit;
};
