import { WorkOS } from "@workos-inc/node";
export type { User as WorkosUser } from "@workos-inc/node";
export const workos = new WorkOS(process.env.WORKOS_API_KEY || "");
