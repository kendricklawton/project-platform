import { create, StateCreator } from "zustand";
import { devtools } from "zustand/middleware";
import { Log, InfoState, Workspace } from "@/models/models";

// --- Log Slice ---

type LogSlice = {
  logs: Log[];
  addLog: (log: Log) => void;
  clearLogs: () => void;
};

const createLogSlice: StateCreator<
  StoreState,
  [["zustand/devtools", never]],
  [],
  LogSlice
> = (set) => ({
  logs: [
    {
      id: "1",
      method: "POST",
      path: "/hooks/stripe",
      status: 200,
      source: "Stripe",
      timestamp: "10:42:05",
      body: "{}",
    },
    {
      id: "2",
      method: "POST",
      path: "/hooks/github",
      status: 500,
      source: "GitHub",
      timestamp: "10:41:55",
      body: "{}",
    },
  ],
  addLog: (log) =>
    set((state) => ({ logs: [log, ...state.logs] }), false, "addLog"),
  clearLogs: () => set({ logs: [] }, false, "clearLogs"),
});

// --- Info Slice ---

type InfoSlice = {
  info: InfoState | null;
  setInfo: (info: InfoState | null) => void;
};

const createInfoSlice: StateCreator<
  StoreState,
  [["zustand/devtools", never]],
  [],
  InfoSlice
> = (set) => ({
  info: null,
  setInfo: (info) => set({ info }, false, "setInfo"),
});

// --- Workspace Slice ---

type WorkspaceSlice = {
  workspaces: Workspace[];
  addWorkspaces: (workspaces: Workspace[]) => void;
  setWorkspaces: (workspaces: Workspace[]) => void;
  updateWorkspace: (workspace: Workspace) => void;
};

const createWorkspaceSlice: StateCreator<
  StoreState,
  [["zustand/devtools", never]],
  [],
  WorkspaceSlice
> = (set) => ({
  workspaces: [],

  setWorkspaces: (workspaces) => set({ workspaces }, false, "setWorkspaces"),

  addWorkspaces: (newWorkspace) =>
    set(
      (state) => {
        if (!Array.isArray(newWorkspace)) {
          console.warn(
            "addWorkspaces expects an array, but received:",
            newWorkspace,
          );
          return { workspaces: state.workspaces };
        }

        const existingIds = new Set(state.workspaces.map((w) => w.id));
        const uniqueNewWorkspace = newWorkspace.filter(
          (w) => !existingIds.has(w.id),
        );

        return { workspaces: [...uniqueNewWorkspace, ...state.workspaces] };
      },
      false,
      "addWorkspaces",
    ),

  updateWorkspace: (updatedWorkspace) =>
    set(
      (state) => ({
        workspaces: state.workspaces.map((w) =>
          w.id === updatedWorkspace.id ? { ...w, ...updatedWorkspace } : w,
        ),
      }),
      false,
      "updateWorkspace",
    ),
});

// --- Loading Slice ---

type LoadingSlice = {
  isLoading: boolean;
  setIsLoading: (isLoading: boolean) => void;
};

const createLoadingSlice: StateCreator<
  StoreState,
  [["zustand/devtools", never]],
  [],
  LoadingSlice
> = (set) => ({
  isLoading: false,
  setIsLoading: (isLoading) => set({ isLoading }, false, "setIsLoading"),
});

// --- Unified Store Creation ---

type StoreState = InfoSlice &
  WorkspaceSlice &
  LoadingSlice &
  LogSlice & { clearAppData: () => void };

export const useStore = create<StoreState>()(
  devtools((...a) => ({
    ...createInfoSlice(...a),
    ...createWorkspaceSlice(...a),
    ...createLoadingSlice(...a),
    ...createLogSlice(...a),

    clearAppData: () => {
      const [set] = a;
      set(
        { workspaces: [], info: null, isLoading: false, logs: [] },
        false,
        "clearAppData",
      );
    },
  })),
);
