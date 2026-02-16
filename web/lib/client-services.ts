import { SchemaField, UpsertWorkspaceRequest } from "@/models/models";

export async function createWorkspaceService(
  type?: string,
  name?: string,
  settings?: Record<string, unknown>,
  schema_definition?: SchemaField[],
): Promise<string> {
  const payload: UpsertWorkspaceRequest = {
    name,
    type,
    settings,
    schema_definition,
  };

  const response = await fetch("/api/workspaces", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const error = await response
      .json()
      .catch(() => ({ error: response.statusText }));
    throw new Error(error.error || "Failed to create workspace");
  }

  const data = await response.json();
  return data.id;
}

export async function updateWorkspaceService(
  id: string,
  name?: string,
  type?: string,
  settings?: Record<string, unknown>,
  schema_definition?: SchemaField[],
): Promise<string> {
  const payload: UpsertWorkspaceRequest = {
    name,
    type,
    settings,
    schema_definition,
  };

  const response = await fetch(`/api/workspaces/${id}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const error = await response
      .json()
      .catch(() => ({ error: response.statusText }));
    throw new Error(error.error || "Failed to update workspace");
  }

  const data = await response.json();
  return data.id;
}

export async function deleteWorkspaceService(id: string): Promise<void> {
  const response = await fetch(`/api/workspaces/${id}`, {
    method: "DELETE",
  });

  if (!response.ok) {
    const error = await response
      .json()
      .catch(() => ({ error: response.statusText }));
    throw new Error(error.error || "Failed to delete workspace");
  }
}

export async function deleteAllWorkspacesService(): Promise<void> {
  const response = await fetch("/api/workspaces", {
    method: "DELETE",
  });

  if (!response.ok) {
    const error = await response
      .json()
      .catch(() => ({ error: response.statusText }));
    throw new Error(error.error || "Failed to delete all workspaces");
  }
}

export async function revokeSessionService(session_id: string): Promise<void> {
  const response = await fetch(`/api/auth/user/${session_id}`, {
    method: "DELETE",
  });
  if (!response.ok) {
    const error = await response
      .json()
      .catch(() => ({ error: response.statusText }));
    throw new Error(error.error || "Failed to revoke session");
  }
}

export async function revokeAllSessionsService(): Promise<void> {
  const response = await fetch(`/api/auth/user/sessions`, {
    method: "DELETE",
  });
  if (!response.ok) {
    const error = await response
      .json()
      .catch(() => ({ error: response.statusText }));
    throw new Error(error.error || "Failed to revoke all sessions");
  }
}
