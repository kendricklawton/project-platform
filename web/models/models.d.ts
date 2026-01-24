export type Role = "owner" | "editor" | "reader";

export type SubscriptionTier = "hobby" | "pro" | "pro_plus" | "ultra";

export type SubscriptionStatus =
  | "active"
  | "canceled"
  | "past_due"
  | "incomplete"
  | "trialing";

export type FunctionType = "llm_prompt" | "formula" | "webhook" | "script";

export type TriggerEvent = "manual" | "on_create" | "on_update";

export type IsoDateString = string;

export type SchemaFieldType =
  | "text"
  | "number"
  | "boolean"
  | "date"
  | "select"
  | "email"
  | "url"
  | "json";

export type SchemaField = {
  key: string;
  label: string;
  type: SchemaFieldType;
  required?: boolean;
  defaultValue?: string | number | boolean | null;
  placeholder?: string;
  description?: string;
  options?: { label: string; value: string; color?: string }[];
  validation?: Record<string, unknown>;
};

export type Workspace<TSettings = Record<string, unknown>> = {
  id: string;
  role: Role;
  name: string;
  description?: string;
  type: string;
  schema_definition: SchemaField[];
  settings: TSettings;
  resource_count: number;
  function_count: number;
  created_at: IsoDateString;
  updated_at: IsoDateString;
};

export type WorkspaceResource<TData = Record<string, unknown>> = {
  id: string;
  workspace_id: string;
  data: TData;
  created_at: IsoDateString;
  updated_at: IsoDateString;
};

export type WorkspaceFunction = {
  id: string;
  workspace_id: string;
  name: string;
  type: FunctionType;

  /** Example: {"prompt": "Summarize {{data.notes}}"} */
  definition: Record<string, unknown>;

  trigger_event: TriggerEvent;

  created_at: IsoDateString;
  updated_at: IsoDateString;
};

export type UpsertWorkosUserRequest = {
  id: string;
  created_at: IsoDateString;
  updated_at: IsoDateString;
};

export type UpsertWorkspaceRequest = {
  name?: string;
  type?: string;
  settings?: Record<string, unknown>;
  schema_definition?: SchemaField[];
};

export type UpsertWorkspaceResourceRequest<TData = Record<string, unknown>> = {
  workspace_id: string;
  data: TData;
};

export type UpsertWorkspaceFunctionRequest = {
  workspace_id: string;
  name: string;
  type: FunctionType;
  definition: Record<string, unknown>;
  trigger_event?: TriggerEvent;
};

export type Log = {
  id: string;
  method: string;
  path: string;
  status: number;
  source: string;
  timestamp: string;
  body: string; // JSON string
};

type InfoState = {
  message: string;
  duration?: number;
};
